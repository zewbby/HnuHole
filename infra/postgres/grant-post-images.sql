-- Explicit opt-in after 0014, separately from the accepted text grants.
-- Execute only against a disposable/approved database as its migration owner.
REVOKE ALL ON c_posts.images FROM PUBLIC,hnuhole_c_runtime,hnuhole_c_recovery,hnuhole_business;
GRANT SELECT,INSERT ON c_posts.images TO hnuhole_c_runtime;
GRANT UPDATE(payload,verified_at,erased_at,display_width,display_height,frames,cycle_duration_ms,max_frame_duration_ms,grant_digest,grant_expires_at)
 ON c_posts.images TO hnuhole_c_runtime;
