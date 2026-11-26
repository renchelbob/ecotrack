from datetime import date
from uuid import UUID

from fastapi import APIRouter, Response

from app.api.dependencies import AuthUser, Db, MutationKey, SignedAccess
from app.api.errors import ErrorResponse
from app.api.v1 import API_PREFIX
from app.api.v1.activity_models import DailyActivitySummaryResponse, SyncDailyStepsRequest
from app.api.v1.route_models import (
    DailyActivityDetailResponse,
    GpsTrackPointsBatchRequest,
    GpsTrackPointsBatchResponse,
    ReplaceRouteAllocationsRequest,
)
from app.application.activity_service import sync_steps
from app.application.route_service import (
    ingest_track,
    read_activity,
    remove_allocation,
    save_allocations,
)

router = APIRouter(prefix=f"{API_PREFIX}/activity", tags=["Activity & Hybrid CO2"])


@router.put(
    "/steps/daily",
    operation_id="syncDailyStepsSummary",
    response_model=DailyActivitySummaryResponse,
    responses={code: {"model": ErrorResponse} for code in (400, 401, 403, 409, 422)},
)
async def daily_steps(
    body: SyncDailyStepsRequest, key: MutationKey, session: SignedAccess, connection: Db
) -> Response:
    result = await sync_steps(connection, session.principal.user_id, key, body, session=session)
    return Response(result.model_dump_json(), media_type="application/json")


@router.post(
    "/tracks/points:batch",
    operation_id="uploadGpsTrackPointsBatch",
    responses={code: {"model": ErrorResponse} for code in (400, 401, 403, 409, 422)},
)
async def upload_gps_batch(
    body: GpsTrackPointsBatchRequest, key: MutationKey, user: AuthUser, connection: Db
) -> GpsTrackPointsBatchResponse:
    return await ingest_track(
        connection, user.user_id, body, key=key, session_id=user.session_id
    )


@router.get(
    "/daily/{activity_date}",
    operation_id="getDailyActivityAndRoute",
    responses={code: {"model": ErrorResponse} for code in (401, 403, 404)},
)
async def daily_route(
    activity_date: date, user: AuthUser, connection: Db
) -> DailyActivityDetailResponse:
    return await read_activity(connection, user.user_id, activity_date)


@router.put(
    "/daily/{activity_date}/allocations",
    operation_id="replaceDailyRouteAllocations",
    responses={code: {"model": ErrorResponse} for code in (400, 401, 403, 404, 409, 422)},
)
async def replace_daily_allocations(
    activity_date: date,
    body: ReplaceRouteAllocationsRequest,
    key: MutationKey,
    user: AuthUser,
    connection: Db,
) -> DailyActivityDetailResponse:
    return await save_allocations(
        connection, user.user_id, activity_date, body.allocations, key=key, session_id=user.session_id
    )


@router.delete(
    "/daily/{activity_date}/allocations/{allocation_id}",
    operation_id="deleteRouteSegmentAllocation",
    responses={code: {"model": ErrorResponse} for code in (400, 401, 403, 404)},
)
async def delete_daily_allocation(
    activity_date: date, allocation_id: UUID, _key: MutationKey, user: AuthUser, connection: Db
) -> DailyActivityDetailResponse:
    return await remove_allocation(
        connection, user.user_id, activity_date, allocation_id, session_id=user.session_id
    )
