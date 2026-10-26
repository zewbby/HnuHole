package commentsnapshot

import (
	"encoding/base64"
	"encoding/hex"
	"github.com/google/uuid"
)

// Private binary arguments are derived from the same validated operation map.
// No MAC key is sent to Redis. Every digest has exactly one wire encoding.
func packedArguments(r map[string]any) ([]any, error) {
	out := make([]any, 7)
	for i := range out {
		out[i] = ""
	}
	if value, ok := r["id"]; ok {
		text, yes := value.(string)
		if !yes {
			return nil, ErrRequest
		}
		id, err := uuid.Parse(text)
		if err != nil || id.String() != text || id == uuid.Nil {
			return nil, ErrRequest
		}
		out[0] = id[:]
	}
	for i, key := range []string{"owner", "request", "scope", "token"} {
		if value, ok := r[key]; ok {
			text, yes := value.(string)
			if !yes {
				return nil, ErrRequest
			}
			raw, err := base64.RawURLEncoding.Strict().DecodeString(text)
			if err != nil || len(raw) != 32 || base64.RawURLEncoding.EncodeToString(raw) != text {
				return nil, ErrRequest
			}
			out[i+1] = raw
		}
	}
	if value, ok := r["digest"]; ok {
		text, yes := value.(string)
		if !yes {
			return nil, ErrRequest
		}
		raw, err := hex.DecodeString(text)
		if err != nil || len(raw) != 32 || hex.EncodeToString(raw) != text {
			return nil, ErrRequest
		}
		out[5] = raw
	}
	if value, ok := r["ids"]; ok {
		ids, yes := value.([]string)
		if !yes || len(ids) > 8192 {
			return nil, ErrRequest
		}
		raw := make([]byte, 0, 16*len(ids))
		for _, text := range ids {
			id, err := uuid.Parse(text)
			if err != nil || id == uuid.Nil || id.String() != text {
				return nil, ErrRequest
			}
			raw = append(raw, id[:]...)
		}
		out[6] = raw
	}
	return out, nil
}
