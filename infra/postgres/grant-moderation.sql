-- Run as the C migration owner, after 0015. V/recovery/business receive no access.
GRANT USAGE ON SCHEMA c_moderation TO hnuhole_c_runtime;
GRANT SELECT ON ALL TABLES IN SCHEMA c_moderation TO hnuhole_c_runtime;
GRANT INSERT(account_id,ban_state,ban_ends_at,mute_state,mute_ends_at),
 UPDATE(ban_state,ban_ends_at,mute_state,mute_ends_at)
 ON c_moderation.legacy_restrictions TO hnuhole_c_runtime;
GRANT INSERT ON c_moderation.cases,c_moderation.reports,c_moderation.sanctions,c_moderation.appeals,c_moderation.appeal_materials,c_moderation.notifications,c_moderation.commands,c_moderation.audit,c_moderation.access_sessions,c_moderation.roles TO hnuhole_c_runtime;
GRANT UPDATE(state,version,outcome,explanation,decided_by) ON c_moderation.cases TO hnuhole_c_runtime;
GRANT UPDATE(reporter_account_id,identity_id) ON c_moderation.reports TO hnuhole_c_runtime;
GRANT UPDATE(revoked_at) ON c_moderation.sanctions,c_moderation.access_sessions TO hnuhole_c_runtime;
GRANT UPDATE(state,version,reason) ON c_moderation.appeals TO hnuhole_c_runtime;
GRANT UPDATE(read_at) ON c_moderation.notifications TO hnuhole_c_runtime;
GRANT UPDATE(role) ON c_moderation.roles TO hnuhole_c_runtime;
GRANT DELETE ON c_moderation.notifications,c_moderation.access_sessions,c_moderation.roles TO hnuhole_c_runtime;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA c_moderation TO hnuhole_c_runtime;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA c_moderation TO hnuhole_c_runtime;
GRANT UPDATE(moderation_hidden) ON c_posts.posts TO hnuhole_c_runtime;
GRANT UPDATE(moderation_rename_required) ON public.community_identities TO hnuhole_c_runtime;
GRANT INSERT(registered_at) ON c_auth.accounts TO hnuhole_c_runtime;
GRANT INSERT,UPDATE(retry_token) ON c_moderation.request_fences TO hnuhole_c_runtime;
-- 0018 adds only this mutable projection; comment ownership/receipts stay fixed.
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid=to_regclass('c_comments.tasks') AND attname='moderation_hidden' AND NOT attisdropped) THEN
  GRANT UPDATE(moderation_hidden) ON c_comments.tasks TO hnuhole_c_runtime;
 END IF;
END $$;
