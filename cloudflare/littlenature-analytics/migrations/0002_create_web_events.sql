CREATE TABLE IF NOT EXISTS web_events (
    event_id TEXT PRIMARY KEY,
    session_id_hash TEXT NOT NULL,
    event_name TEXT NOT NULL,
    occurred_at INTEGER NOT NULL,
    received_at INTEGER NOT NULL DEFAULT (unixepoch() * 1000),
    locale TEXT NOT NULL,
    device_class TEXT NOT NULL,
    properties_json TEXT NOT NULL DEFAULT '{}'
) STRICT;

CREATE INDEX IF NOT EXISTS idx_web_events_name_date ON web_events (event_name, occurred_at);
CREATE INDEX IF NOT EXISTS idx_web_events_session_date ON web_events (session_id_hash, occurred_at);
