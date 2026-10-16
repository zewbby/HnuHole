-- +goose Up
-- +goose StatementBegin
-- Versioned C-only authorization gate. The independent checkpoint is outside
-- PostgreSQL; this row alone cannot establish safety after a snapshot restore.
ALTER TABLE c_auth.signup_intents
    ADD COLUMN authorization_generation bigint NOT NULL DEFAULT 0 CHECK (authorization_generation >= 0);
ALTER TABLE c_auth.sessions
    ADD COLUMN authorization_generation bigint NOT NULL DEFAULT 0 CHECK (authorization_generation >= 0);

CREATE TABLE c_auth.authorization_gate (
    singleton_id integer PRIMARY KEY CHECK (singleton_id = 1),
    gate_state text NOT NULL CHECK (gate_state IN ('OPEN', 'FROZEN')),
    authorization_generation bigint NOT NULL CHECK (authorization_generation >= 0),
    trusted_high_watermark timestamptz NOT NULL,
    evidence_version bigint NOT NULL CHECK (evidence_version >= 0),
    evidence_issued_at timestamptz,
    evidence_valid_until timestamptz,
    freeze_reason text,
    frozen_at timestamptz,
    opened_at timestamptz,
    CHECK ((gate_state = 'OPEN' AND evidence_issued_at IS NOT NULL
            AND evidence_valid_until > evidence_issued_at AND freeze_reason IS NULL)
        OR (gate_state = 'FROZEN' AND freeze_reason IS NOT NULL AND frozen_at IS NOT NULL))
);
INSERT INTO c_auth.authorization_gate
    (singleton_id,gate_state,authorization_generation,trusted_high_watermark,
     evidence_version,freeze_reason,frozen_at)
VALUES (1,'FROZEN',0,'epoch'::timestamptz,0,'BOOTSTRAP',clock_timestamp());

CREATE TABLE c_auth.authorization_gate_audit (
    event_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    event_kind text NOT NULL CHECK (event_kind IN ('FREEZE', 'RECOVER')),
    authorization_generation bigint NOT NULL CHECK (authorization_generation >= 0),
    evidence_version bigint NOT NULL CHECK (evidence_version >= 0),
    actor text NOT NULL,
    reason text NOT NULL,
    operation_id text NOT NULL UNIQUE,
    mode text CHECK (mode IN ('NORMAL', 'BREAK_GLASS')),
    recorded_at timestamptz NOT NULL
);

CREATE FUNCTION c_auth.guard_authorization_gate() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.singleton_id <> OLD.singleton_id
       OR NEW.authorization_generation < OLD.authorization_generation
       OR NEW.trusted_high_watermark < OLD.trusted_high_watermark
       OR NEW.evidence_version < OLD.evidence_version
       OR (OLD.gate_state = 'FROZEN' AND NEW.gate_state = 'OPEN'
           AND NEW.authorization_generation <= OLD.authorization_generation)
       OR (OLD.gate_state = 'OPEN' AND NEW.gate_state = 'OPEN'
           AND NEW.authorization_generation <> OLD.authorization_generation) THEN
        RAISE EXCEPTION 'authorization gate cannot roll back' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END
$$;
CREATE TRIGGER authorization_gate_monotonic
    BEFORE UPDATE ON c_auth.authorization_gate
    FOR EACH ROW EXECUTE FUNCTION c_auth.guard_authorization_gate();

CREATE OR REPLACE FUNCTION c_auth.guard_signup_intent() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.intent_id IS DISTINCT FROM OLD.intent_id
       OR NEW.created_at IS DISTINCT FROM OLD.created_at OR NEW.expires_at IS DISTINCT FROM OLD.expires_at
       OR NEW.authorization_generation IS DISTINCT FROM OLD.authorization_generation
       OR NEW.attempts < OLD.attempts
       OR (OLD.state <> 'OPEN' AND NEW IS DISTINCT FROM OLD) THEN
        RAISE EXCEPTION 'signup intent identity, lifetime, generation, and terminal state are immutable' USING ERRCODE = '23514';
    END IF;
    IF NEW.state = 'OPEN' AND ROW(NEW.challenge, NEW.ticket, NEW.slot_id, NEW.bootstrap_public_key,
        NEW.admission_window, NEW.username, NEW.password_hash, NEW.password_salt,
        NEW.password_params_version, NEW.recovery_digest, NEW.installation_id)
        IS DISTINCT FROM ROW(OLD.challenge, OLD.ticket, OLD.slot_id, OLD.bootstrap_public_key,
        OLD.admission_window, OLD.username, OLD.password_hash, OLD.password_salt,
        OLD.password_params_version, OLD.recovery_digest, OLD.installation_id) THEN
        RAISE EXCEPTION 'signup intent material cannot be substituted' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END
$$;

CREATE FUNCTION c_auth.guard_session_authorization_generation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.authorization_generation IS DISTINCT FROM OLD.authorization_generation THEN
        RAISE EXCEPTION 'session authorization generation is immutable' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END
$$;
CREATE TRIGGER session_authorization_generation_immutable
    BEFORE UPDATE ON c_auth.sessions FOR EACH ROW
    EXECUTE FUNCTION c_auth.guard_session_authorization_generation();

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
DO $$ BEGIN RAISE EXCEPTION 'Authentication facts require freeze and forward repair; Down is forbidden'; END $$;
-- +goose StatementEnd
