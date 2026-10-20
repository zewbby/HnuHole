package authprivacy

import (
	"context"
	"github.com/google/uuid"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
	"testing"
)

func TestFeedInteractionConditionalDelayedWritePostgres(t *testing.T) {
	l, ctx := newPostLab(t), context.Background()
	owner := sessionTestAccount(t, l, "fence_owner")
	reader := sessionTestAccount(t, l, "fence_reader")
	other := sessionTestAccount(t, l, "fence_other")
	identity := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "Fence").IdentityID
	p := postTestCommand(t, l, owner.SessionToken, postTestKey(t), postTestIntent(t, l, identity))
	postTestPublish(t, l)
	read := func(token [32]byte) PostResponse {
		r, e := l.c.ReadPostInteractions(ctx, token, []string{p.PostID})
		if e != nil || !posts.ValidInteractionVersion(r.InteractionVersion) {
			t.Fatal("read fence", e)
		}
		return r
	}
	for _, kind := range []posts.InteractionKind{posts.PostLike, posts.PostFavorite} {
		initial := read(reader.SessionToken)
		interactionTestSet(t, l, other.SessionToken, p.PostID, kind, true)
		if read(reader.SessionToken).InteractionVersion != initial.InteractionVersion {
			t.Fatal("another account changed private write version")
		}
		interactionTestSet(t, l, other.SessionToken, p.PostID, kind, false)
		if read(reader.SessionToken).InteractionVersion != initial.InteractionVersion {
			t.Fatal("aggregate ABA changed write version")
		}
		foreign := read(other.SessionToken)
		if initial.InteractionVersion == foreign.InteractionVersion {
			t.Fatal("tag not account-bound")
		}
		_, e := l.c.SetPostInteractionConditional(ctx, reader.SessionToken, p.PostID, kind, true, foreign.InteractionVersion)
		postTestError(t, e, "INTERACTION_VERSION_CONFLICT", 412)
		// First request is held before the final transaction; a same-intent retry
		// commits, then a reverse intent commits. Deliver the original CAS last.
		barrier := &identitySnapshotBarrier{AuthorizationGate: l.c.gate, captured: make(chan struct{}), release: make(chan struct{})}
		delayed := *l.c
		delayed.gate = barrier
		done := make(chan error, 1)
		go func() {
			_, err := delayed.SetPostInteractionConditional(ctx, reader.SessionToken, p.PostID, kind, true, initial.InteractionVersion)
			done <- err
		}()
		<-barrier.captured
		committed, e := l.c.SetPostInteractionConditional(ctx, reader.SessionToken, p.PostID, kind, true, initial.InteractionVersion)
		if e != nil || committed.InteractionVersion == initial.InteractionVersion {
			t.Fatal("first CAS", e)
		}
		_, e = l.c.SetPostInteractionConditional(ctx, reader.SessionToken, p.PostID, kind, false, committed.InteractionVersion)
		if e != nil {
			t.Fatal("reverse CAS", e)
		}
		close(barrier.release)
		e = <-done
		postTestError(t, e, "INTERACTION_VERSION_CONFLICT", 412)
		after := read(reader.SessionToken)
		item := after.Value.(posts.PostInteractionPage).Items[0]
		if item.LikedByMe || item.FavoritedByMe {
			t.Fatal("late request overwrote reverse")
		}
		// Same-value no-op must rotate even for old unconditional clients; no ABA.
		interactionTestSet(t, l, reader.SessionToken, p.PostID, kind, false)
		if read(reader.SessionToken).InteractionVersion == after.InteractionVersion {
			t.Fatal("same-value legacy fence did not rotate")
		}
		_, e = l.c.SetPostInteractionConditional(ctx, reader.SessionToken, p.PostID, kind, true, after.InteractionVersion)
		postTestError(t, e, "INTERACTION_VERSION_CONFLICT", 412)
	}
}

func TestFeedInteractionLegacyDelayedWriteReproductionPostgres(t *testing.T) {
	l, ctx := newPostLab(t), context.Background()
	a := sessionTestAccount(t, l, "legacy_delayed")
	id := identityChange(t, l.c, a.SessionToken, "CREATE", uuid.Nil, "Legacy").IdentityID
	p := postTestCommand(t, l, a.SessionToken, postTestKey(t), postTestIntent(t, l, id))
	postTestPublish(t, l)
	barrier := &identitySnapshotBarrier{AuthorizationGate: l.c.gate, captured: make(chan struct{}), release: make(chan struct{})}
	delayed := *l.c
	delayed.gate = barrier
	done := make(chan error, 1)
	go func() {
		_, e := delayed.SetPostInteraction(ctx, a.SessionToken, p.PostID, posts.PostLike, true)
		done <- e
	}()
	<-barrier.captured
	interactionTestSet(t, l, a.SessionToken, p.PostID, posts.PostLike, true)
	interactionTestSet(t, l, a.SessionToken, p.PostID, posts.PostLike, false)
	close(barrier.release)
	if e := <-done; e != nil {
		t.Fatal(e)
	}
	if !interactionTestRead(t, l, a.SessionToken, p.PostID)[0].LikedByMe {
		t.Fatal("legacy reproduction changed; revisit compatibility")
	}
}

func TestFeedInteractionConditionalConcurrentAndRollbackPostgres(t *testing.T) {
	l, ctx := newPostLab(t), context.Background()
	owner := sessionTestAccount(t, l, "fence_concurrent")
	id := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "Fence").IdentityID
	p := postTestCommand(t, l, owner.SessionToken, postTestKey(t), postTestIntent(t, l, id))
	postTestPublish(t, l)
	r, e := l.c.ReadPostInteractions(ctx, owner.SessionToken, []string{p.PostID})
	if e != nil {
		t.Fatal(e)
	}
	done := make(chan error, 8)
	for i := 0; i < 8; i++ {
		go func() {
			_, err := l.c.SetPostInteractionConditional(ctx, owner.SessionToken, p.PostID, posts.PostLike, true, r.InteractionVersion)
			done <- err
		}()
	}
	success := 0
	for i := 0; i < 8; i++ {
		if e := <-done; e == nil {
			success++
		} else {
			postTestError(t, e, "INTERACTION_VERSION_CONFLICT", 412)
		}
	}
	if success != 1 {
		t.Fatal("CAS allowed multiple commits", success)
	}
	// Failure after fact write must roll back the fact and preserve the fence.
	r, e = l.c.ReadPostInteractions(ctx, owner.SessionToken, []string{p.PostID})
	if e != nil {
		t.Fatal(e)
	}
	mustExec(t, l.cp, `CREATE FUNCTION c_posts.reject_test_fence() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'fixture fence failure'; END $$; CREATE TRIGGER reject_fence BEFORE UPDATE ON c_posts.post_interaction_versions FOR EACH ROW EXECUTE FUNCTION c_posts.reject_test_fence()`)
	if _, e = l.c.SetPostInteractionConditional(ctx, owner.SessionToken, p.PostID, posts.PostLike, false, r.InteractionVersion); e == nil {
		t.Fatal("fence failure committed")
	}
	mustExec(t, l.cp, `DROP TRIGGER reject_fence ON c_posts.post_interaction_versions; DROP FUNCTION c_posts.reject_test_fence()`)
	after, e := l.c.ReadPostInteractions(ctx, owner.SessionToken, []string{p.PostID})
	if e != nil || after.InteractionVersion != r.InteractionVersion || !after.Value.(posts.PostInteractionPage).Items[0].LikedByMe {
		t.Fatal("partial fence/fact commit", e)
	}
}
