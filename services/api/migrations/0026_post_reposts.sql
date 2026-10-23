-- +goose Up
-- Private identity archive; never a publication or a public account projection.
CREATE TABLE c_posts.post_repost_versions (
 account_id uuid NOT NULL REFERENCES c_auth.accounts(account_id),
 post_id uuid NOT NULL REFERENCES c_posts.posts(post_id),
 version uuid NOT NULL CHECK(version <> '00000000-0000-0000-0000-000000000000'),
 PRIMARY KEY(account_id,post_id)
);
CREATE TABLE c_posts.post_reposts (
 account_id uuid NOT NULL,
 identity_id uuid NOT NULL,
 post_id uuid NOT NULL REFERENCES c_posts.posts(post_id),
 reposted_at timestamptz NOT NULL,
 ordinal bigint GENERATED ALWAYS AS IDENTITY UNIQUE,
 PRIMARY KEY(identity_id,post_id),
 FOREIGN KEY(account_id,identity_id) REFERENCES public.community_identities(account_id,identity_id)
);
CREATE INDEX post_reposts_archive ON c_posts.post_reposts(account_id,reposted_at DESC,ordinal DESC);
-- +goose StatementBegin
CREATE FUNCTION c_posts.clear_identity_reposts() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
 IF NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL THEN
  -- Rotate surviving account/post fences before removing the identity archive.
  UPDATE c_posts.post_repost_versions v SET version=gen_random_uuid()
   WHERE v.account_id=NEW.account_id AND EXISTS
   (SELECT 1 FROM c_posts.post_reposts r WHERE r.identity_id=NEW.identity_id AND r.post_id=v.post_id);
  DELETE FROM c_posts.post_reposts WHERE identity_id=NEW.identity_id;
 END IF;
 RETURN NEW;
END $$;
CREATE FUNCTION c_posts.clear_account_reposts() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
 IF NEW.state='CLOSED' AND OLD.state IS DISTINCT FROM NEW.state THEN
  DELETE FROM c_posts.post_reposts WHERE account_id=NEW.account_id;
  DELETE FROM c_posts.post_repost_versions WHERE account_id=NEW.account_id;
 END IF;
 RETURN NEW;
END $$;
-- +goose StatementEnd
CREATE TRIGGER identity_reposts_cleanup AFTER UPDATE ON public.community_identities
 FOR EACH ROW EXECUTE FUNCTION c_posts.clear_identity_reposts();
CREATE TRIGGER account_reposts_cleanup AFTER UPDATE ON c_auth.accounts
 FOR EACH ROW EXECUTE FUNCTION c_posts.clear_account_reposts();
REVOKE ALL ON c_posts.post_reposts,c_posts.post_repost_versions FROM PUBLIC;
REVOKE ALL ON SEQUENCE c_posts.post_reposts_ordinal_seq FROM PUBLIC;
REVOKE ALL ON FUNCTION c_posts.clear_identity_reposts(),c_posts.clear_account_reposts() FROM PUBLIC;
-- +goose Down
-- +goose StatementBegin
DO $$ BEGIN RAISE EXCEPTION '0026 preserves repost write fences; freeze and repair forward'; END $$;
-- +goose StatementEnd
