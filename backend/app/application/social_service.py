from datetime import datetime, timedelta, timezone
from uuid import UUID

import asyncpg

from app.api.errors import CatalogException
from app.api.v1.auth_models import UserProfileResponse
from app.api.v1.social_models import (
    BadgesListResponse,
    MascotAccessoryItem,
    MascotInventoryResponse,
    SharedForestChallengeResponse,
)
from app.application.activity_service import assert_activity_access
from app.infrastructure.db.repositories import badge_repo, social_repo, user_repo

MOSCOW_OFFSET = timezone(timedelta(hours=3))


async def require_active_account(connection: asyncpg.Connection, user_id: UUID) -> None:
    user = await connection.fetchrow(
        "SELECT is_152fz_consent_active, requires_formal_phone FROM users WHERE id = $1",
        user_id,
    )
    if user is None:
        raise CatalogException("AUTH_TOKEN_INVALID")
    assert_activity_access(user)


async def list_badges(connection: asyncpg.Connection, user_id: UUID) -> BadgesListResponse:
    async with connection.transaction(isolation="repeatable_read", readonly=True):
        await require_active_account(connection, user_id)
        badges = await badge_repo.badge_progress(connection, user_id)
        return BadgesListResponse(
            unlocked_count=sum(badge.is_unlocked for badge in badges),
            total_count=len(badges),
            badges=badges,
        )


async def list_accessories(
    connection: asyncpg.Connection, user_id: UUID
) -> MascotInventoryResponse:
    async with connection.transaction(isolation="repeatable_read", readonly=True):
        await require_active_account(connection, user_id)
        rows = await connection.fetch(
            """
            SELECT a.code, a.name_ru, a.slot, a.vector_layer_key, a.unlock_type, i.acquired_at,
                   i.accessory_code IS NOT NULL AS is_unlocked,
                   i.accessory_code IS NOT NULL
                       AND u.equipped_accessory_code IS NOT DISTINCT FROM a.code AS is_equipped
            FROM users u CROSS JOIN mascot_accessories a
            LEFT JOIN user_mascot_inventory i ON i.accessory_code = a.code AND i.user_id = u.id
            WHERE u.id = $1
            ORDER BY CASE a.unlock_type WHEN 'starter' THEN 0 WHEN 'shop' THEN 1 ELSE 2 END, a.code
            """,
            user_id,
        )
        return MascotInventoryResponse(
            accessories=[MascotAccessoryItem.model_validate(dict(row)) for row in rows]
        )


async def equip_accessory(
    connection: asyncpg.Connection, user_id: UUID, code: str | None,
    *, session_id: UUID | None = None,
) -> UserProfileResponse:
    async with connection.transaction():
        await user_repo.lock_user(connection, user_id, session_id=session_id)
        await require_active_account(connection, user_id)
        if code is not None:
            owned = await connection.fetchval(
                """
                SELECT i.accessory_code IS NOT NULL FROM mascot_accessories a
                LEFT JOIN user_mascot_inventory i ON i.accessory_code = a.code AND i.user_id = $1
                WHERE a.code = $2
                """,
                user_id,
                code,
            )
            if owned is None:
                raise CatalogException("MASCOT_ACCESSORY_NOT_FOUND")
            if not owned:
                raise CatalogException("MASCOT_ACCESSORY_NOT_UNLOCKED")
        await connection.execute(
            """
            UPDATE users SET equipped_accessory_code = $2, updated_at = now() WHERE id = $1
              AND equipped_accessory_code IS DISTINCT FROM $2
            """,
            user_id,
            code,
        )
        return await user_repo.load_profile(connection, user_id)


async def current_forest(
    connection: asyncpg.Connection, user_id: UUID
) -> SharedForestChallengeResponse:
    async with connection.transaction():
        await require_active_account(connection, user_id)
        today = datetime.now(MOSCOW_OFFSET).date()
        challenge_id = await social_repo.ensure_forest_week(connection, today)
        return await social_repo.load_forest(connection, challenge_id, user_id)
