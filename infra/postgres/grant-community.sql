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
