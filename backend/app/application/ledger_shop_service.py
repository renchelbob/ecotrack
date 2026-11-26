from collections import Counter
from datetime import UTC, datetime, time, timedelta, timezone
from secrets import token_hex
from uuid import UUID

import asyncpg

from app.api.errors import CatalogException
from app.api.v1.auth_models import UserProfileResponse
from app.api.v1.ledger_shop_models import CartLineInput, ShopOrderDetail, ShopOrderListResponse
from app.application.activity_service import assert_activity_access
from app.application.social_service import MOSCOW_OFFSET
from app.infrastructure.db.repositories import badge_repo, ledger_shop_repo, social_repo, user_repo
from app.infrastructure.db.transactions import retry_deadlock

DEMO_COUPON_LIFETIME = timedelta(days=30)
DONATION_GRAMS_PER_ITEM = 2000


async def shop_user(connection: asyncpg.Connection, user_id: UUID) -> asyncpg.Record:
    user = await ledger_shop_repo.load_shop_user(connection, user_id)
    assert_activity_access(user)
    return user


async def list_orders(
    connection: asyncpg.Connection, user_id: UUID, limit: int, offset: int
) -> ShopOrderListResponse:
    async with connection.transaction(isolation="repeatable_read", readonly=True):
        user = await shop_user(connection, user_id)
        total = await connection.fetchval(
            "SELECT count(*) FROM shop_orders WHERE user_id = $1", user_id
        )
        if not isinstance(total, int):
            raise CatalogException("INTERNAL_SERVER_ERROR")
        orders = await connection.fetch(
            """
            SELECT id, idempotency_key, status, total_points, item_count, created_at
            FROM shop_orders WHERE user_id = $1
            ORDER BY created_at DESC, id DESC LIMIT $2 OFFSET $3
            """,
            user_id,
            limit,
            offset,
        )
        lines = await ledger_shop_repo.load_order_lines(connection, [row["id"] for row in orders])
        return ShopOrderListResponse(
            total_count=total,
            orders=[
                ledger_shop_repo.order_detail(row, lines[row["id"]], user["points_balance"])
                for row in orders
            ],
        )


async def _existing_order(
    connection: asyncpg.Connection, user: asyncpg.Record, key: UUID, quantities: Counter[UUID]
) -> ShopOrderDetail | None:
    row = await connection.fetchrow(
        """
        SELECT id, user_id, idempotency_key, status, total_points, item_count, created_at
        FROM shop_orders WHERE idempotency_key = $1
        """,
        key,
    )
    if row is None:
        in_ledger = await connection.fetchval(
            "SELECT EXISTS(SELECT 1 FROM point_ledger WHERE idempotency_key = $1)", key
        )
        if in_ledger:
            raise CatalogException("IDEMPOTENCY_KEY_PAYLOAD_MISMATCH")
        return None
    if row["user_id"] != user["id"]:
        raise CatalogException("IDEMPOTENCY_KEY_PAYLOAD_MISMATCH")
    lines = (await ledger_shop_repo.load_order_lines(connection, [row["id"]]))[row["id"]]
    purchased: Counter[UUID] = Counter()
    for line in lines:
        purchased[line.shop_item_id] += line.quantity
    if purchased != quantities:
        raise CatalogException("IDEMPOTENCY_KEY_PAYLOAD_MISMATCH")
    return ledger_shop_repo.order_detail(row, lines, user["points_balance"])


def _check_cart(
    items: dict[UUID, asyncpg.Record],
    quantities: Counter[UUID],
    bought_today: dict[UUID, int],
    owned: set[str],
) -> tuple[int, set[str]]:
    total = 0
    accessories: set[str] = set()
    for item_id, quantity in quantities.items():
        item = items[item_id]
        if not item["is_active"]:
            raise CatalogException("SHOP_ITEM_INACTIVE")
        if item["stock_quantity"] is not None and item["stock_quantity"] < quantity:
            raise CatalogException("SHOP_ITEM_OUT_OF_STOCK")
        if item["item_type"] == "mascot_accessory":
            code = item["accessory_code"]
            if code is None:
                raise CatalogException("SHOP_ITEM_INACTIVE")
            if quantity > 1 or code in owned or code in accessories:
                raise CatalogException("SHOP_ACCESSORY_ALREADY_OWNED")
            accessories.add(code)
        if bought_today.get(item_id, 0) + quantity > item["max_per_user_per_day"]:
            raise CatalogException("SHOP_DAILY_USER_LIMIT_EXCEEDED")
        total += item["price_points"] * quantity
    return total, accessories


async def _issue_items(
    connection: asyncpg.Connection,
    order: asyncpg.Record,
    cart: list[CartLineInput],
    items: dict[UUID, asyncpg.Record],
    quantities: Counter[UUID],
) -> None:
    await connection.executemany(
        """
        UPDATE shop_items SET stock_quantity = stock_quantity - $2
        WHERE id = $1 AND stock_quantity IS NOT NULL
        """,
        quantities.items(),
    )
    lines: list[tuple[UUID, UUID, int, int, str, str, datetime | None]] = []
    for line in cart:
        item = items[line.shop_item_id]
        code = f"ECO-{token_hex(12).upper()}"
        partner_item = item["item_type"] in ("partner_qr", "partner_coupon")
        expiry = order["created_at"] + DEMO_COUPON_LIFETIME if partner_item else None
        lines.append(
            (
                order["id"],
                line.shop_item_id,
                line.quantity,
                item["price_points"],
                code,
                f"ecotrack://demo-coupon/{code}",
                expiry,
            )
        )
    await connection.executemany(
        """
        INSERT INTO shop_order_items (
            order_id, shop_item_id, quantity, unit_price_points, coupon_code, qr_payload, expires_at
        ) VALUES ($1, $2, $3, $4, $5, $6, $7)
        """,
        lines,
    )


async def _fulfill_virtual_items(
    connection: asyncpg.Connection,
    user_id: UUID,
    freezes: int,
    accessories: set[str],
    donation_grams: int,
    purchased_at: datetime,
) -> None:
    if freezes:
        await connection.execute(
            """
            UPDATE users SET streak_freeze_count = streak_freeze_count + $2, updated_at = now()
            WHERE id = $1
            """,
            user_id,
            freezes,
        )
    if accessories:
        await connection.executemany(
            "INSERT INTO user_mascot_inventory (user_id, accessory_code) VALUES ($1, $2)",
            [(user_id, code) for code in sorted(accessories)],
        )
    if donation_grams:
        await social_repo.update_forest(
            connection, user_id, purchased_at.astimezone(MOSCOW_OFFSET).date(), grams=donation_grams
        )
        await badge_repo.award_badges(connection, user_id)


async def _checkout(
    connection: asyncpg.Connection, user_id: UUID, key: UUID, cart: list[CartLineInput]
) -> ShopOrderDetail:
    quantities: Counter[UUID] = Counter()
    for line in cart:
        quantities[line.shop_item_id] += line.quantity
    await user_repo.lock_user(connection, user_id)
    user = await shop_user(connection, user_id)
    # Use the same lock as step sync for the globally unique ledger key.
    await connection.execute("SELECT pg_advisory_xact_lock(hashtextextended($1, 1))", str(key))
    existing_order = await _existing_order(connection, user, key, quantities)
    if existing_order is not None:
        return existing_order

    item_ids = list(quantities)
    items = await ledger_shop_repo.lock_items(connection, item_ids)
    if len(items) != len(item_ids):
        raise CatalogException("SHOP_ITEM_NOT_FOUND")
    purchased_at = datetime.now(UTC)
    local_time = timezone(timedelta(minutes=user["timezone_offset"]))
    local_day = purchased_at.astimezone(local_time).date()
    start = datetime.combine(local_day, time.min, local_time)
    bought_today = await ledger_shop_repo.daily_quantities(
        connection, user_id, item_ids, start, start + timedelta(days=1)
    )
    owned = await ledger_shop_repo.inventory_codes(connection, user_id)
    total, accessories = _check_cart(items, quantities, bought_today, owned)
    if total > user["points_balance"]:
        raise CatalogException("INSUFFICIENT_POINTS_BALANCE")

    count_by_type: Counter[str] = Counter()
    for item_id, quantity in quantities.items():
        count_by_type[items[item_id]["item_type"]] += quantity
    donation = DONATION_GRAMS_PER_ITEM * count_by_type["virtual_eco_donation"]
    order = await ledger_shop_repo.insert_order(
        connection, user_id, key, total, quantities.total(), donation, purchased_at
    )
    await _issue_items(connection, order, cart, items, quantities)
    await _fulfill_virtual_items(
        connection,
        user_id,
        count_by_type["virtual_streak_freeze"],
        accessories,
        donation,
        purchased_at,
    )
    order_lines = (await ledger_shop_repo.load_order_lines(connection, [order["id"]]))[order["id"]]
    balance = await user_repo.load_points_balance(connection, user_id)
    return ledger_shop_repo.order_detail(order, order_lines, balance)


@retry_deadlock
async def checkout(
    connection: asyncpg.Connection, user_id: UUID, key: UUID, cart: list[CartLineInput]
) -> ShopOrderDetail:
    async with connection.transaction():
        return await _checkout(connection, user_id, key, cart)


async def activate_freeze(connection: asyncpg.Connection, user_id: UUID) -> UserProfileResponse:
    async with connection.transaction():
        await user_repo.lock_user(connection, user_id)
        user = await shop_user(connection, user_id)
        if user["streak_freeze_count"] <= 0:
            raise CatalogException("STREAK_FREEZE_NONE_AVAILABLE")
        local_now = datetime.now(UTC) + timedelta(minutes=user["timezone_offset"])
        yesterday = local_now.date() - timedelta(days=1)
        last_active = user["last_active_local_date"]
        if last_active is not None and last_active >= yesterday:
            raise CatalogException("STREAK_FREEZE_NOT_NEEDED")
        await connection.execute(
            """
            UPDATE users SET streak_freeze_count = streak_freeze_count - 1,
                             last_active_local_date = $2, updated_at = now()
            WHERE id = $1
            """,
            user_id,
            yesterday,
        )
        return await user_repo.load_profile(connection, user_id)
