-- Run as the C migration owner, after 0015. V/recovery/business receive no access.
GRANT USAGE ON SCHEMA c_moderation TO hnuhole_c_runtime;
GRANT SELECT ON ALL TABLES IN SCHEMA c_moderation TO hnuhole_c_runtime;
GRANT INSERT ON c_moderation.cases,c_moderation.reports,c_moderation.sanctions,c_moderation.appeals,c_moderation.appeal_materials,c_moderation.notifications,c_moderation.commands,c_moderation.audit,c_moderation.access_sessions,c_moderation.roles,c_moderation.platform_numbers TO hnuhole_c_runtime;
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
