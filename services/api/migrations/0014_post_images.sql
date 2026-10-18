-- +goose Up
-- +goose StatementBegin
-- Deliberately private SQL byte storage. No public bucket, URL token, or cache.
ALTER TABLE c_posts.attempt_contents ADD COLUMN image_count integer NOT NULL DEFAULT 0 CHECK(image_count BETWEEN 0 AND 9);
ALTER TABLE c_posts.attempt_contents DROP CONSTRAINT attempt_contents_check;
ALTER TABLE c_posts.attempt_contents ADD CONSTRAINT attempt_contents_check CHECK (
 (erased_at IS NULL AND title IS NOT NULL AND body IS NOT NULL
  AND octet_length(title) BETWEEN 1 AND 4096 AND octet_length(body) BETWEEN 0 AND 65536
  AND (octet_length(body)>0 OR image_count>0))
 OR (erased_at IS NOT NULL AND title IS NULL AND body IS NULL));

CREATE TABLE c_posts.images (
 task_id uuid NOT NULL,
 version integer NOT NULL,
 media_id uuid NOT NULL CHECK(media_id<>'00000000-0000-0000-0000-000000000000'),
 content_version_id uuid NOT NULL UNIQUE CHECK(content_version_id<>'00000000-0000-0000-0000-000000000000'),
 position integer NOT NULL CHECK(position BETWEEN 0 AND 8),
 digest bytea NOT NULL CHECK(octet_length(digest)=32),
 byte_length integer NOT NULL CHECK(byte_length BETWEEN 1 AND 10485760),
 mime_type text NOT NULL CHECK(mime_type IN ('image/jpeg','image/png','image/gif','image/webp')),
 width integer NOT NULL CHECK(width BETWEEN 1 AND 16384),
 height integer NOT NULL CHECK(height BETWEEN 1 AND 16384),
 display_width integer,
 display_height integer,
 frames integer,
 cycle_duration_ms integer,
 max_frame_duration_ms integer,
 payload bytea,
 verified_at timestamptz,
 erased_at timestamptz,
 grant_digest bytea CHECK(grant_digest IS NULL OR octet_length(grant_digest)=32),
 grant_expires_at timestamptz,
 PRIMARY KEY(task_id,version,media_id),
 UNIQUE(task_id,version,position),
 FOREIGN KEY(task_id,version) REFERENCES c_posts.publication_attempts(task_id,version),
 CHECK(width::bigint*height<=12582912),
 CHECK((grant_digest IS NULL)=(grant_expires_at IS NULL)),
 CHECK((verified_at IS NULL AND payload IS NULL AND display_width IS NULL AND display_height IS NULL AND frames IS NULL AND cycle_duration_ms IS NULL AND max_frame_duration_ms IS NULL)
 OR (verified_at IS NOT NULL AND display_width IS NOT NULL AND display_height IS NOT NULL AND frames IS NOT NULL AND cycle_duration_ms IS NOT NULL AND max_frame_duration_ms IS NOT NULL
     AND ((display_width=width AND display_height=height) OR (display_width=height AND display_height=width))
     AND frames BETWEEN 1 AND 120 AND (frames=1 OR (width::bigint*height<=1048576 AND width::bigint*height*frames<=16777216))
     AND cycle_duration_ms BETWEEN 0 AND 60000 AND max_frame_duration_ms BETWEEN 0 AND 15000
     AND ((erased_at IS NULL AND payload IS NOT NULL AND octet_length(payload)=byte_length AND sha256(payload)=digest)
          OR (erased_at IS NOT NULL AND payload IS NULL)))),
 CHECK(erased_at IS NULL OR (payload IS NULL AND grant_digest IS NULL))
);

CREATE FUNCTION c_posts.guard_image() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'image tombstones are permanent' USING ERRCODE='23514'; END IF;
 IF TG_OP='INSERT' THEN
  IF NOT EXISTS(SELECT 1 FROM c_posts.publication_attempts a WHERE a.task_id=NEW.task_id AND a.version=NEW.version
   AND a.state='ACCEPTED' AND a.xmin::text::bigint=(txid_current() % 4294967296)) THEN
   RAISE EXCEPTION 'manifest must be accepted in the same transaction' USING ERRCODE='23514';
  END IF;
 ELSE
  IF (NEW.task_id,NEW.version,NEW.media_id,NEW.content_version_id,NEW.position,NEW.digest,NEW.byte_length,NEW.mime_type,NEW.width,NEW.height)
    IS DISTINCT FROM (OLD.task_id,OLD.version,OLD.media_id,OLD.content_version_id,OLD.position,OLD.digest,OLD.byte_length,OLD.mime_type,OLD.width,OLD.height)
   OR (OLD.erased_at IS NOT NULL AND NEW IS DISTINCT FROM OLD)
   OR (OLD.verified_at IS NOT NULL AND (NEW.verified_at,NEW.display_width,NEW.display_height,NEW.frames,NEW.cycle_duration_ms,NEW.max_frame_duration_ms) IS DISTINCT FROM
       (OLD.verified_at,OLD.display_width,OLD.display_height,OLD.frames,OLD.cycle_duration_ms,OLD.max_frame_duration_ms))
   OR (OLD.payload IS NOT NULL AND NEW.payload IS DISTINCT FROM OLD.payload AND NOT(NEW.payload IS NULL AND NEW.erased_at IS NOT NULL)) THEN
   RAISE EXCEPTION 'accepted image is immutable except erasure' USING ERRCODE='23514';
  END IF;
 END IF;
 IF (TG_OP='INSERT' OR NEW.payload IS DISTINCT FROM OLD.payload OR NEW.grant_digest IS DISTINCT FROM OLD.grant_digest)
   AND NEW.erased_at IS NULL AND NOT EXISTS(SELECT 1 FROM c_posts.publication_attempts a
    JOIN c_posts.publication_tasks t USING(task_id) JOIN c_posts.account_publication_control ctl ON ctl.account_id=t.owner_account_id
    JOIN c_auth.accounts ac ON ac.account_id=t.owner_account_id
    WHERE a.task_id=NEW.task_id AND a.version=NEW.version AND a.state='ACCEPTED' AND t.latest_attempt_version=NEW.version
     AND t.owner_visible AND ac.state='ACTIVE' AND a.accepted_stop_generation=ctl.stop_generation) THEN
  RAISE EXCEPTION 'image attempt no longer accepts uploads' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER image_immutable BEFORE INSERT OR UPDATE OR DELETE ON c_posts.images FOR EACH ROW EXECUTE FUNCTION c_posts.guard_image();

CREATE FUNCTION c_posts.check_image_set() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE selected_task uuid; selected_version integer; expected integer; actual integer; high integer;
BEGIN
 selected_task:=NEW.task_id; selected_version:=NEW.version;
 SELECT image_count INTO expected FROM c_posts.attempt_contents WHERE task_id=selected_task AND version=selected_version;
 SELECT count(*),max(position) INTO actual,high FROM c_posts.images WHERE task_id=selected_task AND version=selected_version;
 IF expected IS NULL OR expected<>actual OR (actual>0 AND high<>actual-1) THEN
  RAISE EXCEPTION 'complete ordered image manifest required at acceptance' USING ERRCODE='23514';
 END IF;
 IF EXISTS(SELECT 1 FROM c_posts.publication_attempts WHERE task_id=selected_task AND version=selected_version AND state='PUBLISHED')
  AND EXISTS(SELECT 1 FROM c_posts.posts p JOIN c_posts.publication_tasks t USING(post_id) WHERE t.task_id=selected_task AND p.visibility='PUBLISHED')
  AND EXISTS(SELECT 1 FROM c_posts.images WHERE task_id=selected_task AND version=selected_version AND (verified_at IS NULL OR payload IS NULL OR erased_at IS NOT NULL)) THEN
  RAISE EXCEPTION 'all original image bytes must be verified before publication' USING ERRCODE='23514';
 END IF;
 RETURN NULL;
END $$;
CREATE CONSTRAINT TRIGGER image_set_shape AFTER INSERT OR UPDATE ON c_posts.images DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION c_posts.check_image_set();
CREATE CONSTRAINT TRIGGER image_content_shape AFTER INSERT OR UPDATE ON c_posts.attempt_contents DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION c_posts.check_image_set();
CREATE CONSTRAINT TRIGGER image_publication_shape AFTER INSERT OR UPDATE ON c_posts.publication_attempts DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION c_posts.check_image_set();

CREATE FUNCTION c_posts.erase_terminal_images() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_TABLE_NAME='publication_attempts' THEN
  IF NEW.state IN ('CANCELLED','FAILED') THEN
   UPDATE c_posts.images SET payload=NULL,erased_at=NEW.terminal_at,grant_digest=NULL,grant_expires_at=NULL WHERE task_id=NEW.task_id AND version=NEW.version AND erased_at IS NULL;
  END IF;
 ELSIF TG_TABLE_NAME='posts' THEN
  IF NEW.visibility='DELETED' THEN
   UPDATE c_posts.images m SET payload=NULL,erased_at=NEW.deleted_at,grant_digest=NULL,grant_expires_at=NULL
    FROM c_posts.publication_tasks t WHERE t.post_id=NEW.post_id AND m.task_id=t.task_id AND m.erased_at IS NULL;
  END IF;
 END IF;
 RETURN NULL;
END $$;
CREATE TRIGGER image_terminal_erase AFTER UPDATE ON c_posts.publication_attempts FOR EACH ROW EXECUTE FUNCTION c_posts.erase_terminal_images();
CREATE TRIGGER image_post_delete_erase AFTER UPDATE ON c_posts.posts FOR EACH ROW EXECUTE FUNCTION c_posts.erase_terminal_images();

REVOKE ALL ON c_posts.images FROM PUBLIC;
REVOKE ALL ON FUNCTION c_posts.guard_image(),c_posts.check_image_set(),c_posts.erase_terminal_images() FROM PUBLIC;
-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
DO $$ BEGIN RAISE EXCEPTION 'Image ownership and content tombstones require forward repair; Down is forbidden'; END $$;
-- +goose StatementEnd
