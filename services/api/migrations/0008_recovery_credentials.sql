-- +goose Up
-- +goose StatementBegin
-- Isolated credential management and discoverable ES256 WebAuthn recovery.
ALTER TABLE c_auth.accounts
 ADD COLUMN rotation_generation bigint NOT NULL DEFAULT 0 CHECK(rotation_generation>=0),
 ADD COLUMN active_rotation_intent_id bytea CHECK(active_rotation_intent_id IS NULL OR octet_length(active_rotation_intent_id)=32),
 ADD COLUMN user_handle bytea UNIQUE CHECK(user_handle IS NULL OR octet_length(user_handle)=32);

ALTER TABLE c_auth.passkeys
 ADD COLUMN user_handle bytea NOT NULL CHECK(octet_length(user_handle)=32),
 ADD COLUMN cose_algorithm smallint NOT NULL CHECK(cose_algorithm=-7),
 ADD COLUMN sign_count bigint NOT NULL CHECK(sign_count BETWEEN 0 AND 4294967295),
 ADD COLUMN backup_eligible boolean NOT NULL,
 ADD COLUMN backed_up boolean NOT NULL,
 ADD COLUMN created_credential_version bigint NOT NULL CHECK(created_credential_version>=1),
 ADD CONSTRAINT passkey_backup_shape CHECK(NOT backed_up OR backup_eligible);
COMMENT ON TABLE c_auth.passkeys IS 'Minimal canonical ES256 COSE public key and random account handle. No attestation, AAGUID, transports or device metadata.';

CREATE TABLE c_auth.credential_change_intents (
 intent_id bytea PRIMARY KEY CHECK(octet_length(intent_id)=32),
 account_id uuid NOT NULL REFERENCES c_auth.accounts(account_id),
 kind text NOT NULL CHECK(kind IN ('ROTATE_CODE','CREATE_PASSKEY','REMOVE_PASSKEY')),
 session_digest bytea NOT NULL CHECK(octet_length(session_digest)=32),
 session_generation bigint NOT NULL CHECK(session_generation>=1),
 credential_version bigint NOT NULL CHECK(credential_version>=1),
 authorization_generation bigint NOT NULL CHECK(authorization_generation>=1),
 rotation_generation bigint,
 target_credential_id bytea,
 challenge_id bytea,
 new_recovery_digest bytea,
 state text NOT NULL CHECK(state IN ('ACTIVE','ABANDONED','CONSUMED','EXPIRED')),
 created_at timestamptz NOT NULL,
 expires_at timestamptz NOT NULL,
 terminal_at timestamptz,
 UNIQUE(account_id,intent_id),
 CHECK((kind='ROTATE_CODE' AND rotation_generation IS NOT NULL AND rotation_generation>=1 AND expires_at=created_at+interval '10 minutes')
    OR (kind IN ('CREATE_PASSKEY','REMOVE_PASSKEY') AND rotation_generation IS NULL AND expires_at=created_at+interval '5 minutes')),
 CHECK((state='ACTIVE' AND terminal_at IS NULL AND
   ((kind='ROTATE_CODE' AND new_recovery_digest IS NOT NULL AND octet_length(new_recovery_digest)=32 AND target_credential_id IS NULL AND challenge_id IS NULL)
    OR (kind='REMOVE_PASSKEY' AND new_recovery_digest IS NULL AND challenge_id IS NULL AND target_credential_id IS NOT NULL AND octet_length(target_credential_id) BETWEEN 1 AND 1023)
    OR (kind='CREATE_PASSKEY' AND new_recovery_digest IS NULL AND target_credential_id IS NULL AND challenge_id IS NOT NULL AND challenge_id=intent_id)))
  OR (state<>'ACTIVE' AND new_recovery_digest IS NULL AND target_credential_id IS NULL AND challenge_id IS NULL AND terminal_at IS NOT NULL AND terminal_at>=created_at))
);
CREATE UNIQUE INDEX credential_rotation_one_active ON c_auth.credential_change_intents(account_id)
 WHERE kind='ROTATE_CODE' AND state='ACTIVE';
ALTER TABLE c_auth.accounts ADD CONSTRAINT accounts_active_rotation_ownership
 FOREIGN KEY(account_id,active_rotation_intent_id) REFERENCES c_auth.credential_change_intents(account_id,intent_id)
 DEFERRABLE INITIALLY DEFERRED;

CREATE TABLE c_auth.auth_challenges (
 challenge_id bytea PRIMARY KEY CHECK(octet_length(challenge_id)=32),
 kind text NOT NULL CHECK(kind IN ('CREATE_PASSKEY','RESET_PASSKEY')),
 account_id uuid REFERENCES c_auth.accounts(account_id),
 session_digest bytea,
 session_generation bigint,
 credential_version bigint,
 authorization_generation bigint NOT NULL CHECK(authorization_generation>=1),
 policy_digest bytea NOT NULL CHECK(octet_length(policy_digest)=32),
 nonce bytea,
 state text NOT NULL CHECK(state IN ('ACTIVE','ABANDONED','CONSUMED','EXPIRED')),
 created_at timestamptz NOT NULL,
 expires_at timestamptz NOT NULL CHECK(expires_at=created_at+interval '5 minutes'),
 terminal_at timestamptz,
 UNIQUE(account_id,challenge_id),
 CHECK((kind='RESET_PASSKEY' AND account_id IS NULL AND session_digest IS NULL AND session_generation IS NULL AND credential_version IS NULL)
    OR (kind='CREATE_PASSKEY' AND account_id IS NOT NULL AND session_digest IS NOT NULL AND octet_length(session_digest)=32 AND session_generation IS NOT NULL AND session_generation>=1 AND credential_version IS NOT NULL AND credential_version>=1)),
 CHECK((state='ACTIVE' AND nonce IS NOT NULL AND octet_length(nonce)=32 AND terminal_at IS NULL)
    OR (state<>'ACTIVE' AND nonce IS NULL AND terminal_at IS NOT NULL AND terminal_at>=created_at))
);

ALTER TABLE c_auth.credential_change_intents ADD CONSTRAINT credential_challenge_binding
 FOREIGN KEY(account_id,challenge_id) REFERENCES c_auth.auth_challenges(account_id,challenge_id) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE c_auth.request_results
 ADD COLUMN credential_change_id bytea REFERENCES c_auth.credential_change_intents(intent_id) DEFERRABLE INITIALLY DEFERRED,
 ADD COLUMN auth_challenge_id bytea REFERENCES c_auth.auth_challenges(challenge_id) DEFERRABLE INITIALLY DEFERRED,
 ADD CONSTRAINT request_results_credential_shape CHECK(
  (state='EXPIRED' AND credential_change_id IS NULL AND auth_challenge_id IS NULL)
  OR (state='LIVE' AND
    ((operation IN ('ROTATE_CODE','REMOVE_PASSKEY') AND credential_change_id IS NOT NULL AND auth_challenge_id IS NULL AND intent_id IS NULL AND reset_intent_id IS NULL)
     OR (operation='CREATE_PASSKEY' AND auth_challenge_id IS NOT NULL AND credential_change_id IS NULL AND intent_id IS NULL AND reset_intent_id IS NULL)
     OR (operation NOT IN ('ROTATE_CODE','REMOVE_PASSKEY','CREATE_PASSKEY') AND credential_change_id IS NULL AND auth_challenge_id IS NULL))));
ALTER TABLE c_auth.security_events DROP CONSTRAINT security_events_action_check;
ALTER TABLE c_auth.security_events ADD CONSTRAINT security_events_action_check
 CHECK(action IN ('PASSWORD_RESET','ROTATE_CODE','CREATE_PASSKEY','REMOVE_PASSKEY','PASSKEY_COUNTER_RISK'));

CREATE OR REPLACE FUNCTION c_auth.guard_request_result() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'request result anchors cannot be deleted' USING ERRCODE='23514'; END IF;
 IF NEW.operation IS DISTINCT FROM OLD.operation OR NEW.key_digest IS DISTINCT FROM OLD.key_digest
 OR (OLD.state='EXPIRED' AND NEW IS DISTINCT FROM OLD)
 OR (NEW.state='LIVE' AND ROW(NEW.request_hmac,NEW.hmac_key_version,NEW.intent_id,NEW.reset_intent_id,NEW.credential_change_id,NEW.auth_challenge_id,NEW.expires_at)
 IS DISTINCT FROM ROW(OLD.request_hmac,OLD.hmac_key_version,OLD.intent_id,OLD.reset_intent_id,OLD.credential_change_id,OLD.auth_challenge_id,OLD.expires_at))
 THEN RAISE EXCEPTION 'immutable request result binding' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
CREATE FUNCTION c_auth.guard_credential_change() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF ROW(NEW.intent_id,NEW.account_id,NEW.kind,NEW.session_digest,NEW.session_generation,NEW.credential_version,NEW.authorization_generation,NEW.rotation_generation,NEW.created_at,NEW.expires_at)
 IS DISTINCT FROM ROW(OLD.intent_id,OLD.account_id,OLD.kind,OLD.session_digest,OLD.session_generation,OLD.credential_version,OLD.authorization_generation,OLD.rotation_generation,OLD.created_at,OLD.expires_at)
 OR (OLD.state<>'ACTIVE' AND NEW IS DISTINCT FROM OLD)
 OR (NEW.state='ACTIVE' AND ROW(NEW.target_credential_id,NEW.new_recovery_digest,NEW.challenge_id) IS DISTINCT FROM ROW(OLD.target_credential_id,OLD.new_recovery_digest,OLD.challenge_id))
 THEN RAISE EXCEPTION 'immutable credential change proof' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER credential_change_immutable BEFORE UPDATE ON c_auth.credential_change_intents FOR EACH ROW EXECUTE FUNCTION c_auth.guard_credential_change();
CREATE FUNCTION c_auth.guard_auth_challenge() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF ROW(NEW.challenge_id,NEW.kind,NEW.account_id,NEW.session_digest,NEW.session_generation,NEW.credential_version,NEW.authorization_generation,NEW.policy_digest,NEW.created_at,NEW.expires_at)
 IS DISTINCT FROM ROW(OLD.challenge_id,OLD.kind,OLD.account_id,OLD.session_digest,OLD.session_generation,OLD.credential_version,OLD.authorization_generation,OLD.policy_digest,OLD.created_at,OLD.expires_at)
 OR (OLD.state<>'ACTIVE' AND NEW IS DISTINCT FROM OLD)
 OR (NEW.state='ACTIVE' AND NEW.nonce IS DISTINCT FROM OLD.nonce)
 THEN RAISE EXCEPTION 'immutable challenge proof' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER auth_challenge_immutable BEFORE UPDATE ON c_auth.auth_challenges FOR EACH ROW EXECUTE FUNCTION c_auth.guard_auth_challenge();
CREATE FUNCTION c_auth.guard_rotation_generation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF NEW.rotation_generation<OLD.rotation_generation OR (OLD.user_handle IS NOT NULL AND NEW.user_handle IS DISTINCT FROM OLD.user_handle AND NOT(NEW.user_handle IS NULL AND NEW.state='CLOSED'))
 THEN RAISE EXCEPTION 'monotonic rotation and immutable user handle' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER rotation_generation_monotonic BEFORE UPDATE ON c_auth.accounts FOR EACH ROW EXECUTE FUNCTION c_auth.guard_rotation_generation();

CREATE FUNCTION c_auth.guard_passkey_material() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF ROW(NEW.credential_id,NEW.account_id,NEW.public_key,NEW.user_handle,NEW.cose_algorithm,NEW.backup_eligible,NEW.created_at,NEW.created_credential_version)
 IS DISTINCT FROM ROW(OLD.credential_id,OLD.account_id,OLD.public_key,OLD.user_handle,OLD.cose_algorithm,OLD.backup_eligible,OLD.created_at,OLD.created_credential_version)
 OR NEW.sign_count<OLD.sign_count THEN RAISE EXCEPTION 'immutable Passkey and monotonic counter' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER passkey_material_immutable BEFORE UPDATE ON c_auth.passkeys FOR EACH ROW EXECUTE FUNCTION c_auth.guard_passkey_material();

CREATE INDEX credential_intents_account_active ON c_auth.credential_change_intents(account_id,intent_id) WHERE state='ACTIVE';
CREATE INDEX credential_intents_cleanup ON c_auth.credential_change_intents(expires_at,terminal_at);
CREATE INDEX auth_challenges_account_active ON c_auth.auth_challenges(account_id,challenge_id) WHERE state='ACTIVE';
CREATE INDEX auth_challenges_cleanup ON c_auth.auth_challenges(expires_at,terminal_at);

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
DO $$ BEGIN RAISE EXCEPTION 'Authentication facts require freeze and forward repair; Down is forbidden'; END $$;
-- +goose StatementEnd
