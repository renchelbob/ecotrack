from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import Field

from app.api.v1.auth_models import ContractModel
from app.domain.rso_trust import ReportType

WasteFraction = Literal[
    "plastic",
    "glass",
    "paper",
    "metal",
    "tetra_pak",
    "batteries",
    "electronics",
    "clothes",
    "hazardous",
    "caps",
    "mixed_recyclables",
    "general_bin",
]
WasteStatus = Literal["active", "unverified", "temporarily_closed", "removed"]
SourceType = Literal["osm_pbf", "data_mos_ru", "municipal_registry", "community_verified"]


class WastePointMapItem(ContractModel):
    id: UUID
    title: str
    address_text: str | None = None
    accepted_fractions: list[WasteFraction] = Field(min_length=1)
    lat: float
    lon: float
    status: WasteStatus
    trust_score: float = Field(ge=0, le=100)
    confirmations_count: int = Field(ge=0)
    issues_count: int = Field(ge=0)


class WastePointsBboxResponse(ContractModel):
    attribution_banner_ru: str
    total_returned: int = Field(ge=0)
    points: list[WastePointMapItem]


class LinkedSourceRecordItem(ContractModel):
    source_record_id: UUID
    source_type: SourceType
    external_record_id: str
    license_name: str
    match_distance_m: float


class WastePointReportItem(ContractModel):
    id: UUID
    report_type: ReportType
    comment: str | None = None
    distance_to_point_m: float
    trust_delta: float
    created_at: datetime


class WastePointDetailResponse(WastePointMapItem):
    operator_name: str | None = None
    opening_hours: str | None = None
    attribution_text: str
    last_verified_at: datetime | None = None
    sources: list[LinkedSourceRecordItem]
    recent_reports: list[WastePointReportItem]
    updated_at: datetime


class SubmitWastePointReportRequest(ContractModel):
    report_type: ReportType
    comment: str | None = Field(default=None, max_length=500)
    user_lat: float = Field(ge=-90, le=90)
    user_lon: float = Field(ge=-180, le=180)


class WastePointReportCreatedResponse(ContractModel):
    report: WastePointReportItem
    updated_trust_score: float
    updated_status: WasteStatus
    points_rewarded: int = Field(ge=0)


class SuggestWastePointRequest(ContractModel):
    title: str = Field(min_length=3, max_length=160)
    address_text: str | None = Field(default=None, max_length=255)
    operator_name: str | None = Field(default=None, max_length=120)
    opening_hours: str | None = Field(default=None, max_length=160)
    accepted_fractions: list[WasteFraction] = Field(min_length=1, max_length=12)
    lat: float = Field(ge=-90, le=90)
    lon: float = Field(ge=-180, le=180)
    comment: str | None = Field(default=None, max_length=500)
