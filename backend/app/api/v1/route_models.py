from datetime import date
from typing import Literal
from uuid import UUID

from pydantic import AwareDatetime, Field

from app.api.v1.activity_models import DailyActivitySummaryResponse
from app.api.v1.auth_models import ContractModel
from app.domain.motion_classifier import MotionClass

TransportModeCode = Literal[
    "bus", "metro", "tram", "personal_car", "car_compact", "car_sedan", "car_suv", "car_ev"
]
PG_INT_MAX = 2_147_483_647


class GpsTrackPointInput(ContractModel):
    seq_no: int = Field(ge=0, le=PG_INT_MAX, strict=True)
    recorded_at: AwareDatetime
    lat: float = Field(ge=-90, le=90)
    lon: float = Field(ge=-180, le=180)
    accuracy_m: float = Field(ge=0, le=3.4028234663852886e38, allow_inf_nan=False)
    speed_mps: float = Field(ge=0, le=3.4028234663852886e38, allow_inf_nan=False)
    cumulative_steps: int = Field(ge=0, le=PG_INT_MAX, strict=True)


class GpsTrackPointsBatchRequest(ContractModel):
    activity_date: date
    points: list[GpsTrackPointInput] = Field(min_length=1, max_length=500)


class GpsTrackPointsBatchResponse(ContractModel):
    track_id: UUID
    activity_date: date
    ingested_count: int
    total_point_count: int
    total_gps_walking_distance_m: float


class GpsTrackPointClassified(GpsTrackPointInput):
    delta_steps: int
    delta_distance_m: float
    motion_class: MotionClass


class LatLonPair(ContractModel):
    lat: float
    lon: float


class RouteSegmentAllocationInput(ContractModel):
    idempotency_key: UUID
    start_seq_no: int = Field(ge=0, le=PG_INT_MAX, strict=True)
    end_seq_no: int = Field(ge=1, le=PG_INT_MAX, strict=True)
    replaced_transport_mode: TransportModeCode


class RouteSegmentAllocationItem(RouteSegmentAllocationInput):
    id: UUID
    segment_distance_m: float
    segment_steps: int
    applied_co2_g_per_meter: float
    confidence_factor: float
    is_auto_calculated: bool
    co2_saved_grams: int
    coordinates: list[LatLonPair]


class ReplaceRouteAllocationsRequest(ContractModel):
    allocations: list[RouteSegmentAllocationInput] = Field(max_length=50)


class DailyActivityDetailResponse(ContractModel):
    summary: DailyActivitySummaryResponse
    is_editable: bool
    total_gps_walking_distance_m: float
    track_points: list[GpsTrackPointClassified]
    allocations: list[RouteSegmentAllocationItem]
    co2_delta_applied_grams: int
