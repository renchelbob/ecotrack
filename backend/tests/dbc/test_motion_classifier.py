import pytest

from app.domain.motion_classifier import MotionRejected, classify_interval


def test_reboot_uses_counter_since_restart() -> None:
    interval = classify_interval(12, 15, 5, 100, 10)
    assert interval.delta_steps == 10
    assert interval.motion_class == "walking"


def test_vehicle_motion_and_poor_accuracy() -> None:
    assert classify_interval(120, 30, 5, 100, 101).motion_class == "vehicle_suspected"
    assert classify_interval(120, 30, 66, 100, 101).motion_class == "unknown"


@pytest.mark.parametrize(
    ("distance", "elapsed", "steps", "error_code"),
    [
        (300, 5, 10, "ANTIFRAUD_SPEED_SPOOFING_DETECTED"),
        (30, 15, 100, "ANTIFRAUD_STEP_SPIKE_DETECTED"),
    ],
)
def test_excessive_speed_and_cadence_are_rejected(
    distance: int, elapsed: int, steps: int, error_code: str
) -> None:
    with pytest.raises(MotionRejected, match=error_code):
        classify_interval(distance, elapsed, 5, 100, 100 + steps)
