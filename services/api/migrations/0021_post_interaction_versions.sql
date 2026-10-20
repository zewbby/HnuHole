-- +goose Up
-- Private per-account/post write fence. No historical interaction backfill.
CREATE TABLE c_posts.post_interaction_versions (
    account_id uuid NOT NULL REFERENCES c_auth.accounts(account_id),
    post_id uuid NOT NULL REFERENCES c_posts.posts(post_id),
    version uuid NOT NULL CHECK (version <> '00000000-0000-0000-0000-000000000000'),
    PRIMARY KEY (account_id, post_id)
);
-- +goose StatementBegin
CREATE OR REPLACE FUNCTION c_posts.clear_closed_account_interactions() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog AS $$
BEGIN
    IF NEW.state = 'CLOSED' AND OLD.state IS DISTINCT FROM NEW.state THEN
        DELETE FROM c_posts.post_likes WHERE account_id = NEW.account_id;
        DELETE FROM c_posts.post_favorites WHERE account_id = NEW.account_id;
        DELETE FROM c_posts.post_interaction_versions WHERE account_id = NEW.account_id;
    END IF;
    RETURN NEW;
END $$;
-- +goose StatementEnd
REVOKE ALL ON c_posts.post_interaction_versions FROM PUBLIC;
REVOKE ALL ON FUNCTION c_posts.clear_closed_account_interactions() FROM PUBLIC;
-- +goose Down
-- +goose StatementBegin
DO $$ BEGIN
    RAISE EXCEPTION '0021 stores interaction write fences; freeze and repair forward';
END $$;
-- +goose StatementEnd
