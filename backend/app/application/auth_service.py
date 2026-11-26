import hashlib
import secrets
import string
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from uuid import UUID

import asyncpg
import jwt

from app.api.errors import CatalogException
from app.api.v1.auth_models import AuthSessionResponse, OAuthExchangeRequest, TokenRefreshRequest
from app.config import Settings
from app.infrastructure.db.repositories.user_repo import load_profile, lock_user
from app.infrastructure.oauth.yandex_provider import OAuthIdentity


@dataclass(frozen=True, slots=True)
class Principal:
    user_id: UUID
    session_id: UUID


@dataclass(frozen=True, slots=True)
class AccessSession:
    principal: Principal
    fingerprint: str


def signing_key(settings: Settings) -> str:
    key = settings.jwt_secret_key
    if key is None or len(key.get_secret_value().encode("utf-8")) < 32:
        raise CatalogException("INTERNAL_SERVER_ERROR")
    return key.get_secret_value()


def token_hash(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _friend_code() -> str:
    alphabet = string.ascii_uppercase + string.digits
    code = "".join(secrets.choice(alphabet) for _ in range(8))
    return f"ECO-{code[:4]}-{code[4:]}"


async def _create_user(
    connection: asyncpg.Connection, identity: OAuthIdentity, *, google: bool
) -> UUID:
    for _ in range(5):
        user_id: UUID | None = await connection.fetchval(
            """
            INSERT INTO users (
                display_name, email, avatar_url, friend_code, equipped_accessory_code,
                requires_formal_phone
            )
            VALUES ($1, $2, $3, $4, 'leaf_sprout_hat', $5)
            ON CONFLICT (friend_code) DO NOTHING RETURNING id
            """,
            identity.display_name,
            identity.email,
            identity.avatar_url,
            _friend_code(),
            google,
        )
        if user_id is not None:
            await connection.execute(
                "INSERT INTO user_mascot_inventory (user_id, accessory_code)"
                " VALUES ($1, 'leaf_sprout_hat')",
                user_id,
            )
            return user_id
    raise CatalogException("INTERNAL_SERVER_ERROR")


async def _issue_session(
    connection: asyncpg.Connection,
    settings: Settings,
    user_id: UUID,
    fingerprint: str,
) -> AuthSessionResponse:
    google = await connection.fetchval(
        "SELECT EXISTS(SELECT 1 FROM user_oauth_identities "
        "WHERE user_id = $1 AND provider = 'google')",
        user_id,
    )
    if google and not settings.academic_lab_allow_google_oauth:
        raise CatalogException("OAUTH_PROVIDER_UNAVAILABLE")
    refresh = secrets.token_urlsafe(32)
    now = datetime.now(UTC)
    expires = now + timedelta(days=settings.jwt_refresh_token_ttl_days)
    session_id: UUID = await connection.fetchval(
        """
        INSERT INTO auth_refresh_sessions (user_id, token_hash, device_fingerprint, expires_at)
        VALUES ($1, $2, $3, $4) RETURNING id
        """,
        user_id,
        token_hash(refresh),
        fingerprint,
        expires,
    )
    ttl = settings.jwt_access_token_ttl_seconds
    access = jwt.encode(
        {
            "sub": str(user_id),
            "jti": str(session_id),
            "iat": int(now.timestamp()),
            "exp": int(now.timestamp()) + ttl,
            "fp": fingerprint,
        },
        signing_key(settings),
        algorithm="HS256",
    )
    return AuthSessionResponse(
        access_token=access,
        refresh_token=refresh,
        token_type="Bearer",  # noqa: S106 — fixed HTTP authentication scheme.
        expires_in_seconds=ttl,
        is_foreign_provider_lab_mode=google,
        lab_mode_warning_banner=(
            "Внимание. Регистрация и вход через иностранный провайдер Google OAuth "
            "не соответствуют требованиям 406-ФЗ РФ. Этот способ входа включён "
            "исключительно для академического тестирования."
            if google
            else None
        ),
        user=await load_profile(connection, user_id),
    )


async def sign_in(
    connection: asyncpg.Connection,
    settings: Settings,
    body: OAuthExchangeRequest,
    identity: OAuthIdentity,
) -> AuthSessionResponse:
    async with connection.transaction():
        await connection.execute(
            "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))",
            f"oauth:{body.provider}:{identity.subject}",
        )
        user_id: UUID | None = await connection.fetchval(
            """
            SELECT user_id FROM user_oauth_identities
            WHERE provider = $1::oauth_provider_type AND provider_subject_id = $2
            """,
            body.provider,
            identity.subject,
        )
        if user_id is None:
            user_id = await _create_user(connection, identity, google=body.provider == "google")
            await connection.execute(
                """
                INSERT INTO user_oauth_identities
                    (user_id, provider, provider_subject_id, provider_email,
                     is_foreign_provider_lab_mode, last_login_at)
                VALUES ($1, $2::oauth_provider_type, $3, $4, $2 = 'google', now())
                """,
                user_id,
                body.provider,
                identity.subject,
                identity.email,
            )
            await connection.execute(
                """
                INSERT INTO fz152_consent_journal
                    (user_id, policy_version, action, consent_scope)
                VALUES ($1, $2, 'granted', $3::jsonb)
                """,
                user_id,
                body.policy_version,
                body.consent_scope.model_dump(),
            )
        else:
            await lock_user(connection, user_id)
            # A fresh login does not silently override the user's existing consent settings.
            await connection.execute(
                """
                UPDATE user_oauth_identities SET last_login_at = now()
                WHERE user_id = $1 AND provider = $2::oauth_provider_type
                  AND provider_subject_id = $3
                """,
                user_id,
                body.provider,
                identity.subject,
            )
        return await _issue_session(connection, settings, user_id, body.device_fingerprint)


async def refresh_session(
    connection: asyncpg.Connection, settings: Settings, body: TokenRefreshRequest
) -> AuthSessionResponse:
    digest = token_hash(body.refresh_token)
    error = "REFRESH_TOKEN_EXPIRED_OR_REVOKED"
    async with connection.transaction():
        user_id: UUID | None = await connection.fetchval(
            "SELECT user_id FROM auth_refresh_sessions WHERE token_hash = $1", digest
        )
        if user_id is None:
            raise CatalogException(error)
        await lock_user(connection, user_id)
        session = await connection.fetchrow(
            """
            SELECT id, device_fingerprint, revoked_at, expires_at > now() AS unexpired
            FROM auth_refresh_sessions WHERE token_hash = $1 FOR UPDATE
            """,
            digest,
        )
        if session is None or not session["unexpired"]:
            raise CatalogException(error)
        if session["revoked_at"] is not None:
            await connection.execute(
                "UPDATE auth_refresh_sessions SET revoked_at = now()"
                " WHERE user_id = $1 AND revoked_at IS NULL",
                user_id,
            )
        else:
            await connection.execute(
                "UPDATE auth_refresh_sessions SET revoked_at = now() WHERE id = $1", session["id"]
            )
            if session["device_fingerprint"] == body.device_fingerprint:
                return await _issue_session(connection, settings, user_id, body.device_fingerprint)
            error = "DEVICE_FINGERPRINT_MISMATCH"
    # Commit revocation before responding with an error.
    raise CatalogException(error)
