package moderation

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestCommentReportTargetAndOriginalFingerprint(t *testing.T) {
	post := "11111111-1111-4111-8111-111111111111"
	comment := "22222222-2222-4222-8222-222222222222"
	in := ReportInput{PostID: post, Reason: "OTHER", Images: []Image{}}
	legacy, _ := json.Marshal(in)
	if strings.Contains(string(legacy), "commentId") {
		t.Fatal("post replay fingerprint changed")
	}
	postFingerprint := Fingerprint(in)
	in.CommentID = &comment
	if in.Validate() != nil || Fingerprint(in) == postFingerprint {
		t.Fatal("concrete target missing from original intent")
	}
	for _, invalid := range []string{"", "00000000-0000-0000-0000-000000000000", "https://example.invalid/comment", "22222222-2222-4222-8222-22222222222G"} {
		in.CommentID = &invalid
		if in.Validate() == nil {
			t.Fatal("invalid comment resource accepted")
		}
	}
}
