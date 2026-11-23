## Задача в Jira и тип изменения

- Задача: `EC-XX` — ссылка: `https://renchelbob.atlassian.net/browse/EC-XX`
- Тип (`feat` / `fix` / `chore` / `docs` / `release`):

## Что сделано

- 

## Как проверено

- [ ] `uv run --with pyyaml python scripts/verify_contracts.py` проходит без ошибок
- [ ] Проверки линтера / тестов по затронутому модулю пройдены локально (`backend` / `mobile`)

## Чек-лист перед ревью

- [ ] Целевая ветка соответствует Git Flow (`feature/EC-XX-*` и `bugfix/EC-XX-*` в `develop`, `release/v*` и `hotfix/EC-XX-*` в `main`)
- [ ] Каталог `contracts/` не изменялся (либо приложен согласованный `CONTRACT_RFC`)
- [ ] В коде, конфигах и логах нет токенов, паролей и открытых персональных данных (152-ФЗ)
- [ ] Балансы `point_ledger`, PostGIS и SQLite не подменяются моками в тестах
- [ ] Настроен перекрёстный ревьюер из команды
