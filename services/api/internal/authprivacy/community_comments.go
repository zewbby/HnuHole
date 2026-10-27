package authprivacy

import (
	"context"
	"crypto/hmac"
	"encoding/json"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/comments"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/commentsnapshot"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/postmedia"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
)

type CommentConfig struct {
	KeyKey, FingerprintKey [32]byte
	Snapshots              *commentsnapshot.Config
	SnapshotStore          *commentsnapshot.Store
	ObserveRead            func(CommentReadTiming)
}

// CommentReadTiming contains no account, resource, bearer or content fields.
// Observation is optional and is used separately from performance acceptance.
type CommentReadTiming struct {
	Path, Backend                                                      string
	Transaction, StoreInTransaction, SQLGateProjection, Publish, Total time.Duration
	Succeeded                                                          bool
}
type commentServices struct {
	codec                      *comments.CommandCodec
	commandTag, fingerprintTag [32]byte
	snapshotConfig             *commentsnapshot.Config
	snapshotStore              *commentsnapshot.Store
	observeRead                func(CommentReadTiming)
}

type CommentReceipt struct {
	State          string             `json:"state"`
	Operation      comments.Operation `json:"operation,omitempty"`
	TaskID         string             `json:"taskId,omitempty"`
	AttemptVersion int32              `json:"attemptVersion,omitempty"`
	ErrorCode      string             `json:"errorCode,omitempty"`
	CommentID      string             `json:"commentId,omitempty"`
	DeletedCount   *int64             `json:"deletedCount,omitempty"`
	Liked          *bool              `json:"liked,omitempty"`
	LikeCount      *int64             `json:"likeCount,omitempty"`
}
type OwnCommentTask struct {
	TaskID             string             `json:"taskId"`
	OwnerIdentityID    string             `json:"ownerIdentityId"`
	PostID             string             `json:"postId"`
	RootCommentID      *string            `json:"rootCommentId"`
	TargetCommentID    *string            `json:"targetCommentId"`
	AttemptVersion     int32              `json:"attemptVersion"`
	State              comments.TaskState `json:"state"`
	FailureCode        *string            `json:"failureCode"`
	MaterialsAvailable bool               `json:"materialsAvailable"`
	Content            *comments.Content  `json:"content"`
	AllowedActions     []string           `json:"allowedActions"`
	PublishedCommentID *string            `json:"publishedCommentId"`
}

func commentString(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}

func (c *Community) CommentsEnabled() bool { return c != nil && c.comments != nil }
func (c *Community) WithComments(ctx context.Context, cfg CommentConfig) (*Community, error) {
	if !c.PostsEnabled() || cfg.KeyKey == c.requestKey || cfg.FingerprintKey == c.requestKey {
		return nil, ErrIntentInvalid
	}
	codec, e := comments.NewCommandCodec(cfg.KeyKey[:], cfg.FingerprintKey[:])
	if e != nil {
		return nil, e
	}
	// Match against the existing purpose commitments without retaining raw keys.
	for _, key := range [][32]byte{cfg.KeyKey, cfg.FingerprintKey} {
		if hmac.Equal(c.posts.commandTag[:], tagBytes("HNUHOLE/POST-COMMAND-KEY-COMMITMENT/V1", key)) || hmac.Equal(c.posts.fingerprintTag[:], tagBytes("HNUHOLE/POST-FINGERPRINT-KEY-COMMITMENT/V1", key)) {
			return nil, ErrIntentInvalid
		}
	}
	clone := *c
	clone.comments = &commentServices{codec: codec, commandTag: postKeyCommitment("HNUHOLE/COMMENT-KEY-COMMITMENT/V1", cfg.KeyKey), fingerprintTag: postKeyCommitment("HNUHOLE/COMMENT-FINGERPRINT-COMMITMENT/V1", cfg.FingerprintKey)}
	clone.comments.observeRead = cfg.ObserveRead
	if cfg.Snapshots != nil {
		settings := *cfg.Snapshots
		if e = settings.Validate(); e != nil {
			return nil, e
		}
		if settings.ReadRedis && (cfg.SnapshotStore == nil || cfg.SnapshotStore.Config() != settings || !cfg.SnapshotStore.MatchesMAC(codec.IntentFingerprint)) {
			return nil, commentsnapshot.ErrIntegrity
		}
		clone.comments.snapshotConfig = &settings
		clone.comments.snapshotStore = cfg.SnapshotStore
	} else if cfg.SnapshotStore != nil {
		return nil, commentsnapshot.ErrIntegrity
	}
	if e = clone.CheckCommentSchema(ctx); e != nil {
		return nil, e
	}
	if e = clone.checkCommentKeys(ctx, nil); e != nil {
		if errors.Is(e, errPostProtocolIntegrity) {
			return nil, clone.freezePostProtocol(ctx)
		}
		return nil, e
	}
	return &clone, nil
}
func tagBytes(domain string, key [32]byte) []byte { t := postKeyCommitment(domain, key); return t[:] }

func (c *Community) checkCommentKeys(ctx context.Context, tx pgx.Tx) error {
	var db interface {
		QueryRow(context.Context, string, ...any) pgx.Row
	} = c.pool
	if tx != nil {
		db = tx
	}
	var k, f []byte
	e := db.QueryRow(ctx, `SELECT command_tag,fingerprint_tag FROM c_comments.protocol_keys WHERE singleton_id=1`).Scan(&k, &f)
	if e == nil {
		if !hmac.Equal(k, c.comments.commandTag[:]) || !hmac.Equal(f, c.comments.fingerprintTag[:]) {
			return errPostProtocolIntegrity
		}
		return nil
	}
	if !errors.Is(e, pgx.ErrNoRows) {
		return ErrAuthorizationUnavailable
	}
	var history bool
	if e = db.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM c_comments.receipts) OR EXISTS(SELECT 1 FROM c_comments.tasks)`).Scan(&history); e != nil {
		return ErrAuthorizationUnavailable
	}
	if history {
		return errPostProtocolIntegrity
	}
	if tx == nil {
		return nil
	}
	// Different accounts may race the first use. Re-read after the unique insert.
	if _, e = tx.Exec(ctx, `INSERT INTO c_comments.protocol_keys VALUES(1,$1,$2) ON CONFLICT DO NOTHING`, c.comments.commandTag[:], c.comments.fingerprintTag[:]); e != nil {
		return e
	}
	return c.checkCommentKeys(ctx, tx)
}
func (c *Community) withCommentSession(ctx context.Context, bearer [32]byte, action func(pgx.Tx, uuid.UUID, AuthorizationDecision, restriction) (any, error)) (PostResponse, error) {
	if !c.CommentsEnabled() {
		return PostResponse{}, ErrAuthorizationUnavailable
	}
	return c.withPostSession(ctx, bearer, func(tx pgx.Tx, a uuid.UUID, d AuthorizationDecision, m restriction) (any, error) {
		if e := c.checkCommentKeys(ctx, tx); e != nil {
			return nil, e
		}
		return action(tx, a, d, m)
	})
}
func readCommentReceipt(ctx context.Context, tx pgx.Tx, key [32]byte) (CommentReceipt, []byte, bool, error) {
	var r CommentReceipt
	var f []byte
	var task, code, comment *string
	var version *int32
	e := tx.QueryRow(ctx, `SELECT outcome,operation,task_id::text,version,error_code,intent_fingerprint,comment_id::text,deleted_count,liked,like_count FROM c_comments.receipts WHERE key_digest=$1`, key[:]).Scan(&r.State, &r.Operation, &task, &version, &code, &f, &comment, &r.DeletedCount, &r.Liked, &r.LikeCount)
	if errors.Is(e, pgx.ErrNoRows) {
		return r, nil, false, nil
	}
	if e != nil {
		return r, nil, false, e
	}
	if task != nil {
		r.TaskID = *task
	}
	if version != nil {
		r.AttemptVersion = *version
	}
	if code != nil {
		r.ErrorCode = *code
	}
	if comment != nil {
		r.CommentID = *comment
	}
	return r, f, true, nil
}
func writeCommentReceipt(ctx context.Context, tx pgx.Tx, account uuid.UUID, key, fp [32]byte, r CommentReceipt, at time.Time) error {
	var version any
	if r.AttemptVersion > 0 {
		version = r.AttemptVersion
	}
	_, e := tx.Exec(ctx, `INSERT INTO c_comments.receipts(key_digest,owner_account_id,intent_fingerprint,operation,outcome,task_id,version,error_code,committed_at,comment_id,deleted_count,liked,like_count) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)`, key[:], account, fp[:], r.Operation, r.State, nullablePostID(r.TaskID), version, nullablePostID(r.ErrorCode), at, nullablePostID(r.CommentID), r.DeletedCount, r.Liked, r.LikeCount)
	if e == nil {
		e = completeRateAdmission(ctx, tx)
	}
	return e
}
func (c *Community) GetCommentCommand(ctx context.Context, b [32]byte, key string) (PostResponse, error) {
	if _, e := comments.ParseCommandKey(key); e != nil {
		return PostResponse{}, e
	}
	return c.withCommentSession(ctx, b, func(tx pgx.Tx, a uuid.UUID, d AuthorizationDecision, _ restriction) (any, error) {
		digest, _ := c.comments.codec.KeyDigest(a.String(), key)
		if e := c.resolveExpiredAdmission(ctx, tx, a, "comment", digest, d.TrustedAt); e != nil {
			return nil, e
		}
		r, _, ok, e := readCommentReceipt(ctx, tx, digest)
		if !ok && e == nil {
			r.State = "UNKNOWN_NOT_OBSERVED"
		}
		return r, e
	})
}
func (c *Community) SealCommentCommand(ctx context.Context, b [32]byte, key string, op comments.Operation, digest [32]byte) (PostResponse, error) {
	if _, e := comments.ParseCommandKey(key); e != nil || !textCommentOperation(op) {
		return PostResponse{}, comments.ErrInvalid
	}
	return c.withCommentSession(ctx, b, func(tx pgx.Tx, a uuid.UUID, d AuthorizationDecision, _ restriction) (any, error) {
		k, _ := c.comments.codec.KeyDigest(a.String(), key)
		fp := c.comments.codec.IntentFingerprint(digest)
		r, f, found, e := readCommentReceipt(ctx, tx, k)
		if e != nil {
			return nil, e
		}
		if found {
			if !hmac.Equal(f, fp[:]) || r.Operation != op {
				return nil, postError("COMMAND_CONFLICT", 409)
			}
			return r, nil
		}
		if e = commentBudget(ctx, tx, a, d.TrustedAt); e != nil {
			return nil, e
		}
		r = CommentReceipt{State: "NOT_ACCEPTED", Operation: op, ErrorCode: "SEALED"}
		return r, writeCommentReceipt(ctx, tx, a, k, fp, r, d.TrustedAt)
	})
}
func textCommentOperation(op comments.Operation) bool {
	return op.Valid()
}
func commentBudget(ctx context.Context, tx pgx.Tx, a uuid.UUID, at time.Time) error {
	var n int
	if e := tx.QueryRow(ctx, `SELECT count(*) FROM c_comments.receipts WHERE owner_account_id=$1 AND committed_at>$2`, a, at.Add(-time.Minute)).Scan(&n); e != nil {
		return e
	}
	if n >= 120 {
		return &PostError{Code: "RATE_LIMITED", Status: 429, RetryAfter: 60}
	}
	return nil
}
func (c *Community) executeCommentCommandOnce(ctx context.Context, b [32]byte, key string, in comments.Intent) (PostResponse, error) {
	if _, e := comments.ParseCommandKey(key); e != nil || !textCommentOperation(in.Operation) {
		return PostResponse{}, comments.ErrInvalid
	}
	digest, e := comments.RequestDigest(in)
	if e != nil {
		return PostResponse{}, e
	}
	return c.withCommentSession(ctx, b, func(tx pgx.Tx, a uuid.UUID, d AuthorizationDecision, m restriction) (any, error) {
		k, _ := c.comments.codec.KeyDigest(a.String(), key)
		fp := c.comments.codec.IntentFingerprint(digest)
		r, f, found, e := readCommentReceipt(ctx, tx, k)
		if e != nil {
			return nil, e
		}
		if found {
			if !hmac.Equal(f, fp[:]) || r.Operation != in.Operation {
				return nil, postError("COMMAND_CONFLICT", 409)
			}
			return r, nil
		}
		if e = requireRateAdmission(ctx, tx, a, d.TrustedAt); e != nil {
			return nil, e
		}
		if e = commentBudget(ctx, tx, a, d.TrustedAt); e != nil {
			return nil, e
		}
		// Only business rejection is durable. Infrastructure errors roll back both
		// binding and receipt; the caller must reconcile an unknown response.
		r, e = c.applyCommentIntent(ctx, tx, a, in, d.TrustedAt, mutedAt(m, d.TrustedAt))
		var business *PostError
		if e != nil && !errors.As(e, &business) {
			return nil, e
		}
		if business != nil {
			r = CommentReceipt{State: "REJECTED", Operation: in.Operation, ErrorCode: commentRejectionCode(business.Code)}
		}
		if e = writeCommentReceipt(ctx, tx, a, k, fp, r, d.TrustedAt); e != nil {
			return nil, e
		}
		if business != nil {
			return r, errPostRejectionRecorded
		}
		return r, nil
	})
}

// Keep the frozen public contract's rejection vocabulary. Detailed current
// context belongs in the owner task/capabilities, never a new receipt dialect.
func commentRejectionCode(code string) string {
	switch code {
	case "COMMENT_CONTENT_INVALID":
		return "INVALID_CONTENT"
	case "IDENTITY_INACTIVE", "POST_IDENTITY_BOUND":
		return "IDENTITY_UNAVAILABLE"
	case "POST_UNAVAILABLE", "COMMENT_TARGET_DELETED":
		return "TARGET_UNAVAILABLE"
	case "TASK_VERSION_CONFLICT":
		return "STALE_ATTEMPT"
	case "TASK_NOT_ACTIONABLE", "TASK_ID_CONFLICT":
		return "TASK_NOT_FAILED"
	default:
		return "PERMISSION_DENIED"
	}
}
func (c *Community) applyCommentIntent(ctx context.Context, tx pgx.Tx, a uuid.UUID, in comments.Intent, at time.Time, muted bool) (CommentReceipt, error) {
	if in.Operation == comments.DeleteComment || in.Operation == comments.SetLike {
		return c.applyCommentMutation(ctx, tx, a, in, at)
	}
	reject := func(code string) (CommentReceipt, error) { return CommentReceipt{}, postError(code, 409) }
	var model comments.Task
	var e error
	content := comments.Content{Body: in.Body, Image: in.Image}
	if in.Image != nil && !c.PostImagesEnabled() {
		return reject("COMMENT_CONTENT_INVALID")
	}
	if in.Operation != comments.Abandon && content.Validate() != nil {
		return reject("COMMENT_CONTENT_INVALID")
	}
	if in.Operation == comments.Create {
		var exists bool
		if e = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM c_comments.tasks WHERE task_id=$1)`, in.TaskID).Scan(&exists); e != nil {
			return CommentReceipt{}, e
		}
		if exists {
			return reject("TASK_ID_CONFLICT")
		}
		model, e = comments.Accept(comments.AcceptInput{TaskID: in.TaskID, CommentID: uuid.NewString(), Binding: comments.Binding{PostID: in.PostID, IdentityID: in.IdentityID, RootCommentID: in.RootCommentID, TargetCommentID: in.TargetCommentID}, Content: content, AcceptedAt: at})
		if e != nil {
			return reject("COMMENT_CONTENT_INVALID")
		}
	} else {
		model, e = loadCommentTask(ctx, tx, a, in.TaskID)
		if e != nil {
			return CommentReceipt{}, e
		}
		if in.Operation == comments.Abandon {
			model, e = model.Abandon(in.ExpectedAttemptVersion, at)
		} else {
			model, e = model.Retry(in.ExpectedAttemptVersion, content, at)
		}
		if e != nil {
			if errors.Is(e, comments.ErrVersion) {
				return reject("TASK_VERSION_CONFLICT")
			}
			return reject("TASK_NOT_ACTIONABLE")
		}
	}
	v := model.View()
	if in.Operation == comments.Abandon {
		if _, e = tx.Exec(ctx, `UPDATE c_comments.tasks SET abandoned_at=$2,owner_visible=false WHERE task_id=$1`, v.TaskID, at); e != nil {
			return CommentReceipt{}, e
		}
		if _, e = tx.Exec(ctx, `UPDATE c_comments.attempts SET body=NULL WHERE task_id=$1 AND state<>'PUBLISHED'`, v.TaskID); e != nil {
			return CommentReceipt{}, e
		}
		return CommentReceipt{State: "APPLIED", Operation: in.Operation, TaskID: v.TaskID, AttemptVersion: v.AttemptVersion}, nil
	}
	var accountState string
	if e = tx.QueryRow(ctx, `SELECT state FROM c_auth.accounts WHERE account_id=$1`, a).Scan(&accountState); e != nil {
		return CommentReceipt{}, e
	}
	if accountState != "ACTIVE" {
		return reject("ACCOUNT_CLOSING")
	}
	if muted {
		return reject("POSTING_RESTRICTED")
	}
	if e = checkCommentContext(ctx, tx, a, v.Binding); e != nil {
		return CommentReceipt{}, e
	}
	var bound string
	e = tx.QueryRow(ctx, `SELECT identity_id::text FROM c_posts.post_identity_bindings WHERE account_id=$1 AND post_id=$2`, a, v.Binding.PostID).Scan(&bound)
	var existing *comments.ThreadIdentityBinding
	if e == nil {
		existing = &comments.ThreadIdentityBinding{PostID: v.Binding.PostID, IdentityID: bound}
	} else if !errors.Is(e, pgx.ErrNoRows) {
		return CommentReceipt{}, e
	}
	_, insert, e := comments.AcceptanceBinding(v.Binding.PostID, v.Binding.IdentityID, existing)
	if e != nil {
		return reject("POST_IDENTITY_BOUND")
	}
	var live int
	if e = tx.QueryRow(ctx, `SELECT count(*) FROM c_comments.tasks t JOIN c_comments.attempts x USING(task_id) WHERE t.owner_account_id=$1 AND t.owner_visible AND x.version=(SELECT max(version) FROM c_comments.attempts WHERE task_id=t.task_id) AND x.state IN ('ACCEPTED','FAILED')`, a).Scan(&live); e != nil {
		return CommentReceipt{}, e
	}
	if in.Operation == comments.Create && live >= 128 {
		return reject("TASK_LIMIT_REACHED")
	}
	// All checks above precede the first business write.
	if insert {
		if _, e = tx.Exec(ctx, `INSERT INTO c_posts.post_identity_bindings(account_id,post_id,identity_id,bound_at) VALUES($1,$2,$3,$4)`, a, v.Binding.PostID, v.Binding.IdentityID, at); e != nil {
			return CommentReceipt{}, e
		}
	}
	if in.Operation == comments.Create {
		_, e = tx.Exec(ctx, `INSERT INTO c_comments.tasks(task_id,comment_id,owner_account_id,post_id,identity_id,root_comment_id,target_comment_id) VALUES($1,$2,$3,$4,$5,$6,$7)`, v.TaskID, v.CommentID, a, v.Binding.PostID, v.Binding.IdentityID, nullablePostID(v.Binding.RootCommentID), nullablePostID(v.Binding.TargetCommentID))
		if e != nil {
			return CommentReceipt{}, e
		}
	}
	var image any
	if in.Image != nil {
		data, _ := json.Marshal(in.Image)
		image = data
	}
	_, e = tx.Exec(ctx, `INSERT INTO c_comments.attempts(task_id,version,state,accepted_at,accepted_stop_generation,body,image) SELECT $1,$2,'ACCEPTED',$3,stop_generation,$4,$6 FROM c_posts.account_publication_control WHERE account_id=$5`, v.TaskID, v.AttemptVersion, at, in.Body, a, image)
	if e == nil && in.Image != nil {
		_, e = tx.Exec(ctx, `INSERT INTO c_comments.images(task_id,version,content_version_id) VALUES($1,$2,$3)`, v.TaskID, v.AttemptVersion, uuid.New())
	}
	return CommentReceipt{State: "ACCEPTED", Operation: in.Operation, TaskID: v.TaskID, AttemptVersion: v.AttemptVersion}, e
}

// Account lock is already held. Lock the post next, serializing deletion and
// publication without taking another author's account lock.
func checkCommentContext(ctx context.Context, tx pgx.Tx, account uuid.UUID, b comments.Binding) error {
	var visibility string
	e := tx.QueryRow(ctx, `SELECT CASE WHEN moderation_hidden THEN 'HIDDEN' ELSE visibility END FROM c_posts.posts WHERE post_id=$1 FOR UPDATE`, b.PostID).Scan(&visibility)
	if errors.Is(e, pgx.ErrNoRows) || e == nil && visibility != "PUBLISHED" {
		return postError("POST_UNAVAILABLE", 409)
	}
	if e != nil {
		return e
	}
	var active bool
	if e = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM public.community_identities WHERE account_id=$1 AND identity_id=$2 AND deleted_at IS NULL)`, account, b.IdentityID).Scan(&active); e != nil {
		return e
	}
	if !active {
		return postError("IDENTITY_INACTIVE", 409)
	}
	if b.RootCommentID != "" {
		var valid bool
		e = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM c_comments.tasks r JOIN c_comments.attempts ra ON ra.task_id=r.task_id AND ra.state='PUBLISHED' JOIN c_comments.tasks t ON t.comment_id=$3 JOIN c_comments.attempts ta ON ta.task_id=t.task_id AND ta.state='PUBLISHED' WHERE r.comment_id=$2 AND r.post_id=$1 AND r.root_comment_id IS NULL AND t.post_id=r.post_id AND COALESCE(t.root_comment_id,t.comment_id)=r.comment_id AND r.deleted_at IS NULL AND t.deleted_at IS NULL AND NOT COALESCE((to_jsonb(r)->>'moderation_hidden')::boolean,false) AND NOT COALESCE((to_jsonb(t)->>'moderation_hidden')::boolean,false))`, b.PostID, b.RootCommentID, b.TargetCommentID).Scan(&valid)
		if e != nil {
			return e
		}
		if !valid {
			return postError("COMMENT_TARGET_DELETED", 409)
		}
	}
	return nil
}
func loadCommentTask(ctx context.Context, tx pgx.Tx, account uuid.UUID, id string) (comments.Task, error) {
	var r comments.Record
	var root, target, body *string
	var terminal, abandoned, deleted *time.Time
	var failure *string
	var accountState string
	var image []byte
	e := tx.QueryRow(ctx, `SELECT t.task_id::text,t.comment_id::text,t.post_id::text,t.identity_id::text,t.root_comment_id::text,t.target_comment_id::text,t.owner_visible,t.abandoned_at,i.deleted_at,ac.state,x.version,x.state,x.accepted_at,x.terminal_at,x.failure_code,x.body,x.image
 FROM c_comments.tasks t JOIN c_comments.attempts x ON x.task_id=t.task_id AND x.version=(SELECT max(version) FROM c_comments.attempts WHERE task_id=t.task_id)
 JOIN public.community_identities i ON i.identity_id=t.identity_id JOIN c_auth.accounts ac ON ac.account_id=t.owner_account_id WHERE t.task_id=$1 AND t.owner_account_id=$2`, id, account).Scan(&r.TaskID, &r.CommentID, &r.Binding.PostID, &r.Binding.IdentityID, &root, &target, &r.OwnerVisible, &abandoned, &deleted, &accountState, &r.Version, &r.State, &r.AcceptedAt, &terminal, &failure, &body, &image)
	if errors.Is(e, pgx.ErrNoRows) {
		return comments.Task{}, postError("TASK_NOT_FOUND", 404)
	}
	if e != nil {
		return comments.Task{}, e
	}
	if root != nil {
		r.Binding.RootCommentID = *root
	}
	if target != nil {
		r.Binding.TargetCommentID = *target
	}
	if terminal != nil {
		r.TerminalAt = *terminal
	}
	if failure != nil {
		r.Failure = comments.FailureCode(*failure)
	}
	if body != nil {
		r.Content = &comments.Content{Body: *body}
		if len(image) > 0 {
			var selection postmedia.Selection
			if json.Unmarshal(image, &selection) != nil {
				return comments.Task{}, ErrAuthorizationUnavailable
			}
			r.Content.Image = &selection
		}
	}
	r.IdentityActive = deleted == nil && accountState != "CLOSED"
	if abandoned != nil {
		r.State = comments.Abandoned
		r.TerminalAt = *abandoned
	}
	return comments.Restore(r)
}
func (c *Community) GetOwnCommentTask(ctx context.Context, b [32]byte, id string) (PostResponse, error) {
	if _, e := posts.ParseResourceID(id); e != nil {
		return PostResponse{}, e
	}
	return c.withCommentSession(ctx, b, func(tx pgx.Tx, a uuid.UUID, d AuthorizationDecision, m restriction) (any, error) {
		t, e := loadCommentTask(ctx, tx, a, id)
		if e != nil {
			return nil, e
		}
		v := t.View()
		if !v.OwnerVisible && v.State != comments.Abandoned {
			return nil, postError("TASK_NOT_FOUND", 404)
		}
		r := OwnCommentTask{TaskID: v.TaskID, OwnerIdentityID: v.Binding.IdentityID, PostID: v.Binding.PostID, RootCommentID: commentString(v.Binding.RootCommentID), TargetCommentID: commentString(v.Binding.TargetCommentID), AttemptVersion: v.AttemptVersion, State: v.State, FailureCode: commentString(string(v.FailureCode)), MaterialsAvailable: v.Content != nil, Content: v.Content, AllowedActions: []string{}}
		if v.CanAbandon {
			r.AllowedActions = append(r.AllowedActions, "ABANDON")
		}
		if v.CanRetry && !mutedAt(m, d.TrustedAt) {
			var state string
			if e = tx.QueryRow(ctx, `SELECT state FROM c_auth.accounts WHERE account_id=$1`, a).Scan(&state); e != nil {
				return nil, e
			}
			if state == "ACTIVE" {
				e = checkCommentContext(ctx, tx, a, v.Binding)
				var business *PostError
				if e == nil {
					r.AllowedActions = append([]string{"RETRY"}, r.AllowedActions...)
				} else if !errors.As(e, &business) {
					return nil, e
				}
			}
		}
		if v.State == comments.Published {
			r.PublishedCommentID = commentString(v.CommentID)
		}
		if v.State == comments.Abandoned {
			r.FailureCode = nil
		}
		return r, nil
	})
}
