package authprivacyruntime

import (
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacyhttp"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/commentsnapshot"
	"testing"
)

func TestCommentTextExplicitRuntimeConfiguration(t *testing.T) {
	c := Config{}
	if paths, e := c.commentKeyFiles(authprivacyhttp.CommunityService); e != nil || len(paths) != 0 {
		t.Fatal("implicit enable")
	}
	c.Comments = &CommentsConfig{CommandKeyFile: "comment-key", FingerprintKeyFile: "comment-fingerprint"}
	if _, e := c.commentKeyFiles(authprivacyhttp.CommunityService); e == nil {
		t.Fatal("posts dependency missing")
	}
	c.Posts = &PostsConfig{}
	if _, e := c.commentKeyFiles(authprivacyhttp.CommunityService); e == nil {
		t.Fatal("omitted snapshots silently selected legacy PG")
	}
	rollback := commentsnapshot.DefaultConfig()
	rollback.CreateBackend, rollback.ReadRedis = "postgres", false
	c.Comments.Snapshots = &rollback
	if paths, e := c.commentKeyFiles(authprivacyhttp.CommunityService); e != nil || len(paths) != 2 {
		t.Fatal(e)
	}
	if _, e := c.commentKeyFiles(authprivacyhttp.VerifierService); e == nil {
		t.Fatal("V received comment keys")
	}
	c.Comments.FingerprintKeyFile = ""
	if _, e := c.commentKeyFiles(authprivacyhttp.CommunityService); e == nil {
		t.Fatal("partial keys accepted")
	}
}
