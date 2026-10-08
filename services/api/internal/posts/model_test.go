package posts

import (
	"encoding/json"
	"reflect"
	"sort"
	"testing"
	"time"
)

func assertJSONKeys(t *testing.T, value any, expected ...string) map[string]json.RawMessage {
	t.Helper()
	raw, err := json.Marshal(value)
	if err != nil {
		t.Fatal(err)
	}
	var object map[string]json.RawMessage
	if err := json.Unmarshal(raw, &object); err != nil {
		t.Fatal(err)
	}
	var actual []string
	for key := range object {
		actual = append(actual, key)
	}
	sort.Strings(actual)
	sort.Strings(expected)
	if !reflect.DeepEqual(actual, expected) {
		t.Fatalf("strict DTO keys %v want %v", actual, expected)
	}
	return object
}

func TestPublicAndOwnDTOKeepSeparate(t *testing.T) {
	author := PublicAuthor{State: "ACTIVE", Nickname: "当前昵称", Avatar: "default-v1", ShortCode: "ABCDEFGHIJKL"}
	assertJSONKeys(t, author, "state", "nickname", "avatar")
	author.State = "DELETED"
	author.Avatar = "inactive-v1"
	assertJSONKeys(t, author, "state", "shortCode", "avatar")
	author.State = "ACCOUNT_CLOSED"
	assertJSONKeys(t, author, "state", "shortCode", "avatar")
	card := PublicPostCard{PostID: testID, ChannelID: otherID, Title: "标题", Author: author, PublishedAt: time.Now().UTC()}
	assertJSONKeys(t, card, "postId", "channelId", "title", "author", "publishedAt")
	post := PublicPost{PostID: testID, ChannelID: otherID, Title: "标题", Body: "正文", Author: author, PublishedAt: time.Now().UTC()}
	assertJSONKeys(t, post, "postId", "channelId", "title", "body", "author", "publishedAt")
}

func TestCommandResultsHaveOperationSpecificFields(t *testing.T) {
	cases := []struct {
		result CommandResult
		keys   []string
	}{
		{CommandResult{State: "UNKNOWN_NOT_OBSERVED", PostID: testID}, []string{"state"}},
		{CommandResult{State: "RESULT_EXPIRED", TaskID: testID}, []string{"state"}},
		{CommandResult{State: "ACCEPTED", Operation: Create, TaskID: testID, PostID: otherID, AttemptVersion: 1}, []string{"state", "operation", "taskId", "postId", "attemptVersion"}},
		{CommandResult{State: "COMMITTED", Operation: Cancel, TaskID: testID, AttemptVersion: 1, TaskState: Published, PostID: otherID}, []string{"state", "operation", "taskId", "attemptVersion", "taskState"}},
		{CommandResult{State: "COMMITTED", Operation: DeletePost, PostID: testID, TaskID: otherID}, []string{"state", "operation", "postId"}},
		{CommandResult{State: "COMMITTED", Operation: HideTask, TaskID: testID, AttemptVersion: 2, TaskState: Failed}, []string{"state", "operation", "taskId", "attemptVersion"}},
		{CommandResult{State: "REJECTED", Operation: Retry, ErrorCode: "TASK_VERSION_CONFLICT", TaskID: testID}, []string{"state", "operation", "errorCode"}},
		{CommandResult{State: "NOT_ACCEPTED", Operation: Create, Reason: "COMMAND_SEALED"}, []string{"state", "operation", "reason"}},
	}
	for _, c := range cases {
		assertJSONKeys(t, c.result, c.keys...)
	}
	for _, bad := range []CommandResult{{State: "UNKNOWN"}, {State: "ACCEPTED", Operation: DeletePost}, {State: "COMMITTED", Operation: Cancel, TaskID: testID, AttemptVersion: 1, TaskState: Accepted}, {State: "REJECTED", Operation: Create, ErrorCode: "raw SQL error"}} {
		if _, err := json.Marshal(bad); err == nil {
			t.Fatal("invalid result was serialized")
		}
	}
}
