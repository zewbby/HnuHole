package authprivacy

import (
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/comments"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/ratelimit"
)

type communityRate struct {
	engine *ratelimit.Controller
	key    [32]byte
}
type rateSpec struct {
	Budgeted              bool
	PolicyHash            string
	Account               uuid.UUID
	Kind, Operation, DMID string
	Attempt               int
	Key, Fingerprint      [32]byte
	Charges               []ratelimit.Charge
	RecoveryWindow        time.Duration
}
type admissionContextKey struct{}

func (c *Community) WithSharedRateLimit(ctx context.Context, engine *ratelimit.Controller, key [32]byte) (*Community, error) {
	if engine == nil || key == ([32]byte{}) || key == c.requestKey || !engine.MatchesSubjectKey(key) {
		return nil, ErrIntentInvalid
	}
	for _, action := range []string{"post.create", "comment.publish", "dm.send", "dm.conversation.create"} {
		if rule, ok := engine.Rule(action); ok && rule.Mode == ratelimit.Enforce && engine.PrepareWindow() <= 0 {
			return nil, ErrIntentInvalid
		}
	}
	if err := engine.ValidatePolicy(ctx); err != nil {
		return nil, ErrAuthorizationUnavailable
	}
	var ok bool
	err := c.pool.QueryRow(ctx, `SELECT to_regclass('c_rate_limit.admissions') IS NOT NULL AND to_regclass('c_rate_limit.namespace') IS NOT NULL AND has_schema_privilege(current_user,'c_rate_limit','USAGE') AND has_table_privilege(current_user,'c_rate_limit.admissions','SELECT,INSERT,DELETE') AND has_column_privilege(current_user,'c_rate_limit.admissions','state','UPDATE')`).Scan(&ok)
	if err != nil || !ok {
		return nil, ErrAuthorizationUnavailable
	}
	clone := *c
	clone.sharedRate = &communityRate{engine, key}
	return &clone, nil
}

func (c *Community) rateSubject(account uuid.UUID) string {
	return ratelimit.Digest(c.sharedRate.key, "community", "account", account.String())
}
func (c *Community) rateProof(s rateSpec, nonce []byte, incarnation string, deadline time.Time) ratelimit.Proof {
	kind := s.Kind
	if kind == "dm-text" || kind == "dm-image" {
		kind = "dm"
	}
	expires := int64(0)
	if !deadline.IsZero() {
		expires = deadline.UnixMilli()
	}
	return ratelimit.Proof{Operation: ratelimit.Digest(c.sharedRate.key, "community", "operation", kind+":"+hex.EncodeToString(s.Key[:])), Fingerprint: hex.EncodeToString(s.Fingerprint[:]), Nonce: hex.EncodeToString(nonce), Incarnation: incarnation, Deadline: expires}
}
func readRateFinal(ctx context.Context, tx pgx.Tx, s rateSpec) (bool, error) {
	var found bool
	var fingerprint []byte
	var err error
	switch s.Kind {
	case "post":
		_, fingerprint, found, err = readPostReceipt(ctx, tx, s.Key)
	case "comment":
		_, fingerprint, found, err = readCommentReceipt(ctx, tx, s.Key)
	default:
		var receipt DMReceipt
		receipt, fingerprint, err = dmReceipt(ctx, tx, s.Account, s.DMID)
		if err == nil && receipt.ErrorCode == "COMMAND_CLOSED" {
			return true, nil
		}
		found = err == nil
		if errors.Is(err, pgx.ErrNoRows) {
			err = nil
		}
	}
	if err != nil {
		return false, err
	}
	if found && !hmac.Equal(fingerprint, s.Fingerprint[:]) {
		return true, postError("COMMAND_CONFLICT", 409)
	}
	return found, nil
}
func deleteAdmission(ctx context.Context, tx pgx.Tx, s rateSpec) error {
	_, err := tx.Exec(ctx, `DELETE FROM c_rate_limit.admissions WHERE account_id=$1 AND business_kind=$2 AND key_digest=$3`, s.Account, s.Kind, s.Key[:])
	return err
}

// Called by the original permanent receipt writers, in their exact final
// authorized business transaction. No second connection or nested Gate tx.
func completeRateAdmission(ctx context.Context, tx pgx.Tx) error {
	s, ok := ctx.Value(admissionContextKey{}).(rateSpec)
	if !ok || !s.Budgeted {
		return nil
	}
	return deleteAdmission(ctx, tx, s)
}
func requireRateAdmission(ctx context.Context, tx pgx.Tx, account uuid.UUID, at time.Time) error {
	s, ok := ctx.Value(admissionContextKey{}).(rateSpec)
	if !ok {
		return nil
	}
	if s.Account != account {
		return ErrAuthorizationUnavailable
	}
	if !s.Budgeted {
		var hash string
		if err := tx.QueryRow(ctx, `SELECT policy_hash FROM c_rate_limit.namespace WHERE singleton_id=1 FOR SHARE`).Scan(&hash); err != nil {
			return ErrAuthorizationUnavailable
		}
		if hash != s.PolicyHash {
			return &PostError{Code: "SHARED_RATE_UNAVAILABLE", Status: 503}
		}
		return nil
	}
	var admittedGeneration int64
	var incarnation string
	err := tx.QueryRow(ctx, `SELECT generation,incarnation FROM c_rate_limit.admissions WHERE account_id=$1 AND business_kind=$2 AND key_digest=$3 AND fingerprint=$4 AND state='ADMITTED' AND deadline>$5`, account, s.Kind, s.Key[:], s.Fingerprint[:], at).Scan(&admittedGeneration, &incarnation)
	if err != nil {
		return ErrAuthorizationUnavailable
	}
	lock := "FOR SHARE"
	fallback := incarnation == strings.Repeat("0", 32)
	if fallback {
		lock = "FOR UPDATE"
	}
	var generation int64
	var state, policyHash string
	if err = tx.QueryRow(ctx, `SELECT generation,state,policy_hash FROM c_rate_limit.namespace WHERE singleton_id=1 `+lock).Scan(&generation, &state, &policyHash); err != nil {
		return ErrAuthorizationUnavailable
	}
	if state != "READY" || generation != admittedGeneration || policyHash != s.PolicyHash {
		return &PostError{Code: "SHARED_RATE_UNAVAILABLE", Status: 503}
	}
	if fallback {
		if s.RecoveryWindow <= 0 {
			return ErrAuthorizationUnavailable
		}
		_, err = tx.Exec(ctx, `UPDATE c_rate_limit.namespace SET dirty_until=GREATEST(COALESCE(dirty_until,clock_timestamp()),clock_timestamp()+($1::bigint*interval '1 millisecond')) WHERE singleton_id=1`, s.RecoveryWindow.Milliseconds())
		if err != nil {
			return ErrAuthorizationUnavailable
		}
	}
	return nil
}
func sealRateAdmission(ctx context.Context, tx pgx.Tx, s rateSpec, at time.Time) error {
	found, err := readRateFinal(ctx, tx, s)
	if errors.Is(err, ErrAuthorizationUnavailable) {
		return err
	}
	var conflict *PostError
	if errors.As(err, &conflict) && conflict.Code == "COMMAND_CONFLICT" {
		return deleteAdmission(ctx, tx, s)
	}
	if err != nil {
		return err
	}
	if !found {
		switch s.Kind {
		case "post":
			err = writePostReceipt(ctx, tx, s.Account, s.Key, s.Fingerprint, posts.CommandResult{State: "NOT_ACCEPTED", Operation: posts.Operation(s.Operation), Reason: "COMMAND_SEALED"}, at)
		case "comment":
			err = writeCommentReceipt(ctx, tx, s.Account, s.Key, s.Fingerprint, CommentReceipt{State: "NOT_ACCEPTED", Operation: comments.Operation(s.Operation), ErrorCode: "SEALED"}, at)
		default:
			_, err = tx.Exec(ctx, `INSERT INTO c_dm.commands(owner_account,command_id,fingerprint,attempt,state,error_code) VALUES($1,$2,$3,$4,'FAILED','ADMISSION_EXPIRED') ON CONFLICT DO NOTHING`, s.Account, s.DMID, s.Fingerprint[:], s.Attempt)
		}
	}
	if err != nil {
		return err
	}
	return deleteAdmission(ctx, tx, s)
}

// Two normal, outermost authorized transactions precede the original business
// transaction. SQL permanent receipts remain the source of business once-only.
func (c *Community) prepareRateAdmission(ctx context.Context, bearer [32]byte, build func(pgx.Tx, uuid.UUID) (rateSpec, error)) (context.Context, error) {
	if c.sharedRate == nil {
		return ctx, nil
	}
	var spec rateSpec
	var nonce []byte
	var incarnation string
	var deadline time.Time
	var preparedGeneration int64
	var final, guard bool
	_, err := c.withPostSession(ctx, bearer, func(tx pgx.Tx, a uuid.UUID, d AuthorizationDecision, _ restriction) (any, error) {
		var err error
		spec, err = build(tx, a)
		if err != nil {
			return nil, err
		}
		spec.Account = a
		spec.PolicyHash = c.sharedRate.engine.PolicyHash()
		found, err := readRateFinal(ctx, tx, spec)
		if err != nil {
			return nil, err
		}
		if found {
			final = true
			return nil, deleteAdmission(ctx, tx, spec)
		}
		for _, v := range spec.Charges {
			if r, ok := c.sharedRate.engine.Rule(v.Action); ok && r.Mode == ratelimit.Enforce {
				guard = true
			}
		}
		if !guard {
			// Observation never adds a new 429/503; its errors are metrics only.
			_, e := c.sharedRate.engine.Admit(ctx, c.rateSubject(a), spec.Charges, c.rateProof(spec, spec.Key[:16], "", time.Time{}))
			if errors.Is(e, ratelimit.ErrPolicyMismatch) {
				return nil, &PostError{Code: "SHARED_RATE_UNAVAILABLE", Status: 503}
			}
			spec.PolicyHash = c.sharedRate.engine.PolicyHash()
			return nil, nil
		}
		meta, metadataErr := c.sharedRate.engine.Metadata(ctx)
		if errors.Is(metadataErr, ratelimit.ErrPolicyMismatch) {
			return nil, &PostError{Code: "SHARED_RATE_UNAVAILABLE", Status: 503}
		}
		if metadataErr != nil {
			return nil, ErrAuthorizationUnavailable
		}
		if meta.State == "RECOVERING" {
			if e := c.sharedRate.engine.ResumeRecovery(ctx); e != nil {
				return nil, &PostError{Code: "SHARED_RATE_UNAVAILABLE", Status: 503}
			}
		}
		var stored []byte
		err = tx.QueryRow(ctx, `SELECT fingerprint,nonce,deadline,COALESCE(incarnation,''),generation FROM c_rate_limit.admissions WHERE account_id=$1 AND (business_kind=$2 OR (business_kind IN ('dm-text','dm-image') AND $2 IN ('dm-text','dm-image'))) AND key_digest=$3`, a, spec.Kind, spec.Key[:]).Scan(&stored, &nonce, &deadline, &incarnation, &preparedGeneration)
		if err == nil {
			if !hmac.Equal(stored, spec.Fingerprint[:]) {
				return nil, postError("COMMAND_CONFLICT", 409)
			}
			return nil, nil
		}
		if !errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrAuthorizationUnavailable
		}
		if _, err = tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtextextended('HNUHOLE/ADMISSION-CAPACITY/V1',0))`); err != nil {
			return nil, ErrAuthorizationUnavailable
		}
		var prepared, total, ownPrepared, ownTotal int
		err = tx.QueryRow(ctx, `SELECT count(*) FILTER(WHERE state='PREPARED'),count(*),count(*) FILTER(WHERE account_id=$1 AND state='PREPARED'),count(*) FILTER(WHERE account_id=$1) FROM c_rate_limit.admissions`, a).Scan(&prepared, &total, &ownPrepared, &ownTotal)
		if err != nil {
			return nil, ErrAuthorizationUnavailable
		}
		if prepared >= 4096 || total >= 65536 || ownPrepared >= 16 || ownTotal >= 256 {
			return nil, &PostError{Code: "SHARED_RATE_UNAVAILABLE", Status: 503}
		}
		var namespaceState, namespacePolicy string
		if err = tx.QueryRow(ctx, `SELECT generation,state,policy_hash FROM c_rate_limit.namespace WHERE singleton_id=1 FOR SHARE`).Scan(&preparedGeneration, &namespaceState, &namespacePolicy); err != nil {
			return nil, ErrAuthorizationUnavailable
		}
		if namespaceState != "READY" || namespacePolicy != spec.PolicyHash {
			return nil, &PostError{Code: "SHARED_RATE_UNAVAILABLE", Status: 503}
		}
		nonce = make([]byte, 16)
		if _, err = rand.Read(nonce); err != nil {
			return nil, ErrAuthorizationUnavailable
		}
		deadline = d.TrustedAt.Add(c.sharedRate.engine.PrepareWindow())
		actions, err := json.Marshal(spec.Charges)
		if err != nil {
			return nil, ErrAuthorizationUnavailable
		}
		_, err = tx.Exec(ctx, `INSERT INTO c_rate_limit.admissions(account_id,business_kind,key_digest,fingerprint,nonce,actions,operation,dm_command_id,attempt,state,created_at,deadline,generation) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,'PREPARED',$10,$11,$12)`, a, spec.Kind, spec.Key[:], spec.Fingerprint[:], nonce, actions, spec.Operation, nullablePostID(spec.DMID), spec.Attempt, d.TrustedAt, deadline, preparedGeneration)
		return nil, err
	})
	if err != nil || final || !guard {
		if err == nil && final {
			_ = c.sharedRate.engine.Confirm(ctx, c.rateSubject(spec.Account), c.rateProof(spec, nil, "", time.Now().Add(time.Minute)))
		}
		if err == nil && (final || !guard) {
			return context.WithValue(ctx, admissionContextKey{}, spec), nil
		}
		return ctx, err
	}
	var denied int
	var closed bool
	_, err = c.withPostSession(ctx, bearer, func(tx pgx.Tx, a uuid.UUID, d AuthorizationDecision, _ restriction) (any, error) {
		found, err := readRateFinal(ctx, tx, spec)
		if err != nil {
			return nil, err
		}
		if found {
			final = true
			return nil, deleteAdmission(ctx, tx, spec)
		}
		var state string
		var generation int64
		var stored []byte
		err = tx.QueryRow(ctx, `SELECT state,fingerprint,nonce,deadline,COALESCE(incarnation,''),generation FROM c_rate_limit.admissions WHERE account_id=$1 AND business_kind=$2 AND key_digest=$3 FOR UPDATE`, a, spec.Kind, spec.Key[:]).Scan(&state, &stored, &nonce, &deadline, &incarnation, &generation)
		if err != nil {
			return nil, ErrAuthorizationUnavailable
		}
		if !hmac.Equal(stored, spec.Fingerprint[:]) {
			return nil, postError("COMMAND_CONFLICT", 409)
		}
		if !d.TrustedAt.Before(deadline) {
			closed = true
			return nil, sealRateAdmission(ctx, tx, spec, d.TrustedAt)
		}
		ns, e := c.sharedRate.engine.Metadata(ctx)
		if e != nil {
			return nil, ErrAuthorizationUnavailable
		}
		if ns.Generation != generation {
			closed = true
			return nil, sealRateAdmission(ctx, tx, spec, d.TrustedAt)
		}
		if ns.State != "READY" {
			return nil, &PostError{Code: "SHARED_RATE_UNAVAILABLE", Status: 503}
		}
		var decision ratelimit.Decision
		if state == "ADMITTED" {
			// Durable admission is sufficient in its original namespace epoch;
			// the hot Redis marker may have expired after SQL was confirmed.
			decision = ratelimit.Decision{Allowed: true, Replay: true, Generation: generation, Incarnation: incarnation}
		} else {
			proof := c.rateProof(spec, nonce, incarnation, deadline)
			proof.ExpectedGeneration = generation
			decision, err = c.sharedRate.engine.Admit(ctx, c.rateSubject(a), spec.Charges, proof)
		}
		if (errors.Is(err, ratelimit.ErrUnavailable) || errors.Is(err, ratelimit.ErrCapacity)) && c.sharedRate.engine.CanDBFallback(ctx) {
			verified := true
			for _, charge := range spec.Charges {
				rule, ok := c.sharedRate.engine.Rule(charge.Action)
				if !ok || rule.Failure != "verified-db" {
					verified = false
				}
			}
			if verified {
				current, e := c.sharedRate.engine.Metadata(ctx)
				if e == nil && current.State == "READY" && current.Generation == generation {
					err = nil
					decision = ratelimit.Decision{Allowed: true, Generation: generation, Incarnation: strings.Repeat("0", 32)}
					for _, charge := range spec.Charges {
						c.sharedRate.engine.RecordFallback(charge.Action)
					}
				}
			}
		}
		if errors.Is(err, ratelimit.ErrConflict) {
			return nil, postError("COMMAND_CONFLICT", 409)
		}
		if errors.Is(err, ratelimit.ErrLost) || errors.Is(err, ratelimit.ErrStaleProof) {
			closed = true
			return nil, sealRateAdmission(ctx, tx, spec, d.TrustedAt)
		}
		if err != nil {
			return nil, &PostError{Code: "SHARED_RATE_UNAVAILABLE", Status: 503}
		}
		if !decision.Allowed {
			denied = decision.RetryAfter
			return nil, deleteAdmission(ctx, tx, spec)
		}
		// Validate the epoch again after Redis; hold the shared row lock until
		// this confirmation commits, so a racing recovery cannot certify it.
		var currentGeneration int64
		var currentState string
		if err = tx.QueryRow(ctx, `SELECT generation,state FROM c_rate_limit.namespace WHERE singleton_id=1 FOR SHARE`).Scan(&currentGeneration, &currentState); err != nil {
			return nil, ErrAuthorizationUnavailable
		}
		if currentGeneration != generation {
			closed = true
			return nil, sealRateAdmission(ctx, tx, spec, d.TrustedAt)
		}
		if currentState != "READY" {
			return nil, &PostError{Code: "SHARED_RATE_UNAVAILABLE", Status: 503}
		}
		spec.Budgeted = true
		spec.RecoveryWindow = c.sharedRate.engine.RecoveryWindow()
		spec.PolicyHash = c.sharedRate.engine.PolicyHash()
		_, err = tx.Exec(ctx, `UPDATE c_rate_limit.admissions SET state='ADMITTED',generation=$4,incarnation=$5,confirmed_at=$6,deadline=created_at+interval '24 hours' WHERE account_id=$1 AND business_kind=$2 AND key_digest=$3`, a, spec.Kind, spec.Key[:], decision.Generation, decision.Incarnation, d.TrustedAt)
		return nil, err
	})
	if err != nil {
		return ctx, err
	}
	if denied > 0 {
		return ctx, &PostError{Code: "RATE_LIMITED", Status: 429, RetryAfter: denied}
	}
	if final || closed {
		spec.Budgeted = false
		return context.WithValue(ctx, admissionContextKey{}, spec), nil
	}
	return context.WithValue(ctx, admissionContextKey{}, spec), nil
}

func (c *Community) ExecutePostCommand(ctx context.Context, b [32]byte, key string, in posts.Intent) (PostResponse, error) {
	if !c.PostsEnabled() {
		return PostResponse{}, ErrAuthorizationUnavailable
	}
	if _, err := posts.ParseCommandKey(key); err != nil {
		return PostResponse{}, err
	}
	digest, err := posts.RequestDigest(in)
	if err != nil {
		return PostResponse{}, err
	}
	if c.sharedRate != nil && (in.Operation == posts.Create || in.Operation == posts.Retry) {
		ctx, err = c.prepareRateAdmission(ctx, b, func(_ pgx.Tx, a uuid.UUID) (rateSpec, error) {
			k, e := c.posts.commands.KeyDigest(a.String(), key)
			return rateSpec{Kind: "post", Operation: string(in.Operation), Key: k, Fingerprint: c.posts.commands.IntentFingerprint(digest), Charges: []ratelimit.Charge{{Action: "post.create", Cost: 1}}}, e
		})
		if err != nil {
			return PostResponse{}, err
		}
	}
	result, err := c.executePostCommandOnce(ctx, b, key, in)
	if err == nil {
		c.confirmRateAdmission(ctx)
	}
	return result, err
}
func (c *Community) ExecuteCommentCommand(ctx context.Context, b [32]byte, key string, in comments.Intent) (PostResponse, error) {
	if !c.CommentsEnabled() {
		return PostResponse{}, ErrAuthorizationUnavailable
	}
	if _, err := comments.ParseCommandKey(key); err != nil {
		return PostResponse{}, err
	}
	digest, err := comments.RequestDigest(in)
	if err != nil {
		return PostResponse{}, err
	}
	if c.sharedRate != nil && (in.Operation == comments.Create || in.Operation == comments.Retry) {
		ctx, err = c.prepareRateAdmission(ctx, b, func(_ pgx.Tx, a uuid.UUID) (rateSpec, error) {
			k, e := c.comments.codec.KeyDigest(a.String(), key)
			return rateSpec{Kind: "comment", Operation: string(in.Operation), Key: k, Fingerprint: c.comments.codec.IntentFingerprint(digest), Charges: []ratelimit.Charge{{Action: "comment.publish", Cost: 1}}}, e
		})
		if err != nil {
			return PostResponse{}, err
		}
	}
	result, err := c.executeCommentCommandOnce(ctx, b, key, in)
	if err == nil {
		c.confirmRateAdmission(ctx)
	}
	return result, err
}
func (c *Community) dmRateSpec(ctx context.Context, tx pgx.Tx, a uuid.UUID, kind, id string, fingerprint []byte, attempt int, own, peer string, newConversation bool) (rateSpec, error) {
	s := rateSpec{Account: a, Kind: kind, DMID: id, Attempt: attempt, Charges: []ratelimit.Charge{{Action: "dm.send", Cost: 1}}}
	copy(s.Fingerprint[:], fingerprint)
	s.Key = sha256.Sum256([]byte("HNUHOLE/DM-ADMISSION/V1\x00" + a.String() + "\x00" + id))
	if newConversation {
		pair := own + ":" + peer
		if own > peer {
			pair = peer + ":" + own
		}
		if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtextextended($1,0))`, "HNUHOLE/DM-PAIR/V1:"+pair); err != nil {
			return s, err
		}
		var exists bool
		err := tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM c_dm.conversations WHERE (low_identity=$1 AND high_identity=$2) OR (low_identity=$2 AND high_identity=$1))`, own, peer).Scan(&exists)
		if err != nil {
			return s, err
		}
		if !exists {
			s.Charges = append(s.Charges, ratelimit.Charge{Action: "dm.conversation.create", Cost: 1})
		}
	}
	return s, nil
}
func (c *Community) SendDMText(ctx context.Context, b [32]byte, id string, in DMTextIntent) (PostResponse, error) {
	if !dmUUID(id) {
		return PostResponse{}, postError("MALFORMED_REQUEST", 400)
	}
	if err := in.Validate(); err != nil {
		return PostResponse{}, err
	}
	material := in
	material.Attempt = 0
	fp := c.dmFingerprint("HNUHOLE/DM-INTENT/V1\x00", material)
	if c.sharedRate != nil {
		var err error
		ctx, err = c.prepareRateAdmission(ctx, b, func(tx pgx.Tx, a uuid.UUID) (rateSpec, error) {
			return c.dmRateSpec(ctx, tx, a, "dm-text", id, fp, in.Attempt, in.IdentityID, in.PeerID, true)
		})
		if err != nil {
			return PostResponse{}, err
		}
	}
	result, err := c.sendDMTextOnce(ctx, b, id, in)
	if err == nil {
		c.confirmRateAdmission(ctx)
	}
	return result, err
}
func (c *Community) SendDMImage(ctx context.Context, b [32]byte, id string, in DMImageIntent) (PostResponse, error) {
	data, validationErr := validatedDMImage(id, in)
	if validationErr != nil {
		return PostResponse{}, validationErr
	}
	ctx = context.WithValue(ctx, dmImageBytesKey{}, data)
	material := in
	material.Attempt = 0
	material.Data = ""
	fp := c.dmFingerprint("HNUHOLE/DM-IMAGE/V1\x00", material)
	if c.sharedRate != nil {
		var err error
		ctx, err = c.prepareRateAdmission(ctx, b, func(tx pgx.Tx, a uuid.UUID) (rateSpec, error) {
			return c.dmRateSpec(ctx, tx, a, "dm-image", id, fp, in.Attempt, in.IdentityID, in.PeerID, false)
		})
		if err != nil {
			return PostResponse{}, err
		}
	}
	result, err := c.sendDMImageOnce(ctx, b, id, in)
	if err == nil {
		c.confirmRateAdmission(ctx)
	}
	return result, err
}

func (c *Community) confirmRateAdmission(ctx context.Context) {
	s, ok := ctx.Value(admissionContextKey{}).(rateSpec)
	if !ok || !s.Budgeted {
		return
	}
	_ = c.sharedRate.engine.Confirm(ctx, c.rateSubject(s.Account), c.rateProof(s, nil, "", time.Now().Add(time.Minute)))
}
