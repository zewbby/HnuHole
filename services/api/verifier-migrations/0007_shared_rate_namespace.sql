-- +goose Up
CREATE SCHEMA v_rate_limit;
REVOKE ALL ON SCHEMA v_rate_limit FROM PUBLIC;
CREATE TABLE v_rate_limit.namespace (
    singleton_id smallint PRIMARY KEY CHECK(singleton_id=1),
    policy_hash text NOT NULL CHECK(policy_hash ~ '^[0-9a-f]{64}$'),
    recovery_window_ms bigint NOT NULL CHECK(recovery_window_ms BETWEEN 1 AND 86400000),
    generation bigint NOT NULL CHECK(generation>0),
    run_id text NOT NULL CHECK(run_id ~ '^[0-9a-f]{40}$'),
    state text NOT NULL CHECK(state IN ('READY','RECOVERING')),
    dirty_until timestamptz,
    barrier_until timestamptz NOT NULL
);
REVOKE ALL ON v_rate_limit.namespace FROM PUBLIC;
-- +goose Down
-- +goose StatementBegin
DO $$ BEGIN RAISE EXCEPTION '0007 preserves namespace recovery barriers; repair forward'; END $$;
-- +goose StatementEnd
