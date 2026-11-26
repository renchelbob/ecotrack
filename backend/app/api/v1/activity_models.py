from datetime import date, datetime
from typing import Literal
from uuid import UUID

from pydantic import Field, field_validator

from app.api.v1.auth_models import ContractModel


class SyncDailyStepsRequest(ContractModel):
    activity_date: date
    timezone_offset_minutes: int = Field(ge=-720, le=840, strict=True)
    raw_sensor_steps: int = Field(ge=0, le=150000, strict=True)
    stride_length_cm: int | None = Field(default=None, ge=40, le=120, strict=True)

    @field_validator("stride_length_cm")
    @classmethod
    def validate_stride_length(cls, value: int | None) -> int:
        if value is None:
            raise ValueError("stride_length_cm cannot be null")
        return value


class DailyActivitySummaryResponse(ContractModel):
    id: UUID
    activity_date: date
    raw_sensor_steps: int
    validated_steps: int
    stride_length_cm: int
    total_step_distance_m: float
    allocated_gps_distance_m: float
    unallocated_step_distance_m: float
    allocated_co2_saved_grams: int
    auto_default_co2_saved_grams: int
    total_co2_saved_grams: int
    points_awarded_for_day: int
    points_delta_applied: int
    points_balance: int
    is_auto_calculated: bool
    antifraud_flagged: bool
    antifraud_reason: str | None = None
    last_synced_at: datetime


class PaginatedActivityHistoryResponse(ContractModel):
    total_count: int
    limit: int
    offset: int
    items: list[DailyActivitySummaryResponse]


Period = Literal["days", "weeks", "months"]


class EcoEquivalentsMetrics(ContractModel):
    total_co2_saved_grams: int
    trees_planted_equivalent: float
    car_km_avoided: float
    smartphone_charges_equivalent: int
    plastic_bottles_recycled_equivalent: int
    led_bulb_hours_equivalent: int


class EmissionsBucketItem(ContractModel):
    bucket_label: str
    start_date: date
    end_date: date
    validated_steps: int
    total_step_distance_m: float
    allocated_co2_saved_grams: int
    auto_default_co2_saved_grams: int
    total_co2_saved_grams: int


class EmissionsStatisticsResponse(ContractModel):
    period: Period
    period_total_co2_saved_grams: int
    period_total_steps: int
    period_total_distance_m: float
    buckets: list[EmissionsBucketItem]
    equivalents: EcoEquivalentsMetrics


class EcoEquivalentsResponse(ContractModel):
    lifetime: EcoEquivalentsMetrics
    current_week: EcoEquivalentsMetrics
