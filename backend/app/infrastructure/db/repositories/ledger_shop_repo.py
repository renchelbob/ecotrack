from collections import defaultdict
from datetime import datetime
from uuid import UUID

import asyncpg

from app.api.errors import CatalogException
from app.api.v1.ledger_shop_models import (
    PointLedgerItem,
    PointLedgerListResponse,
    ShopCatalogResponse,
    ShopOrderDetail,
    ShopOrderLineItem,
)

SHOP_BANNER = "Все партнёры и купоны в магазине являются вымышленными (демонстрационный режим)."  # noqa: RUF001


async def load_shop_user(connection: asyncpg.Connection, user_id: UUID) -> asyncpg.Record:
    row = await connection.fetchrow(
        """
        SELECT id, points_balance, lifetime_points_earned, streak_freeze_count,
               last_active_local_date, is_152fz_consent_active, requires_formal_phone,
               COALESCE((
                   SELECT timezone_offset_minutes FROM daily_step_summaries
                   WHERE user_id = $1 ORDER BY activity_date DESC LIMIT 1
               ), 180) AS timezone_offset
        FROM users WHERE id = $1
        """,
        user_id,
    )
    if row is None:
        raise CatalogException("AUTH_TOKEN_INVALID")
    return row


async def load_ledger(
    connection: asyncpg.Connection, user: asyncpg.Record, limit: int, offset: int
) -> PointLedgerListResponse:
    total = await connection.fetchval(
        "SELECT count(*) FROM point_ledger WHERE user_id = $1", user["id"]
    )
    if not isinstance(total, int):
        raise CatalogException("INTERNAL_SERVER_ERROR")
    rows = await connection.fetch(
        """
        SELECT id, idempotency_key, operation_type, points_delta, co2_delta_grams,
               reference_entity_type, reference_entity_id, description, created_at
        FROM point_ledger WHERE user_id = $1
        ORDER BY created_at DESC, id DESC LIMIT $2 OFFSET $3
        """,
        user["id"],
        limit,
        offset,
    )
    return PointLedgerListResponse(
        points_balance=user["points_balance"],
        lifetime_points_earned=user["lifetime_points_earned"],
        total_count=total,
        items=[PointLedgerItem.model_validate(dict(row)) for row in rows],
    )


async def load_catalog(
    connection: asyncpg.Connection,
    category: str | None,
    item_type: str | None,
    search: str | None,
) -> ShopCatalogResponse:
    # The category list covers all active items, independently of the active filters.
    rows = await connection.fetch(
        """
        WITH catalog AS (
            SELECT i.id, i.sku, i.item_type, i.title, i.subtitle, i.description, i.price_points,
                   i.stock_quantity, i.max_per_user_per_day, i.accessory_code, i.image_asset_key,
                   i.sort_order,
                   CASE i.item_type
                       WHEN 'mascot_accessory' THEN 'Гардероб зверька'
                       WHEN 'virtual_streak_freeze' THEN 'Виртуальные бонусы'
                       WHEN 'virtual_eco_donation' THEN 'Виртуальные бонусы'
                       ELSE p.category_name
                   END AS category,
                   CASE WHEN p.id IS NOT NULL THEN jsonb_build_object(
                       'id', p.id, 'slug', p.slug, 'name', p.name, 'category_name', p.category_name,
                       'logo_asset_key', p.logo_asset_key,
                       'is_fictional_disclaimer', p.is_fictional_disclaimer
                   ) END AS partner
            FROM shop_items i LEFT JOIN shop_partners p ON p.id = i.partner_id
            WHERE i.is_active AND (p.id IS NULL OR p.is_active)
        )
        SELECT *, ($1::text IS NULL OR lower(category) = lower($1))
               AND ($2::shop_item_type IS NULL OR item_type = $2)
               AND ($3::text IS NULL OR strpos(lower(concat_ws(' ', title, subtitle, description,
                                                              partner->>'name')), lower($3)) > 0)
               AS matches
        FROM catalog ORDER BY sort_order, title, id
        """,
        category,
        item_type,
        search,
    )
    items: list[dict[str, object]] = []
    categories: dict[str, None] = {}
    for row in rows:
        value = dict(row)
        group = value.pop("category")
        if group:
            categories[group] = None
        if value.pop("matches"):
            value.pop("sort_order")
            items.append(value)
    return ShopCatalogResponse.model_validate(
        {"fictional_shop_banner_ru": SHOP_BANNER, "categories": list(categories), "items": items}
    )


async def load_order_lines(
    connection: asyncpg.Connection, order_ids: list[UUID]
) -> dict[UUID, list[ShopOrderLineItem]]:
    rows = await connection.fetch(
        """
        SELECT oi.order_id, oi.id, oi.shop_item_id, i.title, i.item_type, oi.quantity,
               oi.unit_price_points, oi.line_total_points, oi.coupon_code, oi.qr_payload,
               oi.expires_at, oi.redeemed_at
        FROM shop_order_items oi JOIN shop_items i ON i.id = oi.shop_item_id
        WHERE oi.order_id = ANY($1::uuid[]) ORDER BY oi.order_id, oi.id
        """,
        order_ids,
    )
    result: dict[UUID, list[ShopOrderLineItem]] = defaultdict(list)
    for row in rows:
        value = dict(row)
        result[value.pop("order_id")].append(ShopOrderLineItem.model_validate(value))
    return result


def order_detail(
    row: asyncpg.Record, line_items: list[ShopOrderLineItem], balance: int
) -> ShopOrderDetail:
    return ShopOrderDetail(
        id=row["id"],
        idempotency_key=row["idempotency_key"],
        status=row["status"],
        total_points=row["total_points"],
        remaining_points_balance=balance,
        item_count=row["item_count"],
        line_items=line_items,
        created_at=row["created_at"],
    )


async def lock_items(
    connection: asyncpg.Connection, item_ids: list[UUID]
) -> dict[UUID, asyncpg.Record]:
    rows = await connection.fetch(
        """
        SELECT i.id, i.item_type, i.price_points, i.stock_quantity, i.max_per_user_per_day,
               i.accessory_code, i.is_active AND COALESCE(p.is_active, true) AS is_active
        FROM shop_items i LEFT JOIN shop_partners p ON p.id = i.partner_id
        WHERE i.id = ANY($1::uuid[]) ORDER BY i.id FOR UPDATE OF i
        """,
        item_ids,
    )
    return {row["id"]: row for row in rows}


async def daily_quantities(
    connection: asyncpg.Connection,
    user_id: UUID,
    item_ids: list[UUID],
    start: datetime,
    end: datetime,
) -> dict[UUID, int]:
    rows = await connection.fetch(
        """
        SELECT oi.shop_item_id, sum(oi.quantity) AS quantity
        FROM shop_order_items oi JOIN shop_orders o ON o.id = oi.order_id
        WHERE o.user_id = $1 AND oi.shop_item_id = ANY($2::uuid[])
          AND o.created_at >= $3 AND o.created_at < $4 AND o.status IN ('completed', 'redeemed')
        GROUP BY oi.shop_item_id
        """,
        user_id,
        item_ids,
        start,
        end,
    )
    return {row["shop_item_id"]: row["quantity"] for row in rows}


async def inventory_codes(connection: asyncpg.Connection, user_id: UUID) -> set[str]:
    rows = await connection.fetch(
        "SELECT accessory_code FROM user_mascot_inventory WHERE user_id = $1", user_id
    )
    return {row["accessory_code"] for row in rows}


async def insert_order(
    connection: asyncpg.Connection,
    user_id: UUID,
    key: UUID,
    total: int,
    quantity: int,
    donation_grams: int,
    purchased_at: datetime,
) -> asyncpg.Record:
    row = await connection.fetchrow(
        """
        WITH order_id AS (SELECT uuid_generate_v7() AS value),
        debit AS (
            INSERT INTO point_ledger (
                user_id, idempotency_key, operation_type, points_delta, co2_delta_grams,
                reference_entity_type, reference_entity_id, description, created_at
            )
            SELECT $1, $2, 'shop_purchase', -$3::int, $5, 'shop_orders', value,
                   'Покупка в магазине EcoTrack', $6 FROM order_id
            RETURNING id
        )
        INSERT INTO shop_orders (id, user_id, idempotency_key, ledger_entry_id, total_points,
                                 item_count, created_at)
        SELECT order_id.value, $1, $2, debit.id, $3, $4, $6 FROM order_id CROSS JOIN debit
        RETURNING id, idempotency_key, status, total_points, item_count, created_at
        """,
        user_id,
        key,
        total,
        quantity,
        donation_grams,
        purchased_at,
    )
    if row is None:
        raise CatalogException("INTERNAL_SERVER_ERROR")
    return row
