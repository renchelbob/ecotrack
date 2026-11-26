from decimal import Decimal
from typing import Literal

import icontract

ReportType = Literal[
    "confirm_working",
    "overflowing",
    "missing_bin",
    "wrong_fractions",
    "inaccessible",
    "photo_update",
]
BASE_TRUST_DELTA: dict[ReportType, Decimal] = {
    "confirm_working": Decimal(10),
    "overflowing": Decimal(-8),
    "missing_bin": Decimal(-25),
    "wrong_fractions": Decimal(-15),
    "inaccessible": Decimal(-12),
    "photo_update": Decimal(5),
}


def _valid_current(current: Decimal) -> bool:
    return Decimal(0) <= current <= Decimal(100)


def _valid_report_type(report_type: ReportType) -> bool:
    return report_type in BASE_TRUST_DELTA


def _valid_result(result: Decimal) -> bool:
    return Decimal(0) <= result <= Decimal(100)


@icontract.require(_valid_current)
@icontract.require(_valid_report_type)
@icontract.ensure(_valid_result)
def compute_new_trust_score(current: Decimal, report_type: ReportType) -> Decimal:
    return min(Decimal(100), max(Decimal(0), current + BASE_TRUST_DELTA[report_type]))
