-- +goose Up
-- +goose StatementBegin
-- C-only forward migration. No dependency on a future comment relation.
CREATE SCHEMA c_moderation;
CREATE TABLE c_moderation.schema_meta(singleton_id smallint PRIMARY KEY CHECK(singleton_id=1), version int NOT NULL CHECK(version=1));
INSERT INTO c_moderation.schema_meta VALUES(1,1);
-- Reuse the existing private six-digit number; no second mapping.
CREATE VIEW c_moderation.platform_numbers WITH (security_invoker=true) AS SELECT account_id,platform_number AS number FROM c_auth.accounts;
ALTER TABLE c_auth.accounts ADD COLUMN registered_at timestamptz;
ALTER TABLE c_auth.accounts ALTER COLUMN registered_at SET DEFAULT CURRENT_TIMESTAMP;
CREATE TABLE c_moderation.roles(account_id uuid PRIMARY KEY REFERENCES c_auth.accounts, role text NOT NULL CHECK(role IN('REVIEWER','ADMIN')));
CREATE TABLE c_moderation.access_sessions(token_digest bytea PRIMARY KEY CHECK(octet_length(token_digest)=32),account_id uuid NOT NULL REFERENCES c_auth.accounts,credential_version bigint NOT NULL,session_generation bigint NOT NULL,authorization_generation bigint NOT NULL,expires_at timestamptz NOT NULL,revoked_at timestamptz);
CREATE UNIQUE INDEX moderation_one_access ON c_moderation.access_sessions(account_id) WHERE revoked_at IS NULL;
ALTER TABLE c_posts.posts ADD COLUMN moderation_hidden boolean NOT NULL DEFAULT false;
ALTER TABLE public.community_identities ADD COLUMN moderation_rename_required boolean NOT NULL DEFAULT false;
CREATE TABLE c_moderation.legacy_restrictions AS SELECT account_id,ban_state,ban_ends_at,mute_state,mute_ends_at FROM c_auth.account_restrictions;
ALTER TABLE c_moderation.legacy_restrictions ADD PRIMARY KEY(account_id);
CREATE TABLE c_moderation.cases(
 case_id uuid PRIMARY KEY, number bigint GENERATED ALWAYS AS IDENTITY UNIQUE,
 -- Account/identity references here are checked under final Gate, without a
 -- cross-account FK KEY SHARE after Gate (closure holds these rows before Gate).
 post_id uuid NOT NULL REFERENCES c_posts.posts, target_account_id uuid NOT NULL, target_identity_id uuid NOT NULL,
 reason text NOT NULL CHECK(reason IN('ADVERTISING','HARASSMENT','PRIVACY','FRAUD','ILLEGAL','OTHER')), snapshot_digest text NOT NULL,
 evidence jsonb NOT NULL, state text NOT NULL DEFAULT 'PENDING' CHECK(state IN('PENDING','PROCESSING','ENDED')),
 version bigint NOT NULL DEFAULT 1 CHECK(version>0), created_at timestamptz NOT NULL,
 outcome text NOT NULL DEFAULT '', explanation text NOT NULL DEFAULT '', decided_by uuid,
 UNIQUE(post_id,snapshot_digest));
CREATE TABLE c_moderation.reports(
 report_id uuid PRIMARY KEY, request_id uuid NOT NULL, reporter_account_id uuid REFERENCES c_auth.accounts, identity_id uuid REFERENCES public.community_identities,
 case_id uuid NOT NULL REFERENCES c_moderation.cases, reason text NOT NULL CHECK(reason IN('ADVERTISING','HARASSMENT','PRIVACY','FRAUD','ILLEGAL','OTHER')), fingerprint text NOT NULL, description text NOT NULL, images jsonb NOT NULL,
 created_at timestamptz NOT NULL, UNIQUE(reporter_account_id,request_id));
CREATE TABLE c_moderation.sanctions(
 sanction_id uuid PRIMARY KEY, case_id uuid NOT NULL UNIQUE REFERENCES c_moderation.cases, account_id uuid NOT NULL REFERENCES c_auth.accounts,
 action text NOT NULL CHECK(action IN('TAKEDOWN','MUTE','BAN','RESET_NICKNAME','RESET_AVATAR')), reason text NOT NULL,
 starts_at timestamptz NOT NULL, ends_at timestamptz, revoked_at timestamptz, actor_id uuid NOT NULL REFERENCES c_auth.accounts,
 CHECK(ends_at IS NULL OR ends_at>starts_at));
CREATE TABLE c_moderation.appeals(
 appeal_id uuid PRIMARY KEY, sanction_id uuid NOT NULL REFERENCES c_moderation.sanctions, request_id uuid NOT NULL, fingerprint text NOT NULL,
 ordinal int NOT NULL CHECK(ordinal BETWEEN 1 AND 3), state text NOT NULL DEFAULT 'PENDING' CHECK(state IN('PENDING','ACCEPTED','REJECTED')),
 version bigint NOT NULL DEFAULT 1 CHECK(version>0), reason text NOT NULL DEFAULT '', created_at timestamptz NOT NULL,
 UNIQUE(sanction_id,request_id),UNIQUE(sanction_id,ordinal));
CREATE UNIQUE INDEX moderation_pending_appeal ON c_moderation.appeals(sanction_id) WHERE state='PENDING';
CREATE TABLE c_moderation.appeal_materials(appeal_id uuid NOT NULL REFERENCES c_moderation.appeals, request_id uuid NOT NULL, fingerprint text NOT NULL, description text NOT NULL, images jsonb NOT NULL, created_at timestamptz NOT NULL,PRIMARY KEY(appeal_id,request_id));
CREATE TABLE c_moderation.notifications(
 notification_id uuid PRIMARY KEY, event_id text NOT NULL, account_id uuid NOT NULL, identity_id uuid,
 kind text NOT NULL CHECK(kind IN('REPORT_PROGRESS','REPORT_RESULT','SANCTION','APPEAL_RESULT')), state text NOT NULL,title text NOT NULL,body text NOT NULL,
 route_name text NOT NULL CHECK(route_name IN('REPORT','SANCTION','APPEAL')), resource_id uuid NOT NULL,created_at timestamptz NOT NULL,read_at timestamptz,
 UNIQUE(account_id,event_id));
CREATE INDEX moderation_notification_feed ON c_moderation.notifications(account_id,created_at DESC,notification_id DESC);
CREATE TABLE c_moderation.commands(actor_id uuid NOT NULL REFERENCES c_auth.accounts,command_id uuid NOT NULL,fingerprint text NOT NULL,result jsonb NOT NULL,PRIMARY KEY(actor_id,command_id));
-- A result lookup without a committed receipt seals every earlier attempt.
-- The next explicit retry keeps the task ID and presents the latest retry token.
CREATE TABLE c_moderation.request_fences(account_id uuid NOT NULL REFERENCES c_auth.accounts,kind text NOT NULL CHECK(kind IN('REPORT','APPEAL','MATERIAL')),parent_id uuid NOT NULL,request_id uuid NOT NULL,retry_token uuid NOT NULL,PRIMARY KEY(account_id,kind,parent_id,request_id));
CREATE TABLE c_moderation.audit(audit_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,actor_number text NOT NULL,target_number text NOT NULL,case_id uuid REFERENCES c_moderation.cases,action text NOT NULL,reason text NOT NULL,created_at timestamptz NOT NULL);
CREATE FUNCTION c_moderation.immutable_audit() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'moderation audit is append only' USING ERRCODE='23514'; END $$;
CREATE TRIGGER moderation_audit_immutable BEFORE UPDATE OR DELETE ON c_moderation.audit FOR EACH ROW EXECUTE FUNCTION c_moderation.immutable_audit();
CREATE FUNCTION c_moderation.deleted_post() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF NEW.visibility='DELETED' AND OLD.visibility<>'DELETED' THEN
  WITH ended AS (UPDATE c_moderation.cases SET state='ENDED',outcome='TARGET_DELETED',explanation='内容已删除，本次举报已结束',version=version+1 WHERE post_id=NEW.post_id AND state<>'ENDED' RETURNING case_id)
  INSERT INTO c_moderation.notifications(notification_id,event_id,account_id,identity_id,kind,state,title,body,route_name,resource_id,created_at)
  SELECT gen_random_uuid(),'report:'||r.report_id||':deleted',r.reporter_account_id,r.identity_id,'REPORT_RESULT','ENDED','内容已删除，本次举报已结束','本次终结不代表举报成立，也不撤销已有处罚。','REPORT',r.request_id,NEW.deleted_at
  FROM c_moderation.reports r JOIN ended e USING(case_id) WHERE r.reporter_account_id IS NOT NULL ON CONFLICT(account_id,event_id) DO NOTHING;
 END IF; RETURN NEW;
END $$;
CREATE TRIGGER moderation_post_deleted AFTER UPDATE OF visibility ON c_posts.posts FOR EACH ROW EXECUTE FUNCTION c_moderation.deleted_post();
CREATE FUNCTION c_moderation.closed_account() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN IF NEW.state='CLOSED' AND OLD.state<>'CLOSED' THEN
 DELETE FROM c_moderation.notifications WHERE account_id=NEW.account_id;
 UPDATE c_moderation.reports SET reporter_account_id=NULL,identity_id=NULL WHERE reporter_account_id=NEW.account_id;
 DELETE FROM c_moderation.access_sessions WHERE account_id=NEW.account_id;
 DELETE FROM c_moderation.roles WHERE account_id=NEW.account_id;
 END IF;RETURN NEW;END $$;
CREATE TRIGGER moderation_account_closed AFTER UPDATE OF state ON c_auth.accounts FOR EACH ROW EXECUTE FUNCTION c_moderation.closed_account();
REVOKE ALL ON SCHEMA c_moderation FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA c_moderation FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA c_moderation FROM PUBLIC;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA c_moderation FROM PUBLIC;
-- +goose StatementEnd
-- +goose Down
-- irreversible: evidence, case decisions and audit must not be silently discarded.
-- +goose StatementBegin
DO $$ BEGIN RAISE EXCEPTION 'moderation facts cannot be rolled back; use an explicit forward repair'; END $$;
-- +goose StatementEnd
