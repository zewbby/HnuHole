-- +goose Up
CREATE TABLE sessions (
    token_hash bytea PRIMARY KEY,
    account_id uuid NOT NULL,
    expires_at timestamptz NOT NULL,
    revoked_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX sessions_account_id_idx ON sessions (account_id);
CREATE INDEX sessions_active_expiry_idx ON sessions (expires_at)
    WHERE revoked_at IS NULL;

-- +goose Down
DROP TABLE sessions;
