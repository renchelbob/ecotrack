# EcoTrack (ЭкоТрек)

> **Contract-First Monorepo** для платформы учёта экологической активности, снижения выбросов CO₂ и сдачи вторсырья (РСО) в соответствии с законодательством РФ (152-ФЗ, 406-ФЗ).

---

## 1. Архитектура монорепозитория

Репозиторий спроектирован по парадигме **Contract-First**: канонические контракты базы данных, REST API и кодов ошибок зафиксированы в `/contracts/` и являются неизменяемым единым источником правды (Single Source of Truth).

```text
ecotrack/
├── AGENTS.md                           # Регламент монорепозитория, матрица ролей (Dev 1 / Dev 2) и правила
├── Makefile                            # Единый интерфейс верификации, линтинга и сборки
├── docker-compose.yml                  # Локальный стек: PostgreSQL 17 + PostGIS 3.5 + FastAPI
├── .env.example                        # Шаблон переменных окружения для разработки
├── README.md                           # Описание проекта и быстрый старт
│
├── contracts/                          # КАНОНИЧЕСКИЕ КОНТРАКТЫ (LOCKED SSOT)
│   ├── schema.sql                      # DDL PostgreSQL 17 + PostGIS (29 таблиц, 14 ENUM, триггеры иммутабельности)
│   ├── client_sqlite_schema.sql        # DDL SQLite 3 WAL для Flutter (12 таблиц, outbox-очередь, CHECK)
│   ├── openapi.yaml                    # Спецификация OpenAPI 3.1.0 (38 эндпоинтов, 88 схем, OAuth 2.1)
│   └── error_catalog.json              # Машиночитаемый каталог 63 бизнес-ошибок с русскими текстами
│
├── specs/                              # ТЕХНИЧЕСКИЕ СПЕЦИФИКАЦИИ (Progressive Disclosure)
│   ├── 01-product-and-ux-spec.md       # Требования к продукту, 5 табов, логика маскота-лиса, экран 152-ФЗ
│   ├── 02-domain-math-and-algorithms.md# Формула CO₂, классификатор шаги+GPS, антифрод, скоринг РСО
│   ├── 03-backend-architecture-and-152fz.md # Архитектура FastAPI (Python 3.14), asyncpg, право на забвение
│   ├── 04-postgis-and-rso-data-pipeline.md  # ETL-пайплайн (OSM PBF + data.mos.ru), GiST-индексация точек РСО
│   ├── 05-mobile-flutter-architecture.md    # Flutter BLoC, zero-build_runner, Canvas-маскот, оффлайн
│   ├── 06-offline-sync-and-sensors.md       # Автомат синхронизации outbox, датчики шагов и геолокации
│   ├── 07-devops-docker-and-vps-deployment.md# Dockerfile (<= 100 МБ), деплой на российский VPS
│   └── 08-verification-and-quality-gates.md # 4 уровня качества (icontract, Hypothesis, Schemathesis, stress)
│
├── backend/                            # МОДУЛЬ БЭКЕНДА (Зона ответственности Разработчика 1)
│   ├── Dockerfile                      # Многоэтапный легковесный образ python:3.14-slim (<= 100 МБ)
│   ├── pyproject.toml                  # Конфигурация uv, ruff, basedpyright, pytest, hypothesis
│   ├── AGENTS.md                       # Инструкции и ограничения для бэкенд-разработчика
│   ├── alembic/                        # Миграции базы данных
│   ├── app/                            # Исходный код API
│   └── tests/                          # Тесты (PBT, Schemathesis, CrossHair)
│
├── mobile/                             # МОДУЛЬ МОБИЛЬНОГО КЛИЕНТА (Зона ответственности Разработчика 2)
│   ├── pubspec.yaml                    # Зафиксированные зависимости Flutter (BLoC, Dio, SQLite3, FlutterMap)
│   ├── analysis_options.yaml           # Строгий линтер (dart_code_linter + import_lint)
│   ├── AGENTS.md                       # Инструкции для мобильного разработчика (3 файла-исключения)
│   ├── assets/                         # Схемы SQLite и каталог ошибок в бандле приложения
│   ├── lib/                            # Feature-first архитектура приложения на Flutter
│   └── test/                           # Тесты (glados PBT, outbox FSM)
│
├── screens/                            # ЭТАЛОННЫЕ ЭКРАНЫ И ВАЙРФРЕЙМЫ (LOCKED VISUAL CANON, READ-ONLY)
│   ├── wireframes.png                  # Общая панорама экранов
│   ├── 07_Onboarding_... — 09_...      # 3 экрана онбординга и согласия 152-ФЗ (кнопки OAuth на 09)
│   └── 14_Main_... — 23_Shop_...       # 10 финальных экранов приложения
│
├── scripts/
│   ├── verify_contracts.py             # Скрипт автоматической верификации паритета 4 контрактов
│   └── verify_mobile_gates.py          # Скрипт проверки мобильных ворот (screens, конфиги, запреты, тесты)
│
└── .agents/skills/                     # ВАЛИДИРОВАННЫЕ НАВЫКИ ДЛЯ AI-АГЕНТОВ
    ├── dart-use-pattern-matching
    ├── dart-use-primary-constructors
    ├── flutter-fix-layout-issues
    ├── flutter-implement-json-serialization
    └── flutter-setup-declarative-routing
```

---

## 2. Быстрый старт и верификация

### Проверка паритета контрактов (Слой 1 ворот качества)
Контракты проверяются на 100% взаимное соответствие типов, ENUM-ов, CHECK-констрейнтов и статус-кодов:
```bash
uv run --with pyyaml python scripts/verify_contracts.py
```

### Запуск базы данных и локального окружения
```bash
# Запуск PostgreSQL 17 + PostGIS 3.5
docker compose up -d postgres

# Запуск полного стека разработки
docker compose up --build
```

---

## 3. Разделение ответственности и роли

Подробное описание ролей, правил разработки и запретов зафиксировано в [`AGENTS.md`](./AGENTS.md).

* **Разработчик 1 (Backend, Data & DevOps):** отвечает за `/backend/**`, `/scripts/**`, `docker-compose.yml` и backend-цели `Makefile`.
* **Разработчик 2 (Mobile Client):** отвечает за весь каталог `/mobile/**` (Flutter UI, BLoC-состояния, навигация `go_router`, локальная база SQLite WAL, экраны 152-ФЗ, а также три ключевых модуля `mascot_vector_painter.dart`, `outbox_dispatcher.dart`, `map_activity_screen.dart`) и mobile-цели `Makefile`.
