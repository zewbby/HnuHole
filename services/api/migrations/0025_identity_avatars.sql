-- +goose Up
-- +goose StatementBegin
CREATE TABLE public.identity_avatar_assets (
    asset_id uuid PRIMARY KEY,
    account_id uuid NOT NULL REFERENCES c_auth.accounts(account_id),
    identity_id uuid,
    digest bytea NOT NULL CHECK(octet_length(digest)=32),
    payload bytea CHECK(octet_length(payload) BETWEEN 12 AND 524288),
    created_at timestamptz NOT NULL,
    expires_at timestamptz NOT NULL CHECK(expires_at>created_at),
    FOREIGN KEY(account_id,identity_id) REFERENCES public.community_identities(account_id,identity_id) DEFERRABLE INITIALLY DEFERRED
);
CREATE INDEX identity_avatar_pending ON public.identity_avatar_assets(account_id,expires_at) WHERE identity_id IS NULL AND payload IS NOT NULL;
ALTER TABLE public.community_identities DROP CONSTRAINT identity_profile_shape;
ALTER TABLE public.community_identities ADD CONSTRAINT identity_profile_shape CHECK (
 (deleted_at IS NULL AND nickname IS NOT NULL AND octet_length(nickname) BETWEEN 2 AND 512 AND avatar IS NOT NULL
  AND (avatar='default-v1' OR avatar ~ '^avatar-v1:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'))
 OR (deleted_at IS NOT NULL AND nickname IS NULL AND avatar IS NULL AND last_renamed_at IS NULL));
ALTER TABLE public.identity_change_receipts DROP CONSTRAINT identity_change_receipts_operation_check;
ALTER TABLE public.identity_change_receipts ADD CHECK(operation IN ('CREATE','RENAME','DELETE','AVATAR'));
ALTER TABLE public.identity_change_receipts DROP CONSTRAINT identity_change_receipts_error_code_check;
ALTER TABLE public.identity_change_receipts ADD CHECK(error_code IN ('IDENTITY_INVALID_NAME','IDENTITY_DUPLICATE_NAME','IDENTITY_LIMIT','IDENTITY_CREATE_COOLDOWN','IDENTITY_RENAME_COOLDOWN','IDENTITY_LAST_REQUIRED','IDENTITY_NOT_FOUND','IDENTITY_AVATAR_INVALID'));

CREATE OR REPLACE FUNCTION public.guard_identity_avatar() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'avatar references cannot be recycled' USING ERRCODE='23514'; END IF;
 IF NEW.asset_id IS DISTINCT FROM OLD.asset_id OR NEW.account_id IS DISTINCT FROM OLD.account_id
 OR NEW.digest IS DISTINCT FROM OLD.digest OR NEW.created_at IS DISTINCT FROM OLD.created_at OR NEW.expires_at IS DISTINCT FROM OLD.expires_at
 OR (OLD.identity_id IS NOT NULL AND NEW.identity_id IS DISTINCT FROM OLD.identity_id)
 OR (NEW.payload IS DISTINCT FROM OLD.payload AND NEW.payload IS NOT NULL) THEN
 RAISE EXCEPTION 'avatar ownership and bytes are immutable' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER identity_avatar_immutable BEFORE UPDATE OR DELETE ON public.identity_avatar_assets FOR EACH ROW EXECUTE FUNCTION public.guard_identity_avatar();

CREATE OR REPLACE FUNCTION public.bind_identity_avatar() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE bound_count integer;
BEGIN
 IF NEW.avatar LIKE 'avatar-v1:%' AND (TG_OP='INSERT' OR NEW.avatar IS DISTINCT FROM OLD.avatar) THEN
  UPDATE public.identity_avatar_assets SET identity_id=NEW.identity_id
   WHERE asset_id=substring(NEW.avatar from 11)::uuid AND account_id=NEW.account_id AND payload IS NOT NULL
    AND (identity_id IS NULL OR identity_id=NEW.identity_id);
  GET DIAGNOSTICS bound_count=ROW_COUNT;
  IF bound_count<>1 THEN RAISE EXCEPTION 'avatar must belong to this identity' USING ERRCODE='23514'; END IF;
 END IF;
 IF TG_OP='UPDATE' AND OLD.avatar LIKE 'avatar-v1:%' AND NEW.avatar IS DISTINCT FROM OLD.avatar THEN
  UPDATE public.identity_avatar_assets SET payload=NULL WHERE asset_id=substring(OLD.avatar from 11)::uuid AND identity_id=OLD.identity_id;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER identity_avatar_binding AFTER INSERT OR UPDATE OF avatar ON public.community_identities FOR EACH ROW EXECUTE FUNCTION public.bind_identity_avatar();
CREATE OR REPLACE FUNCTION public.close_identity_avatars() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF NEW.state='CLOSED' THEN UPDATE public.identity_avatar_assets SET payload=NULL WHERE account_id=NEW.account_id AND payload IS NOT NULL; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER identity_avatar_account_closed AFTER UPDATE OF state ON c_auth.accounts FOR EACH ROW EXECUTE FUNCTION public.close_identity_avatars();
REVOKE ALL ON public.identity_avatar_assets FROM PUBLIC;
REVOKE ALL ON FUNCTION public.guard_identity_avatar(),public.bind_identity_avatar(),public.close_identity_avatars() FROM PUBLIC;
-- +goose StatementEnd
-- +goose Down
-- +goose StatementBegin
DO $$ BEGIN RAISE EXCEPTION 'Avatar references and receipts require forward repair'; END $$;
-- +goose StatementEnd
