from alembic import op

revision = "0002_friend_code_length"
down_revision = "0001_initial_contract"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("ALTER TABLE users ALTER COLUMN friend_code TYPE VARCHAR(13)")


def downgrade() -> None:
    raise NotImplementedError("VARCHAR(12) cannot represent a valid EcoTrack friend code")
