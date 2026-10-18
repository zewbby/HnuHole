package comments

import (
	"testing"
	"time"
)

func TestCommentTextPersistenceCheckpoint(t *testing.T) {
	at := time.Now().UTC()
	content := Content{Body: "保留原文\r\n e\u0301"}
	r := Record{TaskID: "a1111111-1111-4111-8111-111111111111", CommentID: "a2222222-2222-4222-8222-222222222222", Binding: Binding{PostID: "a3333333-3333-4333-8333-333333333333", IdentityID: "a4444444-4444-4444-8444-444444444444"}, Content: &content, State: Failed, Version: 3, AcceptedAt: at, TerminalAt: at, Failure: FailurePublishingStopped, IdentityActive: true, OwnerVisible: true}
	task, e := Restore(r)
	if e != nil {
		t.Fatal(e)
	}
	next, e := task.Retry(3, Content{Body: "修改后重试"}, at)
	if e != nil || next.View().AttemptVersion != 4 || next.View().Binding != r.Binding {
		t.Fatal("checkpoint did not reuse core transitions")
	}
	abandoned, e := task.Abandon(3, at)
	if e != nil || abandoned.View().Content != nil {
		t.Fatal("abandon checkpoint")
	}
	r.State = Abandoned
	r.OwnerVisible = false
	r.Content = nil
	if _, e = Restore(r); e != nil {
		t.Fatal(e)
	}
	invalid := []Record{r, r, r, r}
	invalid[0].Version = 0
	invalid[1].OwnerVisible = true
	invalid[2].TerminalAt = at.Add(-time.Second)
	invalid[3].State = Accepted
	for _, record := range invalid {
		if _, e = Restore(record); e == nil {
			t.Fatal("invalid checkpoint accepted")
		}
	}
}
