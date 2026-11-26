import hmac
from datetime import UTC, datetime
from uuid import UUID

import asyncpg

from app.api.errors import CatalogException
from app.api.v1.auth_models import AccountDeletionReceiptResponse
from app.config import Settings
from app.infrastructure.db.repositories.user_repo import lock_user
from app.infrastructure.db.transactions import retry_deadlock


@retry_deadlock
async def erase_account(
    connection: asyncpg.Connection,
    settings: Settings,
    user_id: UUID,
    reason: str,
    *,
    session_id: UUID | None = None,
) -> AccountDeletionReceiptResponse:
    secret = deletion_secret(settings)
    audit_hash = deletion_hash(secret, user_id)
    requested_at = datetime.now(UTC)
    async with connection.transaction():
        await lock_user(connection, user_id, session_id=session_id)
        await purge_account_rows(connection, user_id)
        purged_at = datetime.now(UTC)
        signature = deletion_signature(secret, audit_hash, purged_at, reason)
        receipt = await connection.fetchrow(
            """
            INSERT INTO fz152_account_deletion_log (
                anonymized_user_hash, deletion_reason, requested_at, purged_at,
                verification_signature
            ) VALUES ($1, $2, $3, $4, $5)
            RETURNING id AS receipt_id, anonymized_user_hash, purged_at, verification_signature
            """,
            audit_hash,
            reason,
            requested_at,
            purged_at,
            signature,
        )
        if receipt is None:
            raise CatalogException("INTERNAL_SERVER_ERROR")
        return AccountDeletionReceiptResponse.model_validate(dict(receipt))


def deletion_secret(settings: Settings) -> bytes:
    key = settings.fz152_deletion_hmac_secret
    if key is None or len(key.get_secret_value().encode()) < 32:
        raise CatalogException("INTERNAL_SERVER_ERROR")
    return key.get_secret_value().encode()


def deletion_hash(secret: bytes, user_id: UUID) -> str:
    return hmac.digest(secret, str(user_id).encode(), "sha256").hex()


def deletion_signature(secret: bytes, audit_hash: str, purged_at: datetime, reason: str) -> str:
    return hmac.digest(
        secret, f"{audit_hash}:{purged_at.isoformat()}:{reason}".encode(), "sha256"
    ).hex()


async def purge_account_rows(connection: asyncpg.Connection, user_id: UUID) -> None:
    """Purge under the caller's transaction and user lock, retaining anonymised data."""
    # Retain anonymous community counters while removing personal location and text.
    await connection.execute(
        """
        UPDATE point_reports r SET user_id = NULL, comment = NULL,
               user_lat = ST_Y(p.geom), user_lon = ST_X(p.geom), distance_to_point_m = 0
        FROM waste_points p WHERE r.user_id = $1 AND p.id = r.waste_point_id
        """,
        user_id,
    )
    weeks = await connection.fetch(
        """
        SELECT c.id, p.contributed_co2_grams
        FROM shared_forest_contributions p JOIN shared_forest_challenges c
          ON c.id = p.challenge_id
        WHERE p.user_id = $1 ORDER BY c.id FOR UPDATE OF c
        """,
        user_id,
    )
    await connection.executemany(
        """
        UPDATE shared_forest_challenges
        SET current_co2_saved_grams = GREATEST(0, current_co2_saved_grams - $2::bigint)
        WHERE id = $1
        """,
        [(week["id"], week["contributed_co2_grams"]) for week in weeks],
    )
    await connection.execute("SET LOCAL ecotrack.in_152fz_account_erasure = 'true'")
    await connection.execute("DELETE FROM users WHERE id = $1", user_id)
