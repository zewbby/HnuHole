package authprivacyruntime

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"os"
	"path/filepath"
	"testing"

	"github.com/google/uuid"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacyhttp"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/commentsnapshot"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/ratelimit"
)

func TestCommentSnapshotDefaultsAndStandardTemplateRequireRedis(t *testing.T) {
	raw, err := os.ReadFile(filepath.Join("..", "..", "..", "..", "infra", "commentsnapshot", "snapshots.example.json"))
	if err != nil {
		t.Fatal(err)
	}
	var example commentsnapshot.Config
	if err = json.Unmarshal(raw, &example); err != nil {
		t.Fatal(err)
	}
	raw, err = os.ReadFile(filepath.Join("..", "..", "community.config.example.json"))
	if err != nil {
		t.Fatal(err)
	}
	var standard Config
	if err = json.Unmarshal(raw, &standard); err != nil {
		t.Fatal(err)
	}
	if standard.Posts == nil || standard.Comments == nil || standard.Comments.Snapshots == nil {
		t.Fatal("standard API template does not enable comments")
	}
	if *standard.Comments.Snapshots != example {
		t.Fatal("standard and snapshot templates differ")
	}
	defaults := commentsnapshot.DefaultConfig()
	for name, settings := range map[string]*commentsnapshot.Config{"example": &example, "default": &defaults, "standard": standard.Comments.Snapshots, "omitted": nil} {
		t.Run(name, func(t *testing.T) {
			if settings != nil && (settings.CreateBackend != "redis" || !settings.ReadPostgres || !settings.ReadRedis) {
				t.Fatal("Redis default or legacy cursor reads disabled")
			}
			if settings != nil {
				settings.Redis.PasswordFile = filepath.Join(t.TempDir(), "absent-password")
			}
			c := Config{Environment: "dev", Posts: &PostsConfig{CommandKeyFile: "post-key", FingerprintKeyFile: "post-fingerprint", CursorKeyFile: "post-cursor"}, Comments: &CommentsConfig{CommandKeyFile: "comment-key", FingerprintKeyFile: "comment-fingerprint", Snapshots: settings}}
			_, e := c.commentKeyFiles(authprivacyhttp.CommunityService)
			if !errors.Is(e, errCommentSnapshotConfiguration) {
				t.Fatal("missing Redis configuration accepted", e)
			}
			// Run is also called directly by tools; validate before database/listeners.
			c.Environment = "dev"
			if e = Run(context.Background(), c, authprivacyhttp.CommunityService); !errors.Is(e, errCommentSnapshotConfiguration) {
				t.Fatal("runtime bypassed required snapshot configuration", e)
			}
			var output bytes.Buffer
			LogFailure(slog.New(slog.NewJSONHandler(&output, nil)), authprivacyhttp.CommunityService, ConfigurationFailure, e)
			if !bytes.Contains(output.Bytes(), []byte(`"reason":"comment_snapshot_configuration"`)) {
				t.Fatal("missing safe actionable startup diagnostic")
			}
		})
	}
}

func TestCommentSnapshotExplicitPostgresRollbackWithoutRedis(t *testing.T) {
	settings := commentsnapshot.DefaultConfig()
	settings.CreateBackend, settings.ReadRedis = "postgres", false
	settings.Redis.PasswordFile = filepath.Join(t.TempDir(), "absent-password")
	settings.Redis.Address = "invalid-unused-Redis-endpoint"
	c := Config{Posts: &PostsConfig{}, Comments: &CommentsConfig{CommandKeyFile: "comment-key", FingerprintKeyFile: "comment-fingerprint", Snapshots: &settings}}
	if keys, e := c.commentKeyFiles(authprivacyhttp.CommunityService); e != nil || len(keys) != 2 {
		t.Fatal("explicit PG rollback requires Redis credentials", e)
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
