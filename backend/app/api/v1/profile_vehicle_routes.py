from enum import Enum

from fastapi import APIRouter

from app.api.dependencies import AppSettings, AuthUser, Db, MutationKey
from app.api.errors import CatalogException, ErrorResponse
from app.api.v1 import API_PREFIX
from app.api.v1.auth_models import (
    AccountDeletionReceiptResponse,
    AccountDeletionRequest,
    ConsentHistoryListResponse,
    ConsentJournalEntry,
    RecordConsentRequest,
    UpdateUserProfileRequest,
    UserProfileResponse,
)
from app.application.account_service import erase_account
from app.infrastructure.db.repositories.user_repo import load_profile, lock_user

router = APIRouter(prefix=f"{API_PREFIX}/users/me")
profile_tag: list[str | Enum] = ["Profile & Vehicles"]
consent_tag: list[str | Enum] = ["Auth & 152-FZ"]


@router.get(
    "", tags=profile_tag, operation_id="getMyProfile", responses={401: {"model": ErrorResponse}}
)
async def profile(principal: AuthUser, connection: Db) -> UserProfileResponse:
    return await load_profile(connection, principal.user_id)


@router.delete(
    "",
    tags=consent_tag,
    operation_id="deleteMyAccount",
    responses={code: {"model": ErrorResponse} for code in (400, 401)},
)
async def delete_profile(
    body: AccountDeletionRequest,
    _key: MutationKey,
    principal: AuthUser,
    connection: Db,
    settings: AppSettings,
) -> AccountDeletionReceiptResponse:
    return await erase_account(connection, settings, principal.user_id, body.deletion_reason)


@router.patch(
    "",
    tags=profile_tag,
    operation_id="updateMyProfile",
    responses={code: {"model": ErrorResponse} for code in (400, 401, 403, 422)},
)
async def update_profile(
    body: UpdateUserProfileRequest, _key: MutationKey, principal: AuthUser, connection: Db
) -> UserProfileResponse:
    user_id = principal.user_id
    async with connection.transaction():
        await lock_user(connection, user_id)
        active = await connection.fetchval(
            "SELECT is_152fz_consent_active FROM users WHERE id = $1", user_id
        )
        if not active:
            raise CatalogException("FZ152_CONSENT_REVOKED")
        if body.is_gps_tracking_enabled:
            allowed = await connection.fetchval(
                """
                SELECT action <> 'revoked'
                       AND (consent_scope->>'background_geolocation')::boolean
                FROM fz152_consent_journal WHERE user_id = $1
                ORDER BY recorded_at DESC, id DESC LIMIT 1
                """,
                user_id,
            )
            if not allowed:
                raise CatalogException("FZ152_GEOLOCATION_CONSENT_MISSING")
        if body.model_fields_set:
            await connection.execute(
                """
                UPDATE users SET
                    display_name = COALESCE($2, display_name),
                    avatar_url = CASE WHEN $3::boolean THEN $4 ELSE avatar_url END,
                    daily_step_goal = COALESCE($5, daily_step_goal),
                    daily_co2_goal_grams = COALESCE($6, daily_co2_goal_grams),
                    stride_length_cm = COALESCE($7, stride_length_cm),
                    gps_interval_seconds = COALESCE($8, gps_interval_seconds),
                    is_gps_tracking_enabled = COALESCE($9, is_gps_tracking_enabled),
                    is_stats_visible_to_friends = COALESCE($10, is_stats_visible_to_friends),
                    updated_at = now()
                WHERE id = $1
                """,
                user_id,
                body.display_name.strip() if body.display_name is not None else None,
                "avatar_url" in body.model_fields_set,
                body.avatar_url,
                body.daily_step_goal,
                body.daily_co2_goal_grams,
                body.stride_length_cm,
                body.gps_interval_seconds,
                body.is_gps_tracking_enabled,
                body.is_stats_visible_to_friends,
            )
        return await load_profile(connection, user_id)


@router.get(
    "/consents",
    tags=consent_tag,
    operation_id="listConsentHistory",
    responses={401: {"model": ErrorResponse}},
)
async def consent_history(principal: AuthUser, connection: Db) -> ConsentHistoryListResponse:
    async with connection.transaction(isolation="repeatable_read", readonly=True):
        active = await connection.fetchval(
            "SELECT is_152fz_consent_active FROM users WHERE id = $1", principal.user_id
        )
        if active is None:
            raise CatalogException("AUTH_TOKEN_INVALID")
        entries = await connection.fetch(
            """
            SELECT id, policy_version, action, consent_scope, recorded_at
            FROM fz152_consent_journal WHERE user_id = $1 ORDER BY recorded_at DESC, id DESC
            """,
            principal.user_id,
        )
    return ConsentHistoryListResponse(
        is_152fz_consent_active=active,
        entries=[ConsentJournalEntry.model_validate(dict(row)) for row in entries],
    )


@router.post(
    "/consents",
    status_code=201,
    tags=consent_tag,
    operation_id="recordConsentAction",
    responses={code: {"model": ErrorResponse} for code in (400, 401, 409, 422)},
)
async def record_consent(
    body: RecordConsentRequest, key: MutationKey, principal: AuthUser, connection: Db
) -> ConsentJournalEntry:
    scope = body.consent_scope.model_dump()
    user_id = principal.user_id
    async with connection.transaction():
        await lock_user(connection, user_id)
        row = await connection.fetchrow(
            """
            INSERT INTO fz152_consent_journal (id, user_id, policy_version, action, consent_scope)
            VALUES ($1, $2, $3, $4::consent_action_type, $5::jsonb)
            ON CONFLICT (id) DO NOTHING
            RETURNING id, policy_version, action, consent_scope, recorded_at
            """,
            key,
            user_id,
            body.policy_version,
            body.action,
            scope,
        )
        if row is None:
            existing = await connection.fetchrow(
                """
                SELECT id, policy_version, action, consent_scope, recorded_at
                FROM fz152_consent_journal WHERE id = $1 AND user_id = $2
                """,
                key,
                user_id,
            )
            if existing is None or any(
                existing[name] != value for name, value in body.model_dump().items()
            ):
                raise CatalogException("IDEMPOTENCY_KEY_PAYLOAD_MISMATCH")
            return ConsentJournalEntry.model_validate(dict(existing))
        active = body.action != "revoked" and body.consent_scope.personal_data_152fz
        await connection.execute(
            """
            UPDATE users SET is_152fz_consent_active = $2,
                is_gps_tracking_enabled = is_gps_tracking_enabled AND $3::boolean,
                updated_at = now() WHERE id = $1
            """,
            user_id,
            active,
            active and body.consent_scope.background_geolocation,
        )
        return ConsentJournalEntry.model_validate(dict(row))
