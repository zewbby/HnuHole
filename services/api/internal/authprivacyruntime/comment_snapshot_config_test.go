package authprivacyruntime

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/google/uuid"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacyhttp"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/commentsnapshot"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/ratelimit"
)

func TestCommentSnapshotDefaultTemplateKeepsPostgresWithoutRedis(t *testing.T) {
	raw, err := os.ReadFile(filepath.Join("..", "..", "..", "..", "infra", "commentsnapshot", "snapshots.example.json"))
	if err != nil {
		t.Fatal(err)
	}
	var example commentsnapshot.Config
	if err = json.Unmarshal(raw, &example); err != nil {
		t.Fatal(err)
	}
	defaults := commentsnapshot.DefaultConfig()
	for name, settings := range map[string]*commentsnapshot.Config{"example": &example, "default": &defaults, "omitted": nil} {
		t.Run(name, func(t *testing.T) {
			if settings != nil {
				if settings.CreateBackend != "postgres" || !settings.ReadPostgres || settings.ReadRedis {
					t.Fatal("default configuration enables Redis")
				}
				// Missing credentials and an unusable endpoint must not be read
				// or connected to when Redis reading is disabled.
				settings.Redis.PasswordFile = filepath.Join(t.TempDir(), "absent-password")
				settings.Redis.Address = "invalid-unused-Redis-endpoint"
			}
			c := Config{Posts: &PostsConfig{}, Comments: &CommentsConfig{CommandKeyFile: "comment-key", FingerprintKeyFile: "comment-fingerprint", Snapshots: settings}}
			keys, e := c.commentKeyFiles(authprivacyhttp.CommunityService)
			if e != nil || len(keys) != 2 {
				t.Fatal("PG mode requires Redis credentials", keys, e)
			}
		})
	}
}

func TestCommentSnapshotRuntimeIsolation(t *testing.T) {
	dir := t.TempDir()
	password := filepath.Join(dir, "snapshot-password")
	if e := os.WriteFile(password, []byte("fixture-only-password"), 0600); e != nil {
		t.Fatal(e)
	}
	cfg := commentsnapshot.DefaultConfig()
	cfg.ReadRedis = true
	cfg.CreateBackend = "redis"
	cfg.Redis.Address = "127.0.0.1:16381"
	cfg.Redis.Username = "community_comment_snapshot_v2"
	cfg.Redis.PasswordFile = password
	cfg.Redis.Namespace = "hnuhole:comment-snapshot:v2:lab:"
	cfg.Redis.Epoch = uuid.NewString()
	c := Config{Environment: "lab", Posts: &PostsConfig{}, Comments: &CommentsConfig{CommandKeyFile: "comment-key", FingerprintKeyFile: "comment-fingerprint", Snapshots: &cfg}}
	if _, e := c.commentKeyFiles(authprivacyhttp.CommunityService); e != nil {
		t.Fatal(e)
	}
	cfg.Redis.Namespace = "hnuhole:comment-snapshot:v2:other:"
	if _, e := c.commentKeyFiles(authprivacyhttp.CommunityService); e == nil {
		t.Fatal("cross-environment snapshot namespace accepted")
	}
	cfg.Redis.Namespace = "hnuhole:comment-snapshot:v2:lab:"
	c.SharedRateLimit = &SharedRateConfig{Policy: ratelimit.Config{Address: cfg.Redis.Address}}
	if _, e := c.commentKeyFiles(authprivacyhttp.CommunityService); e == nil {
		t.Fatal("shared admission memory instance accepted")
	}
	c.SharedRateLimit = nil
	cfg.MaxPerAccount = 500
	if _, e := c.commentKeyFiles(authprivacyhttp.CommunityService); e == nil {
		t.Fatal("required reading capacity not enforced")
	}
}
