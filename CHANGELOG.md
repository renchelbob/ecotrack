# Журнал изменений (Changelog)

Формат документа основан на [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/), проект придерживается [SemVer 2.0.0](https://semver.org/lang/ru/).

## [Unreleased]

## [0.1.1] — 2026-11-23

### Fixed
- Расширена колонка `users.friend_code` с `VARCHAR(12)` до `VARCHAR(13)` в `contracts/schema.sql` для соответствия шаблону `^ECO-[A-Z0-9]{4}-[A-Z0-9]{4}$` (по согласованному `CONTRACT_RFC`).

### Added
- В `scripts/verify_postgis_smoke.sql` добавлены smoke-проверки вставки в `users`, начисления в `point_ledger`, триггеров `trg_point_ledger_sync_balance` и `trg_point_ledger_immutable`, ограничения `CHECK (points_balance >= 0)` и каскадного удаления аккаунта по 152-ФЗ.

## [0.1.0] — 2026-11-23

### Added
- Регламент командной разработки по модели Atlassian Gitflow (`docs/GIT_FLOW.md`).
- Регламент работы с конфигурациями, секретами и релизами (`docs/RELEASE_AND_CONFIG.md`).
- Пайплайн непрерывной интеграции `.github/workflows/ci.yml` (`Contracts & Config Gate`, `PostGIS 17 Schema Smoke`, `Code Quality Gates`, `Docker Runtime Build`).
- Пайплайн поставки `.github/workflows/cd.yml` (staging-сборка в GHCR + deploy-bundle, production release по тегам `v*.*.*`).
- Скрипт проверки PostGIS-инвариантов, триггеров и ограничений целостности `scripts/verify_postgis_smoke.sql`.
- Шаблон Pull Request (`.github/PULL_REQUEST_TEMPLATE.md`) и файл владельцев кода (`.github/CODEOWNERS`).

## [0.0.1] — 2026-11-19

### Added
- Инициализирован Contract-First монорепозиторий `ecotrack` (ветка `main`, коммит `9d310d7`):
  - канонические контракты `contracts/schema.sql`, `contracts/client_sqlite_schema.sql`, `contracts/openapi.yaml`, `contracts/error_catalog.json`;
  - технические спецификации `specs/01..08` и скрипт проверки паритета `scripts/verify_contracts.py`;
  - каркасы `backend/`, `mobile/`, `docker-compose.yml`, `Makefile`, `.env.example` и 23 экрана в `screens/`.
