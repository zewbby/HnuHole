package authprivacy

import (
	"bytes"
	"context"
	"errors"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/comments"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/postmedia"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
	"os"
	"os/exec"
	"strings"
	"testing"
)

func TestIdentityAvatarRestrictedLifecyclePostgres(t *testing.T) {
	control := newGateControl(t)
	l := control.lab
	enablePostLab(t, l)
	ctx := context.Background()
	enableImageLab(t, l)
	owner := sessionTestAccount(t, l, "avatar_owner")
	foreign := sessionTestAccount(t, l, "avatar_foreign")
	// Exercise real restricted runtime DML, including trigger-invoked erasure.
	dsn := os.Getenv("AUTHLAB_POSTS_RUNTIME_DSN")
	if dsn == "" {
		t.Fatal("restricted runtime fixture required")
	}
	mustExec(t, l.cp, `CREATE TABLE IF NOT EXISTS public.goose_db_version(version_id bigint,is_applied boolean)`)
	mustExec(t, l.cp, `REVOKE CREATE,TEMP ON DATABASE hnuhole_c FROM PUBLIC,hnuhole_c_runtime,hnuhole_c_recovery,hnuhole_business`)
	grants, e := os.ReadFile("../../../../infra/postgres/grant-community.sql")
	if e != nil {
		t.Fatal(e)
	}
	if _, e = l.cp.Exec(ctx, string(grants)); e != nil {
		t.Fatal(e)
	}
	pool, e := pgxpool.New(ctx, dsn)
	if e != nil {
		t.Fatal(e)
	}
	defer pool.Close()
	audit, e := os.ReadFile("../../authlab/privacy-role-audit.sql")
	if e != nil {
		t.Fatal(e)
	}
	if _, e = l.cp.Exec(ctx, strings.Replace(strings.Replace(string(audit), ":'party'", "'c'", 1), "RAISE EXCEPTION 'operational role acquired noncontract table privilege';", "RAISE EXCEPTION 'operational role acquired noncontract table privilege: % %.% %',audit_role,relation.nspname,relation.relname,privilege;", 1)); e != nil {
		t.Fatal("restricted role privacy audit", e)
	}
	service := *l.c
	service.pool = pool
	selection, data := imageFixture(t, "jpeg")
	data, e = exec.Command(os.Getenv("POST_MEDIA_PYTHON"), "-I", "-c", `from PIL import Image; import io,sys; im=Image.new('RGB',(30,20),'blue'); ex=Image.Exif(); ex[274]=6; ex[270]='HNUHOLE_AVATAR_EXIF_CANARY'; b=io.BytesIO(); im.save(b,format='JPEG',exif=ex); sys.stdout.buffer.write(b.getvalue())`).Output()
	if e != nil {
		t.Fatal(e)
	}
	ids := []uuid.UUID{uuid.New(), uuid.New(), uuid.New(), uuid.New()}
	for i, id := range ids {
		if i > 0 {
			if _, e = service.AbandonIdentityAvatar(ctx, owner.SessionToken, ids[i-1]); e != nil {
				t.Fatal(e)
			}
		}
		if _, e = service.UploadIdentityAvatar(ctx, owner.SessionToken, id, data, selection.MIME); e != nil {
			t.Fatal(e)
		}
		if _, e = service.UploadIdentityAvatar(ctx, owner.SessionToken, id, data, selection.MIME); e != nil {
			t.Fatal("same PUT retry", e)
		}
	}
	last := ids[3]
	ref := "avatar-v1:" + last.String()
	if count(t, l.cp, `SELECT count(*) FROM public.identity_avatar_assets WHERE payload IS NOT NULL`) != 1 {
		t.Fatal("preview replacement leaked active budget")
	}
	if _, _, e = service.ReadIdentityAvatar(ctx, foreign.SessionToken, last); e == nil {
		t.Fatal("foreign draft readable")
	}
	got, _, e := service.ReadIdentityAvatar(ctx, owner.SessionToken, last)
	if e != nil || got.MIME != "image/webp" || !bytes.Equal(got.Bytes[:4], []byte("RIFF")) || bytes.Equal(got.Bytes, data) {
		t.Fatal("not normalized", e)
	}
	metadata, e := l.c.postImages.validator.Inspect(ctx, got.Bytes)
	if e != nil || metadata.Width != 20 || metadata.Height != 30 || bytes.Contains(got.Bytes, []byte("EXIF")) || bytes.Contains(got.Bytes, []byte("HNUHOLE_AVATAR_EXIF_CANARY")) {
		t.Fatal("EXIF orientation/metadata not normalized", e)
	}
	createRequest := IdentityChangeRequest{Bearer: owner.SessionToken, ChangeID: identityRequestKey(t), Operation: "CREATE", Nickname: "蓝海风", Avatar: ref}
	first, e := service.ChangeOwnIdentity(ctx, createRequest)
	if e != nil || first.State != "COMMITTED" {
		t.Fatal(e, first)
	}
	createRequest.Avatar = IdentityDefaultAvatar
	if _, e = service.ChangeOwnIdentity(ctx, createRequest); !errors.Is(e, ErrIdentityChangeConflict) {
		t.Fatal("same key accepted changed avatar", e)
	}
	foreignBind, e := service.ChangeOwnIdentity(ctx, IdentityChangeRequest{Bearer: foreign.SessionToken, ChangeID: identityRequestKey(t), Operation: "CREATE", Nickname: "偷用头像", Avatar: ref})
	if !identityRejected(foreignBind, e, "IDENTITY_AVATAR_INVALID") {
		t.Fatal("cross-account ref bound", e)
	}
	if _, _, e = service.ReadIdentityAvatar(ctx, foreign.SessionToken, last); e != nil {
		t.Fatal("bound profile not readable", e)
	}
	if _, e = service.AbandonIdentityAvatar(ctx, owner.SessionToken, last); e == nil {
		t.Fatal("abandon erased bound asset")
	}
	second := uuid.New()
	if _, e = service.UploadIdentityAvatar(ctx, owner.SessionToken, second, data, selection.MIME); e != nil {
		t.Fatal(e)
	}
	combined, e := service.ChangeOwnIdentity(ctx, IdentityChangeRequest{Bearer: owner.SessionToken, ChangeID: identityRequestKey(t), Operation: "RENAME", IdentityID: first.IdentityID, Nickname: "绿海风", Avatar: "avatar-v1:" + second.String()})
	if e != nil || combined.State != "COMMITTED" {
		t.Fatal(e, combined)
	}
	if _, _, e = service.ReadIdentityAvatar(ctx, owner.SessionToken, last); e == nil {
		t.Fatal("replaced bytes remained readable")
	}
	original := identityDirectory(t, &service, owner.SessionToken)
	if original.CreatedCount != 1 || original.Identities[0].RenameAvailableAt == nil {
		t.Fatal("combined rename did not preserve counters")
	}
	third := uuid.New()
	if _, e = service.UploadIdentityAvatar(ctx, owner.SessionToken, third, data, selection.MIME); e != nil {
		t.Fatal(e)
	}
	changed, e := service.ChangeOwnIdentity(ctx, IdentityChangeRequest{Bearer: owner.SessionToken, ChangeID: identityRequestKey(t), Operation: "AVATAR", IdentityID: first.IdentityID, Avatar: "avatar-v1:" + third.String()})
	if e != nil || changed.State != "COMMITTED" {
		t.Fatal("avatar hit rename cooldown", e)
	}
	after := identityDirectory(t, &service, owner.SessionToken)
	if !after.Identities[0].RenameAvailableAt.Equal(*original.Identities[0].RenameAvailableAt) || after.CreatedCount != 1 {
		t.Fatal("avatar altered nickname/create timing")
	}
	reject, e := service.ChangeOwnIdentity(ctx, IdentityChangeRequest{Bearer: owner.SessionToken, ChangeID: identityRequestKey(t), Operation: "RENAME", IdentityID: first.IdentityID, Nickname: "再改昵称", Avatar: IdentityDefaultAvatar})
	if !identityRejected(reject, e, "IDENTITY_RENAME_COOLDOWN") {
		t.Fatal(e, reject)
	}
	if after.Identities[0].Avatar != "avatar-v1:"+third.String() {
		t.Fatal("rejected combination mutated avatar")
	}
	// Moderator resets and account closure use the same triggers, never a worker.
	mustExec(t, l.cp, `UPDATE public.community_identities SET avatar='default-v1' WHERE identity_id=$1`, first.IdentityID)
	if count(t, l.cp, `SELECT count(*) FROM public.identity_avatar_assets WHERE payload IS NOT NULL`) != 0 {
		t.Fatal("moderator reset retained bytes")
	}
	pending := uuid.New()
	if _, e = service.UploadIdentityAvatar(ctx, owner.SessionToken, pending, data, selection.MIME); e != nil {
		t.Fatal(e)
	}
	bound := uuid.New()
	if _, e = service.UploadIdentityAvatar(ctx, owner.SessionToken, bound, data, selection.MIME); e != nil {
		t.Fatal(e)
	}
	changed, e = service.ChangeOwnIdentity(ctx, IdentityChangeRequest{Bearer: owner.SessionToken, ChangeID: identityRequestKey(t), Operation: "AVATAR", IdentityID: first.IdentityID, Avatar: "avatar-v1:" + bound.String()})
	if e != nil || changed.State != "COMMITTED" {
		t.Fatal(e)
	}
	closure, _ := closureTestRequest(t, owner.SessionToken)
	accepted, e := service.RequestAccountClosure(ctx, closure, sessionTestPasswordWorker(t, 1))
	if e != nil {
		t.Fatal(e)
	}
	advanceClosureClock(t, control, accepted.DueAt)
	if n, e := service.FinalizeDueClosures(ctx, 10); e != nil || n != 1 {
		t.Fatal("formal closure", n, e)
	}
	if count(t, l.cp, `SELECT count(*) FROM public.identity_avatar_assets WHERE payload IS NOT NULL`) != 0 {
		t.Fatal("closure retained bytes")
	}
}

func TestIdentityAvatarExistingPostCommentAndDMProjectionPostgres(t *testing.T) {
	l := commentTextLab(t)
	ctx := context.Background()
	enableImageLab(t, l)
	var e error
	l.c, e = l.c.WithDirectMessages(ctx)
	if e != nil {
		t.Fatal(e)
	}
	owner := sessionTestAccount(t, l, "avatar_projection_owner")
	reader := sessionTestAccount(t, l, "avatar_projection_reader")
	ownID := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "资料作者").IdentityID
	readerID := identityChange(t, l.c, reader.SessionToken, "CREATE", uuid.Nil, "读者身份").IdentityID
	post := commentTextPost(t, l, owner.SessionToken, ownID)
	commentTextSend(t, l, owner.SessionToken, postTestKey(t), comments.Intent{Operation: comments.Create, TaskID: uuid.NewString(), PostID: post, IdentityID: ownID.String(), Body: "原评论"})
	commentTextPublish(t, l)
	sent, e := l.c.SendDMText(ctx, reader.SessionToken, uuid.NewString(), DMTextIntent{IdentityID: readerID.String(), PeerID: ownID.String(), SourcePostID: post, Text: "已有会话", Attempt: 1})
	if e != nil || sent.Value.(DMReceipt).State != "SENT" {
		t.Fatal(e)
	}
	selection, data := imageFixture(t, "png")
	asset := uuid.New()
	if _, e = l.c.UploadIdentityAvatar(ctx, owner.SessionToken, asset, data, selection.MIME); e != nil {
		t.Fatal(e)
	}
	ref := "avatar-v1:" + asset.String()
	changed, e := l.c.ChangeOwnIdentity(ctx, IdentityChangeRequest{Bearer: owner.SessionToken, ChangeID: identityRequestKey(t), Operation: "AVATAR", IdentityID: ownID, Avatar: ref})
	if e != nil || changed.State != "COMMITTED" {
		t.Fatal(e)
	}
	check := func(expected string) {
		t.Helper()
		p, e := l.c.ReadPosts(ctx, reader.SessionToken, PostQuery{Kind: PostDetail, ID: post})
		if e != nil || p.Value.(posts.PublicPostResponse).Post.Author.Avatar != expected {
			t.Fatal("existing post profile stale", e)
		}
		c, e := l.c.ReadComments(ctx, reader.SessionToken, CommentQuery{ID: post})
		if e != nil || len(c.Value.(TextCommentPage).Comments) != 1 || c.Value.(TextCommentPage).Comments[0].Author.Avatar != expected {
			t.Fatal("existing comment profile stale", e)
		}
		d, e := l.c.ReadDMDirectory(ctx, reader.SessionToken, readerID.String(), "")
		if e != nil || d.Value.(DMDirectory).Items[0].PeerAvatar != expected {
			t.Fatal("P1 directory avatar stale", e)
		}
		chat, e := l.c.ReadDMChatDirectory(ctx, reader.SessionToken, readerID.String(), "")
		if e != nil || chat.Value.(DMChatDirectory).Items[0].PeerAvatar != expected {
			t.Fatal("P2 directory avatar stale", e)
		}
	}
	check(ref)
	contact, e := l.c.DMContact(ctx, reader.SessionToken, post, "")
	if e != nil || contact.Value.(DMContact).PeerAvatar != ref {
		t.Fatal("new contact avatar stale", e)
	}
	identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "保留身份")
	identityChange(t, l.c, owner.SessionToken, "DELETE", ownID, "")
	check("inactive-v1")
	if _, _, e = l.c.ReadIdentityAvatar(ctx, reader.SessionToken, asset); e == nil {
		t.Fatal("deleted profile bytes remained readable")
	}
}

type avatarValidatorBarrier struct {
	*postmedia.ProcessValidator
	captured, release chan struct{}
}

func (v *avatarValidatorBarrier) Inspect(ctx context.Context, b []byte) (postmedia.Metadata, error) {
	m, e := v.ProcessValidator.Inspect(ctx, b)
	if e != nil {
		return m, e
	}
	close(v.captured)
	select {
	case <-v.release:
	case <-ctx.Done():
		return m, ctx.Err()
	}
	return m, nil
}
func TestIdentityAvatarFinalAuthorityAfterValidationPostgres(t *testing.T) {
	for _, scenario := range []string{"freeze", "replacement"} {
		t.Run(scenario, func(t *testing.T) {
			l := newPostLab(t)
			ctx := context.Background()
			owner := sessionTestAccount(t, l, "avatar_final_gate")
			validator := &avatarValidatorBarrier{ProcessValidator: imageValidator(t), captured: make(chan struct{}), release: make(chan struct{})}
			var e error
			l.c, e = l.c.WithPostImages(ctx, validator)
			if e != nil {
				t.Fatal(e)
			}
			selection, data := imageFixture(t, "png")
			done := make(chan error, 1)
			go func() {
				_, e := l.c.UploadIdentityAvatar(ctx, owner.SessionToken, uuid.New(), data, selection.MIME)
				done <- e
			}()
			<-validator.captured
			expected := ErrAuthorizationUnavailable
			if scenario == "freeze" {
				if e = l.gate.Freeze(ctx, "owned avatar validation race"); e != nil {
					t.Fatal(e)
				}
			} else {
				expected = ErrSessionReplaced
				if _, e = l.c.CreateSession(ctx, sessionTestRequest(t, "avatar_final_gate"), sessionTestPasswordWorker(t, 1)); e != nil {
					t.Fatal(e)
				}
			}
			close(validator.release)
			if e = <-done; !errors.Is(e, expected) {
				t.Fatal("stale validation reached storage", e)
			}
			if count(t, l.cp, `SELECT count(*) FROM public.identity_avatar_assets WHERE payload IS NOT NULL`) != 0 {
				t.Fatal("lost authority retained avatar bytes")
			}
		})
	}
}

func TestIdentityAvatarAbandonFenceInvalidAndLegacyPostgres(t *testing.T) {
	l := newPostLab(t)
	ctx := context.Background()
	enableImageLab(t, l)
	owner := sessionTestAccount(t, l, "avatar_fences")
	selection, data := imageFixture(t, "png")
	id := uuid.New()
	if _, e := l.c.AbandonIdentityAvatar(ctx, owner.SessionToken, id); e != nil {
		t.Fatal(e)
	}
	if _, e := l.c.UploadIdentityAvatar(ctx, owner.SessionToken, id, data, selection.MIME); e == nil {
		t.Fatal("late PUT revived abandoned ID")
	}
	animated, animation := imageFixture(t, "gif")
	if _, e := l.c.UploadIdentityAvatar(ctx, owner.SessionToken, uuid.New(), animation, animated.MIME); e != postmedia.ErrInvalid {
		t.Fatal("animated avatar accepted", e)
	}
	if _, e := l.c.UploadIdentityAvatar(ctx, owner.SessionToken, uuid.New(), data[:len(data)-1], selection.MIME); e == nil {
		t.Fatal("partial decoder accepted")
	}
	for _, op := range []string{"CREATE", "RENAME", "DELETE"} {
		// V1 fingerprints omit avatar entirely. Receipts accepted by the old client
		// remain reusable after upgrade; no implicit default-v1 enters V2.
		target := uuid.Nil
		name := "旧意图" + op
		if op != "CREATE" {
			target = identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "旧名字"+op).IdentityID
		}
		if op == "DELETE" {
			name = ""
		}
		request := IdentityChangeRequest{Bearer: owner.SessionToken, ChangeID: identityRequestKey(t), Operation: op, IdentityID: target, Nickname: name}
		one, e := l.c.ChangeOwnIdentity(ctx, request)
		if e != nil {
			t.Fatal(e)
		}
		two, e := l.c.ChangeOwnIdentity(ctx, request)
		if e != nil || one.IdentityID != two.IdentityID || one.State != two.State {
			t.Fatal("legacy retry changed result", e)
		}
		expected := requestMAC(l.c.requestKey, []byte("HNUHOLE/IDENTITY-INTENT/V1"), []byte(op), target[:], []byte(name))
		var actual []byte
		key := identityChangeKey(request.ChangeID)
		if e = l.cp.QueryRow(ctx, `SELECT intent_fingerprint FROM public.identity_change_receipts WHERE account_id=$1 AND change_key_digest=$2`, owner.AccountID, key[:]).Scan(&actual); e != nil || !bytes.Equal(actual, expected[:]) {
			t.Fatal("legacy fingerprint upgraded", e)
		}
	}
}
