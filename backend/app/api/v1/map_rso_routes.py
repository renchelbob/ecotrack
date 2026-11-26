from decimal import Decimal
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Query, Response
from pydantic import TypeAdapter, ValidationError

from app.api.dependencies import AuthUser, Db, MutationKey, SignedAccess
from app.api.errors import CatalogException, ErrorResponse
from app.api.v1 import API_PREFIX
from app.api.v1.map_rso_models import (
    SubmitWastePointReportRequest,
    SuggestWastePointRequest,
    WasteFraction,
    WastePointDetailResponse,
    WastePointReportCreatedResponse,
    WastePointsBboxResponse,
)
from app.application import map_rso_service
from app.infrastructure.db.repositories.map_rso_repo import bbox_account

router = APIRouter(prefix=f"{API_PREFIX}/map/waste-points", tags=["Recycling Map (RSO)"])
Latitude = Annotated[float, Query(ge=-90, le=90)]
Longitude = Annotated[float, Query(ge=-180, le=180)]
FRACTIONS = TypeAdapter(list[WasteFraction])


@router.get(
    "",
    operation_id="queryWastePointsBbox",
    response_model=WastePointsBboxResponse,
    responses={code: {"model": ErrorResponse} for code in (400, 401, 403)},
)
async def query_points(
    session: SignedAccess,
    connection: Db,
    min_lat: Latitude,
    min_lon: Longitude,
    max_lat: Latitude,
    max_lon: Longitude,
    zoom: Annotated[int, Query(ge=3, le=20)],
    fractions: Annotated[list[str] | None, Query()] = None,
    min_trust_score: Annotated[float, Query(ge=0, le=100)] = 25.0,
    include_unverified: bool = False,
) -> Response:
    account = await bbox_account(
        connection, session.principal.user_id, session.principal.session_id, session.fingerprint
    )
    values = [value for group in fractions or () for value in group.split(",")]
    try:
        parsed = FRACTIONS.validate_python(values) if values else None
    except ValidationError as exc:
        raise CatalogException("VALIDATION_ERROR") from exc
    result = await map_rso_service.query_bbox(
        connection,
        account,
        (min_lon, min_lat, max_lon, max_lat),
        zoom,
        include_unverified,
        Decimal(str(min_trust_score)),
        parsed,
    )
    return Response(result, media_type="application/json")


@router.get(
    "/{point_id}",
    operation_id="getWastePointDetails",
    responses={code: {"model": ErrorResponse} for code in (401, 403, 404)},
)
async def point_detail(
    point_id: UUID, principal: AuthUser, connection: Db
) -> WastePointDetailResponse:
    return await map_rso_service.read_point(connection, principal.user_id, point_id)


@router.post(
    "/{point_id}/reports",
    operation_id="submitWastePointReport",
    status_code=201,
    responses={code: {"model": ErrorResponse} for code in (400, 401, 403, 404, 409, 422, 429)},
)
async def report(
    point_id: UUID,
    body: SubmitWastePointReportRequest,
    key: MutationKey,
    principal: AuthUser,
    connection: Db,
) -> WastePointReportCreatedResponse:
    return await map_rso_service.report_point(connection, principal.user_id, key, point_id, body)


@router.post(
    "/suggestions",
    operation_id="suggestNewWastePoint",
    status_code=201,
    responses={code: {"model": ErrorResponse} for code in (400, 401, 403, 409, 422)},
)
async def suggest(
    body: SuggestWastePointRequest, key: MutationKey, principal: AuthUser, connection: Db
) -> WastePointDetailResponse:
    return await map_rso_service.suggest_point(connection, principal.user_id, key, body)
