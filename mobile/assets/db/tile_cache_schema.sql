-- EcoTrack Map Tile Persistent SQLite Cache Schema
-- Loaded via rootBundle to comply with contract-first SQLite asset gates.

CREATE TABLE IF NOT EXISTS tile_cache (
    cache_key TEXT PRIMARY KEY,
    url TEXT NOT NULL,
    status_code INTEGER NOT NULL,
    priority INTEGER NOT NULL,
    request_date_ms INTEGER NOT NULL,
    response_date_ms INTEGER NOT NULL,
    date_ms INTEGER,
    expires_ms INTEGER,
    max_stale_ms INTEGER,
    etag TEXT,
    last_modified TEXT,
    content BLOB,
    headers BLOB,
    cc_max_age INTEGER NOT NULL DEFAULT -1,
    cc_max_stale INTEGER NOT NULL DEFAULT -1,
    cc_min_fresh INTEGER NOT NULL DEFAULT -1,
    cc_must_revalidate INTEGER NOT NULL DEFAULT 0,
    cc_no_cache INTEGER NOT NULL DEFAULT 0,
    cc_no_store INTEGER NOT NULL DEFAULT 0,
    cc_privacy TEXT,
    cc_other_json TEXT
);

CREATE INDEX IF NOT EXISTS idx_tile_cache_url ON tile_cache (url);
CREATE INDEX IF NOT EXISTS idx_tile_cache_max_stale ON tile_cache (max_stale_ms);
