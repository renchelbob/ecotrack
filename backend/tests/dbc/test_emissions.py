from decimal import Decimal

from app.domain.hybrid_co2 import (
    SegmentEmission,
    calculate_daily_emissions,
    calculate_step_reward_delta,
)
from app.domain.vehicle_emissions import FuelType, calculate_vehicle_emissions


def test_step_distance_and_automatic_estimate() -> None:
    result = calculate_daily_emissions(5000, 80)
    assert result.step_distance_m == 4000
    assert result.total_grams == 184
    assert result.is_auto_calculated


def test_gps_distance_exceeding_step_estimate_keeps_segment_emissions() -> None:
    result = calculate_daily_emissions(
        100, 80, (SegmentEmission(Decimal(125), Decimal("0.02800")),)
    )
    assert result.unallocated_distance_m == 0
    assert result.total_grams == 4  # 3.5 g rounds upward.
    assert not result.is_auto_calculated


def test_vehicle_emissions_in_both_units() -> None:
    result = calculate_vehicle_emissions(FuelType.PETROL_95, Decimal("8.5"))
    assert result.grams_per_km == Decimal("198.05")
    assert result.grams_per_meter == Decimal("0.19805")


def test_step_rewards_are_not_awarded_again() -> None:
    assert calculate_step_reward_delta(5000, 50) == 0
    assert calculate_step_reward_delta(5200, 50) == 2
