package authprivacy

import (
	"context"
	"errors"
	"math"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

func materializePostStops(ctx context.Context, tx pgx.Tx, account uuid.UUID) error {
	_, err := tx.Exec(ctx, `UPDATE c_posts.publication_attempts a SET state='FAILED',terminal_at=e.stopped_at,failure_code='PUBLISHING_STOPPED'
 FROM c_posts.publication_tasks t,c_posts.account_publication_control c,c_posts.publication_stop_events e
 WHERE t.task_id=a.task_id AND t.latest_attempt_version=a.version AND t.owner_account_id=$1 AND c.account_id=$1
 AND a.state='ACCEPTED' AND a.accepted_stop_generation<c.stop_generation
 AND e.account_id=$1 AND e.generation=a.accepted_stop_generation+1`, account)
	return err
}
func enqueuePostErase(ctx context.Context, tx pgx.Tx, task string, version int32, cause string, at time.Time) error {
	_, err := tx.Exec(ctx, `INSERT INTO c_posts.payload_cleanup(task_id,version,cause,requested_at,due_at,state) VALUES($1,$2,$3,$4,$5,'PENDING') ON CONFLICT(task_id,version) DO NOTHING`, task, version, cause, at, at.Add(7*24*time.Hour))
	return err
}

// 与身份/关闭/处罚同一最终授权事务推进；不使用会话代次停止后台任务。
func (c *Community) stopPostPublication(ctx context.Context, tx pgx.Tx, account uuid.UUID, cause string, at time.Time) error {
	if !c.PostsEnabled() {
		return nil
	}
	if err := materializePostStops(ctx, tx, account); err != nil {
		return err
	}
	var generation int64
	if err := tx.QueryRow(ctx, `SELECT stop_generation FROM c_posts.account_publication_control WHERE account_id=$1`, account).Scan(&generation); err != nil {
		return err
	}
	if generation == math.MaxInt64 {
		return ErrAuthorizationUnavailable
	}
	if _, err := tx.Exec(ctx, `INSERT INTO c_posts.publication_stop_events(account_id,generation,stopped_at,cause) VALUES($1,$2,$3,$4)`, account, generation+1, at, cause); err != nil {
		return err
	}
	_, err := tx.Exec(ctx, `UPDATE c_posts.account_publication_control SET stop_generation=stop_generation+1 WHERE account_id=$1`, account)
	return err
}
func (c *Community) deleteIdentityPostTasks(ctx context.Context, tx pgx.Tx, account, identity uuid.UUID, at time.Time) error {
	if !c.PostsEnabled() {
		return nil
	}
	if err := materializePostStops(ctx, tx, account); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, `UPDATE c_posts.publication_attempts a SET state='FAILED',terminal_at=$3,failure_code='IDENTITY_INACTIVE' FROM c_posts.publication_tasks t WHERE t.task_id=a.task_id AND t.owner_account_id=$1 AND t.identity_id=$2 AND a.state='ACCEPTED'`, account, identity, at); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, `UPDATE c_posts.publication_tasks SET owner_visible=false WHERE owner_account_id=$1 AND identity_id=$2 AND owner_visible`, account, identity); err != nil {
		return err
	}
	_, err := tx.Exec(ctx, `INSERT INTO c_posts.payload_cleanup(task_id,version,cause,requested_at,due_at,state)
 SELECT a.task_id,a.version,'IDENTITY_DELETED',$3,$4,'PENDING' FROM c_posts.publication_attempts a JOIN c_posts.publication_tasks t USING(task_id)
 WHERE t.owner_account_id=$1 AND t.identity_id=$2 AND a.state<>'PUBLISHED' ON CONFLICT(task_id,version) DO NOTHING`, account, identity, at, at.Add(7*24*time.Hour))
	return err
}
func (c *Community) closePostAccount(ctx context.Context, tx pgx.Tx, account uuid.UUID, at time.Time) error {
	if !c.PostsEnabled() {
		return nil
	}
	if err := c.stopPostPublication(ctx, tx, account, "ACCOUNT_CLOSED", at); err != nil {
		return err
	}
	if err := materializePostStops(ctx, tx, account); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, `UPDATE c_posts.publication_tasks SET owner_visible=false WHERE owner_account_id=$1 AND owner_visible`, account); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, `INSERT INTO c_posts.payload_cleanup(task_id,version,cause,requested_at,due_at,state)
 SELECT a.task_id,a.version,'ACCOUNT_CLOSED',$2,$3,'PENDING' FROM c_posts.publication_attempts a JOIN c_posts.publication_tasks t USING(task_id)
 JOIN c_posts.posts p ON p.post_id=t.post_id WHERE t.owner_account_id=$1 AND (a.state<>'PUBLISHED' OR p.visibility='DELETED') ON CONFLICT(task_id,version) DO NOTHING`, account, at, at.Add(7*24*time.Hour)); err != nil {
		return err
	}
	_, err := tx.Exec(ctx, `UPDATE c_posts.command_receipts SET owner_account_id=NULL,outcome='RESULT_EXPIRED',task_id=NULL,post_id=NULL,attempt_version=NULL,task_state=NULL,error_code=NULL WHERE owner_account_id=$1`, account)
	return err
}

// ApplyAccountMute 是受信服务端入口，不注册公共处罚API；版本检查与stop事件同事务。
func (c *Community) ApplyAccountMute(ctx context.Context, account uuid.UUID, expectedVersion int64, endsAt *time.Time) error {
	if !c.PostsEnabled() || account == uuid.Nil || expectedVersion < 1 {
		return ErrIntentInvalid
	}
	decision, err := c.gate.Snapshot(ctx)
	if err != nil {
		return err
	}
	tx, err := begin(ctx, c.pool)
	if err != nil {
		return ErrAuthorizationUnavailable
	}
	defer c.gate.Abort(ctx, tx)
	var state string
	if err = tx.QueryRow(ctx, `SELECT state FROM c_auth.accounts WHERE account_id=$1 FOR UPDATE`, account).Scan(&state); errors.Is(err, pgx.ErrNoRows) {
		return ErrAccountUnavailable
	} else if err != nil {
		return ErrAuthorizationUnavailable
	}
	if _, err = lockRestriction(ctx, tx, account); err != nil {
		return ErrAuthorizationUnavailable
	}
	var version int64
	if err = tx.QueryRow(ctx, `SELECT version FROM c_auth.account_restrictions WHERE account_id=$1`, account).Scan(&version); err != nil {
		return ErrAuthorizationUnavailable
	}
	_, err = c.gate.CommitAuthorized(ctx, tx, decision.Generation, func(final AuthorizationDecision) error {
		if state == "CLOSED" {
			return ErrAccountUnavailable
		}
		if version != expectedVersion {
			return ErrRestrictionStateChanged
		}
		if version == math.MaxInt64 {
			return ErrAuthorizationUnavailable
		}
		if endsAt != nil && !endsAt.After(final.TrustedAt) {
			return ErrIntentInvalid
		}
		if err := c.stopPostPublication(ctx, tx, account, "MUTE", final.TrustedAt); err != nil {
			return err
		}
		_, err := tx.Exec(ctx, `UPDATE c_auth.account_restrictions SET mute_state='MUTED',mute_ends_at=$2,version=version+1 WHERE account_id=$1`, account, endsAt)
		return err
	})
	return err
}

// 候选扫描不先锁attempt。账号锁之后才处理本账号资源，避免与取消线程反转锁序。
func (c *Community) PublishAcceptedPosts(ctx context.Context, limit int) (int64, error) {
	if !c.PostsEnabled() {
		return 0, nil
	}
	if limit < 1 || limit > 100 {
		return 0, ErrIntentInvalid
	}
	rows, err := c.pool.Query(ctx, `SELECT t.task_id,t.owner_account_id FROM c_posts.publication_tasks t JOIN c_posts.publication_attempts a ON a.task_id=t.task_id AND a.version=t.latest_attempt_version WHERE a.state='ACCEPTED' ORDER BY a.accepted_at,t.task_id LIMIT $1`, limit)
	if err != nil {
		return 0, ErrAuthorizationUnavailable
	}
	type candidate struct{ task, account uuid.UUID }
	var candidates []candidate
	for rows.Next() {
		var item candidate
		if err = rows.Scan(&item.task, &item.account); err != nil {
			break
		}
		candidates = append(candidates, item)
	}
	if err == nil {
		err = rows.Err()
	}
	rows.Close()
	if err != nil {
		return 0, ErrAuthorizationUnavailable
	}
	var processed int64
	for _, item := range candidates {
		if err = c.publishPostCandidate(ctx, item.account, item.task); err != nil {
			return processed, err
		}
		processed++
	}
	return processed, nil
}
func (c *Community) publishPostCandidate(ctx context.Context, account, task uuid.UUID) error {
	decision, err := c.gate.Snapshot(ctx)
	if err != nil {
		return err
	}
	tx, err := begin(ctx, c.pool)
	if err != nil {
		return ErrAuthorizationUnavailable
	}
	defer c.gate.Abort(ctx, tx)
	var accountState string
	if err = tx.QueryRow(ctx, `SELECT state FROM c_auth.accounts WHERE account_id=$1 FOR UPDATE`, account).Scan(&accountState); err != nil {
		return ErrAuthorizationUnavailable
	}
	ban, err := lockRestriction(ctx, tx, account)
	if err != nil {
		return ErrAuthorizationUnavailable
	}
	var mute restriction
	if err = tx.QueryRow(ctx, `SELECT mute_state,mute_ends_at FROM c_auth.account_restrictions WHERE account_id=$1`, account).Scan(&mute.state, &mute.ends); err != nil {
		return ErrAuthorizationUnavailable
	}
	_, err = c.gate.CommitAuthorized(ctx, tx, decision.Generation, func(final AuthorizationDecision) error {
		if e := c.checkPostProtocolKeys(ctx, tx); e != nil {
			return e
		}
		if e := materializePostStops(ctx, tx, account); e != nil {
			return e
		}
		var state, postVisibility string
		var post, identity uuid.UUID
		var version int32
		var deleted *time.Time
		var contentAvailable bool
		e := tx.QueryRow(ctx, `SELECT a.state,t.post_id,t.identity_id,t.latest_attempt_version,i.deleted_at,p.visibility,(x.erased_at IS NULL)
 FROM c_posts.publication_tasks t JOIN c_posts.publication_attempts a ON a.task_id=t.task_id AND a.version=t.latest_attempt_version
 JOIN public.community_identities i ON i.identity_id=t.identity_id JOIN c_posts.posts p ON p.post_id=t.post_id
 JOIN c_posts.attempt_contents x ON x.task_id=a.task_id AND x.version=a.version WHERE t.task_id=$1 AND t.owner_account_id=$2`, task, account).Scan(&state, &post, &identity, &version, &deleted, &postVisibility, &contentAvailable)
		if errors.Is(e, pgx.ErrNoRows) {
			return nil
		}
		if e != nil {
			return e
		}
		if state != "ACCEPTED" {
			return nil
		}
		if accountState != "ACTIVE" || bannedAt(ban, final.TrustedAt) || mutedAt(mute, final.TrustedAt) || deleted != nil || !contentAvailable || postVisibility != "INTERNAL" {
			code := "PUBLICATION_FAILED"
			if deleted != nil {
				code = "IDENTITY_INACTIVE"
			}
			if accountState != "ACTIVE" || bannedAt(ban, final.TrustedAt) || mutedAt(mute, final.TrustedAt) {
				code = "PUBLISHING_STOPPED"
			}
			_, e = tx.Exec(ctx, `UPDATE c_posts.publication_attempts SET state='FAILED',terminal_at=$3,failure_code=$4 WHERE task_id=$1 AND version=$2`, task, version, final.TrustedAt, code)
			return e
		}
		var ordinal int64
		if e = tx.QueryRow(ctx, `SELECT nextval('c_posts.publication_ordinal_seq')`).Scan(&ordinal); e != nil {
			return e
		}
		if _, e = tx.Exec(ctx, `UPDATE c_posts.publication_attempts SET state='PUBLISHED',terminal_at=$3 WHERE task_id=$1 AND version=$2`, task, version, final.TrustedAt); e != nil {
			return e
		}
		if _, e = tx.Exec(ctx, `UPDATE c_posts.posts SET visibility='PUBLISHED',published_attempt_version=$2,published_at=$3,publication_ordinal=$4 WHERE post_id=$1 AND visibility='INTERNAL'`, post, version, final.TrustedAt, ordinal); e != nil {
			return e
		}
		_, e = tx.Exec(ctx, `UPDATE c_posts.account_publication_control SET last_public_identity_id=$2,last_public_at=$3,last_public_ordinal=$4 WHERE account_id=$1`, account, identity, final.TrustedAt, ordinal)
		return e
	})
	if errors.Is(err, errPostProtocolIntegrity) {
		_ = c.gate.Abort(ctx, tx)
		return c.freezePostProtocol(ctx)
	}
	return err
}

func (c *Community) CleanupPostPayloads(ctx context.Context, limit int) (int64, error) {
	if !c.PostsEnabled() {
		return 0, nil
	}
	if limit < 1 || limit > 100 {
		return 0, ErrIntentInvalid
	}
	rows, err := c.pool.Query(ctx, `SELECT q.task_id,q.version,t.owner_account_id FROM c_posts.payload_cleanup q JOIN c_posts.publication_tasks t USING(task_id) WHERE q.state='PENDING' ORDER BY q.requested_at,q.task_id,q.version LIMIT $1`, limit)
	if err != nil {
		return 0, ErrAuthorizationUnavailable
	}
	type candidate struct {
		task, account uuid.UUID
		version       int32
	}
	var items []candidate
	for rows.Next() {
		var item candidate
		if err = rows.Scan(&item.task, &item.version, &item.account); err != nil {
			break
		}
		items = append(items, item)
	}
	if err == nil {
		err = rows.Err()
	}
	rows.Close()
	if err != nil {
		return 0, ErrAuthorizationUnavailable
	}
	var count int64
	for _, item := range items {
		decision, e := c.gate.Snapshot(ctx)
		if e != nil {
			return count, e
		}
		tx, e := begin(ctx, c.pool)
		if e != nil {
			return count, ErrAuthorizationUnavailable
		}
		var owner uuid.UUID
		e = tx.QueryRow(ctx, `SELECT account_id FROM c_auth.accounts WHERE account_id=$1 FOR UPDATE`, item.account).Scan(&owner)
		if e == nil {
			_, e = c.gate.CommitAuthorized(ctx, tx, decision.Generation, func(final AuthorizationDecision) error {
				if e := c.checkPostProtocolKeys(ctx, tx); e != nil {
					return e
				}
				var eligible bool
				if e := tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM c_posts.payload_cleanup WHERE task_id=$1 AND version=$2 AND state='PENDING')`, item.task, item.version).Scan(&eligible); e != nil {
					return e
				}
				if !eligible {
					return nil
				}
				if _, e := tx.Exec(ctx, `UPDATE c_posts.attempt_contents SET title=NULL,body=NULL,erased_at=$3 WHERE task_id=$1 AND version=$2 AND erased_at IS NULL`, item.task, item.version, final.TrustedAt); e != nil {
					return e
				}
				_, e := tx.Exec(ctx, `UPDATE c_posts.payload_cleanup SET state='ERASED' WHERE task_id=$1 AND version=$2`, item.task, item.version)
				return e
			})
		}
		_ = c.gate.Abort(ctx, tx)
		if errors.Is(e, errPostProtocolIntegrity) {
			e = c.freezePostProtocol(ctx)
		}
		if e != nil {
			return count, e
		}
		count++
	}
	return count, nil
}
