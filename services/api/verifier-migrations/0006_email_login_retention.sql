-- +goose Up
ALTER TABLE v_auth.email_login_confirmations
 ALTER COLUMN request_hmac DROP NOT NULL,
 ALTER COLUMN flow_id DROP NOT NULL,
 ALTER COLUMN installation_id DROP NOT NULL,
 ALTER COLUMN binding DROP NOT NULL;
-- +goose StatementBegin
CREATE FUNCTION v_auth.guard_email_login_tombstone() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'email login replay anchors are permanent' USING ERRCODE='23514'; END IF;
 IF OLD.result_code='EXPIRED' AND NEW IS DISTINCT FROM OLD THEN RAISE EXCEPTION 'expired email login cannot reopen' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER email_login_tombstone_immutable BEFORE UPDATE OR DELETE ON v_auth.email_login_confirmations FOR EACH ROW EXECUTE FUNCTION v_auth.guard_email_login_tombstone();
-- +goose StatementEnd
-- +goose Down
-- +goose StatementBegin
DO $$ BEGIN RAISE EXCEPTION 'Email login retention requires forward repair'; END $$;
-- +goose StatementEnd
