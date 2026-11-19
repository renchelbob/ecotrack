# syntax=docker/dockerfile:1.7

# =============================================================================
# STAGE 1: BUILDER (uv + Python 3.14 Standard GIL)
# =============================================================================
FROM ghcr.io/astral-sh/uv:python3.14-bookworm-slim AS builder

ENV UV_COMPILE_BYTECODE=0 \
    UV_LINK_MODE=copy \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    binutils \
    && rm -rf /var/lib/apt/lists/*

COPY pyproject.toml ./

# Install ONLY production runtime dependencies (excludes alembic, pytest, hypothesis, crosshair)
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --no-dev --no-install-project --no-editable

# Strip debug symbols from C/Rust shared libraries and remove package test/doc bloat
RUN find /app/.venv -type f -name "*.so*" -exec strip --strip-unneeded {} + 2>/dev/null || true && \
    find /app/.venv -type d \( -name "__pycache__" -o -name "tests" -o -name "test" \) -prune -exec rm -rf {} + && \
    find /app/.venv -type f \( -name "*.pyc" -o -name "*.pyo" -o -name "*.c" -o -name "*.h" \) -delete

COPY app ./app

# =============================================================================
# STAGE 2: MIGRATIONS (One-shot Alembic + contracts/schema.sql verifier)
# =============================================================================
FROM builder AS migrations

RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --group migrations --no-install-project --no-editable

COPY alembic.ini ./
ENV PATH="/app/.venv/bin:$PATH"
ENTRYPOINT ["alembic", "upgrade", "head"]

# =============================================================================
# STAGE 3: ETL (Isolated OSM PBF osmium-tool + data.mos.ru Ingestor)
# =============================================================================
FROM python:3.14-slim-bookworm AS etl

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/app/.venv/bin:$PATH"

RUN apt-get update && apt-get install -y --no-install-recommends \
    osmium-tool \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /app/.venv /app/.venv
COPY --from=builder /app/app /app/app

USER nobody
ENTRYPOINT ["python", "-m", "app.etl.run_ingest"]

# =============================================================================
# STAGE 4: PRODUCTION API RUNTIME (Minimized Python 3.14 + FastAPI + asyncpg)
# =============================================================================
FROM python:3.14-slim-bookworm AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONOPTIMIZE=1 \
    PATH="/app/.venv/bin:$PATH"

# Prune unused Python 3.14 standard library modules (~34 MB saved) and strip libpython
RUN rm -rf \
    /usr/local/lib/python3.14/test \
    /usr/local/lib/python3.14/idlelib \
    /usr/local/lib/python3.14/tkinter \
    /usr/local/lib/python3.14/turtledemo \
    /usr/local/lib/python3.14/ensurepip \
    /usr/local/lib/python3.14/pydoc_data \
    /usr/local/lib/python3.14/lib2to3 && \
    find /usr/local/lib/python3.14 -type d -name "__pycache__" -prune -exec rm -rf {} + && \
    find /usr/local/lib -type f -name "*.so*" -exec strip --strip-unneeded {} + 2>/dev/null || true && \
    groupadd --gid 10001 ecotrack && \
    useradd --uid 10001 --gid 10001 --shell /usr/sbin/nologin --no-create-home ecotrack

WORKDIR /app

COPY --from=builder --chown=ecotrack:ecotrack /app/.venv /app/.venv
COPY --from=builder --chown=ecotrack:ecotrack /app/app /app/app

USER ecotrack
EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "2", "--no-access-log"]
