package authprivacy

import (
	"context"
	"crypto/hmac"
	"encoding/base64"
	"encoding/json"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/postmedia"
)

type DMImageIntent struct {
	IdentityID     string `json:"identityId"`
	PeerID         string `json:"peerId"`
	ConversationID string `json:"conversationId"`
	GroupID        string `json:"groupId"`
	Position       int    `json:"position"`
	GroupSize      int    `json:"groupSize"`
	postmedia.Selection
	Data    string `json:"data"`
	Attempt int    `json:"attempt"`
}
type DMPrivateMedia struct {
	MessageID string `json:"messageId"`
	postmedia.Selection
	Data string `json:"data"`
}

func (c *Community) SendDMImage(ctx context.Context, b [32]byte, id string, in DMImageIntent) (PostResponse, error) {
	if !dmUUID(id) || !dmUUID(in.IdentityID) || !dmUUID(in.PeerID) || in.IdentityID == in.PeerID || !dmUUID(in.ConversationID) || !dmUUID(in.GroupID) || in.GroupSize < 1 || in.GroupSize > 9 || in.Position < 0 || in.Position >= in.GroupSize || in.Attempt < 1 || in.Attempt > 1000 || postmedia.ValidateManifest([]postmedia.Selection{in.Selection}) != nil || len(in.Data) > base64.StdEncoding.EncodedLen(postmedia.MaxBytes) {
		return PostResponse{}, postError("MALFORMED_REQUEST", 400)
	}
	data, e := base64.StdEncoding.Strict().DecodeString(in.Data)
	if e != nil || len(data) != in.ByteLength || base64.StdEncoding.EncodeToString(data) != in.Data {
		return PostResponse{}, postError("MALFORMED_REQUEST", 400)
	}
	material := in
	material.Attempt = 0
	material.Data = ""
	fp := c.dmFingerprint("HNUHOLE/DM-IMAGE/V1\x00", material)
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
		var own bool
		if e = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM public.community_identities WHERE identity_id=$1 AND account_id=$2 AND deleted_at IS NULL)`, in.IdentityID, a).Scan(&own); e != nil {
			return nil, e
		}
		if !own {
			return reject("IDENTITY_UNAVAILABLE")
		}
		var peerAccount uuid.UUID
		var deleted *time.Time
		e = tx.QueryRow(ctx, `SELECT account_id,deleted_at FROM public.community_identities WHERE identity_id=$1 FOR SHARE`, in.PeerID).Scan(&peerAccount, &deleted)
		if errors.Is(e, pgx.ErrNoRows) || e == nil && (deleted != nil || peerAccount == a) {
			return reject("CONTACT_UNAVAILABLE")
		}
		if e != nil {
			return nil, e
		}
		var active bool
		if e = tx.QueryRow(ctx, `SELECT state='ACTIVE' FROM c_auth.accounts WHERE account_id=$1`, peerAccount).Scan(&active); e != nil {
			return nil, e
		}
		if !active {
			return reject("CONTACT_UNAVAILABLE")
		}
		// One global byte-budget lock precedes every image acceptance's conversation
		// lock. Cleanup only decreases the budget and needs no global lock.
		if _, e = tx.Exec(ctx, `SELECT pg_advisory_xact_lock(7223001)`); e != nil {
			return nil, e
		}
		var seq int64
		var open bool
		e = tx.QueryRow(ctx, `SELECT sequence,low_sent AND high_sent FROM c_dm.conversations WHERE conversation_id=$1 AND $2 IN(low_identity,high_identity) AND $3 IN(low_identity,high_identity) FOR UPDATE`, in.ConversationID, in.IdentityID, in.PeerID).Scan(&seq, &open)
		if errors.Is(e, pgx.ErrNoRows) {
			return reject("CONTACT_UNAVAILABLE")
		}
		if e != nil {
			return nil, e
		}
		if !open {
			return reject("WAITING_FOR_REPLY")
		}
		var count int
		var senderBytes, totalBytes int64
		e = tx.QueryRow(ctx, `SELECT count(*) FROM c_dm.messages m JOIN public.community_identities i ON i.identity_id=m.sender WHERE NOT m.acknowledged AND (i.account_id=$1 OR m.conversation_id=$2)`, a, in.ConversationID).Scan(&count)
		if e != nil {
			return nil, e
		}
		e = tx.QueryRow(ctx, `SELECT COALESCE(sum(octet_length(x.bytes)) FILTER(WHERE i.account_id=$1),0),COALESCE(sum(octet_length(x.bytes)),0) FROM c_dm.media x JOIN public.community_identities i ON i.identity_id=x.sender WHERE x.bytes IS NOT NULL`, a).Scan(&senderBytes, &totalBytes)
		if e != nil {
			return nil, e
		}
		if count >= 4096 || senderBytes+int64(len(data)) > 128*1024*1024 || totalBytes+int64(len(data)) > 1024*1024*1024 {
			return reject("PENDING_LIMIT")
		}
		if c.postImages == nil || c.postImages.validator == nil {
			return nil, ErrAuthorizationUnavailable
		}
		metadata, e := c.postImages.validator.Inspect(ctx, data)
		if errors.Is(e, postmedia.ErrInvalid) {
			return reject("INVALID_IMAGE")
		}
		if e != nil {
			return nil, ErrAuthorizationUnavailable
		}
		if !metadata.Matches(in.Selection, data) {
			return reject("INVALID_IMAGE")
		}
		_, e = tx.Exec(ctx, `INSERT INTO c_dm.image_groups(sender,group_id,conversation_id,size) VALUES($1,$2,$3,$4) ON CONFLICT DO NOTHING`, in.IdentityID, in.GroupID, in.ConversationID, in.GroupSize)
		if e != nil {
			return nil, e
		}
		var groupConv string
		var groupSize int
		if e = tx.QueryRow(ctx, `SELECT conversation_id::text,size FROM c_dm.image_groups WHERE sender=$1 AND group_id=$2`, in.IdentityID, in.GroupID).Scan(&groupConv, &groupSize); e != nil {
			return nil, e
		}
		if groupConv != in.ConversationID || groupSize != in.GroupSize {
			return reject("COMMAND_CONFLICT")
		}
		var collision bool
		if e = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM c_dm.media WHERE sender=$1 AND ((group_id=$2 AND position=$3) OR media_id=$4))`, in.IdentityID, in.GroupID, in.Position, in.MediaID).Scan(&collision); e != nil {
			return nil, e
		}
		if collision {
			return reject("COMMAND_CONFLICT")
		}
		seq++
		msg := uuid.NewString()
		at := d.TrustedAt.UTC()
		if _, e = tx.Exec(ctx, `UPDATE c_dm.conversations SET sequence=$2 WHERE conversation_id=$1`, in.ConversationID, seq); e != nil {
			return nil, e
		}
		if _, e = tx.Exec(ctx, `INSERT INTO c_dm.messages(message_id,conversation_id,sequence,sender,recipient,body,accepted_at,kind) VALUES($1,$2,$3,$4,$5,'',$6,'IMAGE')`, msg, in.ConversationID, seq, in.IdentityID, in.PeerID, at); e != nil {
			return nil, e
		}
		raw, _ := json.Marshal(in.Selection)
		if _, e = tx.Exec(ctx, `INSERT INTO c_dm.media(message_id,sender,group_id,position,media_id,selection,bytes) VALUES($1,$2,$3,$4,$5,$6,$7)`, msg, in.IdentityID, in.GroupID, in.Position, in.MediaID, raw, data); e != nil {
			return nil, e
		}
		_, e = tx.Exec(ctx, `INSERT INTO c_dm.commands(owner_account,command_id,fingerprint,attempt,state,message_id,conversation_id,sequence,accepted_at) VALUES($1,$2,$3,$4,'SENT',$5,$6,$7,$8) ON CONFLICT(owner_account,command_id) DO UPDATE SET attempt=EXCLUDED.attempt,state='SENT',error_code='',message_id=EXCLUDED.message_id,conversation_id=EXCLUDED.conversation_id,sequence=EXCLUDED.sequence,accepted_at=EXCLUDED.accepted_at`, a, id, fp, in.Attempt, msg, in.ConversationID, seq, at)
		return DMReceipt{State: "SENT", Attempt: in.Attempt, MessageID: msg, ConversationID: in.ConversationID, Sequence: seq, AcceptedAt: &at}, e
	})
}
func (c *Community) ReadDMPrivateMedia(ctx context.Context, b [32]byte, id string) (PostResponse, error) {
	if !dmUUID(id) {
		return PostResponse{}, postError("MALFORMED_REQUEST", 400)
	}
	return c.withDMSession(ctx, b, func(tx pgx.Tx, a uuid.UUID, _ AuthorizationDecision, _ restriction) (any, error) {
		var raw, data []byte
		e := tx.QueryRow(ctx, `SELECT x.selection,x.bytes FROM c_dm.media x JOIN c_dm.messages m USING(message_id) JOIN public.community_identities i ON i.identity_id=m.recipient LEFT JOIN c_dm.settings s ON s.conversation_id=m.conversation_id AND s.identity_id=m.recipient WHERE m.message_id=$1 AND i.account_id=$2 AND i.deleted_at IS NULL AND NOT m.acknowledged AND NOT m.retracted AND m.sequence>COALESCE(s.deleted_through,0) AND x.bytes IS NOT NULL`, id, a).Scan(&raw, &data)
		if errors.Is(e, pgx.ErrNoRows) {
			return nil, postError("COMMAND_CONFLICT", 409)
		}
		if e != nil {
			return nil, e
		}
		r := DMPrivateMedia{MessageID: id, Data: base64.StdEncoding.EncodeToString(data)}
		e = json.Unmarshal(raw, &r.Selection)
		return r, e
	})
}
