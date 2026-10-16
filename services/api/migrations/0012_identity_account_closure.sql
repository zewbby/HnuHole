-- +goose Up
-- +goose StatementBegin
-- Account closure is distinct from deleting one identity. Preserve ownership,
-- cumulative creation counters and permanent receipts, while erasing every
-- live profile in the same final authorized transaction as CLOSED and RELEASED.
LOCK TABLE c_auth.accounts IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE public.identity_account_state, public.community_identities IN SHARE ROW EXCLUSIVE MODE;

CREATE OR REPLACE FUNCTION public.check_identity_account_shape() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    selected_account uuid;
    account_state text;
    cumulative_count bigint;
    total_count bigint;
    active_count bigint;
    original_count bigint;
BEGIN
    -- Runtime business transactions explicitly use READ COMMITTED. A row lock
    -- alone cannot refresh a REPEATABLE READ snapshot; reject other isolation
    -- levels instead of allowing aggregate write skew in direct identity DML.
    IF current_setting('transaction_isolation') <> 'read committed' THEN
        RAISE EXCEPTION 'identity lifecycle mutations require READ COMMITTED'
            USING ERRCODE = '23514';
    END IF;
    selected_account := NEW.account_id;
    -- Normal runtime callers already hold this account lock before any
    -- dependent row. It also serializes direct DML constraint validation.
    SELECT state INTO account_state FROM c_auth.accounts
        WHERE account_id=selected_account FOR NO KEY UPDATE;
    SELECT created_count INTO cumulative_count FROM public.identity_account_state
        WHERE account_id=selected_account;
    SELECT count(*),count(*) FILTER (WHERE deleted_at IS NULL),count(*) FILTER (WHERE is_original)
        INTO total_count,active_count,original_count FROM public.community_identities
        WHERE account_id=selected_account;
    IF account_state IS NULL THEN
        RAISE EXCEPTION 'identity account absent' USING ERRCODE = '23514';
    END IF;
    -- Registration never creates a public identity. Zero-identity accounts
    -- remain valid, including throughout the seven-day wait and after closure.
    IF cumulative_count IS NULL THEN
        IF total_count <> 0 THEN
            RAISE EXCEPTION 'identity cumulative counter absent' USING ERRCODE = '23514';
        END IF;
        RETURN NULL;
    END IF;
    IF cumulative_count <> total_count OR original_count <> 1
       OR (account_state = 'CLOSED' AND active_count <> 0)
       OR (account_state <> 'CLOSED' AND (active_count < 1 OR active_count > 3)) THEN
        RAISE EXCEPTION 'identity count/original/cumulative/closure shape invalid' USING ERRCODE = '23514';
    END IF;
    RETURN NULL;
END
$$;

CREATE CONSTRAINT TRIGGER identity_account_shape_from_account
    AFTER UPDATE ON c_auth.accounts DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW WHEN (OLD.state IS DISTINCT FROM NEW.state)
    EXECUTE FUNCTION public.check_identity_account_shape();

-- Pre-AC02 CLOSED accounts may still have live profiles. This is a privileged
-- forward privacy repair, not a new qualification or an asserted exact closure
-- time. Use only the Gate's already persisted trusted watermark, never the
-- migration host/database wall clock. Existing deleted tombstones are untouched.
DO $$
DECLARE repair_at timestamptz;
BEGIN
    SELECT trusted_high_watermark INTO repair_at FROM c_auth.authorization_gate
        WHERE singleton_id=1 FOR UPDATE;
    IF EXISTS (
        SELECT 1 FROM public.community_identities i JOIN c_auth.accounts a USING (account_id)
        WHERE a.state='CLOSED' AND i.deleted_at IS NULL
          AND (repair_at IS NULL OR repair_at < GREATEST(i.created_at,COALESCE(i.last_renamed_at,i.created_at)))
    ) THEN
        RAISE EXCEPTION 'legacy closed profiles require a sufficient trusted Gate watermark before migration'
            USING ERRCODE = '23514';
    END IF;
    UPDATE public.community_identities i SET nickname=NULL,avatar=NULL,last_renamed_at=NULL,deleted_at=repair_at
        FROM c_auth.accounts a WHERE a.account_id=i.account_id AND a.state='CLOSED' AND i.deleted_at IS NULL;
END
$$;

REVOKE ALL ON FUNCTION public.check_identity_account_shape() FROM PUBLIC;
-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
DO $$ BEGIN RAISE EXCEPTION 'Closed identity tombstones require forward repair; Down is forbidden'; END $$;
-- +goose StatementEnd
