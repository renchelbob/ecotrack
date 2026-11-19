# 06 — Offline Sync FSM, SQLite WAL Engine & Device Sensors Specification

> **Target Audience**: Developer 2 (Flutter Client & Offline Engine) & Mobile AI Coding Agents
> **Governing Contracts**: `contracts/client_sqlite_schema.sql`, `contracts/openapi.yaml`, `contracts/error_catalog.json`
> **Companion Specs**: `specs/02-domain-math-and-algorithms.md`, `specs/05-mobile-flutter-architecture.md`, `mobile/AGENTS.md`

---

## 1. SQLite 3 WAL Engine & DAO Contract

### 1.1 Database Initialization & PRAGMA Configuration
At application startup (`main.dart`), `SqliteDatabase.initialize()` opens `ecotrack_client_v1.db` in the application's private documents directory and executes the following initialization sequence before any BLoC or background task starts:

```dart
final class SqliteDatabase {
  static const String dbFileName = 'ecotrack_client_v1.db';
  static const int schemaVersion = 1;

  Future<Database> openAndInitialize() async {
    final dbPath = join(await getDatabasesPath(), dbFileName);
    return openDatabase(
      dbPath,
      version: schemaVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON;');
        await db.rawQuery('PRAGMA journal_mode = WAL;');
        await db.execute('PRAGMA synchronous = NORMAL;');
        await db.rawQuery('PRAGMA busy_timeout = 5000;');
      },
      onCreate: (db, version) async {
        final ddlScript = await rootBundle.loadString(
          'assets/db/client_sqlite_schema.sql',
        );
        final batch = db.batch();
        for (final statement in _splitSqlStatements(ddlScript)) {
          batch.execute(statement);
        }
        await batch.commit(noResult: true);
      },
      onOpen: (db) async {
        // Crash recovery: reset any mutation interrupted mid-flight by OS kill
        await db.update(
          'offline_mutation_outbox',
          <String, Object?>{'status': 'pending'},
          where: "status = 'in_flight'",
        );
      },
    );
  }
}
```

### 1.2 Security Boundary & Deterministic 152-FZ / Logout Wipe Procedure
1. **Strict Credential Separation**:
   - Secret credentials (`access_token`, `refresh_token`, `device_fingerprint`) MUST NEVER be written to SQLite or `shared_preferences`. They reside exclusively inside `FlutterSecureStorage`:
     - **Android**: `AndroidOptions(encryptedSharedPreferences: true, resetOnError: true)` backed by Android Keystore AES-256-GCM.
     - **iOS**: `IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device)`.
2. **Deterministic Full Wipe Procedure (`wipeAllUserData()`)**:
   - Invoked on **Logout** (`POST /api/v1/auth/logout`), **`force_logout` error action**, or **152-FZ Account Deletion** (`DELETE /api/v1/users/me`).
   - Stops `GpsForegroundService` and `OutboxDispatcher` timers, cancels sensor streams, deletes all keys from `FlutterSecureStorage` and `SharedPreferences`, and executes an atomic SQLite purge followed by WAL truncation so zero deleted personal data remains in unallocated SQLite pages:

```sql
BEGIN IMMEDIATE TRANSACTION;
DELETE FROM offline_mutation_outbox;
DELETE FROM pending_waste_point_reports;
DELETE FROM local_route_segment_allocations;
DELETE FROM local_gps_track_points;
DELETE FROM local_daily_step_summaries;
DELETE FROM local_user_vehicle;
DELETE FROM cached_friends_leaderboard;
DELETE FROM cached_weekly_stats_snapshot;
DELETE FROM cached_badges_and_inventory;
DELETE FROM local_user_profile;
COMMIT;
PRAGMA wal_checkpoint(TRUNCATE);
VACUUM;
```

### 1.3 DAO Responsibility Matrix (All 12 Tables in `contracts/client_sqlite_schema.sql`)

| SQLite Table Name | Owning DAO Class | Primary Key | Operational Responsibility |
| :--- | :--- | :--- | :--- |
| `local_user_profile` | `ProfileSqliteDao` | `user_id` | Caches current user profile, balance, streak, goals, mascot state, 406-FZ lab flags, and 152-FZ consent flag. |
| `local_user_vehicle` | `VehicleSqliteDao` | `id` (`UNIQUE user_id`) | Stores personal vehicle fuel type, consumption, and exact `computed_co2_g_per_meter` for offline route previews. |
| `local_transport_catalog` | `VehicleSqliteDao` | `mode_code` | Caches the 8 `transport_emission_catalog` presets (`bus`, `metro`, `tram`, `personal_car`, `car_*`). |
| `local_daily_step_summaries` | `ActivitySqliteDao` | `activity_date` | Stores daily sensor steps, `pedometer_boot_baseline`, hybrid CO₂ breakdown, and `sync_status`. |
| `local_gps_track_points` | `ActivitySqliteDao` | `local_id` (`UNIQUE activity_date, seq_no`) | High-frequency ring buffer for interval GPS coordinates, `cumulative_steps`, and local `motion_class`. |
| `local_route_segment_allocations` | `ActivitySqliteDao` | `id` | Stores user-selected route transport replacements for today and yesterday with `idempotency_key`. |
| `offline_mutation_outbox` | `OutboxSqliteDao` | `outbox_id` (`UNIQUE idempotency_key`) | Durable transactional queue of pending REST mutations with retry counters and backoff timestamps. |
| `cached_waste_points` | `WastePointSqliteDao` | `id` | Spatial BBox cache of RSO recycling points for offline map viewing and instant pan rendering. |
| `pending_waste_point_reports` | `WastePointSqliteDao` | `id` | Local staging table of user crowdsourced RSO reports awaiting server confirmation. |
| `cached_weekly_stats_snapshot` | `StatsSqliteDao` | `(iso_year, iso_week)` | Caches weekly emissions buckets, eco-equivalents JSON, and Shared Forest challenge progress. |
| `cached_friends_leaderboard` | `FriendsSqliteDao` | `friend_user_id` | Caches accepted/pending friends, weekly CO₂ ranking, and `last_nudge_date` cooldown state. |
| `cached_badges_and_inventory` | `ProfileSqliteDao` | `(item_kind, code)` | Caches badge progress thresholds and unlocked/equipped mascot vector accessories. |

---

## 2. Offline Mutation Outbox — Complete Finite State Machine

### 2.1 Mapping Logical FSM States to `offline_mutation_outbox` Columns
In `contracts/client_sqlite_schema.sql`, `offline_mutation_outbox.status` is constrained by `CHECK (status IN ('pending', 'in_flight', 'failed_permanent'))`. The 5 logical states of the Outbox Finite State Machine map deterministically to the SQLite columns as follows:

| Logical FSM State | SQLite `status` Column | SQLite Predicate / Condition | Corresponding Domain Entity `sync_status` |
| :--- | :--- | :--- | :--- |
| **`pending`** | `'pending'` | `retry_count = 0 AND next_retry_at_ms <= now_ms` | `'pending'` |
| **`in_flight`** | `'in_flight'` | Active HTTP request executing in `OutboxDispatcher` | `'pending'` |
| **`retry_wait`** | `'pending'` | `retry_count > 0 AND next_retry_at_ms > now_ms` | `'pending'` |
| **`acked`** | *(Row deleted from outbox)* | `DELETE FROM offline_mutation_outbox WHERE outbox_id = ?` | `'synced'` |
| **`dead_letter`** | `'failed_permanent'` | Non-retryable `4xx` or `retry_count >= max_retries` | `'failed'` |

### 2.2 Complete Outbox State Transition Table

| Current State | Triggering Event | Guard Condition | Next State | Atomic SQLite & UI Side Effects |
| :--- | :--- | :--- | :--- | :--- |
| *(None)* | User or Sensor triggers offline-capable mutation | `operation_type != 'create_shop_order'` | **`pending`** | Generate UUIDv7 `idempotency_key`; write optimistic state to local entity table (`sync_status = 'pending'`); `INSERT INTO offline_mutation_outbox (status='pending', retry_count=0, next_retry_at_ms=now_ms)` in same SQLite transaction; notify `SyncStatusCubit`. |
| **`pending`** | `OutboxDispatcher` tick or connectivity restored | `isOnline == true` AND causal predecessors for same `activity_date` are **`acked`** | **`in_flight`** | `UPDATE offline_mutation_outbox SET status = 'in_flight' WHERE outbox_id = ?`; dispatch HTTP request with `Idempotency-Key: <idempotency_key>`. |
| **`in_flight`** | HTTP `200`, `201`, or `204` received | Response JSON valid | **`acked`** | In one SQLite transaction: reconcile authoritative server response into local entity table (`sync_status = 'synced'`), update `local_user_profile` balance/CO₂, and `DELETE FROM offline_mutation_outbox WHERE outbox_id = ?`. |
| **`in_flight`** | Network timeout / socket error / HTTP `500` / `503` / `409 IDEMPOTENCY_IN_FLIGHT` | `retry_count + 1 < max_retries` (`12`) | **`retry_wait`** | Compute `backoff_ms = calcBackoffWithJitter(retry_count + 1)`; `UPDATE offline_mutation_outbox SET status = 'pending', retry_count = retry_count + 1, next_retry_at_ms = now_ms + backoff_ms, last_error = ?`. |
| **`in_flight`** | HTTP `429 RATE_LIMIT_EXCEEDED` | `retry_count + 1 < max_retries` AND `oper != 'send_friend_wakeup_nudge'` | **`retry_wait`** | Parse `Retry-After` seconds header (fallback `30 s`); `UPDATE offline_mutation_outbox SET status = 'pending', retry_count = retry_count + 1, next_retry_at_ms = now_ms + retry_after_ms`. |
| **`in_flight`** | HTTP `401 AUTH_TOKEN_EXPIRED` | `TokenRefreshInterceptor` succeeds | **`in_flight`** | Transparently re-sends HTTP request with new Bearer token and identical `Idempotency-Key`. |
| **`in_flight`** | HTTP `401 REFRESH_TOKEN_EXPIRED_OR_REVOKED` | Refresh rejected by server | *(Wiped)* | Halt `OutboxDispatcher`; execute `wipeAllUserData()`; dispatch `AuthForceLogoutRequested`. |
| **`in_flight`** | HTTP `403 FZ152_CONSENT_REVOKED` or `GOOGLE_FORMAL_PHONE_REQUIRED` | Consent or formal phone gate active | **`retry_wait`** | Reset `status = 'pending'`, pause `OutboxDispatcher` queue, and surface `Fz152ConsentResolutionModal` or `GoogleFormalPhoneModal` via `AuthBloc`. |
| **`in_flight`** | Non-retryable `400` / `404` / `409` / `422` (e.g., `EDIT_WINDOW_EXPIRED`, `SEGMENT_CONTAINS_VEHICLE_MOTION`, `WAKEUP_NUDGE_DAILY_COOLDOWN`) | `error.retryable == false` | **`dead_letter`** | `UPDATE offline_mutation_outbox SET status = 'failed_permanent', last_error = error.code`; set local entity `sync_status = 'failed'`; roll back invalid optimistic allocation; present `error.uiMessageRu` via `EcoErrorBannerPresenter`. |
| **`in_flight`** | Retryable failure when `retry_count + 1 >= max_retries` (`12`) | `retry_count + 1 >= 12` | **`dead_letter`** | `UPDATE offline_mutation_outbox SET status = 'failed_permanent', last_error = 'MAX_RETRIES_EXHAUSTED'`; set local entity `sync_status = 'failed'`. |
| **`retry_wait`** | Scheduler timer reaches `next_retry_at_ms` | `now_ms >= next_retry_at_ms` AND `isOnline == true` | **`in_flight`** | Promote to `'in_flight'` and execute HTTP request with original `Idempotency-Key`. |

### 2.3 Causal FIFO Ordering & Dependency Rules
`OutboxDispatcher` processes ready rows ordered by `outbox_id ASC`, subject to two strict causal rules:
1. **Per-Date Activity Barrier**:
   For any `activity_date` $D$:
   - An `upload_gps_track_batch` mutation for date $D$ requires at least one initial `sync_daily_steps` for date $D$ to have been enqueued before or alongside it.
   - An `upsert_segment_allocation` or `delete_segment_allocation` mutation for date $D$ **MUST NOT** transition to `in_flight` while any `sync_daily_steps` or `upload_gps_track_batch` row for date $D$ is still present in `offline_mutation_outbox` (`status IN ('pending', 'in_flight')`). This guarantees that `gps_track_points` (`start_seq_no` .. `end_seq_no`) already exist in PostGIS before `PUT /api/v1/activity/daily/{activity_date}/allocations` executes.
2. **Coalescing Redundant Step & Allocation Mutations**:
   - If a new `sync_daily_steps` for date $D$ is enqueued while an older `sync_daily_steps` for the same date $D$ is still in `status = 'pending'` (not yet `in_flight`), `OutboxSqliteDao` updates the existing `pending` row's `payload_json` (`raw_sensor_steps = max(old, new)`) and generates a fresh `idempotency_key` in place rather than stacking duplicate step sync requests.
   - Similarly, because `PUT /api/v1/activity/daily/{activity_date}/allocations` is a full replacement of the day's segment list, a new allocation save for date $D$ coalesces into any un-sent `pending` `upsert_segment_allocation` row for date $D$.
3. **Shop Checkout Online-Direct Policy**:
   - `POST /api/v1/shop/orders` is executed **online-direct** with a client-generated UUIDv7 `Idempotency-Key` (never silently queued for hours in background outbox) because users expect immediate QR/promo code generation and real-time validation against `SHOP_ITEM_OUT_OF_STOCK` and `INSUFFICIENT_POINTS_BALANCE`.

### 2.4 Exponential Backoff with Full Jitter Formula
For retry attempt $r \in \{1, 2, \dots, 12\}$:
$$\text{base\_delay\_ms}(r) = \min\left(300000, \; 1000 \times 2^{\min(r, 8)}\right)$$
$$\text{next\_retry\_at\_ms} = \text{now\_ms} + \text{base\_delay\_ms}(r) + \text{Random().nextInt}(1501)$$
This produces retry intervals starting at `~2.0–3.5 s` ($r=1$), `~4.0–5.5 s` ($r=2$), `~8.0–9.5 s` ($r=3$), scaling up to a capped `5 minutes` ($300,000\text{ ms}$) ceiling across 12 attempts (~35 minutes total resilience window before pausing until the next network change event).

---

## 3. Dual Step Acquisition Engine (`health ^12.x+` + `pedometer`)

EcoTrack combines two complementary hardware step APIs so that the Home screen and GPS interval tracker have **zero-latency step ticks** while daily totals remain **100% consistent with OS health stores**.

### 3.1 Authoritative Daily Total (`health ^12.x+` — Health Connect & HealthKit)
1. **Strict API Selection (Zero Google Fit)**:
   - On Android 14–16+, `health ^12.1.0` uses **Android Health Connect** (`android.permission.health.READ_STEPS`) natively. Deprecated Google Fit REST/Play Services APIs are strictly forbidden.
   - On iOS 17–19+, `health ^12.1.0` queries **Apple HealthKit** (`HKQuantityTypeIdentifierStepCount`).
2. **Local-Day Aggregation Window**:
   - For `today` (in the device's local timezone), compute `startOfDay = DateTime(now.year, now.month, now.day, 0, 0, 0)` and query:
     ```dart
     final int? healthSteps = await _health.getTotalStepsInInterval(
       startOfDay,
       DateTime.now(),
       includeManualEntry: false, // Enforces hardware-sensor-only rule!
     );
     ```
   - Setting `includeManualEntry: false` instructs Health Connect and HealthKit to exclude user-typed manual step entries at the OS level.
3. **Sync Cadence**:
   - Triggered automatically on:
     1. App startup & transition to `AppLifecycleState.resumed`.
     2. User pull-to-refresh on Tab 3 (`Home`) or Tab 1 (`Stats`).
     3. Every `15 minutes` while active or at the end of a GPS route recording session.
   - Also queries `yesterday` (`[yesterday 00:00:00, yesterday 23:59:59.999]`) once per launch if `yesterday`'s `local_daily_step_summaries` was not synced after midnight.

### 3.2 Real-Time Hardware Tick Counter (`pedometer`) & Reboot Reconciliation
1. **Hardware Sensor Stream**:
   - `Pedometer.stepCountStream` reads the hardware `Sensor.TYPE_STEP_COUNTER` (Android) / `CMPedometer` (iOS), which emits cumulative steps since the last device boot ($S_{\text{boot}}$) with sub-second latency.
2. **Daily Baseline & Reboot-Safe Reconciliation Algorithm**:
   - Let $S_{\text{boot}}(t)$ be the latest integer from `Pedometer.stepCountStream` at timestamp $t$.
   - In `local_daily_step_summaries` for `today`:
     - If `pedometer_boot_baseline` is `NULL` (first reading of the calendar day), set `pedometer_boot_baseline` $= S_{\text{boot}}(t) - S_{\text{HC}}(t)$, where $S_{\text{HC}}(t)$ is the current Health Connect / HealthKit step count for today.
     - **Reboot Detection**: If $S_{\text{boot}}(t) < S_{\text{prev\_boot}}$ (the user rebooted their phone during the day, resetting `TYPE_STEP_COUNTER` to `0`), immediately recompute `pedometer_boot_baseline` $= S_{\text{boot}}(t) - \text{raw\_sensor\_steps}_{\text{saved}}$ so zero steps accumulated before the reboot are lost.
   - At any instant $t$, the live reconciled daily step count is:
     $$S_{\text{live}}(t) = \max\left(S_{\text{HC}}(t), \; S_{\text{boot}}(t) - \text{pedometer\_boot\_baseline}\right)$$
3. **Fallback When Health Connect Permission is Denied**:
   - If the user grants `ACTIVITY_RECOGNITION` / `NSMotionUsageDescription` (hardware pedometer) but declines Health Connect / HealthKit, $S_{\text{HC}}(t) = 0$ and $S_{\text{live}}(t) = S_{\text{boot}}(t) - \text{pedometer\_boot\_baseline}$ continues to function with 100% accuracy.

---

## 4. Configurable Interval GPS Tracking Engine (`geolocator ^14.x` + `flutter_foreground_task`)

### 4.1 User-Configurable Tracking Profiles
The user can toggle `is_gps_tracking_enabled` and select `gps_interval_seconds` in Tab 2 (`Map & Activity`) or Tab 5 (`Profile & Settings`):

| Profile Mode | `gps_interval_seconds` | `distanceFilter` (`m`) | Target `LocationAccuracy` | Typical Battery Impact |
| :--- | :--- | :--- | :--- | :--- |
| **`off`** (`is_gps_tracking_enabled = false`) | N/A | N/A | N/A | `0%` (uses `80% * 0.7` step fallback) |
| **`high_precision`** (`5 сек`) | `5` | `5 m` | `LocationAccuracy.best` | `~4.5% / hour` active walk |
| **`balanced`** (`15 сек`, Default) | `15` | `10 m` | `LocationAccuracy.high` | `~2.0% / hour` active walk |
| **`eco_battery`** (`30 сек` / `60 сек`) | `30` or `60` | `20 m` | `LocationAccuracy.medium` | `< 1.0% / hour` active walk |

### 4.2 Android 14–16 (`AndroidManifest.xml`) & iOS (`Info.plist`) Declarations

#### Android (`mobile/android/app/src/main/AndroidManifest.xml`)
```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- Step Sensor & Health Connect -->
    <uses-permission android:name="android.permission.ACTIVITY_RECOGNITION" />
    <uses-permission android:name="android.permission.health.READ_STEPS" />

    <!-- Geolocation & Android 14-16 Foreground Service -->
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />

    <application>
        <service
            android:name="com.pravera.flutter_foreground_task.service.ForegroundService"
            android:foregroundServiceType="location"
            android:exported="false" />
    </application>
</manifest>
```
- **Localized Russian Foreground Service Notification**:
  - Channel Name: `"Запись эко-маршрута EcoTrack"`
  - Notification Title: `"EcoTrack записывает пеший маршрут"`
  - Notification Body: `"Шагов сегодня: {validated_steps} · Экономия: {total_co2_saved_grams} г CO₂"`
  - Action Button: `"Остановить GPS"` (cleanly stops foreground service and flushes pending track points).

#### iOS (`mobile/ios/Runner/Info.plist`)
- `NSLocationWhenInUseUsageDescription`: `"EcoTrack использует геопозицию для отображения вашего пешего маршрута и пунктов приёма вторсырья (РСО) поблизости."`
- `NSLocationAlwaysAndWhenInUseUsageDescription`: `"EcoTrack записывает пеший маршрут в фоновом режиме (только когда запись включена вами), чтобы точно рассчитать сэкономленный CO₂ вместо транспорта."`
- `NSMotionUsageDescription`: `"EcoTrack считывает количество шагов с датчика движения для начисления эко-баллов и расчёта дистанции."`
- `NSHealthShareUsageDescription`: `"EcoTrack синхронизирует дневное количество шагов из приложения «Здоровье» для точного расчёта вашего эковклада."`
- `UIBackgroundModes`: `<array><string>location</string><string>fetch</string><string>remote-notification</string></array>`

### 4.3 Atomic GPS + Step Capture Tick & Batch Flush Algorithm
Whenever `GpsForegroundService` is active and a new `Position` fix arrives from `Geolocator.getPositionStream`:
1. **Acquire Paired Sensor Snapshot**:
   - Record `recordedAtMs = position.timestamp.millisecondsSinceEpoch`.
   - Read current hardware `cumulativeSteps = stepSensorBridge.latestCumulativeSteps`.
2. **Compute Local Kinematics & Preview Motion Classification**:
   - Load previous point $P_{i-1}$ for `activityDate` from `local_gps_track_points` (`ORDER BY seq_no DESC LIMIT 1`).
   - If no previous point exists: `seqNo = 0`, `deltaSteps = 0`, `deltaDistanceM = 0.0`, `motionClass = 'stationary'`.
   - If $P_{i-1}$ exists:
     - `seqNo = prev.seqNo + 1`
     - `deltaTSec = max(1.0, (recordedAtMs - prev.recordedAtMs) / 1000.0)`
     - `deltaDistanceM = const Distance().as(LengthUnit.Meter, LatLng(prev.lat, prev.lon), LatLng(position.latitude, position.longitude))`
     - `deltaSteps = cumulativeSteps >= prev.cumulativeSteps ? (cumulativeSteps - prev.cumulativeSteps) : cumulativeSteps`
     - Classify `motionClass` using the exact 8-rule decision table from `specs/02-domain-math-and-algorithms.md` Section 3.2.
3. **Persist to SQLite**:
   - Insert row into `local_gps_track_points` with `sync_status = 'pending'`.
4. **Batch Flush Trigger (`POST /api/v1/activity/tracks/points:batch`)**:
   - Query count of rows in `local_gps_track_points` where `activity_date = today AND sync_status = 'pending'`.
   - Flush is triggered when **any** of the following conditions holds:
     - `pendingCount >= 20` points, OR
     - `nowMs - lastBatchFlushMs >= 180000` (`3 minutes`) and `pendingCount >= 1`, OR
     - User toggles GPS off, switches to `[ Мои маршруты ]` screen to annotate a segment, or app enters background.
   - The flush packages up to `500` pending points ordered by `seq_no ASC` into a `GpsTrackPointsBatchRequest` JSON payload and enqueues an `upload_gps_track_batch` row in `offline_mutation_outbox`.

---

## 5. Local Read-Through Cache & Eviction Policies

| SQLite Table | Cache TTL (`staleAfter`) | Hard Row / Size Cap | Pruning & Stale-While-Revalidate Policy |
| :--- | :--- | :--- | :--- |
| `cached_waste_points` | `24 hours` per BBox region | `10,000 rows` | On BBox query: immediately emit cached points inside `[min_lat..max_lat, min_lon..max_lon]` from SQLite, then fetch `/api/v1/map/waste-points` in background and upsert. If row count `> 10,000`, delete oldest rows by `cached_at_ms ASC`. |
| `pending_waste_point_reports` | Until `sync_status = 'synced'` | `200 rows` | Optimistically displayed on `WastePointDetailSheet`; pruned `24 hours` after `sync_status` transitions to `'synced'`. |
| `local_gps_track_points` | `7 days` (`synced` rows) | `50,000 rows` | `pending` rows are NEVER evicted. `synced` rows older than `today - 7 days` are deleted at daily startup maintenance. |
| `local_daily_step_summaries` | `90 days` (`synced` rows) | `365 rows` | Retains 90 days of local summaries for instant offline History & 7-day/30-day chart rendering. |
| `cached_weekly_stats_snapshot` | `15 minutes` | `12 ISO weeks` | Emits cached snapshot immediately when opening Tab 1 (`Stats`); refreshes silently from `/api/v1/stats/emissions` and `/api/v1/challenges/shared-forest/current`. |
| `cached_friends_leaderboard` | `10 minutes` | `500 rows` | Emits cached leaderboard immediately; updates `last_nudge_date` optimistically when `sendWakeupMascotNudge` succeeds. |
| `cached_badges_and_inventory` | `30 minutes` | `200 rows` | Loaded immediately on Tab 3 (`Home`) and Tab 5 (`Profile`); invalidated whenever a badge unlocks or accessory is purchased/equipped. |
| `local_transport_catalog` | `7 days` | `8 rows` | Seeded at SQLite creation with the 8 canonical presets from `contracts/schema.sql`; refreshed from `GET /api/v1/transport/presets`. |

---

## 6. End-to-End Offline Laptop-MVP Failure Recovery Scenarios

### Scenario A: Laptop Docker Backend Sleeps Mid-Walk & User Annotates Route Offline
1. Developer closes laptop lid (`localhost:8000` unreachable). User walks `3,200` steps (`2,368 m`) outdoors with GPS interval tracking (`15 s`) enabled.
2. `GpsForegroundService` records `120` points into `local_gps_track_points` (`seq_no 0..119`). Every 20 points, `OutboxDispatcher` enqueues `sync_daily_steps` and `upload_gps_track_batch` into `offline_mutation_outbox`. Network attempts fail with `connectionError`, transitioning the outbox rows to `retry_wait` with exponential backoff.
3. User opens Tab 2 (`[ Мои маршруты ]`), selects segment `seq_no 10..95` (`1,450 m`), chooses `[ Мой авто ]`, and taps `"Сохранить участок"`.
4. `ActivitySqliteDao` writes the allocation to `local_route_segment_allocations` (`sync_status = 'pending'`), recalculates local hybrid CO₂ preview, updates `HomeCubit` Today cards immediately, and enqueues `upsert_segment_allocation` in `offline_mutation_outbox` with UUIDv7 `idempotency_key`.
5. Laptop lid opens (`postgis` + `fastapi` containers resume). `OutboxDispatcher` detects connectivity and drains `offline_mutation_outbox` in strict causal order:
   - First: `PUT /api/v1/activity/steps/daily` (`200 OK`)
   - Second: `POST /api/v1/activity/tracks/points:batch` (`200 OK`, populates `gps_track_points` `0..119` in PostGIS)
   - Third: `PUT /api/v1/activity/daily/{date}/allocations` (`200 OK`, validates `seq_no 10..95` against PostGIS and records exact CO₂ delta).
6. Result: Zero data loss, zero `SEGMENT_SEQ_OUT_OF_BOUNDS` race condition, and local state transitions to `sync_status = 'synced'`.

### Scenario B: TCP Drop After Server Commits `syncDailyStepsSummary` (Zero Double-Crediting)
1. User walks `5,000` steps (`+50 ★`). `OutboxDispatcher` sends `PUT /api/v1/activity/steps/daily` with `Idempotency-Key: 0195a1b2-c3d4-7000-8000-000000000099`.
2. FastAPI backend commits `daily_step_summaries` (`points_awarded_for_day = 50`) and inserts `+50 ★` into `point_ledger` with `idempotency_key = 0195a1b2-c3d4-7000-8000-000000000099`.
3. Before the HTTP `200 OK` response reaches the phone, Wi-Fi drops.
4. `OutboxDispatcher` catches `receiveTimeout`, keeps the **exact same** `idempotency_key` (`0195a1b2-c3d4-7000-8000-000000000099`) in `offline_mutation_outbox`, and retries 3 seconds later.
5. FastAPI detects the existing `idempotency_key` (and sees `points_awarded_for_day == 50` already equals `5000 // 100`), computes `points_delta = 0`, skips `point_ledger` insertion, and returns `200 OK` with `points_balance = 50`.
6. Result: User receives exactly `+50 ★` — double-crediting is mathematically impossible.

### Scenario C: Smartphone Reboots Mid-Walk While Offline
1. At 14:00, user has walked `4,000` steps today (`S_boot = 24,000`, `pedometer_boot_baseline = 20,000`).
2. At 14:05, phone battery dies or reboots while offline. Hardware `TYPE_STEP_COUNTER` resets to `0`.
3. At 14:15, phone boots up and user walks `600` more steps (`S_boot = 600`).
4. `StepSensorBridge` detects $S_{\text{boot}} (600) < S_{\text{prev\_boot}} (24,000)$, recalculates `pedometer_boot_baseline = 0 - 4000 = -4000`, and computes $S_{\text{live}} = 600 - (-4000) = 4,600$ steps.
5. Simultaneously, `GpsForegroundService` uses `compute_reboot_safe_step_delta(prev=24000, curr=600) -> 600` from `specs/02-domain-math-and-algorithms.md` Section 3.1.
6. Result: Both daily step totals (`4,600`) and GPS segment step deltas (`+600`) remain 100% accurate across device reboots.
