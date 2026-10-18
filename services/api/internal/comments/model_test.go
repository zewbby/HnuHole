package comments

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestPublicProjectionContainsNoInternalOwnership(t *testing.T) {
	author := PublicAuthor{State: "ACTIVE", Nickname: "同名用户", Avatar: "default-v1"}
	comment := PublicComment{CommentID: resourceID(1), PostID: resourceID(2), RootCommentID: resourceID(3), TargetCommentID: resourceID(4), TargetAuthor: &author, TargetAvailable: false, Author: author, Body: "目标删除后这条回复仍保留", PublishedAt: testAt}
	if err := comment.Validate(); err != nil {
		t.Fatal(err)
	}
	raw, err := json.Marshal(comment)
	if err != nil {
		t.Fatal(err)
	}
	for _, forbidden := range []string{"account", "identityId", "owner", "taskId", "requestDigest", "canDelete", "quote"} {
		if strings.Contains(string(raw), forbidden) {
			t.Fatal("public projection disclosed private context", forbidden)
		}
	}
	var fields map[string]any
	if json.Unmarshal(raw, &fields) != nil || fields["targetCommentId"] != resourceID(4) || fields["targetAvailable"] != false {
		t.Fatal("deleted target relationship was lost")
	}
	comment.Author = PublicAuthor{State: "DELETED", ShortCode: "ABCDEFGHIJKL", Avatar: "inactive-v1"}
	if comment.Validate() != nil {
		t.Fatal("independent inactive identity projection rejected")
	}
	comment.Author.ShortCode = "same-account-id"
	if comment.Validate() == nil {
		t.Fatal("invalid inactive identity label accepted")
	}
}

func TestPublicProjectionDistinguishesMainAndConcreteReply(t *testing.T) {
	comment := PublicComment{CommentID: resourceID(1), PostID: resourceID(2), Author: PublicAuthor{State: "ACTIVE", Nickname: "作者", Avatar: "default-v1"}, Body: "主评论", PublishedAt: testAt}
	if comment.Validate() != nil {
		t.Fatal("main comment rejected")
	}
	comment.RootCommentID = resourceID(3)
	if comment.Validate() == nil {
		t.Fatal("reply without concrete target accepted")
	}
	comment.TargetCommentID = resourceID(1)
	comment.TargetAuthor = &comment.Author
	if comment.Validate() == nil {
		t.Fatal("self-referential reply accepted")
	}
	comment.TargetCommentID = resourceID(4)
	comment.ImageCount = 2
	if comment.Validate() == nil {
		t.Fatal("multi-image comment accepted")
	}
}
