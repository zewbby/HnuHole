-- +goose Up
CREATE TABLE c_posts.post_view_totals (
    post_id uuid PRIMARY KEY REFERENCES c_posts.posts(post_id),
    view_count bigint NOT NULL CHECK (view_count >= 0)
);

-- Private deduplication facts. No identity, device, IP or visitor API is stored.
CREATE TABLE c_posts.post_daily_views (
    account_id uuid NOT NULL REFERENCES c_auth.accounts(account_id),
    post_id uuid NOT NULL REFERENCES c_posts.posts(post_id),
    view_day date NOT NULL,
    PRIMARY KEY (account_id, post_id, view_day)
);

CREATE TABLE c_posts.feed_preferences (
    account_id uuid PRIMARY KEY REFERENCES c_auth.accounts(account_id),
    blocked_channel_ids uuid[] NOT NULL DEFAULT '{}',
    revision bigint NOT NULL CHECK (revision > 0),
    CHECK (cardinality(blocked_channel_ids) <= 7),
    CHECK (array_position(blocked_channel_ids, NULL) IS NULL)
);

CREATE INDEX feed_published_time_idx ON c_posts.posts(published_at DESC, publication_ordinal DESC)
    WHERE visibility = 'PUBLISHED' AND NOT moderation_hidden;

-- +goose StatementBegin
CREATE FUNCTION c_posts.clear_closed_account_feed() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog AS $$
BEGIN
    IF NEW.state = 'CLOSED' AND OLD.state IS DISTINCT FROM NEW.state THEN
        DELETE FROM c_posts.post_daily_views WHERE account_id = NEW.account_id;
        DELETE FROM c_posts.feed_preferences WHERE account_id = NEW.account_id;
    END IF;
    RETURN NEW;
END $$;
-- +goose StatementEnd
CREATE TRIGGER feed_account_closed AFTER UPDATE OF state ON c_auth.accounts
    FOR EACH ROW EXECUTE FUNCTION c_posts.clear_closed_account_feed();

REVOKE ALL ON c_posts.post_view_totals,c_posts.post_daily_views,c_posts.feed_preferences FROM PUBLIC;
REVOKE ALL ON FUNCTION c_posts.clear_closed_account_feed() FROM PUBLIC;

-- +goose Down
-- +goose StatementBegin
DO $$ BEGIN
    RAISE EXCEPTION '0019 stores cumulative view facts; freeze and repair forward instead of rolling back';
END $$;
-- +goose StatementEnd
