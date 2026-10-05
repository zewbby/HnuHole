REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA v_auth FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA v_auth FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA v_auth FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA v_auth FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA v_auth FROM hnuhole_v_recovery;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA v_auth FROM hnuhole_v_recovery;
REVOKE ALL ON SCHEMA v_auth FROM hnuhole_v_recovery;
REVOKE ALL ON ALL TABLES IN SCHEMA v_auth FROM hnuhole_v_runtime;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA v_auth FROM hnuhole_v_runtime;
REVOKE ALL ON SCHEMA v_auth FROM hnuhole_v_runtime;
GRANT USAGE ON SCHEMA v_auth TO hnuhole_v_runtime;
GRANT SELECT ON ALL TABLES IN SCHEMA v_auth TO hnuhole_v_runtime;
GRANT INSERT ON v_auth.confirmation_rejections,v_auth.confirmation_sign_jobs,v_auth.device_email_limits,v_auth.email_quota,v_auth.mail_outbox,v_auth.otp_budget_events,v_auth.otp_code_versions,v_auth.otp_confirmations,v_auth.otp_email_state,v_auth.otp_flows,v_auth.processed_receipts,v_auth.request_results,v_auth.retire_pending,v_auth.used_slots TO hnuhole_v_runtime;
GRANT UPDATE ON v_auth.confirmation_sign_jobs,v_auth.device_email_limits,v_auth.email_quota,v_auth.mail_outbox,v_auth.otp_code_versions,v_auth.otp_confirmations,v_auth.otp_email_state,v_auth.otp_flows,v_auth.request_results,v_auth.retire_pending,v_auth.used_slots TO hnuhole_v_runtime;
GRANT DELETE ON v_auth.confirmation_rejections,v_auth.confirmation_sign_jobs,v_auth.device_email_limits,v_auth.email_quota,v_auth.mail_outbox,v_auth.otp_budget_events,v_auth.otp_code_versions,v_auth.otp_confirmations,v_auth.otp_email_state,v_auth.otp_flows,v_auth.retire_pending TO hnuhole_v_runtime;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA v_auth TO hnuhole_v_runtime;

-- Runtime may advance evidence/high-watermark and freeze. It cannot advance
-- authorization_generation, so the monotonic trigger prevents reopening.
GRANT UPDATE(gate_state,trusted_high_watermark,evidence_version,evidence_issued_at,evidence_valid_until,freeze_reason,frozen_at)
    ON v_auth.authorization_gate TO hnuhole_v_runtime;
GRANT INSERT ON v_auth.authorization_gate_audit TO hnuhole_v_runtime;
REVOKE INSERT ON v_auth.authorization_gate FROM hnuhole_v_runtime;
GRANT USAGE ON SCHEMA v_auth TO hnuhole_v_recovery;
GRANT SELECT,UPDATE ON v_auth.authorization_gate TO hnuhole_v_recovery;
GRANT SELECT,INSERT ON v_auth.authorization_gate_audit TO hnuhole_v_recovery;
GRANT USAGE ON SEQUENCE v_auth.authorization_gate_audit_event_id_seq TO hnuhole_v_recovery;

GRANT USAGE ON SCHEMA public TO hnuhole_v_runtime;
GRANT SELECT ON public.goose_db_version TO hnuhole_v_runtime;
