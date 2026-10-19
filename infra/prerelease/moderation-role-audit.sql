-- Exact deployed main 0015 + grant-moderation.sql contract, private C only.
-- This replaces only c_moderation's table/sequence part of the legacy audit.
DO $audit$
DECLARE
 r text; relation record; col record; f record; privilege text;
 allowed boolean; allowed_columns text[];
 tables text[] := ARRAY['schema_meta','platform_numbers','roles','access_sessions','legacy_restrictions',
   'cases','reports','sanctions','appeals','appeal_materials','notifications','commands','request_fences','audit'];
BEGIN
 IF current_database()<>'hnuhole_c' OR to_regnamespace('c_moderation') IS NULL THEN
  RAISE EXCEPTION 'moderation audit requires its migrated private C database';
 END IF;
 FOREACH r IN ARRAY ARRAY['hnuhole_c_runtime','hnuhole_c_recovery','hnuhole_business'] LOOP
  IF has_schema_privilege(r,'c_moderation','USAGE')<>(r='hnuhole_c_runtime')
    OR has_schema_privilege(r,'c_moderation','CREATE') THEN
   RAISE EXCEPTION 'moderation schema privilege mismatch';
  END IF;
  FOR relation IN SELECT c.oid,c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='c_moderation' AND c.relkind IN ('r','p','v','m','f') LOOP
   IF NOT relation.relname=ANY(tables) THEN RAISE EXCEPTION 'unexpected moderation relation'; END IF;
   FOREACH privilege IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP
    allowed := r='hnuhole_c_runtime' AND (privilege='SELECT'
      OR (privilege='INSERT' AND relation.relname IN ('roles','access_sessions','cases','reports','sanctions','appeals','appeal_materials','notifications','commands','request_fences','audit'))
      OR (privilege='DELETE' AND relation.relname IN ('roles','access_sessions','notifications')));
    IF has_table_privilege(r,relation.oid,privilege)<>allowed THEN
     RAISE EXCEPTION 'moderation table privilege mismatch';
    END IF;
    IF privilege IN ('SELECT','INSERT','UPDATE','REFERENCES') THEN
     allowed_columns := ARRAY[]::text[];
     IF r='hnuhole_c_runtime' AND privilege='UPDATE' THEN
      allowed_columns := CASE relation.relname
       WHEN 'roles' THEN ARRAY['role'] WHEN 'access_sessions' THEN ARRAY['revoked_at']
       WHEN 'cases' THEN ARRAY['state','version','outcome','explanation','decided_by']
       WHEN 'reports' THEN ARRAY['reporter_account_id','identity_id']
       WHEN 'sanctions' THEN ARRAY['revoked_at'] WHEN 'appeals' THEN ARRAY['state','version','reason']
       WHEN 'notifications' THEN ARRAY['read_at'] WHEN 'request_fences' THEN ARRAY['retry_token']
       WHEN 'legacy_restrictions' THEN ARRAY['ban_state','ban_ends_at','mute_state','mute_ends_at']
       ELSE ARRAY[]::text[] END;
     ELSIF r='hnuhole_c_runtime' AND privilege='INSERT' AND relation.relname='legacy_restrictions' THEN
      allowed_columns := ARRAY['account_id','ban_state','ban_ends_at','mute_state','mute_ends_at'];
     END IF;
     FOR col IN SELECT attname FROM pg_attribute WHERE attrelid=relation.oid AND attnum>0 AND NOT attisdropped LOOP
      IF has_column_privilege(r,relation.oid,col.attname,privilege)<>(allowed OR col.attname=ANY(allowed_columns)) THEN
       RAISE EXCEPTION 'moderation column privilege mismatch';
      END IF;
     END LOOP;
    END IF;
   END LOOP;
  END LOOP;
  FOR relation IN SELECT c.oid,c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='c_moderation' AND c.relkind='S' LOOP
   FOREACH privilege IN ARRAY ARRAY['USAGE','SELECT','UPDATE'] LOOP
    allowed := r='hnuhole_c_runtime' AND privilege='USAGE' AND relation.relname IN ('cases_number_seq','audit_audit_id_seq');
    IF has_sequence_privilege(r,relation.oid,privilege)<>allowed THEN
     RAISE EXCEPTION 'moderation sequence privilege mismatch';
    END IF;
   END LOOP;
  END LOOP;
  FOR f IN SELECT p.oid,p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='c_moderation' LOOP
   allowed := r='hnuhole_c_runtime' AND f.proname IN ('immutable_audit','deleted_post','closed_account');
   IF has_function_privilege(r,f.oid,'EXECUTE')<>allowed THEN RAISE EXCEPTION 'moderation function privilege mismatch'; END IF;
  END LOOP;
 END LOOP;
END
$audit$;
