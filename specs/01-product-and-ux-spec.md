# 01 — Product & UX Specification (`EcoTrack`)

> **Target Audience**: Developer 2 (Flutter Client) & Mobile AI Coding Agents
> **Governing Contracts**: `contracts/openapi.yaml`, `contracts/client_sqlite_schema.sql`, `contracts/error_catalog.json`
> **UI Language**: Russian (`ru_RU`) for all user-facing strings; English for all code identifiers, routes, and state classes.

---

## 1. Design System & Visual Tokens

### 1.0 Visual Reference Canon (`/screens/`)
The `/screens/` directory is the **Locked Visual Reference Canon (Single Source of Visual Truth)** for all Flutter UI screens, card geometry, spacing, grayscale wireframe tokens, line-art fox mascot styling, and 5-tab bottom navigation bar. Every mobile developer and AI agent MUST inspect the matching PNG(s) below before writing any UI code:

| Reference PNG (`/screens/`) | Target Route / Scope | Notes & Allowed Product Deltas |
| :--- | :--- | :--- |
| `screens/wireframes.png` | Overall navigation & Architectural Wireframe Grayscale system | Master 24-frame panorama (`#01..#23`) |
| `screens/07_Onboarding_Compact_01_Приветствие.png` | `/onboarding` Step 1 | Welcome screen, line-art fox mascot, 3 slogans, `"Далее"` / `"Продолжить >"` |
| `screens/08_Onboarding_Compact_07_Препермишен_шагомера.png` | `/onboarding` Step 2 | Hardware step sensor pre-permission & optional GPS toggle |
| `screens/09_Onboarding_Compact_08_Подарки_и_152ФЗ.png` | `/onboarding` Step 3 + **In-Place OAuth 2.1 + PKCE Sign-In/Sign-Up** | 3 OAuth buttons replace `"Начать >"` directly in-place; 152-FZ checkbox MUST default unchecked (`false`); render clean Russian (`"зверёк"`, `"партнёров"`, fixing Figma typos `"зверек"`, `"партеров"`) |
| `screens/14_Main_Compact_16_Главная_Маскот_ФИНАЛ.png` | `/home` (Tab 3) | Top balance/avatar, line-art fox mascot, 2 collapsible Today cards, central `+` button |
| `screens/15_Calc_Compact_17_Калькулятор_поездок_ФИНАЛ.png` | `/map?mode=routes` (Tab 2 Route/CO₂ Calculator & Transport Annotation) | Top dual-mode toggle (`[ Мои маршруты ] \| [ Пункты РСО ]`), transport chips & segment controls |
| `screens/16_Stats_Compact_05_Статистика_обзор_ФИНАЛ.png` | `/stats` (Tab 1 Overview) | 7-day chart, Activity History preview, 3 Eco-Equivalents Bento cards (exact server values + 3 soft color exceptions) |
| `screens/17_Stats_Compact_26_График_выбросов_и_доли_ФИНАЛ.png` | `/stats/emissions` | `[ Дни \| Недели \| Месяцы ]` bar chart + average line + transport donut |
| `screens/18_Stats_Compact_24_История_активности_список_ФИНАЛ.png` | `/stats/history` | Paginated activity list with edit tap on Today/Yesterday |
| `screens/19_Profile_Compact_18_Профиль_и_настройки_152ФЗ_ФИНАЛ.png` | `/profile` (Tab 5 + 152-FZ Settings) | Profile card, 4-icon badges/wardrobe strip, Friends/Vehicle/RSO cards, 152-FZ consent & erasure controls |
| `screens/20_Shop_Compact_19_Витрина_промокодов_ФИНАЛ.png` | `/shop` (Tab 4 Catalog) | Balance, search, QR/Promo quick cards, filter chips, fictional partner disclaimer & coupons |
| `screens/21_Shop_Compact_20_Корзина_заказов_ФИНАЛ.png` | `/shop/cart` | Line items, balance/quantity/total summary, checkout CTA |
| `screens/22_Shop_Compact_21_Заказы_QR_коды_ФИНАЛ.png` | `/shop/orders/qr` | QR coupon cards (`Активен` / `Использован`), QR modal |
| `screens/23_Shop_Compact_22_Заказы_буквенный_промокод_ФИНАЛ.png` | `/shop/orders/promo` | Monospace promo code cards + copy action |

> **Typo & Legal Hygiene Override**: Figma wireframe copy on `screens/09_Onboarding_Compact_08_Подарки_и_152ФЗ.png` contains minor typos (`"партеров"`, `"зверек"`). Production Flutter UI MUST render clean Russian (`"партнёров"`, `"зверёк"`), and the 152-FZ consent checkbox MUST default to unchecked (`false`) despite being checked in the static Figma mockup.

### 1.1 Wireframe Grayscale Palette & Allowed Color Exceptions
EcoTrack uses a high-contrast **Architectural Wireframe Grayscale** visual system throughout the entire app, with strictly scoped semantic color exceptions on the Statistics Eco-Equivalents cards and the Weekly Leaderboard #1 badge.

| Token Name | Hex Value | Usage |
| :--- | :--- | :--- |
| `EcoColors.surfacePrimary` | `#FFFFFF` | Primary scaffold background, modal sheets, active segment pill |
| `EcoColors.inkPrimary` | `#1E1E1E` | Primary typography, active icons, primary CTA fill, vector mascot outlines, primary chart bars |
| `EcoColors.surfaceCard` | `#D9D9D9` | Standard Bento cards, unselected segmented controls, progress bar tracks |
| `EcoColors.surfaceSubtle` | `#ECECEC` | Secondary card backgrounds, input text fields, expandable card interiors, bottom sheet headers |
| `EcoColors.borderMuted` | `#B0B0B0` | 1.5dp wireframe card borders, dividers, inactive chip outlines |
| `EcoColors.fillDisabled` | `#C4C4C4` | Disabled buttons, locked badge silhouettes, filtered vehicle GPS segments |
| `EcoColors.inkSecondary` | `#868686` | Subtitles, captions, timestamps, legal disclaimers, unallocated indoor step dots |
| `EcoColors.eqForestBg` | `#E3F2E6` | **Exception 1**: Stats Eco-Equivalent "Forest" (`Лес`) card background |
| `EcoColors.eqForestInk` | `#2E7D32` | **Exception 1**: Stats Eco-Equivalent "Forest" (`Лес`) icon & primary metric |
| `EcoColors.eqFuelBg` | `#FFF3E0` | **Exception 2**: Stats Eco-Equivalent "Gasoline" (`Бензин`) card background |
| `EcoColors.eqFuelInk` | `#D99B26` | **Exception 2**: Stats Eco-Equivalent "Gasoline" (`Бензин`) icon & Weekly Leaderboard #1 badge |
| `EcoColors.eqAirBg` | `#E3F2FD` | **Exception 3**: Stats Eco-Equivalent "Clean Air" (`Воздух`) card background |
| `EcoColors.eqAirInk` | `#1565C0` | **Exception 3**: Stats Eco-Equivalent "Clean Air" (`Воздух`) icon & primary metric |

### 1.2 Typography Scale (`EcoTypography`)
Font family: `Inter` (bundled in `mobile/assets/fonts/`) with system `Roboto` / `SF Pro` fallback. Tabular numerals (`FontFeature.tabularFigures()`) MUST be enabled on all step counters, CO₂ gram readouts, timers, and point balances.

| Style Token | Size (`sp`) | Weight | Line Height | Usage |
| :--- | :--- | :--- | :--- | :--- |
| `displayHero` | `32` | `w800` | `38` | Home screen primary metric, Drilldown headline total |
| `headlineLarge` | `24` | `w700` | `30` | Screen titles, onboarding headlines, modal titles |
| `titleMedium` | `18` | `w700` | `24` | Bento card headers, bottom sheet headers |
| `bodyLarge` | `16` | `w500` | `22` | Primary body copy, list item titles, button labels |
| `bodyMedium` | `14` | `w400` | `20` | Card subtitles, explanations, form labels |
| `labelSmall` | `12` | `w600` | `16` | Badges (`Авторасчёт`), chips, axis labels, legal attribution |

### 1.3 Layout Grid, Radii & Touch Targets
- **Base Spacing Grid**: Multiples of `4 dp` (`4`, `8`, `12`, `16`, `20`, `24`, `32`). Horizontal screen padding is `16 dp`.
- **Corner Radii**:
  - Cards & Bento tiles: `20 dp` (`BorderRadius.circular(20)`) with `1.5 dp` border (`#B0B0B0` or `#1E1E1E`).
  - Bottom sheets: `28 dp` top-left and top-right.
  - Buttons, segmented toggles & filter chips: `999 dp` (full pill).
- **Touch Target Invariant**: Every interactive button, icon, chip, map pin, and checkbox MUST have a minimum hit-test box of `48x48 dp` (`ConstrainedBox(constraints: BoxConstraints(minWidth: 48, minHeight: 48))`).

### 1.4 Deterministic Error Presentation (`contracts/error_catalog.json`)
Raw `SnackBar` calls with ad-hoc text are **STRICTLY FORBIDDEN**. Every error returned by `ApiClient` or local storage is an `AppError` resolved from `contracts/error_catalog.json` and handled deterministically by `EcoErrorBannerPresenter` according to `client_action`:

| `client_action` | UI Behavior in Flutter Client |
| :--- | :--- |
| `none` | Silent log only; no UI interruption. |
| `refresh_token` | Handled transparently by `AuthRefreshInterceptor` (single-flight lock on `/api/v1/auth/refresh`). |
| `force_logout` | Clears secure storage tokens, resets SQLite user session, navigates to `/onboarding?step=3` (`/auth/login` redirects to `/onboarding?step=3`) and shows top banner with `ui_message_ru`. |
| `show_inline` | Renders `ui_message_ru` directly beneath the offending form input or segment selector in `12 sp` bold `#1E1E1E` with a warning icon. |
| `show_banner` | Displays a single top non-stacking floating wireframe banner (`EcoTopBanner`) with `ui_message_ru` for `4000 ms` (replaces any existing banner). |
| `queue_retry` | Enqueues payload into SQLite `offline_mutation_outbox` and shows subtle top pill: `"Сохранено офлайн · Синхронизируем при появлении сети"`. |
| `open_phone_modal` | Opens non-dismissible `GoogleFormalPhoneModal` over current route. |
| `open_consent_screen` | Opens `Fz152ConsentResolutionModal` allowing user to re-grant 152-FZ consent or proceed to account deletion. |

---

## 2. Onboarding & Authentication Flow

### 2.1 3-Step Onboarding Carousel (`/onboarding`)
Shown on first launch when no active session exists. Contains a top-right `"Пропустить"` button on Steps 1–2 (jumps directly to Step 3, because Step 3 contains the mandatory 152-FZ checkbox).

1. **Step 1 — Value Proposition & Mascot**:
   - **Illustration**: `FoxMascotWidget` in `happy` state waving inside a wireframe circular frame.
   - **Title**: `"Шагайте по городу — копите эко-вклад"`
   - **Body**: `"EcoTrack считает ваши шаги с датчиков смартфона, переводит пешие маршруты в сэкономленные граммы CO₂ и награждает эко-баллами ★."`
   - **Primary Button**: `"Далее"`
2. **Step 2 — Hardware Step Sensors & Optional Interval GPS**:
   - **Illustration**: Schematic wireframe of pedometer waveform + map polyline.
   - **Title**: `"Точный учёт без ручного ввода"`
   - **Body**: `"Шаги считываются автоматически через системные датчики здоровья. Если включить запись GPS-маршрута, вы сможете отмечать, вместо какого транспорта прошли пешком, получая 100% коэффициент точности."`
   - **Action Toggles**:
     - Card 1: `"Доступ к датчику шагов (обязательно для начисления ★)"` — button `"Запросить доступ"`.
     - Card 2: `"Фоновая запись маршрута GPS (опционально)"` — switch default `OFF`, caption `"Если GPS выключен, приложение автоматически считает эковклад по базовой формуле (80% × 0.7)."`.
   - **Primary Button**: `"Далее"`
3. **Step 3 — Mascot `%` Gift, Mandatory 152-FZ Consent & In-Place OAuth (`screens/09_Onboarding_Compact_08_Подарки_и_152ФЗ.png`)**:
   - **Illustration**: `FoxMascotWidget` holding a schematic wireframe gift box labeled `"%"` inside the circular wireframe container (`"+100 ★ за старт"`).
   - **Title**: `"Забота о природе приносит пользу и подарки"`
   - **Body (clean Russian, correcting Figma wireframe typos `"зверек"` / `"партеров"`)**:
     - Card 1: `"Виртуальный зверёк растёт и развивается вместе с вашими успехами"`
     - Card 2: `"Обменивайте накопленные баллы на скидки и промокоды от наших партнёров"`
   - **Mandatory 152-FZ Checkbox (`48x48 dp` tap area, MUST default to unchecked `false`)**:
     - Label: `"Я принимаю Политику конфиденциальности и даю согласие на обработку персональных данных (включая показатели активности и геопозицию) согласно 152-ФЗ РФ."`
     - Secondary link beneath checkbox: `"Читать полный текст согласия 152-ФЗ"` (opens modal sheet with full policy version `"1.0.0-2026"`).
   - **In-Place OAuth CTA Replacement**: Directly on `screens/09_Onboarding_Compact_08_Подарки_и_152ФЗ.png`, the bottom wireframe CTA `"Начать >"` is **replaced in-place** by the vertical stack of 3 OAuth 2.1 + PKCE sign-in / registration buttons (`"Войти через Яндекс ID"`, `"Войти через VK ID"`, `"Войти через Google (Лаб. режим)"`). All 3 OAuth buttons stay disabled (`#C4C4C4`) until the mandatory 152-FZ consent checkbox is checked (`true`).

### 2.2 In-Place OAuth 2.1 + PKCE Sign-In & Registration (`/onboarding?step=3`)
There is **NO separate email/password login or registration screen** and **NO separate `/auth/login` UI screen** — OAuth 2.1 + PKCE handles both new-user sign-up and returning-user sign-in via `POST /api/v1/auth/oauth/exchange`. Returning signed-out users navigate straight to `/onboarding?step=3` (`/auth/login` aliases and redirects to `/onboarding?step=3`).

- **Placement**: Rendered directly in the bottom CTA slot of Step 3 (`screens/09_Onboarding_Compact_08_Подарки_и_152ФЗ.png`), replacing `"Начать >"`.
- **Gate**: All 3 provider buttons remain disabled (`#C4C4C4` fill, muted text) until the mandatory 152-FZ consent checkbox (`default: false`) is checked.
- **Provider Buttons (vertical stack, `56 dp` height each, full width, wireframe grayscale tokens)**:
  1. **Яндекс ID**: `"Войти через Яндекс ID"` (Primary `#1E1E1E` fill, `#FFFFFF` text when enabled; `#C4C4C4` fill when disabled)
  2. **VK ID**: `"Войти через VK ID"` (`#FFFFFF` fill, `1.5 dp` `#1E1E1E` border, `#1E1E1E` text when enabled; `#C4C4C4` fill / muted border when disabled)
  3. **Google**: `"Войти через Google (Лаб. режим)"` (`#ECECEC` fill, `1.5 dp` `#B0B0B0` border, `#1E1E1E` text when enabled; `#C4C4C4` fill / muted border when disabled)

### 2.3 Google OAuth 406-FZ Academic/Lab Warning Banner & Formal Phone Modal
When the user selects **Google** (`provider = "google"`):
1. **Top Persistent Academic/Lab Warning Banner (`GoogleLabModeBanner`)**:
   - Displayed immediately at the top of the screen after Google OAuth exchange (`is_foreign_provider_lab_mode == true`) and persisted at the top of Tab 5 (`Profile & Settings`):
   - **Exact Copy**: `"Внимание: регистрация и вход через иностранный провайдер (Google OAuth) не соответствуют требованиям 406-ФЗ РФ. Данный способ входа включён исключительно для академического / лабораторного тестирования."`
   - **Button inside banner**: `"Понятно"` (collapses banner to a compact pill `"Лаб. режим 406-ФЗ (Google)"` for the current session).
2. **Post-Google Formal Phone Number Modal (`GoogleFormalPhoneModal`)**:
   - Automatically presented as a non-dismissible modal bottom sheet whenever `user.requires_formal_phone == true` (or on `GOOGLE_FORMAL_PHONE_REQUIRED` error).
   - **Title**: `"Укажите контактный телефон"`
   - **Body**: `"Для завершения лабораторной авторизации через иностранный провайдер укажите номер телефона. Реальная отправка SMS-кода в демо-режиме не производится."`
   - **Input Field**: Masked input `+7 (___) ___-__-__` (normalizes to E.164 `+7XXXXXXXXXX`, validated against `^\+[1-9][0-9]{7,14}$`).
   - **Primary CTA**: `"Сохранить и продолжить"` -> calls `POST /api/v1/auth/google-phone` with `Idempotency-Key`.

---

## 3. 5-Tab Navigation Shell (`FloatingBottomNavBar`)

The application shell uses `StatefulShellRoute.indexedStack` in `go_router ^15.x+` with **strictly 5 tabs**. Adding a 6th tab is prohibited.

| Tab Index | Route Path | Russian Label | Wireframe Icon | Special Styling / Behavior |
| :--- | :--- | :--- | :--- | :--- |
| **0** | `/stats` | `"Статистика"` | Bar chart icon | Standard tab item |
| **1** | `/map` | `"Карта"` | Route pin / polyline icon | Unified Dual-Mode Map (`?mode=routes` or `?mode=rso`) |
| **2** | `/home` | `"Главная"` | Schematic fox head / home icon | **Raised Center Dome (`64x64 dp` circle `#1E1E1E` active)** |
| **3** | `/shop` | `"Магазин"` | Eco bag / star coupon icon | Standard tab item |
| **4** | `/profile` | `"Профиль"` | User badge / gear icon | Contains Friends, My Vehicle & RSO Map shortcut |

---

## 4. Tab 3 — Home Screen (`/home`)

### 4.1 Top Header Bar
- **Left**: Points Balance Pill (`"★ {points_balance}"`) — tapping opens `/ledger` history modal.
- **Center**: Streak Counter Pill (`"🔥 {current_streak_days} дн."`). If `streak_freeze_count > 0`, displays a snowflake shield badge (`"❄ {streak_freeze_count}"`) next to the flame.
- **Right**: Circular User Avatar (`48x48 dp`) — tapping switches to Tab 4 (`Index 4`, `/profile`).

### 4.2 Interactive Schematic Vector Mascot (`FoxMascotWidget`)
Occupies the upper-middle hero stage (`240 dp` height) rendered via custom vector `CustomPainter` (`MascotVectorPainter`) wrapped in a `RepaintBoundary`:
- **Idle Breathing Animation**: Continuous `3200 ms` sine-wave chest/body vertical scale (`0.985` to `1.015`) and subtle tail sway.
- **Press / Hold Squinting Reaction**: On `GestureDetector.onTapDown` / `onLongPressStart`, the mascot's eyes smoothly morph into closed `> <` squinting arcs, ears flatten slightly, and a speech bubble appears (`"Щекотно! Пойдём гулять?"`). Releasing returns to the current mood state over `250 ms`.
- **3 Mood States Tied to Daily CO₂ Goal Progress ($P = \text{total\_co2\_saved\_grams} / \text{daily\_co2\_goal\_grams}$)**:
  1. **0% Progress ($P == 0$) — `sleepy`**: Curled tail, half-closed eyes, floating `"Zzz"` vector glyphs. Status caption: `"Зверёк дремлет · Начните шагать, чтобы разбудить его!"`
  2. **1% to 99% Progress ($0 < P < 1.0$) — `happy`**: Upright ears, alert eyes, steady tail wag. Status caption: `"Зверёк бодрствует · До цели дня осталось {remaining_grams} г CO₂"`
  3. **100%+ Progress ($P \ge 1.0$) — `thriving`**: Joyful arc eyes, sparkling vector aura around body. Status caption: `"Дневная цель выполнена ({percent}%)! Зверёк гордится вами!"`
- **Equippable Vector Accessories**: Dynamically paints unlocked & equipped vector layer from `user.mascot.equipped_accessory_code` (`leaf_sprout_hat`, `knit_green_scarf`, `solar_shades`, `moss_crown`, `firefly_aura`).

### 4.3 "First Entry / Empty Day" State
When `validated_steps == 0` for today:
- Displays a dashed wireframe prompt card beneath the mascot:
  - **Title**: `"Сегодня шагов пока нет"`
  - **Body**: `"Прогуляйтесь со смартфоном в кармане. Шаги синхронизируются автоматически с датчиков устройства."`
  - **Secondary Action**: `"Обновить датчики сейчас"` (triggers immediate `StepSensorBridge.syncNow()`).

### 4.4 Stacked Expandable "Сегодня" Cards & Central `+` Button
Two collapsible wireframe Bento cards (`AnimatedSize` + `ExpansionTile` semantics):
1. **Card 1 — `Активность сегодня`**:
   - **Collapsed Header**: `"Активность сегодня"` · `"{validated_steps} / {daily_step_goal} шагов"` · `"+{points_awarded_for_day} ★"`
   - **Expanded Content**:
     - Linear wireframe progress bar (`validated_steps / daily_step_goal`).
     - 3 metric columns: `"Дистанция: {total_step_distance_km} км"`, `"Калории: {estimated_kcal} ккал"`, `"Длина шага: {stride_length_cm} см"`.
2. **Card 2 — `Экономия CO₂ сегодня`**:
   - **Collapsed Header**: `"Экономия CO₂ сегодня"` · `"{total_co2_saved_grams} / {daily_co2_goal_grams} г CO₂"`
   - **Status Badge**:
     - If `is_auto_calculated == true`: Pill `"Авторасчёт (80% × 0.7)"` (`#ECECEC` fill, `#1E1E1E` border).
     - If `is_auto_calculated == false`: Pill `"Подтверждено по GPS (100%)"` (`#1E1E1E` fill, `#FFFFFF` text).
   - **Expanded Content**:
     - Breakdown row 1: `"Размечено по маршруту GPS: {allocated_co2_saved_grams} г ({allocated_gps_distance_m} м)"`
     - Breakdown row 2: `"Базовый авторасчёт по остатку шагов: {auto_default_co2_saved_grams} г ({unallocated_step_distance_m} м)"`
     - **Action Button**: `"Уточнить транспорт на карте →"` (deep-links to Tab 2 `/map?mode=routes&date=today`).
3. **Central `+` Action Button**:
   - Floating pill button `"＋ Отметить маршрут на карте"` beneath the Today cards -> navigates directly to Tab 2 (`/map?mode=routes`).

---

## 5. Tab 2 — Map & Activity (`/map`)

### 5.1 Top Oval Mode Toggle
Pinned floating header at top of map viewport (`52 dp` height, `#FFFFFF` surface, `1.5 dp` `#1E1E1E` border, `999 dp` radius):
- Left segment: `[ Мои маршруты ]`
- Right segment: `[ Пункты РСО ]`
Switching modes preserves the current map camera center/zoom and swaps the active overlay layers and bottom sheet controls.

### 5.2 Mode A: `[ Мои маршруты ]` (Route Tracking & Transport Annotation)
1. **Sub-Header Controls**:
   - **Date Selector Pill**: `[ Сегодня ]` | `[ Вчера ]` (enforces the 48-hour server edit window; older dates are viewed read-only via Stats History).
   - **GPS Status & Interval Pill**:
     - When `is_gps_tracking_enabled == true`: `"● GPS активен ({gps_interval_seconds} с)"` — tapping opens quick interval sheet (`5 с`, `15 с`, `30 с`, `60 с`).
     - When `is_gps_tracking_enabled == false`: `"○ GPS выключен"` — tapping triggers permission & enables tracking.
2. **Route Polyline & Segment Visual Encoding**:
   - **Unallocated Walking (`motion_class == walking`, not yet annotated)**: Dashed `#1E1E1E` line (`4 dp` stroke) with tappable start/end waypoint handles.
   - **Annotated Walking (`route_segment_allocations`)**: Solid `#1E1E1E` line (`6 dp` stroke) with a floating transport pill badge (`"🚌 Автобус · -142 г CO₂"`).
   - **Indoor Pacing (`motion_class == indoor_pacing`, `delta_steps > 0, delta_d ~ 0`)**: Dotted `#868686` cluster marker with tooltip `"Ходьба в помещении (учтена в общем числе шагов)"`.
   - **Suspected Vehicle Ride (`motion_class == vehicle_suspected`, `delta_d >> 0, delta_steps ~ 0`)**: Thin `#C4C4C4` strikethrough line; tapping shows inline banner `"Участок на транспорте (высокая скорость без шагов) не может быть отмечен как пеший."`
3. **Transport Replacement Bottom Sheet (`TransportAllocationBottomSheet`)**:
   - Opens when user taps an unallocated walking segment or adjusts start/end sequence sliders (`start_seq_no` .. `end_seq_no`).
   - **Title**: `"Участок маршрута: {segment_distance_m} м ({segment_steps} шагов)"`
   - **Subtitle**: `"Укажите, вместо какого транспорта вы прошли пешком:"`
   - **Primary Transport Chips (Horizontal Wrap)**:
     - `[ Автобус (82 г/км) ]` (`bus`)
     - `[ Метро (28 г/км) ]` (`metro`)
     - `[ Трамвай (35 г/км) ]` (`tram`)
     - `[ Мой авто ({user_car_g_km} г/км) ]` (`personal_car` — if not configured, shows subtitle `"Настроить авто"` or defaults to `192 г/км`)
     - `[ Авто (средний) ]` (expands the 4 average car presets below)
   - **Secondary Average Car Presets Row (shown when `[ Авто (средний) ]` is active)**:
     - `[ Компакт (145 г/км) ]` (`car_compact`)
     - `[ Седан (192 г/км) ]` (`car_sedan` — preselected default)
     - `[ Кроссовер (255 г/км) ]` (`car_suv`)
     - `[ Электро (58 г/км) ]` (`car_ev`)
   - **Real-Time Hybrid CO₂ Delta Preview Box**:
     - `"Расчёт по выбранному транспорту (коэф. 1.0): {exact_co2_g} г CO₂"`
     - `"Вместо базового авторасчёта (80% × автобус × 0.7): +{delta_co2_g} г CO₂"`
   - **Buttons**:
     - Primary: `"Сохранить участок"` -> dispatches `PUT /api/v1/activity/daily/{activity_date}/allocations` with UUIDv7 `Idempotency-Key`.
     - Secondary (if editing existing allocation): `"Удалить разметку участка"` -> dispatches `DELETE /api/v1/activity/daily/{activity_date}/allocations/{allocation_id}`.
4. **Empty State when GPS is Disabled**:
   - Floating bottom card over map:
     - **Title**: `"Геолокация маршрутов выключена"`
     - **Body**: `"Сейчас ваш эковклад рассчитывается автоматически по шагам: 80% дистанции приравнивается к замене автобуса с коэффициентом достоверности 0.7. Включите запись маршрута, чтобы выделять реальные пешие отрезки на карте с коэффициентом 1.0."`
     - **Primary Button**: `"Включить запись GPS-маршрута"`

### 5.3 Mode B: `[ Пункты РСО ]` (Recycling & Waste Map)
1. **Fraction Filter Bar (Horizontal Scroll Chips below Mode Toggle)**:
   - `"Все"`, `"Пластик"` (`plastic`), `"Стекло"` (`glass`), `"Бумага"` (`paper`), `"Металл"` (`metal`), `"Тетрапак"` (`tetra_pak`), `"Батарейки"` (`batteries`), `"Электроника"` (`electronics`), `"Одежда"` (`clothes`), `"Опасные"` (`hazardous`), `"Крышечки"` (`caps`), `"Фандоматы"` (`mixed_recyclables`), `"Урны"` (`general_bin`).
2. **Map Pins, Clustering & Legal Attribution**:
   - Uses `flutter_map_marker_cluster` to group dense points into monochrome circular count badges (`#1E1E1E` fill, `#FFFFFF` count).
   - Individual pins show a high-contrast wireframe recycling icon; points with `status == unverified` or `trust_score < 50` render with a dashed border and `?` badge.
   - **Mandatory Legal Attribution Strip** anchored above bottom nav bar: `"© Участники OpenStreetMap (ODbL 1.0) · data.mos.ru · Муниципальные реестры"`.
3. **Waste Point Detail Bottom Sheet (`WastePointDetailSheet`)**:
   - **Header**: `{title}` + Trust Badge (`"Доверие {trust_score}%"`).
   - **Freshness Subtitle**: `"Проверено {days_ago} дн. назад · Подтверждений: {confirmations_count}"` (or `"Ещё не проверялось пользователями"` if `last_verified_at == null`).
   - **Metadata Rows**: Address (`{address_text}`), Operator (`{operator_name}`), Schedule (`{opening_hours}`), Source attribution (`{attribution_text}`).
   - **Accepted Fractions**: Wrap of monochrome pills with Russian fraction names.
   - **External Navigation CTA**: `"Построить маршрут во внешнем навигаторе"` — opens chooser for `yandexmaps://maps.yandex.ru/?rtext=~{lat},{lon}&rtt=pd`, `dgis://2gis.ru/routeSearch/rsType/pedestrian/to/{lon},{lat}`, or system `geo:{lat},{lon}`.
   - **Crowdsourced Verification Section (`"Актуальна ли точка?"`)**:
     - 4 action chips (`POST /api/v1/map/waste-points/{point_id}/reports`):
       1. `"✓ Работает"` (`confirm_working`, `+15 ★`)
       2. `"⚠ Переполнен"` (`overflowing`)
       3. `"✕ Закрыт / Нет бака"` (`missing_bin`)
       4. `"≠ Неверные фракции"` (`wrong_fractions`)
4. **Suggest New Point Flow (`+ Предложить точку`)**:
   - Floating action pill `"+ Предложить точку"` in bottom-right corner of map.
   - Opens `SuggestWastePointModal` with draggable center map crosshair, title input, fraction multi-select chips, optional opening hours/comment, and `"Отправить на карту"` (`POST /api/v1/map/waste-points/suggestions`).

---

## 6. Tab 1 — Stats & Social Challenges (`/stats`)

### 6.1 Emissions 7-Day Card & Drilldown (`/stats/emissions`)
- **Overview Card on Tab 1**:
  - Header: `"Сэкономлено CO₂ за 7 дней"` · `"{period_total_co2_saved_grams} г"`
  - Stacked bar chart (`fl_chart`) showing daily bars split into solid `#1E1E1E` (`allocated_co2_saved_grams`) and hatched/light `#B0B0B0` (`auto_default_co2_saved_grams`).
  - Tap opens `EmissionsDrilldownScreen`:
    - Segmented control: `[ Дни ] | [ Недели ] | [ Месяцы ]` (`GET /api/v1/stats/emissions?period=...`).
    - Interactive bar chart with touch tooltip (`"{date}: {total_g} г CO₂ ({steps} шагов)"`).
    - **Transport Replacement Donut Chart**: Breakdown of CO₂ saved by transport mode (`Автобус`, `Метро`, `Трамвай`, `Мой авто`, `Авто (средний)`, `Авторасчёт по шагам`).

### 6.2 Activity History Preview & Drilldown (`/stats/history`)
- **Overview Card**: Shows last 3 days of activity; button `"Вся история активности →"` opens `ActivityHistoryDrilldownScreen`.
- **Drilldown List (`GET /api/v1/stats/history`)**:
  - Paginated list of days showing date, steps, total distance (`км`), CO₂ saved (`г`), points earned (`+★`), and calculation badge (`"Подтверждено по GPS"` vs `"Авторасчёт 80% × 0.7"`).
  - Tapping Today or Yesterday opens Tab 2 `/map?mode=routes&date={activity_date}` for editing.

### 6.3 Colored Bento Eco-Equivalents Grid & Drilldowns (`/stats/equivalents`)
The **only** colored section in the app (`GET /api/v1/stats/equivalents`). Displays 3 Bento cards with **exact server-computed metrics** (zero hardcoded `~X` placeholders):
1. **Forest Card (`Лес`)** — bg `#E3F2E6`, accent `#2E7D32`:
   - Metric: `"{trees_planted_equivalent} дерева"`
   - Subtitle: `"Поглощают столько же CO₂ в год"`
2. **Gasoline & Car Card (`Бензин и Авто`)** — bg `#FFF3E0`, accent `#D99B26`:
   - Metric: `"{car_km_avoided} км на авто"`
   - Subtitle: `"Не сожжено {liters_avoided} л топлива"`
3. **Clean Air & Energy Card (`Воздух и Энергия`)** — bg `#E3F2FD`, accent `#1565C0`:
   - Metric: `"{smartphone_charges_equivalent} зарядок смартфона"`
   - Subtitle: `"Или {led_bulb_hours_equivalent} ч работы LED-лампы"`
Tapping any card opens `EcoEquivalentsDrilldownScreen` with lifetime vs. current-week tabs and exact physical conversion formulas from `specs/02-domain-math-and-algorithms.md`.

### 6.4 Weekly Friends CO₂ Leaderboard Card
- **Header**: `"Рейтинг друзей за неделю (CO₂)"`
- **Rows (`GET /api/v1/friends/leaderboard`)**:
  - Displays rank `#1..#N`, avatar, `display_name`, monochrome horizontal progress bar proportional to the leader's `weekly_co2_saved_grams`, and exact gram readout.
  - **Rank #1 Leader Badge**: Warm gold pill `"👑 Лидер недели"` (`#D99B26`).
  - If a friend disabled `is_stats_visible_to_friends`, their row displays `"Статистика скрыта настройками приватности"`.

### 6.5 Cooperative "Shared Forest" Weekly Challenge Card
- **Header**: `"Кооперативный челлендж: «Общий лес»"`
- **Reward Badge**: `"+50 ★ каждому участнику при выполнении"`
- **Progress Section (`GET /api/v1/challenges/shared-forest/current`)**:
  - Progress bar: `"{current_co2_saved_grams} / {target_co2_saved_grams} г CO₂"`
  - Subtitle: `"Высажено виртуальных деревьев: {trees_equivalent_planted} · Ваш вклад: {my_contributed_co2_grams} г"`
  - Top 3 friend contributors strip at bottom of card.

---

## 7. Tab 4 — Shop & Orders (`/shop`)

### 7.1 Catalog Screen (`/shop`)
- **Mandatory Top Fictional Disclaimer Banner**:
  - `"Демонстрационный магазин: все бренды партнёров, промокоды и QR-купоны являются вымышленными."`
- **Top Bar**:
  - Search field: `"Поиск купонов и эко-товаров..."`
  - Action buttons: `"Мои QR и промокоды"` -> `/shop/orders/qr`, and `"Корзина ({cart_count})"` -> `/shop/cart`.
- **Category Filter Chips**:
  - `"Все"`, `"Виртуальные бонусы"`, `"Гардероб зверька"`, `"Еда и напитки"`, `"Товары для дома"`, `"Микромобильность"`.
- **Product Grid / List (`GET /api/v1/shop/items`)**:
  - Each card shows vector illustration (`image_asset_key`), partner name + fictional disclaimer caption, `title`, `price_points` (`"{price_points} ★"`), remaining stock or `"Виртуальный товар"`, and `"+ В корзину"` button.
  - Tapping a card opens `ShopItemDetailModal` with full description, daily limit (`"Лимит: до {max_per_user_per_day} шт. в день"`), and `"Добавить в корзину за {price_points} ★"`.

### 7.2 Full-Screen Cart (`/shop/cart`)
- **AppBar**: Left Back button (`←`), Title `"Корзина"`, Right Trash icon (`🗑 "Очистить корзину"`).
- **Line Items**: Title, partner subtitle, unit price `★`, quantity stepper (`-` / `+`, bounded by `1..max_per_user_per_day`), line total `★`.
- **Bottom Summary Bar**:
  - `"Ваш баланс: {points_balance} ★"`
  - `"Итого к списанию: {cart_total_points} ★"`
  - If `cart_total_points > points_balance`: Inline warning `"Нехватка {deficit} ★ для оформления заказа"` and disabled CTA.
  - Primary CTA: `"Оформить заказ за {cart_total_points} ★"` -> calls `POST /api/v1/shop/orders` with UUIDv7 `Idempotency-Key`.

### 7.3 Full-Screen Orders: QR & Promo Codes (`/shop/orders/qr` & `/shop/orders/promo`)
- **AppBar**: Left Back button (`←`), Title `"Мои заказы и купоны"`, Segmented switch `[ QR-купоны ] | [ Промокоды ]`.
- **QR Orders View (`OrdersQrScreen`)**:
  - Cards for `partner_qr` items showing title, status pill (`Активен` / `Использован`), expiration date, and button `"Показать QR-код"` (opens high-contrast modal rendering `qr_payload` via `qr_flutter` + disclaimer `"Демонстрационный QR-код"`).
- **Promo Orders View (`OrdersPromoScreen`)**:
  - Cards for `partner_coupon` and virtual items showing `coupon_code` in monospace font with button `"Скопировать код"` (copies to clipboard and shows top banner `"Промокод {coupon_code} скопирован"`).

---

## 8. Tab 5 — Profile & Settings (`/profile`)

### 8.1 Profile Header Card
- Avatar circle (`64x64 dp`, tappable to cycle schematic vector avatar seeds), editable `display_name` (inline edit icon), email/provider badge (`Яндекс ID`, `VK ID`, or `Google · Лаб. режим`), and copyable `friend_code` pill (`"Код друга: {friend_code}"`).

### 8.2 4-Icon Badges & Mascot Accessories Strip (`/profile/badges`)
- Horizontal Bento card displaying 4 preview icons (unlocked badges/accessories in `#1E1E1E`, locked in `#C4C4C4`) + `"Все достижения и гардероб →"`.
- Tapping opens `BadgesAndAccessoriesScreen` with 2 tabs:
  - **Tab 1 `[ Достижения ]`**: Full list from `GET /api/v1/badges` with progress bars (`{current_value} / {threshold_value}`), reward (`+{reward_points} ★`), and unlock timestamp.
  - **Tab 2 `[ Гардероб зверька ]`**: Full list from `GET /api/v1/mascot/inventory` with live `FoxMascotWidget` preview stage and `"Надеть"` / `"Снять"` button (`PUT /api/v1/users/me/mascot/accessory`).

### 8.3 Bento Subsections: Friends, My Vehicle & Recycling Map Shortcut
1. **Friends Card (`Друзья`) -> `/profile/friends` (`FriendsScreen`)**:
   - **Top Card**: Own `friend_code` (`ECO-XXXX-XXXX`), button `"Показать мой QR"`, button `"Сканировать QR друга"` (opens camera sheet with `mobile_scanner`), and text input `"Ввести код друга ECO-XXXX-XXXX"` -> `"Отправить заявку"`.
   - **Incoming Requests Section (`Входящие заявки`)**: Accept (`"Принять"`) and Decline (`"Отклонить"`) buttons.
   - **Accepted Friends List (`Мои друзья`)**: Shows friend's avatar, `display_name`, streak, weekly CO₂ saved, and the **Wake-Up Mascot Button**:
     - Active state: `"🔔 Разбудить зверька"` (`POST /api/v1/friends/{friend_user_id}/nudge`).
     - Cooldown state (`can_send_wakeup_nudge_today == false`): Disabled pill `"Зверёк уже разбужен сегодня"`.
2. **My Vehicle Card (`Мой автомобиль`) -> `/profile/vehicle` (`MyVehicleScreen`)**:
   - Allows configuring personal car so `[ Мой авто ]` on the route map uses exact emissions instead of the `192 г/км` fallback:
   - **Fields**:
     - Vehicle Name (`"Название авто"`, default `"Мой автомобиль"`).
     - Fuel Type (`"Тип топлива / двигателя"`): `Бензин АИ-92`, `Бензин АИ-95`, `Бензин АИ-98`, `Дизель (ДТ)`, `Газ Пропан (LPG)`, `Газ Метан (CNG)`, `Гибрид`, `Электромобиль (кВт·ч)`.
     - Consumption per 100 km slider & numeric field (`"Средний расход на 100 км"`: `0.5 – 50.0` L or kWh).
   - **Live Formula Readout Card**:
     - `"Расчётный выброс вашего авто: {computed_co2_g_per_km} г CO₂ / км ({computed_co2_g_per_meter} г / м)"`
   - **Buttons**: `"Сохранить автомобиль"` (`PUT /api/v1/users/me/vehicle`) and `"Удалить авто"` (`DELETE /api/v1/users/me/vehicle`).
3. **Recycling Map Shortcut Card (`Карта пунктов РСО`)**:
   - Tapping navigates directly to Tab 2 (`Index 1`) with `mode = Recycling Map` (`/map?mode=rso`).

### 8.4 Sliders, GPS Preferences, Privacy & 152-FZ Legal Controls
- **Eco-Goals Sliders (`Мои дневные цели`)**:
  - Daily Steps Slider: `3 000` to `20 000 шагов` (step `500`, default `8 000`).
  - Daily CO₂ Saved Slider: `500` to `5 000 г CO₂` (`0.5 – 5.0 кг`, step `100 г`, default `1 000 г`).
- **GPS Tracking Preferences (`Настройки трекинга маршрутов`)**:
  - Switch: `"Записывать маршрут GPS для разметки транспорта"` (`is_gps_tracking_enabled`).
  - Interval Selector: `5 сек (высокая точность)`, `15 сек (оптимально)`, `30 сек (экономия заряда)`, `60 сек (минимум)`.
- **Privacy & Notifications Toggles**:
  - Switch `"Делиться эко-статистикой с друзьями"` (`is_stats_visible_to_friends`).
  - Switch `"Push-уведомления (напоминания и «разбудить зверька»)"`.
- **152-FZ Personal Data & Account Management (`Управление данными 152-ФЗ`)**:
  1. `"Политика конфиденциальности и журнал согласий 152-ФЗ"` -> opens sheet showing policy text and timestamped entries from `GET /api/v1/users/me/consents`.
  2. `"Отозвать согласие на обработку ПДн (152-ФЗ)"` -> opens confirmation dialog warning that step/GPS processing will pause until re-granted (`POST /api/v1/users/me/consents` with `action = "revoked"`).
  3. `"Удалить аккаунт и все персональные данные (ст. 21 152-ФЗ)"` -> opens 2-step destructive confirmation modal requiring user to type `"DELETE_MY_DATA_152FZ"`. Calls `DELETE /api/v1/users/me` and displays the cryptographic deletion receipt (`receipt_id`, `anonymized_user_hash`, `verification_signature`).
  4. `"Выйти из аккаунта"` -> calls `POST /api/v1/auth/logout` and clears local session.

---

## 9. Exhaustive Screen State Matrix

Every screen and modal MUST implement all 5 deterministic states below:

| Screen / Modal | Loading State | Empty State | Error State (`error_catalog.json`) | Offline State (SQLite WAL + Outbox) | Populated State |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Onboarding & In-Place OAuth (`/onboarding?step=3`)** | Wireframe spinner inside active OAuth button; other buttons disabled | N/A (static onboarding content always present) | Top `EcoTopBanner` with `OAUTH_CODE_EXCHANGE_FAILED` or `OAUTH_PKCE_VERIFICATION_FAILED` copy | Banner `"Нет подключения к сети. Для первого входа требуется интернет."` | 3 OAuth buttons replacing `"Начать >"` + 152-FZ consent gate + Google lab mode banner/phone modal |
| **Tab 3: Home Screen** | Skeleton wireframe placeholders for balance, streak, and 2 Today cards; mascot in idle breathing | `"Сегодня шагов пока нет"` dashed card when `validated_steps == 0`; mascot in `sleepy` state | Top banner with `ui_message_ru`; retains last known SQLite profile & step summary | Renders `local_user_profile` + `local_daily_step_summaries`; shows `"Сохранено офлайн"` pill | Live points, streak, interactive `FoxMascotWidget` with mood/accessory, 2 expandable Today cards |
| **Tab 2: Map (`Мои маршруты`)** | Map tiles + top shimmer bar `"Загрузка маршрута за день..."` | If GPS off: `"Геолокация маршрутов выключена"` card; if 0 GPS points: `"Маршрут за день ещё не записан"` | Inline or top banner (`EDIT_WINDOW_EXPIRED`, `SEGMENT_OVERLAP_CONFLICT`, `SEGMENT_CONTAINS_VEHICLE_MOTION`) | Renders cached tiles (`flutter_map_cache`) + `local_gps_track_points` + `local_route_segment_allocations`; queues saves in outbox | Polylines colored by motion class, interactive segment handles, `TransportAllocationBottomSheet` |
| **Tab 2: Map (`Пункты РСО`)** | Non-blocking top progress pill `"Загрузка пунктов РСО..."` over map | Floating pill `"В этой области карты пункты РСО не найдены"` with button `"Сбросить фильтры"` | Top banner (`BBOX_AREA_TOO_LARGE_FOR_ZOOM`, `REPORT_USER_TOO_FAR_FROM_POINT`) | Queries `cached_waste_points` by lat/lon bounds; queues new reports in `pending_waste_point_reports` | Clustered monochrome pins, fraction chips, ODbL attribution bar, `WastePointDetailSheet` |
| **Tab 1: Stats & Drilldowns** | Wireframe bar chart shimmer + 3 Bento skeleton cards | Zero-height baseline bars with prompt `"Начните шагать, чтобы увидеть графики CO₂"` | Top banner with retry button `"Повторить загрузку"` | Renders `cached_weekly_stats_snapshot` and `cached_friends_leaderboard` with offline timestamp | 7-day stacked bar chart, drilldowns (`Дни/Недели/Месяцы`), colored Eco-Equivalents, Leaderboard, Shared Forest |
| **Tab 4: Shop, Cart & Orders** | 2-column wireframe card grid shimmer | `"По вашему запросу товары не найдены"` with button `"Показать все категории"` | Inline/banner on checkout (`INSUFFICIENT_POINTS_BALANCE`, `SHOP_DAILY_USER_LIMIT_EXCEEDED`, `SHOP_ITEM_OUT_OF_STOCK`) | Catalog browsing from cache; checkout button shows `"Для оформления заказа требуется подключение к серверу"` | Fictional disclaimer banner, partner coupons, virtual items, Cart stepper, QR modal & copyable promo codes |
| **Tab 5: Profile, Friends & Vehicle** | Profile header + settings list skeleton | Friends list empty: `"У вас пока нет друзей. Поделитесь кодом {friend_code} или отсканируйте QR!"` | Inline validation on vehicle consumption (`INVALID_VEHICLE_CONSUMPTION`) or friend code (`FRIEND_CODE_NOT_FOUND`, `WAKEUP_NUDGE_DAILY_COOLDOWN`) | Reads `local_user_profile`, `local_user_vehicle`, `cached_badges_and_inventory`; queues settings/vehicle edits in outbox | Editable profile, 4-icon badge strip, Friends QR/nudge, live Vehicle calculator, RSO shortcut, 152-FZ controls |
