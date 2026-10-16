-- +goose Up
-- Keep historical data for a later contraction migration; no compatibility path.
UPDATE public.sessions SET revoked_at=COALESCE(revoked_at,clock_timestamp());
REVOKE ALL ON public.sessions FROM PUBLIC;
COMMENT ON SCHEMA c_auth IS 'Community development authentication with versioned schema and Gate; runtime privileges are provisioned separately';
-- Only the separately provisioned recovery role (or the migration owner, which
-- necessarily controls the trigger itself) may move FROZEN to OPEN.
-- +goose StatementBegin
CREATE FUNCTION c_auth.guard_recovery_role() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE owner_name name; recovery_role oid;
BEGIN
    IF OLD.gate_state='FROZEN' AND NEW.gate_state='OPEN' THEN
        SELECT pg_get_userbyid(relowner) INTO owner_name FROM pg_class WHERE oid=TG_RELID;
        recovery_role := to_regrole('hnuhole_c_recovery');
        IF current_user<>owner_name AND (recovery_role IS NULL OR NOT pg_has_role(current_user,recovery_role,'USAGE')) THEN
            RAISE EXCEPTION 'restricted recovery connection required' USING ERRCODE='42501';
        END IF;
    END IF;
    RETURN NEW;
END $$;
-- +goose StatementEnd
CREATE TRIGGER authorization_gate_recovery_role BEFORE UPDATE ON c_auth.authorization_gate
    FOR EACH ROW EXECUTE FUNCTION c_auth.guard_recovery_role();
-- +goose Down
-- +goose StatementBegin
DO $$ BEGIN RAISE EXCEPTION 'Legacy authentication fencing cannot be reversed'; END $$;
-- +goose StatementEnd
