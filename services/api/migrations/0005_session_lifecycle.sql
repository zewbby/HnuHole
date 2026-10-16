-- +goose Up
-- +goose StatementBegin
-- Versioned session lifecycle promoted from the isolated historical source.
-- Existing demonstration sessions cannot be promoted into the new auth domain.
ALTER TABLE c_auth.sessions
    ADD COLUMN revocation_reason text
        CHECK (revocation_reason IN ('REPLACED', 'LOGOUT', 'RECOVERY', 'CLOSURE', 'EXPIRED')),
    ADD CONSTRAINT session_revocation_reason_shape CHECK
        ((revoked_at IS NULL AND revocation_reason IS NULL) OR
         (revoked_at IS NOT NULL));

CREATE TABLE c_auth.account_restrictions (
    account_id uuid PRIMARY KEY REFERENCES c_auth.accounts (account_id),
    ban_state text NOT NULL DEFAULT 'NONE' CHECK (ban_state IN ('NONE', 'BANNED')),
    ban_ends_at timestamptz,
    version bigint NOT NULL DEFAULT 1 CHECK (version > 0),
    CHECK (ban_state = 'BANNED' OR ban_ends_at IS NULL)
);

INSERT INTO c_auth.account_restrictions(account_id)
    SELECT account_id FROM c_auth.accounts;

CREATE FUNCTION c_auth.create_account_restrictions() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO c_auth.account_restrictions(account_id) VALUES (NEW.account_id);
    RETURN NULL;
END
$$;
CREATE TRIGGER account_restrictions_on_insert
    AFTER INSERT ON c_auth.accounts FOR EACH ROW
    EXECUTE FUNCTION c_auth.create_account_restrictions();

CREATE FUNCTION c_auth.guard_account_restrictions() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.account_id IS DISTINCT FROM OLD.account_id
       OR NEW.version < OLD.version
       OR ((NEW.ban_state, NEW.ban_ends_at) IS DISTINCT FROM (OLD.ban_state, OLD.ban_ends_at)
           AND NEW.version <= OLD.version) THEN
        RAISE EXCEPTION 'restriction identity and version are monotonic' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END
$$;
CREATE TRIGGER account_restrictions_monotonic
    BEFORE UPDATE ON c_auth.account_restrictions FOR EACH ROW
    EXECUTE FUNCTION c_auth.guard_account_restrictions();

CREATE TABLE c_auth.recent_device_replacement (
    account_id uuid PRIMARY KEY REFERENCES c_auth.accounts (account_id),
    installation_id bytea NOT NULL CHECK (octet_length(installation_id) = 16),
    signed_in_at timestamptz NOT NULL,
    replaced_at timestamptz NOT NULL CHECK (replaced_at >= signed_in_at)
);

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
DO $$ BEGIN RAISE EXCEPTION 'Authentication facts require freeze and forward repair; Down is forbidden'; END $$;
-- +goose StatementEnd
