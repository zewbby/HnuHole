package authprivacyhttp

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"mime"
	"net/http"
	"strconv"
	"strings"
	"unicode/utf8"

	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy/protocol"
)

var (
	errMalformed  = errors.New("malformed request")
	errTooLarge   = errors.New("request too large")
	errMediaType  = errors.New("unsupported media type")
	errCapability = errors.New("invalid capability")
)

// parseObject bounds allocation before parsing and deliberately does not use
// encoding/json's case-insensitive struct-field matching or last-key-wins rule.
func parseObject(reader io.Reader, limit int64) (map[string]any, error) {
	if reader == nil {
		return nil, errMalformed
	}
	data, err := io.ReadAll(io.LimitReader(reader, limit+1))
	if err != nil {
		return nil, errMalformed
	}
	if int64(len(data)) > limit {
		return nil, errTooLarge
	}
	if !utf8.Valid(data) || !validEscapedScalars(data) {
		return nil, errMalformed
	}
	d := json.NewDecoder(bytes.NewReader(data))
	d.UseNumber()
	value, err := readValue(d, 0)
	if err != nil {
		return nil, errMalformed
	}
	if _, err = d.Token(); !errors.Is(err, io.EOF) {
		return nil, errMalformed
	}
	object, ok := value.(map[string]any)
	if !ok {
		return nil, errMalformed
	}
	return object, nil
}

func readValue(d *json.Decoder, depth int) (any, error) {
	if depth > 8 {
		return nil, errMalformed
	}
	token, err := d.Token()
	if err != nil || token == nil {
		return nil, errMalformed
	}
	if delim, ok := token.(json.Delim); ok {
		switch delim {
		case '{':
			object := make(map[string]any)
			for d.More() {
				keyToken, e := d.Token()
				key, ok := keyToken.(string)
				if e != nil || !ok {
					return nil, errMalformed
				}
				if _, exists := object[key]; exists {
					return nil, errMalformed
				}
				value, e := readValue(d, depth+1)
				if e != nil {
					return nil, e
				}
				object[key] = value
			}
			end, e := d.Token()
			if e != nil || end != json.Delim('}') {
				return nil, errMalformed
			}
			return object, nil
		case '[':
			var array []any
			for d.More() {
				value, e := readValue(d, depth+1)
				if e != nil {
					return nil, e
				}
				array = append(array, value)
			}
			end, e := d.Token()
			if e != nil || end != json.Delim(']') {
				return nil, errMalformed
			}
			return array, nil
		default:
			return nil, errMalformed
		}
	}
	return token, nil
}

// Go's JSON decoder replaces unpaired UTF-16 escapes with U+FFFD. Reject them
// instead of silently changing a password, identifier, or signed material.
func validEscapedScalars(data []byte) bool {
	inString := false
	for i := 0; i < len(data); i++ {
		if data[i] == '"' {
			inString = !inString
			continue
		}
		if !inString || data[i] != '\\' {
			continue
		}
		i++
		if i >= len(data) {
			return false
		}
		if data[i] != 'u' {
			continue
		}
		if i+4 >= len(data) {
			return false
		}
		v, e := strconv.ParseUint(string(data[i+1:i+5]), 16, 16)
		if e != nil {
			return false
		}
		i += 4
		if v >= 0xdc00 && v <= 0xdfff {
			return false
		}
		if v < 0xd800 || v > 0xdbff {
			continue
		}
		if i+6 >= len(data) || data[i+1] != '\\' || data[i+2] != 'u' {
			return false
		}
		low, e := strconv.ParseUint(string(data[i+3:i+7]), 16, 16)
		if e != nil || low < 0xdc00 || low > 0xdfff {
			return false
		}
		i += 6
	}
	return true
}

func fields(object map[string]any, required, optional []string) error {
	allowed := make(map[string]bool, len(required)+len(optional))
	for _, key := range required {
		allowed[key] = true
		if _, ok := object[key]; !ok {
			return errMalformed
		}
	}
	for _, key := range optional {
		allowed[key] = true
	}
	for key := range object {
		if !allowed[key] {
			return errMalformed
		}
	}
	return nil
}

func stringField(object map[string]any, key string) (string, error) {
	value, ok := object[key].(string)
	if !ok {
		return "", errMalformed
	}
	return value, nil
}

func integerField(object map[string]any, key string, minimum, maximum int) (int, error) {
	number, ok := object[key].(json.Number)
	if !ok {
		return 0, errMalformed
	}
	value, err := strconv.Atoi(string(number))
	if err != nil || value < minimum || value > maximum {
		return 0, errMalformed
	}
	return value, nil
}

// Count case-insensitively as well: a manually assembled Header can contain
// two differently cased keys even though net/http canonicalizes wire headers.
func singleHeader(header http.Header, name string) (string, error) {
	var values []string
	for key, items := range header {
		if strings.EqualFold(key, name) {
			values = append(values, items...)
		}
	}
	if len(values) != 1 || values[0] == "" {
		return "", errMalformed
	}
	return values[0], nil
}

func hasHeader(header http.Header, name string) bool {
	for key := range header {
		if strings.EqualFold(key, name) {
			return true
		}
	}
	return false
}

func headerBytes(header http.Header, name string, size int) ([]byte, error) {
	value, err := singleHeader(header, name)
	if err != nil {
		return nil, err
	}
	return protocol.DecodeCanonicalBase64url(value, size)
}

func capability(header http.Header, scheme string) ([32]byte, error) {
	var result [32]byte
	value, err := singleHeader(header, "Authorization")
	if err != nil || !strings.HasPrefix(value, scheme+" ") {
		return result, errCapability
	}
	raw, err := protocol.DecodeCanonicalBase64url(strings.TrimPrefix(value, scheme+" "), 32)
	if err != nil {
		return result, errCapability
	}
	copy(result[:], raw)
	return result, nil
}

func readRequestObject(r *http.Request, limit int64, required, optional []string) (map[string]any, error) {
	if r.URL.RawQuery != "" || r.URL.ForceQuery || r.Header.Get("Content-Encoding") != "" {
		return nil, errMalformed
	}
	contentType, err := singleHeader(r.Header, "Content-Type")
	if err != nil {
		return nil, errMediaType
	}
	mediaType, parameters, err := mime.ParseMediaType(contentType)
	if err != nil || mediaType != "application/json" || len(parameters) > 1 {
		return nil, errMediaType
	}
	if charset, ok := parameters["charset"]; ok && !strings.EqualFold(charset, "utf-8") {
		return nil, errMediaType
	}
	for key := range parameters {
		if key != "charset" {
			return nil, errMediaType
		}
	}
	object, err := parseObject(r.Body, limit)
	if err != nil {
		return nil, err
	}
	if err = fields(object, required, optional); err != nil {
		return nil, err
	}
	return object, nil
}

func noBodyOrQuery(r *http.Request) error {
	if r.URL.RawQuery != "" || r.URL.ForceQuery {
		return errMalformed
	}
	if r.Body != nil {
		body, err := io.ReadAll(io.LimitReader(r.Body, 1))
		if err != nil || len(body) != 0 {
			return errMalformed
		}
	}
	return nil
}
