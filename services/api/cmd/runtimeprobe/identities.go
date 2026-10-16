package main

import (
	"context"
	"errors"
	"net/url"
)

const identitiesPath = "/api/v1/identities"
const identityResultPath = "/api/v1/identity-change-result"

// This phase uses only the real public API under the non-owner runtime role.
// The saved receipt is queried again after both actual services restart.
func (p *probe) identities(ctx context.Context, s *state) error {
	headers := map[string]string{"Authorization": "Bearer " + s.Token}
	list, _, err := p.request(ctx, "GET", p.c, identitiesPath, nil, headers, 200)
	if err != nil {
		return err
	}
	initial, ok := list["identities"].([]any)
	if !ok || list["createdCount"] != float64(0) || len(initial) != 0 {
		return errors.New("registration unexpectedly created an identity")
	}
	if _, err = p.directory(ctx, s.Token, 200); err != nil {
		return err
	}
	change := func(method, path, nickname string, want int) (map[string]any, string, error) {
		key, err := randomCapability(16)
		if err != nil {
			return nil, "", err
		}
		headers["Idempotency-Key"] = key
		var body any
		if method != "DELETE" {
			body = map[string]string{"nickname": nickname}
		}
		result, _, err := p.request(ctx, method, p.c, path, body, headers, want)
		return result, key, err
	}
	first, key, err := change("POST", identitiesPath, "海风", 200)
	if err != nil {
		return err
	}
	id, err := field(first, "identityId")
	if err != nil {
		return err
	}
	s.IdentityID, s.IdentityReceiptKey = id, key
	// Replay the exact intent and reject a different payload under the same key.
	replay, _, err := p.request(ctx, "POST", p.c, identitiesPath, map[string]string{"nickname": "海风"}, headers, 200)
	if err != nil || replay["identityId"] != id {
		return errors.New("identity replay duplicated or lost the original result")
	}
	if _, _, err = p.request(ctx, "POST", p.c, identitiesPath, map[string]string{"nickname": "北风"}, headers, 409); err != nil {
		return err
	}
	if _, _, err = change("PATCH", identitiesPath+"/"+url.PathEscape(id), "南风", 200); err != nil {
		return err
	}
	if _, _, err = change("PATCH", identitiesPath+"/"+url.PathEscape(id), "东风", 409); err != nil {
		return err
	}
	if _, _, err = change("DELETE", identitiesPath+"/"+url.PathEscape(id), "", 409); err != nil {
		return err
	}
	rejected, _, err := p.request(ctx, "GET", p.c, identityResultPath, nil, headers, 200)
	if err != nil || rejected["state"] != "REJECTED" || rejected["errorCode"] != "IDENTITY_LAST_REQUIRED" {
		return errors.New("last-identity rejection did not leave a durable terminal receipt")
	}
	second, _, err := change("POST", identitiesPath, "北风", 200)
	if err != nil {
		return err
	}
	secondID, err := field(second, "identityId")
	if err != nil {
		return err
	}
	if _, _, err = change("POST", identitiesPath, "西风", 200); err != nil {
		return err
	}
	if _, _, err = change("DELETE", identitiesPath+"/"+url.PathEscape(secondID), "", 200); err != nil {
		return err
	}
	if _, _, err = change("POST", identitiesPath, "东风", 409); err != nil {
		return err
	}
	return p.identitySnapshot(ctx, *s)
}

func (p *probe) identitySnapshot(ctx context.Context, s state) error {
	if s.IdentityID == "" || s.IdentityReceiptKey == "" {
		return errors.New("identity probe state absent")
	}
	headers := map[string]string{"Authorization": "Bearer " + s.Token}
	list, responseHeaders, err := p.request(ctx, "GET", p.c, identitiesPath, nil, headers, 200)
	if err != nil {
		return err
	}
	items, ok := list["identities"].([]any)
	if !ok || len(list) != 4 || list["createdCount"] != float64(3) || list["nextCreateAt"] == nil || len(items) != 2 || responseHeaders.Get("Session-Expires-At") == "" {
		return errors.New("identity list lost cumulative quota, deadline or active count")
	}
	found := false
	for _, raw := range items {
		item, ok := raw.(map[string]any)
		if !ok || len(item) != 6 || item["avatar"] != "default-v1" {
			return errors.New("own identity exposed extra fields or lost default avatar")
		}
		if item["nickname"] == "北风" {
			return errors.New("deleted identity remained visible")
		}
		if item["id"] == s.IdentityID {
			found = item["nickname"] == "南风" && item["isOriginal"] == true && item["renameAvailableAt"] != nil
		}
	}
	if !found {
		return errors.New("original identity changed across process/session boundary")
	}
	headers["Idempotency-Key"] = s.IdentityReceiptKey
	result, _, err := p.request(ctx, "GET", p.c, identityResultPath, nil, headers, 200)
	if err != nil || result["state"] != "COMMITTED" || result["operation"] != "CREATE" || result["identityId"] != s.IdentityID {
		return errors.New("original identity receipt lost across process/session boundary")
	}
	return nil
}
