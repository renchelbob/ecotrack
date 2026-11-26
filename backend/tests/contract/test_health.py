import os

import pytest
from fastapi.testclient import TestClient

from app.main import app


def test_probes_when_postgres_is_unavailable(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("DATABASE_URL", "postgresql://invalid:invalid@127.0.0.1:1/invalid")
    with TestClient(app) as client:
        health = client.get("/healthz")
        assert health.status_code == 200
        assert health.json()["status"] == "ok"
        readiness = client.get("/readyz")
        assert readiness.status_code == 503
        payload = readiness.json()
        assert payload["error_code"] == "DATABASE_UNAVAILABLE"
        assert set(payload) == {"error_code", "message", "details", "trace_id", "timestamp"}


@pytest.mark.skipif("TEST_DATABASE_URL" not in os.environ, reason="requires real PostGIS")
def test_ready_with_postgis(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("DATABASE_URL", os.environ["TEST_DATABASE_URL"])
    with TestClient(app) as client:
        readiness = client.get("/readyz")
        assert readiness.status_code == 200
        payload = readiness.json()
        assert payload["postgres_connected"] is True
        assert payload["postgis_version"].startswith("3.5")
