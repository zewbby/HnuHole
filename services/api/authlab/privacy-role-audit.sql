-- Only this invocation's freshly migrated C or V development database.
-- Inspect the real LOGIN roles, rather than assuming an owner fixture proves
-- least privilege. Failure messages are fixed and contain no table row data.
SET authlab.party TO :'party';
DO $$
DECLARE
  party text := current_setting('authlab.party');
  own_schema text;
  runtime_role text;
  recovery_role text;
  audit_role text;
  roles text[];
  relation record;
  privilege text;
  allowed boolean;
  granted boolean;
BEGIN
  IF party NOT IN ('c','v') OR current_database() <> 'hnuhole_' || party THEN
    RAISE EXCEPTION 'privacy audit requires its known disposable database';
  END IF;
  own_schema := party || '_auth';
  runtime_role := 'hnuhole_' || party || '_runtime';
  recovery_role := 'hnuhole_' || party || '_recovery';
  roles := ARRAY[runtime_role,recovery_role];
  IF party='c' THEN roles := array_append(roles,'hnuhole_business'); END IF;
  IF to_regnamespace(CASE party WHEN 'c' THEN 'v_auth' ELSE 'c_auth' END) IS NOT NULL
    OR EXISTS(SELECT 1 FROM pg_roles WHERE rolname LIKE 'hnuhole_' || CASE party WHEN 'c' THEN 'v' ELSE 'c' END || '_%') THEN
    RAISE EXCEPTION 'counterpart schema or credentials share this database cluster';
  END IF;
  FOREACH audit_role IN ARRAY roles LOOP
    IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname=audit_role AND NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole AND NOT rolreplication AND NOT rolbypassrls)
      OR EXISTS(SELECT 1 FROM pg_auth_members m JOIN pg_roles r ON r.oid=m.member WHERE r.rolname=audit_role)
      OR has_database_privilege(audit_role,current_database(),'CREATE')
      OR has_database_privilege(audit_role,current_database(),'TEMP') THEN
      RAISE EXCEPTION 'operational role acquired owner, membership, or database creation authority';
    END IF;
    FOR relation IN SELECT oid,nspname FROM pg_namespace WHERE nspname NOT LIKE 'pg_%' AND nspname<>'information_schema' LOOP
      IF has_schema_privilege(audit_role,relation.oid,'CREATE') THEN
        RAISE EXCEPTION 'operational role can create schema objects';
      END IF;
    END LOOP;
    FOR relation IN
      SELECT c.oid,n.nspname,c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname NOT LIKE 'pg_%' AND n.nspname<>'information_schema' AND c.relkind IN ('r','p','v','m','f')
    LOOP
      FOREACH privilege IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP
        granted := has_table_privilege(audit_role,relation.oid,privilege);
        IF privilege IN ('SELECT','INSERT','UPDATE','REFERENCES') THEN
          granted := granted OR has_any_column_privilege(audit_role,relation.oid,privilege);
        END IF;
        allowed := false;
        IF audit_role=recovery_role AND relation.nspname=own_schema THEN
          allowed := (relation.relname='authorization_gate' AND privilege IN ('SELECT','UPDATE'))
            OR (relation.relname='authorization_gate_audit' AND privilege IN ('SELECT','INSERT'));
        ELSIF audit_role='hnuhole_business' THEN
          allowed := relation.nspname='public' AND relation.relname='channels' AND privilege='SELECT';
        ELSIF audit_role=runtime_role THEN
          allowed := relation.nspname=own_schema AND privilege IN ('SELECT','INSERT','UPDATE','DELETE');
          IF relation.nspname='public' THEN
            allowed := privilege='SELECT' AND relation.relname='goose_db_version';
            IF party='c' THEN
              allowed := allowed OR (relation.relname='channels' AND privilege='SELECT')
                OR (relation.relname IN ('community_identities','identity_account_state') AND privilege IN ('SELECT','INSERT','UPDATE'))
                OR (relation.relname='identity_change_receipts' AND privilege IN ('SELECT','INSERT'));
            END IF;
          END IF;
          IF relation.nspname=own_schema AND relation.relname='authorization_gate' AND privilege IN ('INSERT','DELETE') THEN allowed := false; END IF;
          IF relation.nspname=own_schema AND relation.relname='authorization_gate_audit' AND privilege IN ('UPDATE','DELETE') THEN allowed := false; END IF;
        END IF;
        IF granted AND NOT allowed THEN RAISE EXCEPTION 'operational role acquired noncontract table privilege'; END IF;
      END LOOP;
    END LOOP;
    FOR relation IN
      SELECT c.oid,n.nspname,c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname NOT LIKE 'pg_%' AND c.relkind='S'
    LOOP
      FOREACH privilege IN ARRAY ARRAY['USAGE','SELECT','UPDATE'] LOOP
        allowed := privilege='USAGE' AND relation.nspname=own_schema AND
          (audit_role=runtime_role OR (audit_role=recovery_role AND relation.relname='authorization_gate_audit_event_id_seq'));
        IF has_sequence_privilege(audit_role,relation.oid,privilege) AND NOT allowed THEN RAISE EXCEPTION 'operational role acquired noncontract sequence privilege'; END IF;
      END LOOP;
    END LOOP;
  END LOOP;
  IF party='v' AND (has_column_privilege(runtime_role,'v_auth.authorization_gate','authorization_generation','UPDATE')
    OR has_column_privilege(runtime_role,'v_auth.authorization_gate','opened_at','UPDATE')) THEN
    RAISE EXCEPTION 'V runtime acquired Gate recovery columns';
  END IF;
END $$;
