-- Owner-only first administrator bootstrap. Later changes use the audited API.
-- psql -X -v ON_ERROR_STOP=1 -v platform_number=001527 <owner DSN> -f this-file
\set ON_ERROR_STOP on
BEGIN;
SELECT set_config('hnuhole.bootstrap_platform_number', :'platform_number', true);
DO $$
DECLARE
    chosen uuid;
    target_number text := current_setting('hnuhole.bootstrap_platform_number');
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_class WHERE oid='c_moderation.roles'::regclass
                   AND relowner=(SELECT oid FROM pg_roles WHERE rolname=current_user)) THEN
        RAISE EXCEPTION 'bootstrap requires the moderation table owner';
    END IF;
    IF target_number !~ '^[0-9]{6}$' THEN RAISE EXCEPTION 'expected six digit platform number'; END IF;
    SELECT account_id INTO chosen FROM c_auth.accounts
      WHERE platform_number=target_number AND state='ACTIVE' FOR UPDATE;
    IF chosen IS NULL THEN RAISE EXCEPTION 'active platform account not found'; END IF;
    PERFORM pg_advisory_xact_lock(850018);
    IF EXISTS(SELECT 1 FROM c_moderation.roles WHERE role='ADMIN') THEN
        RAISE EXCEPTION 'administrator exists; use the audited role API';
    END IF;
    INSERT INTO c_moderation.roles(account_id,role) VALUES(chosen,'ADMIN')
      ON CONFLICT(account_id) DO UPDATE SET role=EXCLUDED.role;
    INSERT INTO c_moderation.audit(actor_number,target_number,action,reason,created_at)
      VALUES(target_number,target_number,'BOOTSTRAP_ADMIN','owner bootstrap of first administrator',clock_timestamp());
END $$;
COMMIT;
