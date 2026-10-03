-- +goose Up
-- +goose StatementBegin
-- Versioned V core facts, promoted from the historical laboratory source.
-- Goose executes Up through the controlled migration owner, separately from C.
-- Later migrations in this same sequence add real OTP and continuations.

CREATE SCHEMA v_auth;

CREATE TABLE v_auth.used_slots (
    slot_id bytea PRIMARY KEY CHECK (octet_length(slot_id) = 32),
    state text NOT NULL DEFAULT 'RESERVED' CHECK (state IN ('RESERVED', 'RETIRED', 'RELEASED')),
    version bigint NOT NULL DEFAULT 1 CHECK (version >= 0),
    UNIQUE (slot_id, state),
    UNIQUE (slot_id, state, version)
);

CREATE TABLE v_auth.email_quota (
    email_exact bytea PRIMARY KEY CHECK (octet_length(email_exact) BETWEEN 3 AND 254),
    current_slot bytea NOT NULL UNIQUE CHECK (octet_length(current_slot) = 32),
    bootstrap_public_key bytea NOT NULL CHECK (octet_length(bootstrap_public_key) = 32),
    quota_version bigint NOT NULL DEFAULT 1 CHECK (quota_version >= 0),
    slot_state text GENERATED ALWAYS AS ('RESERVED'::text) STORED,
    UNIQUE (email_exact, current_slot, quota_version),
    FOREIGN KEY (current_slot, slot_state) REFERENCES v_auth.used_slots (slot_id, state)
        DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE v_auth.retire_pending (
    old_slot bytea PRIMARY KEY CHECK (octet_length(old_slot) = 32),
    email_exact bytea NOT NULL UNIQUE,
    quota_version bigint NOT NULL CHECK (quota_version >= 0),
    new_slot bytea NOT NULL CHECK (octet_length(new_slot) = 32 AND new_slot <> old_slot),
    new_bootstrap_public_key bytea NOT NULL CHECK (octet_length(new_bootstrap_public_key) = 32),
    retirement_authorization bytea NOT NULL CHECK (
        octet_length(retirement_authorization) = 123
        AND substring(retirement_authorization FROM 1 FOR 23)
            = convert_to('HNUHOLE/RETIRE-AUTH/V1', 'UTF8') || decode('00', 'hex')
        AND substring(retirement_authorization FROM 28 FOR 32) = old_slot
    ),
    state text NOT NULL DEFAULT 'PENDING' CHECK (state = 'PENDING'),
    FOREIGN KEY (email_exact, old_slot, quota_version)
        REFERENCES v_auth.email_quota (email_exact, current_slot, quota_version)
        DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE v_auth.processed_receipts (
    slot_id bytea PRIMARY KEY CHECK (octet_length(slot_id) = 32),
    purpose text NOT NULL CHECK (purpose IN ('RETIRED', 'RELEASED')),
    version bigint NOT NULL CHECK (version >= 0),
    FOREIGN KEY (slot_id, purpose, version) REFERENCES v_auth.used_slots (slot_id, state, version)
        DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE v_auth.request_results (
    operation text COLLATE "C" NOT NULL CHECK (operation ~ '^[A-Z][A-Z0-9_]{0,63}$'),
    key_digest bytea NOT NULL UNIQUE CHECK (octet_length(key_digest) = 32),
    state text NOT NULL CHECK (state IN ('LIVE', 'EXPIRED')),
    request_hmac bytea,
    hmac_key_version bigint,
    installation_id bytea,
    flow_id bytea,
    result_code text COLLATE "C",
    expires_at timestamptz,
    PRIMARY KEY (operation, key_digest),
    CONSTRAINT request_results_shape CHECK (
        (state = 'LIVE' AND request_hmac IS NOT NULL AND octet_length(request_hmac) = 32
         AND hmac_key_version IS NOT NULL AND hmac_key_version >= 0
         AND (installation_id IS NULL OR octet_length(installation_id) = 16)
         AND (flow_id IS NULL OR octet_length(flow_id) = 32)
         AND result_code IS NOT NULL AND result_code ~ '^[A-Z][A-Z0-9_]{0,63}$'
         AND expires_at IS NOT NULL)
        OR
        (state = 'EXPIRED' AND request_hmac IS NULL AND hmac_key_version IS NULL
         AND installation_id IS NULL AND flow_id IS NULL AND result_code IS NULL AND expires_at IS NULL)
    )
);

CREATE FUNCTION v_auth.guard_used_slot() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'used slot anchors cannot be deleted' USING ERRCODE = '23514';
    END IF;
    IF NEW.slot_id IS DISTINCT FROM OLD.slot_id OR NEW.version < OLD.version
       OR (OLD.state <> 'RESERVED' AND (NEW.state IS DISTINCT FROM OLD.state OR NEW.version <> OLD.version)) THEN
        RAISE EXCEPTION 'used slot identity, version, and terminal state are monotonic' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END
$$;

CREATE TRIGGER used_slot_monotonic
    BEFORE UPDATE OR DELETE ON v_auth.used_slots FOR EACH ROW EXECUTE FUNCTION v_auth.guard_used_slot();

CREATE FUNCTION v_auth.guard_quota() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    -- Generated slot_state is populated after BEFORE triggers. Compare only
    -- the actual binding columns, so an exact no-op UPDATE stays idempotent.
    IF ROW(NEW.email_exact, NEW.current_slot, NEW.bootstrap_public_key, NEW.quota_version)
       IS DISTINCT FROM ROW(OLD.email_exact, OLD.current_slot, OLD.bootstrap_public_key, OLD.quota_version) THEN
        RAISE EXCEPTION 'quota bindings are immutable until receipt processing deletes them' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END
$$;

CREATE TRIGGER email_quota_immutable
    BEFORE UPDATE ON v_auth.email_quota FOR EACH ROW EXECUTE FUNCTION v_auth.guard_quota();

CREATE FUNCTION v_auth.guard_retire_pending() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW IS DISTINCT FROM OLD THEN
        RAISE EXCEPTION 'retirement pending binding is immutable' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END
$$;

CREATE TRIGGER retire_pending_immutable
    BEFORE UPDATE ON v_auth.retire_pending FOR EACH ROW EXECUTE FUNCTION v_auth.guard_retire_pending();

CREATE FUNCTION v_auth.guard_processed_receipt() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'DELETE' OR NEW IS DISTINCT FROM OLD THEN
        RAISE EXCEPTION 'processed receipt anchors are immutable and cannot be deleted' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END
$$;

CREATE TRIGGER processed_receipt_immutable
    BEFORE UPDATE OR DELETE ON v_auth.processed_receipts FOR EACH ROW EXECUTE FUNCTION v_auth.guard_processed_receipt();

CREATE FUNCTION v_auth.guard_request_result() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'request result anchors cannot be deleted' USING ERRCODE = '23514';
    END IF;
    IF NEW.operation IS DISTINCT FROM OLD.operation OR NEW.key_digest IS DISTINCT FROM OLD.key_digest
       OR (OLD.state = 'EXPIRED' AND NEW IS DISTINCT FROM OLD)
       OR (NEW.state = 'LIVE' AND ROW(NEW.request_hmac, NEW.hmac_key_version, NEW.installation_id,
              NEW.flow_id, NEW.expires_at)
           IS DISTINCT FROM ROW(OLD.request_hmac, OLD.hmac_key_version, OLD.installation_id,
              OLD.flow_id, OLD.expires_at)) THEN
        RAISE EXCEPTION 'request result identity and binding are immutable; expired anchors cannot revive' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END
$$;

CREATE TRIGGER request_result_monotonic
    BEFORE UPDATE OR DELETE ON v_auth.request_results FOR EACH ROW EXECUTE FUNCTION v_auth.guard_request_result();

CREATE FUNCTION v_auth.check_slot_quota_receipt() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE selected_slot bytea; slot_state text; processed_purpose text; quota_exists boolean;
BEGIN
    IF TG_TABLE_NAME = 'email_quota' THEN
        selected_slot := CASE WHEN TG_OP = 'DELETE' THEN OLD.current_slot ELSE NEW.current_slot END;
    ELSE
        selected_slot := CASE WHEN TG_OP = 'DELETE' THEN OLD.slot_id ELSE NEW.slot_id END;
    END IF;
    SELECT state INTO slot_state FROM v_auth.used_slots WHERE slot_id = selected_slot;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'quota and processed receipts require a permanent used slot' USING ERRCODE = '23514';
    END IF;
    SELECT EXISTS (SELECT 1 FROM v_auth.email_quota WHERE current_slot = selected_slot) INTO quota_exists;
    SELECT purpose INTO processed_purpose FROM v_auth.processed_receipts WHERE slot_id = selected_slot;
    IF slot_state = 'RESERVED' THEN
        IF NOT quota_exists OR processed_purpose IS NOT NULL THEN
            RAISE EXCEPTION 'reserved slot requires one current quota and no processed receipt' USING ERRCODE = '23514';
        END IF;
    ELSIF quota_exists OR processed_purpose IS DISTINCT FROM slot_state THEN
        RAISE EXCEPTION 'terminal slot requires durable matching receipt and no current quota' USING ERRCODE = '23514';
    END IF;
    RETURN NULL;
END
$$;

CREATE CONSTRAINT TRIGGER used_slot_quota_receipt_consistency
    AFTER INSERT OR UPDATE ON v_auth.used_slots DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION v_auth.check_slot_quota_receipt();
CREATE CONSTRAINT TRIGGER quota_slot_receipt_consistency
    AFTER INSERT OR UPDATE OR DELETE ON v_auth.email_quota DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION v_auth.check_slot_quota_receipt();
CREATE CONSTRAINT TRIGGER processed_slot_quota_consistency
    AFTER INSERT OR UPDATE OR DELETE ON v_auth.processed_receipts DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION v_auth.check_slot_quota_receipt();

COMMENT ON SCHEMA v_auth IS 'Isolated authentication validation subset; synthetic eligibility only, no OTP or external signing/deployment.';

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
DO $$ BEGIN RAISE EXCEPTION 'Authentication facts require freeze and forward repair; Down is forbidden'; END $$;
-- +goose StatementEnd
