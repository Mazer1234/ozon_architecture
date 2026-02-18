CREATE EXTENSION IF NOT EXISTS timescaledb;

CREATE TABLE IF NOT EXISTS telemetry_events (
    ts TIMESTAMPZ NOT NULL DEFAULT now(),
    controller_id TEXT NOT NULL,
    city TEXT NOT NULL,
    value DOUBLE PRECISION NOT NULL,
    raw JSONB NOT NULL
);

SELECT create_hypertable('telemetry_events', 'ts', if_not_exists => TRUE);
CREATE INDEX IF NOT EXISTS telemetry_events_controller_ts_idx
    ON telemetry_events (controller_id, ts DESC);