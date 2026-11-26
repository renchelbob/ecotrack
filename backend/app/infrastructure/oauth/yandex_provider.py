from dataclasses import dataclass

import httpx
from pydantic import BaseModel, Field, ValidationError, field_validator

from app.api.errors import CatalogException
from app.config import Settings


@dataclass(frozen=True, slots=True)
class OAuthIdentity:
    subject: str
    display_name: str
    email: str | None
    avatar_url: str | None


class YandexToken(BaseModel):
    access_token: str = Field(min_length=1)


class YandexProfile(BaseModel):
    id: str = Field(min_length=1, max_length=255)
    display_name: str | None = None
    real_name: str | None = None
    default_email: str | None = Field(default=None, max_length=254)
    default_avatar_id: str | None = Field(default=None, pattern=r"^[a-zA-Z0-9/_-]+$")
    is_avatar_empty: bool = True

    @field_validator("default_avatar_id")
    @classmethod
    def prevent_relative_segments(cls, value: str | None) -> str | None:
        if value is not None and any(not part for part in value.split("/")):
            return None
        return value


async def exchange_yandex_code(
    settings: Settings,
    authorization_code: str,
    verifier: str,
) -> OAuthIdentity:
    secret = settings.yandex_oauth_client_secret
    client_id = settings.yandex_oauth_client_id
    if not client_id or client_id.startswith("mock_") or secret is None:
        raise CatalogException("OAUTH_PROVIDER_UNAVAILABLE")
    if not secret.get_secret_value() or secret.get_secret_value().startswith("mock_"):
        raise CatalogException("OAUTH_PROVIDER_UNAVAILABLE")
    try:
        async with httpx.AsyncClient(timeout=5.0, follow_redirects=False) as client:
            response = await client.post(
                "https://oauth.yandex.ru/token",
                auth=(client_id, secret.get_secret_value()),
                data={
                    "grant_type": "authorization_code",
                    "code": authorization_code,
                    "code_verifier": verifier,
                },
            )
            _check_response(response)
            token = YandexToken.model_validate_json(response.content)
            response = await client.get(
                "https://login.yandex.ru/info",
                params={"format": "json"},
                headers={"Authorization": f"OAuth {token.access_token}"},
            )
            _check_response(response)
            profile = YandexProfile.model_validate_json(response.content)
    except (httpx.RequestError, ValidationError) as exc:
        raise CatalogException("OAUTH_PROVIDER_UNAVAILABLE") from exc

    name = (profile.display_name or profile.real_name or "").strip()[:80].strip()
    avatar = None
    if not profile.is_avatar_empty and profile.default_avatar_id is not None:
        avatar = f"https://avatars.yandex.net/get-yapic/{profile.default_avatar_id}/islands-200"
    return OAuthIdentity(profile.id, name or "Пользователь EcoTrack", profile.default_email, avatar)


def _check_response(response: httpx.Response) -> None:
    if response.is_success:
        return
    if response.status_code >= 500 or response.status_code == 429:
        raise CatalogException("OAUTH_PROVIDER_UNAVAILABLE")
    raise CatalogException("OAUTH_CODE_EXCHANGE_FAILED")
