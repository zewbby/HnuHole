-- Eligibility OTP and encrypted mail queue. Apply after0001 in V only.
-- No plaintext OTP, bootstrap private key, password, or recovery code columns.

CREATE TABLE v_auth.otp_email_state (
    email_exact bytea PRIMARY KEY CHECK (octet_length(email_exact) BETWEEN 16 AND 254),
    code_generation bigint NOT NULL DEFAULT 0 CHECK (code_generation >= 0),
    latest_flow_id bytea CHECK (latest_flow_id IS NULL OR octet_length(latest_flow_id) = 32),
    send_wait_until timestamptz NOT NULL,
    last_activity_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    CHECK (code_generation > 0 OR latest_flow_id IS NULL)
);
CREATE INDEX otp_email_state_expiry ON v_auth.otp_email_state(last_activity_at,email_exact);

CREATE TABLE v_auth.otp_flows (
    flow_id bytea PRIMARY KEY CHECK (octet_length(flow_id) = 32),
    email_exact bytea NOT NULL REFERENCES v_auth.otp_email_state(email_exact),
    installation_id bytea NOT NULL CHECK (octet_length(installation_id) = 16),
    code_generation bigint NOT NULL CHECK (code_generation > 0),
    state text NOT NULL CHECK (state IN ('ACTIVE', 'CONSUMED', 'REPLACED', 'EXPIRED', 'INVALIDATED')),
    failed_attempts integer NOT NULL DEFAULT 0 CHECK (failed_attempts BETWEEN 0 AND 10),
    created_at timestamptz NOT NULL,
    expires_at timestamptz NOT NULL,
    UNIQUE(email_exact,code_generation),
    UNIQUE(email_exact,flow_id,code_generation),
    CHECK (expires_at = created_at + interval '5 minutes'),
    CHECK (state <> 'ACTIVE' OR failed_attempts < 10)
);

ALTER TABLE v_auth.otp_email_state ADD CONSTRAINT otp_latest_flow_binding
    FOREIGN KEY(email_exact,latest_flow_id,code_generation)
    REFERENCES v_auth.otp_flows(email_exact,flow_id,code_generation)
    DEFERRABLE INITIALLY DEFERRED;

CREATE TABLE v_auth.otp_code_versions (
    email_exact bytea NOT NULL,
    code_generation bigint NOT NULL CHECK (code_generation > 0),
    flow_id bytea NOT NULL CHECK (octet_length(flow_id) = 32),
    code_hmac bytea NOT NULL CHECK (octet_length(code_hmac) = 32),
    otp_key_version bigint NOT NULL CHECK (otp_key_version > 0),
    state text NOT NULL CHECK (state IN ('ACTIVE', 'CONSUMED', 'REPLACED', 'EXPIRED', 'INVALIDATED')),
    expires_at timestamptz NOT NULL,
    retain_until timestamptz NOT NULL CHECK (retain_until = expires_at + interval '5 minutes'),
    PRIMARY KEY(email_exact,code_generation),
    FOREIGN KEY(email_exact,flow_id,code_generation)
        REFERENCES v_auth.otp_flows(email_exact,flow_id,code_generation)
);

CREATE TABLE v_auth.device_email_limits (
    installation_id bytea NOT NULL CHECK (octet_length(installation_id) = 16),
    email_digest bytea NOT NULL CHECK (octet_length(email_digest) = 32),
    consecutive_errors integer NOT NULL DEFAULT 0 CHECK (consecutive_errors BETWEEN 0 AND 3),
    locked_until timestamptz,
    last_activity_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    PRIMARY KEY(installation_id,email_digest),
    CHECK ((consecutive_errors < 3 AND locked_until IS NULL) OR (consecutive_errors = 3 AND locked_until IS NOT NULL))
);
CREATE INDEX otp_device_limits_expiry
    ON v_auth.device_email_limits(last_activity_at,installation_id,email_digest);

-- Exact rolling-window counts, not resettable counters attached to a flow.
CREATE TABLE v_auth.otp_budget_events (
    event_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email_exact bytea NOT NULL REFERENCES v_auth.otp_email_state(email_exact),
    kind text NOT NULL CHECK (kind IN ('SEND', 'VERIFY')),
    occurred_at timestamptz NOT NULL
);
CREATE INDEX otp_budget_events_window ON v_auth.otp_budget_events(email_exact,kind,occurred_at);

CREATE TABLE v_auth.mail_outbox (
    operation_id bytea PRIMARY KEY CHECK (octet_length(operation_id) = 32),
    key_digest bytea NOT NULL UNIQUE REFERENCES v_auth.request_results(key_digest),
    flow_id bytea NOT NULL UNIQUE REFERENCES v_auth.otp_flows(flow_id),
    state text NOT NULL CHECK (state IN ('QUEUED', 'DISPATCHING', 'SENT', 'NOT_SENT', 'UNKNOWN')),
    email_exact bytea,
    ciphertext bytea,
    nonce bytea,
    encryption_key_version bigint,
    expires_at timestamptz NOT NULL,
    send_wait_until timestamptz NOT NULL,
    previous_send_wait_until timestamptz NOT NULL,
    CHECK (send_wait_until > previous_send_wait_until),
    CHECK (
        (state IN ('QUEUED', 'DISPATCHING') AND email_exact IS NOT NULL
         AND ciphertext IS NOT NULL AND octet_length(ciphertext) = 22
         AND nonce IS NOT NULL AND octet_length(nonce) = 12
         AND encryption_key_version IS NOT NULL AND encryption_key_version > 0)
        OR
        (state IN ('SENT', 'NOT_SENT', 'UNKNOWN') AND email_exact IS NULL
         AND ciphertext IS NULL AND nonce IS NULL AND encryption_key_version IS NULL)
    )
);

CREATE FUNCTION v_auth.guard_otp_flow() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.flow_id IS DISTINCT FROM OLD.flow_id OR NEW.email_exact IS DISTINCT FROM OLD.email_exact
       OR NEW.installation_id IS DISTINCT FROM OLD.installation_id OR NEW.code_generation <> OLD.code_generation
       OR NEW.created_at IS DISTINCT FROM OLD.created_at OR NEW.expires_at IS DISTINCT FROM OLD.expires_at
       OR NEW.failed_attempts < OLD.failed_attempts
       OR (OLD.state <> 'ACTIVE' AND NEW.state IS DISTINCT FROM OLD.state) THEN
        RAISE EXCEPTION 'OTP flow binding, lifetime and terminal status are immutable' USING ERRCODE='23514';
    END IF;
    RETURN NEW;
END
$$;
CREATE TRIGGER otp_flow_monotonic BEFORE UPDATE ON v_auth.otp_flows
    FOR EACH ROW EXECUTE FUNCTION v_auth.guard_otp_flow();

CREATE FUNCTION v_auth.guard_otp_email_generation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.email_exact IS DISTINCT FROM OLD.email_exact OR NEW.code_generation < OLD.code_generation
       OR (NEW.code_generation = OLD.code_generation AND NEW.latest_flow_id IS DISTINCT FROM OLD.latest_flow_id
           AND NEW.latest_flow_id IS NOT NULL) THEN
        RAISE EXCEPTION 'OTP email generation cannot regress or substitute its flow' USING ERRCODE='23514';
    END IF;
    RETURN NEW;
END
$$;
CREATE TRIGGER otp_email_generation_monotonic BEFORE UPDATE ON v_auth.otp_email_state
    FOR EACH ROW EXECUTE FUNCTION v_auth.guard_otp_email_generation();

CREATE FUNCTION v_auth.guard_mail_job() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.operation_id IS DISTINCT FROM OLD.operation_id OR NEW.key_digest IS DISTINCT FROM OLD.key_digest
       OR NEW.flow_id IS DISTINCT FROM OLD.flow_id OR NEW.expires_at IS DISTINCT FROM OLD.expires_at
       OR NEW.send_wait_until IS DISTINCT FROM OLD.send_wait_until
       OR NEW.previous_send_wait_until IS DISTINCT FROM OLD.previous_send_wait_until
       OR (OLD.state IN ('SENT','NOT_SENT','UNKNOWN') AND NEW IS DISTINCT FROM OLD)
       OR (OLD.state = 'DISPATCHING' AND NEW.state = 'QUEUED') THEN
        RAISE EXCEPTION 'mail operation identity and dispatch attempt are monotonic' USING ERRCODE='23514';
    END IF;
    IF OLD.state = 'QUEUED' AND NEW.state = 'DISPATCHING'
       AND ROW(NEW.email_exact,NEW.ciphertext,NEW.nonce,NEW.encryption_key_version)
           IS DISTINCT FROM ROW(OLD.email_exact,OLD.ciphertext,OLD.nonce,OLD.encryption_key_version) THEN
        RAISE EXCEPTION 'dispatch cannot replace encrypted mail material' USING ERRCODE='23514';
    END IF;
    RETURN NEW;
END
$$;
CREATE TRIGGER mail_job_monotonic BEFORE UPDATE ON v_auth.mail_outbox
    FOR EACH ROW EXECUTE FUNCTION v_auth.guard_mail_job();
