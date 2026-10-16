package main

import (
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
	"reflect"
	"regexp"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy/protocol"
)

type closureIdentityProfile struct {
	ID               uuid.UUID
	Nickname, Avatar *string
	Original         bool
	Created          time.Time
	Renamed, Deleted *time.Time
}
type closureIdentitySnapshot struct {
	Account           uuid.UUID
	Counter, Receipts string
	Profiles          []closureIdentityProfile
}

func readClosureIdentities(ctx context.Context, pool *pgxpool.Pool, account uuid.UUID) (closureIdentitySnapshot, error) {
	snapshot := closureIdentitySnapshot{Account: account}
	err := pool.QueryRow(ctx, `SELECT COALESCE((SELECT to_jsonb(s)::text FROM public.identity_account_state s WHERE account_id=$1),'null'),COALESCE((SELECT jsonb_agg(to_jsonb(r) ORDER BY change_key_digest)::text FROM public.identity_change_receipts r WHERE account_id=$1),'[]')`, account).Scan(&snapshot.Counter, &snapshot.Receipts)
	if err != nil {
		return snapshot, errors.New("cannot read closure identity permanence")
	}
	rows, err := pool.Query(ctx, `SELECT identity_id,nickname,avatar,is_original,created_at,last_renamed_at,deleted_at FROM public.community_identities WHERE account_id=$1 ORDER BY identity_id`, account)
	if err != nil {
		return snapshot, errors.New("cannot read closure identity profiles")
	}
	defer rows.Close()
	for rows.Next() {
		var item closureIdentityProfile
		if err = rows.Scan(&item.ID, &item.Nickname, &item.Avatar, &item.Original, &item.Created, &item.Renamed, &item.Deleted); err != nil {
			return snapshot, errors.New("invalid closure profile shape")
		}
		snapshot.Profiles = append(snapshot.Profiles, item)
	}
	if err = rows.Err(); err != nil {
		return snapshot, errors.New("cannot finish closure profile snapshot")
	}
	return snapshot, nil
}
func (p *probe) captureIdentityClosure(ctx context.Context, pool *pgxpool.Pool, s state) (closureIdentitySnapshot, error) {
	var result closureIdentitySnapshot
	if s.IdentityID == "" || s.Email == "" {
		return result, errors.New("closure identity/eligibility probe state absent")
	}
	raw, err := protocol.DecodeCanonicalBase64url(s.Token, 32)
	if err != nil {
		return result, errors.New("invalid closure probe token")
	}
	token := sha256.Sum256(raw)
	var account uuid.UUID
	if err = pool.QueryRow(ctx, `SELECT account_id FROM c_auth.sessions WHERE token_digest=$1`, token[:]).Scan(&account); err != nil {
		return result, errors.New("closure identity account unavailable")
	}
	result, err = readClosureIdentities(ctx, pool, account)
	if err != nil {
		return result, err
	}
	active, deleted := 0, 0
	for _, item := range result.Profiles {
		if item.Deleted == nil {
			active++
		} else {
			deleted++
		}
	}
	if len(result.Profiles) != 3 || active != 2 || deleted != 1 || result.Counter == "null" || result.Receipts == "[]" {
		return result, errors.New("closure probe did not retain the intended active/deleted identity fixture")
	}
	return result, nil
}
func (p *probe) identityClosureUnchanged(ctx context.Context, pool *pgxpool.Pool, before closureIdentitySnapshot, wantState string) error {
	var state string
	if err := pool.QueryRow(ctx, `SELECT state FROM c_auth.accounts WHERE account_id=$1`, before.Account).Scan(&state); err != nil || state != wantState {
		return errors.New("closure lifecycle state differs from expected boundary")
	}
	after, err := readClosureIdentities(ctx, pool, before.Account)
	if err != nil {
		return err
	}
	if !reflect.DeepEqual(before, after) {
		return errors.New("pending/cancelled closure changed identity profiles or permanence")
	}
	return nil
}
func (p *probe) identityClosureFinalized(ctx context.Context, pool *pgxpool.Pool, before closureIdentitySnapshot, closure []byte, s state) error {
	var accountState string
	var terminalAt time.Time
	if err := pool.QueryRow(ctx, `SELECT state FROM c_auth.accounts WHERE account_id=$1`, before.Account).Scan(&accountState); err != nil || accountState != "CLOSED" {
		return errors.New("release did not follow formal CLOSED account")
	}
	if err := pool.QueryRow(ctx, `SELECT terminal_at FROM c_auth.closure_requests WHERE closure_id=$1`, closure).Scan(&terminalAt); err != nil {
		return errors.New("formal closure terminal time unavailable")
	}
	after, err := readClosureIdentities(ctx, pool, before.Account)
	if err != nil {
		return err
	}
	if before.Counter != after.Counter || before.Receipts != after.Receipts || len(before.Profiles) != len(after.Profiles) {
		return errors.New("formal closure changed permanent identity counts/receipts/tombstones")
	}
	tokens := map[string]bool{}
	for i, old := range before.Profiles {
		current := after.Profiles[i]
		if old.ID != current.ID || old.Original != current.Original || !old.Created.Equal(current.Created) {
			return errors.New("formal closure changed identity ownership/original/creation")
		}
		if old.Deleted != nil {
			if !reflect.DeepEqual(old, current) {
				return errors.New("formal closure rewrote an existing identity tombstone")
			}
		} else if current.Deleted == nil || !current.Deleted.Equal(terminalAt) || current.Nickname != nil || current.Avatar != nil || current.Renamed != nil {
			return errors.New("formal closure did not erase active identity profile at its commit time")
		}
		// This verifies the pure future-business contract. No public post/chat
		// projection endpoint exists in this development slice.
		projection, err := authprivacy.ProjectInactiveIdentityLifecycle(current.ID, true, current.Deleted != nil)
		if err != nil {
			return errors.New("closed identity projection contract rejected fixture")
		}
		wire, err := json.Marshal(projection)
		if err != nil {
			return err
		}
		var shape map[string]any
		if json.Unmarshal(wire, &shape) != nil || len(shape) != 3 || shape["state"] != string(authprivacy.IdentityAccountClosed) || shape["avatar"] != authprivacy.IdentityInactiveAvatar {
			return errors.New("inactive projection exposed fields outside its contract")
		}
		token, ok := shape["placeholderToken"].(string)
		if !ok || token == "" || tokens[token] {
			return errors.New("closed identity placeholders were linked by a common token")
		}
		tokens[token] = true
		deletedProjection, err := authprivacy.ProjectInactiveIdentity(current.ID, authprivacy.IdentityDeleted)
		if err != nil || deletedProjection.PlaceholderToken != token {
			return errors.New("same identity placeholder changed between deletion and closure")
		}
	}
	if _, _, err = p.request(ctx, "GET", p.c, identitiesPath, nil, map[string]string{"Authorization": "Bearer " + s.Token}, 401); err != nil {
		return err
	}
	_, _, err = p.request(ctx, "GET", p.c, identityResultPath, nil, map[string]string{"Authorization": "Bearer " + s.Token, "Idempotency-Key": s.IdentityReceiptKey}, 401)
	return err
}

// The same exact synthetic V email obtains a fresh OTP and bootstrap key after
// V's durable release ACK, and registers a new C account over actual HTTPS.
func (p *probe) identityClosureReturn(ctx context.Context, pool *pgxpool.Pool, before closureIdentitySnapshot, email string) error {
	if !regexp.MustCompile(`^runtime-[a-f0-9]{16}@hainanu\.edu\.cn$`).MatchString(email) {
		return errors.New("return registration needs this invocation's synthetic eligibility address")
	}
	key, err := randomCapability(32)
	if err != nil {
		return err
	}
	installation, err := randomCapability(16)
	if err != nil {
		return err
	}
	requested, _, err := p.request(ctx, "POST", p.v, "/api/v1/eligibility/otp-requests", map[string]string{"email": email}, map[string]string{"Idempotency-Key": key, "V-Installation-ID": installation}, 202)
	if err != nil {
		return err
	}
	flow, err := field(requested, "flowId")
	if err != nil {
		return err
	}
	code, err := p.otp(ctx, email)
	if err != nil {
		return err
	}
	public, private, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		return err
	}
	var bootstrap protocol.PublicKey
	copy(bootstrap[:], public)
	slot, err := protocol.DeriveSlot(bootstrap)
	if err != nil {
		return err
	}
	confirmKey, err := randomCapability(32)
	if err != nil {
		return err
	}
	confirmed, _, err := p.request(ctx, "POST", p.v, "/api/v1/eligibility/otp-confirmations", map[string]string{"flowId": flow, "otp": code, "slotId": protocol.EncodeCanonicalBase64url(slot[:]), "bootstrapPublicKey": protocol.EncodeCanonicalBase64url(public)}, map[string]string{"Idempotency-Key": confirmKey, "V-Installation-ID": installation}, 200)
	if err != nil {
		return err
	}
	ticketText, err := field(confirmed, "registrationTicket")
	if err != nil {
		return err
	}
	cInstall, err := randomCapability(16)
	if err != nil {
		return err
	}
	sum := sha256.Sum256([]byte(key))
	username := fmt.Sprintf("returned_%x", sum[:6])
	password := "new account independent runtime password 2026!"
	intent, _, err := p.request(ctx, "POST", p.c, "/api/v1/auth/registration-intents", map[string]string{"registrationTicket": ticketText, "username": username, "password": password, "installationId": cInstall}, nil, 201)
	if err != nil {
		return err
	}
	idText, err := field(intent, "intentId")
	if err != nil {
		return err
	}
	challengeText, err := field(intent, "challenge")
	if err != nil {
		return err
	}
	recoveryCode, err := field(intent, "recoveryCode")
	if err != nil {
		return err
	}
	idRaw, err := protocol.DecodeCanonicalBase64url(idText, 32)
	if err != nil {
		return err
	}
	challengeRaw, err := protocol.DecodeCanonicalBase64url(challengeText, 32)
	if err != nil {
		return err
	}
	ticket, err := protocol.ParseRegistrationTicket(ticketText)
	if err != nil {
		return err
	}
	var id protocol.IntentID
	copy(id[:], idRaw)
	var challenge protocol.Challenge
	copy(challenge[:], challengeRaw)
	proof := protocol.BootstrapMessageBytes(ticket, id, challenge)
	signupKey, err := randomCapability(32)
	if err != nil {
		return err
	}
	registered, _, err := p.request(ctx, "POST", p.c, "/api/v1/auth/registrations", map[string]string{"intentId": idText, "bootstrapSignature": protocol.EncodeCanonicalBase64url(ed25519.Sign(private, proof[:])), "recoveryCodeConfirmation": recoveryCode}, map[string]string{"Idempotency-Key": signupKey}, 201)
	if err != nil {
		return err
	}
	accountText, err := field(registered, "accountId")
	if err != nil {
		return err
	}
	account, err := uuid.Parse(accountText)
	if err != nil || account == before.Account {
		return errors.New("same email return restored the old account")
	}
	token, err := field(registered, "sessionToken")
	if err != nil {
		return err
	}
	headers := map[string]string{"Authorization": "Bearer " + token}
	list, _, err := p.request(ctx, "GET", p.c, identitiesPath, nil, headers, 200)
	if err != nil {
		return err
	}
	items, ok := list["identities"].([]any)
	if !ok || len(items) != 0 || list["createdCount"] != float64(0) {
		return errors.New("new account inherited old identities or creation quota")
	}
	if _, err = p.directory(ctx, token, 200); err != nil {
		return err
	}
	changeKey, err := randomCapability(16)
	if err != nil {
		return err
	}
	headers["Idempotency-Key"] = changeKey
	if _, _, err = p.request(ctx, "POST", p.c, identitiesPath, map[string]string{"nickname": "海风"}, headers, 200); err != nil {
		return err
	}
	list, _, err = p.request(ctx, "GET", p.c, identitiesPath, nil, map[string]string{"Authorization": "Bearer " + token}, 200)
	if err != nil {
		return err
	}
	items, ok = list["identities"].([]any)
	if !ok || len(items) != 1 || list["createdCount"] != float64(1) {
		return errors.New("new account inherited identity waiting/cumulative history")
	}
	first, ok := items[0].(map[string]any)
	if !ok || first["isOriginal"] != true || first["nickname"] != "海风" {
		return errors.New("new account did not establish its own original identity")
	}
	firstID, err := field(first, "id")
	if err != nil {
		return err
	}
	for _, old := range before.Profiles {
		if firstID == old.ID.String() {
			return errors.New("new account reused an old identity tombstone")
		}
	}
	current, err := readClosureIdentities(ctx, pool, before.Account)
	if err != nil {
		return err
	}
	if current.Counter != before.Counter || current.Receipts != before.Receipts {
		return errors.New("new registration rewrote old permanent identity history")
	}
	return nil
}
