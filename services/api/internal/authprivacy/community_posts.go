package authprivacy

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"errors"
	"math"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
)

// PostConfig 的三份用途密钥独立于认证材料；只在启动时装配。
type PostConfig struct {
	Environment                       string
	KeyKey, FingerprintKey, CursorKey [32]byte
}
type postServices struct {
	commands                   *posts.CommandCodec
	cursors                    *posts.CursorCodec
	commandTag, fingerprintTag [32]byte
}
type PostResponse struct {
	Value                 any
	ExpiresAt, ServerTime time.Time
}
type PostError struct {
	Code               string
	Status, RetryAfter int
}

func (e *PostError) Error() string            { return "post request rejected" }
func postError(code string, status int) error { return &PostError{Code: code, Status: status} }

var errPostRejectionRecorded = errors.New("post rejection recorded")
var errPostProtocolIntegrity = errors.New("post protocol key integrity unavailable")

func (c *Community) WithPosts(ctx context.Context, config PostConfig) (*Community, error) {
	if c == nil || config.KeyKey == c.requestKey || config.FingerprintKey == c.requestKey || config.CursorKey == c.requestKey || config.CursorKey == config.KeyKey || config.CursorKey == config.FingerprintKey {
		return nil, ErrIntentInvalid
	}
	commands, err := posts.NewCommandCodec(config.KeyKey[:], config.FingerprintKey[:])
	if err != nil {
		return nil, err
	}
	cursors, err := posts.NewCursorCodec(config.CursorKey[:], config.Environment)
	if err != nil {
		return nil, err
	}
	if err = c.CheckPostSchema(ctx); err != nil {
		return nil, err
	}
	clone := *c
	clone.posts = &postServices{commands: commands, cursors: cursors}
	clone.posts.commandTag = postKeyCommitment("HNUHOLE/POST-COMMAND-KEY-COMMITMENT/V1", config.KeyKey)
	clone.posts.fingerprintTag = postKeyCommitment("HNUHOLE/POST-FINGERPRINT-KEY-COMMITMENT/V1", config.FingerprintKey)
	if err = clone.checkPostProtocolKeys(ctx, nil); err != nil {
		if errors.Is(err, errPostProtocolIntegrity) {
			return nil, clone.freezePostProtocol(ctx)
		}
		return nil, err
	}
	return &clone, nil
}
func (c *Community) PostsEnabled() bool { return c != nil && c.posts != nil }

func postKeyCommitment(domain string, key [32]byte) [32]byte {
	mac := hmac.New(sha256.New, key[:])
	_, _ = mac.Write([]byte(domain))
	var tag [32]byte
	copy(tag[:], mac.Sum(nil))
	return tag
}
func (c *Community) freezePostProtocol(ctx context.Context) error {
	if gate, ok := c.gate.(interface {
		Freeze(context.Context, string) error
	}); ok {
		_ = gate.Freeze(ctx, "post protocol key integrity unavailable")
	}
	return ErrAuthorizationUnavailable
}

// 启动只校验材料；全新空库可在FROZEN启动。首次合法访问在最终Gate事务
// 固定两份永久密钥承诺，之后每次最终事务重新核对。丢失历史承诺只能冻结。
func (c *Community) checkPostProtocolKeys(ctx context.Context, tx pgx.Tx) error {
	var db interface {
		QueryRow(context.Context, string, ...any) pgx.Row
	} = c.pool
	if tx != nil {
		db = tx
	}
	var storedCommand, storedFingerprint []byte
	err := db.QueryRow(ctx, `SELECT command_tag,fingerprint_tag FROM c_posts.protocol_keys WHERE singleton_id=1`).Scan(&storedCommand, &storedFingerprint)
	if err == nil {
		if !hmac.Equal(storedCommand, c.posts.commandTag[:]) || !hmac.Equal(storedFingerprint, c.posts.fingerprintTag[:]) {
			return errPostProtocolIntegrity
		}
		return nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return ErrAuthorizationUnavailable
	}
	var historical bool
	if err = db.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM c_posts.command_receipts) OR EXISTS(SELECT 1 FROM c_posts.posts)`).Scan(&historical); err != nil {
		return ErrAuthorizationUnavailable
	}
	if historical {
		return errPostProtocolIntegrity
	}
	if tx == nil {
		return nil
	}
	_, err = tx.Exec(ctx, `INSERT INTO c_posts.protocol_keys(singleton_id,version,command_tag,fingerprint_tag) VALUES(1,1,$1,$2)`, c.posts.commandTag[:], c.posts.fingerprintTag[:])
	return err
}

// 调用者账号先锁；同账号写入均串行。所有正文读取及业务效果在最终 Gate 内。
// 不对其他作者行加锁，不通过第二连接池提交已授权业务。
func (c *Community) withPostSession(ctx context.Context, bearer [32]byte, action func(pgx.Tx, uuid.UUID, AuthorizationDecision, restriction) (any, error)) (PostResponse, error) {
	var result PostResponse
	if !c.PostsEnabled() {
		return result, ErrAuthorizationUnavailable
	}
	decision, err := c.gate.Snapshot(ctx)
	if err != nil {
		return result, err
	}
	token := sha256.Sum256(bearer[:])
	var account uuid.UUID
	err = c.pool.QueryRow(ctx, `SELECT account_id FROM c_auth.sessions WHERE token_digest=$1`, token[:]).Scan(&account)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return result, ErrAuthorizationUnavailable
	}
	tx, err := begin(ctx, c.pool)
	if err != nil {
		return result, ErrAuthorizationUnavailable
	}
	defer c.gate.Abort(ctx, tx)
	a := credentialAccount{account: account}
	var session credentialSession
	var mute restriction
	if account != uuid.Nil {
		if err = tx.QueryRow(ctx, `SELECT state,session_generation FROM c_auth.accounts WHERE account_id=$1 FOR UPDATE`, account).Scan(&a.state, &a.generation); err != nil {
			return result, ErrAuthorizationUnavailable
		}
		if a.ban, err = lockRestriction(ctx, tx, account); err != nil {
			return result, ErrAuthorizationUnavailable
		}
		if err = tx.QueryRow(ctx, `SELECT mute_state,mute_ends_at FROM c_auth.account_restrictions WHERE account_id=$1`, account).Scan(&mute.state, &mute.ends); err != nil {
			return result, ErrAuthorizationUnavailable
		}
		session, err = lockCredentialSession(ctx, tx, a, token)
		if err != nil && !errors.Is(err, ErrSessionInvalid) {
			return result, ErrAuthorizationUnavailable
		}
	}
	_, err = c.gate.CommitAuthorized(ctx, tx, decision.Generation, func(final AuthorizationDecision) error {
		if account == uuid.Nil {
			return ErrSessionInvalid
		}
		if e := session.validate(a, final); e != nil {
			return e
		}
		if e := c.checkPostProtocolKeys(ctx, tx); e != nil {
			return e
		}
		result.ServerTime = final.TrustedAt.UTC()
		value, e := action(tx, account, final, mute)
		result.Value = value
		if errors.Is(e, errPostRejectionRecorded) {
			result.ExpiresAt = session.expires.UTC()
			return nil
		}
		if e != nil {
			return e
		}
		result.ExpiresAt, e = session.renew(ctx, tx, final.TrustedAt)
		return e
	})
	if err != nil {
		if errors.Is(err, errPostProtocolIntegrity) {
			_ = c.gate.Abort(ctx, tx)
			return PostResponse{}, c.freezePostProtocol(ctx)
		}
		return PostResponse{}, err
	}
	result.ExpiresAt = result.ExpiresAt.UTC()
	return result, nil
}
func mutedAt(r restriction, at time.Time) bool {
	return r.state == "MUTED" && (r.ends == nil || at.Before(*r.ends))
}

func readPostReceipt(ctx context.Context, tx pgx.Tx, key [32]byte) (posts.CommandResult, []byte, bool, error) {
	var r posts.CommandResult
	var fingerprint []byte
	var task, post *uuid.UUID
	var version *int32
	var state, code *string
	err := tx.QueryRow(ctx, `SELECT outcome,operation,task_id,post_id,attempt_version,task_state,error_code,intent_fingerprint FROM c_posts.command_receipts WHERE key_digest=$1`, key[:]).Scan(&r.State, &r.Operation, &task, &post, &version, &state, &code, &fingerprint)
	if errors.Is(err, pgx.ErrNoRows) {
		return r, nil, false, nil
	}
	if err != nil {
		return r, nil, false, ErrAuthorizationUnavailable
	}
	if task != nil {
		r.TaskID = task.String()
	}
	if post != nil {
		r.PostID = post.String()
	}
	if version != nil {
		r.AttemptVersion = *version
	}
	if state != nil {
		r.TaskState = posts.TaskState(*state)
	}
	if code != nil {
		r.ErrorCode = *code
	}
	if r.State == "NOT_ACCEPTED" {
		r.Reason = r.ErrorCode
		r.ErrorCode = ""
	}
	return r, fingerprint, true, nil
}
func nullablePostID(id string) any {
	if id == "" {
		return nil
	}
	return id
}
func writePostReceipt(ctx context.Context, tx pgx.Tx, account uuid.UUID, key, fingerprint [32]byte, r posts.CommandResult, at time.Time) error {
	var version any
	if r.AttemptVersion > 0 {
		version = r.AttemptVersion
	}
	var taskState, errorCode any
	if r.State == "ACCEPTED" {
		taskState = string(posts.Accepted)
	} else if r.TaskState != "" {
		taskState = string(r.TaskState)
	}
	if r.ErrorCode != "" {
		errorCode = r.ErrorCode
	}
	if r.Reason != "" {
		errorCode = r.Reason
	}
	_, err := tx.Exec(ctx, `INSERT INTO c_posts.command_receipts(key_digest,owner_account_id,operation,intent_fingerprint,outcome,task_id,post_id,attempt_version,task_state,error_code,committed_at) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)`, key[:], account, string(r.Operation), fingerprint[:], r.State, nullablePostID(r.TaskID), nullablePostID(r.PostID), version, taskState, errorCode, at)
	return err
}
func postReceiptReplay(r posts.CommandResult, fingerprint []byte, expected [32]byte) error {
	if !hmac.Equal(fingerprint, expected[:]) {
		return postError("COMMAND_CONFLICT", 409)
	}
	if r.State == "NOT_ACCEPTED" {
		return postError("COMMAND_SEALED", 409)
	}
	if r.State == "RESULT_EXPIRED" {
		return postError("RESULT_EXPIRED", 409)
	}
	return nil
}
func postCommandBudget(ctx context.Context, tx pgx.Tx, account uuid.UUID, at time.Time) error {
	var count int
	if err := tx.QueryRow(ctx, `SELECT count(*) FROM c_posts.command_receipts WHERE owner_account_id=$1 AND committed_at>$2`, account, at.Add(-time.Minute)).Scan(&count); err != nil {
		return ErrAuthorizationUnavailable
	}
	if count >= 120 {
		return &PostError{Code: "RATE_LIMITED", Status: 429, RetryAfter: 60}
	}
	return nil
}
func postLiveBudget(ctx context.Context, tx pgx.Tx, account uuid.UUID) error {
	var count int
	err := tx.QueryRow(ctx, `SELECT count(*) FROM c_posts.publication_tasks t JOIN c_posts.publication_attempts a ON a.task_id=t.task_id AND a.version=t.latest_attempt_version WHERE t.owner_account_id=$1 AND t.owner_visible AND a.state IN ('ACCEPTED','FAILED')`, account).Scan(&count)
	if err != nil {
		return ErrAuthorizationUnavailable
	}
	if count >= 128 {
		return &PostError{Code: "RATE_LIMITED", Status: 429, RetryAfter: 60}
	}
	return nil
}
func (c *Community) GetPostCommand(ctx context.Context, bearer [32]byte, command string) (PostResponse, error) {
	if _, err := posts.ParseCommandKey(command); err != nil {
		return PostResponse{}, err
	}
	return c.withPostSession(ctx, bearer, func(tx pgx.Tx, account uuid.UUID, _ AuthorizationDecision, _ restriction) (any, error) {
		key, e := c.posts.commands.KeyDigest(account.String(), command)
		if e != nil {
			return nil, e
		}
		r, _, found, e := readPostReceipt(ctx, tx, key)
		if e != nil {
			return nil, e
		}
		if !found {
			r = posts.CommandResult{State: "UNKNOWN_NOT_OBSERVED"}
		}
		return r, nil
	})
}
func (c *Community) SealPostCommand(ctx context.Context, bearer [32]byte, command string, input posts.SealInput) (PostResponse, error) {
	if _, err := posts.ParseCommandKey(command); err != nil {
		return PostResponse{}, err
	}
	if !input.Operation.Valid() {
		return PostResponse{}, posts.ErrInvalidIntent
	}
	digest, err := posts.ParseRequestDigest(input.RequestDigest)
	if err != nil {
		return PostResponse{}, err
	}
	return c.withPostSession(ctx, bearer, func(tx pgx.Tx, account uuid.UUID, final AuthorizationDecision, _ restriction) (any, error) {
		key, e := c.posts.commands.KeyDigest(account.String(), command)
		if e != nil {
			return nil, e
		}
		fp := c.posts.commands.IntentFingerprint(digest)
		r, stored, found, e := readPostReceipt(ctx, tx, key)
		if e != nil {
			return nil, e
		}
		if found {
			if !hmac.Equal(stored, fp[:]) || r.Operation != input.Operation {
				return nil, postError("COMMAND_CONFLICT", 409)
			}
			return r, nil
		}
		if e = postCommandBudget(ctx, tx, account, final.TrustedAt); e != nil {
			return nil, e
		}
		r = posts.CommandResult{State: "NOT_ACCEPTED", Operation: input.Operation, Reason: "COMMAND_SEALED"}
		return r, writePostReceipt(ctx, tx, account, key, fp, r, final.TrustedAt)
	})
}
func (c *Community) ExecutePostCommand(ctx context.Context, bearer [32]byte, command string, intent posts.Intent) (PostResponse, error) {
	if _, err := posts.ParseCommandKey(command); err != nil {
		return PostResponse{}, err
	}
	digest, err := posts.RequestDigest(intent)
	if err != nil {
		return PostResponse{}, err
	}
	return c.withPostSession(ctx, bearer, func(tx pgx.Tx, account uuid.UUID, final AuthorizationDecision, mute restriction) (any, error) {
		key, e := c.posts.commands.KeyDigest(account.String(), command)
		if e != nil {
			return nil, e
		}
		fp := c.posts.commands.IntentFingerprint(digest)
		r, stored, found, e := readPostReceipt(ctx, tx, key)
		if e != nil {
			return nil, e
		}
		if found {
			if e = postReceiptReplay(r, stored, fp); e != nil {
				return nil, e
			}
			if r.State == "REJECTED" {
				return r, errPostRejectionRecorded
			}
			return r, nil
		}
		if e = postCommandBudget(ctx, tx, account, final.TrustedAt); e != nil {
			return nil, e
		}
		reject := func(code string) (any, error) {
			r = posts.CommandResult{State: "REJECTED", Operation: intent.Operation, ErrorCode: code}
			if e = writePostReceipt(ctx, tx, account, key, fp, r, final.TrustedAt); e != nil {
				return nil, e
			}
			return r, errPostRejectionRecorded
		}
		if e = materializePostStops(ctx, tx, account); e != nil {
			return nil, e
		}
		var generation int64
		if e = tx.QueryRow(ctx, `SELECT stop_generation FROM c_posts.account_publication_control WHERE account_id=$1`, account).Scan(&generation); e != nil {
			return nil, e
		}
		switch intent.Operation {
		case posts.Create:
			if mutedAt(mute, final.TrustedAt) {
				return reject("POSTING_RESTRICTED")
			}
			if posts.ValidateContent(intent.Title, intent.Body) != nil {
				return reject("POST_CONTENT_INVALID")
			}
			var active bool
			if e = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM public.community_identities WHERE account_id=$1 AND identity_id=$2 AND deleted_at IS NULL)`, account, intent.IdentityID).Scan(&active); e != nil {
				return nil, e
			}
			if !active {
				return reject("POST_IDENTITY_UNAVAILABLE")
			}
			if e = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM public.channels WHERE id=$1)`, intent.ChannelID).Scan(&active); e != nil {
				return nil, e
			}
			if !active {
				return reject("POST_CHANNEL_UNAVAILABLE")
			}
			if e = postLiveBudget(ctx, tx, account); e != nil {
				return nil, e
			}
			postID, e := uuid.NewRandom()
			if e != nil {
				return nil, e
			}
			taskID, e := uuid.NewRandom()
			if e != nil {
				return nil, e
			}
			if _, e = tx.Exec(ctx, `INSERT INTO c_posts.posts(post_id,owner_account_id,channel_id) VALUES($1,$2,$3)`, postID, account, intent.ChannelID); e != nil {
				return nil, e
			}
			if _, e = tx.Exec(ctx, `INSERT INTO c_posts.post_identity_bindings(account_id,post_id,identity_id,bound_at) VALUES($1,$2,$3,$4)`, account, postID, intent.IdentityID, final.TrustedAt); e != nil {
				return nil, e
			}
			if _, e = tx.Exec(ctx, `INSERT INTO c_posts.publication_tasks(task_id,post_id,owner_account_id,identity_id,channel_id,latest_attempt_version) VALUES($1,$2,$3,$4,$5,1)`, taskID, postID, account, intent.IdentityID, intent.ChannelID); e != nil {
				return nil, e
			}
			if e = writePostAttempt(ctx, tx, taskID.String(), 1, generation, intent, digest, final.TrustedAt); e != nil {
				return nil, e
			}
			r = posts.CommandResult{State: "ACCEPTED", Operation: posts.Create, TaskID: taskID.String(), PostID: postID.String(), AttemptVersion: 1, TaskState: posts.Accepted}
		case posts.Retry, posts.Cancel, posts.HideTask:
			task, e := readOwnPostTask(ctx, tx, account, intent.TaskID, final.TrustedAt, mute)
			if errors.Is(e, pgx.ErrNoRows) {
				return reject("TASK_NOT_FOUND")
			}
			if e != nil {
				return nil, e
			}
			if task.Task.AttemptVersion != intent.ExpectedAttemptVersion {
				return reject("TASK_VERSION_CONFLICT")
			}
			switch intent.Operation {
			case posts.Retry:
				if mutedAt(mute, final.TrustedAt) {
					return reject("POSTING_RESTRICTED")
				}
				if !task.Task.CanRetry || task.Task.AttemptVersion == math.MaxInt32 {
					return reject("TASK_NOT_RETRYABLE")
				}
				if posts.ValidateContent(intent.Title, intent.Body) != nil {
					return reject("POST_CONTENT_INVALID")
				}
				version := task.Task.AttemptVersion + 1
				if _, e = tx.Exec(ctx, `UPDATE c_posts.publication_tasks SET latest_attempt_version=$2 WHERE task_id=$1`, intent.TaskID, version); e != nil {
					return nil, e
				}
				if e = writePostAttempt(ctx, tx, intent.TaskID, version, generation, intent, digest, final.TrustedAt); e != nil {
					return nil, e
				}
				if e = enqueuePostErase(ctx, tx, intent.TaskID, task.Task.AttemptVersion, "RETRIED", final.TrustedAt); e != nil {
					return nil, e
				}
				r = posts.CommandResult{State: "ACCEPTED", Operation: posts.Retry, TaskID: intent.TaskID, PostID: task.Task.PostID, AttemptVersion: version, TaskState: posts.Accepted}
			case posts.Cancel:
				state := task.Task.State
				if state == posts.Accepted {
					if _, e = tx.Exec(ctx, `UPDATE c_posts.publication_attempts SET state='CANCELLED',terminal_at=$3 WHERE task_id=$1 AND version=$2 AND state='ACCEPTED'`, intent.TaskID, task.Task.AttemptVersion, final.TrustedAt); e != nil {
						return nil, e
					}
					if e = enqueuePostErase(ctx, tx, intent.TaskID, task.Task.AttemptVersion, "CANCELLED", final.TrustedAt); e != nil {
						return nil, e
					}
					state = posts.Cancelled
				}
				r = posts.CommandResult{State: "COMMITTED", Operation: posts.Cancel, TaskID: intent.TaskID, AttemptVersion: task.Task.AttemptVersion, TaskState: state}
			case posts.HideTask:
				if !task.Task.CanHide {
					return reject("TASK_NOT_HIDEABLE")
				}
				if _, e = tx.Exec(ctx, `UPDATE c_posts.publication_tasks SET owner_visible=false WHERE task_id=$1`, intent.TaskID); e != nil {
					return nil, e
				}
				if e = enqueuePostErase(ctx, tx, intent.TaskID, task.Task.AttemptVersion, "HIDDEN", final.TrustedAt); e != nil {
					return nil, e
				}
				r = posts.CommandResult{State: "COMMITTED", Operation: posts.HideTask, TaskID: intent.TaskID, AttemptVersion: task.Task.AttemptVersion}
			}
		case posts.DeletePost:
			var visibility string
			var task string
			var version int32
			e = tx.QueryRow(ctx, `SELECT p.visibility,t.task_id,t.latest_attempt_version FROM c_posts.posts p JOIN c_posts.publication_tasks t ON t.post_id=p.post_id WHERE p.post_id=$1 AND p.owner_account_id=$2 AND p.visibility IN ('PUBLISHED','DELETED')`, intent.PostID, account).Scan(&visibility, &task, &version)
			if errors.Is(e, pgx.ErrNoRows) {
				return reject("POST_NOT_FOUND")
			}
			if e != nil {
				return nil, e
			}
			if visibility == "PUBLISHED" {
				if _, e = tx.Exec(ctx, `UPDATE c_posts.posts SET visibility='DELETED',deleted_at=$2 WHERE post_id=$1`, intent.PostID, final.TrustedAt); e != nil {
					return nil, e
				}
				if e = enqueuePostErase(ctx, tx, task, version, "POST_DELETED", final.TrustedAt); e != nil {
					return nil, e
				}
			}
			r = posts.CommandResult{State: "COMMITTED", Operation: posts.DeletePost, PostID: intent.PostID}
		default:
			return nil, posts.ErrInvalidIntent
		}
		return r, writePostReceipt(ctx, tx, account, key, fp, r, final.TrustedAt)
	})
}
func writePostAttempt(ctx context.Context, tx pgx.Tx, task string, version int32, generation int64, intent posts.Intent, digest [32]byte, at time.Time) error {
	if _, err := tx.Exec(ctx, `INSERT INTO c_posts.publication_attempts(task_id,version,accepted_stop_generation,state,accepted_at,acceptance_ordinal) VALUES($1,$2,$3,'ACCEPTED',$4,nextval('c_posts.acceptance_ordinal_seq'))`, task, version, generation, at); err != nil {
		return err
	}
	_, err := tx.Exec(ctx, `INSERT INTO c_posts.attempt_contents(task_id,version,title,body,request_digest) VALUES($1,$2,$3,$4,$5)`, task, version, intent.Title, intent.Body, digest[:])
	return err
}
