from alembic import op

revision = "0002_friend_code_length"
down_revision = "0001_initial_contract"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        DO $$
        BEGIN
            IF EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_schema = 'public' AND table_name = 'users'
                  AND column_name = 'friend_code' AND character_maximum_length = 12
            ) THEN
                ALTER TABLE public.users ALTER COLUMN friend_code TYPE VARCHAR(13);
            END IF;
        END
        $$;
        """
    )


def downgrade() -> None:
    raise NotImplementedError("VARCHAR(12) cannot represent a valid EcoTrack friend code")
