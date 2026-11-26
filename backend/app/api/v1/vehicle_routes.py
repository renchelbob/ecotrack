from decimal import ROUND_HALF_UP, Decimal
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Response

from app.api.dependencies import AuthUser, Db, MutationKey
from app.api.errors import CatalogException, ErrorResponse
from app.api.v1 import API_PREFIX
from app.api.v1.auth_models import UserVehicleResponse
from app.api.v1.vehicle_models import (
    TransportPresetItem,
    TransportPresetListResponse,
    UpsertUserVehicleRequest,
)
from app.application.activity_service import assert_activity_access
from app.domain.vehicle_emissions import FUEL_GRAMS_PER_UNIT
from app.infrastructure.db.repositories.user_repo import lock_user

router = APIRouter(prefix=API_PREFIX, tags=["Profile & Vehicles"])


async def _check_access(connection: asyncpg.Connection, user_id: UUID) -> None:
    user = await connection.fetchrow(
        "SELECT is_152fz_consent_active, requires_formal_phone FROM users WHERE id = $1", user_id
    )
    if user is None:
        raise CatalogException("AUTH_TOKEN_INVALID")
    assert_activity_access(user)


@router.get(
    "/users/me/vehicle",
    operation_id="getMyVehicle",
    responses={code: {"model": ErrorResponse} for code in (401, 403, 404)},
)
async def get_vehicle(principal: AuthUser, connection: Db) -> UserVehicleResponse:
    await _check_access(connection, principal.user_id)
    row = await connection.fetchrow(
        """
        SELECT id, vehicle_name, fuel, consumption_per_100km, fuel_emission_factor_g_per_unit,
               computed_co2_g_per_km, computed_co2_g_per_meter, updated_at
        FROM user_vehicles WHERE user_id = $1
        """,
        principal.user_id,
    )
    if row is None:
        raise CatalogException("VEHICLE_NOT_CONFIGURED")
    return UserVehicleResponse.model_validate(dict(row))


@router.put(
    "/users/me/vehicle",
    operation_id="upsertMyVehicle",
    responses={code: {"model": ErrorResponse} for code in (400, 401, 403, 422)},
)
async def save_vehicle(
    body: UpsertUserVehicleRequest, _key: MutationKey, principal: AuthUser, connection: Db
) -> UserVehicleResponse:
    consumption = Decimal(str(body.consumption_per_100km)).quantize(
        Decimal(".01"), rounding=ROUND_HALF_UP
    )
    if not consumption:
        raise CatalogException("INVALID_VEHICLE_CONSUMPTION")
    vehicle_name = body.vehicle_name.strip()
    if not vehicle_name:
        raise CatalogException("VALIDATION_ERROR")
    async with connection.transaction():
        await lock_user(connection, principal.user_id, session_id=principal.session_id)
        await _check_access(connection, principal.user_id)
        row = await connection.fetchrow(
            """
            INSERT INTO user_vehicles (
                user_id, vehicle_name, fuel, consumption_per_100km, fuel_emission_factor_g_per_unit
            ) VALUES ($1, $2, $3, $4, $5)
            ON CONFLICT (user_id) DO UPDATE SET
                vehicle_name = EXCLUDED.vehicle_name, fuel = EXCLUDED.fuel,
                consumption_per_100km = EXCLUDED.consumption_per_100km,
                fuel_emission_factor_g_per_unit = EXCLUDED.fuel_emission_factor_g_per_unit,
                updated_at = CASE WHEN
                    ROW(user_vehicles.vehicle_name, user_vehicles.fuel,
                        user_vehicles.consumption_per_100km,
                        user_vehicles.fuel_emission_factor_g_per_unit) IS DISTINCT FROM
                    ROW(EXCLUDED.vehicle_name, EXCLUDED.fuel, EXCLUDED.consumption_per_100km,
                        EXCLUDED.fuel_emission_factor_g_per_unit)
                    THEN now() ELSE user_vehicles.updated_at END
            RETURNING id, vehicle_name, fuel, consumption_per_100km,
                      fuel_emission_factor_g_per_unit, computed_co2_g_per_km,
                      computed_co2_g_per_meter, updated_at
            """,
            principal.user_id,
            vehicle_name,
            body.fuel.value,
            consumption,
            Decimal(FUEL_GRAMS_PER_UNIT[body.fuel]),
        )
        if row is None:
            raise CatalogException("INTERNAL_SERVER_ERROR")
        return UserVehicleResponse.model_validate(dict(row))


@router.delete(
    "/users/me/vehicle",
    operation_id="deleteMyVehicle",
    status_code=204,
    responses={code: {"model": ErrorResponse} for code in (400, 401, 403)},
)
async def delete_vehicle(_key: MutationKey, principal: AuthUser, connection: Db) -> Response:
    async with connection.transaction():
        await lock_user(connection, principal.user_id, session_id=principal.session_id)
        await _check_access(connection, principal.user_id)
        await connection.execute("DELETE FROM user_vehicles WHERE user_id = $1", principal.user_id)
    return Response(status_code=204)


@router.get(
    "/transport/presets",
    operation_id="listTransportEmissionPresets",
    responses={code: {"model": ErrorResponse} for code in (401, 403)},
)
async def list_presets(principal: AuthUser, connection: Db) -> TransportPresetListResponse:
    await _check_access(connection, principal.user_id)
    rows = await connection.fetch(
        """
        SELECT m.mode_code, m.display_name_ru, m.display_name_en, m.is_personal_vehicle_slot,
               COALESCE(v.computed_co2_g_per_km, m.co2_grams_per_km) AS co2_grams_per_km,
               COALESCE(v.computed_co2_g_per_meter, m.co2_grams_per_meter) AS co2_grams_per_meter
        FROM transport_emission_catalog m LEFT JOIN user_vehicles v
               ON v.user_id = $1 AND m.is_personal_vehicle_slot
        ORDER BY m.sort_order, m.mode_code
        """,
        principal.user_id,
    )
    return TransportPresetListResponse(
        presets=[TransportPresetItem.model_validate(dict(row)) for row in rows]
    )
