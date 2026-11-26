import os
from uuid import uuid4

import pytest
import schemathesis
from hypothesis import settings

from app.main import app

pytestmark = pytest.mark.skipif("TEST_DATABASE_URL" not in os.environ, reason="requires PostGIS")


@pytest.fixture
def api_schema(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("DATABASE_URL", os.environ["TEST_DATABASE_URL"])
    monkeypatch.setenv("JWT_SECRET_KEY", uuid4().hex + uuid4().hex)
    monkeypatch.setenv("ACADEMIC_LAB_ALLOW_GOOGLE_OAUTH", "false")
    monkeypatch.setenv("YANDEX_OAUTH_CLIENT_ID", "mock_contract_test")
    return schemathesis.openapi.from_asgi("/openapi.json", app)


@schemathesis.pytest.from_fixture("api_schema").parametrize()
@settings(max_examples=2, deadline=None)
def test_generated_requests_do_not_crash(case: schemathesis.Case) -> None:
    response = case.call()
    if response.status_code == 503:
        assert response.json()["error_code"] == "OAUTH_PROVIDER_UNAVAILABLE"
    else:
        assert response.status_code < 500, response.text
