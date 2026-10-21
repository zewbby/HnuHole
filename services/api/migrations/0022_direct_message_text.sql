-- +goose Up
CREATE SCHEMA c_dm;
CREATE TABLE c_dm.conversations (
    conversation_id uuid PRIMARY KEY,
    low_identity uuid NOT NULL REFERENCES public.community_identities(identity_id),
    high_identity uuid NOT NULL REFERENCES public.community_identities(identity_id),
    source_post uuid NOT NULL REFERENCES c_posts.posts(post_id),
    sequence bigint NOT NULL DEFAULT 0 CHECK(sequence >= 0),
    low_sent boolean NOT NULL DEFAULT false,
    high_sent boolean NOT NULL DEFAULT false,
    CHECK(low_identity < high_identity),
    UNIQUE(low_identity, high_identity)
);
-- Immutable intent receipt survives ACK/body deletion and retries. Account ids
-- stay inside C; no directory or public projection exposes them.
CREATE TABLE c_dm.commands (
    owner_account uuid NOT NULL REFERENCES c_auth.accounts(account_id),
    command_id uuid NOT NULL,
    fingerprint bytea NOT NULL CHECK(octet_length(fingerprint)=32),
    attempt integer NOT NULL CHECK(attempt > 0),
    state text NOT NULL CHECK(state IN ('SENT','FAILED')),
    error_code text NOT NULL DEFAULT '',
    message_id uuid,
    conversation_id uuid REFERENCES c_dm.conversations(conversation_id),
    sequence bigint,
    accepted_at timestamptz,
    PRIMARY KEY(owner_account, command_id)
);
-- Only pending content is retained. ACK removes body, retaining minimum unread
-- and deduplication metadata. No history endpoint and no TTL on pending text.
CREATE TABLE c_dm.messages (
    message_id uuid PRIMARY KEY,
    conversation_id uuid NOT NULL REFERENCES c_dm.conversations(conversation_id),
    sequence bigint NOT NULL CHECK(sequence > 0),
    sender uuid NOT NULL REFERENCES public.community_identities(identity_id),
    recipient uuid NOT NULL REFERENCES public.community_identities(identity_id),
    body text,
    accepted_at timestamptz NOT NULL,
    acknowledged boolean NOT NULL DEFAULT false,
    read boolean NOT NULL DEFAULT false,
    CHECK(sender <> recipient),
    CHECK((acknowledged AND body IS NULL) OR (NOT acknowledged AND body IS NOT NULL)),
    CHECK(NOT read OR acknowledged),
    UNIQUE(conversation_id, sequence)
);
CREATE INDEX dm_pending ON c_dm.messages(recipient, accepted_at, message_id) WHERE NOT acknowledged;
CREATE INDEX dm_unread ON c_dm.messages(recipient, conversation_id) WHERE NOT read;
CREATE TABLE c_dm.binding_acceptances (
    account_id uuid NOT NULL,
    post_id uuid NOT NULL,
    identity_id uuid NOT NULL,
    command_id uuid NOT NULL,
    bound_at timestamptz NOT NULL,
    PRIMARY KEY(account_id,post_id),
    FOREIGN KEY(account_id,command_id) REFERENCES c_dm.commands(owner_account,command_id) DEFERRABLE INITIALLY DEFERRED,
    FOREIGN KEY(account_id,post_id,identity_id) REFERENCES c_posts.post_identity_bindings(account_id,post_id,identity_id) DEFERRABLE INITIALLY DEFERRED
);
CREATE TRIGGER dm_binding_immutable BEFORE UPDATE OR DELETE ON c_dm.binding_acceptances
    FOR EACH ROW EXECUTE FUNCTION c_posts.guard_immutable();
-- +goose StatementBegin
CREATE OR REPLACE FUNCTION c_comments.check_acceptance() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_TABLE_SCHEMA='c_posts' THEN
  IF EXISTS(SELECT 1 FROM c_posts.posts WHERE post_id=NEW.post_id AND owner_account_id=NEW.account_id) THEN RETURN NULL; END IF;
  IF EXISTS(SELECT 1 FROM c_comments.tasks t JOIN c_comments.attempts a USING(task_id)
    JOIN c_comments.receipts r ON r.task_id=t.task_id AND r.version=a.version
    WHERE t.owner_account_id=NEW.account_id AND t.post_id=NEW.post_id AND t.identity_id=NEW.identity_id
      AND a.version=1 AND a.accepted_at=NEW.bound_at AND r.operation='CREATE' AND r.outcome='ACCEPTED') THEN RETURN NULL; END IF;
  IF NOT EXISTS(SELECT 1 FROM c_dm.binding_acceptances b
    JOIN c_dm.commands r ON r.owner_account=b.account_id AND r.command_id=b.command_id
    JOIN c_dm.messages m ON m.message_id=r.message_id AND m.sender=b.identity_id
    WHERE b.account_id=NEW.account_id AND b.post_id=NEW.post_id AND b.identity_id=NEW.identity_id
      AND b.bound_at=NEW.bound_at AND r.accepted_at=NEW.bound_at AND r.state='SENT') THEN
   RAISE EXCEPTION 'participant binding requires accepted content' USING ERRCODE='23514'; END IF;
 ELSE
  IF NOT EXISTS(SELECT 1 FROM c_comments.attempts a JOIN c_comments.receipts r USING(task_id)
    WHERE a.task_id=NEW.task_id AND a.version=1 AND r.version=1 AND r.owner_account_id=NEW.owner_account_id
      AND r.operation='CREATE' AND r.outcome='ACCEPTED') THEN
   RAISE EXCEPTION 'comment task requires first attempt and receipt' USING ERRCODE='23514'; END IF;
 END IF;
 RETURN NULL;
END $$;
-- +goose StatementEnd
REVOKE ALL ON SCHEMA c_dm FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA c_dm FROM PUBLIC;
-- +goose Down
-- +goose StatementBegin
DO $$ BEGIN
    RAISE EXCEPTION '0022 contains pending messages and permanent deduplication facts; repair forward';
END $$;
-- +goose StatementEnd
