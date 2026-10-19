package authprivacy

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy/protocol"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/postmedia"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
)

func imageValidator(t *testing.T) *postmedia.ProcessValidator {
	t.Helper()
	python := os.Getenv("POST_MEDIA_PYTHON")
	if python == "" {
		t.Skip("dedicated real validator not configured")
	}
	script, e := filepath.Abs("../../media/validate_image.py")
	if configured := os.Getenv("POST_MEDIA_VALIDATOR"); configured != "" {
		script = configured
	}
	if e != nil {
		t.Fatal(e)
	}
	data, e := os.ReadFile(script)
	if e != nil {
		t.Fatal(e)
	}
	hash := sha256.Sum256(data)
	v, e := postmedia.NewProcessValidator(python, script, hex.EncodeToString(hash[:]))
	if e != nil {
		t.Fatal(e)
	}
	return v
}
func enableImageLab(t *testing.T, l *lab) {
	t.Helper()
	var e error
	l.c, e = l.c.WithPostImages(context.Background(), imageValidator(t))
	if e != nil {
		t.Fatal(e)
	}
}
func imageFixture(t *testing.T, format string) (postmedia.Selection, []byte) {
	t.Helper()
	root := os.Getenv("POST_MEDIA_FIXTURES")
	if root == "" {
		t.Skip("synthetic fixtures absent")
	}
	data, e := os.ReadFile(filepath.Join(root, format+".bin"))
	if e != nil {
		t.Fatal(e)
	}
	raw, e := os.ReadFile(filepath.Join(root, format+".json"))
	if e != nil {
		t.Fatal(e)
	}
	var m postmedia.Metadata
	if json.Unmarshal(raw, &m) != nil {
		t.Fatal("metadata fixture")
	}
	return postmedia.Selection{MediaID: uuid.NewString(), SHA256: m.SHA256, ByteLength: m.ByteLength, MIME: m.MIME, Width: m.Width, Height: m.Height}, data
}
func imageGrant(t *testing.T, l *lab, bearer [32]byte, r posts.CommandResult, media string) [32]byte {
	t.Helper()
	response, e := l.c.IssuePostImageGrant(context.Background(), bearer, r.TaskID, media, r.AttemptVersion)
	if e != nil {
		t.Fatal(e)
	}
	raw, e := protocol.DecodeCanonicalBase64url(response.Value.(postmedia.Grant).UploadToken, 32)
	if e != nil {
		t.Fatal("invalid capability")
	}
	var token [32]byte
	copy(token[:], raw)
	return token
}
func imageUpload(t *testing.T, l *lab, r posts.CommandResult, s postmedia.Selection, token [32]byte, data []byte) {
	t.Helper()
	if _, e := l.c.UploadPostImage(context.Background(), token, r.TaskID, s.MediaID, r.AttemptVersion, data, s.MIME); e != nil {
		t.Fatal(e)
	}
}

func TestPostImagesPartialUploadsPublicationAndErasePostgres(t *testing.T) {
	l := newPostLab(t)
	enableImageLab(t, l)
	ctx := context.Background()
	owner := sessionTestAccount(t, l, "image_owner")
	foreign := sessionTestAccount(t, l, "image_reader")
	id := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "图片身份").IdentityID
	intent := postTestIntent(t, l, id)
	intent.Body = ""
	var data [][]byte
	for i := 0; i < 9; i++ {
		s, b := imageFixture(t, []string{"png", "jpeg", "gif", "webp"}[i%4])
		intent.Images = append(intent.Images, s)
		data = append(data, b)
	}
	command := postTestKey(t)
	accepted := postTestCommand(t, l, owner.SessionToken, command, intent)
	var tokens [][32]byte
	for _, s := range intent.Images {
		tokens = append(tokens, imageGrant(t, l, owner.SessionToken, accepted, s.MediaID))
	}
	_, e := l.c.IssuePostImageGrant(ctx, foreign.SessionToken, accepted.TaskID, intent.Images[0].MediaID, 1)
	postTestError(t, e, "MEDIA_UPLOAD_CLOSED", 409)
	_, e = l.c.ReadPostImages(ctx, foreign.SessionToken, accepted.PostID, "")
	postTestError(t, e, "MEDIA_NOT_FOUND", 404)
	for i := 0; i < 7; i++ {
		imageUpload(t, l, accepted, intent.Images[i], tokens[i], data[i])
	}
	for i := 7; i < 9; i++ {
		if _, e := l.c.UploadPostImage(ctx, tokens[i], accepted.TaskID, intent.Images[i].MediaID, 1, data[i][:len(data[i])-1], intent.Images[i].MIME); !errors.Is(e, postmedia.ErrInvalid) {
			t.Fatal("mismatched bytes accepted", e)
		}
	}
	postTestPublish(t, l)
	if count(t, l.cp, `SELECT count(*) FROM c_posts.posts WHERE visibility='PUBLISHED'`) != 0 {
		t.Fatal("partial post published")
	}
	state, e := l.c.ReadPostImageUploads(ctx, owner.SessionToken, accepted.TaskID, 1)
	if e != nil {
		t.Fatal(e)
	}
	items := state.Value.(postmedia.UploadState).Items
	if len(items) != 9 {
		t.Fatal("order lost")
	}
	for i, s := range items {
		if s.Position != i || s.MediaID != intent.Images[i].MediaID || s.Uploaded != (i < 7) {
			t.Fatal("per-item upload state changed")
		}
	}
	for i := 7; i < 9; i++ {
		imageUpload(t, l, accepted, intent.Images[i], tokens[i], data[i])
	}
	// Replay of a lost successful PUT is an exact-byte no-op, not another item.
	imageUpload(t, l, accepted, intent.Images[7], tokens[7], data[7])
	if replay := postTestCommand(t, l, owner.SessionToken, command, intent); replay != accepted {
		t.Fatal("receipt changed")
	}
	postTestPublish(t, l)
	groupResponse, e := l.c.ReadPostImages(ctx, foreign.SessionToken, accepted.PostID, "")
	if e != nil {
		t.Fatal(e)
	}
	group := groupResponse.Value.(postmedia.Group)
	if len(group.Images) != 9 || group.PostID != accepted.PostID {
		t.Fatal("wrong group")
	}
	for i, s := range group.Images {
		if s.Position != i || s.MediaID != intent.Images[i].MediaID || s.Full != s.Original || s.Full != s.Thumbnail || !s.SaveAllowed {
			t.Fatal("source or ordering changed")
		}
		got, e := l.c.ReadPostImages(ctx, foreign.SessionToken, accepted.PostID, s.ContentVersionID)
		if e != nil || !bytes.Equal(got.Value.(ImageBytes).Bytes, data[i]) {
			t.Fatal("original bytes changed", e)
		}
		if (i%4 == 2 || i%4 == 3) && (!s.Animated || s.Frames != 2) {
			t.Fatal("animation lost")
		}
	}
	again, e := l.c.ReadPostImages(ctx, owner.SessionToken, accepted.PostID, "")
	if e != nil || again.Value.(postmedia.Group).Images[0].ContentVersionID != group.Images[0].ContentVersionID {
		t.Fatal("unstable content version")
	}
	otherPost := uuid.NewString()
	_, e = l.c.ReadPostImages(ctx, owner.SessionToken, otherPost, group.Images[0].ContentVersionID)
	postTestError(t, e, "MEDIA_NOT_FOUND", 404)
	postTestCommand(t, l, owner.SessionToken, postTestKey(t), posts.Intent{Operation: posts.DeletePost, PostID: accepted.PostID})
	_, e = l.c.ReadPostImages(ctx, foreign.SessionToken, accepted.PostID, group.Images[0].ContentVersionID)
	postTestError(t, e, "MEDIA_NOT_FOUND", 404)
	if count(t, l.cp, `SELECT count(*) FROM c_posts.images WHERE payload IS NOT NULL OR grant_digest IS NOT NULL`) != 0 || count(t, l.cp, `SELECT count(*) FROM c_posts.images WHERE erased_at IS NOT NULL`) != 9 {
		t.Fatal("deleted private bytes retained")
	}
}

func TestPostImagesImmutableManifestAndSQLBoundaryPostgres(t *testing.T) {
	l := newPostLab(t)
	enableImageLab(t, l)
	ctx := context.Background()
	owner := sessionTestAccount(t, l, "image_immutable")
	id := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "不可改").IdentityID
	intent := postTestIntent(t, l, id)
	a, data := imageFixture(t, "png")
	b, _ := imageFixture(t, "gif")
	intent.Images = []postmedia.Selection{a, b}
	key := postTestKey(t)
	r := postTestCommand(t, l, owner.SessionToken, key, intent)
	changed := intent
	changed.Images = []postmedia.Selection{b, a}
	_, e := l.c.ExecutePostCommand(ctx, owner.SessionToken, key, changed)
	postTestError(t, e, "COMMAND_CONFLICT", 409)
	for _, statement := range []string{`UPDATE c_posts.images SET position=8 WHERE task_id=$1 AND position=0`, `UPDATE c_posts.images SET digest=decode(repeat('11',32),'hex') WHERE task_id=$1`, `DELETE FROM c_posts.images WHERE task_id=$1`, `UPDATE c_posts.attempt_contents SET image_count=0 WHERE task_id=$1`} {
		expectPostSQLRejected(t, l, statement, r.TaskID)
	}
	// Even an owner SQL writer cannot append a manifest item after acceptance.
	expectPostSQLRejected(t, l, `INSERT INTO c_posts.images(task_id,version,media_id,content_version_id,position,digest,byte_length,mime_type,width,height) SELECT task_id,version,gen_random_uuid(),gen_random_uuid(),8,digest,byte_length,mime_type,width,height FROM c_posts.images WHERE task_id=$1 LIMIT 1`, r.TaskID)
	token := imageGrant(t, l, owner.SessionToken, r, a.MediaID)
	imageUpload(t, l, r, a, token, data)
	expectPostSQLRejected(t, l, `UPDATE c_posts.images SET payload=decode('00','hex') WHERE task_id=$1 AND position=0`, r.TaskID)
	// Final publication shape rejects a hand-written attempt/post public pair.
	tx, e := l.cp.Begin(ctx)
	if e != nil {
		t.Fatal(e)
	}
	defer tx.Rollback(ctx)
	at := time.Now().UTC().Add(time.Second)
	if _, e = tx.Exec(ctx, `UPDATE c_posts.publication_attempts SET state='PUBLISHED',terminal_at=$2 WHERE task_id=$1`, r.TaskID, at); e != nil {
		t.Fatal(e)
	}
	if _, e = tx.Exec(ctx, `UPDATE c_posts.posts SET visibility='PUBLISHED',published_attempt_version=1,published_at=$2,publication_ordinal=nextval('c_posts.publication_ordinal_seq') WHERE post_id=$1`, r.PostID, at); e != nil {
		t.Fatal(e)
	}
	var pe *pgconn.PgError
	if e = tx.Commit(ctx); !errors.As(e, &pe) || pe.Code != "23514" {
		t.Fatal("incomplete byte set published through SQL", e)
	}
}

func TestPostImagesUploadCapabilitySessionReplacementAndFreezePostgres(t *testing.T) {
	l := newPostLab(t)
	enableImageLab(t, l)
	ctx := context.Background()
	owner := sessionTestAccount(t, l, "image_session")
	id := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "原身份").IdentityID
	intent := postTestIntent(t, l, id)
	s, data := imageFixture(t, "webp")
	intent.Images = []postmedia.Selection{s}
	r := postTestCommand(t, l, owner.SessionToken, postTestKey(t), intent)
	old := imageGrant(t, l, owner.SessionToken, r, s.MediaID)
	token := imageGrant(t, l, owner.SessionToken, r, s.MediaID)
	_, e := l.c.UploadPostImage(ctx, old, r.TaskID, s.MediaID, 1, data, s.MIME)
	postTestError(t, e, "MEDIA_UPLOAD_DENIED", 403)
	if _, e = l.c.CreateSession(ctx, sessionTestRequest(t, "image_session"), sessionTestPasswordWorker(t, 1)); e != nil {
		t.Fatal(e)
	}
	_, e = l.c.IssuePostImageGrant(ctx, owner.SessionToken, r.TaskID, s.MediaID, 1)
	if !errors.Is(e, ErrSessionReplaced) {
		t.Fatal("old session minted a new grant", e)
	}
	imageUpload(t, l, r, s, token, data) // accepted exact bytes survive session replacement
	if e = l.gate.Freeze(ctx, "synthetic media freeze"); e != nil {
		t.Fatal(e)
	}
	_, e = l.c.UploadPostImage(ctx, token, r.TaskID, s.MediaID, 1, data, s.MIME)
	if !errors.Is(e, ErrAuthorizationUnavailable) {
		t.Fatal("frozen Gate accepted upload", e)
	}
	if _, e = l.c.PublishAcceptedPosts(ctx, 100); !errors.Is(e, ErrAuthorizationUnavailable) {
		t.Fatal("frozen worker published", e)
	}
}

func TestPostImagesCancelMuteAndExpiredGrantPostgres(t *testing.T) {
	for _, cause := range []string{"cancel", "mute", "expiry", "identity", "ban", "closure"} {
		t.Run(cause, func(t *testing.T) {
			control := newGateControl(t)
			l := control.lab
			enablePostLab(t, l)
			enableImageLab(t, l)
			ctx := context.Background()
			owner := sessionTestAccount(t, l, "image_stop")
			id := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "停止身份").IdentityID
			intent := postTestIntent(t, l, id)
			s, data := imageFixture(t, "gif")
			pending := s
			pending.MediaID = uuid.NewString()
			intent.Images = []postmedia.Selection{s, pending}
			r := postTestCommand(t, l, owner.SessionToken, postTestKey(t), intent)
			imageUpload(t, l, r, s, imageGrant(t, l, owner.SessionToken, r, s.MediaID), data)
			token := imageGrant(t, l, owner.SessionToken, r, pending.MediaID)
			switch cause {
			case "cancel":
				postTestCommand(t, l, owner.SessionToken, postTestKey(t), posts.Intent{Operation: posts.Cancel, TaskID: r.TaskID, ExpectedAttemptVersion: 1})
			case "mute":
				if e := l.c.ApplyAccountMute(ctx, owner.AccountID, 1, nil); e != nil {
					t.Fatal(e)
				}
			case "identity":
				identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "保留身份")
				identityChange(t, l.c, owner.SessionToken, "DELETE", id, "")
			case "expiry":
				advanceClosureClock(t, control, control.clock.now().Add(16*time.Minute))
			case "ban":
				if e := l.c.ApplyAccountBan(ctx, owner.AccountID, 1, nil); e != nil {
					t.Fatal(e)
				}
			case "closure":
				request, _ := closureTestRequest(t, owner.SessionToken)
				if _, e := l.c.RequestAccountClosure(ctx, request, sessionTestPasswordWorker(t, 1)); e != nil {
					t.Fatal(e)
				}
			}
			_, e := l.c.UploadPostImage(ctx, token, r.TaskID, pending.MediaID, 1, data, s.MIME)
			if e == nil {
				t.Fatal("revoked upload succeeded")
			}
			if cause == "expiry" {
				advanceClosureClock(t, control, control.clock.now().Add(25*time.Hour))
			}
			postTestPublish(t, l)
			if count(t, l.cp, `SELECT count(*) FROM c_posts.posts WHERE visibility='PUBLISHED'`) != 0 {
				t.Fatal("stopped post published")
			}
			if count(t, l.cp, `SELECT count(*) FROM c_posts.images WHERE payload IS NOT NULL OR grant_digest IS NOT NULL`) != 0 {
				t.Fatal("terminal task retained temporary image bytes")
			}
			if cause == "expiry" {
				login, e := l.c.CreateSession(ctx, sessionTestRequest(t, "image_stop"), sessionTestPasswordWorker(t, 1))
				if e != nil {
					t.Fatal(e)
				}
				retry := posts.Intent{Operation: posts.Retry, TaskID: r.TaskID, ExpectedAttemptVersion: 1, Title: "原身份重试", Body: "", Images: []postmedia.Selection{s}}
				next := postTestCommand(t, l, login.SessionToken, postTestKey(t), retry)
				if next.PostID != r.PostID || next.TaskID != r.TaskID || next.AttemptVersion != 2 {
					t.Fatal("retry changed task/post ownership")
				}
				imageUpload(t, l, next, s, imageGrant(t, l, login.SessionToken, next, s.MediaID), data)
				postTestPublish(t, l)
				if count(t, l.cp, `SELECT count(*) FROM c_posts.publication_tasks WHERE task_id=$1 AND identity_id=$2 AND channel_id=$3`, next.TaskID, id, intent.ChannelID) != 1 {
					t.Fatal("retry reassigned identity/channel")
				}
			}
		})
	}
}

func TestPostImagesRestrictedRuntimePostgres(t *testing.T) {
	l := newPostLab(t)
	enableImageLab(t, l)
	ctx := context.Background()
	dsn := os.Getenv("AUTHLAB_POSTS_RUNTIME_DSN")
	if dsn == "" {
		t.Skip("private runtime DSN absent")
	}
	owner := sessionTestAccount(t, l, "image_role")
	id := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "受限身份").IdentityID
	mustExec(t, l.cp, `CREATE TABLE IF NOT EXISTS public.goose_db_version(version_id bigint,is_applied boolean)`)
	for _, file := range []string{"grant-community.sql", "grant-post-images.sql"} {
		source, e := os.ReadFile("../../../../infra/postgres/" + file)
		if e != nil {
			t.Fatal(e)
		}
		mustExec(t, l.cp, string(source))
	}
	runtime, e := pgxpool.New(ctx, dsn)
	if e != nil {
		t.Fatal(e)
	}
	defer runtime.Close()
	copyCommunity := *l.c
	copyCommunity.pool = runtime
	copyCommunity.postImages = nil
	l.c, e = copyCommunity.WithPostImages(ctx, imageValidator(t))
	if e != nil {
		t.Fatal(e)
	}
	intent := postTestIntent(t, l, id)
	s, data := imageFixture(t, "png")
	intent.Images = []postmedia.Selection{s}
	r := postTestCommand(t, l, owner.SessionToken, postTestKey(t), intent)
	token := imageGrant(t, l, owner.SessionToken, r, s.MediaID)
	imageUpload(t, l, r, s, token, data)
	postTestPublish(t, l)
	group, e := l.c.ReadPostImages(ctx, owner.SessionToken, r.PostID, "")
	if e != nil || len(group.Value.(postmedia.Group).Images) != 1 {
		t.Fatal("restricted role media flow failed", e)
	}
	for _, sql := range []string{`DELETE FROM c_posts.images`, `TRUNCATE c_posts.images`, `UPDATE c_posts.images SET digest=decode(repeat('22',32),'hex')`, `UPDATE c_posts.images SET position=8`} {
		_, e := runtime.Exec(ctx, sql)
		var pe *pgconn.PgError
		if !errors.As(e, &pe) || pe.Code != "42501" {
			t.Fatal("excessive runtime media privilege", e)
		}
	}
	var canRead bool
	for _, role := range []string{"hnuhole_business", "hnuhole_c_recovery"} {
		if l.cp.QueryRow(ctx, `SELECT has_table_privilege($1,'c_posts.images','SELECT')`, role).Scan(&canRead) != nil || canRead {
			t.Fatal("foreign role reads private images")
		}
	}
	postTestCommand(t, l, owner.SessionToken, postTestKey(t), posts.Intent{Operation: posts.DeletePost, PostID: r.PostID})
	if count(t, l.cp, `SELECT count(*) FROM c_posts.images WHERE payload IS NOT NULL`) != 0 {
		t.Fatal("restricted erasure failed")
	}
}

func TestPostImagesMetadataMismatchDoesNotBlockTextPostgres(t *testing.T) {
	l := newPostLab(t)
	enableImageLab(t, l)
	ctx := context.Background()
	owner := sessionTestAccount(t, l, "image_metadata")
	id := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "尺寸身份").IdentityID
	intent := postTestIntent(t, l, id)
	selection, data := imageFixture(t, "png")
	selection.Width++ // exact hash, deliberately false dimensions
	intent.Images = []postmedia.Selection{selection}
	r := postTestCommand(t, l, owner.SessionToken, postTestKey(t), intent)
	token := imageGrant(t, l, owner.SessionToken, r, selection.MediaID)
	if _, e := l.c.UploadPostImage(ctx, token, r.TaskID, selection.MediaID, 1, data, selection.MIME); !errors.Is(e, postmedia.ErrInvalid) {
		t.Fatal("client dimensions trusted", e)
	}
	text := postTestIntent(t, l, id)
	later := postTestCommand(t, l, owner.SessionToken, postTestKey(t), text)
	if _, e := l.c.PublishAcceptedPosts(ctx, 1); e != nil {
		t.Fatal(e)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_posts.posts WHERE post_id=$1 AND visibility='PUBLISHED'`, later.PostID) != 1 || count(t, l.cp, `SELECT count(*) FROM c_posts.posts WHERE post_id=$1 AND visibility='PUBLISHED'`, r.PostID) != 0 {
		t.Fatal("unready media blocked a ready text post")
	}
}

type imageValidationBarrier struct {
	postmedia.Validator
	captured, release chan struct{}
}

func (b *imageValidationBarrier) Inspect(ctx context.Context, data []byte) (postmedia.Metadata, error) {
	metadata, e := b.Validator.Inspect(ctx, data)
	if e != nil {
		return metadata, e
	}
	close(b.captured)
	select {
	case <-b.release:
		return metadata, nil
	case <-ctx.Done():
		return postmedia.Metadata{}, ctx.Err()
	}
}

func TestPostImagesFinalTransactionRacesPostgres(t *testing.T) {
	l := newPostLab(t)
	enableImageLab(t, l)
	ctx := context.Background()
	owner := sessionTestAccount(t, l, "image_race")
	id := identityChange(t, l.c, owner.SessionToken, "CREATE", uuid.Nil, "竞争身份").IdentityID
	intent := postTestIntent(t, l, id)
	selection, data := imageFixture(t, "png")
	intent.Images = []postmedia.Selection{selection}
	r := postTestCommand(t, l, owner.SessionToken, postTestKey(t), intent)
	token := imageGrant(t, l, owner.SessionToken, r, selection.MediaID)
	validation := &imageValidationBarrier{Validator: l.c.postImages.validator, captured: make(chan struct{}), release: make(chan struct{})}
	stale := *l.c
	stale.postImages = &postImageServices{validator: validation}
	done := make(chan error, 1)
	go func() {
		_, e := stale.UploadPostImage(ctx, token, r.TaskID, selection.MediaID, 1, data, selection.MIME)
		done <- e
	}()
	<-validation.captured
	postTestCommand(t, l, owner.SessionToken, postTestKey(t), posts.Intent{Operation: posts.Cancel, TaskID: r.TaskID, ExpectedAttemptVersion: 1})
	close(validation.release)
	if e := <-done; e == nil {
		t.Fatal("upload resurrected a cancelled attempt")
	}
	if count(t, l.cp, `SELECT count(*) FROM c_posts.images WHERE payload IS NOT NULL`) != 0 {
		t.Fatal("cancel race retained private bytes")
	}
	// A stale read also cannot pass the final session generation check.
	text := postTestCommand(t, l, owner.SessionToken, postTestKey(t), postTestIntent(t, l, id))
	postTestPublish(t, l)
	barrier := &identitySnapshotBarrier{AuthorizationGate: l.c.gate, captured: make(chan struct{}), release: make(chan struct{})}
	stale = *l.c
	stale.gate = barrier
	go func() { _, e := stale.ReadPostImages(ctx, owner.SessionToken, text.PostID, ""); done <- e }()
	<-barrier.captured
	if _, e := l.c.CreateSession(ctx, sessionTestRequest(t, "image_race"), sessionTestPasswordWorker(t, 1)); e != nil {
		t.Fatal(e)
	}
	close(barrier.release)
	if e := <-done; !errors.Is(e, ErrSessionReplaced) {
		t.Fatal("stale media read passed final session check", e)
	}
}
