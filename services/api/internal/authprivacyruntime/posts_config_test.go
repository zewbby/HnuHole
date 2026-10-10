package authprivacyruntime

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"

	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacyhttp"
)

func TestRuntimePostsRequiresExplicitCompleteCommunityPolicy(t *testing.T) {
	c := Config{PublicOrigin: "https://127.0.0.1:8443"}
	if paths, err := c.postKeyFiles(authprivacyhttp.CommunityService); err != nil || len(paths) != 0 {
		t.Fatal("旧配置应保持文字功能关闭")
	}
	c.Posts = &PostsConfig{CommandKeyFile: "command", FingerprintKeyFile: "fingerprint", CursorKeyFile: "cursor"}
	if paths, err := c.postKeyFiles(authprivacyhttp.CommunityService); err != nil || len(paths) != 3 {
		t.Fatal("完整 C 配置被拒绝")
	}
	if _, err := c.postKeyFiles(authprivacyhttp.VerifierService); err == nil {
		t.Fatal("V 不得持有 C 文字用途密钥")
	}
	for _, missing := range []string{"command", "fingerprint", "cursor"} {
		t.Run(missing, func(t *testing.T) {
			policy := *c.Posts
			if missing == "command" {
				policy.CommandKeyFile = ""
			}
			if missing == "fingerprint" {
				policy.FingerprintKeyFile = ""
			}
			if missing == "cursor" {
				policy.CursorKeyFile = ""
			}
			candidate := c
			candidate.Posts = &policy
			if _, err := candidate.postKeyFiles(authprivacyhttp.CommunityService); err == nil {
				t.Fatal("缺少一份用途密钥仍启用了文字功能")
			}
		})
	}
}

func TestRuntimePostKeysCannotReuseAuthenticationOrOtherPostPurpose(t *testing.T) {
	dir := t.TempDir()
	c := Config{base: dir, RequestKeyFile: "request", NetworkKeyFile: "network",
		Posts: &PostsConfig{CommandKeyFile: "command", FingerprintKeyFile: "fingerprint", CursorKeyFile: "cursor"}}
	paths := []string{"request", "network", "command", "fingerprint", "cursor"}
	for i, name := range paths {
		if err := os.WriteFile(filepath.Join(dir, name), bytes.Repeat([]byte{byte(i + 1)}, 32), 0600); err != nil {
			t.Fatal(err)
		}
	}
	if err := c.validatePurposeKeys(paths, map[string]bool{}); err != nil {
		t.Fatal(err)
	}
	for _, source := range []string{"request", "network", "command", "fingerprint"} {
		t.Run(source, func(t *testing.T) {
			original, err := os.ReadFile(filepath.Join(dir, "cursor"))
			if err != nil {
				t.Fatal(err)
			}
			defer os.WriteFile(filepath.Join(dir, "cursor"), original, 0600)
			sourceBytes, err := os.ReadFile(filepath.Join(dir, source))
			if err != nil {
				t.Fatal(err)
			}
			if err = os.WriteFile(filepath.Join(dir, "cursor"), sourceBytes, 0600); err != nil {
				t.Fatal(err)
			}
			if err = c.validatePurposeKeys(paths, map[string]bool{}); err == nil {
				t.Fatal("相同密钥字节不得跨用途使用")
			}
		})
	}
	for _, invalid := range [][]byte{make([]byte, 32), bytes.Repeat([]byte{9}, 31), bytes.Repeat([]byte{9}, 33)} {
		if err := os.WriteFile(filepath.Join(dir, "cursor"), invalid, 0600); err != nil {
			t.Fatal(err)
		}
		if err := c.validatePurposeKeys(paths, map[string]bool{}); err == nil {
			t.Fatal("零密钥或错误长度未拒绝")
		}
	}
	if err := os.Remove(filepath.Join(dir, "cursor")); err != nil {
		t.Fatal(err)
	}
	if err := c.validatePurposeKeys(paths, map[string]bool{}); err == nil {
		t.Fatal("缺失文字密钥文件未拒绝")
	}
}

func TestRuntimeRejectsUnknownPostPolicyFieldBeforeMaterialLoading(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	if err := os.WriteFile(path, []byte(`{"posts":{"commandKeyFile":"a","fingerprintKeyFile":"b","cursorKeyFile":"c","extra":"d"}}`), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := LoadConfig(path, authprivacyhttp.CommunityService); err == nil || err.Error() != "invalid runtime configuration JSON" {
		t.Fatal("未知嵌套策略字段未由严格解析拒绝")
	}
}
