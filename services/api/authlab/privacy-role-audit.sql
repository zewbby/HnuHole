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
              allowed := allowed OR (relation.relname='identity_avatar_assets' AND privilege IN ('SELECT','INSERT'));
              IF relation.relname='identity_avatar_assets' AND privilege='UPDATE' THEN
                allowed := NOT has_table_privilege(audit_role,relation.oid,'UPDATE')
                  AND NOT EXISTS(SELECT 1 FROM pg_attribute a WHERE a.attrelid=relation.oid AND a.attnum>0 AND NOT a.attisdropped AND a.attname NOT IN ('identity_id','payload') AND has_column_privilege(audit_role,relation.oid,a.attname,'UPDATE'));
              END IF;
            END IF;
          END IF;
          IF relation.nspname=own_schema AND relation.relname='authorization_gate' AND privilege IN ('INSERT','DELETE') THEN allowed := false; END IF;
          IF relation.nspname=own_schema AND relation.relname='authorization_gate_audit' AND privilege IN ('UPDATE','DELETE') THEN allowed := false; END IF;
          -- 文字业务仍只归 C runtime；独立恢复与普通 business 不能读任务或正文。
          -- 0014 requires image reads and four lifecycle-erasure columns even
          -- with the image API off. Upload insertion/verification stay separate.
          IF party='c' AND relation.nspname='c_posts' THEN
            allowed := (privilege='SELECT' AND relation.relname IN ('schema_meta','protocol_keys','account_publication_control',
              'publication_stop_events','identity_public_labels','posts','post_identity_bindings',
              'publication_tasks','publication_attempts','attempt_contents','command_receipts','payload_cleanup','images'))
              OR (privilege='INSERT' AND relation.relname IN ('protocol_keys','account_publication_control','publication_stop_events',
              'identity_public_labels','posts','post_identity_bindings','publication_tasks','publication_attempts',
              'attempt_contents','command_receipts','payload_cleanup'))
              OR (privilege='UPDATE' AND relation.relname IN ('account_publication_control','posts','publication_tasks',
              'publication_attempts','attempt_contents','command_receipts','payload_cleanup'));
            allowed := allowed OR (relation.relname IN ('post_view_totals','post_daily_views','feed_preferences') AND privilege IN ('SELECT','INSERT'))
              OR (relation.relname IN ('post_daily_views','feed_preferences') AND privilege='DELETE')
              OR (relation.relname IN ('post_likes','post_favorites','post_interaction_versions','post_reposts','post_repost_versions') AND privilege IN ('SELECT','INSERT','DELETE'));
            -- 0026 private repost archives retain only their account/post
            -- fence's version update; archive rows remain immutable.
            IF relation.relname IN ('post_interaction_versions','post_repost_versions') AND privilege='UPDATE' THEN
              allowed := NOT has_table_privilege(audit_role,relation.oid,'UPDATE')
                AND NOT EXISTS(SELECT 1 FROM pg_attribute a WHERE a.attrelid=relation.oid AND a.attnum>0 AND NOT a.attisdropped AND a.attname<>'version' AND has_column_privilege(audit_role,relation.oid,a.attname,'UPDATE'));
            END IF;
            IF relation.relname IN ('post_view_totals','feed_preferences') AND privilege='UPDATE' THEN
              allowed := NOT has_table_privilege(audit_role,relation.oid,'UPDATE')
                AND NOT EXISTS(SELECT 1 FROM pg_attribute a WHERE a.attrelid=relation.oid
                  AND a.attnum>0 AND NOT a.attisdropped
                  AND NOT (a.attname=ANY(CASE relation.relname WHEN 'post_view_totals' THEN ARRAY['view_count'] ELSE ARRAY['blocked_channel_ids','revision'] END))
                  AND has_column_privilege(audit_role,relation.oid,a.attname,'UPDATE'));
            END IF;
            IF relation.relname='images' AND privilege='UPDATE' THEN
              allowed := NOT has_table_privilege(audit_role,relation.oid,'UPDATE')
                AND NOT EXISTS(SELECT 1 FROM pg_attribute a
                  WHERE a.attrelid=relation.oid AND a.attnum>0 AND NOT a.attisdropped
                    AND a.attname NOT IN ('payload','erased_at','grant_digest','grant_expires_at')
                    AND has_column_privilege(audit_role,relation.oid,a.attname,'UPDATE'));
            END IF;
          END IF;
          IF party='c' AND relation.nspname='c_comments' THEN
            allowed := (privilege IN ('SELECT','INSERT') AND relation.relname IN ('protocol_keys','tasks','attempts','receipts','snapshots','images','likes'))
              OR (privilege='DELETE' AND relation.relname IN ('snapshots','likes'));
            IF privilege='UPDATE' AND relation.relname IN ('tasks','attempts','images') THEN
              allowed := NOT has_table_privilege(audit_role,relation.oid,'UPDATE')
                AND NOT EXISTS(SELECT 1 FROM pg_attribute a WHERE a.attrelid=relation.oid
                  AND a.attnum>0 AND NOT a.attisdropped
                  AND NOT (a.attname=ANY(CASE relation.relname WHEN 'tasks' THEN ARRAY['owner_visible','abandoned_at','deleted_at','moderation_hidden'] WHEN 'images' THEN ARRAY['payload','metadata','erased_at'] ELSE ARRAY['state','terminal_at','failure_code','body'] END))
                  AND has_column_privilege(audit_role,relation.oid,a.attname,'UPDATE'));
            END IF;
          END IF;
          -- Common C lifecycle grants from 0015/0018, without optional
          -- moderator access, decisions, report/evidence insertion or appeals.
          IF party='c' AND relation.nspname='c_moderation' THEN
            allowed := (privilege='SELECT' AND relation.relname IN ('cases','reports','notifications','legacy_restrictions','access_sessions','roles','sanctions'))
              OR (privilege='INSERT' AND relation.relname='notifications')
              OR (privilege='DELETE' AND relation.relname IN ('notifications','access_sessions','roles'));
            IF privilege='SELECT' AND relation.relname IN ('access_sessions','roles','sanctions') THEN
              allowed := NOT has_table_privilege(audit_role,relation.oid,'SELECT')
                AND NOT EXISTS(SELECT 1 FROM pg_attribute a WHERE a.attrelid=relation.oid AND a.attnum>0 AND NOT a.attisdropped
                  AND NOT (a.attname=ANY(CASE relation.relname WHEN 'sanctions' THEN ARRAY['account_id','action','revoked_at','ends_at'] ELSE ARRAY['account_id'] END))
                  AND has_column_privilege(audit_role,relation.oid,a.attname,'SELECT'));
            END IF;
            IF (privilege='UPDATE' AND relation.relname IN ('cases','reports','legacy_restrictions')) OR (privilege='INSERT' AND relation.relname='legacy_restrictions') THEN
              allowed := NOT has_table_privilege(audit_role,relation.oid,privilege)
                AND NOT EXISTS(SELECT 1 FROM pg_attribute a WHERE a.attrelid=relation.oid AND a.attnum>0 AND NOT a.attisdropped
                  AND NOT (a.attname=ANY(CASE relation.relname WHEN 'cases' THEN ARRAY['state','outcome','explanation','version'] WHEN 'reports' THEN ARRAY['reporter_account_id','identity_id'] ELSE ARRAY['account_id','ban_state','ban_ends_at','mute_state','mute_ends_at'] END))
                  AND has_column_privilege(audit_role,relation.oid,a.attname,privilege));
            END IF;
          END IF;
          -- 0024 lifecycle cleanup applies even with the DM API disabled.
          -- Sending, operation receipts and immutable evidence remain outside
          -- this baseline; do not admit the optional full DM grant here.
          IF party='c' AND relation.nspname='c_dm' THEN
            allowed := (privilege='SELECT' AND relation.relname IN ('conversations','messages','media','settings','blocks'))
              OR (privilege='DELETE' AND relation.relname='blocks');
            IF privilege='UPDATE' AND relation.relname IN ('conversations','messages','media','settings') THEN
              allowed := NOT has_table_privilege(audit_role,relation.oid,'UPDATE')
                AND NOT EXISTS(SELECT 1 FROM pg_attribute a WHERE a.attrelid=relation.oid
                  AND a.attnum>0 AND NOT a.attisdropped
                  AND NOT (a.attname=ANY(CASE relation.relname
                    WHEN 'conversations' THEN ARRAY['revision']
                    WHEN 'messages' THEN ARRAY['body','acknowledged','read']
                    WHEN 'media' THEN ARRAY['bytes']
                    ELSE ARRAY['version','note','pinned','muted','hidden_through','deleted_through'] END))
                  AND has_column_privilege(audit_role,relation.oid,a.attname,'UPDATE'));
            END IF;
          END IF;
          -- Shared quota metadata is service-local and contains no credentials,
          -- email, community identity or body. Policy and singleton authority
          -- remain owner-only; runtime can only persist loss/dirty recovery.
          IF relation.nspname=party||'_rate_limit' THEN
            allowed := (relation.relname='namespace' AND privilege='SELECT')
              OR (party='c' AND relation.relname='admissions' AND privilege IN ('SELECT','INSERT','DELETE'));
            IF privilege='UPDATE' AND (relation.relname='namespace' OR (party='c' AND relation.relname='admissions')) THEN
              allowed := NOT has_table_privilege(audit_role,relation.oid,'UPDATE')
                AND NOT EXISTS(SELECT 1 FROM pg_attribute a WHERE a.attrelid=relation.oid AND a.attnum>0 AND NOT a.attisdropped
                  AND NOT (a.attname=ANY(CASE relation.relname WHEN 'namespace' THEN ARRAY['generation','run_id','state','barrier_until','dirty_until'] ELSE ARRAY['state','generation','incarnation','confirmed_at','deadline'] END))
                  AND has_column_privilege(audit_role,relation.oid,a.attname,'UPDATE'));
            END IF;
          END IF;
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
        allowed := allowed OR (party='c' AND audit_role=runtime_role AND privilege='USAGE'
          AND relation.nspname='c_posts' AND relation.relname IN ('publication_ordinal_seq','acceptance_ordinal_seq','post_reposts_ordinal_seq'));
        IF has_sequence_privilege(audit_role,relation.oid,privilege) AND NOT allowed THEN RAISE EXCEPTION 'operational role acquired noncontract sequence privilege'; END IF;
      END LOOP;
    END LOOP;
  END LOOP;
  IF party='v' AND (has_column_privilege(runtime_role,'v_auth.authorization_gate','authorization_generation','UPDATE')
    OR has_column_privilege(runtime_role,'v_auth.authorization_gate','opened_at','UPDATE')) THEN
    RAISE EXCEPTION 'V runtime acquired Gate recovery columns';
  END IF;
END $$;
