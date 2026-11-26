import json
from datetime import UTC, datetime
from pathlib import Path
from uuid import uuid4

from fastapi import Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict


class ErrorDetailItem(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)
    field: str
    issue: str


class ErrorResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)
    error_code: str
    message: str
    details: list[ErrorDetailItem]
    trace_id: str
    timestamp: datetime


class CatalogEntry(BaseModel):
    http_status: int
    ui_message_ru: str


class ErrorCatalog(BaseModel):
    errors: dict[str, CatalogEntry]


def load_catalog(path: Path) -> ErrorCatalog:
    return ErrorCatalog.model_validate(json.loads(path.read_text(encoding="utf-8")))


class CatalogException(Exception):
    def __init__(self, code: str, details: list[ErrorDetailItem] | None = None) -> None:
        super().__init__(code)
        self.code = code
        self.details = details if details is not None else []


async def catalog_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    if not isinstance(exc, CatalogException):
        raise exc
    catalog: ErrorCatalog = request.app.state.error_catalog
    entry = catalog.errors[exc.code]
    payload = ErrorResponse(
        error_code=exc.code,
        message=entry.ui_message_ru,
        details=exc.details,
        trace_id=str(uuid4()),
        timestamp=datetime.now(UTC),
    )
    return JSONResponse(payload.model_dump(mode="json"), status_code=entry.http_status)
