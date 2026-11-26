import asyncio
import os
from collections.abc import Iterator
from datetime import UTC, datetime, timedelta
from pathlib import Path
from uuid import uuid4, uuid7

import asyncpg
import jwt
import pytest
import schemathesis
import yaml
from hypothesis import settings
from schemathesis.checks import content_type_conformance, response_schema_conformance
from schemathesis.checks import status_code_conformance
from starlette.applications import Starlette
from starlette.requests import Request
from starlette.responses import JSONResponse
from starlette.routing import Mount, Route

from app.api.v1 import auth_routes
from app.application.auth_service import token_hash
from app.config import Settings
from app.infrastructure.oauth.yandex_provider import OAuthIdentity
from app.main import app

pytestmark = pytest.mark.skipif("TEST_DATABASE_URL" not in os.environ, reason="requires PostGIS")
CONTRACT = Path(__file__).resolve().parents[3] / "contracts" / "openapi.yaml"


@pytest.fixture
def access_token(monkeypatch: pytest.MonkeyPatch) -> Iterator[str]:
    dsn = os.environ["TEST_DATABASE_URL"]
    secret = uuid4().hex + uuid4().hex
    user_id = uuid4()
    session_id = uuid4()
    fingerprint = str(uuid4())
    subject = f"schemathesis-{uuid4()}"
    suffix = uuid4().hex.upper()
    monkeypatch.setenv("DATABASE_URL", dsn)
    monkeypatch.setenv("JWT_SECRET_KEY", secret)
    monkeypatch.setenv("FZ152_DELETION_HMAC_SECRET", uuid4().hex + uuid4().hex)
    monkeypatch.setenv("ACADEMIC_LAB_ALLOW_GOOGLE_OAUTH", "false")

    async def exchange(_settings: Settings, _code: str, _verifier: str) -> OAuthIdentity:
        return OAuthIdentity(subject, "Contract check", None, None)

    monkeypatch.setattr(auth_routes, "exchange_yandex_code", exchange)
    now = datetime.now(UTC)

    async def seed() -> None:
        connection = await asyncpg.connect(dsn)
        try:
            await connection.execute(
                "INSERT INTO users (id, display_name, friend_code) VALUES ($1, 'Contract user', $2)",
                user_id, f"ECO-{suffix[:4]}-{suffix[4:8]}",
            )
            await connection.execute(
                """
                INSERT INTO auth_refresh_sessions (id, user_id, token_hash, device_fingerprint, expires_at)
                VALUES ($1, $2, $3, $4, $5)
                """,
                session_id, user_id, token_hash(str(uuid4())), fingerprint, now + timedelta(hours=1),
            )
            await connection.execute(
                """
                INSERT INTO fz152_consent_journal (user_id, policy_version, action, consent_scope)
                VALUES ($1, 'contract-test', 'granted',
                        '{"personal_data_152fz":true,"health_steps_sensor":true,
                          "background_geolocation":true}')
                """,
                user_id,
            )
        finally:
            await connection.close()

    async def clean() -> None:
        connection = await asyncpg.connect(dsn)
        try:
            async with connection.transaction():
                await connection.execute("SET LOCAL ecotrack.in_152fz_account_erasure = 'true'")
                await connection.execute(
                    """
                    DELETE FROM users WHERE id = $1 OR id IN (
                        SELECT user_id FROM user_oauth_identities
                        WHERE provider_subject_id = $2
                    )
                    """,
                    user_id, subject,
                )
        finally:
            await connection.close()

    asyncio.run(seed())
    try:
        yield jwt.encode(
            {"sub": str(user_id), "jti": str(session_id), "fp": fingerprint,
             "iat": int(now.timestamp()), "exp": int(now.timestamp()) + 3600},
            secret, algorithm="HS256",
        )
    finally:
        asyncio.run(clean())


@pytest.fixture
def api_schema(access_token: str):
    async def canonical_schema(_request: Request) -> JSONResponse:
        return JSONResponse(yaml.safe_load(CONTRACT.read_text(encoding="utf-8")))

    # Use the canonical input document and forward generated calls to the actual API.
    harness = Starlette(
        routes=[Route("/__test_schema.json", canonical_schema), Mount("/", app)],
        lifespan=lambda _: app.router.lifespan_context(app),
    )
    return schemathesis.openapi.from_asgi("/__test_schema.json", harness)


@schemathesis.pytest.from_fixture("api_schema").parametrize()
@settings(max_examples=10, deadline=None)
def test_generated_cases_follow_contract(case: schemathesis.Case, access_token: str) -> None:
    headers = {"Authorization": f"Bearer {access_token}"}
    if case.method.upper() in {"POST", "PUT", "PATCH", "DELETE"} and any(
        name.lower() == "idempotency-key" for name in (case.headers or {})
    ):
        headers["Idempotency-Key"] = str(uuid7())
    response = case.call(headers=headers)
    case.validate_response(
        response,
        checks=[status_code_conformance, content_type_conformance, response_schema_conformance],
    )
