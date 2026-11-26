# Локальный запуск EcoTrack

Из корня репозитория скопируйте `.env.example` в `.env` для локальной разработки,
затем запустите `docker compose up --build -d --wait api`. Compose поднимает PostGIS,
применяет миграцию Alembic и запускает API. Начальная миграция читает
`contracts/schema.sql`. Она рассчитана на новую БД или том, уже управляемый Alembic.

| Проверка | URL по умолчанию |
| --- | --- |
| Процесс API работает | http://127.0.0.1:8000/healthz |
| PostgreSQL и расширение PostGIS доступны | http://127.0.0.1:8000/readyz |
| Документация реализованных операций | http://127.0.0.1:8000/docs |

При конфликте портов задайте `POSTGRES_HOST_PORT` и `API_HOST_PORT`.
Если меняете учётные данные БД для Compose, укажите соответствующую
`COMPOSE_DATABASE_URL` с хостом `db`. Для запуска API напрямую на хосте
используется `DATABASE_URL` с хостом `127.0.0.1` и опубликованным портом БД.
Учётные данные из шаблона предназначены для локального стенда.

Проверки бэкенда на Python 3.14:

```sh
cd backend
uv sync --locked --no-install-project
uv run --no-sync python -m pytest
```

Для проверки успешного `/readyz` задайте `TEST_DATABASE_URL` для локальной
БД с PostGIS. Без неё проверяются отказ БД, работа `/healthz` при этом отказе
и расчёты CO₂. Контракты проверяются скриптом `scripts/verify_contracts.py`.

## Вход и первый сквозной сценарий

На сервере настроен адаптер Яндекс ID. Укажите в локальном `.env`
`YANDEX_OAUTH_CLIENT_ID`, `YANDEX_OAUTH_CLIENT_SECRET` и
`YANDEX_OAUTH_REDIRECT_URI` зарегистрированного приложения. Клиент получает
код авторизации с PKCE S256 и обменивает его через
`POST /api/v1/auth/oauth/exchange`. Секрет провайдера и ключ подписи JWT
хранятся на сервере. Для реального стенда задайте случайный `JWT_SECRET_KEY`.
После изменения конфигурации пересоздайте контейнер API через
`docker compose up -d --force-recreate api`.

1. После входа `GET /api/v1/users/me` возвращает профиль.
2. `PUT /api/v1/activity/steps/daily` принимает шаги при наличии согласия
   на обработку данных датчика. Для записи передайте `Idempotency-Key`.
3. `GET /api/v1/stats/history` возвращает историю,
   `GET /api/v1/stats/emissions?period=days` — график за 7 дней.
   Для периода `weeks` или `months` выдаётся до 12 интервалов.
4. `POST /api/v1/auth/refresh` меняет пару токенов,
   `POST /api/v1/auth/logout` завершает текущую сессию.

Интеграционные тесты выполняют запросы к FastAPI и реальной PostGIS.
Ответ внешнего провайдера в них заменяется тестовой учётной записью.

## GPS-маршруты и транспорт

- `POST /api/v1/activity/tracks/points:batch` принимает точки после согласия
  на геолокацию. Передавайте точки в порядке `seq_no`, начиная с нуля за день.
  Повтор уже принятых точек сверяется с сохранёнными данными и не добавляет копий.
- `GET /api/v1/activity/daily/{activity_date}` возвращает сводку, классы
  движения GPS-точек и сохранённые участки.
- `PUT /api/v1/activity/daily/{activity_date}/allocations` сохраняет весь
  список участков за сегодня или вчера. У каждого участка свой
  `idempotency_key`. Для неизменённого участка сохраните этот ключ при повторе.
  `DELETE .../allocations/{allocation_id}` снимает одну разметку.
- `GET /api/v1/transport/presets` возвращает коэффициенты для выбора
  транспорта. Коэффициент личного авто берётся из `/api/v1/users/me/vehicle`,
  если пользователь его настроил.

## Магазин и история баллов

- `GET /api/v1/shop/items` возвращает витрину. Доступны фильтры `category`,
  `item_type` и поиск `search`.
- `POST /api/v1/shop/orders` принимает `items` с полями `shop_item_id` и
  `quantity`. При повторной отправке той же корзины передайте прежний
  `Idempotency-Key`. Сервер вернёт сохранённый заказ с текущим балансом.
  Для новой корзины используйте новый ключ.
- `GET /api/v1/shop/orders` возвращает заказы пользователя, включая коды
  и данные для QR. Демо-купоны действуют 30 дней.
- `GET /api/v1/ledger` возвращает текущий баланс, сумму начислений и журнал
  операций. Оба списка поддерживают `limit` и `offset`.
- Заморозки серии и аксессуары поступают в профиль сразу после покупки.
  `POST /api/v1/shop/virtual-items/streak-freeze:activate` расходует одну
  заморозку для защиты вчерашнего дня. Повтор в тот же день защищён
  проверкой даты последней активности.
- Один виртуальный эко-вклад добавляет 2 000 г CO₂ в прогресс «Общего леса».
  При достижении порогов сервер начисляет награды через журнал баллов.

## Достижения, гардероб и Общий лес

- `GET /api/v1/badges` возвращает каталог достижений, прогресс и дату получения
  награды. Баллы и аксессуары выдаются один раз при достижении порога.
- `GET /api/v1/mascot/inventory` возвращает каталог аксессуаров и показывает,
  какие из них доступны и какой экипирован.
- `GET /api/v1/challenges/shared-forest/current` показывает общий прогресс за
  ISO-неделю по Москве, личный вклад и до трёх друзей с открытой статистикой.
  Вклад меняется при синхронизации шагов, изменении разметки маршрута и покупке
  виртуального эко-вклада.
- Миграция `0003_backfill_forest_progress` восстанавливает недельные вклады
  по сохранённым сводкам активности и операциям магазина.

## Друзья и уведомления

- `GET /api/v1/friends` возвращает друзей и входящие и исходящие заявки.
  Недельный рейтинг доступен на `GET /api/v1/friends/leaderboard`. Показатели
  скрываются по настройкам приватности, а недоступные аккаунты исключаются.
- `POST /api/v1/friends/{friend_user_id}/nudge` записывает одно напоминание
  для пары отправитель–получатель за календарный день по Москве.
- Клиент регистрирует токен через `POST /api/v1/push/tokens` и удаляет его
  через `DELETE /api/v1/push/tokens/{token}`. При `PUSH_PROVIDER_BACKEND=noop`
  ответ напоминания содержит `push_delivered: false`. Для доставки на FCM
  настройте `PUSH_PROVIDER_BACKEND=fcm` и файл сервисного аккаунта на сервере.

## Google OAuth и удаление аккаунта

Для учебного входа через Google зарегистрируйте клиент с PKCE, укажите его
`GOOGLE_OAUTH_CLIENT_ID`, зарегистрированный `GOOGLE_OAUTH_REDIRECT_URI` и
при необходимости `GOOGLE_OAUTH_CLIENT_SECRET`. Затем включите
`ACADEMIC_LAB_ALLOW_GOOGLE_OAUTH`. После входа профиль сообщает о требовании
формального номера. `POST /api/v1/auth/google-phone` принимает E.164 без SMS.

`DELETE /api/v1/users/me` требует заголовок `Idempotency-Key`, причину удаления
и подтверждение `DELETE_MY_DATA_152FZ`. Отдельный секрет
`FZ152_DELETION_HMAC_SECRET` подписывает квитанцию. Для стенда используйте
сгенерированный секрет длиной не менее 32 байт.

## Карта переработки

- `GET /api/v1/map/waste-points` принимает границы видимой области, масштаб
  и фильтры. На малом масштабе сервер группирует точки по сетке.
- `GET /api/v1/map/waste-points/{point_id}` возвращает карточку с источниками
  и последними отчётами. Отчёты обновляют доверие к точке и начисляют баллы.
- `POST /api/v1/map/waste-points/suggestions` принимает предложение новой
  точки. Новая точка появляется при `include_unverified=true`.

Для OSM положите региональный файл Geofabrik в `data/osm` и отфильтруйте его
через `scripts/osm_ingest/filter_osm_pbf.sh` в окружении с `osmium`. Затем
запустите импорт из корня репозитория.

```sh
docker compose --profile etl run --rm etl --source osm_pbf --input /data/osm/recycling.geojsonseq
```

Для подготовленного CSV используйте `--source data_mos_ru` или
`--source municipal_registry`. Колонки `id,title,lon,lat,fractions`
обязательны, фракции перечисляются через `;` в одной ячейке. Можно добавить
`address,operator,opening_hours`. Параметр `--bbox` задаёт область
`west,south,east,north`. По умолчанию используется Москва с окрестностями.
Повторный импорт сохраняет рейтинг доверия и счётчики пользовательских отчётов.

Для импорта через API портала Москвы задайте `DATA_MOS_RU_API_KEY` и запустите
`etl` с аргументами `--source data_mos_ru --dataset-id ID --fractions glass paper`.
Укажите фракции выбранного набора данных. Параметр `--title-column` позволяет
выбрать поле с названием пункта, если оно отличается от `Name`.

## Проверки перед развёртыванием

Подготовьте отдельную БД PostGIS с миграциями и укажите её в
`TEST_DATABASE_URL`. Из корня запустите `make verify-backend`. Для короткого
нагрузочного прогона на выделенном стенде запустите
`k6 run backend/tests/stress/k6_load_gate.js`. Задайте
`ECOTRACK_BASE_URL` для адреса стенда. С действующим
`ECOTRACK_ACCESS_TOKEN` с разрешением на шаги сценарий последовательно
проверяет карту переработки, синхронизацию шагов и статистику.
По умолчанию проверяется `/readyz`.

На стенде с лимитом в одно ядро API запускается одним процессом Uvicorn.
Для воспроизводимого замера задайте `ECOTRACK_API_CPUSET` и
`ECOTRACK_POSTGRES_CPUSET` в окружении Docker Compose. Выберите по одному
логическому CPU на разных физических ядрах по выводу `lscpu -e=CPU,CORE`.
Лимит каждого сервиса остаётся на уровне одного CPU и 512 МБ памяти.

Для VPS задайте отдельные секреты и окружение, оставьте порт PostGIS на
loopback и опубликуйте API через TLS-прокси. Проверьте миграции и
восстановление `pg_dump` на отдельном томе перед переносом рабочей базы.
Последовательность развёртывания описана в
[`specs/07-devops-docker-and-vps-deployment.md`](../specs/07-devops-docker-and-vps-deployment.md).
Конфигурация `scripts/devops/Caddyfile` принимает имя API через
`ECOTRACK_API_HOST`. Если опубликованный порт API отличается от 8000,
задайте `ECOTRACK_API_PORT` в окружении процесса Caddy.

Скрипт резервного копирования создаёт архив PostgreSQL и контрольную сумму
SHA-256. Перед переносом проверьте восстановление в отдельную пустую БД.

```sh
bash scripts/devops/postgres_backup.sh backup /var/backups/ecotrack-postgres ecotrack
docker compose exec -T db createdb -U ecotrack ecotrack_restore_check
bash scripts/devops/postgres_backup.sh restore /path/to/ecotrack_backup.dump ecotrack_restore_check
```

The restore database must be isolated from API traffic. The restore command
reapplies verified erasures from the authoritative EcoTrack database defined
by the API service's connection settings. Keep the original deletion history
and its HMAC key available. Coordinate the final reconciliation and cutover
with a pause in writes to the authoritative database. A failed reconciliation
leaves the target isolated for investigation.

Uvicorn supplies the peer IP for the consent and session audit. Configure
FORWARDED_ALLOW_IPS with the actual reverse proxy addresses when forwarding
client IPs, and leave other peers untrusted.


Для ежедневной ротации на VPS выполняйте `backup`, а после успешного создания
архива запускайте `prune /var/backups/ecotrack-postgres`. Ротация удаляет
архивы скрипта и их контрольные суммы по достижении возраста 14 суток.

## Подключение трёх модулей Dev 1

- `OutboxDispatcher` создаётся один раз на SQLite-хранилище пользователя. Клиент
  передаёт реализацию `OutboxStore` и отправку HTTP-запроса с исходным
  `Idempotency-Key`. Запись в очередь, объединение ещё не отправленных операций
  и обновление локальной сущности выполняются в транзакциях DAO. После записи
  вызывается `wake()`, при смене сети — `setOnline()`, при выходе — `close()`.
- `MascotVectorPainter` получает настроение, фазу дыхания от контроллера
  анимации, состояние нажатия и коды экипированных аксессуаров. Его передают
  в `CustomPaint` внутри `RepaintBoundary`.
- `MapActivityScreen` принимает данные маршрутов, точки РСО и источник тайлов.
  Клиент передаёт функции запроса точек в видимой области, открытия карточки
  точки и сохранения участка. Для редактирования нужны исходные номера точек
  и коэффициенты транспорта из API.
