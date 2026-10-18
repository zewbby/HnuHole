-- Owned lab only. Restores use --no-privileges and then rebuild canonical ACLs.
-- In particular, newly restored functions otherwise regain PUBLIC EXECUTE.
DO $$ BEGIN
 IF current_database()<>'hnuhole_c' OR to_regnamespace('c_moderation') IS NULL THEN
  RAISE EXCEPTION 'moderation grant reset requires its migrated private C database';
 END IF;
END $$;
REVOKE ALL ON SCHEMA c_moderation FROM PUBLIC,hnuhole_c_runtime,hnuhole_c_recovery,hnuhole_business;
REVOKE ALL ON ALL TABLES IN SCHEMA c_moderation FROM PUBLIC,hnuhole_c_runtime,hnuhole_c_recovery,hnuhole_business;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA c_moderation FROM PUBLIC,hnuhole_c_runtime,hnuhole_c_recovery,hnuhole_business;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA c_moderation FROM PUBLIC,hnuhole_c_runtime,hnuhole_c_recovery,hnuhole_business;
