from pathlib import Path

import yaml

from app.main import app

HTTP_METHODS = {"get", "post", "put", "patch", "delete"}


def test_all_contract_operations_are_registered_with_expected_success_status() -> None:
    path = Path(__file__).resolve().parents[3] / "contracts" / "openapi.yaml"
    contract = yaml.safe_load(path.read_text(encoding="utf-8"))
    actual = app.openapi()["paths"]
    expected_operations = {
        (path, method): spec
        for path, routes in contract["paths"].items()
        for method, spec in routes.items()
        if method in HTTP_METHODS
    }
    assert len(expected_operations) == 44
    assert {(path, method) for path, routes in actual.items() for method in routes} == (
        expected_operations.keys()
    )
    for (path, method), spec in expected_operations.items():
        operation = actual[path][method]
        assert operation["operationId"] == spec["operationId"]
        success = {key for key in spec["responses"] if key.startswith("2")}
        assert success <= operation["responses"].keys()
