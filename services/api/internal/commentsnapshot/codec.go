package commentsnapshot

import (
	"bytes"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/binary"
	"time"

	"github.com/google/uuid"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/comments"
)

func tag(mac MAC, domain string, data []byte) [32]byte {
	b := make([]byte, 0, len(domain)+1+len(data))
	b = append(b, domain...)
	b = append(b, 0)
	b = append(b, data...)
	return mac(sha256.Sum256(b))
}
func OwnerToken(mac MAC, account uuid.UUID, namespace string) [32]byte {
	return tag(mac, "HNUHOLE/COMMENT-SNAPSHOT-OWNER/V1", append(append([]byte(namespace), 0), account[:]...))
}
func Request(mac MAC, owner [32]byte, scope Scope, nonce []byte) RequestIdentity {
	b := append(append([]byte{}, owner[:]...), nonce...)
	key := tag(mac, "HNUHOLE/COMMENT-SNAPSHOT-REQUEST/V1", b)
	b = append(append([]byte{}, scope.Post[:]...), scope.Root[:]...)
	b = append(b, []byte(scope.Kind)...)
	b = append(b, 0)
	b = append(b, []byte(NormalizeSort(scope.Sort))...)
	digest := tag(mac, "HNUHOLE/COMMENT-SNAPSHOT-SCOPE/V1", b)
	return RequestIdentity{base64.RawURLEncoding.EncodeToString(key[:]), base64.RawURLEncoding.EncodeToString(digest[:])}
}
func flags(r Ref) (byte, error) {
	if r.Backend != Postgres && r.Backend != Redis {
		return 0, ErrInvalid
	}
	f := r.Backend
	if r.Kind == comments.Replies {
		f |= 4
	} else if r.Kind != comments.MainComments {
		return 0, ErrInvalid
	}
	switch NormalizeSort(r.Sort) {
	case comments.Relevant:
	case comments.Recent:
		f |= 8
	case comments.MostLiked:
		f |= 16
	default:
		return 0, ErrInvalid
	}
	if r.Kind == comments.Replies && f&24 != 0 {
		return 0, ErrInvalid
	}
	if r.ID == uuid.Nil || (r.Backend == Redis && r.Epoch == uuid.Nil) || (r.Backend == Postgres && r.Epoch != uuid.Nil) || r.Expires.UnixMilli() <= 0 {
		return 0, ErrInvalid
	}
	return f, nil
}
func parseFlags(f byte) (Ref, error) {
	r := Ref{Backend: f & 3, Kind: comments.MainComments, Sort: comments.Relevant}
	if f&224 != 0 || (r.Backend != Postgres && r.Backend != Redis) {
		return r, ErrInvalid
	}
	if f&4 != 0 {
		r.Kind = comments.Replies
	}
	switch f & 24 {
	case 0:
	case 8:
		r.Sort = comments.Recent
	case 16:
		r.Sort = comments.MostLiked
	default:
		return r, ErrInvalid
	}
	if r.Kind == comments.Replies && r.Sort != comments.Relevant {
		return r, ErrInvalid
	}
	return r, nil
}
func EncodeCursor(mac MAC, r Ref, offset int) (string, error) {
	f, e := flags(r)
	if e != nil || offset < 0 || offset > 10000 {
		return "", ErrInvalid
	}
	b := make([]byte, 46)
	b[0] = 2
	b[1] = f
	copy(b[2:18], r.Epoch[:])
	copy(b[18:34], r.ID[:])
	binary.BigEndian.PutUint32(b[34:38], uint32(offset))
	binary.BigEndian.PutUint64(b[38:46], uint64(r.Expires.UnixMilli()))
	t := tag(mac, "HNUHOLE/COMMENT-CURSOR/V2", b)
	return base64.RawURLEncoding.EncodeToString(append(b, t[:]...)), nil
}
func DecodeCursor(mac MAC, s string) (Ref, int, error) {
	b, e := base64.RawURLEncoding.Strict().DecodeString(s)
	if e != nil || len(b) != 78 || base64.RawURLEncoding.EncodeToString(b) != s || b[0] != 2 {
		return Ref{}, 0, ErrInvalid
	}
	t := tag(mac, "HNUHOLE/COMMENT-CURSOR/V2", b[:46])
	if !hmac.Equal(t[:], b[46:]) {
		return Ref{}, 0, ErrInvalid
	}
	r, e := parseFlags(b[1])
	if e != nil {
		return Ref{}, 0, e
	}
	copy(r.Epoch[:], b[2:18])
	copy(r.ID[:], b[18:34])
	ms := binary.BigEndian.Uint64(b[38:46])
	if ms > 1<<53 {
		return Ref{}, 0, ErrInvalid
	}
	r.Expires = time.UnixMilli(int64(ms)).UTC()
	o := int(binary.BigEndian.Uint32(b[34:38]))
	_, e = flags(r)
	if e != nil || o > 10000 {
		return Ref{}, 0, ErrInvalid
	}
	return r, o, nil
}

const payloadHeader = 121

func Encode(mac MAC, s Snapshot, maxBytes int) ([]byte, error) {
	f, e := flags(s.Ref)
	if e != nil || !s.Scope.Valid() || s.Ref.Kind != s.Scope.Kind || NormalizeSort(s.Ref.Sort) != NormalizeSort(s.Scope.Sort) || s.Ref.Expires.Sub(s.Created) != 30*time.Minute {
		return nil, ErrIntegrity
	}
	if len(s.IDs) > 10000 || payloadHeader+16*len(s.IDs)+32 > maxBytes {
		return nil, ErrTooLarge
	}
	b := make([]byte, payloadHeader+16*len(s.IDs))
	copy(b[:4], "HCS1")
	b[4] = f
	copy(b[5:21], s.Ref.Epoch[:])
	copy(b[21:37], s.Ref.ID[:])
	copy(b[37:69], s.Scope.Owner[:])
	copy(b[69:85], s.Scope.Post[:])
	copy(b[85:101], s.Scope.Root[:])
	binary.BigEndian.PutUint64(b[101:109], uint64(s.Created.UnixMilli()))
	binary.BigEndian.PutUint64(b[109:117], uint64(s.Ref.Expires.UnixMilli()))
	binary.BigEndian.PutUint32(b[117:121], uint32(len(s.IDs)))
	seen := make(map[uuid.UUID]bool, len(s.IDs))
	for i, id := range s.IDs {
		if id == uuid.Nil || seen[id] {
			return nil, ErrIntegrity
		}
		seen[id] = true
		copy(b[payloadHeader+i*16:], id[:])
	}
	t := tag(mac, "HNUHOLE/COMMENT-SNAPSHOT-DATA/V1", b)
	return append(b, t[:]...), nil
}
func Decode(mac MAC, b []byte, scope Scope, ref Ref, at time.Time, maxBytes int) (Snapshot, error) {
	if len(b) < payloadHeader+32 || len(b) > maxBytes || !bytes.Equal(b[:4], []byte("HCS1")) {
		return Snapshot{}, ErrIntegrity
	}
	n := int(binary.BigEndian.Uint32(b[117:121]))
	if n > 10000 || len(b) != payloadHeader+16*n+32 {
		return Snapshot{}, ErrIntegrity
	}
	t := tag(mac, "HNUHOLE/COMMENT-SNAPSHOT-DATA/V1", b[:len(b)-32])
	if !hmac.Equal(t[:], b[len(b)-32:]) {
		return Snapshot{}, ErrIntegrity
	}
	r, e := parseFlags(b[4])
	if e != nil {
		return Snapshot{}, ErrIntegrity
	}
	copy(r.Epoch[:], b[5:21])
	copy(r.ID[:], b[21:37])
	ms := binary.BigEndian.Uint64(b[109:117])
	createdMS := binary.BigEndian.Uint64(b[101:109])
	if ms > 1<<53 || createdMS > 1<<53 {
		return Snapshot{}, ErrIntegrity
	}
	r.Expires = time.UnixMilli(int64(ms)).UTC()
	var stored Scope
	copy(stored.Owner[:], b[37:69])
	copy(stored.Post[:], b[69:85])
	copy(stored.Root[:], b[85:101])
	stored.Kind = r.Kind
	stored.Sort = r.Sort
	if !scope.Valid() || stored.Owner != scope.Owner || stored.Post != scope.Post || stored.Root != scope.Root || stored.Kind != scope.Kind || r.ID != ref.ID || r.Epoch != ref.Epoch || r.Backend != ref.Backend || r.Kind != ref.Kind || NormalizeSort(r.Sort) != NormalizeSort(ref.Sort) || !r.Expires.Equal(ref.Expires) || !r.Expires.After(at) {
		return Snapshot{}, ErrInvalid
	}
	s := Snapshot{Ref: r, Scope: stored, Created: time.UnixMilli(int64(createdMS)).UTC(), IDs: make([]uuid.UUID, n)}
	if r.Expires.Sub(s.Created) != 30*time.Minute {
		return Snapshot{}, ErrIntegrity
	}
	seen := map[uuid.UUID]bool{}
	for i := range s.IDs {
		copy(s.IDs[i][:], b[payloadHeader+i*16:payloadHeader+(i+1)*16])
		if s.IDs[i] == uuid.Nil || seen[s.IDs[i]] {
			return Snapshot{}, ErrIntegrity
		}
		seen[s.IDs[i]] = true
	}
	return s, nil
}
