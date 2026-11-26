import re

from fastapi import APIRouter, Response

from app.api.dependencies import AppSettings, AuthUser, Db, MutationKey
from app.api.errors import CatalogException, ErrorResponse
from app.api.v1 import API_PREFIX
from app.api.v1.auth_models import (
    AuthSessionResponse,
    GoogleFormalPhoneRequest,
    LogoutRequest,
    OAuthExchangeRequest,
    TokenRefreshRequest,
    UserProfileResponse,
)
from app.application.auth_service import refresh_session, sign_in, signing_key, token_hash
from app.infrastructure.db.repositories.user_repo import load_profile, lock_user
from app.infrastructure.oauth.google_provider import exchange_google_code
from app.infrastructure.oauth.yandex_provider import exchange_yandex_code

router = APIRouter(prefix=f"{API_PREFIX}/auth", tags=["Auth & 152-FZ"])


@router.post(
    "/oauth/exchange",
    operation_id="exchangeOAuthCode",
    responses={code: {"model": ErrorResponse} for code in (400, 401, 403, 422, 503)},
)
async def exchange_oauth(
    body: OAuthExchangeRequest, _key: MutationKey, settings: AppSettings, connection: Db
) -> AuthSessionResponse:
    if not body.consent_scope.personal_data_152fz:
        raise CatalogException("FZ152_CONSENT_REQUIRED")
    if body.provider == "yandex":
        redirect = settings.yandex_oauth_redirect_uri
        exchange = exchange_yandex_code
    elif body.provider == "google" and settings.academic_lab_allow_google_oauth:
        redirect = settings.google_oauth_redirect_uri
        exchange = exchange_google_code
    else:
        raise CatalogException("OAUTH_PROVIDER_UNAVAILABLE")
    if body.redirect_uri != redirect or not re.fullmatch(
        r"[A-Za-z0-9._~\-]{43,128}", body.code_verifier
    ):
        raise CatalogException("OAUTH_PKCE_VERIFICATION_FAILED")
    signing_key(settings)
    identity = await exchange(settings, body.authorization_code, body.code_verifier)
    return await sign_in(connection, settings, body, identity)


@router.post(
    "/google-phone",
    operation_id="submitGoogleFormalPhone",
    responses={code: {"model": ErrorResponse} for code in (400, 401, 422)},
)
async def google_phone(
    body: GoogleFormalPhoneRequest, _key: MutationKey, principal: AuthUser, connection: Db
) -> UserProfileResponse:
    user_id = principal.user_id
    async with connection.transaction():
        await lock_user(connection, user_id)
        await connection.execute(
            """
            UPDATE users
            SET formal_phone_e164 = $2, requires_formal_phone = false, updated_at = now()
            WHERE id = $1 AND requires_formal_phone
            """,
            user_id,
            body.formal_phone_e164,
        )
        return await load_profile(connection, user_id)


@router.post(
    "/refresh", operation_id="refreshAccessToken", responses={401: {"model": ErrorResponse}}
)
async def refresh(
    body: TokenRefreshRequest, settings: AppSettings, connection: Db
) -> AuthSessionResponse:
    return await refresh_session(connection, settings, body)


@router.post(
    "/logout",
    status_code=204,
    operation_id="logoutSession",
    responses={401: {"model": ErrorResponse}},
)
async def logout(body: LogoutRequest, principal: AuthUser, connection: Db) -> Response:
    async with connection.transaction():
        await lock_user(connection, principal.user_id)
        revoked = await connection.fetchval(
            """
            UPDATE auth_refresh_sessions SET revoked_at = now()
            WHERE id = $1 AND user_id = $2 AND token_hash = $3 AND revoked_at IS NULL
            RETURNING id
            """,
            principal.session_id,
            principal.user_id,
            token_hash(body.refresh_token),
        )
        if revoked is None:
            raise CatalogException("REFRESH_TOKEN_EXPIRED_OR_REVOKED")
    return Response(status_code=204)
