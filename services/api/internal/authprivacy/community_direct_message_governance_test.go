package authprivacy

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"github.com/google/uuid"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/moderation"
	"os"
	"strings"
	"sync"
	"testing"
)

type dmGovernanceFixture struct {
	l                  *lab
	a, b               SessionCreateResult
	ia, ib, post, conv string
	first, reply       DMReceipt
}

func dmGovernanceLab(t *testing.T) *dmGovernanceFixture {
	t.Helper()
	l := moderationLab(t)
	return dmGovernanceFromLab(t, l)
}
func dmGovernanceFromLab(t *testing.T, l *lab) *dmGovernanceFixture {
	t.Helper()
	enableImageLab(t, l)
	var e error
	l.c, e = l.c.WithDirectMessages(context.Background())
	if e != nil {
		t.Fatal(e)
	}
	f := &dmGovernanceFixture{l: l, a: moderationActor(t, l, "dm_gov_a", ""), b: moderationActor(t, l, "dm_gov_b", "")}
	f.ia = identityChange(t, l.c, f.a.SessionToken, "CREATE", uuid.Nil, "治理甲").IdentityID.String()
	f.ib = identityChange(t, l.c, f.b.SessionToken, "CREATE", uuid.Nil, "治理乙").IdentityID.String()
	f.post = commentTextPost(t, l, f.b.SessionToken, uuid.MustParse(f.ib))
	f.first = f.send(t, f.a.SessionToken, DMTextIntent{IdentityID: f.ia, PeerID: f.ib, SourcePostID: f.post, Text: "first original", Attempt: 1})
	f.conv = f.first.ConversationID
	f.reply = f.send(t, f.b.SessionToken, DMTextIntent{IdentityID: f.ib, PeerID: f.ia, ConversationID: f.conv, Text: "reply original", Attempt: 1})
	return f
}
func (f *dmGovernanceFixture) send(t *testing.T, b [32]byte, in DMTextIntent) DMReceipt {
	t.Helper()
	r, e := f.l.c.SendDMText(context.Background(), b, uuid.NewString(), in)
	if e != nil {
		t.Fatal(e)
	}
	return r.Value.(DMReceipt)
}
func (f *dmGovernanceFixture) report() DMReportInput {
	return DMReportInput{IdentityID: f.ia, ConversationID: f.conv, FirstSequence: 1, LastSequence: 2, Reason: "HARASSMENT", Images: []moderation.Image{}, Authorized: true, Entries: []DMEvidenceEntry{{MessageID: f.first.MessageID, Sequence: 1, Kind: "TEXT", Text: "first original"}, {MessageID: f.reply.MessageID, Sequence: 2, Kind: "TEXT", Text: "reply original"}}}
}
func TestDMGovernanceBlocksCrossMaskAndPendingPostgres(t *testing.T) {
	f := dmGovernanceLab(t)
	ctx := context.Background()
	c := f.l.c
	alt := identityChange(t, c, f.a.SessionToken, "CREATE", uuid.Nil, "另一甲").IdentityID.String()
	otherPost := commentTextPost(t, f.l, f.b.SessionToken, uuid.MustParse(f.ib))
	second := f.send(t, f.a.SessionToken, DMTextIntent{IdentityID: alt, PeerID: f.ib, SourcePostID: otherPost, Text: "alternate", Attempt: 1})
	input := DMBlockInput{IdentityID: f.ia, ConversationID: f.conv, Blocked: true}
	id := uuid.NewString()
	if _, e := c.ChangeDMBlock(ctx, f.a.SessionToken, id, input); e != nil {
		t.Fatal(e)
	}
	if _, e := c.ChangeDMBlock(ctx, f.a.SessionToken, id, input); e != nil {
		t.Fatal("idempotence", e)
	}
	for _, x := range []struct {
		b                    [32]byte
		identity, peer, conv string
	}{{f.a.SessionToken, f.ia, f.ib, f.conv}, {f.b.SessionToken, f.ib, f.ia, f.conv}, {f.a.SessionToken, alt, f.ib, second.ConversationID}} {
		r := f.send(t, x.b, DMTextIntent{IdentityID: x.identity, PeerID: x.peer, ConversationID: x.conv, Text: "must reject", Attempt: 1})
		if r.ErrorCode != "CONTACT_UNAVAILABLE" {
			t.Fatal(r)
		}
	}
	pending, e := c.PullDMChat(ctx, f.b.SessionToken)
	if e != nil || len(pending.Value.(DMChatPending).Items) != 2 {
		t.Fatal("accepted deliveries lost", e)
	}
	dir, e := c.ReadDMChatDirectory(ctx, f.a.SessionToken, alt, "")
	if e != nil {
		t.Fatal(e)
	}
	v := dir.Value.(DMChatDirectory).Items[0]
	if v.CanSend || v.OwnBlockID != "" {
		t.Fatal("other mask relation leak", v)
	}
	blocks, e := c.DMBlocks(ctx, f.a.SessionToken)
	if e != nil {
		t.Fatal(e)
	}
	raw, _ := json.Marshal(blocks.Value)
	if strings.Contains(string(raw), alt) || strings.Contains(string(raw), f.b.AccountID.String()) || len(blocks.Value.(DMBlocks).Items) != 1 {
		t.Fatal("blacklist projection", string(raw))
	}
	extra := DMBlockInput{IdentityID: alt, ConversationID: second.ConversationID, Blocked: true}
	if _, e = c.ChangeDMBlock(ctx, f.a.SessionToken, uuid.NewString(), extra); e != nil {
		t.Fatal(e)
	}
	d2, e := c.ReadDMChatDirectory(ctx, f.a.SessionToken, alt, "")
	if e != nil || d2.Value.(DMChatDirectory).Items[0].OwnBlockID == "" {
		t.Fatal("explicitly chosen mask missing own projection", e)
	}
	extra.Blocked = false
	if _, e = c.ChangeDMBlock(ctx, f.a.SessionToken, uuid.NewString(), extra); e != nil {
		t.Fatal(e)
	}
	if r := f.send(t, f.a.SessionToken, DMTextIntent{IdentityID: f.ia, PeerID: f.ib, ConversationID: f.conv, Text: "still blocked by original choice", Attempt: 1}); r.ErrorCode != "CONTACT_UNAVAILABLE" {
		t.Fatal(r)
	}
	input.Blocked = false
	if _, e = c.ChangeDMBlock(ctx, f.a.SessionToken, uuid.NewString(), input); e != nil {
		t.Fatal(e)
	}
	if r := f.send(t, f.a.SessionToken, DMTextIntent{IdentityID: f.ia, PeerID: f.ib, ConversationID: f.conv, Text: "after unblock", Attempt: 1}); r.State != "SENT" {
		t.Fatal(r)
	}
	// Competing opposite-account block/send cannot deadlock or bypass a completed block.
	var wg sync.WaitGroup
	errs := make(chan error, 3)
	for i := 0; i < 3; i++ {
		wg.Add(1)
		go func(n int) {
			defer wg.Done()
			var e error
			if n == 0 {
				_, e = c.ChangeDMBlock(ctx, f.a.SessionToken, uuid.NewString(), DMBlockInput{IdentityID: f.ia, ConversationID: f.conv, Blocked: true})
			} else if n == 1 {
				_, e = c.ChangeDMBlock(ctx, f.b.SessionToken, uuid.NewString(), DMBlockInput{IdentityID: f.ib, ConversationID: f.conv, Blocked: true})
			} else {
				_, e = c.SendDMText(ctx, f.b.SessionToken, uuid.NewString(), DMTextIntent{IdentityID: f.ib, PeerID: f.ia, ConversationID: f.conv, Text: "racing", Attempt: 1})
			}
			errs <- e
		}(i)
	}
	wg.Wait()
	close(errs)
	for e := range errs {
		if e != nil {
			t.Fatal(e)
		}
	}
}
func TestDMGovernanceSnapshotAuthenticityFencesAndModerationPostgres(t *testing.T) {
	f := dmGovernanceLab(t)
	ctx := context.Background()
	c := f.l.c
	in := f.report()
	for _, x := range []struct {
		b  [32]byte
		id string
	}{{f.b.SessionToken, f.first.MessageID}, {f.a.SessionToken, f.reply.MessageID}} {
		if _, e := c.AcknowledgeDM(ctx, x.b, []string{x.id}, false); e != nil {
			t.Fatal(e)
		}
	}
	if count(t, f.l.cp, `SELECT count(*) FROM c_dm.messages WHERE body IS NOT NULL`) != 0 {
		t.Fatal("ACK retained ordinary history")
	}
	forged := f.report()
	forged.Entries[0].Text = "forged"
	_, e := c.SubmitDMReport(ctx, f.a.SessionToken, uuid.NewString(), forged)
	postTestError(t, e, "EVIDENCE_MISMATCH", 409)
	unauthorized := f.report()
	unauthorized.Authorized = false
	if _, e = c.SubmitDMReport(ctx, f.a.SessionToken, uuid.NewString(), unauthorized); e == nil {
		t.Fatal("missing authorization accepted")
	}
	task := uuid.NewString()
	absent, e := c.GetDMReport(ctx, f.a.SessionToken, task)
	if e != nil {
		t.Fatal(e)
	}
	if _, e = c.SubmitDMReport(ctx, f.a.SessionToken, task, in); e == nil {
		t.Fatal("late sealed PUT accepted")
	}
	in.RetryToken = absent.Value.(moderation.ReportResult).RetryToken
	if _, e = c.ExecuteDMChatOperation(ctx, f.a.SessionToken, uuid.NewString(), DMChatOperation{IdentityID: f.ia, ConversationID: f.conv, Operation: "RETRACT", MessageID: f.first.MessageID}); e != nil {
		t.Fatal(e)
	}
	result, e := c.SubmitDMReport(ctx, f.a.SessionToken, task, in)
	if e != nil {
		t.Fatal(e)
	}
	report := result.Value.(moderation.ReportResult).Report
	if report.PostID != "" || report.ConversationID == nil || *report.ConversationID != f.conv {
		t.Fatal("wrong report target", report)
	}
	if _, e = c.SubmitDMReport(ctx, f.a.SessionToken, task, in); e != nil {
		t.Fatal(e)
	}
	reviewer := moderationActor(t, f.l, "dm_gov_reviewer", "REVIEWER")
	if _, e = c.ReadModeration(ctx, f.a.SessionToken, "case", report.CaseID, "", "", 50); e == nil {
		t.Fatal("ordinary evidence read")
	}
	detail, e := c.ReadModeration(ctx, reviewer.SessionToken, "case", report.CaseID, "", "", 50)
	if e != nil {
		t.Fatal(e)
	}
	snapshot := detail.Value.(moderation.Case).Evidence.Body
	if !strings.Contains(snapshot, "已撤回") {
		t.Fatal("missing server retraction marker")
	}
	if !strings.Contains(snapshot, "first original") || !strings.Contains(snapshot, "reply original") {
		t.Fatal(snapshot)
	}
	if _, e = c.ExecuteDMChatOperation(ctx, f.a.SessionToken, uuid.NewString(), DMChatOperation{IdentityID: f.ia, ConversationID: f.conv, Operation: "RETRACT", MessageID: f.first.MessageID}); e != nil {
		t.Fatal(e)
	}
	if _, e = c.ExecuteDMChatOperation(ctx, f.a.SessionToken, uuid.NewString(), DMChatOperation{IdentityID: f.ia, ConversationID: f.conv, Operation: "DELETE", ThroughSequence: 2}); e != nil {
		t.Fatal(e)
	}
	detail, e = c.ReadModeration(ctx, reviewer.SessionToken, "case", report.CaseID, "", "", 50)
	if e != nil || detail.Value.(moderation.Case).Evidence.Body != snapshot {
		t.Fatal("snapshot mutated", e)
	}
	decision := moderationDecision(t, f.l, reviewer, report.CaseID, "MUTE", 1)
	if decision.State != "ENDED" {
		t.Fatal(decision)
	}
	if r := f.send(t, f.b.SessionToken, DMTextIntent{IdentityID: f.ib, PeerID: f.ia, ConversationID: f.conv, Text: "muted", Attempt: 1}); r.ErrorCode != "POSTING_RESTRICTED" {
		t.Fatal(r)
	}
	if count(t, f.l.cp, `SELECT count(*) FROM c_posts.posts WHERE post_id=$1 AND moderation_hidden`, f.post) != 0 {
		t.Fatal("DM sanction hid unrelated source")
	}
	if count(t, f.l.cp, `SELECT count(*) FROM c_moderation.notifications WHERE account_id=$1 AND route_name='REPORT' AND state='ENDED'`, f.a.AccountID) != 1 {
		t.Fatal("no existing progress notification")
	}
	if count(t, f.l.cp, `SELECT count(*) FROM c_moderation.audit WHERE action='READ_DM_EVIDENCE'`) < 2 {
		t.Fatal("evidence access unaudited")
	}
}
func TestDMGovernanceImagesGapsAndIdentityCleanupPostgres(t *testing.T) {
	f := dmGovernanceLab(t)
	ctx := context.Background()
	c := f.l.c
	selection, data := imageFixture(t, "png")
	raw := base64.StdEncoding.EncodeToString(data)
	r, e := c.SendDMImage(ctx, f.b.SessionToken, uuid.NewString(), DMImageIntent{IdentityID: f.ib, PeerID: f.ia, ConversationID: f.conv, GroupID: uuid.NewString(), GroupSize: 1, Selection: selection, Data: raw, Attempt: 1})
	if e != nil {
		t.Fatal(e)
	}
	image := r.Value.(DMReceipt)
	if _, e = c.AcknowledgeDM(ctx, f.a.SessionToken, []string{image.MessageID}, false); e != nil {
		t.Fatal(e)
	}
	in := f.report()
	in.LastSequence = 3
	in.Entries[0] = DMEvidenceEntry{Sequence: 1, Kind: "TEXT", Gap: "LOCAL_UNAVAILABLE"}
	in.Entries = append(in.Entries, DMEvidenceEntry{MessageID: image.MessageID, Sequence: 3, Kind: "IMAGE", Data: raw})
	result, e := c.SubmitDMReport(ctx, f.a.SessionToken, uuid.NewString(), in)
	if e != nil {
		t.Fatal(e)
	}
	caseID := result.Value.(moderation.ReportResult).Report.CaseID
	// A schema-upgraded ACKed message has no trustworthy commitment. Never bless client text.
	mustExec(t, f.l.cp, `ALTER TABLE c_dm.messages DISABLE TRIGGER dm_evidence_immutable`)
	mustExec(t, f.l.cp, `UPDATE c_dm.messages SET evidence_digest=NULL WHERE message_id=$1`, f.first.MessageID)
	mustExec(t, f.l.cp, `ALTER TABLE c_dm.messages ENABLE TRIGGER dm_evidence_immutable`)
	_, e = c.SubmitDMReport(ctx, f.a.SessionToken, uuid.NewString(), f.report())
	postTestError(t, e, "EVIDENCE_UNVERIFIABLE", 409)
	if _, e = c.ExecuteDMChatOperation(ctx, f.a.SessionToken, uuid.NewString(), DMChatOperation{IdentityID: f.ia, ConversationID: f.conv, Operation: "SETTINGS", Note: "private note"}); e != nil {
		t.Fatal(e)
	}
	incoming := f.send(t, f.b.SessionToken, DMTextIntent{IdentityID: f.ib, PeerID: f.ia, ConversationID: f.conv, Text: "pending deleted recipient", Attempt: 1})
	identityChange(t, c, f.a.SessionToken, "CREATE", uuid.Nil, "保留甲")
	identityChange(t, c, f.a.SessionToken, "DELETE", uuid.MustParse(f.ia), "")
	if count(t, f.l.cp, `SELECT count(*) FROM c_dm.messages WHERE message_id=$1 AND body IS NULL AND acknowledged`, incoming.MessageID) != 1 || count(t, f.l.cp, `SELECT count(*) FROM c_dm.settings WHERE identity_id=$1 AND note<>''`, f.ia) != 0 {
		t.Fatal("deleted owner payload survived")
	}
	if count(t, f.l.cp, `SELECT count(*) FROM c_moderation.cases WHERE case_id=$1 AND evidence->>'body' LIKE '%reply original%'`, caseID) != 1 {
		t.Fatal("governance evidence lost")
	}
	// Cleanup still runs through restricted runtime with DM HTTP disabled.
	mustExec(t, f.l.cp, `CREATE TABLE IF NOT EXISTS public.goose_db_version(version_id bigint,is_applied boolean)`)
	for _, name := range []string{"grant-community.sql", "grant-comments.sql", "grant-moderation.sql", "grant-direct-messages.sql"} {
		raw, e := os.ReadFile("../../../../infra/postgres/" + name)
		if e != nil {
			t.Fatal(e)
		}
		mustExec(t, f.l.cp, string(raw))
	}
	pool := moderationLifecycleRuntime(t, f.l)
	clone := *c
	clone.pool = pool
	clone.directMessages = false
	identityChange(t, c, f.b.SessionToken, "CREATE", uuid.Nil, "保留乙")
	identityChange(t, &clone, f.b.SessionToken, "DELETE", uuid.MustParse(f.ib), "")
}

func TestDMGovernanceFormalClosurePostgres(t *testing.T) {
	control := newGateControl(t)
	l := control.lab
	ctx := context.Background()
	enablePostLab(t, l)
	var e error
	l.c, e = l.c.WithModeration(ctx)
	if e != nil {
		t.Fatal(e)
	}
	f := dmGovernanceFromLab(t, l)
	if _, e = l.c.ChangeDMBlock(ctx, f.a.SessionToken, uuid.NewString(), DMBlockInput{IdentityID: f.ia, ConversationID: f.conv, Blocked: true}); e != nil {
		t.Fatal(e)
	}
	if _, e = l.c.SubmitDMReport(ctx, f.a.SessionToken, uuid.NewString(), f.report()); e != nil {
		t.Fatal(e)
	}
	if _, e = l.c.ExecuteDMChatOperation(ctx, f.a.SessionToken, uuid.NewString(), DMChatOperation{IdentityID: f.ia, ConversationID: f.conv, Operation: "SETTINGS", Note: "erase on closure"}); e != nil {
		t.Fatal(e)
	}
	request, _ := closureTestRequest(t, f.a.SessionToken)
	accepted, e := l.c.RequestAccountClosure(ctx, request, sessionTestPasswordWorker(t, 1))
	if e != nil {
		t.Fatal(e)
	}
	advanceClosureClock(t, control, accepted.DueAt)
	if n, e := l.c.FinalizeDueClosures(ctx, 10); e != nil || n != 1 {
		t.Fatal("formal closure", n, e)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_dm.messages m JOIN public.community_identities i ON i.identity_id=m.recipient WHERE i.account_id=$1 AND (m.body IS NOT NULL OR NOT m.acknowledged)`, f.a.AccountID) != 0 || count(t, l.cp, `SELECT count(*) FROM c_dm.blocks WHERE owner_account=$1`, f.a.AccountID) != 0 || count(t, l.cp, `SELECT count(*) FROM c_dm.settings WHERE identity_id=$1 AND note<>''`, f.ia) != 0 {
		t.Fatal("formal closure private data survived")
	}
	if count(t, l.cp, `SELECT count(*) FROM c_dm.messages WHERE message_id=$1 AND body='first original' AND NOT acknowledged`, f.first.MessageID) != 1 {
		t.Fatal("peer accepted delivery lost")
	}
	if count(t, l.cp, `SELECT count(*) FROM c_moderation.cases WHERE conversation_id=$1`, f.conv) != 1 || count(t, l.cp, `SELECT count(*) FROM c_moderation.reports WHERE reporter_account_id=$1`, f.a.AccountID) != 0 {
		t.Fatal("closure evidence/account separation")
	}
}
