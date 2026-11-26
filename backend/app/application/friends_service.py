from datetime import date, datetime, timedelta
from typing import Literal
from uuid import UUID

import asyncpg

from app.api.errors import CatalogException
from app.api.v1.friend_models import (
    FriendAction,
    FriendProfileSummary,
    FriendsLeaderboardResponse,
    FriendsOverviewResponse,
    FriendshipRecord,
    LeaderboardEntry,
    WakeupNudgeResponse,
)
from app.application.social_service import MOSCOW_OFFSET, require_active_account
from app.infrastructure.db.repositories import badge_repo, user_repo
from app.infrastructure.db.transactions import retry_deadlock
from app.infrastructure.push.base import PushNotificationProvider


def _week(today: date) -> tuple[date, date]:
    monday = today - timedelta(days=today.weekday())
    return monday, monday + timedelta(days=6)


async def list_friends(connection: asyncpg.Connection, user_id: UUID) -> FriendsOverviewResponse:
    today = datetime.now(MOSCOW_OFFSET).date()
    start, end = _week(today)
    async with connection.transaction(isolation="repeatable_read", readonly=True):
        await require_active_account(connection, user_id)
        own_code = await connection.fetchval("SELECT friend_code FROM users WHERE id = $1", user_id)
        if not isinstance(own_code, str):
            raise CatalogException("AUTH_TOKEN_INVALID")
        rows = await connection.fetch(
            """
            SELECT f.id AS friendship_id, f.requester_id = $1 AS outgoing,
                u.id AS user_id, u.display_name, u.friend_code, u.avatar_url, f.status,
                CASE WHEN visible.enabled THEN u.current_streak_days ELSE 0 END
                    AS current_streak_days,
                u.equipped_accessory_code, u.is_stats_visible_to_friends,
                CASE WHEN visible.enabled THEN stats.grams END AS weekly_co2_saved_grams,
                CASE WHEN visible.enabled THEN stats.steps END AS weekly_steps,
                f.status = 'accepted' AND NOT EXISTS (
                    SELECT 1 FROM friend_wakeup_nudges n
                    WHERE n.sender_id = $1 AND n.receiver_id = u.id AND n.nudge_date = $4
                ) AS can_send_wakeup_nudge_today
            FROM friendships f JOIN users u ON u.id = CASE WHEN f.requester_id = $1
                                             THEN f.addressee_id ELSE f.requester_id END
            CROSS JOIN LATERAL (
                SELECT u.is_stats_visible_to_friends AND f.status = 'accepted' AS enabled
            ) visible
            CROSS JOIN LATERAL (
                SELECT COALESCE(sum(total_co2_saved_grams), 0) AS grams,
                       COALESCE(sum(validated_steps), 0) AS steps
                FROM daily_step_summaries
                WHERE user_id = u.id AND activity_date BETWEEN $2 AND $3 AND visible.enabled
            ) stats
            WHERE (f.requester_id = $1 OR f.addressee_id = $1)
              AND f.status IN ('pending', 'accepted')
              AND u.is_152fz_consent_active AND NOT u.requires_formal_phone
            ORDER BY f.created_at DESC, f.id
            """,
            user_id,
            start,
            end,
            today,
        )
    friends: list[FriendProfileSummary] = []
    incoming: list[FriendProfileSummary] = []
    outgoing: list[FriendProfileSummary] = []
    for row in rows:
        values = dict(row)
        is_outgoing = values.pop("outgoing")
        item = FriendProfileSummary.model_validate(values)
        if item.status == "accepted":
            friends.append(item)
        elif is_outgoing:
            outgoing.append(item)
        else:
            incoming.append(item)
    return FriendsOverviewResponse(
        my_friend_code=own_code,
        friends=friends,
        incoming_requests=incoming,
        outgoing_requests=outgoing,
    )


async def leaderboard(connection: asyncpg.Connection, user_id: UUID) -> FriendsLeaderboardResponse:
    today = datetime.now(MOSCOW_OFFSET).date()
    start, end = _week(today)
    async with connection.transaction(isolation="repeatable_read", readonly=True):
        await require_active_account(connection, user_id)
        rows = await connection.fetch(
            """
            WITH circle AS (
                SELECT $1::uuid AS uid UNION ALL
                SELECT CASE WHEN requester_id = $1 THEN addressee_id ELSE requester_id END
                FROM friendships WHERE status = 'accepted'
                  AND (requester_id = $1 OR addressee_id = $1)
            ), totals AS (
                SELECT u.id AS user_id, u.display_name, u.avatar_url, u.equipped_accessory_code,
                    u.id = $1 AS is_current_user, v.enabled AS is_stats_visible,
                    COALESCE(sum(d.total_co2_saved_grams), 0) AS weekly_co2_saved_grams,
                    COALESCE(sum(d.validated_steps), 0) AS weekly_steps,
                    CASE WHEN v.enabled THEN u.current_streak_days ELSE 0 END AS current_streak_days
                FROM circle c JOIN users u ON u.id = c.uid
                CROSS JOIN LATERAL (
                    SELECT u.id = $1 OR u.is_stats_visible_to_friends AS enabled
                ) v
                LEFT JOIN daily_step_summaries d ON v.enabled AND d.user_id = u.id
                    AND d.activity_date BETWEEN $2 AND $3
                WHERE u.is_152fz_consent_active AND NOT u.requires_formal_phone
                GROUP BY u.id, v.enabled
            )
            SELECT row_number() OVER (ORDER BY is_stats_visible DESC, weekly_co2_saved_grams DESC,
                                               weekly_steps DESC, user_id) AS rank, totals.*
            FROM totals ORDER BY rank
            """,
            user_id,
            start,
            end,
        )
    iso = today.isocalendar()
    return FriendsLeaderboardResponse(
        iso_year=iso.year,
        iso_week=iso.week,
        week_start_date=start,
        week_end_date=end,
        entries=[LeaderboardEntry.model_validate(dict(row)) for row in rows],
    )


@retry_deadlock
async def send_request(
    connection: asyncpg.Connection, user_id: UUID, key: UUID, friend_code: str,
    *, session_id: UUID | None = None,
) -> FriendshipRecord:
    async with connection.transaction():
        await user_repo.lock_user(connection, user_id, session_id=session_id)
        await require_active_account(connection, user_id)
        target = await connection.fetchval(
            """
            SELECT id FROM users WHERE friend_code = $1
              AND is_152fz_consent_active AND NOT requires_formal_phone
            """,
            friend_code,
        )
        if not isinstance(target, UUID):
            raise CatalogException("FRIEND_CODE_NOT_FOUND")
        if target == user_id:
            raise CatalogException("FRIEND_REQUEST_SELF_FORBIDDEN")
        pair = ":".join(str(uid) for uid in sorted((user_id, target)))
        await connection.execute("SELECT pg_advisory_xact_lock(hashtextextended($1, 4))", pair)
        existing = await connection.fetchrow(
            """
            SELECT * FROM friendships WHERE
                LEAST(requester_id, addressee_id) = LEAST($1::uuid, $2::uuid)
                AND GREATEST(requester_id, addressee_id) = GREATEST($1::uuid, $2::uuid)
            """,
            user_id,
            target,
        )
        if existing is not None:
            if existing["status"] == "blocked":
                raise CatalogException("FRIENDSHIP_BLOCKED")
            if existing["id"] == key and existing["requester_id"] == user_id:
                return FriendshipRecord.model_validate(dict(existing))
            raise CatalogException("FRIENDSHIP_ALREADY_EXISTS")
        created = await connection.fetchrow(
            """
            INSERT INTO friendships (id, requester_id, addressee_id) VALUES ($1, $2, $3)
            ON CONFLICT DO NOTHING RETURNING *
            """,
            key,
            user_id,
            target,
        )
        if created is None:
            raise CatalogException("IDEMPOTENCY_KEY_PAYLOAD_MISMATCH")
        return FriendshipRecord.model_validate(dict(created))


@retry_deadlock
async def reply(
    connection: asyncpg.Connection, user_id: UUID, friendship_id: UUID, action: FriendAction,
    *, session_id: UUID | None = None,
) -> FriendshipRecord:
    async with connection.transaction():
        # The requester can receive a badge upon accepting, so take both user locks in order.
        parties = await connection.fetchval(
            "SELECT requester_id FROM friendships WHERE id = $1 AND addressee_id = $2",
            friendship_id,
            user_id,
        )
        if not isinstance(parties, UUID):
            raise CatalogException("FRIENDSHIP_NOT_FOUND")
        for uid in sorted((user_id, parties)):
            await user_repo.lock_user(connection, uid, session_id=session_id if uid == user_id else None)
        await require_active_account(connection, user_id)
        row = await connection.fetchrow(
            "SELECT * FROM friendships WHERE id = $1 AND addressee_id = $2 FOR UPDATE",
            friendship_id,
            user_id,
        )
        if row is None:
            raise CatalogException("FRIENDSHIP_NOT_FOUND")
        result = FriendshipRecord.model_validate(dict(row))
        if action == "decline":
            if result.status != "pending":
                raise CatalogException("FRIENDSHIP_NOT_FOUND")
            await connection.execute("DELETE FROM friendships WHERE id = $1", friendship_id)
            return result.model_copy(update={"responded_at": datetime.now(MOSCOW_OFFSET)})
        return await _set_reply_status(connection, result, action)


async def _set_reply_status(
    connection: asyncpg.Connection, previous: FriendshipRecord, action: Literal["accept", "block"]
) -> FriendshipRecord:
    status = "accepted" if action == "accept" else "blocked"
    if previous.status == status:
        return previous
    if previous.status != "pending":
        raise CatalogException("FRIENDSHIP_NOT_FOUND")
    updated = await connection.fetchrow(
        "UPDATE friendships SET status = $2, responded_at = now() WHERE id = $1 RETURNING *",
        previous.id,
        status,
    )
    if updated is None:
        raise CatalogException("FRIENDSHIP_NOT_FOUND")
    if status == "accepted":
        await badge_repo.award_badges(connection, previous.addressee_id)
        await badge_repo.award_badges(connection, previous.requester_id)
    return FriendshipRecord.model_validate(dict(updated))


async def remove(
    connection: asyncpg.Connection, user_id: UUID, friend_id: UUID,
    *, session_id: UUID | None = None,
) -> None:
    async with connection.transaction():
        await user_repo.lock_user(connection, user_id, session_id=session_id)
        await require_active_account(connection, user_id)
        removed = await connection.fetchval(
            """
            DELETE FROM friendships WHERE status = 'accepted'
              AND LEAST(requester_id, addressee_id) = LEAST($1::uuid, $2::uuid)
              AND GREATEST(requester_id, addressee_id) = GREATEST($1::uuid, $2::uuid) RETURNING id
            """,
            user_id,
            friend_id,
        )
        if removed is None:
            raise CatalogException("FRIENDSHIP_NOT_FOUND")


async def nudge(
    connection: asyncpg.Connection,
    user_id: UUID,
    friend_id: UUID,
    key: UUID,
    provider: PushNotificationProvider,
    *,
    session_id: UUID | None = None,
) -> WakeupNudgeResponse:
    async with connection.transaction():
        await user_repo.lock_user(connection, user_id, session_id=session_id)
        await require_active_account(connection, user_id)
        await _require_friend(connection, user_id, friend_id)
        previous = await connection.fetchrow(
            """
            SELECT id AS nudge_id, receiver_id, sender_id, nudge_date, sent_at, push_delivered
            FROM friend_wakeup_nudges WHERE id = $1
            """,
            key,
        )
        if previous is not None:
            if previous["sender_id"] != user_id or previous["receiver_id"] != friend_id:
                raise CatalogException("IDEMPOTENCY_KEY_PAYLOAD_MISMATCH")
            return _nudge_result(previous)
        row = await connection.fetchrow(
            """
            INSERT INTO friend_wakeup_nudges (id, sender_id, receiver_id, nudge_date)
            VALUES ($1, $2, $3, $4)
            ON CONFLICT (sender_id, receiver_id, nudge_date) DO NOTHING
            RETURNING id AS nudge_id, receiver_id, nudge_date, sent_at, push_delivered
            """,
            key,
            user_id,
            friend_id,
            datetime.now(MOSCOW_OFFSET).date(),
        )
        if row is None:
            raise CatalogException("WAKEUP_NUDGE_DAILY_COOLDOWN")
        sender = await connection.fetchval("SELECT display_name FROM users WHERE id = $1", user_id)
        tokens = await connection.fetch(
            """
            SELECT token FROM user_push_tokens WHERE user_id = $1 AND is_enabled
               AND platform IN ('fcm_android', 'fcm_ios')
            ORDER BY updated_at DESC LIMIT 20
            """,
            friend_id,
        )
    delivered = isinstance(sender, str) and await provider.send_wakeup_nudge(
        [token["token"] for token in tokens], sender
    )
    if delivered:
        await connection.execute(
            "UPDATE friend_wakeup_nudges SET push_delivered = true WHERE id = $1", key
        )
    return _nudge_result(row).model_copy(update={"push_delivered": delivered})


def _nudge_result(row: asyncpg.Record) -> WakeupNudgeResponse:
    return WakeupNudgeResponse.model_validate(
        {field: row[field] for field in WakeupNudgeResponse.model_fields}
    )


async def _require_friend(connection: asyncpg.Connection, user_id: UUID, friend_id: UUID) -> None:
    exists = await connection.fetchval(
        """
        SELECT 1 FROM friendships f JOIN users u ON u.id = $2
        WHERE f.status = 'accepted' AND u.is_152fz_consent_active AND NOT u.requires_formal_phone
          AND LEAST(f.requester_id, f.addressee_id) = LEAST($1::uuid, $2::uuid)
          AND GREATEST(f.requester_id, f.addressee_id) = GREATEST($1::uuid, $2::uuid)
        """,
        user_id,
        friend_id,
    )
    if not exists:
        raise CatalogException("FRIENDSHIP_NOT_FOUND")
