.PHONY: help verify verify-contracts verify-static verify-backend verify-backend-static verify-dbc verify-pbt verify-stress db-up db-down dev-backend dev-mobile check-image-size verify-backend-pbt verify-backend-stress

help:
	@echo "EcoTrack Contract-First Monorepo Automation"
	@echo "============================================="
	@echo "  make verify          - Run all four required verification layers"
	@echo "  make verify-contracts- Validate parity across 4 canonical contracts"
	@echo "  make verify-static   - Run Ruff, Basedpyright, and Dart Analyze"
	@echo "  make verify-backend  - Run backend checks against TEST_DATABASE_URL"
	@echo "  make verify-dbc      - Run Formal Design-by-Contract (CrossHair/Z3)"
	@echo "  make verify-pbt      - Run Property-Based Tests (Hypothesis & Glados)"
	@echo "  make verify-stress   - Run Double-Spend & PostGIS Spatial Benchmarks"
	@echo "  make db-up           - Start PostGIS 17 container in background"
	@echo "  make db-down         - Stop local Docker containers"
	@echo "  make dev-backend     - Run FastAPI backend locally with hot reload"
	@echo "  make dev-mobile      - Launch Flutter client on connected device"

verify:
	$(MAKE) verify-static
	$(MAKE) verify-dbc
	$(MAKE) verify-pbt
	$(MAKE) verify-stress

verify-contracts:
	uv run --with pyyaml python scripts/verify_contracts.py

verify-static: verify-contracts verify-backend-static
	@echo "==> Running Mobile Linters..."
	uv run --with pyyaml python scripts/verify_mobile_gates.py
	cd mobile && dart format --output=none --set-exit-if-changed lib test
	cd mobile && flutter analyze --fatal-infos --fatal-warnings
	cd mobile && dart analyze --fatal-infos --fatal-warnings
	cd mobile && dart run import_lint

verify-backend-static:
	@echo "==> Running Backend Linters..."
	uv run --locked --directory backend ruff check app tests
	uv run --locked --directory backend ruff format --check app tests
	uv run --locked --directory backend basedpyright --level error
	uvx semgrep --config auto --config backend/.semgrep.yml --error backend/app

verify-backend:
	$(MAKE) verify-contracts
	$(MAKE) verify-backend-static
	$(MAKE) verify-dbc
	$(MAKE) verify-backend-pbt
	$(MAKE) verify-backend-stress

verify-dbc:
	uv run --locked --directory backend crosshair check --per_condition_timeout=10 app/domain/
	uv run --locked --directory backend pytest --fail-on-skip tests/contract/ tests/dbc/

verify-backend-pbt:
	uv run --locked --directory backend pytest --fail-on-skip tests/pbt/

verify-pbt: verify-backend-pbt
	cd mobile && flutter test test/pbt/

verify-backend-stress:
	uv run --locked --directory backend pytest --fail-on-skip tests/stress/

verify-stress: verify-backend-stress
	k6 run backend/tests/stress/k6_load_gate.js
	cd mobile && flutter test integration_test/impeller_map_mascot_benchmark_test.dart

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
	python scripts/check_runtime_image.py ecotrack-api:latest
