-- +goose Up
-- +goose StatementBegin
-- B02 manages private account-owned identities only. Post bindings, deleted
-- author projections and local chat cleanup belong to their business slices.
CREATE TABLE public.identity_account_state (
    account_id uuid PRIMARY KEY REFERENCES c_auth.accounts(account_id),
    created_count bigint NOT NULL CHECK (created_count >= 1),
    last_created_at timestamptz NOT NULL
);

CREATE TABLE public.community_identities (
    identity_id uuid PRIMARY KEY,
    account_id uuid NOT NULL REFERENCES c_auth.accounts(account_id),
    nickname text COLLATE "C",
    avatar text,
    is_original boolean NOT NULL,
    created_at timestamptz NOT NULL,
    last_renamed_at timestamptz,
    deleted_at timestamptz,
    UNIQUE(account_id,identity_id),
    CHECK (last_renamed_at IS NULL OR last_renamed_at >= created_at),
    CHECK (deleted_at IS NULL OR deleted_at >= created_at),
    CONSTRAINT identity_profile_shape CHECK (
        (deleted_at IS NULL AND nickname IS NOT NULL
         AND octet_length(nickname) BETWEEN 2 AND 512
         AND avatar IS NOT NULL AND avatar = 'default-v1')
        OR (deleted_at IS NOT NULL AND nickname IS NULL
            AND avatar IS NULL AND last_renamed_at IS NULL)
    )
);
CREATE INDEX identities_account_active ON public.community_identities(account_id,created_at,identity_id)
    WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX identities_own_nickname ON public.community_identities(account_id,nickname)
    WHERE deleted_at IS NULL;
-- The original identity remains the original after deletion; future creations
-- are new masks, never replacement originals.
CREATE UNIQUE INDEX identities_one_original ON public.community_identities(account_id)
    WHERE is_original;

CREATE TABLE public.identity_change_receipts (
    account_id uuid NOT NULL REFERENCES c_auth.accounts(account_id),
    change_key_digest bytea NOT NULL CHECK (octet_length(change_key_digest) = 32),
    intent_fingerprint bytea NOT NULL CHECK (octet_length(intent_fingerprint) = 32),
    state text NOT NULL CHECK (state IN ('COMMITTED','REJECTED')),
    operation text NOT NULL CHECK (operation IN ('CREATE','RENAME','DELETE')),
    identity_id uuid,
    error_code text CHECK (error_code IN ('IDENTITY_INVALID_NAME','IDENTITY_DUPLICATE_NAME',
        'IDENTITY_LIMIT','IDENTITY_CREATE_COOLDOWN','IDENTITY_RENAME_COOLDOWN',
        'IDENTITY_LAST_REQUIRED','IDENTITY_NOT_FOUND')),
    committed_at timestamptz NOT NULL,
    PRIMARY KEY(account_id,change_key_digest),
    FOREIGN KEY(account_id,identity_id)
        REFERENCES public.community_identities(account_id,identity_id),
    CONSTRAINT identity_receipt_shape CHECK (
        (state='COMMITTED' AND identity_id IS NOT NULL AND error_code IS NULL)
        OR (state='REJECTED' AND identity_id IS NULL AND error_code IS NOT NULL)
    )
);
-- No nickname/bearer/plaintext request is kept in the result anchor. Receipts
-- remain queryable under a later valid session of the same account. Stable
-- business rejection receipts prevent delayed originals from applying after a
-- definitive rejected retry; neither receipt state consumes creation quota.

CREATE FUNCTION public.guard_identity_account_state() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'identity creation counters cannot be deleted' USING ERRCODE = '23514';
    END IF;
    IF NEW.account_id IS DISTINCT FROM OLD.account_id
       OR NEW.created_count <> OLD.created_count + 1
       OR NEW.last_created_at < OLD.last_created_at THEN
        RAISE EXCEPTION 'identity cumulative creation counters are monotonic' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END
$$;
CREATE TRIGGER identity_account_state_monotonic
    BEFORE UPDATE OR DELETE ON public.identity_account_state
    FOR EACH ROW EXECUTE FUNCTION public.guard_identity_account_state();

CREATE FUNCTION public.guard_community_identity() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'identity tombstones cannot be deleted' USING ERRCODE = '23514';
    END IF;
    IF NEW.identity_id IS DISTINCT FROM OLD.identity_id
       OR NEW.account_id IS DISTINCT FROM OLD.account_id
       OR NEW.is_original IS DISTINCT FROM OLD.is_original
       OR NEW.created_at IS DISTINCT FROM OLD.created_at
       OR (OLD.deleted_at IS NOT NULL AND NEW IS DISTINCT FROM OLD)
       OR (OLD.last_renamed_at IS NOT NULL AND NEW.deleted_at IS NULL
           AND (NEW.last_renamed_at IS NULL OR NEW.last_renamed_at < OLD.last_renamed_at)) THEN
        RAISE EXCEPTION 'identity ownership, creation and deletion are immutable' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END
$$;
CREATE TRIGGER community_identity_monotonic
    BEFORE UPDATE OR DELETE ON public.community_identities
    FOR EACH ROW EXECUTE FUNCTION public.guard_community_identity();

CREATE FUNCTION public.guard_identity_receipt() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'identity change receipts are immutable' USING ERRCODE = '23514';
END
$$;
CREATE TRIGGER identity_receipt_immutable
    BEFORE UPDATE OR DELETE ON public.identity_change_receipts
    FOR EACH ROW EXECUTE FUNCTION public.guard_identity_receipt();

CREATE FUNCTION public.check_identity_account_shape() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    selected_account uuid;
    cumulative_count bigint;
    total_count bigint;
    active_count bigint;
    original_count bigint;
BEGIN
    selected_account := NEW.account_id;
    SELECT created_count INTO cumulative_count FROM public.identity_account_state
        WHERE account_id=selected_account;
    SELECT count(*),count(*) FILTER (WHERE deleted_at IS NULL),count(*) FILTER (WHERE is_original)
        INTO total_count,active_count,original_count FROM public.community_identities
        WHERE account_id=selected_account;
    IF cumulative_count IS NULL OR cumulative_count <> total_count
       OR active_count < 1 OR active_count > 3 OR original_count <> 1 THEN
        RAISE EXCEPTION 'identity count/original/cumulative shape invalid' USING ERRCODE = '23514';
    END IF;
    RETURN NULL;
END
$$;
CREATE CONSTRAINT TRIGGER identity_account_shape_from_identity
    AFTER INSERT OR UPDATE ON public.community_identities DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION public.check_identity_account_shape();
CREATE CONSTRAINT TRIGGER identity_account_shape_from_counter
    AFTER INSERT OR UPDATE ON public.identity_account_state DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION public.check_identity_account_shape();

REVOKE ALL ON public.identity_account_state,public.community_identities,public.identity_change_receipts FROM PUBLIC;
REVOKE ALL ON FUNCTION public.guard_identity_account_state(),public.guard_community_identity(),
    public.guard_identity_receipt(),public.check_identity_account_shape() FROM PUBLIC;
-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
DO $$ BEGIN RAISE EXCEPTION 'Identity counters and tombstones require forward repair; Down is forbidden'; END $$;
-- +goose StatementEnd
