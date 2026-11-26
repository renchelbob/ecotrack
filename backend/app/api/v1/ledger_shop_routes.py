from typing import Annotated

from fastapi import APIRouter, Query

from app.api.dependencies import AuthUser, Db, MutationKey
from app.api.errors import ErrorResponse
from app.api.v1 import API_PREFIX
from app.api.v1.auth_models import UserProfileResponse
from app.api.v1.ledger_shop_models import (
    CreateShopOrderRequest,
    PointLedgerListResponse,
    ShopCatalogResponse,
    ShopItemType,
    ShopOrderDetail,
    ShopOrderListResponse,
)
from app.application import ledger_shop_service
from app.infrastructure.db.repositories import ledger_shop_repo

router = APIRouter(prefix=API_PREFIX, tags=["Ledger & Shop"])
Limit = Annotated[int, Query(ge=1, le=100)]
Offset = Annotated[int, Query(ge=0)]
READ_ERRORS: dict[int | str, dict[str, type[ErrorResponse]]] = {
    401: {"model": ErrorResponse},
    403: {"model": ErrorResponse},
}


@router.get("/ledger", operation_id="listPointLedger", responses=READ_ERRORS)
async def ledger(
    principal: AuthUser, connection: Db, limit: Limit = 20, offset: Offset = 0
) -> PointLedgerListResponse:
    async with connection.transaction(isolation="repeatable_read", readonly=True):
        user = await ledger_shop_service.shop_user(connection, principal.user_id)
        return await ledger_shop_repo.load_ledger(connection, user, limit, offset)


@router.get("/shop/items", operation_id="listShopCatalog", responses=READ_ERRORS)
async def catalog(
    principal: AuthUser,
    connection: Db,
    category: Annotated[str | None, Query(max_length=64)] = None,
    item_type: ShopItemType | None = None,
    search: Annotated[str | None, Query(max_length=80)] = None,
) -> ShopCatalogResponse:
    await ledger_shop_service.shop_user(connection, principal.user_id)
    if category is not None and category.casefold() == "все":
        category = None
    return await ledger_shop_repo.load_catalog(connection, category, item_type, search)


@router.get("/shop/orders", operation_id="listMyShopOrders", responses=READ_ERRORS)
async def orders(
    principal: AuthUser, connection: Db, limit: Limit = 20, offset: Offset = 0
) -> ShopOrderListResponse:
    return await ledger_shop_service.list_orders(connection, principal.user_id, limit, offset)


@router.post(
    "/shop/orders",
    operation_id="createShopOrder",
    status_code=201,
    responses={code: {"model": ErrorResponse} for code in (400, 401, 403, 409, 422)},
)
async def create_order(
    body: CreateShopOrderRequest, key: MutationKey, principal: AuthUser, connection: Db
) -> ShopOrderDetail:
    return await ledger_shop_service.checkout(connection, principal.user_id, key, body.items)


@router.post(
    "/shop/virtual-items/streak-freeze:activate",
    operation_id="activateStreakFreeze",
    responses={code: {"model": ErrorResponse} for code in (400, 401, 403, 409)},
)
async def activate_streak_freeze(
    _key: MutationKey, principal: AuthUser, connection: Db
) -> UserProfileResponse:
    return await ledger_shop_service.activate_freeze(connection, principal.user_id)
