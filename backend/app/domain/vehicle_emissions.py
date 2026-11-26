from dataclasses import dataclass
from decimal import ROUND_HALF_UP, Decimal
from enum import StrEnum
from types import MappingProxyType

import icontract


class FuelType(StrEnum):
    PETROL_92 = "petrol_92"
    PETROL_95 = "petrol_95"
    PETROL_98 = "petrol_98"
    DIESEL = "diesel"
    LPG = "lpg"
    CNG = "cng"
    HYBRID = "hybrid"
    ELECTRIC = "electric"


FUEL_GRAMS_PER_UNIT = MappingProxyType(
    {
        FuelType.PETROL_92: 2310,
        FuelType.PETROL_95: 2330,
        FuelType.PETROL_98: 2350,
        FuelType.DIESEL: 2680,
        FuelType.LPG: 1660,
        FuelType.CNG: 1960,
        FuelType.HYBRID: 2310,
        FuelType.ELECTRIC: 340,
    }
)


@dataclass(frozen=True, slots=True)
class VehicleEmissions:
    grams_per_km: Decimal
    grams_per_meter: Decimal


def _valid_consumption(consumption_per_100km: Decimal) -> bool:
    return consumption_per_100km.is_finite() and 0 < consumption_per_100km <= 50


def _nonnegative_factors(result: VehicleEmissions) -> bool:
    return result.grams_per_km >= 0 and result.grams_per_meter >= 0


@icontract.require(_valid_consumption)
@icontract.ensure(_nonnegative_factors)
def calculate_vehicle_emissions(fuel: FuelType, consumption_per_100km: Decimal) -> VehicleEmissions:
    grams_per_100km = consumption_per_100km * FUEL_GRAMS_PER_UNIT[fuel]
    return VehicleEmissions(
        grams_per_km=grams_per_100km.scaleb(-2).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP),
        grams_per_meter=grams_per_100km.scaleb(-5).quantize(
            Decimal("0.00001"), rounding=ROUND_HALF_UP
        ),
    )
