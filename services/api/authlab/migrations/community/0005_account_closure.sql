-- Seven-day closure authority for the disposable C laboratory only.
ALTER TABLE c_auth.accounts
    ADD COLUMN closure_generation bigint NOT NULL DEFAULT 0 CHECK (closure_generation >= 0);

CREATE FUNCTION c_auth.guard_closure_generation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.closure_generation < OLD.closure_generation THEN
        RAISE EXCEPTION 'closure generation cannot regress' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END
$$;
CREATE TRIGGER account_closure_generation_monotonic
    BEFORE UPDATE ON c_auth.accounts FOR EACH ROW EXECUTE FUNCTION c_auth.guard_closure_generation();

ALTER TABLE c_auth.sessions DROP CONSTRAINT sessions_revocation_reason_check;
ALTER TABLE c_auth.sessions ADD CONSTRAINT sessions_revocation_reason_check
    CHECK (revocation_reason IN ('REPLACED', 'LOGOUT', 'RECOVERY', 'CLOSURE', 'EXPIRED', 'BAN'));

ALTER TABLE c_auth.account_restrictions
    ADD COLUMN mute_state text NOT NULL DEFAULT 'NONE' CHECK (mute_state IN ('NONE', 'MUTED')),
    ADD COLUMN mute_ends_at timestamptz,
    ADD CONSTRAINT account_restriction_mute_shape CHECK (mute_state='MUTED' OR mute_ends_at IS NULL);
CREATE FUNCTION c_auth.guard_mute_restrictions() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF (NEW.mute_state,NEW.mute_ends_at) IS DISTINCT FROM (OLD.mute_state,OLD.mute_ends_at)
       AND NEW.version <= OLD.version THEN
        RAISE EXCEPTION 'mute changes require a new restriction version' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END
$$;
CREATE TRIGGER account_mute_restriction_version
    BEFORE UPDATE ON c_auth.account_restrictions FOR EACH ROW EXECUTE FUNCTION c_auth.guard_mute_restrictions();

CREATE TABLE c_auth.closure_requests (
    closure_id bytea PRIMARY KEY CHECK (octet_length(closure_id)=32),
    account_id uuid REFERENCES c_auth.accounts(account_id),
    status_digest bytea NOT NULL CHECK (octet_length(status_digest)=32),
    request_generation bigint,
    due_at timestamptz,
    state text NOT NULL CHECK (state IN ('PENDING','CANCELLED','CLOSED_RELEASE_PENDING')),
    terminal_at timestamptz,
    slot_id bytea REFERENCES c_auth.slot_ledger(slot_id),
    released_at timestamptz,
    CONSTRAINT closure_request_shape CHECK (
        (state='PENDING' AND account_id IS NOT NULL AND request_generation IS NOT NULL AND request_generation>0
         AND due_at IS NOT NULL AND terminal_at IS NULL AND slot_id IS NULL AND released_at IS NULL)
        OR (state='CANCELLED' AND account_id IS NULL AND request_generation IS NULL
            AND due_at IS NULL AND terminal_at IS NOT NULL AND slot_id IS NULL AND released_at IS NULL)
        OR (state='CLOSED_RELEASE_PENDING' AND account_id IS NULL AND request_generation IS NULL
            AND due_at IS NULL AND terminal_at IS NOT NULL AND slot_id IS NOT NULL AND octet_length(slot_id)=32
            AND (released_at IS NULL OR released_at>=terminal_at))
    )
);
CREATE UNIQUE INDEX closure_one_pending_per_account
    ON c_auth.closure_requests(account_id) WHERE state='PENDING';
CREATE UNIQUE INDEX closure_one_closed_per_slot
    ON c_auth.closure_requests(slot_id) WHERE slot_id IS NOT NULL;
CREATE INDEX closure_due_worker ON c_auth.closure_requests(due_at,closure_id) WHERE state='PENDING';

CREATE FUNCTION c_auth.guard_closure_request() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.closure_id IS DISTINCT FROM OLD.closure_id OR NEW.status_digest IS DISTINCT FROM OLD.status_digest
       OR (OLD.state='PENDING' AND NEW.state='PENDING' AND NEW IS DISTINCT FROM OLD)
       OR (OLD.state<>'PENDING' AND
           (NEW.closure_id,NEW.account_id,NEW.status_digest,NEW.request_generation,NEW.due_at,NEW.state,NEW.terminal_at,NEW.slot_id)
           IS DISTINCT FROM
           (OLD.closure_id,OLD.account_id,OLD.status_digest,OLD.request_generation,OLD.due_at,OLD.state,OLD.terminal_at,OLD.slot_id))
       OR (OLD.released_at IS NOT NULL AND NEW.released_at IS DISTINCT FROM OLD.released_at) THEN
        RAISE EXCEPTION 'closure identity, lifetime and terminal state are immutable' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END
$$;
CREATE TRIGGER closure_request_monotonic BEFORE UPDATE ON c_auth.closure_requests
    FOR EACH ROW EXECUTE FUNCTION c_auth.guard_closure_request();

CREATE FUNCTION c_auth.check_closure_authority() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE current_account c_auth.accounts%ROWTYPE; current_slot c_auth.slot_ledger%ROWTYPE;
BEGIN
    IF NEW.state='PENDING' THEN
        SELECT * INTO current_account FROM c_auth.accounts WHERE account_id=NEW.account_id;
        IF NOT FOUND OR current_account.state<>'PENDING_CLOSE'
           OR current_account.closure_generation<>NEW.request_generation
           OR EXISTS(SELECT 1 FROM c_auth.sessions WHERE account_id=NEW.account_id AND revoked_at IS NULL) THEN
            RAISE EXCEPTION 'pending closure requires matching account generation and revoked sessions' USING ERRCODE='23514';
        END IF;
    ELSIF NEW.state='CLOSED_RELEASE_PENDING' THEN
        SELECT * INTO current_slot FROM c_auth.slot_ledger WHERE slot_id=NEW.slot_id;
        IF NOT FOUND OR current_slot.state<>'CLOSED'
           OR (NEW.released_at IS NOT NULL AND NOT current_slot.receipt_acknowledged) THEN
            RAISE EXCEPTION 'closed closure status requires a closed slot and durable release acknowledgment' USING ERRCODE='23514';
        END IF;
    END IF;
    RETURN NULL;
END
$$;
CREATE CONSTRAINT TRIGGER closure_authority_consistency
    AFTER INSERT OR UPDATE ON c_auth.closure_requests DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION c_auth.check_closure_authority();
