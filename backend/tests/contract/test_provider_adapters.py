from collections.abc import Callable
from pathlib import Path
from urllib.parse import parse_qs
from uuid import uuid4

import httpx
import jwt
import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from pydantic import SecretStr

from app.config import Settings
from app.etl import mos_ru_ingestor
from app.infrastructure.oauth import google_provider, yandex_provider
from app.infrastructure.push.fcm_provider import FcmPushProvider, ServiceAccount


def _mock_async_transport(
    monkeypatch: pytest.MonkeyPatch,
    handler: Callable[[httpx.Request], httpx.Response],
) -> None:
    client_type = httpx.AsyncClient

    def client(**kwargs: object) -> httpx.AsyncClient:
        return client_type(transport=httpx.MockTransport(handler), **kwargs)

    monkeypatch.setattr(httpx, "AsyncClient", client)


@pytest.mark.asyncio
async def test_yandex_exchange_passes_pkce_and_reads_subject(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    access = uuid4().hex
    calls: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        calls.append(request.url.host)
        if request.url.host == "oauth.yandex.ru":
            fields = parse_qs(request.content.decode())
            assert fields["code_verifier"] == ["v" * 43]
            assert fields["code"] == ["test-code"]
            assert request.headers["authorization"].startswith("Basic ")
            return httpx.Response(200, json={"access_token": access})
        assert request.url.host == "login.yandex.ru"
        assert request.headers["authorization"] == f"OAuth {access}"
        return httpx.Response(200, json={"id": "test-yandex", "display_name": " Test user "})

    _mock_async_transport(monkeypatch, handler)
    settings = Settings(
        database_url="postgresql://localhost/ecotrack",
        yandex_oauth_client_id="test-client",
        yandex_oauth_client_secret=SecretStr(uuid4().hex),
    )
    identity = await yandex_provider.exchange_yandex_code(settings, "test-code", "v" * 43)
    assert (identity.subject, identity.display_name) == ("test-yandex", "Test user")
    assert calls == ["oauth.yandex.ru", "login.yandex.ru"]


@pytest.mark.asyncio
async def test_google_exchange_omits_unverified_email(monkeypatch: pytest.MonkeyPatch) -> None:
    access = uuid4().hex

    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.host == "oauth2.googleapis.com":
            fields = parse_qs(request.content.decode())
            assert fields["code_verifier"] == ["v" * 43]
            assert fields["redirect_uri"] == ["https://example.test/callback"]
            return httpx.Response(200, json={"access_token": access})
        assert request.url.host == "openidconnect.googleapis.com"
        assert request.headers["authorization"] == f"Bearer {access}"
        return httpx.Response(
            200,
            json={
                "sub": "test-google",
                "name": "Google user",
                "email": "user@example.test",
                "email_verified": False,
            },
        )

    _mock_async_transport(monkeypatch, handler)
    settings = Settings(
        database_url="postgresql://localhost/ecotrack",
        academic_lab_allow_google_oauth=True,
        google_oauth_client_id="test-client",
        google_oauth_redirect_uri="https://example.test/callback",
    )
    identity = await google_provider.exchange_google_code(settings, "test-code", "v" * 43)
    assert identity.subject == "test-google"
    assert identity.email is None


@pytest.mark.asyncio
async def test_fcm_signs_service_account_request_and_reuses_access(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    access = uuid4().hex
    device = uuid4().hex
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    email = "test-fcm@example.test"
    account = ServiceAccount(
        project_id="ecotrack-test",
        client_email=email,
        private_key=key.private_bytes(
            serialization.Encoding.PEM,
            serialization.PrivateFormat.PKCS8,
            serialization.NoEncryption(),
        ).decode(),
    )
    account_path = tmp_path / "fcm-test.json"
    account_path.write_text(account.model_dump_json(), encoding="utf-8")
    calls: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        calls.append(request.url.host)
        if request.url.host == "oauth2.googleapis.com":
            fields = parse_qs(request.content.decode())
            claims = jwt.decode(
                fields["assertion"][0],
                key.public_key(),
                algorithms=["RS256"],
                audience="https://oauth2.googleapis.com/token",
                issuer=email,
            )
            assert claims["scope"] == "https://www.googleapis.com/auth/firebase.messaging"
            return httpx.Response(200, json={"access_token": access, "expires_in": 3600})
        assert request.url.path == "/v1/projects/ecotrack-test/messages:send"
        assert request.headers["authorization"] == f"Bearer {access}"
        assert device.encode() in request.content
        assert b"ecotrack://home" in request.content
        return httpx.Response(200, json={"name": "projects/ecotrack-test/messages/1"})

    _mock_async_transport(monkeypatch, handler)
    provider = FcmPushProvider(account_path)
    assert await provider.send_wakeup_nudge([device], "Test sender")
    assert await provider.send_wakeup_nudge([device], "Test sender")
    assert calls == ["oauth2.googleapis.com", "fcm.googleapis.com", "fcm.googleapis.com"]


def test_moscow_dataset_import_reads_multiple_pages(monkeypatch: pytest.MonkeyPatch) -> None:
    client_type = httpx.Client
    offsets: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.host == "apidata.mos.ru"
        assert request.url.path == "/v1/datasets/42/rows"
        offset = request.url.params["$skip"]
        offsets.append(offset)
        page = [
            {
                "global_id": row,
                "Cells": {
                    "Name": f"Point {row}",
                    "geoData": {"type": "Point", "coordinates": [37.62, 55.75]},
                },
            }
            for row in (1, 2)
            if offset == "0"
        ]
        return httpx.Response(200, json=page)

    def client(**kwargs: object) -> httpx.Client:
        return client_type(transport=httpx.MockTransport(handler), **kwargs)

    key = uuid4().hex
    monkeypatch.setattr(httpx, "Client", client)
    monkeypatch.setattr(mos_ru_ingestor, "PAGE_SIZE", 2)
    rows = list(mos_ru_ingestor.read_mos_dataset(42, key, ["glass"]))
    assert offsets == ["0", "2"]
    assert [(row.external_id, row.fractions) for row in rows] == [
        ("42:1", ["glass"]),
        ("42:2", ["glass"]),
    ]
