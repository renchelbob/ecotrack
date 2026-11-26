from pathlib import Path
from typing import Literal

from pydantic import Field, SecretStr, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

APP_ROOT = Path(__file__).resolve().parents[1]
PROJECT_ROOT = APP_ROOT if (APP_ROOT / "contracts").is_dir() else APP_ROOT.parent


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=PROJECT_ROOT / ".env", extra="ignore")

    database_url: str
    db_pool_min_size: int = Field(default=4, ge=0)
    db_pool_max_size: int = Field(default=16, ge=1)
    jwt_secret_key: SecretStr | None = None
    jwt_access_token_ttl_seconds: int = Field(default=900, ge=60, le=3600)
    jwt_refresh_token_ttl_days: int = Field(default=30, ge=1, le=90)
    fz152_deletion_hmac_secret: SecretStr | None = None
    academic_lab_allow_google_oauth: bool = False
    google_oauth_client_id: str = ""
    google_oauth_client_secret: SecretStr | None = None
    google_oauth_redirect_uri: str = "ecotrack://auth/callback"
    push_provider_backend: Literal["noop", "fcm"] = "noop"
    fcm_service_account_json_path: Path = Path("/app/secrets/fcm-service-account.json")
    data_mos_ru_api_key: SecretStr | None = None
    yandex_oauth_client_id: str = ""
    yandex_oauth_client_secret: SecretStr | None = None
    yandex_oauth_redirect_uri: str = "ecotrack://auth/callback"

    @model_validator(mode="after")
    def validate_pool_bounds(self) -> Settings:
        if self.db_pool_min_size > self.db_pool_max_size:
            raise ValueError("DB_POOL_MIN_SIZE must be <= DB_POOL_MAX_SIZE")
        return self


def load_settings() -> Settings:
    return Settings.model_validate({})
