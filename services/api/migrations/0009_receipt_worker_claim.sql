-- +goose Up
ALTER TABLE c_auth.receipt_outbox
    ADD COLUMN claim_token bytea CHECK (claim_token IS NULL OR octet_length(claim_token)=32),
    ADD COLUMN claim_until timestamptz,
    ADD COLUMN claim_generation bigint CHECK (claim_generation IS NULL OR claim_generation>0),
    ADD CONSTRAINT receipt_claim_complete CHECK ((claim_token IS NULL AND claim_until IS NULL AND claim_generation IS NULL)
        OR (claim_token IS NOT NULL AND claim_until IS NOT NULL AND claim_generation IS NOT NULL));
CREATE INDEX receipt_claim_due ON c_auth.receipt_outbox(claim_until,slot_id) WHERE state IN ('PENDING_SIGN','READY');
-- +goose Down
-- +goose StatementBegin
DO $$ BEGIN RAISE EXCEPTION 'Authentication facts require forward repair'; END $$;
-- +goose StatementEnd
