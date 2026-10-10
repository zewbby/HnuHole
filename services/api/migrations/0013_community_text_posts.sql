-- +goose Up
-- +goose StatementBegin
-- 文字发布事实与命令回执只落在 C；迁移由独立 owner 执行。
-- 此迁移不可回滚删除：绑定、回执、身份编号都是永久事实。
CREATE SCHEMA c_posts;

CREATE TABLE c_posts.schema_meta (
    singleton_id smallint PRIMARY KEY CHECK (singleton_id=1),
    version integer NOT NULL CHECK (version=1),
    hooks_version integer NOT NULL CHECK (hooks_version=1)
);
INSERT INTO c_posts.schema_meta VALUES (1,1,1);
-- 持久绑定命令域与意图指纹的用途密钥，不保存用途密钥本身。
-- 更换命令域密钥必须前向修复，不能让旧命令变成可重执行的新命令。
CREATE TABLE c_posts.protocol_keys (
    singleton_id smallint PRIMARY KEY CHECK (singleton_id=1),
    version integer NOT NULL CHECK (version=1),
    command_tag bytea NOT NULL CHECK (octet_length(command_tag)=32),
    fingerprint_tag bytea NOT NULL CHECK (octet_length(fingerprint_tag)=32)
);

CREATE SEQUENCE c_posts.publication_ordinal_seq AS bigint NO CYCLE;
CREATE SEQUENCE c_posts.acceptance_ordinal_seq AS bigint NO CYCLE;

CREATE TABLE c_posts.identity_public_labels (
    identity_id uuid PRIMARY KEY REFERENCES public.community_identities(identity_id),
    short_code text COLLATE "C" NOT NULL UNIQUE CHECK (short_code ~ '^[A-Z2-7]{12}$')
);

-- 从 PostgreSQL 的密码学 UUID 随机源选取没有 version/variant 固定位的 60 bits。
-- 不截取身份 UUID，也不通过账号或关闭事件派生；碰撞只重新生成标签。
CREATE FUNCTION c_posts.allocate_identity_label(selected_identity uuid) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
    entropy bytea;
    alphabet constant text := 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    code text;
    part integer;
    bit_index integer;
    character_index integer;
BEGIN
    IF EXISTS (SELECT 1 FROM c_posts.identity_public_labels WHERE identity_id=selected_identity) THEN
        RETURN;
    END IF;
    LOOP
        entropy := uuid_send(pg_catalog.gen_random_uuid());
        entropy := substring(entropy FROM 1 FOR 6) || substring(entropy FROM 15 FOR 2);
        code := '';
        FOR character_index IN 0..11 LOOP
            part := 0;
            FOR bit_index IN 0..4 LOOP
                part := (part << 1) | ((get_byte(entropy,(character_index*5+bit_index)/8)
                    >> (7-((character_index*5+bit_index)%8))) & 1);
            END LOOP;
            code := code || substring(alphabet FROM part+1 FOR 1);
        END LOOP;
        BEGIN
            INSERT INTO c_posts.identity_public_labels(identity_id,short_code) VALUES(selected_identity,code);
            RETURN;
        EXCEPTION WHEN unique_violation THEN
            IF EXISTS (SELECT 1 FROM c_posts.identity_public_labels WHERE identity_id=selected_identity) THEN
                RETURN;
            END IF;
        END;
    END LOOP;
END
$$;

CREATE FUNCTION c_posts.label_new_identity() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    PERFORM c_posts.allocate_identity_label(NEW.identity_id);
    RETURN NEW;
END
$$;
CREATE TRIGGER post_label_new_identity AFTER INSERT ON public.community_identities
    FOR EACH ROW EXECUTE FUNCTION c_posts.label_new_identity();
SELECT c_posts.allocate_identity_label(identity_id) FROM public.community_identities ORDER BY identity_id;

CREATE TABLE c_posts.account_publication_control (
    account_id uuid PRIMARY KEY REFERENCES c_auth.accounts(account_id),
    stop_generation bigint NOT NULL DEFAULT 0 CHECK (stop_generation>=0),
    last_public_identity_id uuid,
    last_public_at timestamptz,
    last_public_ordinal bigint,
    FOREIGN KEY(account_id,last_public_identity_id)
        REFERENCES public.community_identities(account_id,identity_id),
    CHECK ((last_public_identity_id IS NULL AND last_public_at IS NULL AND last_public_ordinal IS NULL)
        OR (last_public_identity_id IS NOT NULL AND last_public_at IS NOT NULL
            AND last_public_ordinal IS NOT NULL AND last_public_ordinal>0))
);
INSERT INTO c_posts.account_publication_control(account_id) SELECT account_id FROM c_auth.accounts;
CREATE FUNCTION c_posts.control_new_account() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO c_posts.account_publication_control(account_id) VALUES(NEW.account_id);
    RETURN NEW;
END
$$;
CREATE TRIGGER post_control_new_account AFTER INSERT ON c_auth.accounts
    FOR EACH ROW EXECUTE FUNCTION c_posts.control_new_account();

CREATE TABLE c_posts.publication_stop_events (
    account_id uuid NOT NULL REFERENCES c_auth.accounts(account_id),
    generation bigint NOT NULL CHECK (generation>0),
    stopped_at timestamptz NOT NULL,
    cause text NOT NULL CHECK (cause IN ('REQUEST_CLOSURE','MUTE','BAN','ACCOUNT_CLOSED')),
    transaction_id bigint NOT NULL DEFAULT txid_current(),
    PRIMARY KEY(account_id,generation)
);

CREATE TABLE c_posts.posts (
    post_id uuid PRIMARY KEY,
    owner_account_id uuid NOT NULL REFERENCES c_auth.accounts(account_id),
    channel_id uuid NOT NULL REFERENCES public.channels(id),
    visibility text NOT NULL DEFAULT 'INTERNAL' CHECK (visibility IN ('INTERNAL','PUBLISHED','DELETED')),
    published_attempt_version integer,
    published_at timestamptz,
    publication_ordinal bigint UNIQUE,
    deleted_at timestamptz,
    UNIQUE(owner_account_id,post_id),
    UNIQUE(owner_account_id,post_id,channel_id),
    CHECK (published_attempt_version IS NULL OR published_attempt_version>0),
    CHECK ((visibility='INTERNAL' AND published_attempt_version IS NULL AND published_at IS NULL
            AND publication_ordinal IS NULL AND deleted_at IS NULL)
        OR (visibility='PUBLISHED' AND published_attempt_version IS NOT NULL AND published_at IS NOT NULL
            AND publication_ordinal IS NOT NULL AND publication_ordinal>0 AND deleted_at IS NULL)
        OR (visibility='DELETED' AND deleted_at IS NOT NULL AND published_attempt_version IS NOT NULL
            AND published_at IS NOT NULL AND publication_ordinal IS NOT NULL
            AND publication_ordinal>0 AND deleted_at>=published_at))
);
CREATE INDEX posts_latest_channel ON c_posts.posts(channel_id,published_at DESC,publication_ordinal DESC)
    WHERE visibility='PUBLISHED';
CREATE INDEX posts_latest_owner ON c_posts.posts(owner_account_id,published_at DESC,publication_ordinal DESC)
    WHERE visibility='PUBLISHED';

CREATE TABLE c_posts.post_identity_bindings (
    account_id uuid NOT NULL,
    post_id uuid NOT NULL,
    identity_id uuid NOT NULL,
    bound_at timestamptz NOT NULL,
    PRIMARY KEY(account_id,post_id),
    UNIQUE(account_id,post_id,identity_id),
    FOREIGN KEY(account_id,post_id) REFERENCES c_posts.posts(owner_account_id,post_id),
    FOREIGN KEY(account_id,identity_id) REFERENCES public.community_identities(account_id,identity_id)
);
CREATE TABLE c_posts.publication_tasks (
    task_id uuid PRIMARY KEY,
    post_id uuid NOT NULL UNIQUE,
    owner_account_id uuid NOT NULL,
    identity_id uuid NOT NULL,
    channel_id uuid NOT NULL,
    latest_attempt_version integer NOT NULL CHECK (latest_attempt_version>0),
    owner_visible boolean NOT NULL DEFAULT true,
    UNIQUE(owner_account_id,task_id),
    FOREIGN KEY(owner_account_id,post_id,channel_id) REFERENCES c_posts.posts(owner_account_id,post_id,channel_id),
    FOREIGN KEY(owner_account_id,post_id,identity_id)
        REFERENCES c_posts.post_identity_bindings(account_id,post_id,identity_id)
);
CREATE INDEX tasks_owner ON c_posts.publication_tasks(owner_account_id,task_id) WHERE owner_visible;
CREATE INDEX tasks_identity ON c_posts.publication_tasks(identity_id,task_id);
CREATE TABLE c_posts.publication_attempts (
    task_id uuid NOT NULL REFERENCES c_posts.publication_tasks(task_id),
    version integer NOT NULL CHECK (version>0),
    accepted_stop_generation bigint NOT NULL CHECK (accepted_stop_generation>=0),
    state text NOT NULL CHECK (state IN ('ACCEPTED','PUBLISHED','FAILED','CANCELLED')),
    accepted_at timestamptz NOT NULL,
    acceptance_ordinal bigint NOT NULL UNIQUE CHECK (acceptance_ordinal>0),
    terminal_at timestamptz,
    failure_code text CHECK (failure_code IN ('PUBLICATION_FAILED','PUBLISHING_STOPPED','IDENTITY_INACTIVE')),
    PRIMARY KEY(task_id,version),
    CHECK ((state='ACCEPTED' AND terminal_at IS NULL AND failure_code IS NULL)
        OR (state IN ('PUBLISHED','CANCELLED') AND terminal_at IS NOT NULL
            AND terminal_at>=accepted_at AND failure_code IS NULL)
        OR (state='FAILED' AND terminal_at IS NOT NULL AND terminal_at>=accepted_at AND failure_code IS NOT NULL))
);
ALTER TABLE c_posts.publication_tasks ADD CONSTRAINT task_latest_attempt
    FOREIGN KEY(task_id,latest_attempt_version) REFERENCES c_posts.publication_attempts(task_id,version)
    DEFERRABLE INITIALLY DEFERRED;
CREATE UNIQUE INDEX attempts_one_accepted ON c_posts.publication_attempts(task_id) WHERE state='ACCEPTED';
CREATE UNIQUE INDEX attempts_one_published ON c_posts.publication_attempts(task_id) WHERE state='PUBLISHED';
CREATE INDEX attempts_pending ON c_posts.publication_attempts(accepted_at,task_id) WHERE state='ACCEPTED';
CREATE INDEX attempts_latest_sort ON c_posts.publication_attempts(accepted_at DESC,task_id DESC,acceptance_ordinal);
CREATE TABLE c_posts.attempt_contents (
    task_id uuid NOT NULL,
    version integer NOT NULL,
    title text,
    body text,
    request_digest bytea NOT NULL CHECK (octet_length(request_digest)=32),
    erased_at timestamptz,
    PRIMARY KEY(task_id,version),
    FOREIGN KEY(task_id,version) REFERENCES c_posts.publication_attempts(task_id,version),
    CHECK ((erased_at IS NULL AND title IS NOT NULL AND body IS NOT NULL
                AND octet_length(title) BETWEEN 1 AND 4096 AND octet_length(body) BETWEEN 1 AND 65536)
        OR (erased_at IS NOT NULL AND title IS NULL AND body IS NULL))
);
CREATE TABLE c_posts.command_receipts (
    key_digest bytea PRIMARY KEY CHECK (octet_length(key_digest)=32),
    owner_account_id uuid REFERENCES c_auth.accounts(account_id),
    operation text NOT NULL CHECK (operation IN ('CREATE','RETRY','CANCEL','DELETE_POST','HIDE_TASK')),
    intent_fingerprint bytea NOT NULL CHECK (octet_length(intent_fingerprint)=32),
    outcome text NOT NULL CHECK (outcome IN ('ACCEPTED','COMMITTED','REJECTED','NOT_ACCEPTED','RESULT_EXPIRED')),
    task_id uuid REFERENCES c_posts.publication_tasks(task_id),
    post_id uuid REFERENCES c_posts.posts(post_id),
    attempt_version integer CHECK (attempt_version>0),
    task_state text CHECK (task_state IN ('ACCEPTED','PUBLISHED','FAILED','CANCELLED')),
    error_code text,
    committed_at timestamptz NOT NULL,
    FOREIGN KEY(owner_account_id,task_id) REFERENCES c_posts.publication_tasks(owner_account_id,task_id),
    FOREIGN KEY(owner_account_id,post_id) REFERENCES c_posts.posts(owner_account_id,post_id),
    CHECK (error_code IS NULL OR error_code ~ '^[A-Z][A-Z0-9_]{1,63}$'),
    CHECK ((outcome='RESULT_EXPIRED' AND owner_account_id IS NULL AND task_id IS NULL
                AND post_id IS NULL AND attempt_version IS NULL AND task_state IS NULL AND error_code IS NULL)
        OR (outcome<>'RESULT_EXPIRED' AND owner_account_id IS NOT NULL)),
    CHECK (outcome<>'ACCEPTED' OR (task_id IS NOT NULL AND post_id IS NOT NULL
            AND attempt_version IS NOT NULL AND task_state IS NOT NULL
            AND task_state='ACCEPTED' AND error_code IS NULL)),
    CHECK (outcome<>'NOT_ACCEPTED' OR (task_id IS NULL AND post_id IS NULL
            AND attempt_version IS NULL AND task_state IS NULL AND error_code IS NOT NULL AND error_code='COMMAND_SEALED')),
    CHECK (outcome<>'REJECTED' OR error_code IS NOT NULL)
);
CREATE INDEX command_receipts_owner ON c_posts.command_receipts(owner_account_id,committed_at) WHERE owner_account_id IS NOT NULL;
CREATE TABLE c_posts.payload_cleanup (
    task_id uuid NOT NULL,
    version integer NOT NULL,
    cause text NOT NULL CHECK (cause IN ('CANCELLED','HIDDEN','RETRIED','IDENTITY_DELETED','ACCOUNT_CLOSED','POST_DELETED')),
    requested_at timestamptz NOT NULL,
    due_at timestamptz NOT NULL,
    state text NOT NULL DEFAULT 'PENDING' CHECK (state IN ('PENDING','ERASED')),
    PRIMARY KEY(task_id,version),
    FOREIGN KEY(task_id,version) REFERENCES c_posts.attempt_contents(task_id,version),
    CHECK (due_at>=requested_at AND due_at<=requested_at+interval '7 days')
);
CREATE INDEX payload_cleanup_due ON c_posts.payload_cleanup(due_at,task_id,version) WHERE state='PENDING';

CREATE FUNCTION c_posts.guard_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'permanent post facts cannot be rewritten or deleted' USING ERRCODE='23514';
END
$$;
CREATE TRIGGER identity_public_label_immutable BEFORE UPDATE OR DELETE ON c_posts.identity_public_labels
    FOR EACH ROW EXECUTE FUNCTION c_posts.guard_immutable();
CREATE TRIGGER post_binding_immutable BEFORE UPDATE OR DELETE ON c_posts.post_identity_bindings
    FOR EACH ROW EXECUTE FUNCTION c_posts.guard_immutable();
CREATE TRIGGER publication_stop_event_immutable BEFORE UPDATE OR DELETE ON c_posts.publication_stop_events
    FOR EACH ROW EXECUTE FUNCTION c_posts.guard_immutable();
CREATE TRIGGER post_schema_meta_immutable BEFORE UPDATE OR DELETE ON c_posts.schema_meta
    FOR EACH ROW EXECUTE FUNCTION c_posts.guard_immutable();
CREATE TRIGGER post_protocol_keys_immutable BEFORE UPDATE OR DELETE ON c_posts.protocol_keys
    FOR EACH ROW EXECUTE FUNCTION c_posts.guard_immutable();

CREATE FUNCTION c_posts.guard_control() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP='DELETE' OR NEW.account_id IS DISTINCT FROM OLD.account_id
       OR (NEW.stop_generation<>OLD.stop_generation AND NEW.stop_generation<>OLD.stop_generation+1)
       OR (OLD.last_public_ordinal IS NOT NULL AND
            (NEW.last_public_ordinal IS NULL OR NEW.last_public_ordinal<OLD.last_public_ordinal))
       OR (NEW.last_public_ordinal IS NOT DISTINCT FROM OLD.last_public_ordinal AND
            (NEW.last_public_identity_id,NEW.last_public_at) IS DISTINCT FROM
            (OLD.last_public_identity_id,OLD.last_public_at)) THEN
        RAISE EXCEPTION 'publication control is monotonic' USING ERRCODE='23514';
    END IF;
    RETURN NEW;
END
$$;
CREATE TRIGGER publication_control_monotonic BEFORE UPDATE OR DELETE ON c_posts.account_publication_control
    FOR EACH ROW EXECUTE FUNCTION c_posts.guard_control();
CREATE FUNCTION c_posts.check_stop_event() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE selected_account uuid; selected_generation bigint;
BEGIN
    selected_account := NEW.account_id;
    IF TG_TABLE_NAME='account_publication_control' THEN
        IF TG_OP='INSERT' OR NEW.stop_generation=OLD.stop_generation THEN RETURN NULL; END IF;
        selected_generation := NEW.stop_generation;
        IF NOT EXISTS (SELECT 1 FROM c_posts.publication_stop_events
            WHERE account_id=selected_account AND generation=selected_generation
                AND transaction_id=txid_current()) THEN
            RAISE EXCEPTION 'stop generation requires a same-transaction event' USING ERRCODE='23514';
        END IF;
    ELSE
        IF NEW.transaction_id<>txid_current() OR NOT EXISTS (SELECT 1 FROM c_posts.account_publication_control
            WHERE account_id=selected_account AND stop_generation>=NEW.generation) THEN
            RAISE EXCEPTION 'stop event requires a current monotonic generation' USING ERRCODE='23514';
        END IF;
    END IF;
    RETURN NULL;
END
$$;
CREATE CONSTRAINT TRIGGER publication_control_event AFTER UPDATE ON c_posts.account_publication_control
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION c_posts.check_stop_event();
CREATE CONSTRAINT TRIGGER publication_event_control AFTER INSERT ON c_posts.publication_stop_events
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION c_posts.check_stop_event();

CREATE FUNCTION c_posts.guard_post() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP='DELETE' OR (NEW.post_id,NEW.owner_account_id,NEW.channel_id) IS DISTINCT FROM
            (OLD.post_id,OLD.owner_account_id,OLD.channel_id)
       OR (OLD.visibility='DELETED' AND NEW IS DISTINCT FROM OLD)
       OR (OLD.visibility='PUBLISHED' AND (NEW.visibility NOT IN ('PUBLISHED','DELETED') OR
            (NEW.published_attempt_version,NEW.published_at,NEW.publication_ordinal) IS DISTINCT FROM
            (OLD.published_attempt_version,OLD.published_at,OLD.publication_ordinal)))
       OR (OLD.visibility='INTERNAL' AND NEW.visibility NOT IN ('INTERNAL','PUBLISHED')) THEN
        RAISE EXCEPTION 'post ownership and publication facts are immutable' USING ERRCODE='23514';
    END IF;
    RETURN NEW;
END
$$;
CREATE TRIGGER post_monotonic BEFORE UPDATE OR DELETE ON c_posts.posts
    FOR EACH ROW EXECUTE FUNCTION c_posts.guard_post();
CREATE FUNCTION c_posts.guard_task() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP='DELETE' OR (NEW.task_id,NEW.post_id,NEW.owner_account_id,NEW.identity_id,NEW.channel_id) IS DISTINCT FROM
            (OLD.task_id,OLD.post_id,OLD.owner_account_id,OLD.identity_id,OLD.channel_id)
       OR (NEW.latest_attempt_version<>OLD.latest_attempt_version AND
            NEW.latest_attempt_version::bigint<>OLD.latest_attempt_version::bigint+1)
       OR (NOT OLD.owner_visible AND NEW.owner_visible) THEN
        RAISE EXCEPTION 'task binding, attempts and hidden state are monotonic' USING ERRCODE='23514';
    END IF;
    IF NEW.latest_attempt_version<>OLD.latest_attempt_version AND NOT EXISTS
        (SELECT 1 FROM c_posts.publication_attempts WHERE task_id=OLD.task_id
            AND version=OLD.latest_attempt_version AND state='FAILED') THEN
        RAISE EXCEPTION 'only failed latest attempts can be retried' USING ERRCODE='23514';
    END IF;
    RETURN NEW;
END
$$;
CREATE TRIGGER publication_task_monotonic BEFORE UPDATE OR DELETE ON c_posts.publication_tasks
    FOR EACH ROW EXECUTE FUNCTION c_posts.guard_task();
CREATE FUNCTION c_posts.guard_attempt() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP='DELETE' OR (NEW.task_id,NEW.version,NEW.accepted_stop_generation,NEW.accepted_at,NEW.acceptance_ordinal)
            IS DISTINCT FROM (OLD.task_id,OLD.version,OLD.accepted_stop_generation,OLD.accepted_at,OLD.acceptance_ordinal)
       OR (OLD.state<>'ACCEPTED' AND NEW IS DISTINCT FROM OLD) THEN
        RAISE EXCEPTION 'attempt input and terminal facts are immutable' USING ERRCODE='23514';
    END IF;
    RETURN NEW;
END
$$;
CREATE TRIGGER publication_attempt_monotonic BEFORE UPDATE OR DELETE ON c_posts.publication_attempts
    FOR EACH ROW EXECUTE FUNCTION c_posts.guard_attempt();
CREATE FUNCTION c_posts.guard_content() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP='DELETE' OR (NEW.task_id,NEW.version,NEW.request_digest) IS DISTINCT FROM
            (OLD.task_id,OLD.version,OLD.request_digest)
       OR (OLD.erased_at IS NOT NULL AND NEW IS DISTINCT FROM OLD)
       OR (NEW IS DISTINCT FROM OLD AND NOT (OLD.erased_at IS NULL AND NEW.erased_at IS NOT NULL
            AND NEW.title IS NULL AND NEW.body IS NULL)) THEN
        RAISE EXCEPTION 'accepted text permits only irreversible erasure' USING ERRCODE='23514';
    END IF;
    RETURN NEW;
END
$$;
CREATE TRIGGER attempt_content_erase_only BEFORE UPDATE OR DELETE ON c_posts.attempt_contents
    FOR EACH ROW EXECUTE FUNCTION c_posts.guard_content();
CREATE FUNCTION c_posts.guard_receipt() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP='DELETE' OR (NEW.key_digest,NEW.operation,NEW.intent_fingerprint,NEW.committed_at) IS DISTINCT FROM
            (OLD.key_digest,OLD.operation,OLD.intent_fingerprint,OLD.committed_at)
       OR (NEW IS DISTINCT FROM OLD AND NOT (OLD.outcome<>'RESULT_EXPIRED' AND NEW.outcome='RESULT_EXPIRED'
            AND NEW.owner_account_id IS NULL AND NEW.task_id IS NULL AND NEW.post_id IS NULL
            AND NEW.attempt_version IS NULL AND NEW.task_state IS NULL AND NEW.error_code IS NULL
            AND EXISTS(SELECT 1 FROM c_auth.accounts WHERE account_id=OLD.owner_account_id AND state='CLOSED'))) THEN
        RAISE EXCEPTION 'command outcome is permanent except closure tombstone compaction' USING ERRCODE='23514';
    END IF;
    RETURN NEW;
END
$$;
CREATE TRIGGER post_command_receipt_immutable BEFORE UPDATE OR DELETE ON c_posts.command_receipts
    FOR EACH ROW EXECUTE FUNCTION c_posts.guard_receipt();
CREATE FUNCTION c_posts.guard_cleanup() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP='DELETE' OR (NEW.task_id,NEW.version,NEW.cause,NEW.requested_at,NEW.due_at) IS DISTINCT FROM
            (OLD.task_id,OLD.version,OLD.cause,OLD.requested_at,OLD.due_at)
       OR (OLD.state='ERASED' AND NEW.state<>'ERASED') THEN
        RAISE EXCEPTION 'payload cleanup request is permanent and monotonic' USING ERRCODE='23514';
    END IF;
    RETURN NEW;
END
$$;
CREATE TRIGGER payload_cleanup_monotonic BEFORE UPDATE OR DELETE ON c_posts.payload_cleanup
    FOR EACH ROW EXECUTE FUNCTION c_posts.guard_cleanup();

-- 公开与任务终态必须一起提交，不能只改其中一张表制造虚假公开结果。
CREATE FUNCTION c_posts.check_publication_shape() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE selected_post uuid; post_row c_posts.posts%ROWTYPE; task_row c_posts.publication_tasks%ROWTYPE;
    attempt_row c_posts.publication_attempts%ROWTYPE;
BEGIN
    IF TG_TABLE_NAME='posts' THEN selected_post := NEW.post_id;
    ELSIF TG_TABLE_NAME='publication_tasks' THEN selected_post := NEW.post_id;
    ELSE SELECT post_id INTO selected_post FROM c_posts.publication_tasks WHERE task_id=NEW.task_id;
    END IF;
    SELECT * INTO post_row FROM c_posts.posts WHERE post_id=selected_post;
    SELECT * INTO task_row FROM c_posts.publication_tasks WHERE post_id=selected_post;
    IF task_row.task_id IS NULL THEN
        RAISE EXCEPTION 'each accepted post requires its fixed task and binding' USING ERRCODE='23514';
    END IF;
    IF post_row.visibility IN ('PUBLISHED','DELETED') THEN
        SELECT * INTO attempt_row FROM c_posts.publication_attempts WHERE task_id=task_row.task_id
            AND version=post_row.published_attempt_version;
        IF attempt_row.state IS DISTINCT FROM 'PUBLISHED' OR attempt_row.terminal_at IS DISTINCT FROM post_row.published_at THEN
            RAISE EXCEPTION 'public post requires a matching published attempt' USING ERRCODE='23514';
        END IF;
        IF post_row.visibility='PUBLISHED' AND NOT EXISTS(SELECT 1 FROM c_posts.attempt_contents
            WHERE task_id=task_row.task_id AND version=post_row.published_attempt_version AND erased_at IS NULL) THEN
            RAISE EXCEPTION 'public post content cannot be erased before deletion' USING ERRCODE='23514';
        END IF;
    ELSIF EXISTS (SELECT 1 FROM c_posts.publication_attempts WHERE task_id=task_row.task_id AND state='PUBLISHED') THEN
        RAISE EXCEPTION 'published attempt requires a public or deleted post' USING ERRCODE='23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM c_posts.attempt_contents WHERE task_id=task_row.task_id
            AND version=task_row.latest_attempt_version) THEN
        RAISE EXCEPTION 'latest attempt requires immutable text or an erased tombstone' USING ERRCODE='23514';
    END IF;
    RETURN NULL;
END
$$;
CREATE CONSTRAINT TRIGGER post_publication_shape AFTER INSERT OR UPDATE ON c_posts.posts
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION c_posts.check_publication_shape();
CREATE CONSTRAINT TRIGGER task_publication_shape AFTER INSERT OR UPDATE ON c_posts.publication_tasks
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION c_posts.check_publication_shape();
CREATE CONSTRAINT TRIGGER attempt_publication_shape AFTER INSERT OR UPDATE ON c_posts.publication_attempts
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION c_posts.check_publication_shape();
CREATE CONSTRAINT TRIGGER content_publication_shape AFTER INSERT OR UPDATE ON c_posts.attempt_contents
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION c_posts.check_publication_shape();

-- 若账号已有发布任务，旧 writer 漏掉生命周期 hook 的写入必须在提交时失败。
-- transaction_id 只用于内部完整性校验，不出现在任何公开 DTO。
CREATE FUNCTION c_posts.check_lifecycle_stop() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE selected_cause text;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM c_posts.publication_tasks WHERE owner_account_id=NEW.account_id) THEN RETURN NULL; END IF;
    IF TG_TABLE_NAME='accounts' THEN
        IF NEW.state IS NOT DISTINCT FROM OLD.state THEN RETURN NULL; END IF;
        IF NEW.state='PENDING_CLOSE' THEN selected_cause := 'REQUEST_CLOSURE';
        ELSIF NEW.state='CLOSED' THEN selected_cause := 'ACCOUNT_CLOSED';
        ELSE RETURN NULL; END IF;
    ELSE
        IF NEW.ban_state='BANNED' AND (NEW.ban_state,NEW.ban_ends_at) IS DISTINCT FROM (OLD.ban_state,OLD.ban_ends_at) THEN
            selected_cause := 'BAN';
        ELSIF NEW.mute_state='MUTED' AND (NEW.mute_state,NEW.mute_ends_at) IS DISTINCT FROM (OLD.mute_state,OLD.mute_ends_at) THEN
            selected_cause := 'MUTE';
        ELSE RETURN NULL; END IF;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM c_posts.publication_stop_events WHERE account_id=NEW.account_id
            AND cause=selected_cause AND transaction_id=txid_current()) THEN
        RAISE EXCEPTION 'post lifecycle change requires a same-transaction stop hook' USING ERRCODE='23514';
    END IF;
    RETURN NULL;
END
$$;
CREATE CONSTRAINT TRIGGER post_account_stop_hook AFTER UPDATE ON c_auth.accounts
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION c_posts.check_lifecycle_stop();
CREATE CONSTRAINT TRIGGER post_restriction_stop_hook AFTER UPDATE ON c_auth.account_restrictions
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION c_posts.check_lifecycle_stop();

-- 身份删除也必须携带完整任务终态／私有入口关闭／擦除安排。
-- 旧 writer 即使未启用文字接口，也不能留下仍可公开的受理任务。
CREATE FUNCTION c_posts.check_identity_delete_hook() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.deleted_at IS NULL OR OLD.deleted_at IS NOT NULL THEN RETURN NULL; END IF;
    IF EXISTS(SELECT 1 FROM c_posts.publication_tasks t WHERE t.identity_id=NEW.identity_id AND t.owner_visible)
       OR EXISTS(SELECT 1 FROM c_posts.publication_attempts a JOIN c_posts.publication_tasks t USING(task_id)
            WHERE t.identity_id=NEW.identity_id AND
                (a.state='ACCEPTED' OR (a.state<>'PUBLISHED' AND a.terminal_at>NEW.deleted_at)))
       OR EXISTS(SELECT 1 FROM c_posts.publication_attempts a JOIN c_posts.publication_tasks t USING(task_id)
            JOIN c_posts.attempt_contents x ON x.task_id=a.task_id AND x.version=a.version
            WHERE t.identity_id=NEW.identity_id AND a.state<>'PUBLISHED' AND x.erased_at IS NULL
                AND NOT EXISTS(SELECT 1 FROM c_posts.payload_cleanup q WHERE q.task_id=a.task_id AND q.version=a.version)) THEN
        RAISE EXCEPTION 'identity deletion requires same-transaction private post cleanup' USING ERRCODE='23514';
    END IF;
    RETURN NULL;
END
$$;
CREATE CONSTRAINT TRIGGER post_identity_delete_hook AFTER UPDATE ON public.community_identities
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION c_posts.check_identity_delete_hook();

REVOKE ALL ON SCHEMA c_posts FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA c_posts FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA c_posts FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA c_posts FROM PUBLIC;
-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
DO $$ BEGIN RAISE EXCEPTION 'Post bindings, labels and command tombstones require forward repair; Down is forbidden'; END $$;
-- +goose StatementEnd
