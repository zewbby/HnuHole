REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA v_auth FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA v_auth FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA v_auth FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA v_auth FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA v_auth FROM hnuhole_v_runtime;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA v_auth FROM hnuhole_v_runtime;
REVOKE ALL ON SCHEMA v_auth FROM hnuhole_v_runtime;
GRANT USAGE ON SCHEMA v_auth TO hnuhole_v_runtime;
GRANT SELECT ON ALL TABLES IN SCHEMA v_auth TO hnuhole_v_runtime;
GRANT INSERT ON v_auth.confirmation_rejections,v_auth.confirmation_sign_jobs,v_auth.device_email_limits,v_auth.email_quota,v_auth.mail_outbox,v_auth.otp_budget_events,v_auth.otp_code_versions,v_auth.otp_confirmations,v_auth.otp_email_state,v_auth.otp_flows,v_auth.processed_receipts,v_auth.request_results,v_auth.retire_pending,v_auth.used_slots TO hnuhole_v_runtime;
GRANT UPDATE ON v_auth.confirmation_sign_jobs,v_auth.device_email_limits,v_auth.email_quota,v_auth.mail_outbox,v_auth.otp_code_versions,v_auth.otp_confirmations,v_auth.otp_email_state,v_auth.otp_flows,v_auth.request_results,v_auth.retire_pending,v_auth.used_slots TO hnuhole_v_runtime;
GRANT DELETE ON v_auth.confirmation_rejections,v_auth.confirmation_sign_jobs,v_auth.device_email_limits,v_auth.email_quota,v_auth.mail_outbox,v_auth.otp_budget_events,v_auth.otp_code_versions,v_auth.otp_confirmations,v_auth.otp_email_state,v_auth.otp_flows,v_auth.retire_pending TO hnuhole_v_runtime;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA v_auth TO hnuhole_v_runtime;

GRANT USAGE ON SCHEMA public TO hnuhole_v_runtime;
GRANT SELECT ON public.goose_db_version TO hnuhole_v_runtime;
