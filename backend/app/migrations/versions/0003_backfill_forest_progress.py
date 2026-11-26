import asyncpg
from alembic import op
from sqlalchemy.engine import AdaptedConnection

from app.infrastructure.db.repositories.badge_repo import award_badges
from app.infrastructure.db.repositories.social_repo import complete_challenge

revision = "0003_backfill_forest_progress"
down_revision = "0002_friend_code_length"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        CREATE TEMP TABLE forest_progress_backfill ON COMMIT DROP AS
        WITH entries AS (
            SELECT user_id, activity_date AS day, total_co2_saved_grams AS co2,
                   validated_steps AS steps
            FROM daily_step_summaries WHERE total_co2_saved_grams > 0 OR validated_steps > 0
            UNION ALL
            SELECT user_id, (created_at AT TIME ZONE 'Europe/Moscow')::date, co2_delta_grams, 0
            FROM point_ledger WHERE operation_type = 'shop_purchase' AND co2_delta_grams > 0
        )
        SELECT user_id, date_trunc('week', day::timestamp)::date AS monday,
               sum(co2)::bigint AS grams, sum(steps)::int AS steps
        FROM entries
        WHERE EXTRACT(ISOYEAR FROM day) >= 2025
        GROUP BY user_id, monday
        """
    )
    op.execute(
        """
        INSERT INTO shared_forest_challenges
            (iso_year, iso_week, week_start_date, week_end_date, title_ru, target_co2_saved_grams)
        SELECT EXTRACT(ISOYEAR FROM monday), EXTRACT(WEEK FROM monday), monday, monday + 6,
               'Общий лес недели #' || EXTRACT(WEEK FROM monday)::int, 50000
        FROM (SELECT DISTINCT monday FROM forest_progress_backfill) w
        ON CONFLICT (iso_year, iso_week) DO NOTHING
        """
    )
    op.execute(
        """
        INSERT INTO shared_forest_contributions
            (challenge_id, user_id, contributed_co2_grams, contributed_steps)
        SELECT c.id, b.user_id, b.grams, b.steps
        FROM forest_progress_backfill b JOIN shared_forest_challenges c
          ON c.iso_year = EXTRACT(ISOYEAR FROM b.monday)
          AND c.iso_week = EXTRACT(WEEK FROM b.monday)
        ON CONFLICT (challenge_id, user_id) DO UPDATE
        SET contributed_co2_grams = EXCLUDED.contributed_co2_grams,
            contributed_steps = EXCLUDED.contributed_steps,
            updated_at = now()
        """
    )
    op.execute(
        """
        UPDATE shared_forest_challenges c SET current_co2_saved_grams = COALESCE((
            SELECT sum(p.contributed_co2_grams)
            FROM shared_forest_contributions p WHERE p.challenge_id = c.id
        ), 0)
        """
    )

    async def grant_rewards(connection: asyncpg.Connection) -> None:
        challenges = await connection.fetch(
            """
            SELECT id FROM shared_forest_challenges
            WHERE NOT is_completed AND current_co2_saved_grams >= target_co2_saved_grams
            ORDER BY iso_year, iso_week
            """
        )
        for challenge in challenges:
            await complete_challenge(connection, challenge["id"])
        users = await connection.fetch(
            "SELECT id FROM users WHERE is_152fz_consent_active AND NOT requires_formal_phone"
        )
        for user in users:
            await award_badges(connection, user["id"])

    adapter = op.get_bind().connection.dbapi_connection
    if not isinstance(adapter, AdaptedConnection):
        raise RuntimeError("EcoTrack migrations require the asyncpg adapter")
    adapter.run_async(grant_rewards)


def downgrade() -> None:
    raise NotImplementedError("Forest progress and granted ledger rewards are retained")
