from uuid import NAMESPACE_DNS, UUID, uuid5

import asyncpg

from app.api.v1.social_models import BadgeCatalogProgressItem


async def badge_progress(
    connection: asyncpg.Connection, user_id: UUID
) -> list[BadgeCatalogProgressItem]:
    rows = await connection.fetch(
        """
        WITH metrics AS (
            SELECT u.lifetime_co2_saved_grams, u.longest_streak_days,
                   (SELECT COALESCE(sum(s.validated_steps), 0)
                    FROM daily_step_summaries s WHERE s.user_id = $1) AS steps,
                   (SELECT count(*) FROM point_reports WHERE user_id = $1) AS reports,
                   (SELECT count(*) FROM friendships WHERE status = 'accepted'
                    AND (requester_id = $1 OR addressee_id = $1)) AS friends,
                   (SELECT COALESCE(sum(contributed_co2_grams), 0)
                    FROM shared_forest_contributions WHERE user_id = $1) AS forest
            FROM users u WHERE u.id = $1
        )
        SELECT b.code, b.title_ru, b.description_ru, b.icon_vector_key, b.threshold_type,
               b.threshold_value, b.reward_points, b.reward_accessory_code, a.awarded_at,
               a.badge_code IS NOT NULL AS is_unlocked,
               CASE b.threshold_type
                   WHEN 'steps_total' THEN m.steps
                   WHEN 'co2_grams_total' THEN m.lifetime_co2_saved_grams
                   WHEN 'streak_days' THEN m.longest_streak_days
                   WHEN 'rso_reports' THEN m.reports
                   WHEN 'friends_count' THEN m.friends
                   WHEN 'forest_contribution' THEN m.forest
               END AS current_value
        FROM badges_catalog b CROSS JOIN metrics m
        LEFT JOIN user_badges a ON a.badge_code = b.code AND a.user_id = $1
        ORDER BY b.sort_order, b.code
        """,
        user_id,
    )
    return [BadgeCatalogProgressItem.model_validate(dict(row)) for row in rows]


async def award_badges(connection: asyncpg.Connection, user_id: UUID) -> None:
    # Mutations take the user lock before changing the metrics used by this query.
    for badge in await badge_progress(connection, user_id):
        if not badge.is_unlocked and badge.current_value >= badge.threshold_value:
            await _award_badge(connection, user_id, badge)


async def _award_badge(
    connection: asyncpg.Connection, user_id: UUID, badge: BadgeCatalogProgressItem
) -> None:
    ledger_id = None
    if badge.reward_points:
        ledger_id = await connection.fetchval(
            """
            INSERT INTO point_ledger (user_id, idempotency_key, operation_type, points_delta,
                                      reference_entity_type, description)
            VALUES ($1, $2, 'badge_reward', $3, 'user_badges', $4) RETURNING id
            """,
            user_id,
            uuid5(NAMESPACE_DNS, f"badge:{badge.code}:{user_id}"),
            badge.reward_points,
            badge.title_ru,
        )
    await connection.execute(
        "INSERT INTO user_badges (user_id, badge_code, ledger_entry_id) VALUES ($1, $2, $3)",
        user_id,
        badge.code,
        ledger_id,
    )
    if badge.reward_accessory_code is not None:
        await connection.execute(
            """
            INSERT INTO user_mascot_inventory (user_id, accessory_code) VALUES ($1, $2)
            ON CONFLICT DO NOTHING
            """,
            user_id,
            badge.reward_accessory_code,
        )
