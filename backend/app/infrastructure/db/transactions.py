from collections.abc import Awaitable, Callable
from functools import wraps

import asyncpg

from app.api.errors import CatalogException


def retry_deadlock[**P, T](operation: Callable[P, Awaitable[T]]) -> Callable[P, Awaitable[T]]:
    # The operation owns its transaction, so each attempt starts after a rollback.
    @wraps(operation)
    async def run(*args: P.args, **kwargs: P.kwargs) -> T:
        for _ in range(2):
            try:
                return await operation(*args, **kwargs)
            except asyncpg.DeadlockDetectedError:
                continue
        try:
            return await operation(*args, **kwargs)
        except asyncpg.DeadlockDetectedError as exc:
            raise CatalogException("DATABASE_UNAVAILABLE") from exc

    return run
