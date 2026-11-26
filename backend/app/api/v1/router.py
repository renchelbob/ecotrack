from fastapi import FastAPI

from app.api.v1.activity_routes import router as activity_router
from app.api.v1.auth_routes import router as auth_router
from app.api.v1.friend_routes import router as friends_router
from app.api.v1.ledger_shop_routes import router as ledger_shop_router
from app.api.v1.map_rso_routes import router as map_rso_router
from app.api.v1.profile_vehicle_routes import router as profile_router
from app.api.v1.push_routes import router as push_router
from app.api.v1.social_routes import router as social_router
from app.api.v1.stats_routes import router as stats_router
from app.api.v1.vehicle_routes import router as vehicle_router


def register_v1_routes(app: FastAPI) -> None:
    for router in (
        # The router scans in registration order. Put the frequent sync and read paths first.
        map_rso_router,
        activity_router,
        stats_router,
        auth_router,
        profile_router,
        vehicle_router,
        ledger_shop_router,
        social_router,
        friends_router,
        push_router,
    ):
        # These routes already carry their API prefix and dependency configuration.
        app.router.routes.extend(router.routes)
