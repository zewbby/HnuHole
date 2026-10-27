package authprivacyhttp

import (
	"net/http/httptest"
	"strings"
	"testing"
)

func TestInboxRoutesAndDisabledMentionsBoundary(t *testing.T) {
	for path, method := range map[string]string{"/api/v1/notifications": "GET", "/api/v1/notifications/unread-counts": "GET", "/api/v1/notifications/i_a1111111-1111-4111-8111-111111111111/read": "POST"} {
		if !isInboxPath(path) || !publicMethodAllowed(CommunityService, path, method) {
			t.Fatal(path)
		}
	}
	body := `{"operation":"CREATE","taskId":"a1111111-1111-4111-8111-111111111111","postId":"a2222222-2222-4222-8222-222222222222","identityId":"a3333333-3333-4333-8333-333333333333","rootCommentId":null,"targetCommentId":null,"body":"@同学","image":null,"mentions":["ABCDEFGHIJKL"]}`
	parse := func(s string) error {
		r := httptest.NewRequest("PUT", "/api/v1/comment-commands/unused", strings.NewReader(s))
		r.Header.Set("Content-Type", "application/json")
		_, e := commentIntent(r)
		return e
	}
	if parse(body) == nil {
		t.Fatal("disabled mention metadata was accepted")
	}
	if parse(strings.Replace(body, `,"mentions":["ABCDEFGHIJKL"]`, "", 1)) != nil {
		t.Fatal("ordinary comment rejected")
	}
	if isInboxPath("/api/v1/posts/a1111111-1111-4111-8111-111111111111/mention-targets") {
		t.Fatal("disabled mention route exposed")
	}
}
