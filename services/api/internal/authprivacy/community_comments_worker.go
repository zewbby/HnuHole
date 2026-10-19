package authprivacy

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/comments"
)

// PublishAcceptedComments is bounded and restart-safe in PostgreSQL. A DB/Gate
// failure leaves ACCEPTED; transport uncertainty never becomes task failure.
func (c *Community) PublishAcceptedComments(ctx context.Context, limit int) (int64, error) {
	if !c.CommentsEnabled() {
		return 0, nil
	}
	if limit < 1 || limit > 100 {
		return 0, ErrIntentInvalid
	}
	rows, e := c.pool.Query(ctx, `SELECT t.task_id,t.owner_account_id FROM c_comments.tasks t JOIN c_comments.attempts x USING(task_id) WHERE x.state='ACCEPTED' ORDER BY (x.image IS NULL OR EXISTS(SELECT 1 FROM c_comments.images m WHERE m.task_id=x.task_id AND m.version=x.version AND m.payload IS NOT NULL) OR x.accepted_at<=clock_timestamp()-interval '15 minutes') DESC,x.accepted_at,t.task_id LIMIT $1`, limit)
	if e != nil {
		return 0, ErrAuthorizationUnavailable
	}
	type job struct{ task, account uuid.UUID }
	jobs := []job{}
	for rows.Next() {
		var j job
		if e = rows.Scan(&j.task, &j.account); e != nil {
			break
		}
		jobs = append(jobs, j)
	}
	if e == nil {
		e = rows.Err()
	}
	rows.Close()
	if e != nil {
		return 0, ErrAuthorizationUnavailable
	}
	var n int64
	for _, j := range jobs {
		if e = c.publishComment(ctx, j.account, j.task); e != nil {
			return n, e
		}
		n++
	}
	return n, nil
}
func (c *Community) publishComment(ctx context.Context, account, task uuid.UUID) error {
	decision, e := c.gate.Snapshot(ctx)
	if e != nil {
		return e
	}
	tx, e := begin(ctx, c.pool)
	if e != nil {
		return ErrAuthorizationUnavailable
	}
	defer c.gate.Abort(ctx, tx)
	var state string
	if e = tx.QueryRow(ctx, `SELECT state FROM c_auth.accounts WHERE account_id=$1 FOR UPDATE`, account).Scan(&state); e != nil {
		return e
	}
	ban, e := lockRestriction(ctx, tx, account)
	if e != nil {
		return e
	}
	var mute restriction
	if e = tx.QueryRow(ctx, `SELECT mute_state,mute_ends_at FROM c_auth.account_restrictions WHERE account_id=$1`, account).Scan(&mute.state, &mute.ends); e != nil {
		return e
	}
	_, e = c.gate.CommitAuthorized(ctx, tx, decision.Generation, func(final AuthorizationDecision) error {
		if e := c.checkPostProtocolKeys(ctx, tx); e != nil {
			return e
		}
		if e := c.checkCommentKeys(ctx, tx); e != nil {
			return e
		}
		t, e := loadCommentTask(ctx, tx, account, task.String())
		if e != nil {
			return e
		}
		v := t.View()
		if v.State != comments.Accepted {
			return nil
		}
		failure := comments.FailureCode("")
		if state != "ACTIVE" || bannedAt(ban, final.TrustedAt) || mutedAt(mute, final.TrustedAt) {
			failure = comments.FailurePublishingStopped
		} else {
			e = checkCommentContext(ctx, tx, account, v.Binding)
			var business *PostError
			if errors.As(e, &business) {
				switch business.Code {
				case "IDENTITY_INACTIVE":
					failure = comments.FailureIdentityInactive
				case "POST_UNAVAILABLE":
					failure = comments.FailurePostUnavailable
				case "COMMENT_TARGET_DELETED":
					failure = comments.FailureTargetDeleted
				default:
					return e
				}
			} else if e != nil {
				return e
			}
		}
		var acceptedGeneration, currentGeneration int64
		if e = tx.QueryRow(ctx, `SELECT x.accepted_stop_generation,c.stop_generation FROM c_comments.attempts x,c_posts.account_publication_control c WHERE x.task_id=$1 AND x.version=$2 AND c.account_id=$3`, v.TaskID, v.AttemptVersion, account).Scan(&acceptedGeneration, &currentGeneration); e != nil {
			return e
		}
		if acceptedGeneration != currentGeneration {
			failure = comments.FailurePublishingStopped
		}
		if failure == "" && v.Content != nil && v.Content.Image != nil {
			var ready bool
			if e = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM c_comments.images WHERE task_id=$1 AND version=$2 AND payload IS NOT NULL AND erased_at IS NULL)`, v.TaskID, v.AttemptVersion).Scan(&ready); e != nil {
				return e
			}
			if !ready {
				if final.TrustedAt.Before(v.AcceptedAt.Add(15 * time.Minute)) {
					return nil
				}
				failure = comments.FailurePublication
			}
		}
		if failure == "" {
			t, e = t.Publish(v.AttemptVersion, final.TrustedAt)
		} else {
			t, e = t.Fail(v.AttemptVersion, failure, final.TrustedAt)
		}
		if e != nil {
			return e
		}
		v = t.View()
		_, e = tx.Exec(ctx, `UPDATE c_comments.attempts SET state=$3,terminal_at=$4,failure_code=$5 WHERE task_id=$1 AND version=$2 AND state='ACCEPTED'`, v.TaskID, v.AttemptVersion, v.State, v.TerminalAt, nullablePostID(string(v.FailureCode)))
		return e
	})
	if errors.Is(e, errPostProtocolIntegrity) {
		_ = c.gate.Abort(ctx, tx)
		return c.freezePostProtocol(ctx)
	}
	return e
}
