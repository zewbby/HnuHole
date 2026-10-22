package authprivacy

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"sort"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
)

// P1 is explicitly enabled only in isolated integration environments.
func (c *Community) WithDirectMessages(ctx context.Context) (*Community, error) {
	if !c.PostsEnabled() {
		return nil, ErrAuthorizationUnavailable
	}
	var present bool
	if err := c.pool.QueryRow(ctx, `SELECT to_regclass('c_dm.messages') IS NOT NULL AND to_regclass('c_dm.commands') IS NOT NULL`).Scan(&present); err != nil || !present {
		return nil, ErrAuthorizationUnavailable
	}
	clone := *c
	if e := clone.checkDMSchema(ctx); e != nil {
		return nil, e
	}
	clone.directMessages = true
	return &clone, nil
}
func (c *Community) DirectMessagesEnabled() bool { return c != nil && c.directMessages }

type DMTextIntent struct {
	IdentityID      string `json:"identityId"`
	PeerID          string `json:"peerId"`
	ConversationID  string `json:"conversationId"`
	SourcePostID    string `json:"sourcePostId"`
	SourceCommentID string `json:"sourceCommentId"`
	Text            string `json:"text"`
	Attempt         int    `json:"attempt"`
}
type DMReceipt struct {
	State          string     `json:"state"`
	Attempt        int        `json:"attempt"`
	ErrorCode      string     `json:"errorCode,omitempty"`
	MessageID      string     `json:"messageId,omitempty"`
	ConversationID string     `json:"conversationId,omitempty"`
	Sequence       int64      `json:"sequence,omitempty"`
	AcceptedAt     *time.Time `json:"acceptedAt,omitempty"`
}
type DMConversation struct {
	ID           string `json:"id"`
	IdentityID   string `json:"identityId"`
	PeerID       string `json:"peerId"`
	PeerName     string `json:"peerName"`
	SourcePostID string `json:"sourcePostId"`
	Sequence     int64  `json:"sequence"`
	Unread       int64  `json:"unread"`
	Waiting      bool   `json:"waiting"`
	CanSend      bool   `json:"canSend"`
}
type DMDelivery struct {
	MessageID      string    `json:"messageId"`
	ConversationID string    `json:"conversationId"`
	IdentityID     string    `json:"identityId"`
	SenderID       string    `json:"senderId"`
	Sequence       int64     `json:"sequence"`
	Text           string    `json:"text"`
	AcceptedAt     time.Time `json:"acceptedAt"`
}
type DMDirectory struct {
	Items []DMConversation `json:"items"`
}
type DMPending struct {
	Items []DMDelivery `json:"items"`
}
type DMApplied struct {
	State string `json:"state"`
}

type DMContact struct {
	PeerID          string `json:"peerId"`
	PeerName        string `json:"peerName"`
	BoundIdentityID string `json:"boundIdentityId"`
	Self            bool   `json:"self"`
}

func (c *Community) DMContact(ctx context.Context, b [32]byte, post, comment string) (PostResponse, error) {
	if !dmUUID(post) || (comment != "" && !dmUUID(comment)) {
		return PostResponse{}, postError("MALFORMED_REQUEST", 400)
	}
	return c.withDMSession(ctx, b, func(tx pgx.Tx, a uuid.UUID, _ AuthorizationDecision, _ restriction) (any, error) {
		var peer string
		e := tx.QueryRow(ctx, `SELECT b.identity_id::text FROM c_posts.posts p JOIN c_posts.post_identity_bindings b ON b.post_id=p.post_id AND b.account_id=p.owner_account_id WHERE p.post_id=$1 AND p.visibility='PUBLISHED' AND NOT p.moderation_hidden`, post).Scan(&peer)
		if errors.Is(e, pgx.ErrNoRows) {
			return nil, postError("COMMAND_CONFLICT", 409)
		}
		if e != nil {
			return nil, e
		}
		if comment != "" {
			e = tx.QueryRow(ctx, `SELECT t.identity_id::text FROM c_comments.tasks t WHERE t.comment_id=$1 AND t.post_id=$2 AND t.deleted_at IS NULL AND NOT t.moderation_hidden AND EXISTS(SELECT 1 FROM c_comments.attempts x WHERE x.task_id=t.task_id AND x.state='PUBLISHED')`, comment, post).Scan(&peer)
			if errors.Is(e, pgx.ErrNoRows) {
				return nil, postError("COMMAND_CONFLICT", 409)
			}
			if e != nil {
				return nil, e
			}
		}
		r := DMContact{PeerID: peer}
		e = tx.QueryRow(ctx, `SELECT nickname,account_id=$2 FROM public.community_identities WHERE identity_id=$1 AND deleted_at IS NULL`, peer, a).Scan(&r.PeerName, &r.Self)
		if errors.Is(e, pgx.ErrNoRows) {
			return nil, postError("COMMAND_CONFLICT", 409)
		}
		if e != nil {
			return nil, e
		}
		e = tx.QueryRow(ctx, `SELECT identity_id::text FROM c_posts.post_identity_bindings WHERE account_id=$1 AND post_id=$2`, a, post).Scan(&r.BoundIdentityID)
		if errors.Is(e, pgx.ErrNoRows) {
			e = nil
		}
		return r, e
	})
}

func dmUUID(v string) bool {
	u, e := uuid.Parse(v)
	return e == nil && u != uuid.Nil && u.String() == v
}
func (in DMTextIntent) Validate() error {
	n, e := posts.CountGraphemes(in.Text)
	if !dmUUID(in.IdentityID) || !dmUUID(in.PeerID) || in.IdentityID == in.PeerID || in.Attempt < 1 || in.Attempt > 1000 || e != nil || n > 4000 || len(in.Text) > 16384 || strings.TrimSpace(in.Text) == "" {
		return postError("MALFORMED_REQUEST", 400)
	}
	if in.ConversationID != "" {
		if !dmUUID(in.ConversationID) || in.SourcePostID != "" || in.SourceCommentID != "" {
			return postError("MALFORMED_REQUEST", 400)
		}
	} else if !dmUUID(in.SourcePostID) || (in.SourceCommentID != "" && !dmUUID(in.SourceCommentID)) {
		return postError("MALFORMED_REQUEST", 400)
	}
	return nil
}
func (c *Community) withDMSession(ctx context.Context, b [32]byte, f func(pgx.Tx, uuid.UUID, AuthorizationDecision, restriction) (any, error)) (PostResponse, error) {
	if !c.DirectMessagesEnabled() {
		return PostResponse{}, ErrAuthorizationUnavailable
	}
	return c.withPostSession(ctx, b, f)
}
func dmReceipt(ctx context.Context, tx pgx.Tx, a uuid.UUID, id string) (DMReceipt, []byte, error) {
	var r DMReceipt
	var fp []byte
	e := tx.QueryRow(ctx, `SELECT state,attempt,error_code,COALESCE(message_id::text,''),COALESCE(conversation_id::text,''),COALESCE(sequence,0),accepted_at,fingerprint FROM c_dm.commands WHERE owner_account=$1 AND command_id=$2`, a, id).Scan(&r.State, &r.Attempt, &r.ErrorCode, &r.MessageID, &r.ConversationID, &r.Sequence, &r.AcceptedAt, &fp)
	return r, fp, e
}
func (c *Community) GetDMCommand(ctx context.Context, b [32]byte, id string) (PostResponse, error) {
	if !dmUUID(id) {
		return PostResponse{}, postError("MALFORMED_REQUEST", 400)
	}
	return c.withDMSession(ctx, b, func(tx pgx.Tx, a uuid.UUID, _ AuthorizationDecision, _ restriction) (any, error) {
		r, _, e := dmReceipt(ctx, tx, a, id)
		if errors.Is(e, pgx.ErrNoRows) {
			return DMReceipt{State: "ABSENT"}, nil
		}
		return r, e
	})
}
func (c *Community) SendDMText(ctx context.Context, b [32]byte, id string, in DMTextIntent) (PostResponse, error) {
	if !dmUUID(id) {
		return PostResponse{}, postError("MALFORMED_REQUEST", 400)
	}
	if e := in.Validate(); e != nil {
		return PostResponse{}, e
	}
	material := in
	material.Attempt = 0
	encoded, _ := json.Marshal(material)
	mac := hmac.New(sha256.New, c.requestKey[:])
	mac.Write([]byte("HNUHOLE/DM-INTENT/V1\x00"))
	mac.Write(encoded)
	fp := mac.Sum(nil)
	return c.withDMSession(ctx, b, func(tx pgx.Tx, a uuid.UUID, d AuthorizationDecision, m restriction) (any, error) {
		old, prior, e := dmReceipt(ctx, tx, a, id)
		if e == nil {
			if !hmac.Equal(fp, prior) {
				return nil, postError("COMMAND_CONFLICT", 409)
			}
			if old.State == "SENT" || in.Attempt <= old.Attempt {
				return old, nil
			}
			if in.Attempt != old.Attempt+1 {
				return nil, postError("COMMAND_CONFLICT", 409)
			}
		} else if !errors.Is(e, pgx.ErrNoRows) {
			return nil, e
		} else if in.Attempt != 1 {
			return nil, postError("COMMAND_CONFLICT", 409)
		}
		reject := func(code string) (any, error) {
			_, e := tx.Exec(ctx, `INSERT INTO c_dm.commands(owner_account,command_id,fingerprint,attempt,state,error_code) VALUES($1,$2,$3,$4,'FAILED',$5) ON CONFLICT(owner_account,command_id) DO UPDATE SET attempt=EXCLUDED.attempt,state='FAILED',error_code=EXCLUDED.error_code`, a, id, fp, in.Attempt, code)
			return DMReceipt{State: "FAILED", Attempt: in.Attempt, ErrorCode: code}, e
		}
		if mutedAt(m, d.TrustedAt) {
			return reject("POSTING_RESTRICTED")
		}
		var active bool
		if e = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM public.community_identities i JOIN c_auth.accounts a USING(account_id) WHERE i.identity_id=$1 AND i.account_id=$2 AND i.deleted_at IS NULL AND a.state='ACTIVE')`, in.IdentityID, a).Scan(&active); e != nil {
			return nil, e
		}
		if !active {
			return reject("IDENTITY_UNAVAILABLE")
		}
		// Lock the peer identity, never the peer account: avoids opposite-direction
		// account-lock deadlocks and serializes identity deletion with acceptance.
		var peerAccount uuid.UUID
		var deleted *time.Time
		e = tx.QueryRow(ctx, `SELECT account_id,deleted_at FROM public.community_identities WHERE identity_id=$1 FOR SHARE`, in.PeerID).Scan(&peerAccount, &deleted)
		if errors.Is(e, pgx.ErrNoRows) || e == nil && (deleted != nil || peerAccount == a) {
			return reject("CONTACT_UNAVAILABLE")
		}
		if e != nil {
			return nil, e
		}
		var peerActive bool
		if e = tx.QueryRow(ctx, `SELECT state='ACTIVE' FROM c_auth.accounts WHERE account_id=$1`, peerAccount).Scan(&peerActive); e != nil {
			return nil, e
		}
		if !peerActive {
			return reject("CONTACT_UNAVAILABLE")
		}
		var outstanding int
		if e = tx.QueryRow(ctx, `SELECT count(*) FROM c_dm.messages m JOIN public.community_identities i ON i.identity_id=m.sender WHERE i.account_id=$1 AND NOT m.acknowledged`, a).Scan(&outstanding); e != nil {
			return nil, e
		}
		if outstanding >= 4096 {
			return reject("PENDING_LIMIT")
		}
		pair := []string{in.IdentityID, in.PeerID}
		sort.Strings(pair)
		conv := in.ConversationID
		if conv == "" {
			var author string
			var visible bool
			e = tx.QueryRow(ctx, `SELECT b.identity_id::text,p.visibility='PUBLISHED' AND NOT p.moderation_hidden FROM c_posts.posts p JOIN c_posts.post_identity_bindings b ON b.post_id=p.post_id AND b.account_id=p.owner_account_id WHERE p.post_id=$1 FOR SHARE OF p`, in.SourcePostID).Scan(&author, &visible)
			if errors.Is(e, pgx.ErrNoRows) || e == nil && !visible {
				return reject("CONTACT_UNAVAILABLE")
			}
			if e != nil {
				return nil, e
			}
			if in.SourceCommentID != "" {
				e = tx.QueryRow(ctx, `SELECT t.identity_id::text FROM c_comments.tasks t WHERE t.comment_id=$1 AND t.post_id=$2 AND t.deleted_at IS NULL AND NOT t.moderation_hidden AND EXISTS(SELECT 1 FROM c_comments.attempts x WHERE x.task_id=t.task_id AND x.state='PUBLISHED') FOR SHARE`, in.SourceCommentID, in.SourcePostID).Scan(&author)
				if errors.Is(e, pgx.ErrNoRows) {
					return reject("CONTACT_UNAVAILABLE")
				}
				if e != nil {
					return nil, e
				}
			}
			if author != in.PeerID {
				return reject("CONTACT_UNAVAILABLE")
			}
			var bound string
			e = tx.QueryRow(ctx, `SELECT identity_id::text FROM c_posts.post_identity_bindings WHERE account_id=$1 AND post_id=$2`, a, in.SourcePostID).Scan(&bound)
			if e == nil && bound != in.IdentityID {
				return reject("POST_IDENTITY_BOUND")
			}
			if e != nil && !errors.Is(e, pgx.ErrNoRows) {
				return nil, e
			}
			// Unique identity pair is independent of the source post and direction.
			_, e = tx.Exec(ctx, `INSERT INTO c_dm.conversations(conversation_id,low_identity,high_identity,source_post) VALUES($1,$2,$3,$4) ON CONFLICT(low_identity,high_identity) DO NOTHING`, uuid.New(), pair[0], pair[1], in.SourcePostID)
			if e != nil {
				return nil, e
			}
			e = tx.QueryRow(ctx, `SELECT conversation_id::text FROM c_dm.conversations WHERE low_identity=$1 AND high_identity=$2`, pair[0], pair[1]).Scan(&conv)
			if e != nil {
				return nil, e
			}
		}
		var low, high string
		var lowSent, highSent bool
		var seq int64
		e = tx.QueryRow(ctx, `SELECT low_identity::text,high_identity::text,low_sent,high_sent,sequence FROM c_dm.conversations WHERE conversation_id=$1 FOR UPDATE`, conv).Scan(&low, &high, &lowSent, &highSent, &seq)
		if errors.Is(e, pgx.ErrNoRows) || e == nil && (low != pair[0] || high != pair[1]) {
			return reject("CONTACT_UNAVAILABLE")
		}
		if e != nil {
			return nil, e
		}
		ownSent, otherSent := lowSent, highSent
		if in.IdentityID == high {
			ownSent, otherSent = highSent, lowSent
		}
		if ownSent && !otherSent {
			return reject("WAITING_FOR_REPLY")
		}
		var pending int
		if e = tx.QueryRow(ctx, `SELECT count(*) FROM c_dm.messages WHERE conversation_id=$1 AND NOT acknowledged`, conv).Scan(&pending); e != nil {
			return nil, e
		}
		if pending >= 4096 {
			return reject("PENDING_LIMIT")
		}
		if in.SourcePostID != "" {
			binding, bindErr := tx.Exec(ctx, `INSERT INTO c_posts.post_identity_bindings(account_id,post_id,identity_id,bound_at) VALUES($1,$2,$3,$4) ON CONFLICT(account_id,post_id) DO NOTHING`, a, in.SourcePostID, in.IdentityID, d.TrustedAt)
			e = bindErr
			if e != nil {
				return nil, e
			}
			if binding.RowsAffected() == 1 {
				if _, e = tx.Exec(ctx, `INSERT INTO c_dm.binding_acceptances VALUES($1,$2,$3,$4,$5)`, a, in.SourcePostID, in.IdentityID, id, d.TrustedAt); e != nil {
					return nil, e
				}
			}
		}
		seq++
		msg := uuid.NewString()
		at := d.TrustedAt.UTC()
		_, e = tx.Exec(ctx, `UPDATE c_dm.conversations SET sequence=$2,low_sent=low_sent OR low_identity=$3,high_sent=high_sent OR high_identity=$3 WHERE conversation_id=$1`, conv, seq, in.IdentityID)
		if e != nil {
			return nil, e
		}
		_, e = tx.Exec(ctx, `INSERT INTO c_dm.messages(message_id,conversation_id,sequence,sender,recipient,body,accepted_at) VALUES($1,$2,$3,$4,$5,$6,$7)`, msg, conv, seq, in.IdentityID, in.PeerID, in.Text, at)
		if e != nil {
			return nil, e
		}
		_, e = tx.Exec(ctx, `INSERT INTO c_dm.commands(owner_account,command_id,fingerprint,attempt,state,message_id,conversation_id,sequence,accepted_at) VALUES($1,$2,$3,$4,'SENT',$5,$6,$7,$8) ON CONFLICT(owner_account,command_id) DO UPDATE SET attempt=EXCLUDED.attempt,state='SENT',error_code='',message_id=EXCLUDED.message_id,conversation_id=EXCLUDED.conversation_id,sequence=EXCLUDED.sequence,accepted_at=EXCLUDED.accepted_at`, a, id, fp, in.Attempt, msg, conv, seq, at)
		return DMReceipt{State: "SENT", Attempt: in.Attempt, MessageID: msg, ConversationID: conv, Sequence: seq, AcceptedAt: &at}, e
	})
}

func (c *Community) ReadDMDirectory(ctx context.Context, b [32]byte, identity, after string) (PostResponse, error) {
	if !dmUUID(identity) || (after != "" && !dmUUID(after)) {
		return PostResponse{}, postError("MALFORMED_REQUEST", 400)
	}
	return c.withDMSession(ctx, b, func(tx pgx.Tx, a uuid.UUID, _ AuthorizationDecision, m restriction) (any, error) {
		items := make([]DMConversation, 0)
		rows, e := tx.Query(ctx, `SELECT c.conversation_id::text,i.identity_id::text,p.identity_id::text,CASE WHEN p.deleted_at IS NULL THEN p.nickname ELSE '已删除身份' END,c.source_post::text,c.sequence,(SELECT count(*) FROM c_dm.messages x WHERE x.conversation_id=c.conversation_id AND x.recipient=i.identity_id AND NOT x.read),CASE WHEN c.low_identity=i.identity_id THEN c.low_sent AND NOT c.high_sent ELSE c.high_sent AND NOT c.low_sent END,p.deleted_at IS NULL FROM c_dm.conversations c JOIN public.community_identities i ON i.identity_id IN(c.low_identity,c.high_identity) JOIN public.community_identities p ON p.identity_id=CASE WHEN i.identity_id=c.low_identity THEN c.high_identity ELSE c.low_identity END WHERE i.account_id=$1 AND i.identity_id=$2 AND i.deleted_at IS NULL AND ($3='' OR c.conversation_id>NULLIF($3,'')::uuid) ORDER BY c.conversation_id LIMIT 100`, a, identity, after)
		if e != nil {
			return nil, e
		}
		defer rows.Close()
		for rows.Next() {
			var v DMConversation
			if e = rows.Scan(&v.ID, &v.IdentityID, &v.PeerID, &v.PeerName, &v.SourcePostID, &v.Sequence, &v.Unread, &v.Waiting, &v.CanSend); e != nil {
				return nil, e
			}
			items = append(items, v)
		}
		return DMDirectory{Items: items}, rows.Err()
	})
}
func (c *Community) PullDM(ctx context.Context, b [32]byte) (PostResponse, error) {
	return c.withDMSession(ctx, b, func(tx pgx.Tx, a uuid.UUID, _ AuthorizationDecision, _ restriction) (any, error) {
		items := make([]DMDelivery, 0)
		rows, e := tx.Query(ctx, `SELECT m.message_id::text,m.conversation_id::text,m.recipient::text,m.sender::text,m.sequence,m.body,m.accepted_at FROM c_dm.messages m JOIN public.community_identities i ON i.identity_id=m.recipient WHERE i.account_id=$1 AND i.deleted_at IS NULL AND NOT m.acknowledged AND m.kind='TEXT' AND NOT m.retracted ORDER BY m.accepted_at,m.conversation_id,m.sequence LIMIT 100`, a)
		if e != nil {
			return nil, e
		}
		defer rows.Close()
		for rows.Next() {
			var v DMDelivery
			if e = rows.Scan(&v.MessageID, &v.ConversationID, &v.IdentityID, &v.SenderID, &v.Sequence, &v.Text, &v.AcceptedAt); e != nil {
				return nil, e
			}
			items = append(items, v)
		}
		return DMPending{Items: items}, rows.Err()
	})
}

// ACK is item-based: no cursor can accidentally acknowledge an unseen item.
// Read uses the same explicit ids and additionally requires prior durable ACK.
func (c *Community) AcknowledgeDM(ctx context.Context, b [32]byte, ids []string, read bool) (PostResponse, error) {
	if len(ids) == 0 || len(ids) > 100 {
		return PostResponse{}, postError("MALFORMED_REQUEST", 400)
	}
	for _, id := range ids {
		if !dmUUID(id) {
			return PostResponse{}, postError("MALFORMED_REQUEST", 400)
		}
	}
	return c.withDMSession(ctx, b, func(tx pgx.Tx, a uuid.UUID, _ AuthorizationDecision, _ restriction) (any, error) {
		// Serialize ACK/read with deletion/retraction and the directory revision
		// trigger. Always acquire conversation locks before message row locks.
		rows, e := tx.Query(ctx, `SELECT conversation_id FROM c_dm.conversations WHERE conversation_id IN(SELECT conversation_id FROM c_dm.messages WHERE message_id=ANY($1::uuid[])) ORDER BY conversation_id FOR UPDATE`, ids)
		if e != nil {
			return nil, e
		}
		for rows.Next() {
			var ignored uuid.UUID
			if e = rows.Scan(&ignored); e != nil {
				rows.Close()
				return nil, e
			}
		}
		e = rows.Err()
		rows.Close()
		if e != nil {
			return nil, e
		}
		var count int
		e = tx.QueryRow(ctx, `SELECT count(DISTINCT m.message_id) FROM c_dm.messages m JOIN public.community_identities i ON i.identity_id=m.recipient WHERE m.message_id=ANY($1::uuid[]) AND i.account_id=$2 AND i.deleted_at IS NULL AND (NOT $3 OR m.acknowledged)`, ids, a, read).Scan(&count)
		if e != nil {
			return nil, e
		}
		unique := map[string]bool{}
		for _, id := range ids {
			unique[id] = true
		}
		if count != len(unique) {
			return nil, postError("COMMAND_CONFLICT", 409)
		}
		if read {
			_, e = tx.Exec(ctx, `UPDATE c_dm.messages SET read=true WHERE message_id=ANY($1::uuid[])`, ids)
		} else {
			_, e = tx.Exec(ctx, `UPDATE c_dm.messages SET acknowledged=true,body=NULL WHERE message_id=ANY($1::uuid[])`, ids)
			if e == nil {
				_, e = tx.Exec(ctx, `UPDATE c_dm.media SET bytes=NULL WHERE message_id=ANY($1::uuid[])`, ids)
			}
		}
		return DMApplied{State: "APPLIED"}, e
	})
}
