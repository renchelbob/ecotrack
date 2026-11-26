import asyncio
import os
import time
from collections.abc import Iterator
from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime, timedelta
from pathlib import Path
from uuid import UUID, uuid4, uuid7

import asyncpg
import httpx
import pytest
import schemathesis
from fastapi.testclient import TestClient
from starlette.routing import compile_path

from app.api import dependencies
from app.api.v1 import auth_routes
from app.api.v1.ledger_shop_models import CartLineInput
from app.api.v1.map_rso_models import WastePointsBboxResponse
from app.application.ledger_shop_service import checkout
from app.application.social_service import MOSCOW_OFFSET
from app.config import Settings
from app.infrastructure.oauth.yandex_provider import OAuthIdentity
from app.main import app

pytestmark = pytest.mark.skipif("TEST_DATABASE_URL" not in os.environ, reason="requires PostGIS")

FINGERPRINT = "test-installation-001"


@pytest.fixture(scope="module")
def validate_contract_response():
    contract_path = Path(__file__).resolve().parents[3] / "contracts" / "openapi.yaml"
    schema = schemathesis.openapi.from_path(contract_path)
    paths = [
        (compile_path(path)[0], path, methods)
        for path, methods in schema.raw_schema["paths"].items()
    ]

    def validate(response: httpx.Response) -> None:
        request = response.request
        method = request.method.lower()
        for pattern, path, methods in paths:
            if method in methods and pattern.fullmatch(request.url.path):
                operation = schema[path][method]
                if (
                    response.is_success
                    or str(response.status_code) in operation.definition.raw["responses"]
                ):
                    response.read()
                    operation.validate_response(response)
                return
        pytest.fail(f"Operation missing from OpenAPI: {request.method} {request.url.path}")

    return validate


@pytest.fixture
def oauth_client(
    monkeypatch: pytest.MonkeyPatch, validate_contract_response
) -> Iterator[TestClient]:
    dsn = os.environ["TEST_DATABASE_URL"]
    subject = f"test-yandex-{uuid4()}"
    monkeypatch.setenv("DATABASE_URL", dsn)
    monkeypatch.setenv("JWT_SECRET_KEY", uuid4().hex + uuid4().hex)
    monkeypatch.setenv("FZ152_DELETION_HMAC_SECRET", uuid4().hex + uuid4().hex)
    monkeypatch.setenv("PUSH_PROVIDER_BACKEND", "noop")

    async def exchange(_settings: Settings, code: str, _verifier: str) -> OAuthIdentity:
        identity = f"{subject}-second" if code == "second-provider-code" else subject
        return OAuthIdentity(identity, "Test EcoTrack", None, None)

    monkeypatch.setattr(auth_routes, "exchange_yandex_code", exchange)
    monkeypatch.setattr(auth_routes, "exchange_google_code", exchange)
    try:
        with TestClient(app) as client:
            client.event_hooks["response"].append(validate_contract_response)
            yield client
    finally:

        async def clean_up() -> None:
            connection = await asyncpg.connect(dsn)
            try:
                async with connection.transaction():
                    await connection.execute("SET LOCAL ecotrack.in_152fz_account_erasure = 'true'")
                    deleted = await connection.fetch(
                        """
                        DELETE FROM users WHERE id IN (
                            SELECT user_id FROM user_oauth_identities
                            WHERE provider_subject_id IN ($1, $2)
                        )
                        RETURNING ARRAY(SELECT challenge_id FROM shared_forest_contributions
                                        WHERE user_id = users.id) AS challenge_ids
                        """,
                        subject,
                        f"{subject}-second",
                    )
                    weeks = {week for row in deleted for week in row["challenge_ids"]}
                    if weeks:
                        await connection.execute(
                            """
                            UPDATE shared_forest_challenges c
                            SET current_co2_saved_grams = COALESCE((
                                SELECT sum(p.contributed_co2_grams)
                                FROM shared_forest_contributions p WHERE p.challenge_id = c.id
                            ), 0)
                            WHERE id = ANY($1::uuid[])
                            """,
                            list(weeks),
                        )
            finally:
                await connection.close()

        asyncio.run(clean_up())


def exchange(
    client: TestClient, code: str = "provider-code", provider: str = "yandex"
) -> dict[str, object]:
    response = client.post(
        "/api/v1/auth/oauth/exchange",
        headers={"Idempotency-Key": str(uuid7())},
        json={
            "provider": provider,
            "authorization_code": code,
            "code_verifier": "x" * 43,
            "redirect_uri": "ecotrack://auth/callback",
            "device_fingerprint": FINGERPRINT,
            "policy_version": "1.0.0-2026",
            "consent_scope": {
                "personal_data_152fz": True,
                "health_steps_sensor": True,
                "background_geolocation": False,
            },
        },
    )
    assert response.status_code == 200, response.text
    return response.json()


def test_cached_access_token_still_expires(
    oauth_client: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    session = exchange(oauth_client)
    headers = {"Authorization": f"Bearer {session['access_token']}"}
    assert oauth_client.get("/api/v1/users/me", headers=headers).status_code == 200

    expires_after = time.time() + int(str(session["expires_in_seconds"])) + 1
    monkeypatch.setattr(dependencies, "time", lambda: expires_after)
    expired = oauth_client.get("/api/v1/users/me", headers=headers)
    assert expired.status_code == 401
    assert expired.json()["error_code"] == "AUTH_TOKEN_EXPIRED"


def test_login_returns_same_profile_and_consent_is_idempotent(oauth_client: TestClient) -> None:
    session = exchange(oauth_client)
    other = exchange(oauth_client)
    assert session["user"] == other["user"]
    headers = {"Authorization": f"Bearer {session['access_token']}"}

    profile = oauth_client.get("/api/v1/users/me", headers=headers)
    assert profile.status_code == 200
    assert len(profile.json()["friend_code"]) == 13
    assert "leaf_sprout_hat" in profile.json()["mascot"]["unlocked_accessory_codes"]

    settings = oauth_client.patch(
        "/api/v1/users/me",
        headers={**headers, "Idempotency-Key": str(uuid7())},
        json={"daily_step_goal": 9000, "avatar_url": None},
    )
    assert settings.status_code == 200, settings.text
    assert settings.json()["daily_step_goal"] == 9000
    blocked = oauth_client.patch(
        "/api/v1/users/me",
        headers={**headers, "Idempotency-Key": str(uuid7())},
        json={"is_gps_tracking_enabled": True},
    )
    assert blocked.json()["error_code"] == "FZ152_GEOLOCATION_CONSENT_MISSING"

    payload = {
        "policy_version": "1.0.0-2026",
        "action": "revoked",
        "consent_scope": {
            "personal_data_152fz": False,
            "health_steps_sensor": False,
            "background_geolocation": False,
        },
    }
    mutation = {**headers, "Idempotency-Key": str(uuid7())}
    result = oauth_client.post("/api/v1/users/me/consents", headers=mutation, json=payload)
    repeat = oauth_client.post("/api/v1/users/me/consents", headers=mutation, json=payload)
    assert result.status_code == 201
    assert repeat.json() == result.json()
    history = oauth_client.get("/api/v1/users/me/consents", headers=headers)
    assert history.json()["is_152fz_consent_active"] is False
    assert len(history.json()["entries"]) == 2
    assert exchange(oauth_client)["user"]["is_152fz_consent_active"] is False


def test_refresh_reuse_revokes_sessions_and_logout_revokes_current(
    oauth_client: TestClient,
) -> None:
    session = exchange(oauth_client)
    refresh = {"refresh_token": session["refresh_token"], "device_fingerprint": FINGERPRINT}
    response = oauth_client.post("/api/v1/auth/refresh", json=refresh)
    assert response.status_code == 200, response.text
    rotated = response.json()
    assert rotated["refresh_token"] != session["refresh_token"]
    replay = oauth_client.post("/api/v1/auth/refresh", json=refresh)
    assert replay.status_code == 401
    assert replay.json()["error_code"] == "REFRESH_TOKEN_EXPIRED_OR_REVOKED"
    rejected = oauth_client.get(
        "/api/v1/users/me", headers={"Authorization": f"Bearer {rotated['access_token']}"}
    )
    assert rejected.status_code == 401

    active = exchange(oauth_client)
    headers = {"Authorization": f"Bearer {active['access_token']}"}
    bbox = "/api/v1/map/waste-points?min_lat=0&max_lat=1&min_lon=0&max_lon=1&zoom=14"
    stats = "/api/v1/stats/emissions?period=days"
    for path in (bbox, stats):
        assert oauth_client.get(path, headers=headers).status_code == 200
    logout = oauth_client.post(
        "/api/v1/auth/logout", headers=headers, json={"refresh_token": active["refresh_token"]}
    )
    assert logout.status_code == 204
    for path in ("/api/v1/users/me", bbox, stats):
        assert oauth_client.get(path, headers=headers).status_code == 401
    steps = oauth_client.put(
        "/api/v1/activity/steps/daily",
        headers={**headers, "Idempotency-Key": str(uuid7())},
        json={
            "activity_date": (datetime.now(UTC).date() - timedelta(days=1)).isoformat(),
            "timezone_offset_minutes": 0,
            "raw_sensor_steps": 100,
        },
    )
    assert steps.status_code == 401


def test_steps_replay_awards_once_and_updates_statistics(oauth_client: TestClient) -> None:
    session = exchange(oauth_client)
    headers = {"Authorization": f"Bearer {session['access_token']}"}
    day = (datetime.now(UTC).date() - timedelta(days=1)).isoformat()
    body = {
        "activity_date": day,
        "raw_sensor_steps": 5000,
        "timezone_offset_minutes": 0,
        "stride_length_cm": 80,
    }
    missing = oauth_client.put("/api/v1/activity/steps/daily", headers=headers, json=body)
    assert missing.status_code == 400
    assert missing.json()["error_code"] == "INVALID_IDEMPOTENCY_KEY"
    mutation = {**headers, "Idempotency-Key": str(uuid7())}
    null_stride = oauth_client.put(
        "/api/v1/activity/steps/daily", headers=mutation, json={**body, "stride_length_cm": None}
    )
    assert null_stride.status_code == 422
    first = oauth_client.put("/api/v1/activity/steps/daily", headers=mutation, json=body)
    assert first.status_code == 200, first.text
    assert first.json()["points_delta_applied"] == 50
    assert first.json()["total_co2_saved_grams"] == 184
    repeated = oauth_client.put("/api/v1/activity/steps/daily", headers=mutation, json=body)
    assert repeated.status_code == 200
    assert repeated.json()["points_delta_applied"] == 0
    assert repeated.json()["points_balance"] == 50
    newer = oauth_client.put(
        "/api/v1/activity/steps/daily",
        headers={**headers, "Idempotency-Key": str(uuid7())},
        json={**body, "raw_sensor_steps": 5200},
    )
    assert newer.status_code == 200, newer.text
    assert newer.json()["points_balance"] == 52
    overview = oauth_client.get(
        f"/api/v1/stats/emissions?period=days&reference_date={day}", headers=headers
    )
    assert overview.status_code == 200, overview.text
    assert overview.json()["period_total_steps"] == 5200
    assert overview.json()["period_total_co2_saved_grams"] == 191
    assert len(overview.json()["buckets"]) == 7
    for period in ("weeks", "months"):
        overview = oauth_client.get(
            f"/api/v1/stats/emissions?period={period}&reference_date={day}", headers=headers
        )
        assert overview.status_code == 200, overview.text
        assert overview.json()["period_total_steps"] == 5200
        buckets = overview.json()["buckets"]
        assert len(buckets) == 12
        assert buckets[-1]["end_date"] == day
        assert buckets[-1]["validated_steps"] == 5200
    history = oauth_client.get("/api/v1/stats/history", headers=headers)
    assert history.status_code == 200, history.text
    assert history.json()["total_count"] == 1
    assert history.json()["items"][0]["validated_steps"] == 5200


def test_gps_batch_and_allocation_recalculate_co2(oauth_client: TestClient) -> None:
    session = exchange(oauth_client)
    bearer = {"Authorization": f"Bearer {session['access_token']}"}
    yesterday = (datetime.now(UTC) + timedelta(hours=3)).date() - timedelta(days=1)
    start = datetime.combine(yesterday, datetime.min.time(), UTC) + timedelta(hours=12)
    batch = {
        "activity_date": yesterday.isoformat(),
        "points": [
            {
                "seq_no": seq,
                "recorded_at": (start + timedelta(seconds=15 * seq)).isoformat(),
                "lat": 55.7500 + 0.00010 * seq,
                "lon": 37.6100,
                "accuracy_m": 2.4,
                "speed_mps": 0.7,
                "cumulative_steps": 50 + seq * 10,
            }
            for seq in range(3)
        ],
    }
    headers = {**bearer, "Idempotency-Key": str(uuid7())}
    batch_path = "/api/v1/activity/tracks/points:batch"
    blocked = oauth_client.post(batch_path, headers=headers, json=batch)
    assert blocked.status_code == 403
    assert blocked.json()["error_code"] == "FZ152_GEOLOCATION_CONSENT_MISSING"
    consent = oauth_client.post(
        "/api/v1/users/me/consents",
        headers={**bearer, "Idempotency-Key": str(uuid7())},
        json={
            "policy_version": "1.0.0-2026",
            "action": "updated",
            "consent_scope": {
                "personal_data_152fz": True,
                "health_steps_sensor": True,
                "background_geolocation": True,
            },
        },
    )
    assert consent.status_code == 201
    first = oauth_client.post(batch_path, headers=headers, json=batch)
    assert first.status_code == 200, first.text
    assert first.json()["ingested_count"] == 3
    assert 22 < first.json()["total_gps_walking_distance_m"] < 23
    retry = oauth_client.post(batch_path, headers=headers, json=batch)
    assert retry.status_code == 200
    assert retry.json()["ingested_count"] == 0
    assert retry.json()["total_point_count"] == 3
    last = {
        **batch["points"][-1],
        "seq_no": 3,
        "recorded_at": (start + timedelta(seconds=45)).isoformat(),
        "lat": 55.7508,
    }
    continuation = oauth_client.post(
        batch_path,
        headers={**bearer, "Idempotency-Key": str(uuid7())},
        json={**batch, "points": [last]},
    )
    assert continuation.status_code == 200, continuation.text
    assert continuation.json()["total_point_count"] == 4
    update = oauth_client.put(
        "/api/v1/activity/steps/daily",
        headers={**bearer, "Idempotency-Key": str(uuid7())},
        json={
            "activity_date": yesterday.isoformat(),
            "timezone_offset_minutes": 180,
            "raw_sensor_steps": 5000,
            "stride_length_cm": 80,
        },
    )
    assert update.status_code == 200, update.text
    route_path = f"/api/v1/activity/daily/{yesterday}"
    detail = oauth_client.get(route_path, headers=bearer)
    assert detail.status_code == 200, detail.text
    assert detail.json()["is_editable"]
    assert [point["motion_class"] for point in detail.json()["track_points"]] == [
        "stationary",
        "walking",
        "walking",
        "vehicle_suspected",
    ]
    allocation = {
        "idempotency_key": str(uuid7()),
        "start_seq_no": 0,
        "end_seq_no": 2,
        "replaced_transport_mode": "car_sedan",
    }
    request = {"allocations": [allocation]}
    annotation_headers = {**bearer, "Idempotency-Key": str(uuid7())}
    annotated = oauth_client.put(
        f"{route_path}/allocations", headers=annotation_headers, json=request
    )
    assert annotated.status_code == 200, annotated.text
    details = annotated.json()
    assert details["co2_delta_applied_grams"] > 0
    assert details["summary"]["points_balance"] == 50
    segment = details["allocations"][0]
    assert segment["segment_steps"] == 20
    assert len(segment["coordinates"]) == 3
    replay = oauth_client.put(f"{route_path}/allocations", headers=annotation_headers, json=request)
    assert replay.status_code == 200
    assert replay.json()["co2_delta_applied_grams"] == 0
    assert replay.json()["allocations"][0]["id"] == segment["id"]
    overlapping = oauth_client.put(
        f"{route_path}/allocations",
        headers={**bearer, "Idempotency-Key": str(uuid7())},
        json={"allocations": [allocation, {**allocation, "idempotency_key": str(uuid7())}]},
    )
    assert overlapping.status_code == 409
    assert overlapping.json()["error_code"] == "SEGMENT_OVERLAP_CONFLICT"
    vehicle = oauth_client.put(
        f"{route_path}/allocations",
        headers={**bearer, "Idempotency-Key": str(uuid7())},
        json={"allocations": [{**allocation, "idempotency_key": str(uuid7()), "end_seq_no": 3}]},
    )
    assert vehicle.status_code == 422
    assert vehicle.json()["error_code"] == "SEGMENT_CONTAINS_VEHICLE_MOTION"
    deleted = oauth_client.delete(
        f"{route_path}/allocations/{segment['id']}",
        headers={**bearer, "Idempotency-Key": str(uuid7())},
    )
    assert deleted.status_code == 200, deleted.text
    assert deleted.json()["allocations"] == []
    assert deleted.json()["summary"]["total_co2_saved_grams"] == 184
    assert deleted.json()["co2_delta_applied_grams"] == -details["co2_delta_applied_grams"]

    async def check_forest_contribution() -> None:
        connection = await asyncpg.connect(os.environ["TEST_DATABASE_URL"])
        try:
            row = await connection.fetchrow(
                """
                SELECT p.contributed_steps, p.contributed_co2_grams
                FROM shared_forest_contributions p
                JOIN shared_forest_challenges c ON c.id = p.challenge_id
                WHERE p.user_id = $1 AND $2 BETWEEN c.week_start_date AND c.week_end_date
                """,
                UUID(session["user"]["id"]),
                yesterday,
            )
            assert row is not None
            assert row["contributed_steps"] == 5000
            assert row["contributed_co2_grams"] == 184
        finally:
            await connection.close()

    asyncio.run(check_forest_contribution())


def test_vehicle_changes_only_personal_transport_preset(oauth_client: TestClient) -> None:
    session = exchange(oauth_client)
    bearer = {"Authorization": f"Bearer {session['access_token']}"}
    preset_path = "/api/v1/transport/presets"
    vehicle_path = "/api/v1/users/me/vehicle"
    original = oauth_client.get(preset_path, headers=bearer)
    assert original.status_code == 200, original.text
    initial = {item["mode_code"]: item for item in original.json()["presets"]}
    assert len(initial) == 8
    assert initial["personal_car"]["co2_grams_per_km"] == 192
    body = {"vehicle_name": "Авто", "fuel": "petrol_95", "consumption_per_100km": 8.5}
    mutation = {**bearer, "Idempotency-Key": str(uuid7())}
    saved = oauth_client.put(vehicle_path, headers=mutation, json=body)
    assert saved.status_code == 200, saved.text
    assert saved.json()["computed_co2_g_per_km"] == 198.05
    assert saved.json()["computed_co2_g_per_meter"] == 0.19805
    retry = oauth_client.put(vehicle_path, headers=mutation, json=body)
    assert retry.status_code == 200
    assert retry.json() == saved.json()
    read = oauth_client.get(vehicle_path, headers=bearer)
    assert read.json() == saved.json()
    new = oauth_client.get(preset_path, headers=bearer)
    assert new.status_code == 200, new.text
    updated = {item["mode_code"]: item for item in new.json()["presets"]}
    assert updated.pop("personal_car")["co2_grams_per_km"] == 198.05
    initial.pop("personal_car")
    assert initial == updated
    deleted = oauth_client.delete(vehicle_path, headers={**bearer, "Idempotency-Key": str(uuid7())})
    assert deleted.status_code == 204
    assert oauth_client.get(vehicle_path, headers=bearer).status_code == 404
    assert oauth_client.get(preset_path, headers=bearer).json() == original.json()


ORDER_URL = "/api/v1/shop/orders"
LEDGER_URL = "/api/v1/ledger"
FREEZE_URL = "/api/v1/shop/virtual-items/streak-freeze:activate"
DONATION_ID = UUID("01950000-0000-7000-8000-000000000102")


async def _credit(connection: asyncpg.Connection, user_id: UUID, points: int) -> None:
    await connection.execute(
        """
        INSERT INTO point_ledger (user_id, idempotency_key, operation_type, points_delta,
                                  description)
        VALUES ($1, $2, 'admin_adjustment', $3, 'Test balance')
        """,
        user_id,
        uuid7(),
        points,
    )


def _fund_shop_user(user_id: str, points: int) -> None:
    async def fund() -> None:
        connection = await asyncpg.connect(os.environ["TEST_DATABASE_URL"])
        try:
            await _credit(connection, UUID(user_id), points)
        finally:
            await connection.close()

    asyncio.run(fund())


@pytest.mark.parametrize("stock_item", [3], indirect=True)
def test_shop_order_replay_and_ledger(stock_item: str, oauth_client: TestClient) -> None:
    session = exchange(oauth_client)
    bearer = {"Authorization": f"Bearer {session['access_token']}"}
    result = oauth_client.get(
        "/api/v1/shop/items",
        headers=bearer,
        params={"category": "еда и напитки", "item_type": "partner_qr", "search": "КОФЕ"},
    )
    assert result.status_code == 200, result.text
    catalog = result.json()
    (item,) = catalog["items"]
    assert item["sku"] == "DEMO-COFFEE-30"
    assert item["partner"]["slug"] == "zelenaya-chashka"
    assert "Виртуальные бонусы" in catalog["categories"]
    body = {"items": [{"shop_item_id": stock_item, "quantity": 2}]}
    mutation = {**bearer, "Idempotency-Key": str(uuid7())}
    no_points = oauth_client.post(ORDER_URL, json=body, headers=mutation)
    assert no_points.status_code == 409, no_points.text
    assert no_points.json()["error_code"] == "INSUFFICIENT_POINTS_BALANCE"
    _fund_shop_user(session["user"]["id"], 1000)
    created = oauth_client.post(ORDER_URL, json=body, headers=mutation)
    assert created.status_code == 201, created.text
    order = created.json()
    assert order["total_points"] == 500
    assert order["item_count"] == 2
    assert order["remaining_points_balance"] == 500
    (line,) = order["line_items"]
    assert line["coupon_code"] in line["qr_payload"]
    assert line["expires_at"]
    assert oauth_client.post(ORDER_URL, json=body, headers=mutation).json() == order

    one = {"items": [{"shop_item_id": stock_item, "quantity": 1}]}
    mismatch = oauth_client.post(ORDER_URL, json=one, headers=mutation)
    assert mismatch.status_code == 409
    assert mismatch.json()["error_code"] == "IDEMPOTENCY_KEY_PAYLOAD_MISMATCH"
    limited = oauth_client.post(
        ORDER_URL, json=one, headers={**bearer, "Idempotency-Key": str(uuid7())}
    )
    assert limited.status_code == 409
    assert limited.json()["error_code"] == "SHOP_DAILY_USER_LIMIT_EXCEEDED"
    ledger = oauth_client.get(LEDGER_URL, headers=bearer, params={"limit": 1}).json()
    assert (ledger["points_balance"], ledger["lifetime_points_earned"]) == (500, 1000)
    assert ledger["total_count"] == 2
    (debit,) = ledger["items"]
    assert debit["points_delta"] == -500
    assert debit["reference_entity_id"] == order["id"]
    assert oauth_client.get(ORDER_URL, headers=bearer).json() == {
        "orders": [order],
        "total_count": 1,
    }
    other = exchange(oauth_client, "second-provider-code")
    other_bearer = {"Authorization": f"Bearer {other['access_token']}"}
    assert oauth_client.get(ORDER_URL, headers=other_bearer).json() == {
        "orders": [],
        "total_count": 0,
    }
    collision = oauth_client.post(
        ORDER_URL,
        json=body,
        headers={**other_bearer, "Idempotency-Key": mutation["Idempotency-Key"]},
    )
    assert collision.json()["error_code"] == "IDEMPOTENCY_KEY_PAYLOAD_MISMATCH"


@pytest.fixture
def stock_item(request: pytest.FixtureRequest) -> Iterator[str]:
    item_id = uuid7()
    stock = getattr(request, "param", 1)

    async def update_stock(*, create: bool) -> None:
        connection = await asyncpg.connect(os.environ["TEST_DATABASE_URL"])
        try:
            if create:
                await connection.execute(
                    """
                    INSERT INTO shop_items (id, sku, item_type, title, subtitle, description,
                                            price_points, stock_quantity, max_per_user_per_day,
                                            image_asset_key)
                    VALUES ($1, $2, 'partner_qr', 'Test', '', 'Test stock', 250, $3, 2, 'test')
                    """,
                    item_id,
                    str(item_id),
                    stock,
                )
            else:
                await connection.execute("DELETE FROM shop_items WHERE id = $1", item_id)
        finally:
            await connection.close()

    asyncio.run(update_stock(create=True))
    try:
        yield str(item_id)
    finally:
        asyncio.run(update_stock(create=False))


def test_shop_does_not_oversell_last_coupon(stock_item: str, oauth_client: TestClient) -> None:
    sessions = [exchange(oauth_client), exchange(oauth_client, "second-provider-code")]
    bearers = []
    for session in sessions:
        bearers.append({"Authorization": f"Bearer {session['access_token']}"})
        _fund_shop_user(session["user"]["id"], 250)
    body = {"items": [{"shop_item_id": stock_item, "quantity": 1}]}
    with ThreadPoolExecutor(max_workers=2) as executor:
        purchases = [
            executor.submit(
                oauth_client.post,
                ORDER_URL,
                json=body,
                headers={**bearer, "Idempotency-Key": str(uuid7())},
            )
            for bearer in bearers
        ]
        results = [purchase.result(timeout=15) for purchase in purchases]
    assert sorted(result.status_code for result in results) == [201, 409], [
        result.text for result in results
    ]
    for bearer, result in zip(bearers, results, strict=True):
        ledger = oauth_client.get(LEDGER_URL, headers=bearer).json()
        if result.status_code == 409:
            assert result.json()["error_code"] == "SHOP_ITEM_OUT_OF_STOCK"
            assert (ledger["points_balance"], ledger["total_count"]) == (250, 1)
        else:
            assert (ledger["points_balance"], ledger["total_count"]) == (0, 2)


def test_shop_grants_virtual_inventory_and_freeze_can_be_activated_once(
    oauth_client: TestClient,
) -> None:
    session = exchange(oauth_client)
    _fund_shop_user(session["user"]["id"], 2000)
    bearer = {"Authorization": f"Bearer {session['access_token']}"}
    items = [
        {"shop_item_id": "01950000-0000-7000-8000-000000000101", "quantity": 2},
        {"shop_item_id": "01950000-0000-7000-8000-000000000103", "quantity": 1},
    ]
    order = oauth_client.post(
        ORDER_URL,
        json={"items": items},
        headers={**bearer, "Idempotency-Key": str(uuid7())},
    )
    assert order.status_code == 201, order.text
    assert order.json()["item_count"] == 3
    profile = oauth_client.get("/api/v1/users/me", headers=bearer).json()
    assert profile["streak_freeze_count"] == 2
    assert "knit_green_scarf" in profile["mascot"]["unlocked_accessory_codes"]
    duplicate = oauth_client.post(
        ORDER_URL,
        json={"items": items[1:]},
        headers={**bearer, "Idempotency-Key": str(uuid7())},
    )
    assert duplicate.json()["error_code"] == "SHOP_ACCESSORY_ALREADY_OWNED"
    mutation = {**bearer, "Idempotency-Key": str(uuid7())}
    activated = oauth_client.post(FREEZE_URL, headers=mutation)
    assert activated.status_code == 200, activated.text
    assert activated.json()["streak_freeze_count"] == 1
    assert oauth_client.post(FREEZE_URL, headers=mutation).json()["error_code"] == (
        "STREAK_FREEZE_NOT_NEEDED"
    )
    assert oauth_client.get("/api/v1/users/me", headers=bearer).json()["streak_freeze_count"] == 1


def test_shop_donation_unlocks_badge_and_completes_forest(oauth_client: TestClient) -> None:
    session = exchange(oauth_client)
    user_id = UUID(session["user"]["id"])

    async def purchase() -> None:
        connection = await asyncpg.connect(os.environ["TEST_DATABASE_URL"])
        transaction = connection.transaction()
        await transaction.start()
        try:
            # Roll back the challenge and all effects on contributors after this test.
            today = datetime.now(MOSCOW_OFFSET).date()
            iso = today.isocalendar()
            monday = today - timedelta(days=today.weekday())
            await connection.execute(
                """
                INSERT INTO shared_forest_challenges (
                    iso_year, iso_week, week_start_date, week_end_date,
                    title_ru, target_co2_saved_grams
                ) VALUES ($1, $2, $3, $4, 'Test forest', 10000)
                ON CONFLICT (iso_year, iso_week) DO UPDATE SET
                    target_co2_saved_grams =
                        shared_forest_challenges.current_co2_saved_grams + 10000,
                    is_completed = false
                """,
                iso.year,
                iso.week,
                monday,
                monday + timedelta(days=6),
            )
            await _credit(connection, user_id, 2500)
            items = [CartLineInput(shop_item_id=DONATION_ID, quantity=5)]
            key = uuid7()
            order = await checkout(connection, user_id, key, items)
            assert order.remaining_points_balance == 600
            assert await checkout(connection, user_id, key, items) == order
            assert (
                await connection.fetchval(
                    """
                    SELECT contributed_co2_grams FROM shared_forest_contributions
                    WHERE user_id = $1
                    """,
                    user_id,
                )
                == 10000
            )
            assert (
                await connection.fetchval(
                    "SELECT lifetime_co2_saved_grams FROM users WHERE id = $1", user_id
                )
                == 10000
            )
            assert await connection.fetchval(
                """
                SELECT is_completed FROM shared_forest_challenges
                WHERE iso_year = $1 AND iso_week = $2
                """,
                iso.year,
                iso.week,
            )
            awards = await connection.fetch(
                "SELECT badge_code FROM user_badges WHERE user_id = $1", user_id
            )
            assert {row["badge_code"] for row in awards} == {"forest_guardian_10k", "co2_saver_5kg"}
        finally:
            await transaction.rollback()
            await connection.close()

    asyncio.run(purchase())


def test_steps_update_forest_and_award_badges_once(oauth_client: TestClient) -> None:
    session = exchange(oauth_client)
    bearer = {"Authorization": f"Bearer {session['access_token']}"}
    key = str(uuid7())
    headers = {**bearer, "Idempotency-Key": key}
    today = datetime.now(MOSCOW_OFFSET).date()
    body = {
        "activity_date": today.isoformat(),
        "raw_sensor_steps": 10000,
        "timezone_offset_minutes": 180,
        "stride_length_cm": 80,
    }
    forest_url = "/api/v1/challenges/shared-forest/current"
    badges_url = "/api/v1/badges"
    before = oauth_client.get(forest_url, headers=bearer)
    assert before.status_code == 200, before.text
    assert before.json()["my_contributed_co2_grams"] == 0
    steps = oauth_client.put("/api/v1/activity/steps/daily", json=body, headers=headers)
    assert steps.status_code == 200, steps.text
    summary = steps.json()
    assert summary["points_delta_applied"] == 100
    balance = summary["points_balance"]
    assert balance in (200, 250)
    repeat = oauth_client.put("/api/v1/activity/steps/daily", json=body, headers=headers)
    assert repeat.json()["points_balance"] == balance

    forest = oauth_client.get(forest_url, headers=bearer).json()
    assert forest["id"] == before.json()["id"]
    assert forest["my_contributed_co2_grams"] == summary["total_co2_saved_grams"]
    change = forest["current_co2_saved_grams"] - before.json()["current_co2_saved_grams"]
    assert change == summary["total_co2_saved_grams"]
    badges_response = oauth_client.get(badges_url, headers=bearer)
    assert badges_response.status_code == 200, badges_response.text
    badges = badges_response.json()
    assert badges["unlocked_count"] == 1
    badge = next(item for item in badges["badges"] if item["code"] == "first_10k_steps")
    assert badge["is_unlocked"]
    assert badge["awarded_at"]
    assert badge["current_value"] == 10000
    ledger = oauth_client.get(LEDGER_URL, headers=bearer).json()["items"]
    awards = [item["points_delta"] for item in ledger if item["operation_type"] == "badge_reward"]
    assert awards == [100]

    friend = exchange(oauth_client, "second-provider-code")
    friend_bearer = {"Authorization": f"Bearer {friend['access_token']}"}

    async def connect_friends() -> None:
        connection = await asyncpg.connect(os.environ["TEST_DATABASE_URL"])
        try:
            await connection.execute(
                """
                INSERT INTO friendships (requester_id, addressee_id, status)
                VALUES ($1, $2, 'accepted')
                """,
                UUID(friend["user"]["id"]),
                UUID(session["user"]["id"]),
            )
        finally:
            await connection.close()

    asyncio.run(connect_friends())
    ranking = oauth_client.get(forest_url, headers=friend_bearer).json()["top_friends_contributors"]
    (contributor,) = ranking
    assert contributor["user_id"] == session["user"]["id"]
    assert contributor["contributed_steps"] == 10000
    assert contributor["contributed_co2_grams"] == summary["total_co2_saved_grams"]
    privacy = oauth_client.patch(
        "/api/v1/users/me",
        headers={**bearer, "Idempotency-Key": str(uuid7())},
        json={"is_stats_visible_to_friends": False},
    )
    assert privacy.status_code == 200
    assert not oauth_client.get(forest_url, headers=friend_bearer).json()[
        "top_friends_contributors"
    ]


def test_mascot_inventory_lists_locked_and_earned_accessories(oauth_client: TestClient) -> None:
    session = exchange(oauth_client)
    bearer = {"Authorization": f"Bearer {session['access_token']}"}
    path = "/api/v1/mascot/inventory"
    inventory = oauth_client.get(path, headers=bearer)
    assert inventory.status_code == 200, inventory.text
    initial = {item["code"]: item for item in inventory.json()["accessories"]}
    assert initial["leaf_sprout_hat"]["is_unlocked"]
    assert not initial["knit_green_scarf"]["is_unlocked"]
    assert initial["knit_green_scarf"]["acquired_at"] is None
    _fund_shop_user(session["user"]["id"], 450)
    order = oauth_client.post(
        ORDER_URL,
        headers={**bearer, "Idempotency-Key": str(uuid7())},
        json={"items": [{"shop_item_id": "01950000-0000-7000-8000-000000000103", "quantity": 1}]},
    )
    assert order.status_code == 201, order.text
    updated = oauth_client.get(path, headers=bearer)
    scarf = next(
        item for item in updated.json()["accessories"] if item["code"] == "knit_green_scarf"
    )
    assert scarf["is_unlocked"]
    assert scarf["acquired_at"]
    assert not scarf["is_equipped"]
    equip_url = "/api/v1/users/me/mascot/accessory"
    headers = {**bearer, "Idempotency-Key": str(uuid7())}
    missing = oauth_client.put(equip_url, headers=headers, json={"accessory_code": "unknown"})
    assert missing.status_code == 404
    locked = oauth_client.put(equip_url, headers=headers, json={"accessory_code": "solar_shades"})
    assert locked.status_code == 403
    equipped = oauth_client.put(
        equip_url, headers=headers, json={"accessory_code": "knit_green_scarf"}
    )
    assert equipped.status_code == 200, equipped.text
    assert equipped.json()["mascot"]["equipped_accessory_code"] == "knit_green_scarf"
    removed = oauth_client.put(
        equip_url,
        headers={**bearer, "Idempotency-Key": str(uuid7())},
        json={"accessory_code": None},
    )
    assert removed.json()["mascot"]["equipped_accessory_code"] is None


def test_google_lab_requires_phone_and_account_erasure_deletes_session(
    oauth_client: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    # Settings are loaded when the application enters its lifespan.
    monkeypatch.setattr(app.state.settings, "academic_lab_allow_google_oauth", True)
    session = exchange(oauth_client, provider="google")
    headers = {
        "Authorization": f"Bearer {session['access_token']}",
        "Idempotency-Key": str(uuid7()),
    }
    assert session["is_foreign_provider_lab_mode"] is True
    assert session["user"]["requires_formal_phone"] is True
    assert oauth_client.get("/api/v1/badges", headers=headers).json()["error_code"] == (
        "GOOGLE_FORMAL_PHONE_REQUIRED"
    )
    bad = oauth_client.post(
        "/api/v1/auth/google-phone", headers=headers, json={"formal_phone_e164": "123"}
    )
    assert bad.json()["error_code"] == "INVALID_FORMAL_PHONE_E164"
    phone = oauth_client.post(
        "/api/v1/auth/google-phone", headers=headers, json={"formal_phone_e164": "+79990000000"}
    )
    assert phone.status_code == 200, phone.text
    assert phone.json()["requires_formal_phone"] is False
    assert oauth_client.get("/api/v1/badges", headers=headers).status_code == 200
    _fund_shop_user(session["user"]["id"], 100)
    bad_delete = oauth_client.request(
        "DELETE",
        "/api/v1/users/me",
        headers=headers,
        json={"confirmation_phrase": "NO", "deletion_reason": "Test"},
    )
    assert bad_delete.json()["error_code"] == "FZ152_INVALID_CONFIRMATION_PHRASE"
    erased = oauth_client.request(
        "DELETE",
        "/api/v1/users/me",
        headers=headers,
        json={"confirmation_phrase": "DELETE_MY_DATA_152FZ", "deletion_reason": "Test"},
    )
    assert erased.status_code == 200, erased.text
    receipt = erased.json()
    assert len(receipt["anonymized_user_hash"]) == len(receipt["verification_signature"]) == 64
    assert oauth_client.get("/api/v1/users/me", headers=headers).status_code == 401

    async def check_deleted() -> None:
        connection = await asyncpg.connect(os.environ["TEST_DATABASE_URL"])
        try:
            user_id = UUID(session["user"]["id"])
            assert not await connection.fetchval("SELECT 1 FROM users WHERE id = $1", user_id)
            assert not await connection.fetchval(
                "SELECT 1 FROM point_ledger WHERE user_id = $1", user_id
            )
            status = await connection.execute(
                "DELETE FROM fz152_account_deletion_log WHERE id = $1", UUID(receipt["receipt_id"])
            )
            assert status == "DELETE 1"
        finally:
            await connection.close()

    asyncio.run(check_deleted())


def test_friendship_and_nudge_with_push_registration(oauth_client: TestClient) -> None:
    first = exchange(oauth_client)
    second = exchange(oauth_client, "second-provider-code")
    alice = {"Authorization": f"Bearer {first['access_token']}"}
    bob = {"Authorization": f"Bearer {second['access_token']}"}
    request_headers = {**alice, "Idempotency-Key": str(uuid7())}
    request = {"friend_code": second["user"]["friend_code"]}
    sent = oauth_client.post("/api/v1/friends/requests", headers=request_headers, json=request)
    assert sent.status_code == 201, sent.text
    assert (
        oauth_client.post("/api/v1/friends/requests", headers=request_headers, json=request).json()
        == sent.json()
    )
    request_id = sent.json()["id"]
    friends = oauth_client.get("/api/v1/friends", headers=bob)
    assert friends.status_code == 200, friends.text
    assert friends.json()["incoming_requests"][0]["friendship_id"] == request_id
    answer = oauth_client.patch(
        f"/api/v1/friends/requests/{request_id}",
        headers={**bob, "Idempotency-Key": str(uuid7())},
        json={"action": "accept"},
    )
    assert answer.status_code == 200, answer.text
    assert answer.json()["status"] == "accepted"
    board = oauth_client.get("/api/v1/friends/leaderboard", headers=alice)
    assert board.status_code == 200, board.text
    assert len(board.json()["entries"]) == 2
    token = uuid4().hex
    push = oauth_client.post(
        "/api/v1/push/tokens",
        headers={**bob, "Idempotency-Key": str(uuid7())},
        json={"platform": "fcm_android", "token": token, "device_id": "example-device"},
    )
    assert push.status_code == 200, push.text
    assert push.json()["is_enabled"]
    nudge_url = f"/api/v1/friends/{second['user']['id']}/nudge"
    nudge_key = {**alice, "Idempotency-Key": str(uuid7())}
    nudge = oauth_client.post(nudge_url, headers=nudge_key)
    assert nudge.status_code == 200, nudge.text
    assert nudge.json()["push_delivered"] is False
    assert oauth_client.post(nudge_url, headers=nudge_key).json() == nudge.json()
    cooldown = oauth_client.post(nudge_url, headers={**alice, "Idempotency-Key": str(uuid7())})
    assert cooldown.status_code == 429
    assert oauth_client.delete(f"/api/v1/push/tokens/{token}", headers=bob).status_code == 204
    removed = oauth_client.delete(
        f"/api/v1/friends/{second['user']['id']}",
        headers={**alice, "Idempotency-Key": str(uuid7())},
    )
    assert removed.status_code == 204


def test_recycling_point_report_updates_trust_and_rewards_once(oauth_client: TestClient) -> None:
    session = exchange(oauth_client)
    bearer = {"Authorization": f"Bearer {session['access_token']}"}
    root = "/api/v1/map/waste-points"
    key = uuid7()
    suggestion = {
        "title": "Test recycling",
        "accepted_fractions": ["glass"],
        "lat": 0.1,
        "lon": (key.int % 100000) / 10000,
    }
    created = oauth_client.post(
        f"{root}/suggestions", headers={**bearer, "Idempotency-Key": str(key)}, json=suggestion
    )
    assert created.status_code == 201, created.text
    detail = created.json()
    assert detail["status"] == "unverified"
    assert detail["sources"][0]["source_type"] == "community_verified"
    point_id = detail["id"]
    report = {
        "report_type": "confirm_working",
        "user_lat": suggestion["lat"],
        "user_lon": suggestion["lon"],
    }
    report_key = {**bearer, "Idempotency-Key": str(uuid7())}
    bbox = {
        "min_lat": 0,
        "max_lat": 1,
        "min_lon": suggestion["lon"] - 0.1,
        "max_lon": suggestion["lon"] + 0.1,
        "fractions": "glass,paper",
        "include_unverified": "true",
    }
    try:
        before = oauth_client.get(root, headers=bearer, params={**bbox, "zoom": 14})
        assert before.status_code == 200, before.text
        original = next(point for point in before.json()["points"] if point["id"] == point_id)
        assert original["status"] == "unverified"
        submitted = oauth_client.post(f"{root}/{point_id}/reports", headers=report_key, json=report)
        assert submitted.status_code == 201, submitted.text
        data = submitted.json()
        assert (data["updated_status"], data["updated_trust_score"]) == ("active", 55)
        assert (
            oauth_client.post(f"{root}/{point_id}/reports", headers=report_key, json=report).json()
            == data
        )
        replay_ledger = oauth_client.get(LEDGER_URL, headers=bearer).json()
        assert (replay_ledger["points_balance"], replay_ledger["total_count"]) == (15, 1)
        for zoom in (11, 14):
            view = oauth_client.get(root, headers=bearer, params={**bbox, "zoom": zoom})
            assert view.status_code == 200, view.text
            payload = WastePointsBboxResponse.model_validate_json(view.content)
            assert payload.total_returned == len(payload.points)
            point = next(item for item in payload.points if item.id == UUID(point_id))
            assert point.status == "active"
            assert point.trust_score == 55
    finally:

        async def remove_point() -> None:
            connection = await asyncpg.connect(os.environ["TEST_DATABASE_URL"])
            try:
                async with connection.transaction():
                    await connection.execute(
                        "DELETE FROM waste_points WHERE id = $1", UUID(point_id)
                    )
                    await connection.execute(
                        "DELETE FROM rso_source_records WHERE external_record_id = $1", str(key)
                    )
            finally:
                await connection.close()

        asyncio.run(remove_point())
