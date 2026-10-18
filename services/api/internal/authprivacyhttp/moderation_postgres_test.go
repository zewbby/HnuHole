package authprivacyhttp

import (
	"context"
	"encoding/json"
	"strings"
	"testing"

	"github.com/google/uuid"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
)

func TestRealHTTPSModerationReportReviewNoticeAppealPostgres(t *testing.T) {
	s := e2eNewServices(t, func(c *authprivacy.Community) *authprivacy.Community {
		v, e := c.WithModeration(context.Background())
		if e != nil {
			t.Fatal(e)
		}
		return v
	})
	owner, ownerID := e2ePrivacySignup(t, s, "mod_https_owner")
	reporter, reporterID := e2ePrivacySignup(t, s, "mod_https_reporter")
	reviewer, reviewerID := e2ePrivacySignup(t, s, "mod_https_reviewer")
	admin, adminID := e2ePrivacySignup(t, s, "mod_https_admin")
	for _, a := range []struct{ id, role string }{{reviewerID, "REVIEWER"}, {adminID, "ADMIN"}} {
		if _, e := s.cp.Exec(context.Background(), `INSERT INTO c_moderation.roles VALUES($1,$2)`, a.id, a.role); e != nil {
			t.Fatal(e)
		}
	}
	channel := postHTTPSChannel(t, s, owner)
	identity := postHTTPSIdentity(t, s, owner, "帖子身份", 51)
	reportIdentity := postHTTPSIdentity(t, s, reporter, "举报身份", 52)
	created := postHTTPSJSON(t, s, "PUT", "/api/v1/post-commands/"+httpTestEncoding(16, 53), owner, "", posts.CreatePostInput{ChannelID: channel, IdentityID: identity, Title: "治理链路", Body: "仅合成内容"}, 202)
	postID := created["postId"].(string)
	if _, e := s.c.PublishAcceptedPosts(context.Background(), 100); e != nil {
		t.Fatal(e)
	}
	key := uuid.NewString()
	path := "/api/v1/reports/" + key
	input := map[string]any{"postId": postID, "identityId": reportIdentity, "reason": "HARASSMENT", "description": "合成举报材料", "images": []any{}}
	// A missing result is sealed transactionally. A delayed original cannot create a case.
	absent := postHTTPSJSON(t, s, "GET", path, reporter, "", nil, 200)
	if absent["state"] != "NOT_SUBMITTED" || absent["retryToken"] == nil {
		t.Fatal("missing authoritative retry fence")
	}
	postHTTPSJSON(t, s, "PUT", path, reporter, "", input, 409)
	input["retryToken"] = absent["retryToken"]
	result := postHTTPSJSON(t, s, "PUT", path, reporter, "", input, 200)
	caseID := result["report"].(map[string]any)["caseId"].(string)
	postHTTPSJSON(t, s, "PUT", path, reporter, "", input, 200)
	for _, id := range []string{caseID, uuid.NewString()} {
		for _, token := range []string{reporter, httpTestEncoding(32, 41)} {
			postHTTPSJSON(t, s, "POST", "/api/v1/moderation/cases/"+id+"/decision", token, "", map[string]any{"commandId": uuid.NewString(), "expectedVersion": 1, "action": "TAKEDOWN", "days": 0, "reason": "越权"}, map[bool]int{true: 403, false: 401}[token == reporter])
		}
	}
	detail := postHTTPSJSON(t, s, "GET", "/api/v1/moderation/cases/"+caseID, reviewer, "", nil, 200)
	b, _ := json.Marshal(detail)
	for _, secret := range []string{ownerID, reporterID, reviewerID, "username", "email", "slotId", "reporterAccount"} {
		if strings.Contains(string(b), secret) {
			t.Fatal("management leaked identity metadata")
		}
	}
	command := map[string]any{"commandId": uuid.NewString(), "expectedVersion": 1, "action": "MUTE", "days": 3, "reason": "合成限时禁言"}
	decision := postHTTPSJSON(t, s, "POST", "/api/v1/moderation/cases/"+caseID+"/decision", reviewer, "", command, 200)
	sanctionID := decision["sanctions"].([]any)[0].(map[string]any)["id"].(string)
	postHTTPSJSON(t, s, "GET", "/api/v1/posts/"+postID, reporter, "", nil, 404)
	notices := postHTTPSJSON(t, s, "GET", "/api/v1/system-notifications?identityId="+reportIdentity, reporter, "", nil, 200)["items"].([]any)
	if len(notices) != 2 {
		t.Fatal("report progress/result missing")
	}
	n := notices[0].(map[string]any)
	postHTTPSJSON(t, s, "GET", "/api/v1/system-notifications/"+n["id"].(string), reporter, "", nil, 404)
	postHTTPSJSON(t, s, "POST", "/api/v1/system-notifications/"+n["id"].(string)+"/read?identityId="+reportIdentity, reporter, "", map[string]any{}, 200)
	penalty := postHTTPSJSON(t, s, "GET", "/api/v1/sanctions/"+sanctionID, owner, "", nil, 200)
	if penalty["action"] != "MUTE" {
		t.Fatal("sanction route failed")
	}
	appealKey := uuid.NewString()
	appealPath := "/api/v1/sanctions/" + sanctionID + "/appeals/" + appealKey
	appealInput := map[string]any{"description": "新的合成申诉材料", "images": []any{}}
	appeal := postHTTPSJSON(t, s, "PUT", appealPath, owner, "", appealInput, 200)
	appealID := appeal["id"].(string)
	review := map[string]any{"commandId": uuid.NewString(), "expectedVersion": 1, "accept": true, "reason": "独立复核撤销"}
	postHTTPSJSON(t, s, "POST", "/api/v1/moderation/appeals/"+appealID+"/decision", reviewer, "", review, 403)
	review["commandId"] = uuid.NewString()
	postHTTPSJSON(t, s, "POST", "/api/v1/moderation/appeals/"+appealID+"/decision", admin, "", review, 200)
	postHTTPSJSON(t, s, "GET", "/api/v1/posts/"+postID, reporter, "", nil, 200)
	postHTTPSJSON(t, s, "GET", "/api/v1/moderation/audit?caseId="+caseID, admin, "", nil, 200)
}
