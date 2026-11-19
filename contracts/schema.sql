-- =============================================================================
-- EcoTrack Production Database Schema Contract
-- Target Engine: PostgreSQL 17.x + PostGIS 3.5 (postgis/postgis:17-3.5-alpine)
-- Compliance: Russian Federal Law 152-FZ & 406-FZ (with explicit Lab Mode caveat)
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. EXTENSIONS & UUIDv7 GENERATOR FUNCTION
-- -----------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE OR REPLACE FUNCTION uuid_generate_v7()
RETURNS UUID
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    v_time BIGINT;
    v_bytes BYTEA;
BEGIN
    v_time := FLOOR(EXTRACT(EPOCH FROM clock_timestamp()) * 1000)::BIGINT;
    v_bytes := gen_random_bytes(16);

    -- 48-bit big-endian Unix epoch timestamp in milliseconds
    v_bytes := set_byte(v_bytes, 0, ((v_time >> 40) & 255)::INT);
    v_bytes := set_byte(v_bytes, 1, ((v_time >> 32) & 255)::INT);
    v_bytes := set_byte(v_bytes, 2, ((v_time >> 24) & 255)::INT);
    v_bytes := set_byte(v_bytes, 3, ((v_time >> 16) & 255)::INT);
    v_bytes := set_byte(v_bytes, 4, ((v_time >> 8) & 255)::INT);
    v_bytes := set_byte(v_bytes, 5, (v_time & 255)::INT);

    -- Version 7 (0111xxxx)
    v_bytes := set_byte(v_bytes, 6, (get_byte(v_bytes, 6) & 15) | 112);
    -- Variant RFC 4122 / RFC 9562 (10xxxxxx)
    v_bytes := set_byte(v_bytes, 8, (get_byte(v_bytes, 8) & 63) | 128);

    RETURN encode(v_bytes, 'hex')::UUID;
END;
$$;

-- -----------------------------------------------------------------------------
-- 2. ENUMERATED TYPES
-- -----------------------------------------------------------------------------
CREATE TYPE oauth_provider_type AS ENUM (
    'yandex',
    'vk',
    'google'
);

CREATE TYPE consent_action_type AS ENUM (
    'granted',
    'revoked',
    'updated'
);

CREATE TYPE fuel_type AS ENUM (
    'petrol_92',
    'petrol_95',
    'petrol_98',
    'diesel',
    'lpg',
    'cng',
    'hybrid',
    'electric'
);

CREATE TYPE transport_mode_code AS ENUM (
    'bus',
    'metro',
    'tram',
    'personal_car',
    'car_compact',
    'car_sedan',
    'car_suv',
    'car_ev'
);

CREATE TYPE track_point_motion_class AS ENUM (
    'unknown',
    'walking',
    'indoor_pacing',
    'vehicle_suspected',
    'stationary'
);

CREATE TYPE ledger_operation_type AS ENUM (
    'daily_steps_reward',
    'segment_annotation_delta',
    'streak_bonus',
    'challenge_reward',
    'badge_reward',
    'shop_purchase',
    'shop_refund',
    'admin_adjustment'
);

CREATE TYPE shop_item_type AS ENUM (
    'partner_coupon',
    'partner_qr',
    'virtual_streak_freeze',
    'virtual_eco_donation',
    'mascot_accessory'
);

CREATE TYPE order_status AS ENUM (
    'completed',
    'redeemed',
    'refunded',
    'expired'
);

CREATE TYPE friendship_status AS ENUM (
    'pending',
    'accepted',
    'blocked'
);

CREATE TYPE waste_fraction_code AS ENUM (
    'plastic',
    'glass',
    'paper',
    'metal',
    'tetra_pak',
    'batteries',
    'electronics',
    'clothes',
    'hazardous',
    'caps',
    'mixed_recyclables',
    'general_bin'
);

CREATE TYPE rso_source_type AS ENUM (
    'osm_pbf',
    'data_mos_ru',
    'municipal_registry',
    'community_verified'
);

CREATE TYPE waste_point_status AS ENUM (
    'active',
    'unverified',
    'temporarily_closed',
    'removed'
);

CREATE TYPE report_type AS ENUM (
    'confirm_working',
    'overflowing',
    'missing_bin',
    'wrong_fractions',
    'inaccessible',
    'photo_update'
);

CREATE TYPE push_platform_type AS ENUM (
    'fcm_android',
    'fcm_ios',
    'rustore',
    'apns'
);

-- -----------------------------------------------------------------------------
-- 3. MASCOT ACCESSORIES CATALOG (Referenced by users & shop)
-- -----------------------------------------------------------------------------
CREATE TABLE mascot_accessories (
    code VARCHAR(64) PRIMARY KEY,
    name_ru VARCHAR(80) NOT NULL,
    slot VARCHAR(32) NOT NULL CHECK (slot IN ('head', 'neck', 'glasses', 'aura', 'companion')),
    vector_layer_key VARCHAR(64) NOT NULL,
    unlock_type VARCHAR(32) NOT NULL CHECK (unlock_type IN ('starter', 'shop', 'badge', 'streak')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- -----------------------------------------------------------------------------
-- 4. USERS, AUTHENTICATION & 152-FZ COMPLIANCE TABLES
-- -----------------------------------------------------------------------------
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    email VARCHAR(254),
    display_name VARCHAR(80) NOT NULL CHECK (char_length(trim(display_name)) >= 1),
    avatar_url TEXT,
    friend_code VARCHAR(12) NOT NULL UNIQUE CHECK (friend_code ~ '^ECO-[A-Z0-9]{4}-[A-Z0-9]{4}$'),
    formal_phone_e164 VARCHAR(20) CHECK (
        formal_phone_e164 IS NULL OR formal_phone_e164 ~ '^\+[1-9][0-9]{7,14}$'
    ),
    requires_formal_phone BOOLEAN NOT NULL DEFAULT FALSE,
    points_balance INTEGER NOT NULL DEFAULT 0 CHECK (points_balance >= 0),
    lifetime_points_earned INTEGER NOT NULL DEFAULT 0 CHECK (lifetime_points_earned >= 0),
    lifetime_co2_saved_grams BIGINT NOT NULL DEFAULT 0 CHECK (lifetime_co2_saved_grams >= 0),
    current_streak_days INTEGER NOT NULL DEFAULT 0 CHECK (current_streak_days >= 0),
    longest_streak_days INTEGER NOT NULL DEFAULT 0 CHECK (longest_streak_days >= 0),
    streak_freeze_count INTEGER NOT NULL DEFAULT 0 CHECK (streak_freeze_count >= 0),
    last_active_local_date DATE,
    daily_step_goal INTEGER NOT NULL DEFAULT 8000 CHECK (daily_step_goal BETWEEN 1000 AND 50000),
    daily_co2_goal_grams INTEGER NOT NULL DEFAULT 1000 CHECK (daily_co2_goal_grams BETWEEN 100 AND 20000),
    stride_length_cm INTEGER NOT NULL DEFAULT 74 CHECK (stride_length_cm BETWEEN 40 AND 120),
    gps_interval_seconds INTEGER NOT NULL DEFAULT 15 CHECK (gps_interval_seconds BETWEEN 5 AND 300),
    is_gps_tracking_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    is_stats_visible_to_friends BOOLEAN NOT NULL DEFAULT TRUE,
    is_152fz_consent_active BOOLEAN NOT NULL DEFAULT TRUE,
    equipped_accessory_code VARCHAR(64) REFERENCES mascot_accessories(code) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_users_friend_code ON users (friend_code);

CREATE TABLE user_oauth_identities (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider oauth_provider_type NOT NULL,
    provider_subject_id VARCHAR(255) NOT NULL,
    provider_email VARCHAR(254),
    is_foreign_provider_lab_mode BOOLEAN NOT NULL DEFAULT FALSE,
    last_login_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (provider, provider_subject_id),
    CHECK (
        (provider = 'google' AND is_foreign_provider_lab_mode = TRUE)
        OR (provider IN ('yandex', 'vk') AND is_foreign_provider_lab_mode = FALSE)
    )
);

CREATE INDEX idx_user_oauth_identities_user_id ON user_oauth_identities (user_id);

CREATE TABLE auth_refresh_sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash CHAR(64) NOT NULL UNIQUE,
    device_fingerprint VARCHAR(128) NOT NULL,
    user_agent TEXT,
    ip_address INET,
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_auth_refresh_sessions_user_id ON auth_refresh_sessions (user_id);
CREATE INDEX idx_auth_refresh_sessions_expires_at ON auth_refresh_sessions (expires_at);

CREATE TABLE fz152_consent_journal (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    policy_version VARCHAR(32) NOT NULL,
    action consent_action_type NOT NULL,
    consent_scope JSONB NOT NULL,
    ip_address INET,
    user_agent TEXT,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (jsonb_typeof(consent_scope) = 'object')
);

CREATE INDEX idx_fz152_consent_journal_user_id ON fz152_consent_journal (user_id, recorded_at DESC);

-- Anonymized audit log without FK to users so it survives 152-FZ CASCADE erasure
CREATE TABLE fz152_account_deletion_log (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    anonymized_user_hash CHAR(64) NOT NULL,
    deletion_reason VARCHAR(128) NOT NULL,
    requested_at TIMESTAMPTZ NOT NULL,
    purged_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    verification_signature CHAR(64) NOT NULL
);

CREATE INDEX idx_fz152_deletion_log_purged_at ON fz152_account_deletion_log (purged_at DESC);

CREATE TABLE user_push_tokens (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    platform push_platform_type NOT NULL,
    token TEXT NOT NULL,
    device_id VARCHAR(128) NOT NULL,
    is_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, device_id)
);

CREATE INDEX idx_user_push_tokens_user_enabled ON user_push_tokens (user_id) WHERE is_enabled = TRUE;

-- -----------------------------------------------------------------------------
-- 5. TRANSPORT EMISSION CATALOG & USER PERSONAL VEHICLES
-- -----------------------------------------------------------------------------
CREATE TABLE transport_emission_catalog (
    mode_code transport_mode_code PRIMARY KEY,
    display_name_ru VARCHAR(64) NOT NULL,
    display_name_en VARCHAR(64) NOT NULL,
    co2_grams_per_km NUMERIC(8, 2) NOT NULL CHECK (co2_grams_per_km >= 0),
    co2_grams_per_meter NUMERIC(8, 5) GENERATED ALWAYS AS (ROUND(co2_grams_per_km / 1000.0, 5)) STORED,
    is_personal_vehicle_slot BOOLEAN NOT NULL DEFAULT FALSE,
    sort_order SMALLINT NOT NULL DEFAULT 0
);

CREATE TABLE user_vehicles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    vehicle_name VARCHAR(80) NOT NULL DEFAULT 'Мой автомобиль',
    fuel fuel_type NOT NULL,
    consumption_per_100km NUMERIC(5, 2) NOT NULL CHECK (consumption_per_100km > 0 AND consumption_per_100km <= 50.00),
    fuel_emission_factor_g_per_unit NUMERIC(8, 2) NOT NULL CHECK (fuel_emission_factor_g_per_unit >= 0),
    computed_co2_g_per_km NUMERIC(8, 2) GENERATED ALWAYS AS (
        ROUND((consumption_per_100km * fuel_emission_factor_g_per_unit) / 100.0, 2)
    ) STORED,
    computed_co2_g_per_meter NUMERIC(8, 5) GENERATED ALWAYS AS (
        ROUND((consumption_per_100km * fuel_emission_factor_g_per_unit) / 100000.0, 5)
    ) STORED,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- -----------------------------------------------------------------------------
-- 6. DAILY STEPS, INTERVAL GPS TRACKING & HYBRID CO2 SEGMENT ALLOCATIONS
-- -----------------------------------------------------------------------------
CREATE TABLE daily_step_summaries (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    activity_date DATE NOT NULL,
    timezone_offset_minutes SMALLINT NOT NULL DEFAULT 180 CHECK (timezone_offset_minutes BETWEEN -720 AND 840),
    raw_sensor_steps INTEGER NOT NULL DEFAULT 0 CHECK (raw_sensor_steps >= 0),
    validated_steps INTEGER NOT NULL DEFAULT 0 CHECK (validated_steps >= 0 AND validated_steps <= 100000),
    stride_length_cm INTEGER NOT NULL DEFAULT 74 CHECK (stride_length_cm BETWEEN 40 AND 120),
    total_step_distance_m NUMERIC(10, 2) GENERATED ALWAYS AS (
        ROUND((validated_steps::NUMERIC * stride_length_cm::NUMERIC) / 100.0, 2)
    ) STORED,
    allocated_gps_distance_m NUMERIC(10, 2) NOT NULL DEFAULT 0.00 CHECK (allocated_gps_distance_m >= 0),
    unallocated_step_distance_m NUMERIC(10, 2) GENERATED ALWAYS AS (
        GREATEST(0.00, ROUND(((validated_steps::NUMERIC * stride_length_cm::NUMERIC) / 100.0) - allocated_gps_distance_m, 2))
    ) STORED,
    allocated_co2_saved_grams INTEGER NOT NULL DEFAULT 0 CHECK (allocated_co2_saved_grams >= 0),
    auto_default_co2_saved_grams INTEGER NOT NULL DEFAULT 0 CHECK (auto_default_co2_saved_grams >= 0),
    total_co2_saved_grams INTEGER GENERATED ALWAYS AS (
        allocated_co2_saved_grams + auto_default_co2_saved_grams
    ) STORED,
    points_awarded_for_day INTEGER NOT NULL DEFAULT 0 CHECK (points_awarded_for_day >= 0),
    is_auto_calculated BOOLEAN NOT NULL DEFAULT TRUE,
    antifraud_flagged BOOLEAN NOT NULL DEFAULT FALSE,
    antifraud_reason VARCHAR(128),
    last_synced_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, activity_date)
);

CREATE INDEX idx_daily_step_summaries_user_date ON daily_step_summaries (user_id, activity_date DESC);
CREATE INDEX idx_daily_step_summaries_date_co2 ON daily_step_summaries (activity_date, total_co2_saved_grams DESC);

CREATE TABLE gps_daily_tracks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    daily_summary_id UUID NOT NULL UNIQUE REFERENCES daily_step_summaries(id) ON DELETE CASCADE,
    activity_date DATE NOT NULL,
    route_geom geometry(LineString, 4326) CHECK (route_geom IS NULL OR ST_IsValid(route_geom)),
    total_gps_walking_distance_m NUMERIC(10, 2) NOT NULL DEFAULT 0.00 CHECK (total_gps_walking_distance_m >= 0),
    point_count INTEGER NOT NULL DEFAULT 0 CHECK (point_count >= 0),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, activity_date)
);

CREATE INDEX idx_gps_daily_tracks_geom_gist ON gps_daily_tracks USING GIST (route_geom);

CREATE TABLE gps_track_points (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    track_id UUID NOT NULL REFERENCES gps_daily_tracks(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    seq_no INTEGER NOT NULL CHECK (seq_no >= 0),
    recorded_at TIMESTAMPTZ NOT NULL,
    lat DOUBLE PRECISION NOT NULL CHECK (lat BETWEEN -90.0 AND 90.0),
    lon DOUBLE PRECISION NOT NULL CHECK (lon BETWEEN -180.0 AND 180.0),
    geom geometry(Point, 4326) GENERATED ALWAYS AS (ST_SetSRID(ST_MakePoint(lon, lat), 4326)) STORED,
    accuracy_m REAL NOT NULL CHECK (accuracy_m >= 0),
    speed_mps REAL NOT NULL DEFAULT 0.0 CHECK (speed_mps >= 0),
    cumulative_steps INTEGER NOT NULL CHECK (cumulative_steps >= 0),
    delta_steps INTEGER NOT NULL DEFAULT 0 CHECK (delta_steps >= 0),
    delta_distance_m NUMERIC(8, 2) NOT NULL DEFAULT 0.00 CHECK (delta_distance_m >= 0),
    motion_class track_point_motion_class NOT NULL DEFAULT 'unknown',
    UNIQUE (track_id, seq_no),
    UNIQUE (track_id, recorded_at)
);

CREATE INDEX idx_gps_track_points_track_seq ON gps_track_points (track_id, seq_no);
CREATE INDEX idx_gps_track_points_geom_gist ON gps_track_points USING GIST (geom);

CREATE TABLE route_segment_allocations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    daily_summary_id UUID NOT NULL REFERENCES daily_step_summaries(id) ON DELETE CASCADE,
    track_id UUID NOT NULL REFERENCES gps_daily_tracks(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    activity_date DATE NOT NULL,
    start_seq_no INTEGER NOT NULL CHECK (start_seq_no >= 0),
    end_seq_no INTEGER NOT NULL CHECK (end_seq_no > start_seq_no),
    segment_geom geometry(LineString, 4326) NOT NULL CHECK (ST_IsValid(segment_geom)),
    segment_distance_m NUMERIC(10, 2) NOT NULL CHECK (segment_distance_m > 0),
    segment_steps INTEGER NOT NULL CHECK (segment_steps >= 0),
    replaced_transport_mode transport_mode_code NOT NULL,
    applied_co2_g_per_meter NUMERIC(8, 5) NOT NULL CHECK (applied_co2_g_per_meter >= 0),
    confidence_factor NUMERIC(3, 2) NOT NULL DEFAULT 1.00 CHECK (confidence_factor IN (0.70, 1.00)),
    is_auto_calculated BOOLEAN NOT NULL DEFAULT FALSE,
    co2_saved_grams INTEGER NOT NULL CHECK (co2_saved_grams >= 0),
    idempotency_key UUID NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_route_segment_allocations_summary ON route_segment_allocations (daily_summary_id);
CREATE INDEX idx_route_segment_allocations_user_date ON route_segment_allocations (user_id, activity_date DESC);
CREATE INDEX idx_route_segment_allocations_geom_gist ON route_segment_allocations USING GIST (segment_geom);

-- -----------------------------------------------------------------------------
-- 7. IMMUTABLE POINT LEDGER & ATOMIC BALANCE SYNC TRIGGERS
-- -----------------------------------------------------------------------------
CREATE TABLE point_ledger (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    idempotency_key UUID NOT NULL UNIQUE,
    operation_type ledger_operation_type NOT NULL,
    points_delta INTEGER NOT NULL CHECK (points_delta <> 0),
    co2_delta_grams BIGINT NOT NULL DEFAULT 0,
    reference_entity_type VARCHAR(64),
    reference_entity_id UUID,
    description VARCHAR(255) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_point_ledger_user_created ON point_ledger (user_id, created_at DESC);

CREATE OR REPLACE FUNCTION fn_protect_point_ledger_immutability()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        RAISE EXCEPTION 'point_ledger is strictly append-only; UPDATE is prohibited (row id=%).', OLD.id
            USING ERRCODE = 'integrity_constraint_violation';
    END IF;

    -- Allow DELETE only during explicit 152-FZ account erasure transaction
    IF TG_OP = 'DELETE' THEN
        IF current_setting('ecotrack.in_152fz_account_erasure', true) = 'true' THEN
            RETURN OLD;
        END IF;
        RAISE EXCEPTION 'point_ledger is strictly append-only; direct DELETE is prohibited (row id=%).', OLD.id
            USING ERRCODE = 'integrity_constraint_violation';
    END IF;

    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_point_ledger_immutable
BEFORE UPDATE OR DELETE ON point_ledger
FOR EACH ROW
EXECUTE FUNCTION fn_protect_point_ledger_immutability();

CREATE OR REPLACE FUNCTION fn_sync_user_balance_from_ledger()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE users
    SET
        points_balance = points_balance + NEW.points_delta,
        lifetime_points_earned = lifetime_points_earned + GREATEST(0, NEW.points_delta),
        lifetime_co2_saved_grams = GREATEST(0, lifetime_co2_saved_grams + NEW.co2_delta_grams),
        updated_at = NOW()
    WHERE id = NEW.user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Target user % not found for point_ledger insert.', NEW.user_id
            USING ERRCODE = 'foreign_key_violation';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_point_ledger_sync_balance
AFTER INSERT ON point_ledger
FOR EACH ROW
EXECUTE FUNCTION fn_sync_user_balance_from_ledger();

-- -----------------------------------------------------------------------------
-- 8. FICTIONAL SHOP, PARTNERS, ORDERS & VIRTUAL INVENTORY
-- -----------------------------------------------------------------------------
CREATE TABLE shop_partners (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    slug VARCHAR(64) NOT NULL UNIQUE,
    name VARCHAR(100) NOT NULL,
    category_name VARCHAR(64) NOT NULL,
    logo_asset_key VARCHAR(128) NOT NULL,
    description TEXT NOT NULL,
    is_fictional_disclaimer VARCHAR(255) NOT NULL DEFAULT 'Демонстрационный партнёр EcoTrack (вымышленный бренд)',
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE shop_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    partner_id UUID REFERENCES shop_partners(id) ON DELETE SET NULL,
    sku VARCHAR(64) NOT NULL UNIQUE,
    item_type shop_item_type NOT NULL,
    title VARCHAR(120) NOT NULL,
    subtitle VARCHAR(160) NOT NULL,
    description TEXT NOT NULL,
    price_points INTEGER NOT NULL CHECK (price_points > 0),
    stock_quantity INTEGER CHECK (stock_quantity IS NULL OR stock_quantity >= 0),
    max_per_user_per_day SMALLINT NOT NULL DEFAULT 3 CHECK (max_per_user_per_day > 0),
    accessory_code VARCHAR(64) REFERENCES mascot_accessories(code) ON DELETE SET NULL,
    image_asset_key VARCHAR(128) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    sort_order SMALLINT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_shop_items_active_sort ON shop_items (is_active, sort_order, title);

CREATE TABLE shop_orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    idempotency_key UUID NOT NULL UNIQUE,
    ledger_entry_id UUID NOT NULL UNIQUE REFERENCES point_ledger(id) ON DELETE CASCADE,
    status order_status NOT NULL DEFAULT 'completed',
    total_points INTEGER NOT NULL CHECK (total_points > 0),
    item_count SMALLINT NOT NULL CHECK (item_count > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_shop_orders_user_created ON shop_orders (user_id, created_at DESC);

CREATE TABLE shop_order_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    order_id UUID NOT NULL REFERENCES shop_orders(id) ON DELETE CASCADE,
    shop_item_id UUID NOT NULL REFERENCES shop_items(id) ON DELETE RESTRICT,
    quantity SMALLINT NOT NULL CHECK (quantity > 0 AND quantity <= 10),
    unit_price_points INTEGER NOT NULL CHECK (unit_price_points > 0),
    line_total_points INTEGER GENERATED ALWAYS AS (quantity * unit_price_points) STORED,
    coupon_code VARCHAR(32) NOT NULL UNIQUE,
    qr_payload TEXT NOT NULL,
    expires_at TIMESTAMPTZ,
    redeemed_at TIMESTAMPTZ
);

CREATE INDEX idx_shop_order_items_order_id ON shop_order_items (order_id);

CREATE TABLE user_mascot_inventory (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    accessory_code VARCHAR(64) NOT NULL REFERENCES mascot_accessories(code) ON DELETE CASCADE,
    acquired_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, accessory_code)
);

-- -----------------------------------------------------------------------------
-- 9. BADGES & ACHIEVEMENTS
-- -----------------------------------------------------------------------------
CREATE TABLE badges_catalog (
    code VARCHAR(64) PRIMARY KEY,
    title_ru VARCHAR(80) NOT NULL,
    description_ru VARCHAR(255) NOT NULL,
    icon_vector_key VARCHAR(64) NOT NULL,
    threshold_type VARCHAR(32) NOT NULL CHECK (
        threshold_type IN (
            'steps_total',
            'co2_grams_total',
            'streak_days',
            'rso_reports',
            'friends_count',
            'forest_contribution'
        )
    ),
    threshold_value INTEGER NOT NULL CHECK (threshold_value > 0),
    reward_points INTEGER NOT NULL DEFAULT 0 CHECK (reward_points >= 0),
    reward_accessory_code VARCHAR(64) REFERENCES mascot_accessories(code) ON DELETE SET NULL,
    sort_order SMALLINT NOT NULL DEFAULT 0
);

CREATE TABLE user_badges (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    badge_code VARCHAR(64) NOT NULL REFERENCES badges_catalog(code) ON DELETE CASCADE,
    awarded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ledger_entry_id UUID REFERENCES point_ledger(id) ON DELETE SET NULL,
    PRIMARY KEY (user_id, badge_code)
);

-- -----------------------------------------------------------------------------
-- 10. FRIENDSHIPS & WAKE-UP MASCOT NUDGES
-- -----------------------------------------------------------------------------
CREATE TABLE friendships (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    requester_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    addressee_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status friendship_status NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    responded_at TIMESTAMPTZ,
    CHECK (requester_id <> addressee_id)
);

CREATE UNIQUE INDEX idx_friendships_unordered_pair
ON friendships (LEAST(requester_id, addressee_id), GREATEST(requester_id, addressee_id));

CREATE INDEX idx_friendships_requester_status ON friendships (requester_id, status);
CREATE INDEX idx_friendships_addressee_status ON friendships (addressee_id, status);

CREATE TABLE friend_wakeup_nudges (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    receiver_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    nudge_date DATE NOT NULL DEFAULT CURRENT_DATE,
    sent_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    push_delivered BOOLEAN NOT NULL DEFAULT FALSE,
    CHECK (sender_id <> receiver_id),
    UNIQUE (sender_id, receiver_id, nudge_date)
);

CREATE INDEX idx_friend_wakeup_nudges_receiver_date ON friend_wakeup_nudges (receiver_id, nudge_date DESC);

-- -----------------------------------------------------------------------------
-- 11. COOPERATIVE WEEKLY "SHARED FOREST" CHALLENGES
-- -----------------------------------------------------------------------------
CREATE TABLE shared_forest_challenges (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    iso_year SMALLINT NOT NULL CHECK (iso_year >= 2025),
    iso_week SMALLINT NOT NULL CHECK (iso_week BETWEEN 1 AND 53),
    week_start_date DATE NOT NULL,
    week_end_date DATE NOT NULL,
    title_ru VARCHAR(120) NOT NULL,
    target_co2_saved_grams BIGINT NOT NULL CHECK (target_co2_saved_grams > 0),
    current_co2_saved_grams BIGINT NOT NULL DEFAULT 0 CHECK (current_co2_saved_grams >= 0),
    trees_equivalent_planted INTEGER GENERATED ALWAYS AS (
        FLOOR(current_co2_saved_grams / 20000.0)::INTEGER
    ) STORED,
    is_completed BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (iso_year, iso_week),
    CHECK (week_end_date >= week_start_date)
);

CREATE TABLE shared_forest_contributions (
    challenge_id UUID NOT NULL REFERENCES shared_forest_challenges(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    contributed_co2_grams BIGINT NOT NULL DEFAULT 0 CHECK (contributed_co2_grams >= 0),
    contributed_steps INTEGER NOT NULL DEFAULT 0 CHECK (contributed_steps >= 0),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (challenge_id, user_id)
);

CREATE INDEX idx_shared_forest_contrib_ranking
ON shared_forest_contributions (challenge_id, contributed_co2_grams DESC);

-- -----------------------------------------------------------------------------
-- 12. RSO / RECYCLING & WASTE MAP TABLES (PostGIS 3.5)
-- -----------------------------------------------------------------------------
CREATE TABLE rso_source_records (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    source_type rso_source_type NOT NULL,
    external_record_id VARCHAR(128) NOT NULL,
    license_name VARCHAR(64) NOT NULL,
    raw_tags JSONB NOT NULL DEFAULT '{}'::JSONB,
    geom geometry(Point, 4326) NOT NULL CHECK (ST_IsValid(geom)),
    imported_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    source_updated_at TIMESTAMPTZ,
    UNIQUE (source_type, external_record_id),
    CHECK (jsonb_typeof(raw_tags) = 'object')
);

CREATE INDEX idx_rso_source_records_geom_gist ON rso_source_records USING GIST (geom);
CREATE INDEX idx_rso_source_records_tags_gin ON rso_source_records USING GIN (raw_tags);

CREATE TABLE waste_points (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    title VARCHAR(160) NOT NULL,
    address_text VARCHAR(255),
    operator_name VARCHAR(120),
    opening_hours VARCHAR(160),
    accepted_fractions waste_fraction_code[] NOT NULL CHECK (cardinality(accepted_fractions) > 0),
    geom geometry(Point, 4326) NOT NULL CHECK (ST_IsValid(geom)),
    geog geography(Point, 4326) GENERATED ALWAYS AS (geom::geography) STORED,
    status waste_point_status NOT NULL DEFAULT 'active',
    trust_score NUMERIC(5, 2) NOT NULL DEFAULT 50.00 CHECK (trust_score BETWEEN 0.00 AND 100.00),
    confirmations_count INTEGER NOT NULL DEFAULT 0 CHECK (confirmations_count >= 0),
    issues_count INTEGER NOT NULL DEFAULT 0 CHECK (issues_count >= 0),
    attribution_text VARCHAR(255) NOT NULL DEFAULT '© Участники OpenStreetMap (ODbL) / Открытые данные',
    last_verified_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_waste_points_geom_gist ON waste_points USING GIST (geom);
CREATE INDEX idx_waste_points_geog_gist ON waste_points USING GIST (geog);
CREATE INDEX idx_waste_points_fractions_gin ON waste_points USING GIN (accepted_fractions);
CREATE INDEX idx_waste_points_status_trust ON waste_points (status, trust_score DESC);

CREATE TABLE point_source_links (
    waste_point_id UUID NOT NULL REFERENCES waste_points(id) ON DELETE CASCADE,
    source_record_id UUID NOT NULL REFERENCES rso_source_records(id) ON DELETE CASCADE,
    match_distance_m NUMERIC(6, 2) NOT NULL DEFAULT 0.00 CHECK (match_distance_m >= 0),
    linked_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (waste_point_id, source_record_id)
);

CREATE INDEX idx_point_source_links_source_id ON point_source_links (source_record_id);

CREATE TABLE point_reports (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    waste_point_id UUID NOT NULL REFERENCES waste_points(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    idempotency_key UUID NOT NULL UNIQUE,
    report_type report_type NOT NULL,
    comment TEXT CHECK (comment IS NULL OR char_length(comment) <= 500),
    user_lat DOUBLE PRECISION NOT NULL CHECK (user_lat BETWEEN -90.0 AND 90.0),
    user_lon DOUBLE PRECISION NOT NULL CHECK (user_lon BETWEEN -180.0 AND 180.0),
    distance_to_point_m NUMERIC(8, 2) NOT NULL CHECK (distance_to_point_m >= 0),
    trust_delta NUMERIC(5, 2) NOT NULL CHECK (trust_delta BETWEEN -30.00 AND 20.00),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_point_reports_waste_point_created ON point_reports (waste_point_id, created_at DESC);
CREATE INDEX idx_point_reports_user_created ON point_reports (user_id, created_at DESC);

CREATE OR REPLACE FUNCTION fn_apply_waste_point_report_trust()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_new_trust NUMERIC(5, 2);
BEGIN
    UPDATE waste_points
    SET
        trust_score = LEAST(100.00, GREATEST(0.00, trust_score + NEW.trust_delta)),
        confirmations_count = confirmations_count + CASE WHEN NEW.report_type = 'confirm_working' THEN 1 ELSE 0 END,
        issues_count = issues_count + CASE WHEN NEW.report_type <> 'confirm_working' THEN 1 ELSE 0 END,
        last_verified_at = CASE WHEN NEW.report_type = 'confirm_working' THEN NOW() ELSE last_verified_at END,
        updated_at = NOW()
    WHERE id = NEW.waste_point_id
    RETURNING trust_score INTO v_new_trust;

    IF v_new_trust < 25.00 THEN
        UPDATE waste_points
        SET status = 'unverified'
        WHERE id = NEW.waste_point_id AND status = 'active';
    ELSIF v_new_trust >= 50.00 THEN
        UPDATE waste_points
        SET status = 'active'
        WHERE id = NEW.waste_point_id AND status = 'unverified';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_point_reports_apply_trust
AFTER INSERT ON point_reports
FOR EACH ROW
EXECUTE FUNCTION fn_apply_waste_point_report_trust();

-- -----------------------------------------------------------------------------
-- 13. REFERENCE & STARTER SEED DATA
-- -----------------------------------------------------------------------------

-- 13.1 Transport Emission Coefficients
INSERT INTO transport_emission_catalog (
    mode_code, display_name_ru, display_name_en, co2_grams_per_km, is_personal_vehicle_slot, sort_order
) VALUES
    ('bus',          'Автобус / электробус', 'City Bus',            82.00,  FALSE, 1),
    ('metro',        'Метро / МЦК / МЦД',    'Metro / Urban Rail',  28.00,  FALSE, 2),
    ('tram',         'Трамвай',              'Tram',                35.00,  FALSE, 3),
    ('personal_car', 'Мой автомобиль',       'My Personal Vehicle', 192.00, TRUE,  4),
    ('car_compact',  'Авто (компакт B-класс)', 'Compact Car',       145.00, FALSE, 5),
    ('car_sedan',    'Авто (седан C/D-класс)', 'Average Sedan',     192.00, FALSE, 6),
    ('car_suv',      'Авто (кроссовер / SUV)', 'SUV / Crossover',   255.00, FALSE, 7),
    ('car_ev',       'Электромобиль (РФ сеть)', 'Electric Vehicle',  58.00, FALSE, 8)
ON CONFLICT (mode_code) DO NOTHING;

-- 13.2 Mascot Vector Accessories
INSERT INTO mascot_accessories (
    code, name_ru, slot, vector_layer_key, unlock_type
) VALUES
    ('leaf_sprout_hat', 'Росток клевера',        'head',      'layer_head_leaf_sprout', 'starter'),
    ('knit_green_scarf', 'Вязаный эко-шарф',     'neck',      'layer_neck_knit_scarf',  'shop'),
    ('solar_shades',    'Солнечные очки',        'glasses',   'layer_glasses_solar',    'shop'),
    ('moss_crown',      'Лесная корона мха',     'head',      'layer_head_moss_crown',  'badge'),
    ('firefly_aura',    'Аура светлячков',       'aura',      'layer_aura_fireflies',   'streak')
ON CONFLICT (code) DO NOTHING;

-- 13.3 Badges Catalog
INSERT INTO badges_catalog (
    code, title_ru, description_ru, icon_vector_key, threshold_type, threshold_value, reward_points, reward_accessory_code, sort_order
) VALUES
    ('first_10k_steps',    'Первые 10 000 шагов',   'Пройдите суммарно 10 000 валидированных шагов.',          'badge_steps_10k',      'steps_total',         10000,  100, NULL,            1),
    ('co2_saver_5kg',      'Минус 5 кг CO₂',        'Сэкономьте 5 000 граммов выбросов CO₂ пешими маршрутами.', 'badge_co2_5kg',        'co2_grams_total',     5000,   250, NULL,            2),
    ('streak_7_days',      'Неделя в ритме',        'Поддерживайте ежедневную серию активности 7 дней подряд.', 'badge_streak_7d',      'streak_days',         7,      200, 'firefly_aura',  3),
    ('rso_scout_5',        'Разведчик РСО',         'Отправьте 5 отчётов об актуальности пунктов вторсырья.',   'badge_rso_scout',      'rso_reports',         5,      150, NULL,            4),
    ('forest_guardian_10k','Хранитель Общего леса', 'Внесите 10 кг CO₂ в кооперативный челлендж «Общий лес».',  'badge_forest_guard',   'forest_contribution', 10000,  300, 'moss_crown',    5)
ON CONFLICT (code) DO NOTHING;

-- 13.4 Fictional Shop Partners & Starter Items
INSERT INTO shop_partners (
    id, slug, name, category_name, logo_asset_key, description
) VALUES
    ('01950000-0000-7000-8000-000000000001', 'zelenaya-chashka', 'Кофейня «Зелёная Чашка»', 'Еда и напитки', 'partner_green_cup', 'Вымышленная сеть городских эко-кофеен со скидкой за напитки в свою термокружку.'),
    ('01950000-0000-7000-8000-000000000002', 'ekodom-market',    'Маркет «ЭкоДом Плюс»',    'Товары для дома', 'partner_ecodom',   'Демонстрационный магазин многоразовых аксессуаров и бытовой эко-химии на разлив.'),
    ('01950000-0000-7000-8000-000000000003', 'velosamokat-go',   'Прокат «ВелоПоток»',      'Микромобильность', 'partner_veloflow', 'Вымышленный сервис городского велошеринга и аренды механических велосипедов.')
ON CONFLICT (slug) DO NOTHING;

INSERT INTO shop_items (
    id, partner_id, sku, item_type, title, subtitle, description, price_points, stock_quantity, max_per_user_per_day, accessory_code, image_asset_key, sort_order
) VALUES
    (
        '01950000-0000-7000-8000-000000000101',
        NULL,
        'VIRT-STREAK-FREEZE',
        'virtual_streak_freeze',
        'Заморозка серии (1 день)',
        'Защита ударного режима при пропуске дня',
        'Автоматически сохраняет вашу серию (streak), если вы пропустили один день активности.',
        300,
        NULL,
        2,
        NULL,
        'shop_streak_freeze',
        1
    ),
    (
        '01950000-0000-7000-8000-000000000102',
        NULL,
        'VIRT-FOREST-DONATION',
        'virtual_eco_donation',
        'Эко-вклад: Посадка саженца',
        '+2 000 г CO₂ в недельный «Общий лес»',
        'Виртуальный вклад баллов в озеленение и пополнение прогресса кооперативного челленджа.',
        500,
        NULL,
        5,
        NULL,
        'shop_tree_seedling',
        2
    ),
    (
        '01950000-0000-7000-8000-000000000103',
        NULL,
        'MASCOT-SCARF-GREEN',
        'mascot_accessory',
        'Вязаный эко-шарф для зверька',
        'Векторный аксессуар на главный экран',
        'Открывает тёплый зелёный шарф для вашего маскота на главном экране.',
        450,
        NULL,
        1,
        'knit_green_scarf',
        'shop_mascot_scarf',
        3
    ),
    (
        '01950000-0000-7000-8000-000000000104',
        NULL,
        'MASCOT-SOLAR-SHADES',
        'mascot_accessory',
        'Солнечные очки для зверька',
        'Векторный аксессуар на главный экран',
        'Стильные очки для вашего маскота.',
        600,
        NULL,
        1,
        'solar_shades',
        'shop_mascot_shades',
        4
    ),
    (
        '01950000-0000-7000-8000-000000000105',
        '01950000-0000-7000-8000-000000000001',
        'DEMO-COFFEE-30',
        'partner_qr',
        'Скидка 30% на кофе в свою кружку',
        'Кофейня «Зелёная Чашка» (демо)',
        'Демонстрационный QR-купон на скидку 30% при заказе любого напитка в многоразовую кружку.',
        250,
        500,
        2,
        NULL,
        'shop_green_cup_qr',
        5
    ),
    (
        '01950000-0000-7000-8000-000000000106',
        '01950000-0000-7000-8000-000000000002',
        'DEMO-ECODOM-200',
        'partner_coupon',
        'Промокод 200 ₽ на эко-товары',
        'Маркет «ЭкоДом Плюс» (демо)',
        'Демонстрационный промокод на покупку многоразовых мешочков и средств на разлив.',
        400,
        300,
        2,
        NULL,
        'shop_ecodom_promo',
        6
    ),
    (
        '01950000-0000-7000-8000-000000000107',
        '01950000-0000-7000-8000-000000000003',
        'DEMO-VELO-30MIN',
        'partner_coupon',
        '30 минут бесплатной велопоездки',
        'Прокат «ВелоПоток» (демо)',
        'Демонстрационный промокод на 30 минут поездки на городском велосипеде.',
        350,
        400,
        2,
        NULL,
        'shop_veloflow_promo',
        7
    )
ON CONFLICT (sku) DO NOTHING;

COMMIT;
