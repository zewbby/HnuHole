-- +goose Up
-- +goose StatementBegin
-- Follows the real 0016/0017 comments delivery; never mutates its receipts.
ALTER TABLE c_moderation.cases ADD COLUMN comment_id uuid;
ALTER TABLE c_comments.tasks ADD COLUMN moderation_hidden boolean NOT NULL DEFAULT false;
CREATE INDEX moderation_comment_cases ON c_moderation.cases(comment_id) WHERE comment_id IS NOT NULL;

-- Checked under final Gate together with the parent post. No cross-account FK
-- lock is taken after Gate; cases keep an immutable snapshot after deletion.
CREATE FUNCTION c_moderation.deleted_comment() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL THEN
  WITH ended AS (
   UPDATE c_moderation.cases SET state='ENDED',outcome='TARGET_DELETED',
    explanation='评论已删除，本次举报已结束',version=version+1
   WHERE comment_id=NEW.comment_id AND state<>'ENDED' RETURNING case_id
  )
  INSERT INTO c_moderation.notifications(notification_id,event_id,account_id,identity_id,kind,state,title,body,route_name,resource_id,created_at)
  SELECT gen_random_uuid(),'report:'||r.report_id||':deleted',r.reporter_account_id,r.identity_id,
   'REPORT_RESULT','ENDED','评论已删除，本次举报已结束','本次终结不代表举报成立，也不撤销已有处罚。',
   'REPORT',r.request_id,NEW.deleted_at FROM c_moderation.reports r JOIN ended e USING(case_id)
  WHERE r.reporter_account_id IS NOT NULL ON CONFLICT(account_id,event_id) DO NOTHING;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER moderation_comment_deleted AFTER UPDATE OF deleted_at ON c_comments.tasks
 FOR EACH ROW EXECUTE FUNCTION c_moderation.deleted_comment();

CREATE FUNCTION c_moderation.comment_publication_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_OP='INSERT' OR (OLD.state='ACCEPTED' AND NEW.state='PUBLISHED') THEN
  IF EXISTS(SELECT 1 FROM c_comments.tasks t JOIN c_comments.tasks p
   ON p.comment_id IN(t.root_comment_id,t.target_comment_id)
   WHERE t.task_id=NEW.task_id AND p.moderation_hidden) THEN
   RAISE EXCEPTION 'moderated comment target' USING ERRCODE='23514';
  END IF;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER moderation_comment_publication BEFORE INSERT OR UPDATE ON c_comments.attempts
 FOR EACH ROW EXECUTE FUNCTION c_moderation.comment_publication_guard();
REVOKE EXECUTE ON FUNCTION c_moderation.deleted_comment(),c_moderation.comment_publication_guard() FROM PUBLIC;
-- +goose StatementEnd
-- +goose Down
-- +goose StatementBegin
DO $$ BEGIN RAISE EXCEPTION 'comment report evidence and moderation facts require a forward repair'; END $$;
-- +goose StatementEnd
