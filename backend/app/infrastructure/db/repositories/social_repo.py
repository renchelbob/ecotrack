from datetime import date, timedelta
from uuid import NAMESPACE_DNS, UUID, uuid5

import asyncpg

from app.api.errors import CatalogException
from app.api.v1.social_models import SharedForestChallengeResponse


async def ensure_forest_week(connection: asyncpg.Connection, day: date) -> UUID:
    iso = day.isocalendar()
    week_start = day - timedelta(days=day.weekday())
    await connection.execute(
        """
        INSERT INTO shared_forest_challenges (
            iso_year, iso_week, week_start_date, week_end_date, title_ru, target_co2_saved_grams
        ) VALUES ($1, $2, $3, $4, $5, 50000)
        ON CONFLICT (iso_year, iso_week) DO NOTHING
        """,
        iso.year,
        iso.week,
        week_start,
        week_start + timedelta(days=6),
        f"Общий лес недели #{iso.week}",
    )
    challenge_id = await connection.fetchval(
        "SELECT id FROM shared_forest_challenges WHERE iso_year = $1 AND iso_week = $2",
        iso.year,
        iso.week,
    )
    if not isinstance(challenge_id, UUID):
        raise CatalogException("SHARED_FOREST_CHALLENGE_NOT_ACTIVE")
    return challenge_id


async def update_forest(
    connection: asyncpg.Connection, user_id: UUID, day: date, *, grams: int, steps: int = 0
) -> None:
    if (grams == 0 and steps == 0) or day.isocalendar().year < 2025:
        return
    challenge_id = await ensure_forest_week(connection, day)
    # Serialize adjustments per week so the total follows the sum of individual contributions.
    await connection.fetchval(
        "SELECT id FROM shared_forest_challenges WHERE id = $1 FOR UPDATE", challenge_id
    )
    crossed_target = await connection.fetchval(
        """
        WITH previous AS MATERIALIZED (
            SELECT contributed_co2_grams FROM shared_forest_contributions
            WHERE challenge_id = $1 AND user_id = $2
        ), contribution AS (
            INSERT INTO shared_forest_contributions (
                challenge_id, user_id, contributed_co2_grams, contributed_steps
            ) VALUES ($1, $2, GREATEST(0, $3::bigint), GREATEST(0, $4::integer))
            ON CONFLICT (challenge_id, user_id) DO UPDATE SET
                contributed_co2_grams = GREATEST(
                    0, shared_forest_contributions.contributed_co2_grams + $3
                ),
                contributed_steps = GREATEST(
                    0, shared_forest_contributions.contributed_steps + $4
                ),
                updated_at = now()
            RETURNING contributed_co2_grams
        )
        UPDATE shared_forest_challenges c
        SET current_co2_saved_grams = GREATEST(0, c.current_co2_saved_grams
            + contribution.contributed_co2_grams
            - COALESCE((SELECT contributed_co2_grams FROM previous), 0))
        FROM contribution WHERE c.id = $1
        RETURNING NOT c.is_completed AND c.current_co2_saved_grams >= c.target_co2_saved_grams
        """,
        challenge_id,
        user_id,
        grams,
        steps,
    )
    if crossed_target:
        await complete_challenge(connection, challenge_id)


async def complete_challenge(connection: asyncpg.Connection, challenge_id: UUID) -> None:
    completed = await connection.fetchval(
        """
        UPDATE shared_forest_challenges SET is_completed = true
        WHERE id = $1 AND NOT is_completed AND current_co2_saved_grams >= target_co2_saved_grams
        RETURNING id
        """,
        challenge_id,
    )
    if completed is None:
        return
    contributors = await connection.fetch(
        """
        SELECT p.user_id FROM shared_forest_contributions p JOIN users u ON u.id = p.user_id
        WHERE p.challenge_id = $1 AND p.contributed_co2_grams > 0
        ORDER BY p.user_id FOR UPDATE OF u
        """,
        challenge_id,
    )
    await connection.executemany(
        """
        INSERT INTO point_ledger (user_id, idempotency_key, operation_type, points_delta,
                                  reference_entity_type, reference_entity_id, description)
        VALUES ($1, $2, 'challenge_reward', 50, 'shared_forest_challenges', $3,
                'Награда за завершение челленджа «Общий лес»')
        ON CONFLICT (idempotency_key) DO NOTHING
        """,
        [
            (
                row["user_id"],
                uuid5(NAMESPACE_DNS, f"shared-forest:{challenge_id}:{row['user_id']}"),
                challenge_id,
            )
            for row in contributors
        ],
    )


async def load_forest(
    connection: asyncpg.Connection, challenge_id: UUID, user_id: UUID
) -> SharedForestChallengeResponse:
    # Compute the user's and friends' contributions in the same snapshot as the total.
    row = await connection.fetchrow(
        """
        SELECT c.id, c.iso_year, c.iso_week, c.week_start_date, c.week_end_date, c.title_ru,
               c.target_co2_saved_grams, c.current_co2_saved_grams, c.trees_equivalent_planted,
               c.is_completed,
               COALESCE(m.contributed_co2_grams, 0) AS my_contributed_co2_grams,
               COALESCE(r.contributors, '[]'::jsonb) AS top_friends_contributors
        FROM shared_forest_challenges c
        LEFT JOIN shared_forest_contributions m ON m.challenge_id = c.id AND m.user_id = $2
        CROSS JOIN LATERAL (
            SELECT jsonb_agg(to_jsonb(ranked) ORDER BY contributed_co2_grams DESC,
                             contributed_steps DESC, user_id) AS contributors
            FROM (
                SELECT u.id AS user_id, u.display_name, u.avatar_url, p.contributed_co2_grams,
                       p.contributed_steps
                FROM friendships f
                JOIN users u ON u.id = CASE WHEN f.requester_id = $2
                                            THEN f.addressee_id ELSE f.requester_id END
                JOIN shared_forest_contributions p ON p.challenge_id = c.id AND p.user_id = u.id
                WHERE f.status = 'accepted' AND (f.requester_id = $2 OR f.addressee_id = $2)
                  AND u.is_stats_visible_to_friends AND u.is_152fz_consent_active
                  AND NOT u.requires_formal_phone AND p.contributed_co2_grams > 0
                ORDER BY p.contributed_co2_grams DESC, p.contributed_steps DESC, u.id
                LIMIT 3
            ) ranked
        ) r
        WHERE c.id = $1
        """,
        challenge_id,
        user_id,
    )
    if row is None:
        raise CatalogException("SHARED_FOREST_CHALLENGE_NOT_ACTIVE")
    values = dict(row)
    values["progress_ratio"] = values["current_co2_saved_grams"] / values["target_co2_saved_grams"]
    return SharedForestChallengeResponse.model_validate(values)
