from dataclasses import dataclass
from decimal import ROUND_HALF_UP, Decimal

import icontract

BUS_GRAMS_PER_METER = Decimal("0.08200")
DEFAULT_TRANSPORT_SHARE = Decimal("0.80")
DEFAULT_CONFIDENCE = Decimal("0.70")


def round_grams(value: Decimal) -> int:
    return int(value.quantize(Decimal("1"), rounding=ROUND_HALF_UP))


def automatic_emissions(distance_m: Decimal) -> int:
    return round_grams(
        distance_m * DEFAULT_TRANSPORT_SHARE * BUS_GRAMS_PER_METER * DEFAULT_CONFIDENCE
    )


@dataclass(frozen=True, slots=True)
class SegmentEmission:
    distance_m: Decimal
    grams_per_meter: Decimal

    def __post_init__(self) -> None:
        for value in (self.distance_m, self.grams_per_meter):
            if not value.is_finite() or value < 0:
                raise ValueError("Distance and emission factor must be finite and nonnegative")


@dataclass(frozen=True, slots=True)
class DailyEmissions:
    step_distance_m: Decimal
    allocated_distance_m: Decimal
    unallocated_distance_m: Decimal
    allocated_grams: int
    auto_grams: int
    is_auto_calculated: bool

    @property
    def total_grams(self) -> int:
        return self.allocated_grams + self.auto_grams


def _valid_steps(validated_steps: int) -> bool:
    return 0 <= validated_steps <= 100_000


def _valid_stride(stride_length_cm: int) -> bool:
    return 40 <= stride_length_cm <= 120


def _nonnegative_emissions(result: DailyEmissions) -> bool:
    return result.total_grams >= 0


@icontract.require(_valid_steps)
@icontract.require(_valid_stride)
@icontract.ensure(_nonnegative_emissions)
def calculate_daily_emissions(
    validated_steps: int,
    stride_length_cm: int,
    segments: tuple[SegmentEmission, ...] = (),
) -> DailyEmissions:
    step_distance = Decimal(validated_steps * stride_length_cm).scaleb(-2)
    allocated_distance = sum((segment.distance_m for segment in segments), Decimal(0))
    unallocated_distance = max(Decimal(0), step_distance - allocated_distance)
    allocated_grams = sum(
        round_grams(segment.distance_m * segment.grams_per_meter) for segment in segments
    )
    auto_grams = automatic_emissions(unallocated_distance)
    return DailyEmissions(
        step_distance_m=step_distance,
        allocated_distance_m=allocated_distance,
        unallocated_distance_m=unallocated_distance,
        allocated_grams=allocated_grams,
        auto_grams=auto_grams,
        is_auto_calculated=not segments,
    )


def _valid_already_awarded(already_awarded: int) -> bool:
    return 0 <= already_awarded <= 1_000


def _valid_step_reward(result: int) -> bool:
    return 0 <= result <= 1_000


@icontract.require(_valid_steps)
@icontract.require(_valid_already_awarded)
@icontract.ensure(_valid_step_reward)
def calculate_step_reward_delta(validated_steps: int, already_awarded: int) -> int:
    return max(0, validated_steps // 100 - already_awarded)
