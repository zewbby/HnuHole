package authprivacyhttp

import (
	"context"
	"github.com/google/uuid"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/moderation"
	"testing"
)

func TestDMGovernanceHTTPSPostgres(t *testing.T) {
	ctx := context.Background()
	s := e2eNewServices(t, func(c *authprivacy.Community) *authprivacy.Community {
		v, e := c.WithDirectMessages(ctx)
		if e != nil {
			t.Fatal(e)
		}
		v, e = v.WithModeration(ctx)
		if e != nil {
			t.Fatal(e)
		}
		return v
	})
	a, _ := e2ePrivacySignup(t, s, "dm_p3_https_a")
	b, _ := e2ePrivacySignup(t, s, "dm_p3_https_b")
	ia := postHTTPSIdentity(t, s, a, "治理甲", 71)
	ib := postHTTPSIdentity(t, s, b, "治理乙", 72)
	p := postHTTPSJSON(t, s, "PUT", "/api/v1/post-commands/"+httpTestEncoding(16, 73), b, "", map[string]any{"channelId": postHTTPSChannel(t, s, b), "identityId": ib, "title": "来源", "body": "内容"}, 202)
	if _, e := s.c.PublishAcceptedPosts(ctx, 100); e != nil {
		t.Fatal(e)
	}
	first := postHTTPSJSON(t, s, "PUT", "/api/v1/dm/commands/"+uuid.NewString(), a, "", authprivacy.DMTextIntent{IdentityID: ia, PeerID: ib, SourcePostID: p["postId"].(string), Text: "original", Attempt: 1}, 200)
	conv := first["conversationId"].(string)
	message := first["messageId"].(string)
	if first["evidenceVersion"] != float64(1) {
		t.Fatal("no authenticity version", first)
	}
	op := uuid.NewString()
	input := authprivacy.DMBlockInput{IdentityID: ia, ConversationID: conv, Blocked: true}
	postHTTPSJSON(t, s, "PUT", "/api/v1/dm/governance/blocks/"+op, a, "", input, 200)
	blocks := postHTTPSJSON(t, s, "GET", "/api/v1/dm/governance/blocks", a, "", nil, 200)["items"].([]any)
	if len(blocks) != 1 || blocks[0].(map[string]any)["conversationId"] != conv {
		t.Fatal(blocks)
	}
	if postHTTPSJSON(t, s, "GET", "/api/v1/dm/governance/blocks/"+op, b, "", nil, 200)["state"] != "ABSENT" {
		t.Fatal("other block receipt")
	}
	task := uuid.NewString()
	report := authprivacy.DMReportInput{IdentityID: ia, ConversationID: conv, FirstSequence: 1, LastSequence: 1, Reason: "OTHER", Images: []moderation.Image{}, Authorized: true, Entries: []authprivacy.DMEvidenceEntry{{MessageID: message, Sequence: 1, Kind: "TEXT", Text: "original"}}}
	absent := postHTTPSJSON(t, s, "GET", "/api/v1/dm/governance/reports/"+task, a, "", nil, 200)
	report.RetryToken = absent["retryToken"].(string)
	postHTTPSJSON(t, s, "PUT", "/api/v1/dm/governance/reports/"+task, a, "", report, 200)
	result := postHTTPSJSON(t, s, "GET", "/api/v1/reports/"+task, a, "", nil, 200)
	if result["state"] != "SUBMITTED" {
		t.Fatal(result)
	}
	bad := map[string]any{"identityId": ia, "conversationId": conv, "firstSequence": 1, "lastSequence": 1, "reason": "OTHER", "description": "", "images": []any{}, "authorized": true, "entries": []any{map[string]any{"messageId": message, "sequence": 1, "kind": "TEXT", "text": "original", "data": "", "gap": "", "accountId": uuid.NewString()}}}
	postHTTPSJSON(t, s, "PUT", "/api/v1/dm/governance/reports/"+uuid.NewString(), a, "", bad, 400)
	report.IdentityID = ib
	postHTTPSJSON(t, s, "PUT", "/api/v1/dm/governance/reports/"+uuid.NewString(), a, "", report, 409)
	if e := s.gate.Freeze(ctx, "DM P3 final Gate"); e != nil {
		t.Fatal(e)
	}
	postHTTPSJSON(t, s, "GET", "/api/v1/dm/governance/blocks", a, "", nil, 503)
	postHTTPSJSON(t, s, "PUT", "/api/v1/dm/governance/blocks/"+uuid.NewString(), a, "", input, 503)
}
