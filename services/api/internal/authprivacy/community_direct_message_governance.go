package authprivacy

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"sort"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/moderation"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/postmedia"
)

type DMBlockInput struct {
	IdentityID     string `json:"identityId"`
	ConversationID string `json:"conversationId"`
	Blocked        bool   `json:"blocked"`
}
type DMBlockResult struct {
	State   string `json:"state"`
	BlockID string `json:"blockId"`
}
type DMBlock struct {
	ID             string    `json:"id"`
	IdentityID     string    `json:"identityId"`
	ConversationID string    `json:"conversationId"`
	PeerID         string    `json:"peerId"`
	PeerName       string    `json:"peerName"`
	PeerAvatar     string    `json:"peerAvatar"`
	CreatedAt      time.Time `json:"createdAt"`
}
type DMBlocks struct {
	Items []DMBlock `json:"items"`
}

// Account pair serialization is acquired after the caller account and peer
// identity but before conversations. It never locks the opposite account.
func dmPairLock(ctx context.Context, tx pgx.Tx, a, b uuid.UUID) error {
	pair := []string{a.String(), b.String()}
	sort.Strings(pair)
	_, e := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtextextended($1,72401))`, strings.Join(pair, ":"))
	return e
}
func dmSendingBlocked(ctx context.Context, tx pgx.Tx, a, b uuid.UUID) (bool, error) {
	if e := dmPairLock(ctx, tx, a, b); e != nil {
		return false, e
	}
	var blocked bool
	e := tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM c_dm.blocks WHERE (owner_account=$1 AND peer_account=$2) OR (owner_account=$2 AND peer_account=$1))`, a, b).Scan(&blocked)
	return blocked, e
}
func (c *Community) DMBlocks(ctx context.Context, b [32]byte) (PostResponse, error) {
	return c.withDMSession(ctx, b, func(tx pgx.Tx, a uuid.UUID, _ AuthorizationDecision, _ restriction) (any, error) {
		rows, e := tx.Query(ctx, `SELECT b.block_id,b.identity_id,b.conversation_id,b.peer_id,CASE WHEN p.deleted_at IS NULL THEN b.peer_name ELSE '注销身份 · '||(SELECT short_code FROM c_posts.identity_public_labels WHERE identity_id=p.identity_id) END,CASE WHEN p.deleted_at IS NULL THEN b.peer_avatar ELSE 'inactive-v1' END,b.created_at FROM c_dm.blocks b JOIN public.community_identities p ON p.identity_id=b.peer_id WHERE b.owner_account=$1 ORDER BY b.created_at,b.block_id`, a)
		if e != nil {
			return nil, e
		}
		defer rows.Close()
		out := DMBlocks{Items: []DMBlock{}}
		for rows.Next() {
			var v DMBlock
			if e = rows.Scan(&v.ID, &v.IdentityID, &v.ConversationID, &v.PeerID, &v.PeerName, &v.PeerAvatar, &v.CreatedAt); e != nil {
				return nil, e
			}
			out.Items = append(out.Items, v)
		}
		return out, rows.Err()
	})
}
func (c *Community) GetDMBlock(ctx context.Context, b [32]byte, id string) (PostResponse, error) {
	if !dmUUID(id) {
		return PostResponse{}, postError("MALFORMED_REQUEST", 400)
	}
	return c.withDMSession(ctx, b, func(tx pgx.Tx, a uuid.UUID, _ AuthorizationDecision, _ restriction) (any, error) {
		var raw []byte
		e := tx.QueryRow(ctx, `SELECT result FROM c_dm.operations WHERE owner_account=$1 AND operation_id=$2`, a, id).Scan(&raw)
		if errors.Is(e, pgx.ErrNoRows) {
			return DMBlockResult{State: "ABSENT"}, nil
		}
		if e != nil {
			return nil, e
		}
		var r DMBlockResult
		e = json.Unmarshal(raw, &r)
		return r, e
	})
}
func (c *Community) ChangeDMBlock(ctx context.Context, b [32]byte, id string, in DMBlockInput) (PostResponse, error) {
	if !dmUUID(id) || !dmUUID(in.IdentityID) || !dmUUID(in.ConversationID) {
		return PostResponse{}, postError("MALFORMED_REQUEST", 400)
	}
	fp := c.dmFingerprint("HNUHOLE/DM-BLOCK/V1\x00", in)
	return c.withDMSession(ctx, b, func(tx pgx.Tx, a uuid.UUID, d AuthorizationDecision, _ restriction) (any, error) {
		var old, raw []byte
		e := tx.QueryRow(ctx, `SELECT fingerprint,result FROM c_dm.operations WHERE owner_account=$1 AND operation_id=$2`, a, id).Scan(&old, &raw)
		if e == nil {
			if !hmac.Equal(old, fp) {
				return nil, postError("COMMAND_CONFLICT", 409)
			}
			var out DMBlockResult
			e = json.Unmarshal(raw, &out)
			return out, e
		}
		if !errors.Is(e, pgx.ErrNoRows) {
			return nil, e
		}
		var peerAccount uuid.UUID
		var peer, name, avatar string
		e = tx.QueryRow(ctx, `SELECT p.account_id,p.identity_id,COALESCE(p.nickname,'已删除身份'),COALESCE(p.avatar,'default-v1') FROM c_dm.conversations c JOIN public.community_identities i ON i.identity_id=$2 AND i.identity_id IN(c.low_identity,c.high_identity) JOIN public.community_identities p ON p.identity_id=CASE WHEN c.low_identity=i.identity_id THEN c.high_identity ELSE c.low_identity END WHERE c.conversation_id=$1 AND i.account_id=$3`, in.ConversationID, in.IdentityID, a).Scan(&peerAccount, &peer, &name, &avatar)
		if errors.Is(e, pgx.ErrNoRows) {
			return nil, postError("COMMAND_CONFLICT", 409)
		}
		if e != nil {
			return nil, e
		}
		if e = dmPairLock(ctx, tx, a, peerAccount); e != nil {
			return nil, e
		}
		out := DMBlockResult{State: "APPLIED", BlockID: id}
		if in.Blocked {
			_, e = tx.Exec(ctx, `INSERT INTO c_dm.blocks(block_id,owner_account,peer_account,identity_id,peer_id,conversation_id,peer_name,peer_avatar,created_at) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9) ON CONFLICT(owner_account,identity_id,peer_id) DO NOTHING`, uuid.New(), a, peerAccount, in.IdentityID, peer, in.ConversationID, name, avatar, d.TrustedAt)
			if e != nil {
				return nil, e
			}
		} else {
			_, e = tx.Exec(ctx, `DELETE FROM c_dm.blocks WHERE owner_account=$1 AND identity_id=$2 AND conversation_id=$3`, a, in.IdentityID, in.ConversationID)
		}
		if e != nil {
			return nil, e
		}
		rows, e := tx.Query(ctx, `SELECT c.conversation_id FROM c_dm.conversations c JOIN public.community_identities l ON l.identity_id=c.low_identity JOIN public.community_identities h ON h.identity_id=c.high_identity WHERE (l.account_id=$1 AND h.account_id=$2) OR (l.account_id=$2 AND h.account_id=$1) ORDER BY c.conversation_id FOR UPDATE OF c`, a, peerAccount)
		if e != nil {
			return nil, e
		}
		for rows.Next() {
			var locked uuid.UUID
			if e = rows.Scan(&locked); e != nil {
				rows.Close()
				return nil, e
			}
		}
		e = rows.Err()
		rows.Close()
		if e != nil {
			return nil, e
		}
		_, e = tx.Exec(ctx, `UPDATE c_dm.conversations c SET revision=revision+1 FROM public.community_identities l,public.community_identities h WHERE l.identity_id=c.low_identity AND h.identity_id=c.high_identity AND ((l.account_id=$1 AND h.account_id=$2) OR (l.account_id=$2 AND h.account_id=$1))`, a, peerAccount)
		if e != nil {
			return nil, e
		}
		raw, _ = json.Marshal(out)
		_, e = tx.Exec(ctx, `INSERT INTO c_dm.operations VALUES($1,$2,$3,$4)`, a, id, fp, raw)
		return out, e
	})
}

func (c *Community) dmEvidenceDigest(id, text string) []byte {
	return c.dmFingerprint("HNUHOLE/DM-EVIDENCE/V1\x00", []string{id, text})
}

type DMEvidenceEntry struct {
	MessageID string `json:"messageId"`
	Sequence  int64  `json:"sequence"`
	Kind      string `json:"kind"`
	Text      string `json:"text"`
	Data      string `json:"data"`
	Gap       string `json:"gap"`
}
type DMReportInput struct {
	RetryToken     string             `json:"retryToken,omitempty"`
	IdentityID     string             `json:"identityId"`
	ConversationID string             `json:"conversationId"`
	FirstSequence  int64              `json:"firstSequence"`
	LastSequence   int64              `json:"lastSequence"`
	Reason         string             `json:"reason"`
	Description    string             `json:"description"`
	Images         []moderation.Image `json:"images"`
	Authorized     bool               `json:"authorized"`
	Entries        []DMEvidenceEntry  `json:"entries"`
}

func (in DMReportInput) Validate() error {
	if !dmUUID(in.IdentityID) || !dmUUID(in.ConversationID) || in.FirstSequence < 1 || in.LastSequence < in.FirstSequence || in.LastSequence-in.FirstSequence >= 200 || int64(len(in.Entries)) != in.LastSequence-in.FirstSequence+1 || !in.Authorized || !moderation.ValidReason(in.Reason) || !moderation.Text(in.Description, 200) {
		return postError("MALFORMED_REQUEST", 400)
	}
	for i, v := range in.Entries {
		if !(dmUUID(v.MessageID) || v.MessageID == "" && v.Gap != "") || v.Sequence != in.FirstSequence+int64(i) || (v.Kind != "TEXT" && v.Kind != "IMAGE" && !(v.Kind == "UNKNOWN" && v.Gap != "")) || len(v.Text) > 16384 || len(v.Data) > base64.StdEncoding.EncodedLen(postmedia.MaxBytes) {
			return postError("MALFORMED_REQUEST", 400)
		}
		switch v.Gap {
		case "":
			if v.Kind == "TEXT" && (strings.TrimSpace(v.Text) == "" || v.Data != "") || v.Kind == "IMAGE" && (v.Data == "" || v.Text != "") {
				return postError("MALFORMED_REQUEST", 400)
			}
		case "LOCAL_UNAVAILABLE", "RETRACTED", "UNVERIFIABLE":
			if v.Text != "" || v.Data != "" {
				return postError("MALFORMED_REQUEST", 400)
			}
		default:
			return postError("MALFORMED_REQUEST", 400)
		}
	}
	return nil
}
func (c *Community) GetDMReport(ctx context.Context, b [32]byte, id string) (PostResponse, error) {
	if !dmUUID(id) {
		return PostResponse{}, postError("MALFORMED_REQUEST", 400)
	}
	return c.withModerationSession(ctx, b, false, func(tx pgx.Tx, a uuid.UUID, _ AuthorizationDecision) (any, error) {
		r, e := readReport(ctx, tx, a, id)
		if e == nil && r.State == "NOT_SUBMITTED" {
			r.RetryToken, e = sealModerationAttempt(ctx, tx, a, "REPORT", "", id)
		}
		return r, e
	})
}
func (c *Community) SubmitDMReport(ctx context.Context, b [32]byte, id string, in DMReportInput) (PostResponse, error) {
	if !c.DirectMessagesEnabled() || !c.ModerationEnabled() {
		return PostResponse{}, ErrAuthorizationUnavailable
	}
	if !dmUUID(id) {
		return PostResponse{}, postError("MALFORMED_REQUEST", 400)
	}
	if e := in.Validate(); e != nil {
		return PostResponse{}, e
	}
	if e := c.inspectModerationImages(ctx, in.Images, 6); e != nil {
		return PostResponse{}, e
	}
	return c.withModerationSession(ctx, b, false, func(tx pgx.Tx, a uuid.UUID, d AuthorizationDecision) (any, error) {
		material := in
		material.RetryToken = ""
		fp := moderation.Fingerprint(material)
		var prior string
		e := tx.QueryRow(ctx, `SELECT fingerprint FROM c_moderation.reports WHERE reporter_account_id=$1 AND request_id=$2`, a, id).Scan(&prior)
		if e == nil {
			if prior != fp {
				return nil, postError("REQUEST_CONFLICT", 409)
			}
			return readReport(ctx, tx, a, id)
		}
		if !errors.Is(e, pgx.ErrNoRows) {
			return nil, e
		}
		if e = checkModerationAttempt(ctx, tx, a, "REPORT", "", id, in.RetryToken); e != nil {
			return nil, e
		}
		last, e := dmOwnConversation(ctx, tx, a, in.IdentityID, in.ConversationID)
		if e != nil {
			return nil, e
		}
		if in.LastSequence > last {
			return nil, postError("EVIDENCE_MISMATCH", 409)
		}
		var target uuid.UUID
		var peer string
		e = tx.QueryRow(ctx, `SELECT i.account_id,i.identity_id FROM c_dm.conversations c JOIN public.community_identities i ON i.identity_id=CASE WHEN c.low_identity=$2 THEN c.high_identity ELSE c.low_identity END WHERE conversation_id=$1`, in.ConversationID, in.IdentityID).Scan(&target, &peer)
		if e != nil {
			return nil, e
		}
		evidence := moderation.Evidence{Title: "私信授权区间", Images: []moderation.Image{}}
		var body strings.Builder
		fmt.Fprintf(&body, "固定授权范围：%d–%d\n", in.FirstSequence, in.LastSequence)
		authenticated := 0
		totalBytes := 0
		for _, image := range in.Images {
			raw, _ := base64.StdEncoding.DecodeString(image.Base64)
			totalBytes += len(raw)
		}
		for _, v := range in.Entries {
			var sender, kind string
			var digest, selection []byte
			var retracted bool
			e = tx.QueryRow(ctx, `SELECT m.sender,m.kind,m.evidence_digest,m.retracted,x.selection FROM c_dm.messages m LEFT JOIN c_dm.media x USING(message_id) WHERE ($1='' OR m.message_id=NULLIF($1,'')::uuid) AND m.conversation_id=$2 AND m.sequence=$3`, v.MessageID, in.ConversationID, v.Sequence).Scan(&sender, &kind, &digest, &retracted, &selection)
			if errors.Is(e, pgx.ErrNoRows) || e == nil && kind != v.Kind && v.Kind != "UNKNOWN" {
				return nil, postError("EVIDENCE_MISMATCH", 409)
			}
			if e != nil {
				return nil, e
			}
			direction := "被举报方"
			if sender == in.IdentityID {
				direction = "举报方"
			}
			record := moderation.DMEvidenceRecord{Sequence: v.Sequence, Direction: direction, Kind: kind, Text: v.Text, Gap: v.Gap, Retracted: retracted}
			if v.Gap != "" {
				if v.Gap == "RETRACTED" && !retracted || v.Gap == "UNVERIFIABLE" && (len(digest) > 0 || kind == "IMAGE") {
					return nil, postError("EVIDENCE_MISMATCH", 409)
				}
				evidence.DMRecords = append(evidence.DMRecords, record)
				fmt.Fprintf(&body, "[%d %s] 缺口：%s\n", v.Sequence, direction, v.Gap)
				continue
			}
			if retracted {
				fmt.Fprintf(&body, "[%d %s] 服务器标记：已撤回，以下为授权时固定的原始记录\n", v.Sequence, direction)
			}
			if kind == "TEXT" {
				totalBytes += len(v.Text)
				if totalBytes > 32*1024*1024 {
					return nil, postError("EVIDENCE_LIMIT", 413)
				}
				if len(digest) == 0 {
					return nil, postError("EVIDENCE_UNVERIFIABLE", 409)
				}
				if !hmac.Equal(digest, c.dmEvidenceDigest(v.MessageID, v.Text)) {
					return nil, postError("EVIDENCE_MISMATCH", 409)
				}
				fmt.Fprintf(&body, "[%d %s] %s\n", v.Sequence, direction, v.Text)
			} else {
				var s postmedia.Selection
				if e = json.Unmarshal(selection, &s); e != nil {
					return nil, e
				}
				data, e := base64.StdEncoding.Strict().DecodeString(v.Data)
				if e != nil || base64.StdEncoding.EncodeToString(data) != v.Data {
					return nil, postError("EVIDENCE_MISMATCH", 409)
				}
				totalBytes += len(data)
				if totalBytes > 32*1024*1024 {
					return nil, postError("EVIDENCE_LIMIT", 413)
				}
				if len(data) != s.ByteLength || !dmImageMatches(s, data) {
					return nil, postError("EVIDENCE_MISMATCH", 409)
				}
				evidence.Images = append(evidence.Images, moderation.Image{MIME: s.MIME, Base64: v.Data})
				record.ImageIndex = len(evidence.Images)
				fmt.Fprintf(&body, "[%d %s] 图片 %d\n", v.Sequence, direction, len(evidence.Images))
			}
			evidence.DMRecords = append(evidence.DMRecords, record)
			authenticated++
		}
		if authenticated == 0 {
			return nil, postError("EVIDENCE_UNVERIFIABLE", 409)
		}
		evidence.Body = body.String()
		payload, _ := json.Marshal(evidence)
		snapshot := moderation.Fingerprint([]any{in.ConversationID, in.IdentityID, in.FirstSequence, in.LastSequence, in.Entries})
		caseID := uuid.New()
		e = tx.QueryRow(ctx, `INSERT INTO c_moderation.cases(case_id,conversation_id,target_account_id,target_identity_id,reason,snapshot_digest,evidence,created_at) VALUES($1,$2,$3,$4,$5,$6,$7,$8) ON CONFLICT(conversation_id,snapshot_digest) WHERE conversation_id IS NOT NULL DO UPDATE SET version=c_moderation.cases.version RETURNING case_id`, caseID, in.ConversationID, target, peer, in.Reason, snapshot, payload, d.TrustedAt).Scan(&caseID)
		if e != nil {
			return nil, e
		}
		reportID := uuid.New()
		images, _ := json.Marshal(in.Images)
		_, e = tx.Exec(ctx, `INSERT INTO c_moderation.reports(report_id,request_id,reporter_account_id,identity_id,case_id,reason,fingerprint,description,images,created_at) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)`, reportID, id, a, in.IdentityID, caseID, in.Reason, fp, in.Description, images, d.TrustedAt)
		if e != nil {
			return nil, e
		}
		if e = notification(ctx, tx, a, &in.IdentityID, "report:"+reportID.String()+":submitted", "REPORT_PROGRESS", "PENDING", "举报已提交，等待处理", "提交举报不代表认定违规。", "REPORT", id, d.TrustedAt); e != nil {
			return nil, e
		}
		return readReport(ctx, tx, a, id)
	})
}

func dmImageMatches(s postmedia.Selection, data []byte) bool {
	h := sha256.Sum256(data)
	return hex.EncodeToString(h[:]) == s.SHA256
}

// Erase the deleted owner's receiving queue and private settings. Accepted
// outgoing deliveries still belong to the active recipient and are retained
// until that recipient ACKs. Governance snapshots remain independently held.
func (c *Community) cleanupDMIdentity(ctx context.Context, tx pgx.Tx, account, identity uuid.UUID) error {
	var installed bool
	if e := tx.QueryRow(ctx, `SELECT to_regclass('c_dm.blocks') IS NOT NULL`).Scan(&installed); e != nil {
		return e
	}
	if !installed {
		return nil
	}
	rows, e := tx.Query(ctx, `SELECT identity_id FROM public.community_identities WHERE account_id=$1 AND ($2::uuid IS NULL OR identity_id=$2) ORDER BY identity_id FOR UPDATE`, account, nullableUUID(identity))
	if e != nil {
		return e
	}
	ids := []uuid.UUID{}
	for rows.Next() {
		var id uuid.UUID
		if e = rows.Scan(&id); e != nil {
			rows.Close()
			return e
		}
		ids = append(ids, id)
	}
	e = rows.Err()
	rows.Close()
	if e != nil {
		return e
	}
	rows, e = tx.Query(ctx, `SELECT conversation_id FROM c_dm.conversations WHERE low_identity=ANY($1::uuid[]) OR high_identity=ANY($1::uuid[]) ORDER BY conversation_id FOR UPDATE`, ids)
	if e != nil {
		return e
	}
	for rows.Next() {
		var id uuid.UUID
		if e = rows.Scan(&id); e != nil {
			rows.Close()
			return e
		}
	}
	e = rows.Err()
	rows.Close()
	if e != nil {
		return e
	}
	if _, e = tx.Exec(ctx, `UPDATE c_dm.messages SET body=NULL,acknowledged=true,read=true WHERE recipient=ANY($1::uuid[]) AND (NOT acknowledged OR NOT read OR body IS NOT NULL)`, ids); e != nil {
		return e
	}
	if _, e = tx.Exec(ctx, `UPDATE c_dm.media x SET bytes=NULL FROM c_dm.messages m WHERE m.message_id=x.message_id AND m.recipient=ANY($1::uuid[]) AND x.bytes IS NOT NULL`, ids); e != nil {
		return e
	}
	if _, e = tx.Exec(ctx, `UPDATE c_dm.settings s SET version=s.version+1,note='',pinned=false,muted=false,hidden_through=c.sequence,deleted_through=c.sequence FROM c_dm.conversations c WHERE c.conversation_id=s.conversation_id AND s.identity_id=ANY($1::uuid[])`, ids); e != nil {
		return e
	}
	if identity == uuid.Nil {
		_, e = tx.Exec(ctx, `DELETE FROM c_dm.blocks WHERE owner_account=$1`, account)
	}
	return e
}
