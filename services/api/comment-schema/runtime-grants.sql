-- Explicit C runtime grants for the pending text component, after the existing
-- auth/privacy bootstrap. No recovery/business/V role receives comment data.
GRANT USAGE ON SCHEMA c_comments TO hnuhole_c_runtime;
GRANT SELECT,INSERT ON c_comments.protocol_keys,c_comments.tasks,c_comments.attempts,c_comments.receipts,c_comments.snapshots TO hnuhole_c_runtime;
GRANT UPDATE(owner_visible,abandoned_at) ON c_comments.tasks TO hnuhole_c_runtime;
GRANT UPDATE(state,terminal_at,failure_code,body) ON c_comments.attempts TO hnuhole_c_runtime;
GRANT DELETE ON c_comments.snapshots TO hnuhole_c_runtime;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA c_comments TO hnuhole_c_runtime;
