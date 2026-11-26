from functools import lru_cache
from pathlib import Path
from uuid import UUID

from fastapi import APIRouter, Response

from app.api.dependencies import AppSettings, AuthUser, Db, MutationKey
from app.api.errors import ErrorResponse
from app.api.v1 import API_PREFIX
from app.api.v1.friend_models import (
    FriendsLeaderboardResponse,
    FriendsOverviewResponse,
    FriendshipRecord,
    RespondFriendRequestPayload,
    SendFriendRequestPayload,
    WakeupNudgeResponse,
)
from app.application import friends_service
from app.infrastructure.push.base import PushNotificationProvider
from app.infrastructure.push.fcm_provider import FcmPushProvider
from app.infrastructure.push.noop_provider import NoopPushProvider

router = APIRouter(prefix=f"{API_PREFIX}/friends", tags=["Social & Challenges"])


@lru_cache(maxsize=4)
def _provider(backend: str, service_account: Path) -> PushNotificationProvider:
    return FcmPushProvider(service_account) if backend == "fcm" else NoopPushProvider()


@router.get(
    "",
    operation_id="getFriendsAndRequests",
    responses={code: {"model": ErrorResponse} for code in (401, 403)},
)
async def list_friends(principal: AuthUser, connection: Db) -> FriendsOverviewResponse:
    return await friends_service.list_friends(connection, principal.user_id)


@router.get(
    "/leaderboard",
    operation_id="getWeeklyFriendsLeaderboard",
    responses={code: {"model": ErrorResponse} for code in (401, 403)},
)
async def leaderboard(principal: AuthUser, connection: Db) -> FriendsLeaderboardResponse:
    return await friends_service.leaderboard(connection, principal.user_id)


@router.post(
    "/requests",
    operation_id="sendFriendRequest",
    status_code=201,
    responses={code: {"model": ErrorResponse} for code in (400, 401, 403, 404, 409)},
)
async def send_request(
    body: SendFriendRequestPayload, key: MutationKey, principal: AuthUser, connection: Db
) -> FriendshipRecord:
    return await friends_service.send_request(
        connection, principal.user_id, key, body.friend_code, session_id=principal.session_id
    )


@router.patch(
    "/requests/{friendship_id}",
    operation_id="respondToFriendRequest",
    responses={code: {"model": ErrorResponse} for code in (400, 401, 403, 404)},
)
async def reply(
    friendship_id: UUID,
    body: RespondFriendRequestPayload,
    _key: MutationKey,
    principal: AuthUser,
    connection: Db,
) -> FriendshipRecord:
    return await friends_service.reply(
        connection, principal.user_id, friendship_id, body.action, session_id=principal.session_id
    )


@router.delete(
    "/{friend_user_id}",
    operation_id="removeFriend",
    status_code=204,
    responses={code: {"model": ErrorResponse} for code in (401, 403, 404)},
)
async def remove(
    friend_user_id: UUID, _key: MutationKey, principal: AuthUser, connection: Db
) -> Response:
    await friends_service.remove(
        connection, principal.user_id, friend_user_id, session_id=principal.session_id
    )
    return Response(status_code=204)


@router.post(
    "/{friend_user_id}/nudge",
    operation_id="sendWakeupMascotNudge",
    responses={code: {"model": ErrorResponse} for code in (401, 403, 404, 409, 429)},
)
async def nudge(
    friend_user_id: UUID,
    key: MutationKey,
    principal: AuthUser,
    connection: Db,
    settings: AppSettings,
) -> WakeupNudgeResponse:
    provider = _provider(settings.push_provider_backend, settings.fcm_service_account_json_path)
    return await friends_service.nudge(
        connection, principal.user_id, friend_user_id, key, provider, session_id=principal.session_id
    )
