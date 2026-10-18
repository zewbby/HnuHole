package authprivacyhttp

import (
	"net/http/httptest"
	"strings"
	"testing"
)

func TestCommentTextNullableBoundary(t *testing.T) {
	body := `{"operation":"CREATE","taskId":"a1111111-1111-4111-8111-111111111111","postId":"a2222222-2222-4222-8222-222222222222","identityId":"a3333333-3333-4333-8333-333333333333","rootCommentId":null,"targetCommentId":null,"body":"文字","image":null}`
	parse := func(s string) error {
		r := httptest.NewRequest("PUT", "/api/v1/comment-commands/unused", strings.NewReader(s))
		r.Header.Set("Content-Type", "application/json")
		_, e := commentIntent(r)
		return e
	}
	if e := parse(body); e != nil {
		t.Fatal(e)
	}
	for _, s := range []string{strings.Replace(body, `"body":"文字"`, `"body":null`, 1), strings.Replace(body, `"image":null`, `"image":{}`, 1), strings.Replace(body, `"operation":"CREATE"`, `"operation":"CREATE","operation":"CREATE"`, 1), strings.Replace(body, `"targetCommentId":null`, `"targetCommentId":"a4444444-4444-4444-8444-444444444444"`, 1), strings.Replace(body, `"body":"文字"`, `"body":"\ud800"`, 1)} {
		if parse(s) == nil {
			t.Fatal("ambiguous comment input accepted")
		}
	}
	// The authentication parser keeps its original no-null rule.
	if _, e := parseObject(strings.NewReader(`{"password":null}`), 1024); e == nil {
		t.Fatal("auth null policy changed")
	}
}
