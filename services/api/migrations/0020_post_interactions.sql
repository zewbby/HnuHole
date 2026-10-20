-- +goose Up
-- Account-private facts, independent of speaking identities. No voter API.
CREATE TABLE c_posts.post_likes (
    account_id uuid NOT NULL REFERENCES c_auth.accounts(account_id),
    post_id uuid NOT NULL REFERENCES c_posts.posts(post_id),
    PRIMARY KEY (account_id, post_id)
);
CREATE INDEX post_likes_count_idx ON c_posts.post_likes(post_id);
CREATE TABLE c_posts.post_favorites (
    account_id uuid NOT NULL REFERENCES c_auth.accounts(account_id),
    post_id uuid NOT NULL REFERENCES c_posts.posts(post_id),
    saved_at timestamptz NOT NULL,
    PRIMARY KEY (account_id, post_id)
);
CREATE INDEX post_favorites_count_idx ON c_posts.post_favorites(post_id);

-- +goose StatementBegin
CREATE FUNCTION c_posts.clear_closed_account_interactions() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog AS $$
BEGIN
    IF NEW.state = 'CLOSED' AND OLD.state IS DISTINCT FROM NEW.state THEN
        DELETE FROM c_posts.post_likes WHERE account_id = NEW.account_id;
        DELETE FROM c_posts.post_favorites WHERE account_id = NEW.account_id;
    END IF;
    RETURN NEW;
END $$;
-- +goose StatementEnd
CREATE TRIGGER interactions_account_closed AFTER UPDATE OF state ON c_auth.accounts
    FOR EACH ROW EXECUTE FUNCTION c_posts.clear_closed_account_interactions();
REVOKE ALL ON c_posts.post_likes,c_posts.post_favorites FROM PUBLIC;
REVOKE ALL ON FUNCTION c_posts.clear_closed_account_interactions() FROM PUBLIC;

-- +goose Down
-- +goose StatementBegin
DO $$ BEGIN
    RAISE EXCEPTION '0020 contains account interaction facts; freeze and repair forward';
END $$;
-- +goose StatementEnd
