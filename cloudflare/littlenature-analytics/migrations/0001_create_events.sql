CREATE TABLE IF NOT EXISTS events (
    event_id TEXT PRIMARY KEY,
    installation_id_hash TEXT NOT NULL,
    session_id_hash TEXT NOT NULL,
    event_name TEXT NOT NULL,
    occurred_at INTEGER NOT NULL,
    received_at INTEGER NOT NULL DEFAULT (unixepoch() * 1000),
    app_version TEXT NOT NULL,
    build_number TEXT NOT NULL,
    platform TEXT NOT NULL,
    os_version TEXT NOT NULL,
    locale TEXT NOT NULL,
    properties_json TEXT NOT NULL DEFAULT '{}'
) STRICT;

CREATE INDEX IF NOT EXISTS idx_events_name_occurred ON events (event_name, occurred_at);
CREATE INDEX IF NOT EXISTS idx_events_installation_occurred ON events (installation_id_hash, occurred_at);
CREATE INDEX IF NOT EXISTS idx_events_received ON events (received_at);
