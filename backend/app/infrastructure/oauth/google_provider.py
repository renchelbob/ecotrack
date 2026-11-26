import httpx
from pydantic import BaseModel, Field, ValidationError

from app.api.errors import CatalogException
from app.config import Settings
from app.infrastructure.oauth.yandex_provider import OAuthIdentity


class GoogleToken(BaseModel):
    access_token: str = Field(min_length=1, repr=False)


class GoogleProfile(BaseModel):
    sub: str = Field(min_length=1, max_length=255)
    name: str = ""
    email: str | None = Field(default=None, max_length=254)
    email_verified: bool = False
    picture: str | None = None


async def exchange_google_code(
    settings: Settings, authorization_code: str, verifier: str
) -> OAuthIdentity:
    client_id = settings.google_oauth_client_id
    secret = settings.google_oauth_client_secret
    if (
        not settings.academic_lab_allow_google_oauth
        or not client_id
        or client_id.startswith("mock_")
    ):
        raise CatalogException("OAUTH_PROVIDER_UNAVAILABLE")
    data = {
        "grant_type": "authorization_code",
        "code": authorization_code,
        "code_verifier": verifier,
        "client_id": client_id,
        "redirect_uri": settings.google_oauth_redirect_uri,
    }
    if secret is not None:
        data["client_secret"] = secret.get_secret_value()
    try:
        async with httpx.AsyncClient(timeout=5, follow_redirects=False) as client:
            response = await client.post("https://oauth2.googleapis.com/token", data=data)
            _check_response(response)
            token = GoogleToken.model_validate_json(response.content)
            profile_response = await client.get(
                "https://openidconnect.googleapis.com/v1/userinfo",
                headers={"Authorization": f"Bearer {token.access_token}"},
            )
            _check_response(profile_response)
            profile = GoogleProfile.model_validate_json(profile_response.content)
    except (httpx.RequestError, ValidationError) as exc:
        raise CatalogException("OAUTH_PROVIDER_UNAVAILABLE") from exc
    return OAuthIdentity(
        profile.sub,
        profile.name.strip()[:80].strip() or "Пользователь EcoTrack",
        profile.email if profile.email_verified else None,
        profile.picture if (profile.picture or "").startswith("https://") else None,
    )


def _check_response(response: httpx.Response) -> None:
    if response.is_success:
        return
    if response.status_code >= 500 or response.status_code == 429:
        raise CatalogException("OAUTH_PROVIDER_UNAVAILABLE")
    raise CatalogException("OAUTH_CODE_EXCHANGE_FAILED")
