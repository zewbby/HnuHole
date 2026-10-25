package ratelimit

import "errors"

// TrialConfig is a complete, observable starting policy. Existing SQL/network
// limits remain enforced. Operators enable each new rule after normal-traffic
// evidence; this function does not claim these thresholds are production data.
func TrialConfig(address, namespace string) Config {
	sw := func(action, failure string, pairs ...int64) Rule {
		r := Rule{Action: action, Mode: Observe, Failure: failure}
		for i := 0; i < len(pairs); i += 2 {
			r.Windows = append(r.Windows, Window{pairs[i] * 1000, pairs[i+1]})
		}
		return r
	}
	tb := func(action, failure string, capacity, rate int64) Rule {
		return Rule{Action: action, Mode: Observe, Failure: failure, Bucket: &Bucket{capacity, rate}}
	}
	return Config{Address: address, Namespace: namespace, DeadlineMilliseconds: 100, PoolSize: 8, MaxSubjects: 32768, MaxEvents: 16384, MaxDedup: 256, MaxReserves: 32, MaxStateBytes: 1048576, DedupSeconds: 86400, ReadSeconds: 30, Rules: []Rule{
		tb("entry.query", "local-read", 10000, 166), tb("entry.mutation", "reject", 6000, 100),
		sw("login.ip", "reject", 60, 300), sw("login.source", "reject", 60, 10), sw("login.failure", "reject", 300, 5),
		sw("otp.request", "verified-db", 60, 120), sw("otp.verify", "verified-db", 60, 300),
		sw("post.create", "verified-db", 60, 5, 3600, 30), sw("comment.publish", "verified-db", 60, 12, 3600, 120),
		tb("dm.send", "reject", 30, 2), sw("dm.conversation.create", "reject", 600, 10, 3600, 40),
		sw("upload.attempt", "reject", 600, 60), sw("upload.bytes", "reject", 600, 120*1024*1024, 3600, 512*1024*1024),
		tb("read.account", "local-read", 180, 6), tb("read.control", "local-read", 300, 10),
	}}
}

// Rule names are a closed interface. Both services require explicit off rules
// for their unused product features; omitted routes never fail only at runtime.
var actionService = map[string]string{
	"entry.query": "both", "entry.mutation": "both",
	"login.ip": "community", "login.source": "community", "login.failure": "community",
	"otp.request": "verifier", "otp.verify": "verifier",
	"post.create": "community", "comment.publish": "community", "dm.send": "community", "dm.conversation.create": "community",
	"upload.attempt": "community", "upload.bytes": "community", "read.account": "community", "read.control": "community",
}

func (c Config) ValidateFor(service string) error {
	if service != "community" && service != "verifier" {
		return errors.New("invalid shared admission service")
	}
	if err := c.Validate(); err != nil {
		return err
	}
	seen := map[string]bool{}
	for _, rule := range c.Rules {
		scope := actionService[rule.Action]
		if scope != "both" && scope != service && rule.Mode != Off {
			return errors.New("cross-service shared admission action must be off or omitted")
		}
		seen[rule.Action] = true
	}
	for action, scope := range actionService {
		if (scope == "both" || scope == service) && !seen[action] {
			return errors.New("missing explicit service admission rule")
		}
	}
	return nil
}
