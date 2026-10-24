-- P1 isolated runtime only; migration owner applies after 0023.
GRANT USAGE ON SCHEMA c_dm TO hnuhole_c_runtime;
GRANT SELECT,INSERT ON c_dm.conversations,c_dm.commands,c_dm.messages,c_dm.binding_acceptances TO hnuhole_c_runtime;
GRANT UPDATE(sequence,low_sent,high_sent,revision) ON c_dm.conversations TO hnuhole_c_runtime;
GRANT UPDATE(attempt,state,error_code,message_id,conversation_id,sequence,accepted_at) ON c_dm.commands TO hnuhole_c_runtime;
GRANT UPDATE(body,acknowledged,read,retracted) ON c_dm.messages TO hnuhole_c_runtime;

GRANT SELECT,INSERT ON c_dm.settings,c_dm.image_groups,c_dm.media,c_dm.operations,c_dm.controls TO hnuhole_c_runtime;
GRANT UPDATE(version,pinned,muted,note,hidden_through,deleted_through) ON c_dm.settings TO hnuhole_c_runtime;
GRANT UPDATE(bytes) ON c_dm.media TO hnuhole_c_runtime;
GRANT USAGE ON SEQUENCE c_dm.controls_sequence_seq TO hnuhole_c_runtime;

GRANT SELECT,INSERT,DELETE ON c_dm.blocks TO hnuhole_c_runtime;

-- Permanent close anchors; fingerprint and closed_at remain immutable to other commands.
GRANT UPDATE(closed_at) ON c_dm.commands TO hnuhole_c_runtime;
