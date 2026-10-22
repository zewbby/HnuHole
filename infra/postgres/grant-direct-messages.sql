-- P1 isolated runtime only; migration owner applies after 0022.
GRANT USAGE ON SCHEMA c_dm TO hnuhole_c_runtime;
GRANT SELECT,INSERT ON c_dm.conversations,c_dm.commands,c_dm.messages,c_dm.binding_acceptances TO hnuhole_c_runtime;
GRANT UPDATE(sequence,low_sent,high_sent) ON c_dm.conversations TO hnuhole_c_runtime;
GRANT UPDATE(attempt,state,error_code,message_id,conversation_id,sequence,accepted_at) ON c_dm.commands TO hnuhole_c_runtime;
GRANT UPDATE(body,acknowledged,read) ON c_dm.messages TO hnuhole_c_runtime;
