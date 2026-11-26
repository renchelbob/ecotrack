from dataclasses import dataclass
from typing import Literal

import icontract

MotionClass = Literal["unknown", "walking", "indoor_pacing", "vehicle_suspected", "stationary"]


class MotionRejected(ValueError):
    """A track interval exceeded the configured measurement limits."""


@dataclass(frozen=True, slots=True)
class ClassifiedInterval:
    delta_steps: int
    motion_class: MotionClass


@icontract.require(lambda distance_m: distance_m >= 0)
@icontract.require(lambda elapsed_seconds: elapsed_seconds >= 1)
@icontract.require(lambda accuracy_m: accuracy_m >= 0)
@icontract.require(
    lambda previous_steps, cumulative_steps: previous_steps >= 0 and cumulative_steps >= 0
)
@icontract.ensure(lambda result: result.delta_steps >= 0)
@icontract.ensure(lambda accuracy_m, result: accuracy_m <= 65 or result.motion_class == "unknown")
@icontract.ensure(
    lambda distance_m, result: result.motion_class != "walking"
    or (result.delta_steps >= 4 and distance_m >= 6)
)
def classify_interval(
    distance_m: float,
    elapsed_seconds: float,
    accuracy_m: float,
    previous_steps: int,
    cumulative_steps: int,
) -> ClassifiedInterval:
    steps = (
        cumulative_steps - previous_steps
        if cumulative_steps >= previous_steps
        else cumulative_steps
    )
    elapsed = elapsed_seconds
    speed = distance_m / elapsed
    stride = distance_m / steps if steps else float("inf")
    if accuracy_m > 65:
        return ClassifiedInterval(steps, "unknown")
    if speed > 50 and distance_m > 250:
        raise MotionRejected("ANTIFRAUD_SPEED_SPOOFING_DETECTED")
    if elapsed >= 10 and steps / elapsed > 4.5:
        raise MotionRejected("ANTIFRAUD_STEP_SPIKE_DETECTED")
    if speed > 6.5 or (distance_m >= 25 and steps < 5) or (speed >= 2.5 and stride > 2.2):
        return ClassifiedInterval(steps, "vehicle_suspected")
    if steps >= 10 and distance_m < 6:
        return ClassifiedInterval(steps, "indoor_pacing")
    if steps < 4 and distance_m < 6:
        return ClassifiedInterval(steps, "stationary")
    if steps >= 4 and distance_m >= 6 and 0.30 <= stride <= 2.20 and speed <= 6.50:
        return ClassifiedInterval(steps, "walking")
    return ClassifiedInterval(steps, "unknown")
