-- +goose Up
-- +goose StatementBegin
-- Formal C auth migration, promoted from the historical isolated lab source.
-- Goose executes this complete Up transaction through the migration owner.
-- Passwords, recovery codes, bearer tokens, OTPs, and bootstrap private keys
-- have no plaintext columns. Signature and time validation remain in Go.

CREATE SCHEMA c_auth;

CREATE TABLE c_auth.accounts (
    account_id uuid PRIMARY KEY,
    platform_number text COLLATE "C" NOT NULL UNIQUE
        CHECK (platform_number ~ '^[0-9]{6}$'),
    state text NOT NULL DEFAULT 'ACTIVE'
        CHECK (state IN ('ACTIVE', 'PENDING_CLOSE', 'CLOSED')),
    username text COLLATE "C",
    password_hash bytea,
    password_salt bytea,
    password_params_version bigint,
    credential_version bigint NOT NULL DEFAULT 1 CHECK (credential_version >= 0),
    session_generation bigint NOT NULL DEFAULT 1 CHECK (session_generation >= 0),
    CONSTRAINT accounts_credentials_shape CHECK (
        (state IN ('ACTIVE', 'PENDING_CLOSE')
         AND username IS NOT NULL AND username ~ '^[a-z][a-z0-9_]{5,23}$'
         AND password_hash IS NOT NULL AND octet_length(password_hash) = 32
         AND password_salt IS NOT NULL AND octet_length(password_salt) = 16
         AND password_params_version IS NOT NULL AND password_params_version >= 1)
        OR
        (state = 'CLOSED' AND username IS NULL AND password_hash IS NULL
         AND password_salt IS NULL AND password_params_version IS NULL)
    )
);

CREATE UNIQUE INDEX accounts_active_username_unique
    ON c_auth.accounts (username) WHERE state <> 'CLOSED';

CREATE TABLE c_auth.slot_ledger (
    slot_id bytea PRIMARY KEY CHECK (octet_length(slot_id) = 32),
    state text NOT NULL CHECK (state IN ('ACTIVE', 'RETIRED', 'CLOSED')),
    account_id uuid UNIQUE REFERENCES c_auth.accounts (account_id),
    receipt_acknowledged boolean NOT NULL DEFAULT false,
    receipt_purpose text GENERATED ALWAYS AS (
        CASE state WHEN 'RETIRED' THEN 'RETIRED'
                   WHEN 'CLOSED' THEN 'RELEASED' ELSE NULL END
    ) STORED,
    UNIQUE (slot_id, receipt_purpose),
    CONSTRAINT slot_ledger_shape CHECK (
        (state = 'ACTIVE' AND account_id IS NOT NULL AND NOT receipt_acknowledged)
        OR (state IN ('RETIRED', 'CLOSED') AND account_id IS NULL)
    )
);

CREATE TABLE c_auth.signup_intents (
    intent_id bytea PRIMARY KEY CHECK (octet_length(intent_id) = 32),
    state text NOT NULL DEFAULT 'OPEN'
        CHECK (state IN ('OPEN', 'CONSUMED', 'EXPIRED', 'ABANDONED')),
    attempts bigint NOT NULL DEFAULT 0 CHECK (attempts >= 0),
    created_at timestamptz NOT NULL,
    expires_at timestamptz NOT NULL,
    challenge bytea UNIQUE,
    ticket bytea,
    slot_id bytea,
    bootstrap_public_key bytea,
    admission_window bigint,
    username text COLLATE "C",
    password_hash bytea,
    password_salt bytea,
    password_params_version bigint,
    recovery_digest bytea,
    installation_id bytea,
    CHECK (expires_at > created_at AND expires_at <= created_at + interval '10 minutes'),
    CONSTRAINT signup_intents_material_shape CHECK (
        (state = 'OPEN'
         AND challenge IS NOT NULL AND octet_length(challenge) = 32
         AND ticket IS NOT NULL AND octet_length(ticket) = 156
         AND slot_id IS NOT NULL AND octet_length(slot_id) = 32
         AND bootstrap_public_key IS NOT NULL AND octet_length(bootstrap_public_key) = 32
         AND admission_window IS NOT NULL AND admission_window BETWEEN 0 AND 4294967295
         AND username IS NOT NULL AND username ~ '^[a-z][a-z0-9_]{5,23}$'
         AND password_hash IS NOT NULL AND octet_length(password_hash) = 32
         AND password_salt IS NOT NULL AND octet_length(password_salt) = 16
         AND password_params_version IS NOT NULL AND password_params_version >= 1
         AND recovery_digest IS NOT NULL AND octet_length(recovery_digest) = 32
         AND installation_id IS NOT NULL AND octet_length(installation_id) = 16
         AND substring(ticket FROM 1 FOR 20) = convert_to('HNUHOLE/REGISTER/V2', 'UTF8') || decode('00', 'hex')
         AND substring(ticket FROM 25 FOR 4) = decode(lpad(to_hex(admission_window), 8, '0'), 'hex')
         AND substring(ticket FROM 29 FOR 32) = slot_id
         AND substring(ticket FROM 61 FOR 32) = bootstrap_public_key)
        OR
        (state <> 'OPEN' AND challenge IS NULL AND ticket IS NULL AND slot_id IS NULL
         AND bootstrap_public_key IS NULL AND admission_window IS NULL AND username IS NULL
         AND password_hash IS NULL AND password_salt IS NULL AND password_params_version IS NULL
         AND recovery_digest IS NULL AND installation_id IS NULL)
    )
);

CREATE TABLE c_auth.recovery_codes (
    account_id uuid PRIMARY KEY REFERENCES c_auth.accounts (account_id),
    code_digest bytea NOT NULL UNIQUE CHECK (octet_length(code_digest) = 32),
    activation_version bigint NOT NULL CHECK (activation_version >= 0)
);

CREATE TABLE c_auth.sessions (
    token_digest bytea PRIMARY KEY CHECK (octet_length(token_digest) = 32),
    revoke_digest bytea NOT NULL UNIQUE CHECK (octet_length(revoke_digest) = 32),
    account_id uuid NOT NULL REFERENCES c_auth.accounts (account_id),
    installation_id bytea NOT NULL CHECK (octet_length(installation_id) = 16),
    session_generation bigint NOT NULL CHECK (session_generation >= 0),
    created_at timestamptz NOT NULL,
    last_activity_at timestamptz NOT NULL,
    expires_at timestamptz NOT NULL,
    revoked_at timestamptz,
    CHECK (expires_at > created_at),
    CHECK (last_activity_at >= created_at AND last_activity_at <= expires_at),
    CHECK (revoked_at IS NULL OR revoked_at >= created_at)
);

-- Expiry is checked by the command, not a now()-dependent partial index.
CREATE UNIQUE INDEX sessions_one_unrevoked_per_account
    ON c_auth.sessions (account_id) WHERE revoked_at IS NULL;

CREATE TABLE c_auth.request_results (
    operation text COLLATE "C" NOT NULL CHECK (operation ~ '^[A-Z][A-Z0-9_]{0,63}$'),
    key_digest bytea NOT NULL UNIQUE CHECK (octet_length(key_digest) = 32),
    state text NOT NULL CHECK (state IN ('LIVE', 'EXPIRED')),
    request_hmac bytea,
    hmac_key_version bigint,
    intent_id bytea REFERENCES c_auth.signup_intents (intent_id) DEFERRABLE INITIALLY DEFERRED,
    result_code text COLLATE "C",
    expires_at timestamptz,
    PRIMARY KEY (operation, key_digest),
    CONSTRAINT request_results_shape CHECK (
        (state = 'LIVE'
         AND request_hmac IS NOT NULL AND octet_length(request_hmac) = 32
         AND hmac_key_version IS NOT NULL AND hmac_key_version >= 0
         AND (intent_id IS NULL OR octet_length(intent_id) = 32)
         AND result_code IS NOT NULL AND result_code ~ '^[A-Z][A-Z0-9_]{0,63}$'
         AND expires_at IS NOT NULL)
        OR
        (state = 'EXPIRED' AND request_hmac IS NULL AND hmac_key_version IS NULL
         AND intent_id IS NULL AND result_code IS NULL AND expires_at IS NULL)
    )
);

CREATE TABLE c_auth.receipt_outbox (
    slot_id bytea PRIMARY KEY CHECK (octet_length(slot_id) = 32),
    purpose text NOT NULL CHECK (purpose IN ('RETIRED', 'RELEASED')),
    signing_key_epoch bigint NOT NULL CHECK (signing_key_epoch BETWEEN 0 AND 4294967295),
    receipt_message bytea NOT NULL,
    signature bytea CHECK (signature IS NULL OR octet_length(signature) = 64),
    state text NOT NULL DEFAULT 'PENDING_SIGN' CHECK (state IN ('PENDING_SIGN', 'READY', 'ACKED')),
    ack_at timestamptz,
    FOREIGN KEY (slot_id, purpose) REFERENCES c_auth.slot_ledger (slot_id, receipt_purpose)
        DEFERRABLE INITIALLY DEFERRED,
    CHECK (receipt_message = convert_to('HNUHOLE/' || purpose || '/V1', 'UTF8')
           || decode('00', 'hex') || decode(lpad(to_hex(signing_key_epoch), 8, '0'), 'hex') || slot_id),
    CONSTRAINT receipt_outbox_shape CHECK (
        (state = 'PENDING_SIGN' AND signature IS NULL AND ack_at IS NULL)
        OR (state = 'READY' AND signature IS NOT NULL AND ack_at IS NULL)
        OR (state = 'ACKED' AND ack_at IS NOT NULL)
    )
);

CREATE FUNCTION c_auth.guard_slot_ledger() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'slot ledger anchors cannot be deleted' USING ERRCODE = '23514';
    ELSIF TG_OP = 'INSERT' THEN
        IF NEW.receipt_acknowledged THEN
            RAISE EXCEPTION 'new slot ledger anchors cannot start acknowledged' USING ERRCODE = '23514';
        END IF;
    ELSE
        IF NEW.slot_id IS DISTINCT FROM OLD.slot_id
           OR (OLD.state <> 'ACTIVE' AND NEW.state IS DISTINCT FROM OLD.state)
           OR (OLD.state = 'ACTIVE' AND NEW.state NOT IN ('ACTIVE', 'CLOSED'))
           OR (OLD.state = 'ACTIVE' AND NEW.state = 'ACTIVE' AND NEW.account_id IS DISTINCT FROM OLD.account_id)
           OR (OLD.receipt_acknowledged AND NOT NEW.receipt_acknowledged) THEN
            RAISE EXCEPTION 'slot ledger state, binding, and acknowledgment are monotonic' USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END
$$;

CREATE TRIGGER slot_ledger_monotonic
    BEFORE INSERT OR UPDATE OR DELETE ON c_auth.slot_ledger
    FOR EACH ROW EXECUTE FUNCTION c_auth.guard_slot_ledger();

CREATE FUNCTION c_auth.guard_account() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.account_id IS DISTINCT FROM OLD.account_id
       OR NEW.platform_number IS DISTINCT FROM OLD.platform_number
       OR NEW.credential_version < OLD.credential_version
       OR NEW.session_generation < OLD.session_generation
       OR (OLD.state = 'CLOSED' AND NEW.state <> 'CLOSED') THEN
        RAISE EXCEPTION 'account identity, terminal state, and control versions are monotonic' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END
$$;

CREATE TRIGGER account_monotonic
    BEFORE UPDATE ON c_auth.accounts FOR EACH ROW EXECUTE FUNCTION c_auth.guard_account();

CREATE FUNCTION c_auth.check_closed_account_release() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE account_state text;
BEGIN
    SELECT state INTO account_state FROM c_auth.accounts WHERE account_id = OLD.account_id;
    IF account_state IS DISTINCT FROM 'CLOSED'
       OR EXISTS (SELECT 1 FROM c_auth.sessions WHERE account_id = OLD.account_id AND revoked_at IS NULL) THEN
        RAISE EXCEPTION 'release requires the linked account to be closed and all sessions revoked' USING ERRCODE = '23514';
    END IF;
    RETURN NULL;
END
$$;

-- This is only a release-signing defense, not the seven-day closure feature.
-- The OLD link is used transiently inside this transaction and is not retained
-- in the permanent terminal ledger or outbox.
CREATE CONSTRAINT TRIGGER closed_account_release_consistency
    AFTER UPDATE ON c_auth.slot_ledger DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW WHEN (OLD.state = 'ACTIVE' AND NEW.state = 'CLOSED')
    EXECUTE FUNCTION c_auth.check_closed_account_release();

CREATE FUNCTION c_auth.guard_signup_intent() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.intent_id IS DISTINCT FROM OLD.intent_id
       OR NEW.created_at IS DISTINCT FROM OLD.created_at OR NEW.expires_at IS DISTINCT FROM OLD.expires_at
       OR NEW.attempts < OLD.attempts
       OR (OLD.state <> 'OPEN' AND NEW IS DISTINCT FROM OLD) THEN
        RAISE EXCEPTION 'signup intent identity, lifetime, and terminal state are immutable' USING ERRCODE = '23514';
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

CREATE TRIGGER signup_intent_immutable
    BEFORE UPDATE ON c_auth.signup_intents FOR EACH ROW EXECUTE FUNCTION c_auth.guard_signup_intent();

CREATE FUNCTION c_auth.guard_request_result() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'request result anchors cannot be deleted' USING ERRCODE = '23514';
    END IF;
    IF NEW.operation IS DISTINCT FROM OLD.operation OR NEW.key_digest IS DISTINCT FROM OLD.key_digest
       OR (OLD.state = 'EXPIRED' AND NEW IS DISTINCT FROM OLD)
       OR (NEW.state = 'LIVE' AND ROW(NEW.request_hmac, NEW.hmac_key_version, NEW.intent_id, NEW.expires_at)
           IS DISTINCT FROM ROW(OLD.request_hmac, OLD.hmac_key_version, OLD.intent_id, OLD.expires_at)) THEN
        RAISE EXCEPTION 'request result identity and binding are immutable; expired anchors cannot revive' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END
$$;

CREATE TRIGGER request_result_monotonic
    BEFORE UPDATE OR DELETE ON c_auth.request_results FOR EACH ROW EXECUTE FUNCTION c_auth.guard_request_result();

CREATE FUNCTION c_auth.guard_receipt_outbox() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE acknowledged boolean;
BEGIN
    IF TG_OP = 'INSERT' THEN
        -- Same lock order as the application: ledger before outbox. This also
        -- rejects a stale worker INSERT after acknowledged payload cleanup.
        SELECT receipt_acknowledged INTO acknowledged FROM c_auth.slot_ledger
            WHERE slot_id = NEW.slot_id FOR UPDATE;
        IF acknowledged THEN
            RAISE EXCEPTION 'acknowledged receipt payload cannot be recreated' USING ERRCODE = '23514';
        END IF;
    ELSIF TG_OP = 'DELETE' THEN
        IF OLD.state <> 'ACKED' THEN
            RAISE EXCEPTION 'unacknowledged receipt payload cannot be deleted' USING ERRCODE = '23514';
        END IF;
        RETURN OLD;
    ELSE
        IF NEW.slot_id IS DISTINCT FROM OLD.slot_id OR NEW.purpose IS DISTINCT FROM OLD.purpose
           OR NEW.signing_key_epoch < OLD.signing_key_epoch
           OR (OLD.state = 'ACKED' AND NEW IS DISTINCT FROM OLD) THEN
            RAISE EXCEPTION 'receipt identity, signing epoch, and ACK are monotonic' USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END
$$;

CREATE TRIGGER receipt_outbox_monotonic
    BEFORE INSERT OR UPDATE OR DELETE ON c_auth.receipt_outbox
    FOR EACH ROW EXECUTE FUNCTION c_auth.guard_receipt_outbox();

CREATE FUNCTION c_auth.check_terminal_receipt() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE selected_slot bytea; ledger c_auth.slot_ledger%ROWTYPE; outbox c_auth.receipt_outbox%ROWTYPE;
BEGIN
    selected_slot := CASE WHEN TG_OP = 'DELETE' THEN OLD.slot_id ELSE NEW.slot_id END;
    SELECT * INTO ledger FROM c_auth.slot_ledger WHERE slot_id = selected_slot;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'receipt requires a permanent slot ledger anchor' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO outbox FROM c_auth.receipt_outbox WHERE slot_id = selected_slot;
    IF ledger.state = 'ACTIVE' THEN
        IF FOUND THEN
            RAISE EXCEPTION 'active slot cannot have a receipt' USING ERRCODE = '23514';
        END IF;
    ELSIF ledger.receipt_acknowledged THEN
        IF FOUND AND outbox.state <> 'ACKED' THEN
            RAISE EXCEPTION 'acknowledged slot requires ACKED or cleaned receipt payload' USING ERRCODE = '23514';
        END IF;
    ELSIF NOT FOUND OR outbox.state = 'ACKED' THEN
        RAISE EXCEPTION 'unacknowledged terminal slot requires pending receipt payload' USING ERRCODE = '23514';
    END IF;
    RETURN NULL;
END
$$;

-- Deferred checks permit terminal+outbox and ledger+ACK changes in either
-- order inside one transaction; a partial durable commit is rejected.
CREATE CONSTRAINT TRIGGER slot_terminal_receipt_consistency
    AFTER INSERT OR UPDATE ON c_auth.slot_ledger DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION c_auth.check_terminal_receipt();
CREATE CONSTRAINT TRIGGER outbox_terminal_receipt_consistency
    AFTER INSERT OR UPDATE OR DELETE ON c_auth.receipt_outbox DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION c_auth.check_terminal_receipt();

COMMENT ON SCHEMA c_auth IS 'Isolated authentication validation subset; no production wiring or least-privilege deployment.';

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
DO $$ BEGIN RAISE EXCEPTION 'Authentication facts require freeze and forward repair; Down is forbidden'; END $$;
-- +goose StatementEnd
