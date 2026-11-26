from datetime import datetime
from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, Path, Response
from pydantic import Field

from app.api.dependencies import AuthUser, Db, MutationKey
from app.api.errors import CatalogException, ErrorResponse
from app.api.v1 import API_PREFIX
from app.api.v1.auth_models import ContractModel
from app.application.social_service import require_active_account
from app.infrastructure.db.repositories.user_repo import lock_user

router = APIRouter(prefix=f"{API_PREFIX}/push/tokens", tags=["Push Notifications"])
PushPlatform = Literal["fcm_android", "fcm_ios", "rustore", "apns"]


class RegisterPushTokenRequest(ContractModel):
    platform: PushPlatform
    token: str = Field(min_length=8, max_length=512, repr=False)
    device_id: str = Field(min_length=4, max_length=128)


class PushTokenResponse(ContractModel):
    id: UUID
    platform: PushPlatform
    device_id: str
    is_enabled: bool
    updated_at: datetime


@router.post(
    "",
    operation_id="registerPushToken",
    responses={code: {"model": ErrorResponse} for code in (401, 403, 422)},
)
async def register(
    body: RegisterPushTokenRequest, _key: MutationKey, principal: AuthUser, connection: Db
) -> PushTokenResponse:
    user = principal.user_id
    async with connection.transaction():
        await lock_user(connection, user)
        await require_active_account(connection, user)
        await connection.execute(
            "SELECT pg_advisory_xact_lock(hashtextextended($1, 5))", body.token
        )
        await connection.execute(
            "DELETE FROM user_push_tokens WHERE token = $1 AND (user_id, device_id) <> ($2, $3)",
            body.token,
            user,
            body.device_id,
        )
        row = await connection.fetchrow(
            """
            INSERT INTO user_push_tokens (user_id, platform, token, device_id)
            VALUES ($1, $2, $3, $4)
            ON CONFLICT (user_id, device_id) DO UPDATE SET
                platform = EXCLUDED.platform, token = EXCLUDED.token, is_enabled = true,
                updated_at = CASE WHEN ROW(user_push_tokens.platform, user_push_tokens.token,
                                          user_push_tokens.is_enabled)
                    IS DISTINCT FROM ROW(EXCLUDED.platform, EXCLUDED.token, true)
                    THEN now() ELSE user_push_tokens.updated_at END
            RETURNING id, platform, device_id, is_enabled, updated_at
            """,
            user,
            body.platform,
            body.token,
            body.device_id,
        )
        if row is None:
            raise CatalogException("INTERNAL_SERVER_ERROR")
        return PushTokenResponse.model_validate(dict(row))


@router.delete(
    "/{token}",
    operation_id="unregisterPushToken",
    status_code=204,
    responses={401: {"model": ErrorResponse}},
)
async def unregister(
    token: Annotated[str, Path(min_length=8, max_length=512)], principal: AuthUser, connection: Db
) -> Response:
    await connection.execute(
        "DELETE FROM user_push_tokens WHERE user_id = $1 AND token = $2", principal.user_id, token
    )
    return Response(status_code=204)
