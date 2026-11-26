from datetime import date, datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, StrictBool, model_validator

from app.domain.vehicle_emissions import FuelType

OAuthProviderType = Literal["yandex", "vk", "google"]
ConsentActionType = Literal["granted", "updated", "revoked"]
MascotMoodState = Literal["sleepy", "neutral", "happy", "thriving", "squinting"]


class ContractModel(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)


class ConsentScopeObject(ContractModel):
    personal_data_152fz: StrictBool
    health_steps_sensor: StrictBool
    background_geolocation: StrictBool


class OAuthExchangeRequest(ContractModel):
    provider: OAuthProviderType
    authorization_code: str = Field(min_length=4, max_length=2048, repr=False)
    code_verifier: str = Field(min_length=43, max_length=128, repr=False)
    redirect_uri: str
    device_fingerprint: str = Field(min_length=8, max_length=128, repr=False)
    policy_version: str = Field(max_length=32)
    consent_scope: ConsentScopeObject


class TokenRefreshRequest(ContractModel):
    refresh_token: str = Field(min_length=32, max_length=512, repr=False)
    device_fingerprint: str = Field(min_length=8, max_length=128, repr=False)


class LogoutRequest(ContractModel):
    refresh_token: str = Field(min_length=32, max_length=512, repr=False)


class GoogleFormalPhoneRequest(ContractModel):
    formal_phone_e164: str = Field(pattern=r"^\+[1-9][0-9]{7,14}$")


class AccountDeletionRequest(ContractModel):
    deletion_reason: str = Field(min_length=3, max_length=128)
    confirmation_phrase: Literal["DELETE_MY_DATA_152FZ"]


class AccountDeletionReceiptResponse(ContractModel):
    receipt_id: UUID
    anonymized_user_hash: str = Field(min_length=64, max_length=64)
    purged_at: datetime
    verification_signature: str = Field(min_length=64, max_length=64)


class RecordConsentRequest(ContractModel):
    policy_version: str = Field(min_length=1, max_length=32)
    action: ConsentActionType
    consent_scope: ConsentScopeObject


class ConsentJournalEntry(RecordConsentRequest):
    id: UUID
    recorded_at: datetime


class ConsentHistoryListResponse(ContractModel):
    is_152fz_consent_active: bool
    entries: list[ConsentJournalEntry]


class MascotVisualState(ContractModel):
    mood: MascotMoodState
    daily_goal_progress_ratio: float = Field(ge=0)
    equipped_accessory_code: str | None
    unlocked_accessory_codes: list[str]


class UserVehicleResponse(ContractModel):
    id: UUID
    vehicle_name: str
    fuel: FuelType
    consumption_per_100km: float
    fuel_emission_factor_g_per_unit: float
    computed_co2_g_per_km: float
    computed_co2_g_per_meter: float
    updated_at: datetime


class UserProfileResponse(ContractModel):
    id: UUID
    email: str | None = None
    display_name: str = Field(min_length=1, max_length=80)
    avatar_url: str | None = None
    friend_code: str = Field(pattern=r"^ECO-[A-Z0-9]{4}-[A-Z0-9]{4}$")
    formal_phone_e164: str | None = None
    requires_formal_phone: bool
    points_balance: int = Field(ge=0)
    lifetime_points_earned: int = Field(ge=0)
    lifetime_co2_saved_grams: int = Field(ge=0)
    current_streak_days: int = Field(ge=0)
    longest_streak_days: int = Field(ge=0)
    streak_freeze_count: int = Field(ge=0)
    last_active_local_date: date | None = None
    daily_step_goal: int = Field(ge=1000, le=50000)
    daily_co2_goal_grams: int = Field(ge=100, le=20000)
    stride_length_cm: int = Field(ge=40, le=120)
    gps_interval_seconds: int = Field(ge=5, le=300)
    is_gps_tracking_enabled: bool
    is_stats_visible_to_friends: bool
    is_152fz_consent_active: bool
    mascot: MascotVisualState
    personal_vehicle: UserVehicleResponse | None = None
    created_at: datetime


class AuthSessionResponse(ContractModel):
    access_token: str = Field(repr=False)
    refresh_token: str = Field(repr=False)
    token_type: Literal["Bearer"]
    expires_in_seconds: int = Field(ge=60)
    is_foreign_provider_lab_mode: bool
    lab_mode_warning_banner: str | None
    user: UserProfileResponse


class UpdateUserProfileRequest(ContractModel):
    display_name: str | None = Field(default=None, min_length=1, max_length=80)
    avatar_url: str | None = None
    daily_step_goal: int | None = Field(default=None, ge=1000, le=50000, strict=True)
    daily_co2_goal_grams: int | None = Field(default=None, ge=100, le=20000, strict=True)
    stride_length_cm: int | None = Field(default=None, ge=40, le=120, strict=True)
    gps_interval_seconds: int | None = Field(default=None, ge=5, le=300, strict=True)
    is_gps_tracking_enabled: StrictBool | None = None
    is_stats_visible_to_friends: StrictBool | None = None

    @model_validator(mode="after")
    def validate_patch(self) -> UpdateUserProfileRequest:
        for name in self.model_fields_set - {"avatar_url"}:
            if getattr(self, name) is None:
                raise ValueError(f"{name} cannot be null")
        if self.display_name is not None and not self.display_name.strip():
            raise ValueError("display_name must not be blank")
        return self
