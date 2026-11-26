from pydantic import Field

from app.api.v1.auth_models import ContractModel
from app.api.v1.route_models import TransportModeCode
from app.domain.vehicle_emissions import FuelType


class UpsertUserVehicleRequest(ContractModel):
    vehicle_name: str = Field(min_length=1, max_length=80)
    fuel: FuelType
    consumption_per_100km: float = Field(gt=0, le=50, allow_inf_nan=False)


class TransportPresetItem(ContractModel):
    mode_code: TransportModeCode
    display_name_ru: str
    display_name_en: str
    co2_grams_per_km: float
    co2_grams_per_meter: float
    is_personal_vehicle_slot: bool


class TransportPresetListResponse(ContractModel):
    presets: list[TransportPresetItem]
