-- +goose Up
ALTER TABLE v_auth.otp_flows ADD COLUMN purpose text NOT NULL DEFAULT 'REGISTER' CHECK(purpose IN ('REGISTER','LOGIN'));
CREATE TABLE v_auth.email_login_confirmations (
 key_digest bytea PRIMARY KEY CHECK(octet_length(key_digest)=32),
 request_hmac bytea NOT NULL CHECK(octet_length(request_hmac)=32),
 flow_id bytea NOT NULL CHECK(octet_length(flow_id)=32),
 installation_id bytea NOT NULL CHECK(octet_length(installation_id)=16),
 binding bytea NOT NULL CHECK(octet_length(binding)=32),
 result_code text NOT NULL,
 proof text,
 expires_at timestamptz NOT NULL,
 authorization_generation bigint NOT NULL CHECK(authorization_generation>0)
);
-- +goose StatementBegin
CREATE FUNCTION v_auth.guard_otp_purpose() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF NEW.purpose IS DISTINCT FROM OLD.purpose THEN RAISE EXCEPTION 'OTP purpose is immutable' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER otp_purpose_immutable BEFORE UPDATE ON v_auth.otp_flows FOR EACH ROW EXECUTE FUNCTION v_auth.guard_otp_purpose();
-- +goose StatementEnd
REVOKE ALL ON v_auth.email_login_confirmations FROM PUBLIC;
-- +goose Down
-- +goose StatementBegin
DO $$ BEGIN RAISE EXCEPTION 'Email login requires freeze and forward repair'; END $$;
-- +goose StatementEnd
