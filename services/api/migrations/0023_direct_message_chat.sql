-- +goose Up
ALTER TABLE c_dm.conversations ADD COLUMN revision bigint NOT NULL DEFAULT 0 CHECK(revision>=0);
ALTER TABLE c_dm.messages ADD COLUMN kind text NOT NULL DEFAULT 'TEXT' CHECK(kind IN ('TEXT','IMAGE'));
ALTER TABLE c_dm.messages ADD COLUMN retracted boolean NOT NULL DEFAULT false;
CREATE TABLE c_dm.settings (
 conversation_id uuid NOT NULL REFERENCES c_dm.conversations,
 identity_id uuid NOT NULL REFERENCES public.community_identities,
 version bigint NOT NULL DEFAULT 0 CHECK(version>=0),
 pinned boolean NOT NULL DEFAULT false,
 muted boolean NOT NULL DEFAULT false,
 note text NOT NULL DEFAULT '' CHECK(octet_length(note)<=400),
 hidden_through bigint NOT NULL DEFAULT 0 CHECK(hidden_through>=0),
 deleted_through bigint NOT NULL DEFAULT 0 CHECK(deleted_through>=0),
 PRIMARY KEY(conversation_id,identity_id)
);
CREATE TABLE c_dm.image_groups (
 sender uuid NOT NULL REFERENCES public.community_identities,
 group_id uuid NOT NULL,
 conversation_id uuid NOT NULL REFERENCES c_dm.conversations,
 size integer NOT NULL CHECK(size BETWEEN 1 AND 9),
 PRIMARY KEY(sender,group_id)
);
CREATE TABLE c_dm.media (
 message_id uuid PRIMARY KEY REFERENCES c_dm.messages,
 sender uuid NOT NULL,
 group_id uuid NOT NULL,
 position integer NOT NULL CHECK(position BETWEEN 0 AND 8),
 media_id uuid NOT NULL,
 selection jsonb NOT NULL,
 bytes bytea CHECK(octet_length(bytes) BETWEEN 1 AND 10485760),
 FOREIGN KEY(sender,group_id) REFERENCES c_dm.image_groups,
 UNIQUE(sender,group_id,position),
 UNIQUE(sender,media_id)
);
CREATE TABLE c_dm.operations (
 owner_account uuid NOT NULL REFERENCES c_auth.accounts,
 operation_id uuid NOT NULL,
 fingerprint bytea NOT NULL CHECK(octet_length(fingerprint)=32),
 result jsonb NOT NULL,
 PRIMARY KEY(owner_account,operation_id)
);
CREATE TABLE c_dm.controls (
 sequence bigserial PRIMARY KEY,
 event_id uuid NOT NULL UNIQUE,
 identity_id uuid NOT NULL REFERENCES public.community_identities,
 conversation_id uuid NOT NULL REFERENCES c_dm.conversations,
 message_id uuid NOT NULL REFERENCES c_dm.messages,
 message_sequence bigint NOT NULL,
 created_at timestamptz NOT NULL,
 UNIQUE(identity_id,message_id)
);
CREATE INDEX dm_controls_identity ON c_dm.controls(identity_id,sequence);
-- Every directory-visible change increments one revision under the conversation
-- lock. Callers lock conversations BEFORE touching messages/settings to avoid
-- ACK/retract lock inversion. SELECT uses one MVCC snapshot for all fields.
-- +goose StatementBegin
CREATE FUNCTION c_dm.bump_revision() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 UPDATE c_dm.conversations SET revision=revision+1 WHERE conversation_id=NEW.conversation_id;
 RETURN NEW;
END $$;
-- +goose StatementEnd
CREATE TRIGGER dm_message_revision AFTER INSERT OR UPDATE ON c_dm.messages FOR EACH ROW EXECUTE FUNCTION c_dm.bump_revision();
CREATE TRIGGER dm_settings_revision AFTER INSERT OR UPDATE ON c_dm.settings FOR EACH ROW EXECUTE FUNCTION c_dm.bump_revision();
-- +goose StatementBegin
CREATE FUNCTION c_dm.guard_chat_monotonic() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_TABLE_NAME='settings' THEN
  IF NEW.deleted_through<OLD.deleted_through OR NEW.version<>OLD.version+1 THEN
   RAISE EXCEPTION 'DM settings boundary/version must advance' USING ERRCODE='23514';
  END IF;
 ELSIF TG_TABLE_NAME='media' THEN
  IF NEW.bytes IS NOT NULL THEN RAISE EXCEPTION 'DM media may only be erased' USING ERRCODE='23514'; END IF;
 ELSIF TG_TABLE_NAME='messages' THEN
  IF (OLD.acknowledged AND NOT NEW.acknowledged) OR (OLD.read AND NOT NEW.read)
      OR (OLD.retracted AND NOT NEW.retracted) THEN
   RAISE EXCEPTION 'DM delivery and retraction cannot regress' USING ERRCODE='23514';
  END IF;
 END IF;
 RETURN NEW;
END $$;
-- +goose StatementEnd
CREATE TRIGGER dm_settings_monotonic BEFORE UPDATE ON c_dm.settings FOR EACH ROW EXECUTE FUNCTION c_dm.guard_chat_monotonic();
CREATE TRIGGER dm_media_erase_only BEFORE UPDATE ON c_dm.media FOR EACH ROW EXECUTE FUNCTION c_dm.guard_chat_monotonic();
CREATE TRIGGER dm_message_monotonic BEFORE UPDATE ON c_dm.messages FOR EACH ROW EXECUTE FUNCTION c_dm.guard_chat_monotonic();
REVOKE ALL ON ALL TABLES IN SCHEMA c_dm FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA c_dm FROM PUBLIC;
-- +goose Down
-- +goose StatementBegin
DO $$ BEGIN RAISE EXCEPTION '0023 contains private pending media and deletion/retraction tombstones; repair forward'; END $$;
-- +goose StatementEnd
