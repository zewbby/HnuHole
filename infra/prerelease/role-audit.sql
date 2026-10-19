-- Private source/restored clusters only; @PARTY@ is replaced with c or v.
DO $audit$
DECLARE p text := '@PARTY@'; r text := 'hnuhole_@PARTY@_runtime';
BEGIN
 IF current_database() <> 'hnuhole_' || p THEN RAISE EXCEPTION 'wrong database'; END IF;
 IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname=r AND
   (rolsuper OR rolcreatedb OR rolcreaterole OR rolreplication OR rolbypassrls))
   OR pg_has_role(r,'hnuhole_'||p||'_owner','MEMBER')
   OR pg_has_role(r,'hnuhole_'||p||'_recovery','MEMBER')
   OR has_database_privilege(r,current_database(),'TEMP')
   OR has_schema_privilege(r,'public','CREATE')
 THEN RAISE EXCEPTION 'runtime acquired administrative privilege'; END IF;
 IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname LIKE 'hnuhole_' || CASE p WHEN 'c' THEN 'v' ELSE 'c' END || '%')
 THEN RAISE EXCEPTION 'C and V share a cluster'; END IF;
 IF has_table_privilege(r,p||'_auth.authorization_gate','INSERT,DELETE,TRUNCATE')
   OR has_table_privilege('hnuhole_'||p||'_recovery',p||'_auth.authorization_gate_audit','UPDATE,DELETE,TRUNCATE')
 THEN RAISE EXCEPTION 'Gate privilege exceeded'; END IF;
 IF p='c' THEN
  IF has_table_privilege(r,'public.sessions','SELECT,INSERT,UPDATE,DELETE')
   OR NOT has_table_privilege(r,'c_posts.images','SELECT')
   OR NOT has_table_privilege(r,'c_posts.images','INSERT')
   OR has_table_privilege(r,'c_posts.images','UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
   OR has_any_column_privilege('hnuhole_c_recovery','c_posts.images','SELECT,INSERT,UPDATE,REFERENCES')
   OR has_any_column_privilege('hnuhole_business','c_posts.images','SELECT,INSERT,UPDATE,REFERENCES')
   OR has_table_privilege(r,'c_posts.command_receipts','UPDATE,DELETE,TRUNCATE')
  THEN RAISE EXCEPTION 'image/receipt/legacy privilege mismatch'; END IF;
 END IF;
END
$audit$;
SELECT 'PASS';
