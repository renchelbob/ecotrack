DO $$
DECLARE
    v_tables INT;
    v_enums INT;
    v_triggers INT;
    v_indexes INT;
    v_modes INT;
    v_accessories INT;
    v_badges INT;
    v_partners INT;
    v_items INT;
    v_uuid UUID;
    v_point_id UUID;
    v_bbox_hits INT;
    v_trust NUMERIC(5, 2);
    v_status waste_point_status;
    v_caught BOOLEAN;
    v_uid UUID;
    v_ledger_id UUID;
    v_balance INT;
    v_earned INT;
    v_cnt INT;
BEGIN
    SELECT COUNT(*) INTO v_tables
    FROM information_schema.tables
    WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
      AND table_name IN (
          'mascot_accessories', 'users', 'user_oauth_identities', 'auth_refresh_sessions',
          'fz152_consent_journal', 'fz152_account_deletion_log', 'user_push_tokens',
          'transport_emission_catalog', 'user_vehicles', 'daily_step_summaries',
          'gps_daily_tracks', 'gps_track_points', 'route_segment_allocations',
          'point_ledger', 'shop_partners', 'shop_items', 'shop_orders', 'shop_order_items',
          'user_mascot_inventory', 'badges_catalog', 'user_badges', 'friendships',
          'friend_wakeup_nudges', 'shared_forest_challenges', 'shared_forest_contributions',
          'rso_source_records', 'waste_points', 'point_source_links', 'point_reports'
      );
    IF v_tables <> 29 THEN
        RAISE EXCEPTION 'Expected 29 EcoTrack tables, got %', v_tables;
    END IF;

    SELECT COUNT(*) INTO v_enums
    FROM pg_type t
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'public' AND t.typtype = 'e'
      AND t.typname IN (
          'oauth_provider_type', 'consent_action_type', 'fuel_type', 'transport_mode_code',
          'track_point_motion_class', 'ledger_operation_type', 'shop_item_type', 'order_status',
          'friendship_status', 'waste_fraction_code', 'rso_source_type', 'waste_point_status',
          'report_type', 'push_platform_type'
      );
    IF v_enums <> 14 THEN
        RAISE EXCEPTION 'Expected 14 ENUM types, got %', v_enums;
    END IF;

    SELECT COUNT(*) INTO v_triggers
    FROM pg_trigger
    WHERE NOT tgisinternal
      AND tgname IN (
          'trg_point_ledger_immutable',
          'trg_point_ledger_sync_balance',
          'trg_point_reports_apply_trust'
      );
    IF v_triggers <> 3 THEN
        RAISE EXCEPTION 'Expected 3 domain triggers, got %', v_triggers;
    END IF;

    SELECT COUNT(*) INTO v_indexes
    FROM pg_indexes
    WHERE schemaname = 'public'
      AND indexname IN (
          'idx_gps_daily_tracks_geom_gist',
          'idx_gps_track_points_geom_gist',
          'idx_route_segment_allocations_geom_gist',
          'idx_rso_source_records_geom_gist',
          'idx_rso_source_records_tags_gin',
          'idx_waste_points_geom_gist',
          'idx_waste_points_geog_gist',
          'idx_waste_points_fractions_gin'
      );
    IF v_indexes <> 8 THEN
        RAISE EXCEPTION 'Expected 8 spatial/GIN indexes, got %', v_indexes;
    END IF;

    SELECT COUNT(*) INTO v_modes FROM transport_emission_catalog;
    SELECT COUNT(*) INTO v_accessories FROM mascot_accessories;
    SELECT COUNT(*) INTO v_badges FROM badges_catalog;
    SELECT COUNT(*) INTO v_partners FROM shop_partners;
    SELECT COUNT(*) INTO v_items FROM shop_items;
    IF v_modes <> 8 OR v_accessories <> 5 OR v_badges <> 5 OR v_partners <> 3 OR v_items <> 7 THEN
        RAISE EXCEPTION 'Seed row count mismatch: modes=%, acc=%, badges=%, partners=%, items=%',
            v_modes, v_accessories, v_badges, v_partners, v_items;
    END IF;

    v_uuid := uuid_generate_v7();
    IF v_uuid IS NULL THEN
        RAISE EXCEPTION 'uuid_generate_v7() returned NULL';
    END IF;

    INSERT INTO waste_points (title, accepted_fractions, geom)
    VALUES (
        'CI Smoke RSO',
        ARRAY['plastic', 'glass']::waste_fraction_code[],
        ST_SetSRID(ST_MakePoint(37.6173, 55.7558), 4326)
    )
    RETURNING id INTO v_point_id;

    SELECT COUNT(*) INTO v_bbox_hits
    FROM waste_points
    WHERE id = v_point_id
      AND geog IS NOT NULL
      AND geom && ST_MakeEnvelope(37.50, 55.70, 37.70, 55.80, 4326)
      AND accepted_fractions && ARRAY['plastic']::waste_fraction_code[];
    IF v_bbox_hits <> 1 THEN
        RAISE EXCEPTION 'Spatial BBox lookup failed for inserted waste_point';
    END IF;

    INSERT INTO point_reports (
        waste_point_id, user_id, idempotency_key, report_type,
        user_lat, user_lon, distance_to_point_m, trust_delta
    ) VALUES
        (v_point_id, NULL, uuid_generate_v7(), 'missing_bin', 55.7558, 37.6173, 10.00, -25.00),
        (v_point_id, NULL, uuid_generate_v7(), 'missing_bin', 55.7558, 37.6173, 10.00, -25.00);

    SELECT trust_score, status INTO v_trust, v_status FROM waste_points WHERE id = v_point_id;
    IF v_trust <> 0.00 OR v_status <> 'unverified' THEN
        RAISE EXCEPTION 'PG-INV-09 failed after 2 reports: trust=%, status=%', v_trust, v_status;
    END IF;

    INSERT INTO point_reports (
        waste_point_id, user_id, idempotency_key, report_type,
        user_lat, user_lon, distance_to_point_m, trust_delta
    ) VALUES (
        v_point_id, NULL, uuid_generate_v7(), 'missing_bin', 55.7558, 37.6173, 10.00, -25.00
    );

    SELECT trust_score INTO v_trust FROM waste_points WHERE id = v_point_id;
    IF v_trust <> 0.00 THEN
        RAISE EXCEPTION 'Trust score clamp failed on 3rd report: trust=%', v_trust;
    END IF;

    v_caught := FALSE;
    BEGIN
        INSERT INTO waste_points (title, accepted_fractions, geom)
        VALUES (
            'Invalid Empty Fractions',
            ARRAY[]::waste_fraction_code[],
            ST_SetSRID(ST_MakePoint(37.6173, 55.7558), 4326)
        );
    EXCEPTION WHEN check_violation THEN
        v_caught := TRUE;
    END;
    IF NOT v_caught THEN
        RAISE EXCEPTION 'CHECK constraint failed to reject empty accepted_fractions';
    END IF;

    v_caught := FALSE;
    BEGIN
        INSERT INTO point_reports (
            waste_point_id, user_id, idempotency_key, report_type,
            user_lat, user_lon, distance_to_point_m, trust_delta
        ) VALUES (
            v_point_id, NULL, uuid_generate_v7(), 'confirm_working', 120.0, 37.6173, 5.00, 10.00
        );
    EXCEPTION WHEN check_violation THEN
        v_caught := TRUE;
    END;
    IF NOT v_caught THEN
        RAISE EXCEPTION 'CHECK constraint failed to reject out-of-range user_lat';
    END IF;

    DELETE FROM waste_points WHERE id = v_point_id;

    INSERT INTO users (display_name, friend_code)
    VALUES ('CI Smoke User', 'ECO-TEST-0001')
    RETURNING id INTO v_uid;

    INSERT INTO point_ledger (user_id, idempotency_key, operation_type, points_delta, description)
    VALUES (v_uid, uuid_generate_v7(), 'daily_steps_reward', 100, 'CI smoke credit')
    RETURNING id INTO v_ledger_id;

    SELECT points_balance, lifetime_points_earned INTO v_balance, v_earned
    FROM users
    WHERE id = v_uid;
    IF v_balance <> 100 OR v_earned <> 100 THEN
        RAISE EXCEPTION 'trg_point_ledger_sync_balance failed: balance=%, earned=%', v_balance, v_earned;
    END IF;

    v_caught := FALSE;
    BEGIN
        UPDATE point_ledger SET points_delta = 500 WHERE id = v_ledger_id;
    EXCEPTION WHEN integrity_constraint_violation THEN
        v_caught := TRUE;
    END;
    IF NOT v_caught THEN
        RAISE EXCEPTION 'trg_point_ledger_immutable failed to block UPDATE';
    END IF;

    v_caught := FALSE;
    BEGIN
        DELETE FROM point_ledger WHERE id = v_ledger_id;
    EXCEPTION WHEN integrity_constraint_violation THEN
        v_caught := TRUE;
    END;
    IF NOT v_caught THEN
        RAISE EXCEPTION 'trg_point_ledger_immutable failed to block direct DELETE';
    END IF;

    v_caught := FALSE;
    BEGIN
        INSERT INTO point_ledger (user_id, idempotency_key, operation_type, points_delta, description)
        VALUES (v_uid, uuid_generate_v7(), 'shop_purchase', -150, 'CI smoke overdraft');
    EXCEPTION WHEN check_violation THEN
        v_caught := TRUE;
    END;
    IF NOT v_caught THEN
        RAISE EXCEPTION 'CHECK (points_balance >= 0) failed to reject overdraft';
    END IF;

    PERFORM set_config('ecotrack.in_152fz_account_erasure', 'true', true);
    DELETE FROM users WHERE id = v_uid;

    SELECT COUNT(*) INTO v_cnt FROM point_ledger WHERE user_id = v_uid;
    IF v_cnt <> 0 THEN
        RAISE EXCEPTION '152-FZ cascade deletion left % rows in point_ledger', v_cnt;
    END IF;

    RAISE NOTICE 'POSTGIS_SMOKE_OK';
END $$;
