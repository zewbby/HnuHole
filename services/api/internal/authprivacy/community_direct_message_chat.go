package authprivacy

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/postmedia"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
)

type DMChatConversation struct {
	DMConversation
	SourceTitle       string `json:"sourceTitle"`
	Version           int64  `json:"version"`
	SettingsVersion   int64  `json:"settingsVersion"`
	Pinned            bool   `json:"pinned"`
	Muted             bool   `json:"muted"`
	Hidden            bool   `json:"hidden"`
	Deleted           bool   `json:"deleted"`
	DeletedThrough    int64  `json:"deletedThrough"`
	Note              string `json:"note"`
	UnavailableUnread int64  `json:"unavailableUnread"`
}
type DMChatDirectory struct {
	Items []DMChatConversation `json:"items"`
}
type DMChatDelivery struct {
	DMDelivery
	Kind      string               `json:"kind"`
	GroupID   string               `json:"groupId"`
	Position  int                  `json:"position"`
	GroupSize int                  `json:"groupSize"`
	Media     *postmedia.Selection `json:"media"`
}
type DMChatPending struct {
	Items []DMChatDelivery `json:"items"`
}
type DMChatOperation struct {
	IdentityID      string `json:"identityId"`
	ConversationID  string `json:"conversationId"`
	Operation       string `json:"operation"`
	ExpectedVersion int64  `json:"expectedVersion"`
	Pinned          bool   `json:"pinned"`
	Muted           bool   `json:"muted"`
	Note            string `json:"note"`
	ThroughSequence int64  `json:"throughSequence"`
	MessageID       string `json:"messageId"`
}
type DMChatResult struct {
	State           string `json:"state"`
	ErrorCode       string `json:"errorCode"`
	ConversationID  string `json:"conversationId"`
	Version         int64  `json:"version"`
	SettingsVersion int64  `json:"settingsVersion"`
	DeletedThrough  int64  `json:"deletedThrough"`
	MessageID       string `json:"messageId"`
}
type DMControl struct {
	EventID         string    `json:"eventId"`
	Sequence        int64     `json:"sequence"`
	IdentityID      string    `json:"identityId"`
	ConversationID  string    `json:"conversationId"`
	MessageID       string    `json:"messageId"`
	MessageSequence int64     `json:"messageSequence"`
	Type            string    `json:"type"`
	CreatedAt       time.Time `json:"createdAt"`
}
type DMControls struct {
	Items []DMControl `json:"items"`
	Next  int64       `json:"next"`
}

func (c *Community) dmFingerprint(domain string, v any) []byte {
	data, _ := json.Marshal(v)
	h := hmac.New(sha256.New, c.requestKey[:])
	h.Write([]byte(domain))
	h.Write(data)
	return h.Sum(nil)
}

// Caller account/session is already locked. Conversation always precedes its
// message/settings rows; peer account locks are deliberately never acquired.
func dmOwnConversation(ctx context.Context, tx pgx.Tx, a uuid.UUID, identity, conv string) (int64, error) {
	var exists bool
	if e := tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM public.community_identities WHERE identity_id=$1 AND account_id=$2 AND deleted_at IS NULL)`, identity, a).Scan(&exists); e != nil {
		return 0, e
	}
	if !exists {
		return 0, postError("COMMAND_CONFLICT", 409)
	}
	var seq int64
	e := tx.QueryRow(ctx, `SELECT sequence FROM c_dm.conversations WHERE conversation_id=$1 AND $2 IN(low_identity,high_identity) FOR UPDATE`, conv, identity).Scan(&seq)
	if errors.Is(e, pgx.ErrNoRows) {
		return 0, postError("COMMAND_CONFLICT", 409)
	}
	return seq, e
}
func (c *Community) ReadDMChatDirectory(ctx context.Context, b [32]byte, identity, after string) (PostResponse, error) {
	if !dmUUID(identity) || (after != "" && !dmUUID(after)) {
		return PostResponse{}, postError("MALFORMED_REQUEST", 400)
	}
	return c.withDMSession(ctx, b, func(tx pgx.Tx, a uuid.UUID, _ AuthorizationDecision, _ restriction) (any, error) {
		items := make([]DMChatConversation, 0)
		rows, e := tx.Query(ctx, `SELECT c.conversation_id::text,i.identity_id::text,p.identity_id::text,CASE WHEN p.deleted_at IS NULL THEN p.nickname ELSE '已删除身份' END,c.source_post::text,c.sequence,
   (SELECT count(*) FROM c_dm.messages x WHERE x.conversation_id=c.conversation_id AND x.recipient=i.identity_id AND NOT x.read AND NOT x.retracted AND x.sequence>COALESCE(s.deleted_through,0)),
   CASE WHEN c.low_identity=i.identity_id THEN c.low_sent AND NOT c.high_sent ELSE c.high_sent AND NOT c.low_sent END,
   p.deleted_at IS NULL AND pa.state='ACTIVE',c.revision,COALESCE(s.version,0),COALESCE(s.pinned,false),COALESCE(s.muted,false),COALESCE(s.hidden_through,0)>=c.sequence AND COALESCE(s.hidden_through,0)>0,c.sequence<=COALESCE(s.deleted_through,0),COALESCE(s.deleted_through,0),COALESCE(s.note,''),CASE WHEN source.visibility='PUBLISHED' AND NOT source.moderation_hidden THEN COALESCE(source_content.title,'') ELSE '' END,
   (SELECT count(*) FROM c_dm.messages x WHERE x.conversation_id=c.conversation_id AND x.recipient=i.identity_id AND x.acknowledged AND NOT x.read AND NOT x.retracted AND x.sequence>COALESCE(s.deleted_through,0))
   FROM c_dm.conversations c JOIN public.community_identities i ON i.identity_id IN(c.low_identity,c.high_identity)
   JOIN public.community_identities p ON p.identity_id=CASE WHEN i.identity_id=c.low_identity THEN c.high_identity ELSE c.low_identity END
   JOIN c_auth.accounts pa ON pa.account_id=p.account_id LEFT JOIN c_posts.posts source ON source.post_id=c.source_post LEFT JOIN c_posts.publication_tasks source_task ON source_task.post_id=source.post_id LEFT JOIN c_posts.attempt_contents source_content ON source_content.task_id=source_task.task_id AND source_content.version=source.published_attempt_version AND source_content.erased_at IS NULL LEFT JOIN c_dm.settings s ON s.conversation_id=c.conversation_id AND s.identity_id=i.identity_id
   WHERE i.account_id=$1 AND i.identity_id=$2 AND i.deleted_at IS NULL AND ($3='' OR c.conversation_id>NULLIF($3,'')::uuid) ORDER BY c.conversation_id LIMIT 100`, a, identity, after)
		if e != nil {
			return nil, e
		}
		defer rows.Close()
		for rows.Next() {
			var v DMChatConversation
			if e = rows.Scan(&v.ID, &v.IdentityID, &v.PeerID, &v.PeerName, &v.SourcePostID, &v.Sequence, &v.Unread, &v.Waiting, &v.CanSend, &v.Version, &v.SettingsVersion, &v.Pinned, &v.Muted, &v.Hidden, &v.Deleted, &v.DeletedThrough, &v.Note, &v.SourceTitle, &v.UnavailableUnread); e != nil {
				return nil, e
			}
			items = append(items, v)
		}
		return DMChatDirectory{Items: items}, rows.Err()
	})
}
func (c *Community) PullDMChat(ctx context.Context, b [32]byte) (PostResponse, error) {
	return c.withDMSession(ctx, b, func(tx pgx.Tx, a uuid.UUID, _ AuthorizationDecision, _ restriction) (any, error) {
		items := make([]DMChatDelivery, 0)
		rows, e := tx.Query(ctx, `SELECT m.message_id::text,m.conversation_id::text,m.recipient::text,m.sender::text,m.sequence,m.body,m.accepted_at,m.kind,COALESCE(x.group_id::text,''),COALESCE(x.position,0),COALESCE(g.size,0),x.selection FROM c_dm.messages m JOIN public.community_identities i ON i.identity_id=m.recipient LEFT JOIN c_dm.media x USING(message_id) LEFT JOIN c_dm.image_groups g ON g.sender=x.sender AND g.group_id=x.group_id LEFT JOIN c_dm.settings s ON s.conversation_id=m.conversation_id AND s.identity_id=m.recipient WHERE i.account_id=$1 AND i.deleted_at IS NULL AND NOT m.acknowledged AND NOT m.retracted AND m.sequence>COALESCE(s.deleted_through,0) ORDER BY m.accepted_at,m.conversation_id,m.sequence LIMIT 100`, a)
		if e != nil {
			return nil, e
		}
		defer rows.Close()
		for rows.Next() {
			var v DMChatDelivery
			var raw []byte
			if e = rows.Scan(&v.MessageID, &v.ConversationID, &v.IdentityID, &v.SenderID, &v.Sequence, &v.Text, &v.AcceptedAt, &v.Kind, &v.GroupID, &v.Position, &v.GroupSize, &raw); e != nil {
				return nil, e
			}
			if raw != nil {
				v.Media = new(postmedia.Selection)
				if e = json.Unmarshal(raw, v.Media); e != nil {
					return nil, e
				}
			}
			items = append(items, v)
		}
		return DMChatPending{Items: items}, rows.Err()
	})
}
func (c *Community) GetDMChatOperation(ctx context.Context, b [32]byte, id string) (PostResponse, error) {
	if !dmUUID(id) {
		return PostResponse{}, postError("MALFORMED_REQUEST", 400)
	}
	return c.withDMSession(ctx, b, func(tx pgx.Tx, a uuid.UUID, _ AuthorizationDecision, _ restriction) (any, error) {
		var raw []byte
		e := tx.QueryRow(ctx, `SELECT result FROM c_dm.operations WHERE owner_account=$1 AND operation_id=$2`, a, id).Scan(&raw)
		if errors.Is(e, pgx.ErrNoRows) {
			return DMChatResult{State: "ABSENT"}, nil
		}
		if e != nil {
			return nil, e
		}
		var r DMChatResult
		e = json.Unmarshal(raw, &r)
		return r, e
	})
}
func (c *Community) ExecuteDMChatOperation(ctx context.Context, b [32]byte, id string, in DMChatOperation) (PostResponse, error) {
	n, e := posts.CountGraphemes(in.Note)
	if !dmUUID(id) || !dmUUID(in.IdentityID) || !dmUUID(in.ConversationID) || in.ExpectedVersion < 0 || in.ThroughSequence < 0 || e != nil || n > 100 || len(in.Note) > 400 {
		return PostResponse{}, postError("MALFORMED_REQUEST", 400)
	}
	switch in.Operation {
	case "SETTINGS", "HIDE", "RESTORE", "DELETE":
	case "RETRACT":
		if !dmUUID(in.MessageID) {
			return PostResponse{}, postError("MALFORMED_REQUEST", 400)
		}
	default:
		return PostResponse{}, postError("MALFORMED_REQUEST", 400)
	}
	fp := c.dmFingerprint("HNUHOLE/DM-CHAT-OP/V1\x00", in)
	return c.withDMSession(ctx, b, func(tx pgx.Tx, a uuid.UUID, d AuthorizationDecision, _ restriction) (any, error) {
		var raw, prior []byte
		e := tx.QueryRow(ctx, `SELECT fingerprint,result FROM c_dm.operations WHERE owner_account=$1 AND operation_id=$2`, a, id).Scan(&prior, &raw)
		if e == nil {
			if !hmac.Equal(fp, prior) {
				return nil, postError("COMMAND_CONFLICT", 409)
			}
			var r DMChatResult
			e = json.Unmarshal(raw, &r)
			return r, e
		}
		if !errors.Is(e, pgx.ErrNoRows) {
			return nil, e
		}
		seq, e := dmOwnConversation(ctx, tx, a, in.IdentityID, in.ConversationID)
		if e != nil {
			return nil, e
		}
		r := DMChatResult{State: "APPLIED", ConversationID: in.ConversationID, MessageID: in.MessageID}
		if _, e = tx.Exec(ctx, `INSERT INTO c_dm.settings(conversation_id,identity_id) VALUES($1,$2) ON CONFLICT DO NOTHING`, in.ConversationID, in.IdentityID); e != nil {
			return nil, e
		}
		if e = tx.QueryRow(ctx, `SELECT version,deleted_through FROM c_dm.settings WHERE conversation_id=$1 AND identity_id=$2`, in.ConversationID, in.IdentityID).Scan(&r.SettingsVersion, &r.DeletedThrough); e != nil {
			return nil, e
		}
		reject := func(code string) { r.State = "REJECTED"; r.ErrorCode = code }
		if (in.Operation == "SETTINGS" || in.Operation == "HIDE" || in.Operation == "RESTORE") && in.ExpectedVersion != r.SettingsVersion {
			reject("VERSION_CONFLICT")
		} else {
			switch in.Operation {
			case "SETTINGS":
				_, e = tx.Exec(ctx, `UPDATE c_dm.settings SET version=version+1,pinned=$3,muted=$4,note=$5 WHERE conversation_id=$1 AND identity_id=$2`, in.ConversationID, in.IdentityID, in.Pinned, in.Muted, in.Note)
			case "HIDE":
				_, e = tx.Exec(ctx, `UPDATE c_dm.settings SET version=version+1,hidden_through=$3 WHERE conversation_id=$1 AND identity_id=$2`, in.ConversationID, in.IdentityID, seq)
			case "RESTORE":
				_, e = tx.Exec(ctx, `UPDATE c_dm.settings SET version=version+1,hidden_through=0 WHERE conversation_id=$1 AND identity_id=$2`, in.ConversationID, in.IdentityID)
			case "DELETE":
				if in.ThroughSequence > seq {
					reject("COMMAND_CONFLICT")
					break
				}
				_, e = tx.Exec(ctx, `UPDATE c_dm.settings SET version=version+1,deleted_through=GREATEST(deleted_through,$3) WHERE conversation_id=$1 AND identity_id=$2`, in.ConversationID, in.IdentityID, in.ThroughSequence)
				if e == nil {
					_, e = tx.Exec(ctx, `UPDATE c_dm.messages SET acknowledged=true,read=true,body=NULL WHERE conversation_id=$1 AND recipient=$2 AND sequence<=$3`, in.ConversationID, in.IdentityID, in.ThroughSequence)
				}
				if e == nil {
					_, e = tx.Exec(ctx, `UPDATE c_dm.media x SET bytes=NULL FROM c_dm.messages m WHERE x.message_id=m.message_id AND m.conversation_id=$1 AND m.recipient=$2 AND m.sequence<=$3`, in.ConversationID, in.IdentityID, in.ThroughSequence)
				}
			case "RETRACT":
				var sender, recipient string
				var accepted time.Time
				var retracted bool
				var msgseq int64
				e = tx.QueryRow(ctx, `SELECT sender::text,recipient::text,accepted_at,retracted,sequence FROM c_dm.messages WHERE conversation_id=$1 AND message_id=$2 FOR UPDATE`, in.ConversationID, in.MessageID).Scan(&sender, &recipient, &accepted, &retracted, &msgseq)
				if errors.Is(e, pgx.ErrNoRows) {
					e = nil
					reject("COMMAND_CONFLICT")
					break
				}
				if e != nil {
					break
				}
				if sender != in.IdentityID {
					reject("COMMAND_CONFLICT")
					break
				}
				if retracted {
					break
				}
				if d.TrustedAt.Before(accepted) || !d.TrustedAt.Before(accepted.Add(2*time.Minute)) {
					reject("RETRACT_EXPIRED")
					break
				}
				_, e = tx.Exec(ctx, `UPDATE c_dm.messages SET retracted=true,acknowledged=true,read=true,body=NULL WHERE message_id=$1`, in.MessageID)
				if e == nil {
					_, e = tx.Exec(ctx, `UPDATE c_dm.media SET bytes=NULL WHERE message_id=$1`, in.MessageID)
				}
				// Global transaction lock prevents control sequence/commit-order inversion;
				// otherwise a cursor could skip a lower sequence committed later.
				if e == nil {
					_, e = tx.Exec(ctx, `SELECT pg_advisory_xact_lock(7223002)`)
				}
				if e == nil {
					_, e = tx.Exec(ctx, `INSERT INTO c_dm.controls(event_id,identity_id,conversation_id,message_id,message_sequence,created_at) VALUES($1,$2,$3,$4,$5,$6),($7,$8,$3,$4,$5,$6)`, uuid.New(), sender, in.ConversationID, in.MessageID, msgseq, d.TrustedAt, uuid.New(), recipient)
				}
			}
		}
		if e != nil {
			return nil, e
		}
		if e = tx.QueryRow(ctx, `SELECT c.revision,s.version,s.deleted_through FROM c_dm.conversations c JOIN c_dm.settings s USING(conversation_id) WHERE c.conversation_id=$1 AND s.identity_id=$2`, in.ConversationID, in.IdentityID).Scan(&r.Version, &r.SettingsVersion, &r.DeletedThrough); e != nil {
			return nil, e
		}
		raw, e = json.Marshal(r)
		if e != nil {
			return nil, e
		}
		_, e = tx.Exec(ctx, `INSERT INTO c_dm.operations(owner_account,operation_id,fingerprint,result) VALUES($1,$2,$3,$4)`, a, id, fp, raw)
		return r, e
	})
}
func (c *Community) PullDMControls(ctx context.Context, b [32]byte, after int64) (PostResponse, error) {
	if after < 0 {
		return PostResponse{}, postError("MALFORMED_REQUEST", 400)
	}
	return c.withDMSession(ctx, b, func(tx pgx.Tx, a uuid.UUID, _ AuthorizationDecision, _ restriction) (any, error) {
		r := DMControls{Items: make([]DMControl, 0), Next: after}
		rows, e := tx.Query(ctx, `SELECT x.event_id::text,x.sequence,x.identity_id::text,x.conversation_id::text,x.message_id::text,x.message_sequence,x.created_at FROM c_dm.controls x JOIN public.community_identities i USING(identity_id) WHERE i.account_id=$1 AND i.deleted_at IS NULL AND x.sequence>$2 ORDER BY x.sequence LIMIT 100`, a, after)
		if e != nil {
			return nil, e
		}
		defer rows.Close()
		for rows.Next() {
			var v DMControl
			v.Type = "RETRACTED"
			if e = rows.Scan(&v.EventID, &v.Sequence, &v.IdentityID, &v.ConversationID, &v.MessageID, &v.MessageSequence, &v.CreatedAt); e != nil {
				return nil, e
			}
			r.Items = append(r.Items, v)
			r.Next = v.Sequence
		}
		return r, rows.Err()
	})
}
