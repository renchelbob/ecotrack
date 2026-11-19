-- =============================================================================
-- EcoTrack Mobile Client Offline Engine Schema Contract
-- Target Engine: SQLite 3 (sqflite / sqlite3 on Flutter Dart ^3.13.4)
-- Purpose: Local sensor buffering, hybrid CO2 cache, offline outbox & RSO cache
-- =============================================================================

PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;

-- -----------------------------------------------------------------------------
-- 1. CACHED USER PROFILE, SETTINGS, STREAK & 152-FZ STATE
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS local_user_profile (
    user_id TEXT PRIMARY KEY,
    email TEXT,
    display_name TEXT NOT NULL,
    avatar_url TEXT,
    friend_code TEXT NOT NULL,
    auth_provider TEXT NOT NULL CHECK (auth_provider IN ('yandex', 'vk', 'google')),
    is_foreign_provider_lab_mode INTEGER NOT NULL DEFAULT 0 CHECK (is_foreign_provider_lab_mode IN (0, 1)),
    formal_phone_e164 TEXT,
    requires_formal_phone INTEGER NOT NULL DEFAULT 0 CHECK (requires_formal_phone IN (0, 1)),
    points_balance INTEGER NOT NULL DEFAULT 0 CHECK (points_balance >= 0),
    lifetime_points_earned INTEGER NOT NULL DEFAULT 0 CHECK (lifetime_points_earned >= 0),
    lifetime_co2_saved_grams INTEGER NOT NULL DEFAULT 0 CHECK (lifetime_co2_saved_grams >= 0),
    current_streak_days INTEGER NOT NULL DEFAULT 0 CHECK (current_streak_days >= 0),
    longest_streak_days INTEGER NOT NULL DEFAULT 0 CHECK (longest_streak_days >= 0),
    streak_freeze_count INTEGER NOT NULL DEFAULT 0 CHECK (streak_freeze_count >= 0),
    last_active_local_date TEXT,
    daily_step_goal INTEGER NOT NULL DEFAULT 8000 CHECK (daily_step_goal BETWEEN 1000 AND 50000),
    daily_co2_goal_grams INTEGER NOT NULL DEFAULT 1000 CHECK (daily_co2_goal_grams BETWEEN 100 AND 20000),
    stride_length_cm INTEGER NOT NULL DEFAULT 74 CHECK (stride_length_cm BETWEEN 40 AND 120),
    gps_interval_seconds INTEGER NOT NULL DEFAULT 15 CHECK (gps_interval_seconds BETWEEN 5 AND 300),
    is_gps_tracking_enabled INTEGER NOT NULL DEFAULT 0 CHECK (is_gps_tracking_enabled IN (0, 1)),
    is_stats_visible_to_friends INTEGER NOT NULL DEFAULT 1 CHECK (is_stats_visible_to_friends IN (0, 1)),
    is_152fz_consent_active INTEGER NOT NULL DEFAULT 1 CHECK (is_152fz_consent_active IN (0, 1)),
    equipped_accessory_code TEXT,
    updated_at_ms INTEGER NOT NULL
);

-- -----------------------------------------------------------------------------
-- 2. CACHED PERSONAL VEHICLE & TRANSPORT EMISSION CATALOG
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS local_user_vehicle (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL UNIQUE REFERENCES local_user_profile(user_id) ON DELETE CASCADE,
    vehicle_name TEXT NOT NULL,
    fuel TEXT NOT NULL CHECK (
        fuel IN ('petrol_92', 'petrol_95', 'petrol_98', 'diesel', 'lpg', 'cng', 'hybrid', 'electric')
    ),
    consumption_per_100km REAL NOT NULL CHECK (consumption_per_100km > 0 AND consumption_per_100km <= 50.0),
    fuel_emission_factor_g_per_unit REAL NOT NULL CHECK (fuel_emission_factor_g_per_unit >= 0),
    computed_co2_g_per_km REAL NOT NULL CHECK (computed_co2_g_per_km >= 0),
    computed_co2_g_per_meter REAL NOT NULL CHECK (computed_co2_g_per_meter >= 0),
    is_dirty INTEGER NOT NULL DEFAULT 0 CHECK (is_dirty IN (0, 1)),
    updated_at_ms INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS local_transport_catalog (
    mode_code TEXT PRIMARY KEY CHECK (
        mode_code IN ('bus', 'metro', 'tram', 'personal_car', 'car_compact', 'car_sedan', 'car_suv', 'car_ev')
    ),
    display_name_ru TEXT NOT NULL,
    display_name_en TEXT NOT NULL,
    co2_grams_per_km REAL NOT NULL CHECK (co2_grams_per_km >= 0),
    co2_grams_per_meter REAL NOT NULL CHECK (co2_grams_per_meter >= 0),
    is_personal_vehicle_slot INTEGER NOT NULL DEFAULT 0 CHECK (is_personal_vehicle_slot IN (0, 1)),
    sort_order INTEGER NOT NULL DEFAULT 0
);

-- -----------------------------------------------------------------------------
-- 3. LOCAL DAILY STEP SUMMARIES & HYBRID CO2 STATE
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS local_daily_step_summaries (
    activity_date TEXT PRIMARY KEY, -- ISO-8601 YYYY-MM-DD local date
    user_id TEXT NOT NULL,
    timezone_offset_minutes INTEGER NOT NULL DEFAULT 180,
    raw_sensor_steps INTEGER NOT NULL DEFAULT 0 CHECK (raw_sensor_steps >= 0),
    validated_steps INTEGER NOT NULL DEFAULT 0 CHECK (validated_steps >= 0),
    pedometer_boot_baseline INTEGER,
    stride_length_cm INTEGER NOT NULL DEFAULT 74 CHECK (stride_length_cm BETWEEN 40 AND 120),
    total_step_distance_m REAL NOT NULL DEFAULT 0.0 CHECK (total_step_distance_m >= 0.0),
    allocated_gps_distance_m REAL NOT NULL DEFAULT 0.0 CHECK (allocated_gps_distance_m >= 0.0),
    unallocated_step_distance_m REAL NOT NULL DEFAULT 0.0 CHECK (unallocated_step_distance_m >= 0.0),
    allocated_co2_saved_grams INTEGER NOT NULL DEFAULT 0 CHECK (allocated_co2_saved_grams >= 0),
    auto_default_co2_saved_grams INTEGER NOT NULL DEFAULT 0 CHECK (auto_default_co2_saved_grams >= 0),
    total_co2_saved_grams INTEGER NOT NULL DEFAULT 0 CHECK (total_co2_saved_grams >= 0),
    points_awarded_for_day INTEGER NOT NULL DEFAULT 0 CHECK (points_awarded_for_day >= 0),
    is_auto_calculated INTEGER NOT NULL DEFAULT 1 CHECK (is_auto_calculated IN (0, 1)),
    sync_status TEXT NOT NULL DEFAULT 'pending' CHECK (sync_status IN ('pending', 'synced', 'failed')),
    last_sensor_read_at_ms INTEGER NOT NULL,
    last_synced_at_ms INTEGER
);

CREATE INDEX IF NOT EXISTS idx_local_daily_summaries_sync
ON local_daily_step_summaries (sync_status, activity_date DESC);

-- -----------------------------------------------------------------------------
-- 4. LOCAL INTERVAL GPS + CUMULATIVE STEPS TRACK POINTS BUFFER
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS local_gps_track_points (
    local_id INTEGER PRIMARY KEY AUTOINCREMENT,
    activity_date TEXT NOT NULL,
    seq_no INTEGER NOT NULL CHECK (seq_no >= 0),
    recorded_at_ms INTEGER NOT NULL,
    lat REAL NOT NULL CHECK (lat BETWEEN -90.0 AND 90.0),
    lon REAL NOT NULL CHECK (lon BETWEEN -180.0 AND 180.0),
    accuracy_m REAL NOT NULL CHECK (accuracy_m >= 0.0),
    speed_mps REAL NOT NULL DEFAULT 0.0 CHECK (speed_mps >= 0.0),
    cumulative_steps INTEGER NOT NULL CHECK (cumulative_steps >= 0),
    delta_steps INTEGER NOT NULL DEFAULT 0 CHECK (delta_steps >= 0),
    delta_distance_m REAL NOT NULL DEFAULT 0.0 CHECK (delta_distance_m >= 0.0),
    motion_class TEXT NOT NULL DEFAULT 'unknown' CHECK (
        motion_class IN ('unknown', 'walking', 'indoor_pacing', 'vehicle_suspected', 'stationary')
    ),
    sync_status TEXT NOT NULL DEFAULT 'pending' CHECK (sync_status IN ('pending', 'synced', 'failed')),
    UNIQUE (activity_date, seq_no),
    UNIQUE (activity_date, recorded_at_ms)
);

CREATE INDEX IF NOT EXISTS idx_local_gps_points_date_seq
ON local_gps_track_points (activity_date, seq_no ASC);

CREATE INDEX IF NOT EXISTS idx_local_gps_points_sync
ON local_gps_track_points (sync_status, recorded_at_ms ASC);

-- -----------------------------------------------------------------------------
-- 5. LOCAL ROUTE SEGMENT ALLOCATIONS (TODAY & YESTERDAY ANNOTATION)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS local_route_segment_allocations (
    id TEXT PRIMARY KEY,
    idempotency_key TEXT NOT NULL UNIQUE,
    activity_date TEXT NOT NULL,
    start_seq_no INTEGER NOT NULL CHECK (start_seq_no >= 0),
    end_seq_no INTEGER NOT NULL CHECK (end_seq_no > start_seq_no),
    polyline_json TEXT NOT NULL, -- JSON array of [[lat, lon], ...]
    segment_distance_m REAL NOT NULL CHECK (segment_distance_m > 0.0),
    segment_steps INTEGER NOT NULL CHECK (segment_steps >= 0),
    replaced_transport_mode TEXT NOT NULL CHECK (
        replaced_transport_mode IN (
            'bus', 'metro', 'tram', 'personal_car', 'car_compact', 'car_sedan', 'car_suv', 'car_ev'
        )
    ),
    applied_co2_g_per_meter REAL NOT NULL CHECK (applied_co2_g_per_meter >= 0.0),
    confidence_factor REAL NOT NULL DEFAULT 1.0 CHECK (confidence_factor IN (0.7, 1.0)),
    is_auto_calculated INTEGER NOT NULL DEFAULT 0 CHECK (is_auto_calculated IN (0, 1)),
    co2_saved_grams INTEGER NOT NULL CHECK (co2_saved_grams >= 0),
    sync_status TEXT NOT NULL DEFAULT 'pending' CHECK (sync_status IN ('pending', 'synced', 'failed')),
    created_at_ms INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_local_segment_alloc_date
ON local_route_segment_allocations (activity_date, start_seq_no ASC);

-- -----------------------------------------------------------------------------
-- 6. GENERIC OFFLINE MUTATION OUTBOX (IDEMPOTENT RETRY ENGINE)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS offline_mutation_outbox (
    outbox_id INTEGER PRIMARY KEY AUTOINCREMENT,
    idempotency_key TEXT NOT NULL UNIQUE, -- UUIDv7 generated on client
    operation_type TEXT NOT NULL CHECK (
        operation_type IN (
            'sync_daily_steps',
            'upload_gps_track_batch',
            'upsert_segment_allocation',
            'delete_segment_allocation',
            'submit_waste_point_report',
            'create_shop_order',
            'update_user_vehicle',
            'update_user_settings',
            'send_friend_wakeup_nudge',
            'equip_mascot_accessory'
        )
    ),
    http_method TEXT NOT NULL CHECK (http_method IN ('POST', 'PUT', 'PATCH', 'DELETE')),
    endpoint_path TEXT NOT NULL,
    payload_json TEXT NOT NULL,
    retry_count INTEGER NOT NULL DEFAULT 0 CHECK (retry_count >= 0),
    max_retries INTEGER NOT NULL DEFAULT 12 CHECK (max_retries > 0),
    next_retry_at_ms INTEGER NOT NULL,
    last_error TEXT,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (
        status IN ('pending', 'in_flight', 'failed_permanent')
    ),
    created_at_ms INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_offline_outbox_dispatch
ON offline_mutation_outbox (status, next_retry_at_ms ASC, outbox_id ASC);

-- -----------------------------------------------------------------------------
-- 7. CACHED RSO WASTE POINTS & PENDING USER REPORTS
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS cached_waste_points (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    address_text TEXT,
    operator_name TEXT,
    opening_hours TEXT,
    accepted_fractions_csv TEXT NOT NULL, -- Comma-separated waste_fraction_code values
    lat REAL NOT NULL CHECK (lat BETWEEN -90.0 AND 90.0),
    lon REAL NOT NULL CHECK (lon BETWEEN -180.0 AND 180.0),
    status TEXT NOT NULL CHECK (status IN ('active', 'unverified', 'temporarily_closed', 'removed')),
    trust_score REAL NOT NULL CHECK (trust_score BETWEEN 0.0 AND 100.0),
    confirmations_count INTEGER NOT NULL DEFAULT 0,
    issues_count INTEGER NOT NULL DEFAULT 0,
    attribution_text TEXT NOT NULL,
    last_verified_at_ms INTEGER,
    cached_at_ms INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_cached_waste_points_bbox
ON cached_waste_points (lat, lon, status);

CREATE TABLE IF NOT EXISTS pending_waste_point_reports (
    id TEXT PRIMARY KEY,
    idempotency_key TEXT NOT NULL UNIQUE,
    waste_point_id TEXT NOT NULL,
    report_type TEXT NOT NULL CHECK (
        report_type IN (
            'confirm_working', 'overflowing', 'missing_bin', 'wrong_fractions', 'inaccessible', 'photo_update'
        )
    ),
    comment TEXT,
    user_lat REAL NOT NULL CHECK (user_lat BETWEEN -90.0 AND 90.0),
    user_lon REAL NOT NULL CHECK (user_lon BETWEEN -180.0 AND 180.0),
    distance_to_point_m REAL NOT NULL CHECK (distance_to_point_m >= 0.0),
    sync_status TEXT NOT NULL DEFAULT 'pending' CHECK (sync_status IN ('pending', 'synced', 'failed')),
    created_at_ms INTEGER NOT NULL
);

-- -----------------------------------------------------------------------------
-- 8. CACHED STATS, SHARED FOREST, FRIENDS LEADERBOARD & INVENTORY SNAPSHOTS
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS cached_weekly_stats_snapshot (
    iso_year INTEGER NOT NULL,
    iso_week INTEGER NOT NULL,
    daily_breakdown_json TEXT NOT NULL,
    equivalents_json TEXT NOT NULL,
    shared_forest_json TEXT NOT NULL,
    updated_at_ms INTEGER NOT NULL,
    PRIMARY KEY (iso_year, iso_week)
);

CREATE TABLE IF NOT EXISTS cached_friends_leaderboard (
    friend_user_id TEXT PRIMARY KEY,
    display_name TEXT NOT NULL,
    avatar_url TEXT,
    friend_code TEXT NOT NULL,
    friendship_status TEXT NOT NULL CHECK (friendship_status IN ('pending', 'accepted', 'blocked')),
    weekly_co2_saved_grams INTEGER NOT NULL DEFAULT 0,
    weekly_steps INTEGER NOT NULL DEFAULT 0,
    current_streak_days INTEGER NOT NULL DEFAULT 0,
    equipped_accessory_code TEXT,
    is_stats_visible INTEGER NOT NULL DEFAULT 1 CHECK (is_stats_visible IN (0, 1)),
    last_nudge_date TEXT,
    updated_at_ms INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_cached_friends_ranking
ON cached_friends_leaderboard (friendship_status, weekly_co2_saved_grams DESC);

CREATE TABLE IF NOT EXISTS cached_badges_and_inventory (
    item_kind TEXT NOT NULL CHECK (item_kind IN ('badge', 'accessory')),
    code TEXT NOT NULL,
    title_ru TEXT NOT NULL,
    description_ru TEXT NOT NULL,
    icon_or_layer_key TEXT NOT NULL,
    slot TEXT,
    is_unlocked INTEGER NOT NULL DEFAULT 0 CHECK (is_unlocked IN (0, 1)),
    is_equipped INTEGER NOT NULL DEFAULT 0 CHECK (is_equipped IN (0, 1)),
    progress_value INTEGER NOT NULL DEFAULT 0,
    threshold_value INTEGER NOT NULL DEFAULT 1,
    updated_at_ms INTEGER NOT NULL,
    PRIMARY KEY (item_kind, code)
);
