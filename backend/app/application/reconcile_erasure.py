import argparse
import asyncio
import hmac
from datetime import UTC

import asyncpg

from app.application.account_service import (
    deletion_hash,
    deletion_secret,
    deletion_signature,
    purge_account_rows,
)
from app.config import load_settings

_RECEIPTS = """
SELECT id, anonymized_user_hash, deletion_reason, requested_at, purged_at, verification_signature
FROM fz152_account_deletion_log ORDER BY purged_at, id
"""


async def reconcile(source: asyncpg.Connection, target: asyncpg.Connection, secret: bytes) -> int:
    # Both connections point to the same server. Reject reconciling in place.
    if await source.fetchval("SELECT current_database()") == await target.fetchval(
        "SELECT current_database()"
    ):
        raise RuntimeError("Restore target must be isolated from the authoritative database")

    async with source.transaction(), target.transaction():
        await source.execute("LOCK TABLE fz152_account_deletion_log IN SHARE MODE")
        source_receipts = await source.fetch(_RECEIPTS)
        target_receipts = {row["id"]: row for row in await target.fetch(_RECEIPTS)}
        hashes: set[str] = set()
        for row in source_receipts:
            audit_hash = row["anonymized_user_hash"]
            signature = deletion_signature(
                secret, audit_hash, row["purged_at"].astimezone(UTC), row["deletion_reason"]
            )
            if not hmac.compare_digest(signature, row["verification_signature"]):
                raise RuntimeError("Cannot verify an authoritative erasure receipt")
            hashes.add(audit_hash)
            existing = target_receipts.get(row["id"])
            if existing is not None and existing != row:
                raise RuntimeError("An erasure receipt differs between source and target")
            await target.execute(
                """
                INSERT INTO fz152_account_deletion_log (
                    id, anonymized_user_hash, deletion_reason, requested_at, purged_at,
                    verification_signature
                ) VALUES ($1, $2, $3, $4, $5, $6)
                ON CONFLICT (id) DO NOTHING
                """,
                *row.values(),
            )
        if target_receipts.keys() - {row["id"] for row in source_receipts}:
            raise RuntimeError("Authoritative erasure history does not cover the restored archive")

        removed = 0
        async for user in target.cursor("SELECT id FROM users"):
            user_id = user["id"]
            if deletion_hash(secret, user_id) in hashes:
                await purge_account_rows(target, user_id)
                removed += 1
        return removed


async def _main(target_db: str) -> None:
    settings = load_settings()
    secret = deletion_secret(settings)
    source = await asyncpg.connect(settings.database_url)
    try:
        target = await asyncpg.connect(settings.database_url, database=target_db)
        try:
            removed = await reconcile(source, target, secret)
        finally:
            await target.close()
    finally:
        await source.close()
    print(f"Reconciled erased accounts in isolated database: {removed}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Reapply authoritative EcoTrack erasures after restore")
    parser.add_argument("target_db")
    asyncio.run(_main(parser.parse_args().target_db))
