.PHONY: help verify verify-contracts verify-static verify-dbc verify-pbt verify-stress db-up db-down dev-backend dev-mobile check-image-size

help:
	@echo "EcoTrack Contract-First Monorepo Automation"
	@echo "============================================="
	@echo "  make verify          - Run Layer 1 contract and static checks"
	@echo "  make verify-contracts- Validate parity across 4 canonical contracts"
	@echo "  make verify-static   - Run Ruff, Basedpyright, and Dart Analyze"
	@echo "  make verify-dbc      - Run Formal Design-by-Contract (CrossHair/Z3)"
	@echo "  make verify-pbt      - Run Property-Based Tests (Hypothesis & Glados)"
	@echo "  make verify-stress   - Run Double-Spend & PostGIS Spatial Benchmarks"
	@echo "  make db-up           - Start PostGIS 17 container in background"
	@echo "  make db-down         - Stop local Docker containers"
	@echo "  make dev-backend     - Run FastAPI backend locally with hot reload"
	@echo "  make dev-mobile      - Launch Flutter client on connected device"

verify: verify-contracts verify-static

verify-contracts:
	uv run --with pyyaml python scripts/verify_contracts.py

verify-static:
	@echo "==> Running Backend Linters..."
	uv run --directory backend ruff check app tests
	uv run --directory backend ruff format --check app tests
	uv run --directory backend basedpyright --level error
	@echo "==> Running Mobile Linters..."
	uv run --with pyyaml python scripts/verify_mobile_gates.py
	cd mobile && dart format --output=none --set-exit-if-changed lib test
	cd mobile && flutter analyze --fatal-infos --fatal-warnings
	cd mobile && dart analyze --fatal-infos --fatal-warnings
	cd mobile && dart run import_lint

verify-dbc:
	@echo "==> Running Symbolic SMT Verification (CrossHair / Z3)..."
	uv run --directory backend crosshair check --per_condition_timeout=10 app/domain/

verify-pbt:
	@echo "==> Running Property-Based Testing..."
	uv run --directory backend pytest tests/pbt/
	cd mobile && flutter test test/pbt/

verify-stress:
	@echo "==> Running Concurrency & PostGIS Performance Gates..."
	uv run --directory backend pytest tests/stress/

db-up:
	docker compose up -d db

db-down:
	docker compose down

dev-backend:
	uv run --directory backend uvicorn app.main:app --reload --port 8000

dev-mobile:
	cd mobile && flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000

check-image-size:
	docker build --target runtime -t ecotrack-api:latest ./backend
	@echo "Checking uncompressed runtime image size budget (<= 100 MB)..."
	docker run --rm ecotrack-api:latest du -sh /usr/local /app/.venv /app/app
