-- +goose Up
ALTER TABLE c_dm.messages ADD COLUMN evidence_digest bytea CHECK(evidence_digest IS NULL OR octet_length(evidence_digest)=32);
CREATE TABLE c_dm.blocks (
 block_id uuid NOT NULL UNIQUE,
 owner_account uuid NOT NULL REFERENCES c_auth.accounts,
 peer_account uuid NOT NULL,
 identity_id uuid NOT NULL REFERENCES public.community_identities,
 peer_id uuid NOT NULL REFERENCES public.community_identities,
 conversation_id uuid NOT NULL REFERENCES c_dm.conversations,
 peer_name text NOT NULL, peer_avatar text NOT NULL,
 created_at timestamptz NOT NULL,
 PRIMARY KEY(owner_account,identity_id,peer_id), CHECK(owner_account<>peer_account)
);
CREATE INDEX dm_blocks_account_pair ON c_dm.blocks(owner_account,peer_account);
ALTER TABLE c_moderation.cases ALTER COLUMN post_id DROP NOT NULL;
ALTER TABLE c_moderation.cases ADD COLUMN conversation_id uuid REFERENCES c_dm.conversations;
ALTER TABLE c_moderation.cases ADD CONSTRAINT moderation_exact_target CHECK((post_id IS NOT NULL AND conversation_id IS NULL) OR (post_id IS NULL AND conversation_id IS NOT NULL AND comment_id IS NULL));
CREATE UNIQUE INDEX moderation_dm_snapshot ON c_moderation.cases(conversation_id,snapshot_digest) WHERE conversation_id IS NOT NULL;
-- +goose StatementBegin
CREATE FUNCTION c_dm.guard_evidence_digest() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF NEW.evidence_digest IS DISTINCT FROM OLD.evidence_digest THEN RAISE EXCEPTION 'DM evidence commitment is immutable' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
-- +goose StatementEnd
CREATE TRIGGER dm_evidence_immutable BEFORE UPDATE ON c_dm.messages FOR EACH ROW EXECUTE FUNCTION c_dm.guard_evidence_digest();
REVOKE ALL ON c_dm.blocks FROM PUBLIC;
-- +goose Down
-- +goose StatementBegin
DO $$ BEGIN RAISE EXCEPTION '0024 contains blocks and authorized governance evidence; repair forward'; END $$;
-- +goose StatementEnd
