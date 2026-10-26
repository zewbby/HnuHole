-- Run after real Goose 0017 and grant-community.sql. No recovery/business/V
-- role receives comment data, and no runtime role receives DDL or permanent deletion.
GRANT USAGE ON SCHEMA c_comments TO hnuhole_c_runtime;
GRANT SELECT,INSERT ON c_comments.protocol_keys,c_comments.tasks,c_comments.attempts,c_comments.receipts,c_comments.snapshots TO hnuhole_c_runtime;
GRANT UPDATE(owner_visible,abandoned_at,deleted_at) ON c_comments.tasks TO hnuhole_c_runtime;
GRANT UPDATE(state,terminal_at,failure_code,body) ON c_comments.attempts TO hnuhole_c_runtime;
GRANT DELETE ON c_comments.snapshots TO hnuhole_c_runtime;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA c_comments TO hnuhole_c_runtime;

GRANT SELECT,INSERT,DELETE ON c_comments.likes TO hnuhole_c_runtime;
GRANT SELECT,INSERT ON c_comments.images TO hnuhole_c_runtime;
GRANT UPDATE(payload,metadata,erased_at) ON c_comments.images TO hnuhole_c_runtime;

-- Optional forward migration 0028. Event-writing functions are trigger-only
-- SECURITY DEFINER functions with a fixed search_path; runtime cannot forge them.
DO $$ BEGIN
 IF to_regclass('c_inbox.records') IS NOT NULL THEN
  GRANT USAGE ON SCHEMA c_inbox TO hnuhole_c_runtime;
  GRANT SELECT ON c_inbox.records,c_inbox.like_events TO hnuhole_c_runtime;
  GRANT UPDATE(read_version,seen_like_count) ON c_inbox.records TO hnuhole_c_runtime;
  GRANT UPDATE(read_at) ON c_moderation.notifications TO hnuhole_c_runtime;
 END IF;
END $$;
