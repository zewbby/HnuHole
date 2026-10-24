-- +goose Up
CREATE SCHEMA c_rate_limit;
REVOKE ALL ON SCHEMA c_rate_limit FROM PUBLIC;

CREATE TABLE c_rate_limit.namespace (
    singleton_id smallint PRIMARY KEY CHECK(singleton_id=1),
    policy_hash text NOT NULL CHECK(policy_hash ~ '^[0-9a-f]{64}$'),
    recovery_window_ms bigint NOT NULL CHECK(recovery_window_ms BETWEEN 1 AND 86400000),
    generation bigint NOT NULL CHECK(generation>0),
    run_id text NOT NULL CHECK(run_id ~ '^[0-9a-f]{40}$'),
    state text NOT NULL CHECK(state IN ('READY','RECOVERING')),
    dirty_until timestamptz,
    barrier_until timestamptz NOT NULL
);
REVOKE ALL ON c_rate_limit.namespace FROM PUBLIC;

CREATE TABLE c_rate_limit.admissions (
    account_id uuid NOT NULL REFERENCES c_auth.accounts(account_id),
    business_kind text NOT NULL CHECK(business_kind IN ('post','comment','dm-text','dm-image')),
    key_digest bytea NOT NULL CHECK(octet_length(key_digest)=32),
    fingerprint bytea NOT NULL CHECK(octet_length(fingerprint)=32),
    nonce bytea NOT NULL CHECK(octet_length(nonce)=16),
    operation text NOT NULL CHECK(length(operation)<=32),
    dm_command_id uuid,
    attempt integer NOT NULL DEFAULT 0 CHECK(attempt BETWEEN 0 AND 1000),
    actions jsonb NOT NULL CHECK(jsonb_typeof(actions)='array' AND jsonb_array_length(actions) BETWEEN 1 AND 4),
    state text NOT NULL CHECK(state IN ('PREPARED','ADMITTED')),
    generation bigint NOT NULL CHECK(generation>0),
    incarnation text,
    created_at timestamptz NOT NULL,
    deadline timestamptz NOT NULL,
    confirmed_at timestamptz,
    PRIMARY KEY(account_id,business_kind,key_digest),
    CHECK(deadline>created_at AND deadline<=created_at+interval '24 hours'),
    CHECK((state='PREPARED' AND confirmed_at IS NULL) OR
          (state='ADMITTED' AND generation>0 AND incarnation IS NOT NULL AND incarnation ~ '^[0-9a-f]{32}$' AND confirmed_at IS NOT NULL))
);
CREATE INDEX admission_deadline ON c_rate_limit.admissions(deadline,account_id);
REVOKE ALL ON c_rate_limit.admissions FROM PUBLIC;

-- A hidden unknown command needs a permanent account-local terminal anchor.
-- Its original receipt is retained; no body or peer identity is added here.
ALTER TABLE c_dm.commands ADD COLUMN closed_at timestamptz;
CREATE INDEX dm_command_close_budget ON c_dm.commands(owner_account,closed_at) WHERE closed_at IS NOT NULL;

-- +goose Down
-- +goose StatementBegin
DO $$ BEGIN
    RAISE EXCEPTION '0027 preserves admission recovery facts; freeze and repair forward';
END $$;
-- +goose StatementEnd
