from fastapi import APIRouter

from app.api.dependencies import AuthUser, Db, MutationKey
from app.api.errors import ErrorResponse
from app.api.v1 import API_PREFIX
from app.api.v1.auth_models import UserProfileResponse
from app.api.v1.social_models import (
    BadgesListResponse,
    EquipMascotAccessoryRequest,
    MascotInventoryResponse,
    SharedForestChallengeResponse,
)
from app.application import social_service

router = APIRouter(prefix=API_PREFIX)
ACCESS_ERRORS: dict[int | str, dict[str, type[ErrorResponse]]] = {
    401: {"model": ErrorResponse},
    403: {"model": ErrorResponse},
}


@router.get(
    "/badges",
    tags=["Social & Challenges"],
    operation_id="listUserBadges",
    responses=ACCESS_ERRORS,
)
async def badges(principal: AuthUser, connection: Db) -> BadgesListResponse:
    return await social_service.list_badges(connection, principal.user_id)


@router.get(
    "/mascot/inventory",
    tags=["Profile & Vehicles"],
    operation_id="listMascotAccessories",
    responses=ACCESS_ERRORS,
)
async def inventory(principal: AuthUser, connection: Db) -> MascotInventoryResponse:
    return await social_service.list_accessories(connection, principal.user_id)


@router.put(
    "/users/me/mascot/accessory",
    tags=["Profile & Vehicles"],
    operation_id="equipMascotAccessory",
    responses={code: {"model": ErrorResponse} for code in (400, 401, 403, 404)},
)
async def equip(
    body: EquipMascotAccessoryRequest, _key: MutationKey, principal: AuthUser, connection: Db
) -> UserProfileResponse:
    return await social_service.equip_accessory(connection, principal.user_id, body.accessory_code)


@router.get(
    "/challenges/shared-forest/current",
    tags=["Social & Challenges"],
    operation_id="getCurrentSharedForestChallenge",
    responses=ACCESS_ERRORS,
)
async def shared_forest(principal: AuthUser, connection: Db) -> SharedForestChallengeResponse:
    return await social_service.current_forest(connection, principal.user_id)
