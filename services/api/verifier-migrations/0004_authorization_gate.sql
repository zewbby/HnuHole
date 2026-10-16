-- +goose Up
-- +goose StatementBegin
-- V owns its authorization state, generation, evidence and external anchor.
-- The snapshot's OPEN row alone is never evidence that restoration is safe.
CREATE TABLE v_auth.authorization_gate (
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
    CHECK ((gate_state = 'OPEN' AND authorization_generation > 0 AND evidence_version > 0
            AND evidence_issued_at IS NOT NULL AND evidence_valid_until > evidence_issued_at
            AND freeze_reason IS NULL)
        OR (gate_state = 'FROZEN' AND freeze_reason IS NOT NULL AND frozen_at IS NOT NULL))
);
INSERT INTO v_auth.authorization_gate
    (singleton_id,gate_state,authorization_generation,trusted_high_watermark,
     evidence_version,freeze_reason,frozen_at)
VALUES (1,'FROZEN',0,'epoch'::timestamptz,0,'BOOTSTRAP',clock_timestamp());

CREATE TABLE v_auth.authorization_gate_audit (
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

CREATE FUNCTION v_auth.guard_authorization_gate() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.singleton_id <> OLD.singleton_id
       OR NEW.authorization_generation < OLD.authorization_generation
       OR NEW.trusted_high_watermark < OLD.trusted_high_watermark
       OR NEW.evidence_version < OLD.evidence_version
       OR (OLD.gate_state = 'FROZEN' AND NEW.gate_state = 'OPEN'
           AND NEW.authorization_generation <= OLD.authorization_generation)
       OR (OLD.gate_state = 'OPEN' AND NEW.gate_state = 'OPEN'
           AND NEW.authorization_generation <> OLD.authorization_generation) THEN
        RAISE EXCEPTION 'verifier authorization gate cannot roll back' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END
$$;
CREATE TRIGGER authorization_gate_monotonic
    BEFORE UPDATE ON v_auth.authorization_gate
    FOR EACH ROW EXECUTE FUNCTION v_auth.guard_authorization_gate();

-- Existing work retains generation zero. It may be reconciled as historical
-- data but cannot issue qualification, sign, send mail or resume retirement.
-- A recovery must never rewrite those bindings to the new generation.
ALTER TABLE v_auth.otp_flows
    ADD COLUMN authorization_generation bigint NOT NULL DEFAULT 0 CHECK (authorization_generation >= 0);
ALTER TABLE v_auth.otp_confirmations
    ADD COLUMN authorization_generation bigint NOT NULL DEFAULT 0 CHECK (authorization_generation >= 0);
ALTER TABLE v_auth.confirmation_sign_jobs
    ADD COLUMN authorization_generation bigint NOT NULL DEFAULT 0 CHECK (authorization_generation >= 0);
ALTER TABLE v_auth.mail_outbox
    ADD COLUMN authorization_generation bigint NOT NULL DEFAULT 0 CHECK (authorization_generation >= 0);
ALTER TABLE v_auth.retire_pending
    ADD COLUMN authorization_generation bigint NOT NULL DEFAULT 0 CHECK (authorization_generation >= 0);

CREATE FUNCTION v_auth.guard_authorization_generation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.authorization_generation IS DISTINCT FROM OLD.authorization_generation THEN
        RAISE EXCEPTION 'verifier pending authorization generation is immutable' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END
$$;
CREATE TRIGGER otp_flow_authorization_generation_immutable
    BEFORE UPDATE ON v_auth.otp_flows FOR EACH ROW
    EXECUTE FUNCTION v_auth.guard_authorization_generation();
CREATE TRIGGER otp_confirmation_authorization_generation_immutable
    BEFORE UPDATE ON v_auth.otp_confirmations FOR EACH ROW
    EXECUTE FUNCTION v_auth.guard_authorization_generation();
CREATE TRIGGER confirmation_sign_authorization_generation_immutable
    BEFORE UPDATE ON v_auth.confirmation_sign_jobs FOR EACH ROW
    EXECUTE FUNCTION v_auth.guard_authorization_generation();
CREATE TRIGGER mail_authorization_generation_immutable
    BEFORE UPDATE ON v_auth.mail_outbox FOR EACH ROW
    EXECUTE FUNCTION v_auth.guard_authorization_generation();
CREATE TRIGGER retirement_authorization_generation_immutable
    BEFORE UPDATE ON v_auth.retire_pending FOR EACH ROW
    EXECUTE FUNCTION v_auth.guard_authorization_generation();

COMMENT ON SCHEMA v_auth IS 'Verifier eligibility facts with an independent authorization gate; development file evidence does not prove production trust';
-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
DO $$ BEGIN RAISE EXCEPTION 'Authentication facts require freeze and forward repair; Down is forbidden'; END $$;
-- +goose StatementEnd
