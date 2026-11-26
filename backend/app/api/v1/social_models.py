from datetime import date, datetime
from typing import Literal
from uuid import UUID

from pydantic import Field

from app.api.v1.auth_models import ContractModel

BadgeThreshold = Literal[
    "steps_total",
    "co2_grams_total",
    "streak_days",
    "rso_reports",
    "friends_count",
    "forest_contribution",
]


class MascotAccessoryItem(ContractModel):
    code: str
    name_ru: str
    slot: Literal["head", "neck", "glasses", "aura", "companion"]
    vector_layer_key: str
    unlock_type: Literal["starter", "shop", "badge", "streak"]
    is_unlocked: bool
    is_equipped: bool
    acquired_at: datetime | None = None


class MascotInventoryResponse(ContractModel):
    accessories: list[MascotAccessoryItem]


class EquipMascotAccessoryRequest(ContractModel):
    accessory_code: str | None = Field(max_length=64)


class BadgeCatalogProgressItem(ContractModel):
    code: str
    title_ru: str
    description_ru: str
    icon_vector_key: str
    threshold_type: BadgeThreshold
    threshold_value: int = Field(ge=1)
    current_value: int = Field(ge=0)
    reward_points: int = Field(ge=0)
    reward_accessory_code: str | None = None
    is_unlocked: bool
    awarded_at: datetime | None = None


class BadgesListResponse(ContractModel):
    unlocked_count: int = Field(ge=0)
    total_count: int = Field(ge=0)
    badges: list[BadgeCatalogProgressItem]


class SharedForestContributorItem(ContractModel):
    user_id: UUID
    display_name: str
    avatar_url: str | None = None
    contributed_co2_grams: int = Field(ge=0)
    contributed_steps: int = Field(ge=0)


class SharedForestChallengeResponse(ContractModel):
    id: UUID
    iso_year: int
    iso_week: int
    week_start_date: date
    week_end_date: date
    title_ru: str
    target_co2_saved_grams: int = Field(ge=1)
    current_co2_saved_grams: int = Field(ge=0)
    progress_ratio: float = Field(ge=0)
    trees_equivalent_planted: int = Field(ge=0)
    my_contributed_co2_grams: int = Field(ge=0)
    is_completed: bool
    top_friends_contributors: list[SharedForestContributorItem]
