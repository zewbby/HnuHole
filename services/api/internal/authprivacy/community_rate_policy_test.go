package authprivacy

import (
	"context"
	"errors"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/postmedia"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/ratelimit"
	"strings"
	"testing"
	"time"
)

func TestSharedRatePolicySwitchRejectsRunningOffAndObserveWriters(t *testing.T) {
	for _, mode := range []ratelimit.Mode{ratelimit.Off, ratelimit.Observe} {
		t.Run(string(mode), func(t *testing.T) {
			l := newPostLab(t)
			ctx := context.Background()
			account := sessionTestAccount(t, l, "policy_writer")
			identity := identityChange(t, l.c, account.SessionToken, "CREATE", uuid.Nil, "策略身份").IdentityID
			engine, config, store := sharedEngine(t, l, sharedRedisAddress(t), 5, func(config *ratelimit.Config) {
				config.ReadSeconds = 1
				for i := range config.Rules {
					if config.Rules[i].Action == "post.create" {
						config.Rules[i].Mode = mode
						config.Rules[i].Windows = []ratelimit.Window{{Milliseconds: 100, Limit: 5}}
					}
				}
			})
			key, err := random32()
			if err != nil {
				t.Fatal(err)
			}
			old, err := l.c.WithSharedRateLimit(ctx, engine, key)
			if err != nil {
				t.Fatal(err)
			}
			// Ordinary Redis outage must not reject same-policy observer/off business.
			engine.Close()
			intent := postTestIntent(t, l, identity)
			if _, err = old.ExecutePostCommand(ctx, account.SessionToken, postTestKey(t), intent); err != nil {
				t.Fatal("same-policy off/observe Redis outage added rejection", err)
			}
			command := postTestKey(t)
			digest, _ := posts.RequestDigest(intent)
			k, _ := old.posts.commands.KeyDigest(account.AccountID.String(), command)
			spec := rateSpec{Account: account.AccountID, Kind: "post", Operation: "CREATE", Key: k, Fingerprint: old.posts.commands.IntentFingerprint(digest), Charges: []ratelimit.Charge{{Action: "post.create", Cost: 1}}}
			pending, err := old.prepareRateAdmission(ctx, account.SessionToken, func(pgx.Tx, uuid.UUID) (rateSpec, error) { return spec, nil })
			if err != nil {
				t.Fatal(err)
			}
			if count(t, l.cp, `SELECT count(*) FROM c_rate_limit.admissions`) != 0 {
				t.Fatal("observer/off created coordinated admission")
			}
			for i := range config.Rules {
				if config.Rules[i].Action == "post.create" {
					config.Rules[i].Mode = ratelimit.Enforce
				}
			}
			next, err := ratelimit.New(config, "", store)
			if err != nil {
				t.Fatal(err)
			}
			defer next.Close()
			current, err := store.Load(ctx)
			if err != nil {
				t.Fatal(err)
			}
			changed, err := store.Reconfigure(ctx, current.Generation, current.RunID, next.PolicyHash(), next.RecoveryWindow())
			if err != nil {
				t.Fatal(err)
			}
			if next.RecoveryWindow() < 2*time.Second || next.RecoveryWindow() > 2200*time.Millisecond {
				t.Fatal("fixed in-flight grace not bounded", next.RecoveryWindow())
			}
			if err = engine.ValidatePolicy(ctx); !errors.Is(err, ratelimit.ErrPolicyMismatch) {
				t.Fatal("old runtime policy still valid", err)
			}
			_, err = old.ExecutePostCommand(ctx, account.SessionToken, postTestKey(t), intent)
			postTestError(t, err, "SHARED_RATE_UNAVAILABLE", 503)
			_, err = old.executePostCommandOnce(pending, account.SessionToken, command, intent)
			postTestError(t, err, "SHARED_RATE_UNAVAILABLE", 503)
			if count(t, l.cp, `SELECT count(*) FROM c_posts.publication_tasks WHERE owner_account_id=$1`, account.AccountID) != 1 {
				t.Fatal("old prepared or new request crossed final policy fence")
			}
			replacement, err := l.c.WithSharedRateLimit(ctx, next, key)
			if err != nil {
				t.Fatal(err)
			}
			_, err = replacement.ExecutePostCommand(ctx, account.SessionToken, command, intent)
			postTestError(t, err, "SHARED_RATE_UNAVAILABLE", 503)
			time.Sleep(time.Until(changed.BarrierUntil) + 20*time.Millisecond)
			// Entry is explicitly off. The business path itself must resume elapsed
			// recovery, rather than requiring an unrelated read to activate the epoch.
			if _, err = replacement.ExecutePostCommand(ctx, account.SessionToken, command, intent); err != nil {
				t.Fatal("healthy policy failed to resume after effective window", err)
			}
		})
	}
}

func TestSharedRateDMImageFormatBeforeChargeAndFailedRetryFinalPolicyFence(t *testing.T) {
	l := commentTextLab(t)
	ctx := context.Background()
	var err error
	l.c, err = l.c.WithDirectMessages(ctx)
	if err != nil {
		t.Fatal(err)
	}
	a := sessionTestAccount(t, l, "policy_dm_a")
	b := sessionTestAccount(t, l, "policy_dm_b")
	peerAccount := sessionTestAccount(t, l, "policy_dm_peer")
	own := identityChange(t, l.c, a.SessionToken, "CREATE", uuid.Nil, "策略甲").IdentityID.String()
	otherOwn := identityChange(t, l.c, b.SessionToken, "CREATE", uuid.Nil, "策略乙").IdentityID.String()
	peer := identityChange(t, l.c, peerAccount.SessionToken, "CREATE", uuid.Nil, "策略丙").IdentityID.String()
	post := commentTextPost(t, l, peerAccount.SessionToken, uuid.MustParse(peer))
	engine, config, store := sharedEngine(t, l, sharedRedisAddress(t), 5, func(c *ratelimit.Config) {
		for i := range c.Rules {
			if c.Rules[i].Action == "post.create" {
				c.Rules[i].Mode = ratelimit.Off
			}
			if c.Rules[i].Action == "dm.send" || c.Rules[i].Action == "dm.conversation.create" {
				c.Rules[i].Mode = ratelimit.Enforce
				c.Rules[i].Bucket = nil
				c.Rules[i].Failure = "reject"
				c.Rules[i].Windows = []ratelimit.Window{{Milliseconds: 60000, Limit: 1}}
			}
		}
	})
	key, err := random32()
	if err != nil {
		t.Fatal(err)
	}
	api, err := l.c.WithSharedRateLimit(ctx, engine, key)
	if err != nil {
		t.Fatal(err)
	}
	malformed := DMImageIntent{IdentityID: own, PeerID: peer, ConversationID: uuid.NewString(), GroupID: uuid.NewString(), GroupSize: 1, Selection: postmedia.Selection{MediaID: uuid.NewString(), SHA256: strings.Repeat("a", 64), ByteLength: 1, MIME: "image/png", Width: 1, Height: 1}, Data: "%%%", Attempt: 1}
	_, err = api.SendDMImage(ctx, a.SessionToken, uuid.NewString(), malformed)
	postTestError(t, err, "MALFORMED_REQUEST", 400)
	mustExec(t, l.cp, `UPDATE c_auth.account_restrictions SET mute_state='MUTED',version=version+1 WHERE account_id IN ($1,$2)`, a.AccountID, b.AccountID)
	input := DMTextIntent{IdentityID: own, PeerID: peer, SourcePostID: post, Text: "same original", Attempt: 1}
	id := uuid.NewString()
	r, err := api.SendDMText(ctx, a.SessionToken, id, input)
	if err != nil || r.Value.(DMReceipt).ErrorCode != "POSTING_RESTRICTED" {
		t.Fatal("malformed image consumed logical send before valid attempt", err)
	}
	otherInput := input
	otherInput.IdentityID = otherOwn
	otherID := uuid.NewString()
	r, err = api.SendDMText(ctx, b.SessionToken, otherID, otherInput)
	if err != nil || r.Value.(DMReceipt).State != "FAILED" {
		t.Fatal(err)
	}
	mustExec(t, l.cp, `UPDATE c_auth.account_restrictions SET mute_state='NONE',version=version+1 WHERE account_id IN ($1,$2)`, a.AccountID, b.AccountID)
	input.Attempt = 2
	r, err = api.SendDMText(ctx, a.SessionToken, id, input)
	if err != nil || r.Value.(DMReceipt).State != "SENT" {
		t.Fatal("same-policy explicit failed retry spent quota twice", err)
	}
	input.Attempt = 1
	_, err = api.SendDMText(ctx, a.SessionToken, uuid.NewString(), input)
	postTestError(t, err, "RATE_LIMITED", 429)
	for i := range config.Rules {
		if config.Rules[i].Action == "dm.send" {
			config.Rules[i].Windows[0].Limit = 2
		}
	}
	replacement, err := ratelimit.New(config, "", store)
	if err != nil {
		t.Fatal(err)
	}
	defer replacement.Close()
	ns, err := store.Load(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = store.Reconfigure(ctx, ns.Generation, ns.RunID, replacement.PolicyHash(), replacement.RecoveryWindow()); err != nil {
		t.Fatal(err)
	}
	otherInput.Attempt = 2
	_, err = api.SendDMText(ctx, b.SessionToken, otherID, otherInput)
	postTestError(t, err, "SHARED_RATE_UNAVAILABLE", 503)
	r, err = api.GetDMCommand(ctx, b.SessionToken, otherID)
	if err != nil || r.Value.(DMReceipt).State != "FAILED" || r.Value.(DMReceipt).Attempt != 1 {
		t.Fatal("old FAILED retry crossed new policy without final hash fence", err)
	}
}
