-- +goose Up
-- Notifications are private recipient facts; never a voter directory.
CREATE SCHEMA c_inbox;
CREATE TABLE c_inbox.records (
 notification_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 account_id uuid NOT NULL REFERENCES c_auth.accounts(account_id),
 identity_id uuid NOT NULL REFERENCES public.community_identities(identity_id),
 post_id uuid NOT NULL REFERENCES c_posts.posts(post_id),
 comment_id uuid REFERENCES c_comments.tasks(comment_id),
 content_id uuid NOT NULL,
 kind text NOT NULL CHECK(kind IN('COMMENT','LIKE_POST','LIKE_COMMENT')),
 is_reply boolean NOT NULL DEFAULT false,
 version bigint NOT NULL DEFAULT 1 CHECK(version>0),
 read_version bigint NOT NULL DEFAULT 0 CHECK(read_version>=0 AND read_version<=version),
 seen_like_count bigint NOT NULL DEFAULT 0 CHECK(seen_like_count>=0),
 created_at timestamptz NOT NULL,
 updated_at timestamptz NOT NULL,
 UNIQUE(account_id,identity_id,kind,content_id),
 CHECK(kind<>'COMMENT' OR comment_id=content_id AND is_reply)
);
CREATE INDEX inbox_identity_order ON c_inbox.records(account_id,identity_id,updated_at DESC,notification_id DESC);
CREATE TABLE c_inbox.like_events (
 notification_id uuid NOT NULL REFERENCES c_inbox.records(notification_id) ON DELETE CASCADE,
 liker_account_id uuid NOT NULL REFERENCES c_auth.accounts(account_id),
 version bigint NOT NULL CHECK(version>0),
 PRIMARY KEY(notification_id,liker_account_id),
 UNIQUE(notification_id,version)
);
-- +goose StatementBegin
CREATE FUNCTION c_inbox.comment_published() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t c_comments.tasks%ROWTYPE; recipient_identity uuid; recipient_account uuid;
BEGIN
 IF NEW.state<>'PUBLISHED' OR (TG_OP='UPDATE' AND OLD.state='PUBLISHED') THEN RETURN NULL; END IF;
 SELECT * INTO STRICT t FROM c_comments.tasks WHERE task_id=NEW.task_id;
 IF t.target_comment_id IS NULL THEN
  SELECT identity_id INTO recipient_identity FROM c_posts.publication_tasks WHERE post_id=t.post_id;
 ELSE
  SELECT identity_id INTO recipient_identity FROM c_comments.tasks WHERE comment_id=t.target_comment_id;
 END IF;
 SELECT i.account_id INTO recipient_account FROM public.community_identities i JOIN c_auth.accounts a USING(account_id)
 WHERE i.identity_id=recipient_identity AND i.deleted_at IS NULL AND a.state='ACTIVE';
 IF recipient_account IS NULL OR recipient_account=t.owner_account_id THEN RETURN NULL; END IF;
 INSERT INTO c_inbox.records(account_id,identity_id,post_id,comment_id,content_id,kind,is_reply,created_at,updated_at)
 VALUES(recipient_account,recipient_identity,t.post_id,t.comment_id,t.comment_id,'COMMENT',true,NEW.terminal_at,NEW.terminal_at)
 ON CONFLICT(account_id,identity_id,kind,content_id) DO NOTHING;
 RETURN NULL;
END $$;
CREATE TRIGGER inbox_comment_published AFTER INSERT OR UPDATE OF state ON c_comments.attempts
 FOR EACH ROW EXECUTE FUNCTION c_inbox.comment_published();

CREATE FUNCTION c_inbox.like_changed() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE actor uuid; content uuid; post uuid; owner_id uuid; identity uuid; kind_name text; notice uuid; next_version bigint; at_time timestamptz;
BEGIN
 IF TG_OP='DELETE' THEN actor=OLD.account_id; ELSE actor=NEW.account_id; END IF;
 IF TG_TABLE_SCHEMA='c_posts' THEN
  kind_name='LIKE_POST';
  IF TG_OP='DELETE' THEN content=OLD.post_id; ELSE content=NEW.post_id; END IF;
  SELECT p.post_id,p.owner_account_id,t.identity_id INTO post,owner_id,identity
   FROM c_posts.posts p JOIN c_posts.publication_tasks t USING(post_id) WHERE p.post_id=content;
 ELSE
  kind_name='LIKE_COMMENT';
  IF TG_OP='DELETE' THEN content=OLD.comment_id; ELSE content=NEW.comment_id; END IF;
  SELECT t.post_id,t.owner_account_id,t.identity_id INTO post,owner_id,identity FROM c_comments.tasks t WHERE t.comment_id=content;
 END IF;
 IF owner_id IS NULL OR actor=owner_id THEN RETURN NULL; END IF;
 IF TG_OP='DELETE' THEN
  DELETE FROM c_inbox.like_events e USING c_inbox.records n WHERE e.notification_id=n.notification_id
   AND n.account_id=owner_id AND n.kind=kind_name AND n.content_id=content AND e.liker_account_id=actor;
  RETURN NULL;
 END IF;
 IF NOT EXISTS(SELECT 1 FROM public.community_identities i JOIN c_auth.accounts a USING(account_id)
  WHERE i.identity_id=identity AND i.deleted_at IS NULL AND a.state='ACTIVE') THEN RETURN NULL; END IF;
 at_time=clock_timestamp();
 INSERT INTO c_inbox.records(account_id,identity_id,post_id,comment_id,content_id,kind,created_at,updated_at)
  VALUES(owner_id,identity,post,CASE WHEN kind_name='LIKE_COMMENT' THEN content END,content,kind_name,at_time,at_time)
  ON CONFLICT(account_id,identity_id,kind,content_id) DO UPDATE SET version=c_inbox.records.version+1,updated_at=EXCLUDED.updated_at
  RETURNING notification_id,version INTO notice,next_version;
 INSERT INTO c_inbox.like_events VALUES(notice,actor,next_version);
 RETURN NULL;
END $$;
CREATE TRIGGER inbox_post_likes AFTER INSERT OR DELETE ON c_posts.post_likes FOR EACH ROW EXECUTE FUNCTION c_inbox.like_changed();
CREATE TRIGGER inbox_comment_likes AFTER INSERT OR DELETE ON c_comments.likes FOR EACH ROW EXECUTE FUNCTION c_inbox.like_changed();

CREATE FUNCTION c_inbox.account_closed() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 IF NEW.state='CLOSED' AND OLD.state IS DISTINCT FROM NEW.state THEN
  DELETE FROM c_comments.likes WHERE account_id=NEW.account_id;
  DELETE FROM c_inbox.like_events WHERE liker_account_id=NEW.account_id;
  DELETE FROM c_inbox.records WHERE account_id=NEW.account_id;
 END IF;
 RETURN NULL;
END $$;
CREATE TRIGGER inbox_account_closed AFTER UPDATE OF state ON c_auth.accounts FOR EACH ROW EXECUTE FUNCTION c_inbox.account_closed();
REVOKE ALL ON SCHEMA c_inbox FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA c_inbox FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA c_inbox FROM PUBLIC;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname='hnuhole_c_runtime') THEN
  GRANT USAGE ON SCHEMA c_inbox TO hnuhole_c_runtime;
  GRANT SELECT ON c_inbox.records,c_inbox.like_events TO hnuhole_c_runtime;
  GRANT UPDATE(read_version,seen_like_count) ON c_inbox.records TO hnuhole_c_runtime;
  GRANT UPDATE(read_at) ON c_moderation.notifications TO hnuhole_c_runtime;
 END IF;
END $$;
-- +goose StatementEnd
-- +goose Down
-- +goose StatementBegin
DO $$ BEGIN RAISE EXCEPTION 'notification facts require forward repair'; END $$;
-- +goose StatementEnd
