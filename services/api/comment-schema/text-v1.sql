-- Pending ordered migration body. Component lab ONLY until governance 0015 is
-- merged and the real main migration chain can assign/validate the next number.
-- This file does NOT advance goose_db_version and must not be used as a deploy shortcut.
CREATE SCHEMA c_comments;
REVOKE ALL ON SCHEMA c_comments FROM PUBLIC;

-- A participant's fixed identity belongs to that account, not the post author.
-- Keep the original immutable binding trigger and the account/identity FK.
ALTER TABLE c_posts.post_identity_bindings DROP CONSTRAINT post_identity_bindings_account_id_post_id_fkey;
ALTER TABLE c_posts.post_identity_bindings ADD CONSTRAINT comment_binding_post_fk
    FOREIGN KEY(post_id) REFERENCES c_posts.posts(post_id);

CREATE TABLE c_comments.protocol_keys (
    singleton_id integer PRIMARY KEY CHECK(singleton_id=1),
    command_tag bytea NOT NULL CHECK(octet_length(command_tag)=32),
    fingerprint_tag bytea NOT NULL CHECK(octet_length(fingerprint_tag)=32)
);
CREATE TABLE c_comments.tasks (
    task_id uuid PRIMARY KEY,
    comment_id uuid NOT NULL UNIQUE,
    owner_account_id uuid NOT NULL REFERENCES c_auth.accounts(account_id),
    post_id uuid NOT NULL REFERENCES c_posts.posts(post_id),
    identity_id uuid NOT NULL,
    root_comment_id uuid REFERENCES c_comments.tasks(comment_id),
    target_comment_id uuid REFERENCES c_comments.tasks(comment_id),
    owner_visible boolean NOT NULL DEFAULT true,
    abandoned_at timestamptz,
    UNIQUE(owner_account_id,task_id),
    CHECK((root_comment_id IS NULL)=(target_comment_id IS NULL)),
    CHECK(comment_id<>root_comment_id AND comment_id<>target_comment_id),
    CHECK(abandoned_at IS NULL OR NOT owner_visible),
    FOREIGN KEY(owner_account_id,post_id,identity_id)
      REFERENCES c_posts.post_identity_bindings(account_id,post_id,identity_id)
);
CREATE INDEX comment_task_owner ON c_comments.tasks(owner_account_id,task_id);
CREATE INDEX comment_task_thread ON c_comments.tasks(post_id,root_comment_id);
CREATE TABLE c_comments.attempts (
    task_id uuid NOT NULL REFERENCES c_comments.tasks(task_id),
    version integer NOT NULL CHECK(version>0),
    state text NOT NULL CHECK(state IN ('ACCEPTED','FAILED','PUBLISHED')),
    accepted_at timestamptz NOT NULL,
    accepted_stop_generation bigint NOT NULL CHECK(accepted_stop_generation>=0),
    terminal_at timestamptz,
    failure_code text,
    body text CHECK(octet_length(body)<=65536 AND length(body)>0),
    PRIMARY KEY(task_id,version),
    CHECK((state='ACCEPTED' AND terminal_at IS NULL AND failure_code IS NULL AND body IS NOT NULL)
       OR (state='PUBLISHED' AND terminal_at IS NOT NULL AND terminal_at>=accepted_at AND failure_code IS NULL AND body IS NOT NULL)
       OR (state='FAILED' AND terminal_at IS NOT NULL AND terminal_at>=accepted_at AND failure_code IS NOT NULL AND failure_code IN
       ('PUBLICATION_FAILED','PUBLISHING_STOPPED','IDENTITY_INACTIVE','COMMENT_TARGET_DELETED','POST_UNAVAILABLE')))
);
CREATE UNIQUE INDEX comment_one_published ON c_comments.attempts(task_id) WHERE state='PUBLISHED';
CREATE INDEX comment_pending ON c_comments.attempts(accepted_at,task_id) WHERE state='ACCEPTED';
CREATE TABLE c_comments.receipts (
    key_digest bytea PRIMARY KEY CHECK(octet_length(key_digest)=32),
    owner_account_id uuid NOT NULL REFERENCES c_auth.accounts(account_id),
    intent_fingerprint bytea NOT NULL CHECK(octet_length(intent_fingerprint)=32),
    operation text NOT NULL CHECK(operation IN ('CREATE','RETRY','ABANDON')),
    outcome text NOT NULL CHECK(outcome IN ('ACCEPTED','APPLIED','REJECTED','NOT_ACCEPTED')),
    task_id uuid REFERENCES c_comments.tasks(task_id),
    version integer,
    error_code text,
    committed_at timestamptz NOT NULL,
    FOREIGN KEY(owner_account_id,task_id) REFERENCES c_comments.tasks(owner_account_id,task_id),
    FOREIGN KEY(task_id,version) REFERENCES c_comments.attempts(task_id,version),
    CHECK((outcome IN ('ACCEPTED','APPLIED') AND task_id IS NOT NULL AND version>0 AND error_code IS NULL)
       OR (outcome IN ('REJECTED','NOT_ACCEPTED') AND task_id IS NULL AND version IS NULL AND error_code IS NOT NULL)),
    CHECK(outcome<>'ACCEPTED' OR operation IN ('CREATE','RETRY')),
    CHECK(outcome<>'APPLIED' OR operation='ABANDON'),
    CHECK(outcome<>'NOT_ACCEPTED' OR error_code='SEALED')
);
CREATE INDEX comment_receipt_budget ON c_comments.receipts(owner_account_id,committed_at);
CREATE TABLE c_comments.snapshots (
 snapshot_id uuid PRIMARY KEY,
 owner_account_id uuid NOT NULL REFERENCES c_auth.accounts(account_id),
 post_id uuid NOT NULL REFERENCES c_posts.posts(post_id),
 root_comment_id uuid,
 comment_ids uuid[] NOT NULL,
 expires_at timestamptz NOT NULL
);
CREATE INDEX comment_snapshot_expiry ON c_comments.snapshots(expires_at);

CREATE TRIGGER comment_keys_immutable BEFORE UPDATE OR DELETE ON c_comments.protocol_keys
 FOR EACH ROW EXECUTE FUNCTION c_posts.guard_immutable();
CREATE TRIGGER comment_receipt_immutable BEFORE UPDATE OR DELETE ON c_comments.receipts
 FOR EACH ROW EXECUTE FUNCTION c_posts.guard_immutable();

CREATE FUNCTION c_comments.guard_task() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_OP='DELETE' OR (NEW.task_id,NEW.comment_id,NEW.owner_account_id,NEW.post_id,NEW.identity_id,NEW.root_comment_id,NEW.target_comment_id)
 IS DISTINCT FROM (OLD.task_id,OLD.comment_id,OLD.owner_account_id,OLD.post_id,OLD.identity_id,OLD.root_comment_id,OLD.target_comment_id)
 OR (NOT OLD.owner_visible AND NEW.owner_visible)
 OR (OLD.abandoned_at IS NOT NULL AND NEW.abandoned_at IS DISTINCT FROM OLD.abandoned_at) THEN
 RAISE EXCEPTION 'immutable comment binding' USING ERRCODE='23514'; END IF;
 IF NEW.abandoned_at IS NOT NULL AND (NOT EXISTS(SELECT 1 FROM c_comments.attempts WHERE task_id=NEW.task_id AND state='FAILED')
 OR EXISTS(SELECT 1 FROM c_comments.attempts WHERE task_id=NEW.task_id AND state IN ('PUBLISHED','ACCEPTED'))) THEN
 RAISE EXCEPTION 'only failed tasks can be abandoned' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER comment_task_guard BEFORE UPDATE OR DELETE ON c_comments.tasks FOR EACH ROW EXECUTE FUNCTION c_comments.guard_task();

CREATE FUNCTION c_comments.guard_attempt() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE t c_comments.tasks%ROWTYPE; p c_comments.tasks%ROWTYPE; latest c_comments.attempts%ROWTYPE; generation bigint;
BEGIN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'permanent attempt' USING ERRCODE='23514'; END IF;
 SELECT * INTO STRICT t FROM c_comments.tasks WHERE task_id=NEW.task_id;
 IF TG_OP='INSERT' THEN
  SELECT * INTO latest FROM c_comments.attempts WHERE task_id=NEW.task_id ORDER BY version DESC LIMIT 1;
  IF NEW.state<>'ACCEPTED' OR NEW.body IS NULL OR t.abandoned_at IS NOT NULL OR NOT t.owner_visible
   OR NEW.version<>COALESCE(latest.version,0)+1 OR (latest.version IS NOT NULL AND latest.state<>'FAILED')
   OR latest.failure_code IN ('IDENTITY_INACTIVE','COMMENT_TARGET_DELETED','POST_UNAVAILABLE')
   OR NEW.accepted_at<latest.terminal_at THEN
   RAISE EXCEPTION 'invalid comment acceptance' USING ERRCODE='23514'; END IF;
 ELSE
  IF (NEW.task_id,NEW.version,NEW.accepted_at,NEW.accepted_stop_generation) IS DISTINCT FROM
    (OLD.task_id,OLD.version,OLD.accepted_at,OLD.accepted_stop_generation)
   OR (NEW.body IS DISTINCT FROM OLD.body AND (NEW.body IS NOT NULL OR t.owner_visible))
   OR (OLD.state<>'ACCEPTED' AND (NEW.state,NEW.terminal_at,NEW.failure_code) IS DISTINCT FROM (OLD.state,OLD.terminal_at,OLD.failure_code))
   OR (OLD.state='ACCEPTED' AND NEW.state='ACCEPTED' AND NEW IS DISTINCT FROM OLD) THEN
   RAISE EXCEPTION 'immutable comment attempt' USING ERRCODE='23514'; END IF;
 END IF;
 IF TG_OP='INSERT' OR NEW.state='PUBLISHED' THEN
  SELECT stop_generation INTO STRICT generation FROM c_posts.account_publication_control WHERE account_id=t.owner_account_id;
  IF NEW.accepted_stop_generation<>generation OR NOT EXISTS(SELECT 1 FROM c_auth.accounts WHERE account_id=t.owner_account_id AND state='ACTIVE')
   OR NOT EXISTS(SELECT 1 FROM public.community_identities WHERE identity_id=t.identity_id AND deleted_at IS NULL)
   OR NOT EXISTS(SELECT 1 FROM c_posts.posts WHERE post_id=t.post_id AND visibility='PUBLISHED') THEN
   RAISE EXCEPTION 'publication unavailable' USING ERRCODE='23514'; END IF;
  IF t.root_comment_id IS NOT NULL THEN
   SELECT * INTO p FROM c_comments.tasks WHERE comment_id=t.root_comment_id;
   IF p.post_id IS DISTINCT FROM t.post_id OR p.root_comment_id IS NOT NULL
    OR NOT EXISTS(SELECT 1 FROM c_comments.attempts WHERE task_id=p.task_id AND state='PUBLISHED') THEN
    RAISE EXCEPTION 'invalid root' USING ERRCODE='23514'; END IF;
   SELECT * INTO p FROM c_comments.tasks WHERE comment_id=t.target_comment_id;
   IF p.post_id IS DISTINCT FROM t.post_id OR COALESCE(p.root_comment_id,p.comment_id) IS DISTINCT FROM t.root_comment_id
    OR NOT EXISTS(SELECT 1 FROM c_comments.attempts WHERE task_id=p.task_id AND state='PUBLISHED') THEN
    RAISE EXCEPTION 'invalid target' USING ERRCODE='23514'; END IF;
  END IF;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER comment_attempt_guard BEFORE INSERT OR UPDATE OR DELETE ON c_comments.attempts FOR EACH ROW EXECUTE FUNCTION c_comments.guard_attempt();

-- Existing lifecycle transactions emit these permanent stop events; comments
-- share their generation and never use session expiry to stop accepted work.
CREATE FUNCTION c_comments.stop_hook() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 UPDATE c_comments.attempts a SET state='FAILED',terminal_at=NEW.stopped_at,failure_code='PUBLISHING_STOPPED'
 FROM c_comments.tasks t WHERE t.task_id=a.task_id AND t.owner_account_id=NEW.account_id
 AND a.state='ACCEPTED' AND a.accepted_stop_generation<NEW.generation;
 IF NEW.cause='ACCOUNT_CLOSED' THEN
  UPDATE c_comments.tasks SET owner_visible=false WHERE owner_account_id=NEW.account_id;
  UPDATE c_comments.attempts a SET body=NULL FROM c_comments.tasks t WHERE t.task_id=a.task_id AND t.owner_account_id=NEW.account_id AND a.state<>'PUBLISHED';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER comment_stop_hook AFTER INSERT ON c_posts.publication_stop_events FOR EACH ROW EXECUTE FUNCTION c_comments.stop_hook();
CREATE FUNCTION c_comments.identity_hook() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL THEN
  UPDATE c_comments.attempts SET state='FAILED',terminal_at=NEW.deleted_at,failure_code='IDENTITY_INACTIVE'
  WHERE state='ACCEPTED' AND task_id IN (SELECT task_id FROM c_comments.tasks WHERE identity_id=NEW.identity_id);
  UPDATE c_comments.tasks SET owner_visible=false WHERE identity_id=NEW.identity_id;
  UPDATE c_comments.attempts SET body=NULL WHERE state<>'PUBLISHED' AND task_id IN (SELECT task_id FROM c_comments.tasks WHERE identity_id=NEW.identity_id);
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER comment_identity_hook AFTER UPDATE ON public.community_identities FOR EACH ROW EXECUTE FUNCTION c_comments.identity_hook();
REVOKE ALL ON ALL TABLES IN SCHEMA c_comments FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA c_comments FROM PUBLIC;
