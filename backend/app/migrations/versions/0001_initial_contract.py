from pathlib import Path

import asyncpg
from alembic import op
from sqlalchemy.engine import AdaptedConnection

revision = "0001_initial_contract"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Execute the contract with the simple-query protocol under Alembic's own transaction.
    schema_candidates = (
        Path("/contracts/schema.sql"),
        Path(__file__).resolve().parents[4] / "contracts" / "schema.sql",
    )
    schema = next(path for path in schema_candidates if path.is_file())
    content = schema.read_text(encoding="utf-8").strip()
    before, begin, statements = content.partition("\nBEGIN;\n")
    if not begin or not statements.endswith("\nCOMMIT;"):
        raise RuntimeError("Expected initial schema to be wrapped in BEGIN/COMMIT")
    ddl = before + "\n" + statements.removesuffix("\nCOMMIT;")

    async def execute(connection: asyncpg.Connection) -> None:
        await connection.execute(ddl)

    adapter = op.get_bind().connection.dbapi_connection
    if not isinstance(adapter, AdaptedConnection):
        raise RuntimeError("EcoTrack migrations require the asyncpg adapter")
    adapter.run_async(execute)


def downgrade() -> None:
    raise NotImplementedError("The initial EcoTrack schema cannot be downgraded without data loss")
