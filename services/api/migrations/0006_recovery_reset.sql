-- +goose Up
-- +goose StatementBegin
-- Isolated recovery-code reset slice. Passkey binding/verification is a later
-- slice; this minimal table makes reset/closure revocation cover every stored
-- optional credential rather than silently leaving one behind.
ALTER TABLE c_auth.accounts
    ADD COLUMN reset_generation bigint NOT NULL DEFAULT 0 CHECK (reset_generation >= 0),
    ADD COLUMN active_reset_intent_id bytea CHECK (active_reset_intent_id IS NULL OR octet_length(active_reset_intent_id) = 32);

CREATE TABLE c_auth.reset_intents (
    intent_id bytea PRIMARY KEY CHECK (octet_length(intent_id) = 32),
    account_id uuid NOT NULL REFERENCES c_auth.accounts(account_id),
    credential_version bigint NOT NULL CHECK (credential_version >= 1),
    reset_generation bigint NOT NULL CHECK (reset_generation >= 1),
    authorization_generation bigint NOT NULL CHECK (authorization_generation >= 1),
    state text NOT NULL CHECK (state IN ('ACTIVE','ABANDONED','CONSUMED','EXPIRED')),
    new_recovery_digest bytea,
    created_at timestamptz NOT NULL,
    expires_at timestamptz NOT NULL,
    terminal_at timestamptz,
    UNIQUE(account_id,intent_id),
    CHECK (expires_at > created_at AND expires_at <= created_at + interval '10 minutes'),
    CHECK ((state='ACTIVE' AND new_recovery_digest IS NOT NULL AND octet_length(new_recovery_digest)=32 AND terminal_at IS NULL)
        OR (state<>'ACTIVE' AND new_recovery_digest IS NULL AND terminal_at IS NOT NULL AND terminal_at >= created_at))
);
CREATE UNIQUE INDEX reset_intents_one_active_per_account
    ON c_auth.reset_intents(account_id) WHERE state='ACTIVE';
ALTER TABLE c_auth.accounts ADD CONSTRAINT accounts_active_reset_ownership
    FOREIGN KEY(account_id,active_reset_intent_id) REFERENCES c_auth.reset_intents(account_id,intent_id)
    DEFERRABLE INITIALLY DEFERRED;

CREATE TABLE c_auth.passkeys (
    credential_id bytea PRIMARY KEY CHECK (octet_length(credential_id) BETWEEN 1 AND 1023),
    account_id uuid NOT NULL REFERENCES c_auth.accounts(account_id),
    public_key bytea NOT NULL CHECK (octet_length(public_key) BETWEEN 1 AND 4096),
    created_at timestamptz NOT NULL
);
COMMENT ON TABLE c_auth.passkeys IS 'Isolated revocation storage only; no Passkey registration or WebAuthn authorization is implemented by this migration.';

CREATE TABLE c_auth.security_events (
    event_id uuid PRIMARY KEY,
    account_id uuid NOT NULL REFERENCES c_auth.accounts(account_id),
    action text NOT NULL CHECK (action IN ('PASSWORD_RESET')),
    credential_version bigint NOT NULL CHECK (credential_version >= 1),
    session_generation bigint NOT NULL CHECK (session_generation >= 1),
    recorded_at timestamptz NOT NULL
);

ALTER TABLE c_auth.request_results ADD COLUMN reset_intent_id bytea
    REFERENCES c_auth.reset_intents(intent_id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE c_auth.request_results ADD CONSTRAINT request_results_reset_shape CHECK (
    (state='EXPIRED' AND reset_intent_id IS NULL)
    OR (state='LIVE' AND ((operation='PASSWORD_RESET' AND reset_intent_id IS NOT NULL AND intent_id IS NULL)
        OR (operation<>'PASSWORD_RESET' AND reset_intent_id IS NULL)))
);

CREATE OR REPLACE FUNCTION c_auth.guard_request_result() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP='DELETE' THEN
        RAISE EXCEPTION 'request result anchors cannot be deleted' USING ERRCODE='23514';
    END IF;
    IF NEW.operation IS DISTINCT FROM OLD.operation OR NEW.key_digest IS DISTINCT FROM OLD.key_digest
       OR (OLD.state='EXPIRED' AND NEW IS DISTINCT FROM OLD)
       OR (NEW.state='LIVE' AND ROW(NEW.request_hmac,NEW.hmac_key_version,NEW.intent_id,NEW.reset_intent_id,NEW.expires_at)
           IS DISTINCT FROM ROW(OLD.request_hmac,OLD.hmac_key_version,OLD.intent_id,OLD.reset_intent_id,OLD.expires_at)) THEN
        RAISE EXCEPTION 'request result identity and binding are immutable; expired anchors cannot revive' USING ERRCODE='23514';
    END IF;
    RETURN NEW;
END
$$;

CREATE FUNCTION c_auth.guard_reset_intent() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.intent_id IS DISTINCT FROM OLD.intent_id OR NEW.account_id IS DISTINCT FROM OLD.account_id
       OR NEW.credential_version IS DISTINCT FROM OLD.credential_version
       OR NEW.reset_generation IS DISTINCT FROM OLD.reset_generation
       OR NEW.authorization_generation IS DISTINCT FROM OLD.authorization_generation
       OR NEW.created_at IS DISTINCT FROM OLD.created_at OR NEW.expires_at IS DISTINCT FROM OLD.expires_at
       OR (OLD.state<>'ACTIVE' AND NEW IS DISTINCT FROM OLD)
       OR (NEW.state='ACTIVE' AND NEW.new_recovery_digest IS DISTINCT FROM OLD.new_recovery_digest) THEN
        RAISE EXCEPTION 'reset intent identity, lifetime, proof binding and terminal state are immutable' USING ERRCODE='23514';
    END IF;
    RETURN NEW;
END
$$;
CREATE TRIGGER reset_intent_immutable BEFORE UPDATE ON c_auth.reset_intents
    FOR EACH ROW EXECUTE FUNCTION c_auth.guard_reset_intent();
CREATE FUNCTION c_auth.guard_reset_generation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.reset_generation < OLD.reset_generation THEN
        RAISE EXCEPTION 'reset generation cannot move backwards' USING ERRCODE='23514';
    END IF;
    RETURN NEW;
END
$$;
CREATE TRIGGER account_reset_generation_monotonic BEFORE UPDATE ON c_auth.accounts
    FOR EACH ROW EXECUTE FUNCTION c_auth.guard_reset_generation();

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
DO $$ BEGIN RAISE EXCEPTION 'Authentication facts require freeze and forward repair; Down is forbidden'; END $$;
-- +goose StatementEnd
