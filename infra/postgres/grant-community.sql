-- Run as the controlled migration owner after Goose, never as the API.
REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA c_auth FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA c_auth FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA c_auth FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA c_auth FROM PUBLIC;
REVOKE ALL ON public.sessions FROM hnuhole_c_runtime;
REVOKE ALL ON ALL TABLES IN SCHEMA c_auth FROM hnuhole_c_runtime;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA c_auth FROM hnuhole_c_runtime;
REVOKE ALL ON SCHEMA c_auth FROM hnuhole_c_runtime;
REVOKE ALL ON public.channels FROM hnuhole_c_runtime;
REVOKE ALL ON public.identity_account_state,public.community_identities,public.identity_change_receipts FROM hnuhole_c_runtime,hnuhole_c_recovery,hnuhole_business;
REVOKE ALL ON public.identity_avatar_assets FROM hnuhole_c_runtime,hnuhole_c_recovery,hnuhole_business;
-- A --no-privileges restore regains default PUBLIC function EXECUTE.
-- Earlier-version startup fixtures also use this file before 0025 exists.
DO $$ BEGIN
 IF to_regprocedure('public.guard_identity_avatar()') IS NOT NULL THEN
  REVOKE ALL ON FUNCTION public.guard_identity_avatar() FROM PUBLIC;
 END IF;
 IF to_regprocedure('public.bind_identity_avatar()') IS NOT NULL THEN
  REVOKE ALL ON FUNCTION public.bind_identity_avatar() FROM PUBLIC;
 END IF;
 IF to_regprocedure('public.close_identity_avatars()') IS NOT NULL THEN
  REVOKE ALL ON FUNCTION public.close_identity_avatars() FROM PUBLIC;
 END IF;
END $$;
REVOKE ALL ON ALL TABLES IN SCHEMA c_auth FROM hnuhole_c_recovery,hnuhole_business;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA c_auth FROM hnuhole_c_recovery,hnuhole_business;
REVOKE ALL ON SCHEMA c_auth FROM hnuhole_c_recovery,hnuhole_business;
REVOKE ALL ON public.sessions FROM hnuhole_business;
GRANT USAGE ON SCHEMA c_auth,public TO hnuhole_c_runtime;
GRANT SELECT ON ALL TABLES IN SCHEMA c_auth TO hnuhole_c_runtime;
GRANT INSERT ON c_auth.account_restrictions,c_auth.accounts,c_auth.auth_challenges,c_auth.authorization_gate_audit,c_auth.closure_requests,c_auth.credential_change_intents,c_auth.passkeys,c_auth.receipt_outbox,c_auth.recent_device_replacement,c_auth.recovery_codes,c_auth.request_results,c_auth.reset_intents,c_auth.sessions,c_auth.signup_intents,c_auth.slot_ledger TO hnuhole_c_runtime;
GRANT UPDATE ON c_auth.account_restrictions,c_auth.accounts,c_auth.auth_challenges,c_auth.authorization_gate,c_auth.closure_requests,c_auth.credential_change_intents,c_auth.passkeys,c_auth.receipt_outbox,c_auth.recent_device_replacement,c_auth.recovery_codes,c_auth.request_results,c_auth.reset_intents,c_auth.sessions,c_auth.signup_intents,c_auth.slot_ledger TO hnuhole_c_runtime;
GRANT DELETE ON c_auth.auth_challenges,c_auth.closure_requests,c_auth.credential_change_intents,c_auth.passkeys,c_auth.receipt_outbox,c_auth.recent_device_replacement,c_auth.recovery_codes,c_auth.reset_intents,c_auth.security_events,c_auth.sessions TO hnuhole_c_runtime;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA c_auth TO hnuhole_c_runtime;
GRANT SELECT ON public.channels TO hnuhole_c_runtime;
GRANT SELECT,INSERT,UPDATE ON public.identity_account_state,public.community_identities TO hnuhole_c_runtime;
GRANT SELECT,INSERT ON public.identity_change_receipts TO hnuhole_c_runtime;
GRANT SELECT,INSERT ON public.identity_avatar_assets TO hnuhole_c_runtime;
GRANT UPDATE(identity_id,payload) ON public.identity_avatar_assets TO hnuhole_c_runtime;
GRANT USAGE ON SCHEMA c_auth TO hnuhole_c_recovery;
GRANT SELECT,UPDATE ON c_auth.authorization_gate TO hnuhole_c_recovery;
GRANT SELECT,INSERT ON c_auth.authorization_gate_audit TO hnuhole_c_recovery;
GRANT USAGE ON SEQUENCE c_auth.authorization_gate_audit_event_id_seq TO hnuhole_c_recovery;
GRANT USAGE ON SCHEMA public TO hnuhole_business;
GRANT SELECT ON public.channels TO hnuhole_business;

GRANT USAGE ON SCHEMA public TO hnuhole_c_runtime;
GRANT SELECT ON public.goose_db_version TO hnuhole_c_runtime;

REVOKE INSERT ON c_auth.authorization_gate FROM hnuhole_c_runtime;

-- PostgreSQL row-locking requires UPDATE on at least one column; event content is never edited.
GRANT UPDATE(event_id) ON c_auth.security_events TO hnuhole_c_runtime;
GRANT INSERT ON c_auth.security_events TO hnuhole_c_runtime;

-- 文字发布与认证共享最终事务，但 C runtime 只有逐表／逐列 DML。
-- business 与 recovery 角色不能取得正文、任务、命令回执或 stop event。
REVOKE ALL ON SCHEMA c_posts FROM PUBLIC,hnuhole_c_runtime,hnuhole_c_recovery,hnuhole_business;
REVOKE ALL ON ALL TABLES IN SCHEMA c_posts FROM PUBLIC,hnuhole_c_runtime,hnuhole_c_recovery,hnuhole_business;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA c_posts FROM PUBLIC,hnuhole_c_runtime,hnuhole_c_recovery,hnuhole_business;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA c_posts FROM PUBLIC,hnuhole_c_runtime,hnuhole_c_recovery,hnuhole_business;
GRANT USAGE ON SCHEMA c_posts TO hnuhole_c_runtime;
GRANT SELECT ON c_posts.schema_meta,c_posts.protocol_keys,c_posts.account_publication_control,c_posts.publication_stop_events,
    c_posts.identity_public_labels,c_posts.posts,c_posts.post_identity_bindings,c_posts.publication_tasks,
    c_posts.publication_attempts,c_posts.attempt_contents,c_posts.command_receipts,c_posts.payload_cleanup
    TO hnuhole_c_runtime;
GRANT INSERT ON c_posts.protocol_keys,c_posts.account_publication_control,c_posts.publication_stop_events,c_posts.identity_public_labels,
    c_posts.posts,c_posts.post_identity_bindings,c_posts.publication_tasks,c_posts.publication_attempts,
    c_posts.attempt_contents,c_posts.command_receipts,c_posts.payload_cleanup TO hnuhole_c_runtime;
GRANT UPDATE(stop_generation,last_public_identity_id,last_public_at,last_public_ordinal)
    ON c_posts.account_publication_control TO hnuhole_c_runtime;
GRANT UPDATE(visibility,published_attempt_version,published_at,publication_ordinal,deleted_at)
    ON c_posts.posts TO hnuhole_c_runtime;
GRANT UPDATE(latest_attempt_version,owner_visible) ON c_posts.publication_tasks TO hnuhole_c_runtime;
GRANT UPDATE(state,terminal_at,failure_code) ON c_posts.publication_attempts TO hnuhole_c_runtime;
-- guard_content 仅接受一次整份擦除；授予这些列也不能改写已授权文字。
GRANT UPDATE(title,body,erased_at) ON c_posts.attempt_contents TO hnuhole_c_runtime;
-- 仅账号正式关闭后的墓碑收缩可通过 guard_receipt；原始结果不可改写。
GRANT UPDATE(owner_account_id,outcome,task_id,post_id,attempt_version,task_state,error_code)
    ON c_posts.command_receipts TO hnuhole_c_runtime;
GRANT UPDATE(state) ON c_posts.payload_cleanup TO hnuhole_c_runtime;
GRANT USAGE ON SEQUENCE c_posts.publication_ordinal_seq,c_posts.acceptance_ordinal_seq TO hnuhole_c_runtime;
GRANT EXECUTE ON FUNCTION c_posts.allocate_identity_label(uuid) TO hnuhole_c_runtime;

-- 0020: account-private interactions, including closure with HTTP disabled.
DO $$ BEGIN
 IF to_regclass('c_posts.post_likes') IS NOT NULL THEN
  GRANT SELECT,INSERT,DELETE ON c_posts.post_likes,c_posts.post_favorites TO hnuhole_c_runtime;
 END IF;
END $$;

-- 0019: closure cleanup also runs when post HTTP endpoints are disabled.
DO $$ BEGIN
 IF to_regclass('c_posts.feed_preferences') IS NOT NULL THEN
  GRANT SELECT,INSERT ON c_posts.post_view_totals,c_posts.post_daily_views,c_posts.feed_preferences TO hnuhole_c_runtime;
  GRANT UPDATE(view_count) ON c_posts.post_view_totals TO hnuhole_c_runtime;
  GRANT UPDATE(blocked_channel_ids,revision) ON c_posts.feed_preferences TO hnuhole_c_runtime;
  GRANT DELETE ON c_posts.post_daily_views,c_posts.feed_preferences TO hnuhole_c_runtime;
 END IF;
END $$;

-- 0014's image triggers also protect text-only writes. Lifecycle cleanup
-- must erase existing bytes/grants even when the image HTTP API is disabled.
-- Upload insertion and verification columns remain a separate opt-in grant.
DO $$ BEGIN
 IF to_regclass('c_posts.images') IS NOT NULL THEN
  GRANT SELECT ON c_posts.images TO hnuhole_c_runtime;
  GRANT UPDATE(payload,erased_at,grant_digest,grant_expires_at)
   ON c_posts.images TO hnuhole_c_runtime;
 END IF;
END $$;

-- 0016 lifecycle hooks run even with the comment HTTP feature disabled.
DO $$ BEGIN
 IF to_regnamespace('c_comments') IS NOT NULL THEN
  GRANT USAGE ON SCHEMA c_comments TO hnuhole_c_runtime;
  GRANT SELECT ON c_comments.tasks,c_comments.attempts TO hnuhole_c_runtime;
  GRANT UPDATE(owner_visible) ON c_comments.tasks TO hnuhole_c_runtime;
  GRANT UPDATE(state,terminal_at,failure_code,body) ON c_comments.attempts TO hnuhole_c_runtime;
 END IF;
END $$;

-- 0015 lifecycle hooks execute on old post/closure paths even when moderation
-- HTTP features are disabled. Grant only their cleanup operations here.
DO $$ BEGIN
 IF to_regnamespace('c_moderation') IS NOT NULL THEN
  GRANT USAGE ON SCHEMA c_moderation TO hnuhole_c_runtime;
  GRANT SELECT ON c_moderation.cases,c_moderation.reports,c_moderation.notifications TO hnuhole_c_runtime;
  GRANT UPDATE(state,outcome,explanation,version) ON c_moderation.cases TO hnuhole_c_runtime;
  GRANT UPDATE(reporter_account_id,identity_id) ON c_moderation.reports TO hnuhole_c_runtime;
  GRANT INSERT,DELETE ON c_moderation.notifications TO hnuhole_c_runtime;
  GRANT SELECT(account_id),DELETE ON c_moderation.access_sessions,c_moderation.roles TO hnuhole_c_runtime;
  -- Old trusted ban/mute commands keep a separate baseline when 0015 exists.
  GRANT SELECT ON c_moderation.legacy_restrictions TO hnuhole_c_runtime;
  GRANT SELECT(account_id,action,revoked_at,ends_at) ON c_moderation.sanctions TO hnuhole_c_runtime;
  GRANT INSERT(account_id,ban_state,ban_ends_at,mute_state,mute_ends_at),
   UPDATE(ban_state,ban_ends_at,mute_state,mute_ends_at)
   ON c_moderation.legacy_restrictions TO hnuhole_c_runtime;
  GRANT UPDATE(moderation_rename_required) ON public.community_identities TO hnuhole_c_runtime;
 END IF;
END $$;

-- Comment lifecycle cleanup remains active when comment HTTP is disabled.
DO $$ BEGIN
 IF to_regclass('c_posts.post_interaction_versions') IS NOT NULL THEN
  GRANT SELECT,INSERT,DELETE ON c_posts.post_interaction_versions TO hnuhole_c_runtime;
  GRANT UPDATE(version) ON c_posts.post_interaction_versions TO hnuhole_c_runtime;
 END IF;
END $$;

-- Comment lifecycle cleanup remains active when comment HTTP is disabled.
DO $$ BEGIN
 IF to_regclass('c_comments.images') IS NOT NULL THEN
  GRANT SELECT ON c_comments.images TO hnuhole_c_runtime;
  GRANT UPDATE(payload,metadata,erased_at) ON c_comments.images TO hnuhole_c_runtime;
 END IF;
END $$;

-- 0026 private repost writes and account/identity lifecycle cleanup.
DO $$ BEGIN
 IF to_regclass('c_posts.post_reposts') IS NOT NULL THEN
  GRANT SELECT,INSERT,DELETE ON c_posts.post_reposts,c_posts.post_repost_versions TO hnuhole_c_runtime;
  GRANT UPDATE(version) ON c_posts.post_repost_versions TO hnuhole_c_runtime;
  GRANT USAGE ON SEQUENCE c_posts.post_reposts_ordinal_seq TO hnuhole_c_runtime;
 END IF;
END $$;

-- 0024 cleanup must remain possible with DM HTTP disabled. No send/report insert.
DO $$ BEGIN
 IF to_regclass('c_dm.blocks') IS NOT NULL THEN
  GRANT USAGE ON SCHEMA c_dm TO hnuhole_c_runtime;
  GRANT SELECT ON c_dm.conversations,c_dm.messages,c_dm.media,c_dm.settings,c_dm.blocks TO hnuhole_c_runtime;
  GRANT UPDATE(revision) ON c_dm.conversations TO hnuhole_c_runtime;
  GRANT UPDATE(body,acknowledged,read) ON c_dm.messages TO hnuhole_c_runtime;
  GRANT UPDATE(bytes) ON c_dm.media TO hnuhole_c_runtime;
  GRANT UPDATE(version,note,pinned,muted,hidden_through,deleted_through) ON c_dm.settings TO hnuhole_c_runtime;
  GRANT DELETE ON c_dm.blocks TO hnuhole_c_runtime;
 END IF;
END $$;

-- 0027: transient admission facts only. Runtime cannot create/reinitialize the
-- durable namespace, alter its singleton identity, or grant cross-domain access.
DO $$ BEGIN
 IF to_regclass('c_rate_limit.admissions') IS NOT NULL THEN
  REVOKE ALL ON SCHEMA c_rate_limit FROM PUBLIC;
  REVOKE ALL ON ALL TABLES IN SCHEMA c_rate_limit FROM PUBLIC,hnuhole_c_runtime;
  GRANT USAGE ON SCHEMA c_rate_limit TO hnuhole_c_runtime;
  GRANT SELECT ON c_rate_limit.namespace TO hnuhole_c_runtime;
  GRANT UPDATE(generation,run_id,state,barrier_until,dirty_until) ON c_rate_limit.namespace TO hnuhole_c_runtime;
  GRANT SELECT,INSERT,DELETE ON c_rate_limit.admissions TO hnuhole_c_runtime;
  GRANT UPDATE(state,generation,incarnation,confirmed_at,deadline) ON c_rate_limit.admissions TO hnuhole_c_runtime;
 END IF;
END $$;
