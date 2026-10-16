-- +goose Up
-- +goose StatementBegin
-- OTP confirmation and post-commit signing. Run after 0001 and 0002 in the
-- same disposable verifier database. This is not a production migration.

-- Only a budgeted OTP decision that actually creates the original device lock
-- has a replay deadline here. No address, code, flow or installation is copied.
CREATE TABLE v_auth.confirmation_rejections (
    confirmation_key_digest bytea PRIMARY KEY
        REFERENCES v_auth.request_results(key_digest)
        CHECK (octet_length(confirmation_key_digest) = 32),
    retry_until timestamptz NOT NULL
);

CREATE FUNCTION v_auth.guard_confirmation_rejection() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW IS DISTINCT FROM OLD THEN
        RAISE EXCEPTION 'cached original rejection deadline is immutable' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END
$$;

CREATE TRIGGER confirmation_rejection_immutable
    BEFORE UPDATE ON v_auth.confirmation_rejections
    FOR EACH ROW EXECUTE FUNCTION v_auth.guard_confirmation_rejection();

CREATE TABLE v_auth.otp_confirmations (
    confirmation_key_digest bytea PRIMARY KEY
        REFERENCES v_auth.request_results(key_digest) DEFERRABLE INITIALLY DEFERRED
        CHECK (octet_length(confirmation_key_digest) = 32),
    flow_id bytea CHECK (flow_id IS NULL OR octet_length(flow_id) = 32),
    installation_id bytea CHECK (installation_id IS NULL OR octet_length(installation_id) = 16),
    email_exact bytea NOT NULL CHECK (octet_length(email_exact) BETWEEN 3 AND 254),
    new_slot bytea NOT NULL CHECK (octet_length(new_slot) = 32),
    new_bootstrap_public_key bytea NOT NULL CHECK (octet_length(new_bootstrap_public_key) = 32),
    old_slot bytea CHECK (old_slot IS NULL OR octet_length(old_slot) = 32),
    old_quota_version bigint,
    verified_at timestamptz NOT NULL,
    verified_otp_expires_at timestamptz NOT NULL,
    admission_window bigint NOT NULL CHECK (admission_window BETWEEN 0 AND 4294967295),
    signing_key_epoch bigint NOT NULL CHECK (signing_key_epoch BETWEEN 0 AND 4294967295),
    state text NOT NULL CHECK (state IN (
        'RETIREMENT_PENDING', 'CONFIRMATION_PENDING', 'TICKET_AVAILABLE',
        'REVERIFY_REQUIRED', 'ELIGIBILITY_RESERVED'
    )),
    qualification_committed_at timestamptz,
    ticket_replay_until timestamptz,
    terminal_at timestamptz,
    CHECK ((flow_id IS NULL) = (installation_id IS NULL)),
    CHECK (verified_otp_expires_at > verified_at),
    CHECK ((old_slot IS NULL AND old_quota_version IS NULL)
           OR (old_slot IS NOT NULL AND old_quota_version IS NOT NULL
               AND old_quota_version >= 0 AND old_slot <> new_slot)),
    CHECK ((qualification_committed_at IS NULL AND ticket_replay_until IS NULL)
           OR (qualification_committed_at IS NOT NULL AND ticket_replay_until IS NOT NULL
               AND ticket_replay_until = verified_at + interval '10 minutes'))
);

CREATE INDEX otp_confirmations_retirement_pending
    ON v_auth.otp_confirmations(old_slot) WHERE state = 'RETIREMENT_PENDING';

CREATE TABLE v_auth.confirmation_sign_jobs (
    confirmation_key_digest bytea PRIMARY KEY
        REFERENCES v_auth.otp_confirmations(confirmation_key_digest),
    slot_id bytea NOT NULL CHECK (octet_length(slot_id) = 32),
    quota_version bigint NOT NULL CHECK (quota_version >= 0),
    signing_key_epoch bigint NOT NULL CHECK (signing_key_epoch BETWEEN 0 AND 4294967295),
    reg_message bytea NOT NULL CHECK (octet_length(reg_message) = 92),
    state text NOT NULL DEFAULT 'PENDING_SIGN' CHECK (state IN ('PENDING_SIGN', 'READY')),
    signature bytea CHECK (signature IS NULL OR octet_length(signature) = 64),
    CHECK ((state = 'PENDING_SIGN' AND signature IS NULL)
           OR (state = 'READY' AND signature IS NOT NULL)),
    CHECK (substring(reg_message FROM 1 FOR 20)
           = convert_to('HNUHOLE/REGISTER/V2', 'UTF8') || decode('00', 'hex')),
    CHECK (substring(reg_message FROM 21 FOR 4)
           = decode(lpad(to_hex(signing_key_epoch), 8, '0'), 'hex')),
    CHECK (substring(reg_message FROM 29 FOR 32) = slot_id)
);

ALTER TABLE v_auth.email_quota ADD COLUMN reservation_confirmation_key_digest bytea
    CHECK (reservation_confirmation_key_digest IS NULL
           OR octet_length(reservation_confirmation_key_digest) = 32);

CREATE OR REPLACE FUNCTION v_auth.guard_quota() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF ROW(NEW.email_exact, NEW.current_slot, NEW.bootstrap_public_key, NEW.quota_version,
           NEW.reservation_confirmation_key_digest)
       IS DISTINCT FROM ROW(OLD.email_exact, OLD.current_slot, OLD.bootstrap_public_key,
                            OLD.quota_version, OLD.reservation_confirmation_key_digest) THEN
        RAISE EXCEPTION 'quota bindings are immutable until receipt processing deletes them'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END
$$;

-- The pending authorization message is committed with successful OTP
-- consumption before calling the signer. Only its signature may be filled in.
ALTER TABLE v_auth.retire_pending
    ALTER COLUMN retirement_authorization DROP NOT NULL,
    ADD COLUMN confirmation_key_digest bytea
        REFERENCES v_auth.otp_confirmations(confirmation_key_digest)
        CHECK (confirmation_key_digest IS NULL OR octet_length(confirmation_key_digest) = 32),
    ADD COLUMN authorization_message bytea,
    ADD COLUMN signing_key_epoch bigint;

ALTER TABLE v_auth.retire_pending ADD CONSTRAINT retire_pending_signing_shape CHECK (
    (confirmation_key_digest IS NULL AND authorization_message IS NULL
     AND signing_key_epoch IS NULL AND retirement_authorization IS NOT NULL)
    OR
    (confirmation_key_digest IS NOT NULL AND authorization_message IS NOT NULL
     AND signing_key_epoch IS NOT NULL AND signing_key_epoch BETWEEN 0 AND 4294967295
     AND authorization_message = convert_to('HNUHOLE/RETIRE-AUTH/V1', 'UTF8')
         || decode('00', 'hex') || decode(lpad(to_hex(signing_key_epoch), 8, '0'), 'hex') || old_slot
     AND (retirement_authorization IS NULL
          OR substring(retirement_authorization FROM 1 FOR 59) = authorization_message))
);

CREATE OR REPLACE FUNCTION v_auth.guard_retire_pending() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF ROW(NEW.old_slot, NEW.email_exact, NEW.quota_version, NEW.new_slot,
           NEW.new_bootstrap_public_key, NEW.state, NEW.confirmation_key_digest,
           NEW.authorization_message, NEW.signing_key_epoch)
       IS DISTINCT FROM
       ROW(OLD.old_slot, OLD.email_exact, OLD.quota_version, OLD.new_slot,
           OLD.new_bootstrap_public_key, OLD.state, OLD.confirmation_key_digest,
           OLD.authorization_message, OLD.signing_key_epoch)
       OR (OLD.retirement_authorization IS NOT NULL
           AND NEW.retirement_authorization IS DISTINCT FROM OLD.retirement_authorization)
       OR NEW.retirement_authorization IS NULL THEN
        RAISE EXCEPTION 'retirement binding is immutable; authorization only fills once'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END
$$;

CREATE FUNCTION v_auth.guard_otp_confirmation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF ROW(NEW.confirmation_key_digest, NEW.email_exact,
           NEW.new_slot, NEW.new_bootstrap_public_key, NEW.old_slot, NEW.old_quota_version,
           NEW.verified_at, NEW.verified_otp_expires_at, NEW.admission_window, NEW.signing_key_epoch)
       IS DISTINCT FROM
       ROW(OLD.confirmation_key_digest, OLD.email_exact,
           OLD.new_slot, OLD.new_bootstrap_public_key, OLD.old_slot, OLD.old_quota_version,
           OLD.verified_at, OLD.verified_otp_expires_at, OLD.admission_window, OLD.signing_key_epoch)
       OR (OLD.qualification_committed_at IS NOT NULL
           AND ROW(NEW.qualification_committed_at, NEW.ticket_replay_until)
               IS DISTINCT FROM ROW(OLD.qualification_committed_at, OLD.ticket_replay_until))
       OR ((NEW.flow_id IS DISTINCT FROM OLD.flow_id
            OR NEW.installation_id IS DISTINCT FROM OLD.installation_id)
           AND NOT (OLD.flow_id IS NOT NULL AND NEW.flow_id IS NULL
                    AND NEW.installation_id IS NULL
                    AND EXISTS (SELECT 1 FROM v_auth.request_results
                                WHERE key_digest=OLD.confirmation_key_digest AND state='EXPIRED')))
       OR (OLD.state IN ('REVERIFY_REQUIRED', 'ELIGIBILITY_RESERVED')
           AND ROW(NEW.state, NEW.qualification_committed_at, NEW.ticket_replay_until, NEW.terminal_at)
               IS DISTINCT FROM ROW(OLD.state, OLD.qualification_committed_at,
                                    OLD.ticket_replay_until, OLD.terminal_at))
       OR (OLD.state = 'TICKET_AVAILABLE'
           AND NEW.state NOT IN ('TICKET_AVAILABLE', 'REVERIFY_REQUIRED'))
       OR (OLD.state = 'CONFIRMATION_PENDING'
           AND NEW.state NOT IN ('CONFIRMATION_PENDING', 'TICKET_AVAILABLE', 'REVERIFY_REQUIRED'))
       OR (OLD.terminal_at IS NOT NULL AND NEW.terminal_at IS DISTINCT FROM OLD.terminal_at) THEN
        RAISE EXCEPTION 'confirmation binding, admission, and terminal state are immutable'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END
$$;

CREATE TRIGGER otp_confirmation_immutable
    BEFORE UPDATE ON v_auth.otp_confirmations
    FOR EACH ROW EXECUTE FUNCTION v_auth.guard_otp_confirmation();

CREATE FUNCTION v_auth.guard_confirmation_sign_job() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF ROW(NEW.confirmation_key_digest, NEW.slot_id, NEW.quota_version,
           NEW.signing_key_epoch, NEW.reg_message)
       IS DISTINCT FROM ROW(OLD.confirmation_key_digest, OLD.slot_id, OLD.quota_version,
                            OLD.signing_key_epoch, OLD.reg_message)
       OR (OLD.state = 'READY' AND NEW IS DISTINCT FROM OLD) THEN
        RAISE EXCEPTION 'registration signing message and completed signature are immutable'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END
$$;

CREATE TRIGGER confirmation_sign_job_immutable
    BEFORE UPDATE ON v_auth.confirmation_sign_jobs
    FOR EACH ROW EXECUTE FUNCTION v_auth.guard_confirmation_sign_job();

COMMENT ON SCHEMA v_auth IS 'Verifier development OTP and eligibility facts; database time is development-only and V Gate is pending';
-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
DO $$ BEGIN RAISE EXCEPTION 'Authentication facts require freeze and forward repair; Down is forbidden'; END $$;
-- +goose StatementEnd
