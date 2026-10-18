package comments

import (
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/postmedia"
)

func resourceID(n int) string { return fmt.Sprintf("00000000-0000-4000-8000-%012x", n) }

var testAt = time.Date(2026, 10, 18, 1, 0, 0, 0, time.UTC)

func imageSelection() postmedia.Selection {
	return postmedia.Selection{MediaID: resourceID(99), SHA256: strings.Repeat("a", 64), ByteLength: 100, MIME: "image/png", Width: 10, Height: 10}
}

func acceptedTask(t *testing.T) Task {
	t.Helper()
	image := imageSelection()
	task, err := Accept(AcceptInput{TaskID: resourceID(1), CommentID: resourceID(2), Binding: Binding{PostID: resourceID(3), IdentityID: resourceID(4), RootCommentID: resourceID(5), TargetCommentID: resourceID(6)}, Content: Content{Body: "原文 e\u0301\r\n👨‍👩‍👧‍👦", Image: &image}, AcceptedAt: testAt})
	if err != nil {
		t.Fatal(err)
	}
	return task
}

func TestContentUsesExistingBodyAndSingleImageRules(t *testing.T) {
	image := imageSelection()
	for _, content := range []Content{{Body: "主评论"}, {Body: "", Image: &image}, {Body: strings.Repeat("文", MaxBodyClusters)}, {Body: strings.Repeat("👨‍👩‍👧‍👦", 1000)}} {
		if err := content.Validate(); err != nil {
			t.Fatalf("valid content rejected: %v", err)
		}
	}
	for _, content := range []Content{{}, {Body: " \t\n"}, {Body: "\x00正文"}, {Body: "\xff"}, {Body: strings.Repeat("文", MaxBodyClusters+1)}, {Image: &postmedia.Selection{}}} {
		if !errors.Is(content.Validate(), ErrInvalid) {
			t.Fatal("invalid content accepted")
		}
	}
	raw, err := json.Marshal(Content{Body: "正文"})
	if err != nil || string(raw) != `{"body":"正文","image":null}` {
		t.Fatal("single nullable image contract changed", string(raw), err)
	}
}

func TestBindingRequiresConcreteRootAndTarget(t *testing.T) {
	binding := Binding{PostID: resourceID(1), IdentityID: resourceID(2)}
	if binding.Validate() != nil {
		t.Fatal("main comment requires a reply target")
	}
	binding.RootCommentID = resourceID(3)
	if !errors.Is(binding.Validate(), ErrInvalid) {
		t.Fatal("reply without concrete target accepted")
	}
	binding.TargetCommentID = resourceID(4)
	if binding.Validate() != nil {
		t.Fatal("valid reply rejected")
	}
	binding.IdentityID = "00000000-0000-0000-0000-000000000000"
	if !errors.Is(binding.Validate(), ErrInvalid) {
		t.Fatal("zero identity accepted")
	}
}

func TestAcceptanceBindingReusesOneIdentityPerPost(t *testing.T) {
	binding, insert, err := AcceptanceBinding(resourceID(1), resourceID(2), nil)
	if err != nil || !insert || binding.PostID != resourceID(1) || binding.IdentityID != resourceID(2) {
		t.Fatal("first accepted sending task did not require atomic binding", err)
	}
	if again, insert, err := AcceptanceBinding(resourceID(1), resourceID(2), &binding); err != nil || insert || again != binding {
		t.Fatal("same post identity not reused", err)
	}
	if _, _, err := AcceptanceBinding(resourceID(1), resourceID(3), &binding); !errors.Is(err, ErrIdentityBound) {
		t.Fatal("second identity accepted for bound post")
	}
	if _, _, err := AcceptanceBinding(resourceID(4), resourceID(2), &binding); !errors.Is(err, ErrInvalid) {
		t.Fatal("binding from another post accepted")
	}
}

func TestAcceptedTaskOnlyResolvesOriginalAttempt(t *testing.T) {
	task := acceptedTask(t)
	view := task.View()
	if view.State != Accepted || view.AttemptVersion != 1 || view.CanRetry || view.CanAbandon || !view.OwnerVisible || view.Content == nil {
		t.Fatal("acceptance state or permissions invalid")
	}
	if _, err := task.Retry(1, Content{Body: "重复发表"}, testAt.Add(time.Second)); !errors.Is(err, ErrState) {
		t.Fatal("unresolved attempt can be retried", err)
	}
	if _, err := task.Abandon(1, testAt.Add(time.Second)); !errors.Is(err, ErrState) {
		t.Fatal("unresolved attempt can be abandoned", err)
	}
	for _, observed := range []Observation{ResultUnknown, TaskAccepted} {
		if action, err := ReconcileAction(observed); err != nil || action != QueryOriginal {
			t.Fatal("unknown/accepted result allowed new send", action, err)
		}
	}
	if _, err := task.Publish(2, testAt.Add(time.Second)); !errors.Is(err, ErrVersion) {
		t.Fatal("stale worker version accepted")
	}
	published, err := task.Publish(1, testAt.Add(time.Second))
	if err != nil || published.View().State != Published || published.View().Content != nil || published.View().CanRetry {
		t.Fatal("publication not terminal", err)
	}
	if _, err = published.Fail(1, FailurePublication, testAt.Add(2*time.Second)); !errors.Is(err, ErrState) {
		t.Fatal("late failure rewrote success")
	}
	if task.View().State != Accepted {
		t.Fatal("transition mutated earlier task fact")
	}
}

func TestConfirmedFailureRetryKeepsIdentityAndConcreteTarget(t *testing.T) {
	task := acceptedTask(t)
	failed, err := task.Fail(1, FailurePublication, testAt.Add(time.Second))
	if err != nil || !failed.View().CanRetry || !failed.View().CanAbandon {
		t.Fatal("confirmed failure unavailable for handling", err)
	}
	if _, err = failed.Retry(2, Content{Body: "修改原内容"}, testAt.Add(2*time.Second)); !errors.Is(err, ErrVersion) {
		t.Fatal("retry ignored expected attempt version")
	}
	retried, err := failed.Retry(1, Content{Body: "移除失败图片后的原目标回复"}, testAt.Add(2*time.Second))
	if err != nil {
		t.Fatal(err)
	}
	before, after := failed.View(), retried.View()
	if after.TaskID != before.TaskID || after.CommentID != before.CommentID || after.Binding != before.Binding || after.State != Accepted || after.AttemptVersion != 2 || after.FailureCode != "" || !after.TerminalAt.IsZero() || after.Content == nil || after.Content.Image != nil {
		t.Fatal("retry changed binding or did not create a new attempt")
	}
	if before.State != Failed || before.AttemptVersion != 1 || before.Content.Image == nil {
		t.Fatal("retry changed prior attempt")
	}
	if _, err = retried.Publish(1, testAt.Add(3*time.Second)); !errors.Is(err, ErrVersion) {
		t.Fatal("late first attempt can publish after retry")
	}
	deleted, err := task.Fail(1, FailureTargetDeleted, testAt.Add(time.Second))
	if err != nil || deleted.View().CanRetry || deleted.View().Content == nil || deleted.View().Binding != before.Binding {
		t.Fatal("deleted target changed original content or target")
	}
	if _, err = deleted.Retry(1, Content{Body: "不能自动改投"}, testAt.Add(2*time.Second)); !errors.Is(err, ErrState) {
		t.Fatal("deleted target allowed direct retry")
	}
}

func TestAbandonIsTerminalAndOnlyForFailedTask(t *testing.T) {
	task := acceptedTask(t)
	failed, _ := task.Fail(1, FailurePublication, testAt.Add(time.Second))
	abandoned, err := failed.Abandon(1, testAt.Add(2*time.Second))
	if err != nil || abandoned.View().State != Abandoned || abandoned.View().OwnerVisible || abandoned.View().Content != nil || abandoned.View().CanRetry || abandoned.View().CanAbandon {
		t.Fatal("abandon retained owner recovery", err)
	}
	if _, err = abandoned.Retry(1, Content{Body: "复活"}, testAt.Add(3*time.Second)); !errors.Is(err, ErrState) {
		t.Fatal("abandoned task revived")
	}
	if action, err := ReconcileAction(TaskAbandoned); err != nil || action != Resolved {
		t.Fatal("abandoned task offered recovery")
	}
}

func TestIdentityDeletionCleansPrivateRecoveryWithoutRewritingSuccess(t *testing.T) {
	task := acceptedTask(t)
	failed, _ := task.Fail(1, FailurePublication, testAt.Add(time.Second))
	published, _ := task.Publish(1, testAt.Add(time.Second))
	for name, original := range map[string]Task{"accepted": task, "failed": failed, "published": published} {
		t.Run(name, func(t *testing.T) {
			deleted, err := original.IdentityDeleted(testAt.Add(2 * time.Second))
			if err != nil {
				t.Fatal(err)
			}
			view := deleted.View()
			if view.OwnerVisible || view.Content != nil || view.CanRetry || view.CanAbandon || view.Binding != original.View().Binding {
				t.Fatal("identity deletion left private recovery or changed binding")
			}
			if name == "published" && view.State != Published || name != "published" && view.State != Failed {
				t.Fatal("identity deletion rewrote publication facts")
			}
			if _, err = deleted.Retry(view.AttemptVersion, Content{Body: "换身份补发"}, testAt.Add(3*time.Second)); !errors.Is(err, ErrIdentity) {
				t.Fatal("deleted identity may retry")
			}
		})
	}
}

func TestTaskContentDoesNotShareMutableImagePointers(t *testing.T) {
	image := imageSelection()
	task, err := Accept(AcceptInput{TaskID: resourceID(1), CommentID: resourceID(2), Binding: Binding{PostID: resourceID(3), IdentityID: resourceID(4)}, Content: Content{Image: &image}, AcceptedAt: testAt})
	if err != nil {
		t.Fatal(err)
	}
	image.MediaID = resourceID(100)
	view := task.View()
	view.Content.Image.MediaID = resourceID(101)
	if task.View().Content.Image.MediaID != resourceID(99) {
		t.Fatal("caller rewrote immutable accepted image")
	}
}
