# 07 — DevOps, Compact Docker (Python 3.14 + PostGIS) & Laptop-to-Russian-VPS Deployment

> **Target Audience**: Developer 1 (Backend, Data & DevOps) & Infrastructure AI Coding Agents
> **Governing Contracts**: `contracts/schema.sql`, `contracts/openapi.yaml`, `AGENTS.md`, `backend/AGENTS.md`
> **Compliance Scope**: Russian Federal Law 152-FZ Art. 18(5) (Primary Database Localization in the Russian Federation)

---

## 1. Multi-Stage Compact `backend/Dockerfile` Blueprint

### 1.1 Architectural Strategy for the `<= 100 MB` Python Runtime Footprint
To keep the Python 3.14 environment and dependencies within the `<= 100 MB` footprint target on a developer laptop while supporting PostGIS 3.5, Alembic migrations, and OSM PBF ingestion, `backend/Dockerfile` uses **four isolated multi-stage targets**:

1. **`builder`**: Uses `ghcr.io/astral-sh/uv:python3.14-bookworm-slim` to compile and install strictly production runtime packages (`--no-dev`), strips debug symbols (`strip --strip-unneeded`) from compiled Cython/Rust `.so` extensions (`asyncpg`, `pydantic_core`, `cryptography`), and deletes `.pyc` caches, test suites, and `.dist-info` documentation bloat.
2. **`runtime`**: Starts from clean `python:3.14-slim-bookworm`, removes unused standard library GUI/test packages (`tkinter`, `idlelib`, `turtledemo`, `ensurepip`, `test`, `pydoc_data` — saving `~34 MB`), copies only the stripped `/app/.venv` and `/app/app`, and runs under an unprivileged `ecotrack` user (`UID 10001`). **Zero C-GIS libraries (`GDAL`, `Shapely`, `GeoPandas`, `PROJ`, `libpq`) are installed**.
3. **`migrations`**: Extends `builder` with the `migrations` dependency group (`alembic>=1.20.0`, `sqlalchemy>=2.0.40`) for the one-shot schema migration container.
4. **`etl`**: Isolated stage that installs `osmium-tool` for filtering regional Geofabrik `.osm.pbf` extracts so C++ OSM binaries never enter the `runtime` API image.

### 1.2 Complete `backend/Dockerfile`

```dockerfile
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

COPY pyproject.toml uv.lock ./

# Install ONLY production runtime dependencies (excludes alembic, pytest, hypothesis, crosshair)
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev --no-install-project --no-editable

# Strip debug symbols from C/Rust shared libraries and remove package test/doc bloat
RUN find /app/.venv -type f -name "*.so*" -exec strip --strip-unneeded {} + 2>/dev/null || true && \
    find /app/.venv -type d \( -name "__pycache__" -o -name "tests" -o -name "test" \) -prune -exec rm -rf {} + && \
    find /app/.venv -type f \( -name "*.pyc" -o -name "*.pyo" -o -name "*.c" -o -name "*.h" \) -delete

COPY app ./app

# =============================================================================
# STAGE 2: MIGRATIONS (One-shot Alembic 1.20.x + contracts/schema.sql verifier)
# =============================================================================
FROM builder AS migrations

RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --group migrations --no-install-project --no-editable

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
```

### 1.3 Image Size Budget & Final Pruning Checklist

| Layer / Component inside `runtime` | Target Uncompressed Size | Verification Command |
| :--- | :--- | :--- |
| Pruned `/usr/local` Python 3.14 interpreter & stdlib | `~36 MB` | `docker run --rm ecotrack-api:latest du -sh /usr/local` |
| Stripped `/app/.venv` (`fastapi`, `uvicorn`, `pydantic`, `asyncpg`, `httpx`, `pyjwt`, `icontract`) | `~42 MB` | `docker run --rm ecotrack-api:latest du -sh /app/.venv` |
| Application source `/app/app` | `< 2 MB` | `docker run --rm ecotrack-api:latest du -sh /app/app` |
| **Total Python Environment + App (`<= 100 MB` Gate)** | **`~80 MB` (`<= 100 MB`)** | `make check-image-size` |
| Underlying Debian Bookworm slim OS rootfs (`/lib`, `/usr/lib`) | `~74 MB` | Shared base OS layer |

**Conscious Budget Adjustment Rule**: If a newly approved runtime dependency pushes `/usr/local + /app` above `100 MB`, the budget may be adjusted **only** after Developer 1 executes and documents all 5 steps of this Mandatory Pruning Checklist:
1. Run `uv tree --no-dev` and verify zero transitive `sqlalchemy`, `alembic`, `numpy`, `pandas`, `gdal`, `shapely`, or `scipy` packages leaked into `[project.dependencies]`.
2. Verify `strip --strip-unneeded` ran on `pydantic_core/*.so`, `asyncpg/*.so`, and `cryptography/*.so`.
3. Verify `UV_COMPILE_BYTECODE=0` and `PYTHONDONTWRITEBYTECODE=1` are active so duplicate `.pyc` files are not stored in the image layer.
4. Run `docker history ecotrack-api:latest` to confirm no multi-stage artifacts leaked across `COPY --from=builder`.
5. Run `dive ecotrack-api:latest --ci` and assert image efficiency `>= 98%` and wasted space `< 2 MB`.

---

## 2. Self-Hosted Laptop MVP `docker-compose.yml` Blueprint

Save at the repository root (`/docker-compose.yml`). All host ports bind to `127.0.0.1` by default for security (with override instructions in Section 4 for LAN mobile testing).

```yaml
name: ecotrack-mvp

services:
  db:
    image: postgis/postgis:17-3.5-alpine
    container_name: ecotrack-db
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${POSTGRES_USER:-ecotrack}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:?POSTGRES_PASSWORD is required}
      POSTGRES_DB: ${POSTGRES_DB:-ecotrack}
      TZ: Europe/Moscow
    command:
      - "postgres"
      - "-c"
      - "shared_buffers=128MB"
      - "-c"
      - "work_mem=8MB"
      - "-c"
      - "maintenance_work_mem=64MB"
      - "-c"
      - "effective_cache_size=384MB"
      - "-c"
      - "max_connections=50"
      - "-c"
      - "random_page_cost=1.1"
      - "-c"
      - "log_min_duration_statement=250"
    ports:
      - "127.0.0.1:5432:5432"
    volumes:
      - ecotrack_pgdata:/var/lib/postgresql/data
      - ./contracts/schema.sql:/docker-entrypoint-initdb.d/01_schema.sql:ro
    deploy:
      resources:
        limits:
          cpus: "1.0"
          memory: 512M
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-ecotrack} -d ${POSTGRES_DB:-ecotrack}"]
      interval: 5s
      timeout: 3s
      retries: 10
      start_period: 10s
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    networks:
      - ecotrack_internal

  migrate:
    build:
      context: ./backend
      dockerfile: Dockerfile
      target: migrations
    container_name: ecotrack-migrate
    restart: "no"
    env_file:
      - .env
    volumes:
      - ./contracts:/contracts:ro
    depends_on:
      db:
        condition: service_healthy
    networks:
      - ecotrack_internal

  api:
    build:
      context: ./backend
      dockerfile: Dockerfile
      target: runtime
    image: ecotrack-api:latest
    container_name: ecotrack-api
    restart: unless-stopped
    env_file:
      - .env
    ports:
      - "${API_BIND_HOST:-127.0.0.1}:8000:8000"
    volumes:
      - ./contracts/error_catalog.json:/app/contracts/error_catalog.json:ro
      - ./secrets:/app/secrets:ro
    depends_on:
      db:
        condition: service_healthy
      migrate:
        condition: service_completed_successfully
    deploy:
      resources:
        limits:
          cpus: "1.0"
          memory: 512M
    healthcheck:
      test:
        [
          "CMD",
          "python",
          "-c",
          "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/readyz', timeout=3)",
        ]
      interval: 10s
      timeout: 4s
      retries: 5
      start_period: 10s
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    networks:
      - ecotrack_internal

  etl:
    build:
      context: ./backend
      dockerfile: Dockerfile
      target: etl
    container_name: ecotrack-etl
    profiles:
      - etl
    env_file:
      - .env
    volumes:
      - ./data/osm:/data/osm
    depends_on:
      db:
        condition: service_healthy
      migrate:
        condition: service_completed_successfully
    deploy:
      resources:
        limits:
          cpus: "1.5"
          memory: 768M
    networks:
      - ecotrack_internal

volumes:
  ecotrack_pgdata:
    name: ecotrack_pgdata

networks:
  ecotrack_internal:
    name: ecotrack_internal
    driver: bridge
```

---

## 3. Complete Environment Variables Contract (`.env.example`)

| Variable Name | Type | Default / Example | Required | Description & Security Rule |
| :--- | :--- | :--- | :--- | :--- |
| `APP_ENV` | `str` | `development` (`production` on VPS) | Yes | Controls debug logging and TLS cookie/header strictness |
| `LOG_LEVEL` | `str` | `INFO` | Yes | Structured JSON log level (`DEBUG`, `INFO`, `WARNING`, `ERROR`) |
| `API_BIND_HOST` | `str` | `127.0.0.1` (`0.0.0.0` for LAN dev) | Yes | Host interface binding for Docker port `8000` |
| `POSTGRES_USER` | `str` | `ecotrack` | Yes | PostgreSQL superuser / app role |
| `POSTGRES_PASSWORD` | `SecretStr` | *(32-char random hex)* | **Yes** | Database password; never commit real value to Git |
| `POSTGRES_DB` | `str` | `ecotrack` | Yes | Database name |
| `DATABASE_URL` | `PostgresDsn` | `postgresql://ecotrack:...@db:5432/ecotrack` | **Yes** | `asyncpg` connection DSN |
| `DB_POOL_MIN_SIZE` | `int` | `4` | Yes | Minimum open connections per Uvicorn worker |
| `DB_POOL_MAX_SIZE` | `int` | `16` | Yes | Maximum connections per worker (`2 * 16 = 32 < max_connections 50`) |
| `JWT_ALGORITHM` | `str` | `HS256` | Yes | Signing algorithm for EcoTrack access tokens |
| `JWT_SECRET_KEY` | `SecretStr` | *(64-char random hex)* | **Yes** | Secret key for signing JWT access tokens (`openssl rand -hex 32`) |
| `JWT_ACCESS_TOKEN_TTL_SECONDS` | `int` | `900` (`15 min`) | Yes | Access token lifetime returned in `AuthSessionResponse` |
| `JWT_REFRESH_TOKEN_TTL_DAYS` | `int` | `30` | Yes | Refresh session lifetime in `auth_refresh_sessions` |
| `FZ152_DELETION_HMAC_SECRET` | `SecretStr` | *(64-char random hex)* | **Yes** | HMAC-SHA256 key signing `fz152_account_deletion_log.verification_signature` |
| `YANDEX_OAUTH_CLIENT_ID` | `str` | `y_client_id_here` | **Yes** | Yandex ID OAuth 2.1 application client ID |
| `YANDEX_OAUTH_CLIENT_SECRET` | `SecretStr` | `y_client_secret_here` | **Yes** | Yandex ID OAuth 2.1 secret (server-side code exchange only) |
| `YANDEX_OAUTH_REDIRECT_URI` | `AnyUrl` | `ecotrack://auth/callback` | Yes | Registered PKCE redirect URI |
| `VK_OAUTH_CLIENT_ID` | `str` | `vk_app_id_here` | **Yes** | VK ID OAuth 2.1 application ID |
| `VK_OAUTH_CLIENT_SECRET` | `SecretStr` | `vk_service_secret_here` | **Yes** | VK ID OAuth secret |
| `VK_OAUTH_REDIRECT_URI` | `AnyUrl` | `ecotrack://auth/callback` | Yes | Registered PKCE redirect URI |
| `ACADEMIC_LAB_ALLOW_GOOGLE_OAUTH` | `bool` | `true` (`false` for strict RF prod) | Yes | Enables Google OAuth with 406-FZ lab warning banner & formal phone gate |
| `GOOGLE_OAUTH_CLIENT_ID` | `str` | `xxx.apps.googleusercontent.com` | Cond. | Required when `ACADEMIC_LAB_ALLOW_GOOGLE_OAUTH=true` |
| `GOOGLE_OAUTH_CLIENT_SECRET` | `SecretStr` | `GOCSPX-...` | Cond. | Required when `ACADEMIC_LAB_ALLOW_GOOGLE_OAUTH=true` |
| `GOOGLE_OAUTH_REDIRECT_URI` | `AnyUrl` | `ecotrack://auth/callback` | Cond. | Registered PKCE redirect URI |
| `PUSH_PROVIDER_BACKEND` | `str` | `noop` (`fcm` / `rustore` / `apns`) | Yes | Selects `PushNotificationProvider` adapter in `app/api/dependencies.py` |
| `FCM_SERVICE_ACCOUNT_JSON_PATH` | `str` | `/app/secrets/fcm-service-account.json` | Cond. | Mounted read-only when `PUSH_PROVIDER_BACKEND=fcm` |
| `OSM_REGION_PBF_URL` | `AnyUrl` | `https://download.geofabrik.de/russia/central-fed-district-latest.osm.pbf` | Yes | Single-region Geofabrik PBF source for laptop MVP |
| `OSM_BBOX_FILTER` | `str` | `36.80,55.10,38.20,56.10` | Yes | Moscow & Moscow Oblast bounding box (`min_lon,min_lat,max_lon,max_lat`) |
| `DATA_MOS_RU_API_KEY` | `SecretStr` | `optional_mos_ru_key` | No | API key for `apidata.mos.ru` open datasets |
| `RATE_LIMIT_REQUESTS_PER_MINUTE` | `int` | `120` | Yes | Per-user/IP sliding window rate limit |

---

## 4. Mobile-to-Laptop Local Development Networking

When running the Docker stack on a developer laptop and testing on a physical smartphone:

### 4.1 Option A — USB / Wi-Fi ADB Reverse Tunnel (Recommended for Android)
Requires zero firewall modification and keeps `API_BIND_HOST=127.0.0.1`:
```bash
# Map phone's localhost:8000 directly to laptop's 127.0.0.1:8000 over ADB
adb reverse tcp:8000 tcp:8000

# Launch Flutter app pointing to localhost
cd mobile && flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

### 4.2 Option B — Shared Wi-Fi LAN IP (iOS Physical Device & Wireless Testing)
1. Set `API_BIND_HOST=0.0.0.0` in `.env` and restart `docker compose up -d api`.
2. Find the laptop's LAN IPv4 address (e.g., `192.168.1.42`).
3. Allow inbound TCP `8000` on the local Wi-Fi profile:
   - **Windows PowerShell (Admin)**:
     ```powershell
     New-NetFirewallRule -DisplayName "EcoTrack-MVP-API-8000" -Direction Inbound -LocalPort 8000 -Protocol TCP -Profile Private -Action Allow
     ```
   - **Linux (`ufw`)**:
     ```bash
     sudo ufw allow from 192.168.0.0/16 to any port 8000 proto tcp
     ```
4. Launch the mobile client with:
   ```bash
   cd mobile && flutter run --dart-define=API_BASE_URL=http://192.168.1.42:8000
   ```

### 4.3 Local OAuth 2.1 + PKCE Callback Routing (`ecotrack://auth/callback`)
Because EcoTrack uses native custom-scheme PKCE (`ecotrack://auth/callback`) registered in `mobile/android/app/src/main/AndroidManifest.xml` and `mobile/ios/Runner/Info.plist`, Yandex ID, VK ID, and Google redirect the authorization code directly back to the OS app intent on the phone. The phone then sends `{authorization_code, code_verifier}` over the local tunnel (`http://127.0.0.1:8000/api/v1/auth/oauth/exchange`) to the laptop container, which completes the outbound HTTPS token exchange with the OAuth provider. **No public ngrok tunnel is required for OAuth login**.

---

## 5. 10-Minute Migration to Russian VPS (152-FZ Data Localization)

To comply with **Article 18 Part 5 of Federal Law No. 152-FZ**, production personal data of Russian citizens must be recorded and stored on database servers physically located within the Russian Federation (e.g., **Selectel** `ru-1` St. Petersburg / Moscow, **Yandex Cloud** `ru-central1`, or **Timeweb Cloud** Moscow, minimum spec: `2 vCPU, 4 GB RAM, 40 GB NVMe, Ubuntu 24.04 LTS`).

### Step 1 — Create Consistent Compressed Dump on Laptop (`T+0 min`)
```bash
docker compose exec -T db pg_dump \
  -U ecotrack -d ecotrack -Fc --no-owner --no-acl \
  > ecotrack_migration_$(date +%Y%m%d).dump
```

### Step 2 — Harden Russian VPS & Configure UFW Firewall (`T+2 min`)
SSH into the Russian VPS (`root@<VPS_IP>`) and lock down inbound ports so PostgreSQL (`5432`) and Uvicorn (`8000`) are never exposed to the public internet:
```bash
apt-get update && apt-get install -y ufw caddy docker.io docker-compose-v2
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable
```
*(Critical Docker + UFW Rule: Keep `127.0.0.1:5432:5432` and `127.0.0.1:8000:8000` in `docker-compose.yml` so Docker's `iptables` chains never expose ports `5432` or `8000` on `eth0`).*

### Step 3 — Configure Caddy Automatic TLS Reverse Proxy (`T+4 min`)
Write `/etc/caddy/Caddyfile` for `api.ecotrack.ru`:
```caddyfile
api.ecotrack.ru {
    encode zstd gzip

    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "DENY"
        Referrer-Policy "no-referrer"
        -Server
    }

    reverse_proxy 127.0.0.1:8000 {
        health_uri /readyz
        health_interval 10s
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }
}
```
Reload Caddy: `systemctl reload caddy`.

### Step 4 — Transfer Repository, `.env` & Database Dump (`T+6 min`)
```bash
scp ecotrack_migration_*.dump deploy@api.ecotrack.ru:/opt/ecotrack/
```
On the VPS (`/opt/ecotrack/`), set `APP_ENV=production` and `API_BIND_HOST=127.0.0.1` in `.env`, start `db`, and restore the dump:
```bash
cd /opt/ecotrack
docker compose up -d db
docker compose exec -T db pg_restore \
  -U ecotrack -d ecotrack --clean --if-exists --no-owner --no-acl \
  < ecotrack_migration_*.dump
docker compose up -d --build migrate api
```

### Step 5 — Automated Daily `pg_dump` Backup Cron & 14-Day Retention (`T+9 min`)
Install `/etc/cron.daily/ecotrack-pg-backup` (`chmod +x`):
```bash
#!/usr/bin/env bash
set -euo pipefail
BACKUP_DIR="/var/backups/ecotrack-postgres"
mkdir -p "$BACKUP_DIR"
STAMP=$(date -u +"%Y%m%dT%H%M%SZ")
FILE="$BACKUP_DIR/ecotrack_${STAMP}.dump"

docker compose -f /opt/ecotrack/docker-compose.yml exec -T db \
  pg_dump -U ecotrack -d ecotrack -Fc --no-owner --no-acl > "$FILE"

sha256sum "$FILE" > "${FILE}.sha256"
find "$BACKUP_DIR" -type f -mtime +14 -delete
```

---

## 6. Operational `Makefile` Targets

Save at repository root (`/Makefile`):

```makefile
.PHONY: up down logs migrate etl-rso backup-db check-image-size \
        verify verify-contracts verify-static verify-dbc verify-pbt verify-stress

up:
	docker compose up -d --build db migrate api

down:
	docker compose down

logs:
	docker compose logs -f --tail=100 api db

migrate:
	docker compose run --rm migrate

etl-rso:
	docker compose --profile etl run --rm etl

backup-db:
	@mkdir -p backups
	docker compose exec -T db pg_dump -U $${POSTGRES_USER:-ecotrack} -d $${POSTGRES_DB:-ecotrack} -Fc > backups/ecotrack_$$(date +%Y%m%d_%H%M%S).dump

check-image-size:
	docker build --target runtime -t ecotrack-api:latest ./backend
	@PY_KB=$$(docker run --rm ecotrack-api:latest sh -c "du -sk /usr/local /app | awk '{s+=\$$1} END {print s}'"); \
	PY_MB=$$((PY_KB / 1024)); \
	echo "Python 3.14 runtime + venv footprint: $${PY_MB} MB (Budget: <= 100 MB)"; \
	test $${PY_MB} -le 100

verify-contracts:
	uv run --directory backend python ../scripts/verify_contracts.py

verify-static: verify-contracts
	uv run --directory backend ruff check app tests
	uv run --directory backend ruff format --check app tests
	uv run --directory backend basedpyright --level error
	uv run --directory backend semgrep --config auto --error app
	cd mobile && dart format --output=none --set-exit-if-changed lib test
	cd mobile && flutter analyze --fatal-infos --fatal-warnings
	cd mobile && dart run dart_code_linter:metrics analyze lib --fatal-style --fatal-performance --fatal-warnings
	cd mobile && dart run import_lint

verify-dbc:
	uv run --directory backend crosshair check --per_condition_timeout=10 app/domain/
	uv run --directory backend pytest tests/contract/ -v

verify-pbt:
	uv run --directory backend pytest tests/pbt/ -v
	cd mobile && flutter test test/pbt/ test/database/

verify-stress:
	uv run --directory backend pytest tests/stress/ -v
	cd mobile && flutter test integration_test/impeller_map_mascot_benchmark_test.dart

verify: verify-static verify-dbc verify-pbt verify-stress
```
