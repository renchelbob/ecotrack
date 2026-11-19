# 03 — Backend Architecture, Transactional SQL & 152-FZ Compliance

> **Target Audience**: Developer 1 (Backend, Data & DevOps) & Backend AI Coding Agents
> **Governing Contracts**: `contracts/schema.sql`, `contracts/openapi.yaml`, `contracts/error_catalog.json`, `backend/AGENTS.md`
> **Runtime Stack**: Python `3.14` (standard GIL), `FastAPI >= 0.150.0`, `Pydantic v2.14.x`, `asyncpg >= 0.31.0`, `orjson`, `httpx`, `PyJWT`

---

## 1. Service Topology, FastAPI Lifespan & Unified Error Envelope

### 1.1 Python 3.14 & `asyncpg` Connection Pool Lifespan
The backend runs as an asynchronous ASGI service managed by `uvicorn` (`uvloop` + `httptools`). Python 3.14's native PEP 649 / PEP 749 deferred annotation evaluation is used everywhere (`from __future__ import annotations` is strictly prohibited).

```python
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
import asyncpg
import orjson
from fastapi import FastAPI

from app.config import Settings, get_settings
from app.infrastructure.push.fcm_provider import FcmPushProvider


async def _init_pg_connection(conn: asyncpg.Connection) -> None:
    await conn.set_type_codec(
        "jsonb",
        encoder=lambda v: orjson.dumps(v).decode("utf-8"),
        decoder=orjson.loads,
        schema="pg_catalog",
        format="text",
    )
    await conn.set_type_codec(
        "json",
        encoder=lambda v: orjson.dumps(v).decode("utf-8"),
        decoder=orjson.loads,
        schema="pg_catalog",
        format="text",
    )
    await conn.execute("SET TIME ZONE 'UTC'")


@asynccontextmanager
async def app_lifespan(app: FastAPI) -> AsyncIterator[None]:
    settings: Settings = get_settings()
    app.state.db_pool = await asyncpg.create_pool(
        dsn=settings.database_url,
        min_size=5,
        max_size=25,
        max_queries=50_000,
        max_inactive_connection_lifetime=300.0,
        command_timeout=15.0,
        init=_init_pg_connection,
    )
    app.state.push_provider = FcmPushProvider(settings=settings)
    try:
        yield
    finally:
        await app.state.push_provider.close()
        await app.state.db_pool.close()
```

### 1.2 Unified Error Catalog Exception Middleware (`app/api/errors.py`)
At startup, the backend loads `contracts/error_catalog.json` into an immutable `dict[str, CatalogErrorEntry]`. All domain exceptions, FastAPI `RequestValidationError`s, and `asyncpg.PostgresError`s map deterministically to the `ErrorResponse` schema:

| Raised Exception / PostgreSQL SQLSTATE | Mapped `error_code` (`contracts/error_catalog.json`) | HTTP Status |
| :--- | :--- | :--- |
| `CatalogException(code, details)` | Exact `code` passed by caller | `entry.http_status` |
| `RequestValidationError` (Pydantic v2.14) | `VALIDATION_ERROR` | `422` |
| `asyncpg.CheckViolationError` (`users_points_balance_check`) | `INSUFFICIENT_POINTS_BALANCE` | `409` |
| `asyncpg.UniqueViolationError` (`friend_wakeup_nudges_sender_id_receiver_id_nudge_date_key`) | `WAKEUP_NUDGE_DAILY_COOLDOWN` | `429` |
| `asyncpg.UniqueViolationError` (`idx_friendships_unordered_pair`) | `FRIENDSHIP_ALREADY_EXISTS` | `409` |
| `asyncpg.IntegrityConstraintViolationError` (`trg_point_ledger_immutable`) | `POINT_LEDGER_IMMUTABLE_VIOLATION` | `409` |
| `asyncpg.PostgresConnectionError` / `InterfaceError` | `DATABASE_UNAVAILABLE` | `503` |
| Any unhandled `Exception` | `INTERNAL_SERVER_ERROR` | `500` |

---

## 2. Backend-Driven OAuth 2.1 + PKCE & Session Security

### 2.1 OAuth 2.1 + PKCE Provider Exchange Matrix
The mobile client performs the interactive browser step via `flutter_appauth` using S256 PKCE and sends `(provider, authorization_code, code_verifier, redirect_uri, device_fingerprint, policy_version, consent_scope)` to `POST /api/v1/auth/oauth/exchange`.

| Provider (`oauth_provider_type`) | Token Endpoint (`POST`) | UserInfo Endpoint (`GET`) | Subject ID Field | 406-FZ Lab Mode Flag |
| :--- | :--- | :--- | :--- | :--- |
| `'yandex'` | `https://oauth.yandex.ru/token` | `https://login.yandex.ru/info?format=json` | `id` | `FALSE` |
| `'vk'` | `https://id.vk.com/oauth2/auth` | `https://id.vk.com/oauth2/user_info` | `user.user_id` | `FALSE` |
| `'google'` | `https://oauth2.googleapis.com/token` | `https://openidconnect.googleapis.com/v1/userinfo` | `sub` | `TRUE` |

### 2.2 Transactional OAuth Login, Starter Inventory & 152-FZ Journal Blueprint
```sql
-- 1. Check if identity exists
SELECT u.id, u.formal_phone_e164, u.requires_formal_phone
FROM user_oauth_identities oi
JOIN users u ON u.id = oi.user_id
WHERE oi.provider = $1::oauth_provider_type
  AND oi.provider_subject_id = $2
FOR UPDATE OF u;

-- 2. If new user: insert into users (with generated ECO-XXXX-XXXX friend_code)
INSERT INTO users (
    email,
    display_name,
    avatar_url,
    friend_code,
    requires_formal_phone,
    is_152fz_consent_active,
    equipped_accessory_code
) VALUES (
    $1, $2, $3, $4,
    ($5::oauth_provider_type = 'google'),
    TRUE,
    'leaf_sprout_hat'
)
RETURNING id;

-- 3. Grant starter mascot accessory in user_mascot_inventory
INSERT INTO user_mascot_inventory (user_id, accessory_code)
VALUES ($1, 'leaf_sprout_hat')
ON CONFLICT (user_id, accessory_code) DO NOTHING;

-- 4. Upsert user_oauth_identities
INSERT INTO user_oauth_identities (
    user_id, provider, provider_subject_id, provider_email, is_foreign_provider_lab_mode, last_login_at
) VALUES (
    $1, $2::oauth_provider_type, $3, $4, ($2::oauth_provider_type = 'google'), NOW()
)
ON CONFLICT (provider, provider_subject_id)
DO UPDATE SET
    provider_email = EXCLUDED.provider_email,
    last_login_at = NOW();

-- 5. Append 152-FZ consent grant record
INSERT INTO fz152_consent_journal (
    user_id, policy_version, action, consent_scope, ip_address, user_agent
) VALUES (
    $1, $2, 'granted'::consent_action_type, $3::jsonb, $4::inet, $5
);
```

When `provider == 'google'`, `AuthSessionResponse` returns:
- `is_foreign_provider_lab_mode = True`
- `lab_mode_warning_banner = "Внимание: регистрация и вход через иностранный провайдер (Google OAuth) не соответствуют требованиям 406-ФЗ РФ. Данный способ входа включён исключительно для академического / лабораторного тестирования."`

### 2.3 Google Formal Phone Submission & Enforcement (`POST /api/v1/auth/google-phone`)
- While `users.requires_formal_phone == TRUE`, any call to protected endpoints (except `/api/v1/auth/google-phone`, `/api/v1/users/me`, `/api/v1/users/me/consents`, `/api/v1/auth/logout`, and `DELETE /api/v1/users/me`) is rejected by the FastAPI security dependency with `403 GOOGLE_FORMAL_PHONE_REQUIRED` (`client_action: "open_phone_modal"`).
- Submitting `formal_phone_e164` (`^\+[1-9][0-9]{7,14}$`) executes:
```sql
UPDATE users
SET
    formal_phone_e164 = $1,
    requires_formal_phone = FALSE,
    updated_at = NOW()
WHERE id = $2
RETURNING *;
```

### 2.4 JWT Access Tokens & Rotating Refresh Tokens with Reuse Detection
- **Access Token**: `HS256` JWT, TTL `900 seconds` (`15 minutes`), claims:
  `{"sub": str(user_id), "jti": str(uuid_v7()), "iat": now_ts, "exp": now_ts + 900, "fp": device_fingerprint}`.
- **Refresh Token**: `32` cryptographically random bytes encoded as URL-safe Base64 (`43` chars), TTL `30 days`. Only `sha256(refresh_token).hexdigest()` (`CHAR(64)`) is stored in `auth_refresh_sessions.token_hash`.
- **Rotation & Reuse Detection (`POST /api/v1/auth/refresh`)**:
  1. Look up session by `token_hash = $1 FOR UPDATE`.
  2. If not found or `expires_at <= NOW()`: raise `401 REFRESH_TOKEN_EXPIRED_OR_REVOKED`.
  3. **Reuse Breach Detection**: If `revoked_at IS NOT NULL`, a stolen or replayed refresh token was presented. Immediately revoke all active sessions for that user and raise `401 REFRESH_TOKEN_EXPIRED_OR_REVOKED`:
     ```sql
     UPDATE auth_refresh_sessions
     SET revoked_at = NOW()
     WHERE user_id = $1 AND revoked_at IS NULL;
     ```
  4. **Fingerprint Binding**: If `session.device_fingerprint != request.device_fingerprint`, revoke the session and raise `401 DEVICE_FINGERPRINT_MISMATCH`.
  5. Otherwise set `revoked_at = NOW()` on the old row and insert a new `auth_refresh_sessions` row in the same transaction.

---

## 3. 152-FZ Personal Data Compliance Engine

### 3.1 Consent Recording & Revocation State Machine (`POST /api/v1/users/me/consents`)
```sql
-- Executed inside a single transaction
INSERT INTO fz152_consent_journal (
    user_id, policy_version, action, consent_scope, ip_address, user_agent
) VALUES (
    $1, $2, $3::consent_action_type, $4::jsonb, $5::inet, $6
)
RETURNING id, policy_version, action, consent_scope, recorded_at;

UPDATE users
SET
    is_152fz_consent_active = (
        $2::consent_action_type <> 'revoked'
        AND COALESCE(($3::jsonb ->> 'personal_data_152fz')::boolean, FALSE) = TRUE
    ),
    is_gps_tracking_enabled = CASE
        WHEN $2::consent_action_type = 'revoked'
          OR COALESCE(($3::jsonb ->> 'background_geolocation')::boolean, FALSE) = FALSE
        THEN FALSE
        ELSE is_gps_tracking_enabled
    END,
    updated_at = NOW()
WHERE id = $1;
```

**Enforcement Rules in `require_active_152fz_consent` Dependency**:
1. If `users.is_152fz_consent_active == FALSE`, reject all activity, map, shop, social, and profile-mutation endpoints with `403 FZ152_CONSENT_REVOKED` (`client_action: "open_consent_screen"`).
2. Read-only access to `GET /api/v1/users/me`, `GET /api/v1/users/me/consents`, `POST /api/v1/users/me/consents`, `DELETE /api/v1/users/me`, and `POST /api/v1/auth/logout` remains permitted so the user can inspect their status, re-grant consent, or erase their account.
3. Granular sensor scopes in the latest `fz152_consent_journal.consent_scope` entry are checked on sensor ingestion:
   - `PUT /api/v1/activity/steps/daily` requires `consent_scope.health_steps_sensor == true` (`403 FZ152_HEALTH_SENSOR_CONSENT_MISSING`).
   - `POST /api/v1/activity/tracks/points:batch` requires `consent_scope.background_geolocation == true` (`403 FZ152_GEOLOCATION_CONSENT_MISSING`).

### 3.2 Complete Account Erasure under 152-FZ Article 21 (`DELETE /api/v1/users/me`)
1. Verify `request.confirmation_phrase == "DELETE_MY_DATA_152FZ"`; if not, raise `400 FZ152_INVALID_CONFIRMATION_PHRASE`.
2. Compute deterministic non-reversible cryptographic audit hashes using `settings.erasure_hmac_secret`:
   - `anonymized_user_hash = hmac.new(secret, str(user_id).encode(), sha256).hexdigest()`
   - `verification_signature = hmac.new(secret, f"{anonymized_user_hash}:{purged_at_iso}:{request.deletion_reason}".encode(), sha256).hexdigest()`
3. Execute atomic erasure transaction:
```sql
-- Inside async with conn.transaction():
-- Step 1: Set session variable allowing trg_point_ledger_immutable to permit cascade delete
SET LOCAL ecotrack.in_152fz_account_erasure = 'true';

-- Step 2: Delete user row. PostgreSQL ON DELETE CASCADE automatically purges:
-- user_oauth_identities, auth_refresh_sessions, fz152_consent_journal, user_push_tokens,
-- user_vehicles, daily_step_summaries, gps_daily_tracks, gps_track_points,
-- route_segment_allocations, point_ledger (permitted by trg_point_ledger_immutable during erasure),
-- shop_orders, shop_order_items, user_mascot_inventory, user_badges,
-- friendships, friend_wakeup_nudges, shared_forest_contributions.
-- point_reports.user_id is set to NULL via ON DELETE SET NULL.
DELETE FROM users
WHERE id = $1;

-- Step 3: Record anonymized 152-FZ erasure proof
INSERT INTO fz152_account_deletion_log (
    anonymized_user_hash, deletion_reason, requested_at, purged_at, verification_signature
) VALUES (
    $1, $2, $3, $4, $5
)
RETURNING id AS receipt_id, anonymized_user_hash, purged_at, verification_signature;
```

---

## 4. Transactional `point_ledger`, Activity Sync & Shop Checkout Blueprints

### 4.1 Daily Step Sync & Ledger Delta Transaction (`PUT /api/v1/activity/steps/daily`)
```sql
-- Inside async with conn.transaction():
-- 1. Lock user row to serialize concurrent step/ledger updates
SELECT id, stride_length_cm, points_balance, current_streak_days, longest_streak_days,
       streak_freeze_count, last_active_local_date, daily_co2_goal_grams
FROM users
WHERE id = $1
FOR UPDATE;

-- 2. Lock existing daily summary if present
SELECT id, validated_steps, allocated_gps_distance_m, allocated_co2_saved_grams,
       auto_default_co2_saved_grams, total_co2_saved_grams, points_awarded_for_day,
       is_auto_calculated, last_synced_at
FROM daily_step_summaries
WHERE user_id = $1 AND activity_date = $2
FOR UPDATE;

-- 3. Upsert daily_step_summaries with recalculated hybrid CO2 and points_awarded_for_day
INSERT INTO daily_step_summaries (
    user_id, activity_date, timezone_offset_minutes, raw_sensor_steps,
    validated_steps, stride_length_cm, allocated_gps_distance_m,
    allocated_co2_saved_grams, auto_default_co2_saved_grams,
    points_awarded_for_day, is_auto_calculated, last_synced_at
) VALUES (
    $1, $2, $3, $4,
    $5, $6, $7,
    $8, $9,
    $10, $11, NOW()
)
ON CONFLICT (user_id, activity_date)
DO UPDATE SET
    timezone_offset_minutes = EXCLUDED.timezone_offset_minutes,
    raw_sensor_steps = EXCLUDED.raw_sensor_steps,
    validated_steps = EXCLUDED.validated_steps,
    stride_length_cm = EXCLUDED.stride_length_cm,
    auto_default_co2_saved_grams = EXCLUDED.auto_default_co2_saved_grams,
    points_awarded_for_day = EXCLUDED.points_awarded_for_day,
    last_synced_at = NOW()
RETURNING id, total_step_distance_m, unallocated_step_distance_m, total_co2_saved_grams;

-- 4. If points_delta > 0: insert into point_ledger (fires trg_point_ledger_sync_balance)
INSERT INTO point_ledger (
    user_id, idempotency_key, operation_type, points_delta, co2_delta_grams,
    reference_entity_type, reference_entity_id, description
) VALUES (
    $1, $2, 'daily_steps_reward'::ledger_operation_type, $3, $4,
    'daily_step_summaries', $5, $6
)
ON CONFLICT (idempotency_key) DO NOTHING;

-- 5. If points_delta == 0 and co2_delta_grams != 0: update lifetime CO2 directly
UPDATE users
SET
    lifetime_co2_saved_grams = GREATEST(0, lifetime_co2_saved_grams + $2),
    current_streak_days = $3,
    longest_streak_days = $4,
    streak_freeze_count = $5,
    last_active_local_date = $6,
    updated_at = NOW()
WHERE id = $1;
```

### 4.2 Batch Interval GPS + Steps Point Ingestion (`POST /api/v1/activity/tracks/points:batch`)
1. Ensure a `daily_step_summaries` row and a `gps_daily_tracks` row exist for `(user_id, activity_date)`.
2. Fetch the last recorded point (`ORDER BY seq_no DESC LIMIT 1`) to initialize `(prev_lat, prev_lon, prev_recorded_at, prev_cumulative_steps)`.
3. Classify each incoming point using `app.domain.motion_classifier` and bulk-insert via parameterized `unnest`:
```sql
INSERT INTO gps_track_points (
    track_id, user_id, seq_no, recorded_at, lat, lon,
    accuracy_m, speed_mps, cumulative_steps, delta_steps,
    delta_distance_m, motion_class
)
SELECT
    $1::uuid,
    $2::uuid,
    u.seq_no,
    u.recorded_at,
    u.lat,
    u.lon,
    u.accuracy_m,
    u.speed_mps,
    u.cumulative_steps,
    u.delta_steps,
    u.delta_distance_m,
    u.motion_class::track_point_motion_class
FROM unnest(
    $3::int[],
    $4::timestamptz[],
    $5::float8[],
    $6::float8[],
    $7::real[],
    $8::real[],
    $9::int[],
    $10::int[],
    $11::numeric[],
    $12::text[]
) AS u(
    seq_no, recorded_at, lat, lon, accuracy_m, speed_mps,
    cumulative_steps, delta_steps, delta_distance_m, motion_class
)
ON CONFLICT (track_id, seq_no) DO NOTHING;

-- Recompute daily LineString geometry and total walking distance inside PostGIS
UPDATE gps_daily_tracks t
SET
    route_geom = CASE
        WHEN sub.pt_count >= 2 THEN sub.line_geom
        ELSE NULL
    END,
    total_gps_walking_distance_m = sub.walking_dist_m,
    point_count = sub.pt_count,
    updated_at = NOW()
FROM (
    SELECT
        COUNT(*)::int AS pt_count,
        COALESCE(SUM(delta_distance_m) FILTER (WHERE motion_class = 'walking'), 0.00) AS walking_dist_m,
        ST_MakeLine(geom ORDER BY seq_no ASC) FILTER (WHERE motion_class <> 'unknown') AS line_geom
    FROM gps_track_points
    WHERE track_id = $1
) sub
WHERE t.id = $1
RETURNING t.id, t.total_gps_walking_distance_m, t.point_count;
```

### 4.3 Route Segment Allocations Update (`PUT /api/v1/activity/daily/{activity_date}/allocations`)
1. Validate `(user_local_today - activity_date).days in (0, 1)` (`400 EDIT_WINDOW_EXPIRED`).
2. Validate non-overlapping `[start_seq_no, end_seq_no]` intervals (`409 SEGMENT_OVERLAP_CONFLICT`).
3. For each allocation item, query `gps_track_points` for `seq_no BETWEEN $2 AND $3` to verify:
   - Both boundary `seq_no` exist (`422 SEGMENT_SEQ_OUT_OF_BOUNDS`).
   - Zero points in `(start_seq_no, end_seq_no]` have `motion_class = 'vehicle_suspected'` (`422 SEGMENT_CONTAINS_VEHICLE_MOTION`).
   - Compute `segment_geom = ST_MakeLine(geom ORDER BY seq_no ASC)`, `segment_distance_m = SUM(delta_distance_m) WHERE seq_no > start_seq_no`, `segment_steps = SUM(delta_steps) WHERE seq_no > start_seq_no`.
4. Replace existing allocations for `(daily_summary_id)` and recalculate `daily_step_summaries` hybrid CO₂ (`allocated_gps_distance_m`, `allocated_co2_saved_grams`, `auto_default_co2_saved_grams`, `is_auto_calculated`).
5. Apply $\Delta C_{\text{total}} = C_{\text{total}}^{\text{new}} - C_{\text{total}}^{\text{old}}$ to `users.lifetime_co2_saved_grams` and active `shared_forest_contributions`.

### 4.4 Atomic Shop Cart Checkout (`POST /api/v1/shop/orders`)
Executes inside a single `asyncpg` serializable/row-locked transaction so concurrent checkouts can never double-spend `users.points_balance` or oversell `shop_items.stock_quantity`:

```sql
-- Inside async with conn.transaction():
-- 1. Check idempotency: if shop_orders already has idempotency_key = $1, return existing order detail
SELECT id FROM shop_orders WHERE idempotency_key = $1 AND user_id = $2;

-- 2. Lock user row to serialize balance deductions and virtual item grants
SELECT id, points_balance, streak_freeze_count
FROM users
WHERE id = $1
FOR UPDATE;

-- 3. Lock requested shop_items in deterministic UUID order (ORDER BY id ASC) to prevent deadlocks
SELECT
    id,
    sku,
    item_type,
    title,
    price_points,
    stock_quantity,
    max_per_user_per_day,
    accessory_code,
    is_active
FROM shop_items
WHERE id = ANY($1::uuid[])
ORDER BY id ASC
FOR UPDATE;

-- 4. Check daily per-user purchase limits across today's completed/redeemed orders
SELECT
    oi.shop_item_id,
    COALESCE(SUM(oi.quantity), 0)::int AS bought_today
FROM shop_order_items oi
JOIN shop_orders o ON o.id = oi.order_id
WHERE o.user_id = $1
  AND o.status IN ('completed', 'redeemed')
  AND o.created_at >= CURRENT_DATE
  AND oi.shop_item_id = ANY($2::uuid[])
GROUP BY oi.shop_item_id;

-- 5. Check if user already owns any requested mascot_accessory (raises 409 SHOP_ACCESSORY_ALREADY_OWNED)
SELECT accessory_code
FROM user_mascot_inventory
WHERE user_id = $1
  AND accessory_code = ANY($2::varchar[]);

-- 6. Decrement stock_quantity for finite-stock items (after verifying stock_quantity >= requested_qty)
UPDATE shop_items
SET stock_quantity = stock_quantity - $2
WHERE id = $1 AND stock_quantity IS NOT NULL;

-- 7. Insert negative points delta into point_ledger (fires trg_point_ledger_sync_balance)
-- If total_points > users.points_balance, raises 409 INSUFFICIENT_POINTS_BALANCE
INSERT INTO point_ledger (
    user_id,
    idempotency_key,
    operation_type,
    points_delta,
    co2_delta_grams,
    reference_entity_type,
    description
) VALUES (
    $1,
    $2,
    'shop_purchase'::ledger_operation_type,
    -$3, -- negative integer (-total_points)
    $4,  -- +2000 * qty if VIRT-FOREST-DONATION is in cart, else 0
    'shop_orders',
    $5
)
RETURNING id;

-- 8. Create shop_orders header linked to ledger_entry_id
INSERT INTO shop_orders (
    user_id,
    idempotency_key,
    ledger_entry_id,
    status,
    total_points,
    item_count
) VALUES (
    $1, $2, $3, 'completed'::order_status, $4, $5
)
RETURNING id, created_at;

-- 9. Insert shop_order_items (coupon_code is VARCHAR(32) UNIQUE, e.g. 'ECO-7F3A-9K2M-4P1X')
INSERT INTO shop_order_items (
    order_id,
    shop_item_id,
    quantity,
    unit_price_points,
    coupon_code,
    qr_payload,
    expires_at
) VALUES (
    $1, $2, $3, $4, $5, $6, $7
)
RETURNING id, line_total_points;
```

#### Immediate Virtual Item Fulfillment (Inside the Same Checkout Transaction):
- `item_type == 'virtual_streak_freeze'` (`VIRT-STREAK-FREEZE`):
```sql
UPDATE users
SET streak_freeze_count = streak_freeze_count + $2,
    updated_at = NOW()
WHERE id = $1;
```
- `item_type == 'mascot_accessory'` (`MASCOT-SCARF-GREEN`, `MASCOT-SOLAR-SHADES`):
```sql
INSERT INTO user_mascot_inventory (user_id, accessory_code)
VALUES ($1, $2);
```
- `item_type == 'virtual_eco_donation'` (`VIRT-FOREST-DONATION`):
Adds `+2000 * quantity` grams of CO₂ to the current ISO week's `shared_forest_challenges` and `shared_forest_contributions` (and evaluates the `'forest_guardian_10k'` badge and challenge completion reward).

### 4.5 Manual Streak Freeze Activation (`POST /api/v1/shop/virtual-items/streak-freeze:activate`)
1. Lock user row (`SELECT ... FROM users WHERE id = $1 FOR UPDATE`).
2. If `streak_freeze_count <= 0`, raise `409 STREAK_FREEZE_NONE_AVAILABLE`.
3. If `last_active_local_date` is already today or yesterday (`last_active_local_date >= user_local_today - 1`), raise `400 STREAK_FREEZE_NOT_NEEDED`.
4. Consume 1 freeze and advance `last_active_local_date` to yesterday so the streak remains unbroken:
```sql
UPDATE users
SET
    streak_freeze_count = streak_freeze_count - 1,
    last_active_local_date = $2, -- (user_local_today - 1 day)
    updated_at = NOW()
WHERE id = $1
RETURNING *;
```

---

## 5. Social, Friends, Wake-Up Nudges & Cooperative "Shared Forest" SQL Blueprints

### 5.1 Friend Requests & Unordered Pair Constraint (`POST /api/v1/friends/requests`)
1. Look up target user by `friend_code`:
```sql
SELECT id FROM users WHERE friend_code = $1;
```
2. If not found, raise `404 FRIEND_CODE_NOT_FOUND`.
3. If `target_id == current_user_id`, raise `400 FRIEND_REQUEST_SELF_FORBIDDEN`.
4. Check existing relationship in `friendships` using the unordered pair index `idx_friendships_unordered_pair`:
```sql
SELECT id, status
FROM friendships
WHERE LEAST(requester_id, addressee_id) = LEAST($1::uuid, $2::uuid)
  AND GREATEST(requester_id, addressee_id) = GREATEST($1::uuid, $2::uuid);
```
5. If row exists and `status == 'blocked'`, raise `403 FRIENDSHIP_BLOCKED`.
6. If row exists and `status IN ('pending', 'accepted')`, raise `409 FRIENDSHIP_ALREADY_EXISTS`.
7. Insert pending request:
```sql
INSERT INTO friendships (requester_id, addressee_id, status)
VALUES ($1, $2, 'pending'::friendship_status)
RETURNING id, requester_id, addressee_id, status, created_at, responded_at;
```

### 5.2 Wake-Up Mascot Nudge & Daily Cooldown (`POST /api/v1/friends/{friend_user_id}/nudge`)
1. Verify an `'accepted'` friendship exists between `current_user_id` and `friend_user_id`; otherwise raise `404 FRIENDSHIP_NOT_FOUND`.
2. Insert into `friend_wakeup_nudges` (relying on `UNIQUE (sender_id, receiver_id, nudge_date)`):
```sql
INSERT INTO friend_wakeup_nudges (sender_id, receiver_id, nudge_date, push_delivered)
VALUES ($1, $2, CURRENT_DATE, FALSE)
RETURNING id, receiver_id, nudge_date, sent_at;
```
3. If `asyncpg.UniqueViolationError` is raised on `friend_wakeup_nudges_sender_id_receiver_id_nudge_date_key`, map to `429 WAKEUP_NUDGE_DAILY_COOLDOWN`.
4. Query active push tokens (`SELECT platform, token FROM user_push_tokens WHERE user_id = $1 AND is_enabled = TRUE`) and dispatch push notification ("Друг {sender_name} будит вашего зверька! 🔔", deep_link = "ecotrack://home") via `PushNotificationProvider`. If delivered, update `push_delivered = TRUE`.

### 5.3 Weekly Friends CO₂ Leaderboard (`GET /api/v1/friends/leaderboard`)
Computes the current ISO week (`week_start_date .. week_end_date`) ranking across the authenticated user and all `'accepted'` friends, masking metrics when a friend has `is_stats_visible_to_friends = FALSE`:
```sql
WITH friend_circle AS (
    SELECT $1::uuid AS uid
    UNION
    SELECT CASE
               WHEN f.requester_id = $1::uuid THEN f.addressee_id
               ELSE f.requester_id
           END AS uid
    FROM friendships f
    WHERE (f.requester_id = $1::uuid OR f.addressee_id = $1::uuid)
      AND f.status = 'accepted'
),
weekly_totals AS (
    SELECT
        u.id AS user_id,
        u.display_name,
        u.avatar_url,
        u.equipped_accessory_code,
        (u.id = $1::uuid) AS is_current_user,
        (u.id = $1::uuid OR u.is_stats_visible_to_friends) AS is_stats_visible,
        CASE
            WHEN (u.id = $1::uuid OR u.is_stats_visible_to_friends)
            THEN COALESCE(SUM(d.total_co2_saved_grams), 0)::int
            ELSE 0
        END AS weekly_co2_saved_grams,
        CASE
            WHEN (u.id = $1::uuid OR u.is_stats_visible_to_friends)
            THEN COALESCE(SUM(d.validated_steps), 0)::int
            ELSE 0
        END AS weekly_steps,
        u.current_streak_days
    FROM friend_circle fc
    JOIN users u ON u.id = fc.uid
    LEFT JOIN daily_step_summaries d
           ON d.user_id = u.id
          AND d.activity_date BETWEEN $2::date AND $3::date
    GROUP BY u.id
)
SELECT
    ROW_NUMBER() OVER (
        ORDER BY is_stats_visible DESC, weekly_co2_saved_grams DESC, weekly_steps DESC, user_id ASC
    )::int AS rank,
    user_id,
    display_name,
    avatar_url,
    equipped_accessory_code,
    is_current_user,
    is_stats_visible,
    weekly_co2_saved_grams,
    weekly_steps,
    current_streak_days
FROM weekly_totals
ORDER BY rank ASC;
```

### 5.4 Cooperative Weekly "Shared Forest" Auto-Seed & Completion Payout
#### Auto-Seeding Current ISO Week Challenge:
Whenever `GET /api/v1/challenges/shared-forest/current` or a CO₂-producing mutation runs, ensure the current ISO week row exists:
```sql
INSERT INTO shared_forest_challenges (
    iso_year, iso_week, week_start_date, week_end_date, title_ru, target_co2_saved_grams
) VALUES (
    $1, $2, $3, $4, 'Общий лес недели #' || $2::text, 50000
)
ON CONFLICT (iso_year, iso_week) DO UPDATE
SET title_ru = shared_forest_challenges.title_ru
RETURNING *;
```

#### Atomic Completion & +50 ★ Participant Reward:
Whenever `shared_forest_challenges.current_co2_saved_grams` crosses `target_co2_saved_grams` while `is_completed = FALSE`:
```sql
UPDATE shared_forest_challenges
SET is_completed = TRUE
WHERE id = $1 AND is_completed = FALSE
RETURNING id;
```
If the UPDATE returns a row, iterate over all contributors in `shared_forest_contributions WHERE challenge_id = $1 AND contributed_co2_grams > 0` and insert +50 ★ into `point_ledger` with a deterministic UUIDv5 idempotency key derived from `uuid5(NAMESPACE_DNS, f"shared-forest:{challenge_id}:{user_id}")` (`ON CONFLICT (idempotency_key) DO NOTHING`).

---

## 6. Idempotency-Key Enforcement & Health/Readiness Probes

### 6.1 UUIDv7 Idempotency-Key Dependency (`require_idempotency_key`)
1. Every mutating endpoint (POST, PUT, PATCH, DELETE, except `/api/v1/auth/refresh`, `/api/v1/auth/logout`, and `/api/v1/push/tokens/{token}`) requires the `Idempotency-Key` header.
2. Validate that `Idempotency-Key` is a valid UUID (version 7 preferred; standard RFC 9562 UUID format accepted for test harnesses). If missing or malformed, raise `400 INVALID_IDEMPOTENCY_KEY`.
3. For ledger-backed and domain-table mutations (`point_ledger.idempotency_key`, `route_segment_allocations.idempotency_key`, `shop_orders.idempotency_key`, `point_reports.idempotency_key`), PostgreSQL `UNIQUE` constraints enforce storage-level idempotency even across Uvicorn worker restarts.
4. Process-local in-flight lock (`asyncio.Lock` keyed by `(user_id, idempotency_key)`): if a duplicate request arrives while the first transaction is still executing, immediately raise `409 IDEMPOTENCY_IN_FLIGHT` (`client_action: "queue_retry"`).

### 6.2 Liveness (`/healthz`) & PostGIS Readiness (`/readyz`) Probes
- `GET /healthz`: Returns `{"status": "ok", "version": "1.0.0", "python_runtime": "3.14"}` with zero database I/O.
- `GET /readyz`: Acquires a connection from `app.state.db_pool` with a 3.0 s timeout and executes:
```sql
SELECT extversion FROM pg_extension WHERE extname = 'postgis';
```
If the pool connection fails, raise `503 DATABASE_UNAVAILABLE`.
If postgis is missing, raise `503 POSTGIS_EXTENSION_UNAVAILABLE`.
Otherwise return 200 OK with `{"status": "ready", "postgres_connected": True, "postgis_version": row["extversion"]}`.
