package authprivacyruntime

import (
	"strings"
	"testing"

	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacyhttp"
)

func TestPostImagesRequiresExplicitCommunityConfiguration(t *testing.T) {
	for _, c := range []Config{
		{Environment: "dev", PostImages: &PostImagesConfig{}},
		{Environment: "dev", PostImages: &PostImagesConfig{PythonFile: "python", ValidatorFile: "validate.py", ValidatorSHA256: strings.Repeat("a", 64)}},
		{Environment: "dev", Posts: &PostsConfig{}, PostImages: &PostImagesConfig{PythonFile: "python", ValidatorFile: "validate.py", ValidatorSHA256: "short"}},
	} {
		if e := c.Validate(authprivacyhttp.CommunityService); e == nil || !strings.Contains(e.Error(), "postImages") {
			t.Fatal("incomplete postImages policy not rejected before material loading")
		}
	}
	c := Config{Environment: "dev", Posts: &PostsConfig{}, PostImages: &PostImagesConfig{PythonFile: "python", ValidatorFile: "validate.py", ValidatorSHA256: strings.Repeat("a", 64)}}
	if e := c.Validate(authprivacyhttp.VerifierService); e == nil || !strings.Contains(e.Error(), "postImages") {
		t.Fatal("V acquired image policy")
	}
}
