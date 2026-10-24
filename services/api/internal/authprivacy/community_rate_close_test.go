package authprivacy

import (
	"context"
	"encoding/base64"
	"github.com/google/uuid"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/postmedia"
	"strings"
	"sync"
	"testing"
)

func TestSharedRateDMCloseOrdersLateTextAndImageAndBoundsSQL(t *testing.T) {
	l := commentTextLab(t)
	ctx := context.Background()
	var err error
	l.c, err = l.c.WithDirectMessages(ctx)
	if err != nil {
		t.Fatal(err)
	}
	a := sessionTestAccount(t, l, "close_owner")
	b := sessionTestAccount(t, l, "close_peer")
	own := identityChange(t, l.c, a.SessionToken, "CREATE", uuid.Nil, "关闭甲").IdentityID.String()
	peer := identityChange(t, l.c, b.SessionToken, "CREATE", uuid.Nil, "关闭乙").IdentityID.String()
	post := commentTextPost(t, l, b.SessionToken, uuid.MustParse(peer))
	in := DMTextIntent{IdentityID: own, PeerID: peer, SourcePostID: post, Text: "original", Attempt: 1}
	closed := uuid.NewString()
	r, err := l.c.CloseDMCommand(ctx, a.SessionToken, closed, 2)
	if err != nil || r.Value.(DMReceipt).ErrorCode != "COMMAND_CLOSED" {
		t.Fatal("absent close did not persist permanent anchor", err)
	}
	for _, attempt := range []int{1, 2, 1000} {
		current := in
		current.Attempt = attempt
		current.Text = "late arbitrary body"
		r, err = l.c.SendDMText(ctx, a.SessionToken, closed, current)
		if err != nil || r.Value.(DMReceipt).ErrorCode != "COMMAND_CLOSED" {
			t.Fatal("late text attempt revived closed id", attempt, err)
		}
	}
	image := DMImageIntent{IdentityID: own, PeerID: peer, ConversationID: uuid.NewString(), GroupID: uuid.NewString(), GroupSize: 1, Selection: postmedia.Selection{MediaID: uuid.NewString(), SHA256: strings.Repeat("a", 64), ByteLength: 1, MIME: "image/png", Width: 1, Height: 1}, Data: base64.StdEncoding.EncodeToString([]byte{1}), Attempt: 1000}
	r, err = l.c.SendDMImage(ctx, a.SessionToken, closed, image)
	if err != nil || r.Value.(DMReceipt).ErrorCode != "COMMAND_CLOSED" {
		t.Fatal("late image recreated erased body", err)
	}
	// Same UUID belongs to a separate account and cannot reveal or alter its peer.
	r, err = l.c.GetDMCommand(ctx, b.SessionToken, closed)
	if err != nil || r.Value.(DMReceipt).State != "ABSENT" {
		t.Fatal("close anchor crossed account boundary", err)
	}
	r, err = l.c.CloseDMCommand(ctx, b.SessionToken, closed, 1)
	if err != nil || r.Value.(DMReceipt).ErrorCode != "COMMAND_CLOSED" {
		t.Fatal(err)
	}
	sentID := uuid.NewString()
	r, err = l.c.SendDMText(ctx, a.SessionToken, sentID, in)
	if err != nil {
		t.Fatal(err)
	}
	sent := r.Value.(DMReceipt)
	if sent.State != "SENT" {
		t.Fatal(sent)
	}
	r, err = l.c.CloseDMCommand(ctx, a.SessionToken, sentID, 1000)
	if err != nil || r.Value.(DMReceipt).MessageID != sent.MessageID || r.Value.(DMReceipt).Attempt != sent.Attempt {
		t.Fatal("close falsely cancelled SENT", err)
	}
	r, err = l.c.SendDMText(ctx, b.SessionToken, uuid.NewString(), DMTextIntent{IdentityID: peer, PeerID: own, ConversationID: sent.ConversationID, Text: "reply", Attempt: 1})
	if err != nil || r.Value.(DMReceipt).State != "SENT" {
		t.Fatal(err)
	}
	in.ConversationID = sent.ConversationID
	in.SourcePostID = ""
	// Concurrent close and a delayed original PUT have exactly one durable answer.
	var wg sync.WaitGroup
	for i := 0; i < 10; i++ {
		id := uuid.NewString()
		wg.Add(2)
		go func() {
			defer wg.Done()
			_, e := l.c.SendDMText(ctx, a.SessionToken, id, in)
			if e != nil {
				t.Error(e)
			}
		}()
		go func() {
			defer wg.Done()
			_, e := l.c.CloseDMCommand(ctx, a.SessionToken, id, 1)
			if e != nil {
				t.Error(e)
			}
		}()
	}
	wg.Wait()
	if n := count(t, l.cp, `SELECT count(*) FROM c_dm.commands c LEFT JOIN c_dm.messages m ON m.message_id=c.message_id WHERE c.owner_account=$1 AND (c.error_code='COMMAND_CLOSED' AND m.message_id IS NOT NULL OR c.state='SENT' AND m.message_id IS NULL)`, a.AccountID); n != 0 {
		t.Fatal("close/send race lost immutable receipt or created closed message")
	}
	// A lower old business FAILED cannot be used to escape closure by attempt++.
	failedID := uuid.NewString()
	mustExec(t, l.cp, `INSERT INTO c_dm.commands(owner_account,command_id,fingerprint,attempt,state,error_code) VALUES($1,$2,$3,1,'FAILED','WAITING_FOR_REPLY')`, a.AccountID, failedID, make([]byte, 32))
	_, err = l.c.CloseDMCommand(ctx, a.SessionToken, failedID, 2)
	if err != nil {
		t.Fatal(err)
	}
	in.Attempt = 1000
	r, err = l.c.SendDMText(ctx, a.SessionToken, failedID, in)
	if err != nil || r.Value.(DMReceipt).ErrorCode != "COMMAND_CLOSED" {
		t.Fatal("old FAILED escaped closed anchor", err)
	}
	limiter := sessionTestAccount(t, l, "close_sql_limit")
	first := ""
	for i := 0; i < 120; i++ {
		id := uuid.NewString()
		if i == 0 {
			first = id
		}
		if _, err = l.c.CloseDMCommand(ctx, limiter.SessionToken, id, 1); err != nil {
			t.Fatal("bounded close budget rejected before limit", i, err)
		}
	}
	rejected := uuid.NewString()
	_, err = l.c.CloseDMCommand(ctx, limiter.SessionToken, rejected, 1)
	postTestError(t, err, "RATE_LIMITED", 429)
	if count(t, l.cp, `SELECT count(*) FROM c_dm.commands WHERE owner_account=$1 AND command_id=$2`, limiter.AccountID, rejected) != 0 {
		t.Fatal("pre-admission close429 wrote permanent receipt")
	}
	if _, err = l.c.CloseDMCommand(ctx, limiter.SessionToken, first, 1000); err != nil {
		t.Fatal("closed receipt replay consumed close budget", err)
	}
}
