-- +goose Up
-- +goose StatementBegin
ALTER TABLE c_comments.tasks ADD COLUMN deleted_at timestamptz;
ALTER TABLE c_comments.attempts DROP CONSTRAINT attempts_body_check;
ALTER TABLE c_comments.attempts ADD CONSTRAINT comment_text_budget CHECK(octet_length(body)<=65536);
ALTER TABLE c_comments.attempts ADD COLUMN image jsonb;
ALTER TABLE c_comments.attempts ADD CONSTRAINT comment_image_object CHECK(image IS NULL OR jsonb_typeof(image)='object');
ALTER TABLE c_comments.receipts ADD COLUMN comment_id uuid REFERENCES c_comments.tasks(comment_id);
ALTER TABLE c_comments.receipts ADD COLUMN deleted_count integer;
ALTER TABLE c_comments.receipts ADD COLUMN liked boolean;
ALTER TABLE c_comments.receipts ADD COLUMN like_count bigint;
DO $$ DECLARE c record; BEGIN
 FOR c IN SELECT conname FROM pg_constraint WHERE conrelid='c_comments.receipts'::regclass AND contype='c'
  AND (pg_get_constraintdef(oid) LIKE '%operation%' OR pg_get_constraintdef(oid) LIKE '%outcome%') LOOP
  EXECUTE format('ALTER TABLE c_comments.receipts DROP CONSTRAINT %I',c.conname);
 END LOOP;
END $$;
ALTER TABLE c_comments.receipts ADD CONSTRAINT comment_receipt_operation CHECK(operation IN ('CREATE','RETRY','ABANDON','DELETE','SET_LIKE'));
ALTER TABLE c_comments.receipts ADD CONSTRAINT comment_receipt_outcome CHECK(
 (outcome='ACCEPTED' AND operation IN ('CREATE','RETRY') AND task_id IS NOT NULL AND version IS NOT NULL AND version>0 AND error_code IS NULL AND comment_id IS NULL)
 OR (outcome='APPLIED' AND error_code IS NULL AND (
 (operation='ABANDON' AND task_id IS NOT NULL AND version IS NOT NULL AND version>0 AND comment_id IS NULL)
 OR (operation='DELETE' AND task_id IS NULL AND version IS NULL AND comment_id IS NOT NULL AND deleted_count IS NOT NULL AND deleted_count>0)
 OR (operation='SET_LIKE' AND task_id IS NULL AND version IS NULL AND comment_id IS NOT NULL AND liked IS NOT NULL AND like_count IS NOT NULL AND like_count>=0)))
 OR (outcome IN ('REJECTED','NOT_ACCEPTED') AND task_id IS NULL AND version IS NULL AND comment_id IS NULL AND error_code IS NOT NULL)
);
ALTER TABLE c_comments.receipts ADD CONSTRAINT comment_receipt_rejection CHECK(
 (outcome<>'NOT_ACCEPTED' OR error_code='SEALED') AND
 (outcome<>'REJECTED' OR error_code IN('INVALID_CONTENT','IDENTITY_UNAVAILABLE','TARGET_UNAVAILABLE','PERMISSION_DENIED','STALE_ATTEMPT','TASK_NOT_FAILED')));
ALTER TABLE c_comments.receipts ADD CONSTRAINT comment_receipt_extra_fields CHECK(
 (operation='DELETE' AND outcome='APPLIED' OR deleted_count IS NULL) AND
 (operation='SET_LIKE' AND outcome='APPLIED' OR liked IS NULL AND like_count IS NULL));
CREATE TABLE c_comments.likes(
 account_id uuid NOT NULL REFERENCES c_auth.accounts(account_id),
 comment_id uuid NOT NULL REFERENCES c_comments.tasks(comment_id),
 PRIMARY KEY(account_id,comment_id)
);
CREATE TABLE c_comments.images(
 task_id uuid NOT NULL,version integer NOT NULL,
 content_version_id uuid NOT NULL UNIQUE,
 payload bytea,metadata jsonb,erased_at timestamptz,
 PRIMARY KEY(task_id,version),FOREIGN KEY(task_id,version) REFERENCES c_comments.attempts(task_id,version),
 CHECK(payload IS NULL OR octet_length(payload) BETWEEN 1 AND 10485760),
 CHECK((payload IS NULL AND metadata IS NULL) OR (payload IS NOT NULL AND metadata IS NOT NULL AND erased_at IS NULL))
);
CREATE FUNCTION c_comments.business_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE t c_comments.tasks%ROWTYPE; a c_comments.attempts%ROWTYPE;
BEGIN
 IF TG_TABLE_NAME='tasks' THEN
  IF OLD.deleted_at IS NOT NULL AND NEW.deleted_at IS DISTINCT FROM OLD.deleted_at THEN
   RAISE EXCEPTION 'comment deletion is permanent' USING ERRCODE='23514'; END IF;
 ELSIF TG_TABLE_NAME='attempts' THEN
  IF TG_OP='UPDATE' AND NEW.image IS DISTINCT FROM OLD.image THEN
   RAISE EXCEPTION 'accepted image is immutable' USING ERRCODE='23514'; END IF;
  SELECT * INTO STRICT t FROM c_comments.tasks WHERE task_id=NEW.task_id;
  IF TG_OP='INSERT' OR (OLD.state='ACCEPTED' AND NEW.state='PUBLISHED') THEN
   IF t.deleted_at IS NOT NULL OR EXISTS(SELECT 1 FROM c_comments.tasks WHERE comment_id IN(t.root_comment_id,t.target_comment_id) AND deleted_at IS NOT NULL) THEN
    RAISE EXCEPTION 'deleted comment target' USING ERRCODE='23514'; END IF;
   IF length(NEW.body)=0 AND NEW.image IS NULL THEN RAISE EXCEPTION 'empty comment' USING ERRCODE='23514'; END IF;
   IF NEW.state='PUBLISHED' AND NEW.image IS NOT NULL AND NOT EXISTS(SELECT 1 FROM c_comments.images WHERE task_id=NEW.task_id AND version=NEW.version AND payload IS NOT NULL AND erased_at IS NULL) THEN
    RAISE EXCEPTION 'verified original required' USING ERRCODE='23514'; END IF;
  END IF;
 ELSIF TG_TABLE_NAME='images' THEN
  IF TG_OP='DELETE' THEN RAISE EXCEPTION 'permanent media fact' USING ERRCODE='23514'; END IF;
  SELECT * INTO STRICT t FROM c_comments.tasks WHERE task_id=NEW.task_id;
  SELECT * INTO STRICT a FROM c_comments.attempts WHERE task_id=NEW.task_id AND version=NEW.version;
  IF TG_OP='UPDATE' AND ((NEW.task_id,NEW.version,NEW.content_version_id) IS DISTINCT FROM (OLD.task_id,OLD.version,OLD.content_version_id)
   OR OLD.erased_at IS NOT NULL AND NEW IS DISTINCT FROM OLD
   OR OLD.payload IS NOT NULL AND (NEW.payload,NEW.metadata) IS DISTINCT FROM (OLD.payload,OLD.metadata) AND NEW.erased_at IS NULL) THEN
   RAISE EXCEPTION 'immutable original' USING ERRCODE='23514'; END IF;
  IF NEW.payload IS NOT NULL AND (a.image IS NULL OR a.state<>'ACCEPTED' OR t.deleted_at IS NOT NULL
   OR NOT t.owner_visible
   OR NOT EXISTS(SELECT 1 FROM public.community_identities WHERE identity_id=t.identity_id AND deleted_at IS NULL)
   OR NOT EXISTS(SELECT 1 FROM c_posts.account_publication_control c WHERE c.account_id=t.owner_account_id AND c.stop_generation=a.accepted_stop_generation)
   OR (NEW.metadata->>'sha256') IS DISTINCT FROM a.image->>'sha256'
   OR encode(sha256(NEW.payload),'hex') IS DISTINCT FROM a.image->>'sha256'
   OR NEW.metadata->>'mimeType' IS DISTINCT FROM a.image->>'mimeType'
   OR NEW.metadata->>'width' IS DISTINCT FROM a.image->>'width'
   OR NEW.metadata->>'height' IS DISTINCT FROM a.image->>'height'
   OR octet_length(NEW.payload) IS DISTINCT FROM (a.image->>'byteLength')::integer) THEN
   RAISE EXCEPTION 'media binding mismatch' USING ERRCODE='23514'; END IF;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER comment_delete_monotonic BEFORE UPDATE ON c_comments.tasks FOR EACH ROW EXECUTE FUNCTION c_comments.business_guard();
CREATE TRIGGER comment_media_attempt BEFORE INSERT OR UPDATE ON c_comments.attempts FOR EACH ROW EXECUTE FUNCTION c_comments.business_guard();
CREATE TRIGGER comment_original_guard BEFORE INSERT OR UPDATE OR DELETE ON c_comments.images FOR EACH ROW EXECUTE FUNCTION c_comments.business_guard();

ALTER TABLE c_moderation.notifications DROP CONSTRAINT notifications_kind_check;
ALTER TABLE c_moderation.notifications DROP CONSTRAINT notifications_route_name_check;
ALTER TABLE c_moderation.notifications ADD CONSTRAINT notifications_kind_check CHECK(kind IN('REPORT_PROGRESS','REPORT_RESULT','SANCTION','APPEAL_RESULT','COMMENT_FAILURE'));
ALTER TABLE c_moderation.notifications ADD CONSTRAINT notifications_route_name_check CHECK(route_name IN('REPORT','SANCTION','APPEAL','COMMENT_FAILURE'));
CREATE FUNCTION c_comments.sync_failure_notice() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE t c_comments.tasks%ROWTYPE; a c_comments.attempts%ROWTYPE;
BEGIN
 SELECT * INTO t FROM c_comments.tasks WHERE task_id=NEW.task_id;
 SELECT * INTO a FROM c_comments.attempts WHERE task_id=NEW.task_id ORDER BY version DESC LIMIT 1;
 -- Same permanent event per task; retry/publication/abandon deletes its entry.
 IF a.state<>'FAILED' OR NOT t.owner_visible OR t.abandoned_at IS NOT NULL OR t.deleted_at IS NOT NULL THEN
 DELETE FROM c_moderation.notifications WHERE account_id=t.owner_account_id AND event_id='comment-failure:'||t.task_id::text;
 END IF;
 IF a.state='FAILED' AND t.owner_visible AND t.abandoned_at IS NULL AND t.deleted_at IS NULL
  AND EXISTS(SELECT 1 FROM public.community_identities WHERE identity_id=t.identity_id AND deleted_at IS NULL) THEN
  INSERT INTO c_moderation.notifications(notification_id,event_id,account_id,identity_id,kind,state,title,body,route_name,resource_id,created_at)
  VALUES(gen_random_uuid(),'comment-failure:'||t.task_id::text,t.owner_account_id,t.identity_id,'COMMENT_FAILURE','FAILED','评论发送失败','保留原身份与回复对象，请进入处理。','COMMENT_FAILURE',t.task_id,a.terminal_at) ON CONFLICT(account_id,event_id) DO NOTHING;
 END IF;
 IF (TG_TABLE_NAME='tasks' AND (NOT t.owner_visible OR t.deleted_at IS NOT NULL)) OR a.state IN('FAILED') THEN
  -- Failed bytes remain in the submitted local journal for explicit retry;
  -- no failed upload capability or temporary server payload survives.
  UPDATE c_comments.images SET payload=NULL,metadata=NULL,erased_at=COALESCE(t.deleted_at,t.abandoned_at,a.terminal_at,clock_timestamp())
   WHERE task_id=t.task_id AND (t.deleted_at IS NOT NULL OR version=a.version AND a.state<>'PUBLISHED') AND erased_at IS NULL;
 END IF;
 RETURN NULL;
END $$;
CREATE TRIGGER comment_failure_notice AFTER INSERT OR UPDATE ON c_comments.attempts FOR EACH ROW EXECUTE FUNCTION c_comments.sync_failure_notice();
CREATE TRIGGER comment_task_notice AFTER UPDATE ON c_comments.tasks FOR EACH ROW EXECUTE FUNCTION c_comments.sync_failure_notice();
CREATE FUNCTION c_comments.post_deleted_hook() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF NEW.visibility<>'PUBLISHED' THEN
  UPDATE c_comments.images m SET payload=NULL,metadata=NULL,erased_at=clock_timestamp()
   FROM c_comments.tasks t WHERE t.task_id=m.task_id AND t.post_id=NEW.post_id AND m.erased_at IS NULL;
 END IF;
 RETURN NULL;
END $$;
CREATE TRIGGER comment_post_deleted AFTER UPDATE OF visibility ON c_posts.posts
 FOR EACH ROW EXECUTE FUNCTION c_comments.post_deleted_hook();
REVOKE ALL ON c_comments.likes,c_comments.images FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA c_comments FROM PUBLIC;
-- +goose StatementEnd
-- +goose Down
-- +goose StatementBegin
DO $$ BEGIN RAISE EXCEPTION 'comment business facts require forward repair'; END $$;
-- +goose StatementEnd
