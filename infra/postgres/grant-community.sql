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
