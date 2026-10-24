package ratelimit

import (
	"bytes"
	"context"
	"encoding/json"
	"log/slog"
	"os"
	"strings"
	"testing"
	"time"
)

func TestBoundedConfigRejectsUnverifiedFallbackAndUnsafeParameters(t *testing.T) {
	for _, change := range []func(*Config){func(c *Config) { c.MaxSubjects = 65537 }, func(c *Config) { c.DedupSeconds = 86401 }, func(c *Config) { c.ReadSeconds = 0 }, func(c *Config) { c.DeadlineMilliseconds = 1001 }, func(c *Config) { c.PoolSize = 65 }, func(c *Config) { c.Rules[0].Mode = "silent" }, func(c *Config) { c.Rules[0].Action = "account:user-supplied" }, func(c *Config) { c.Rules[0].Failure = "verified-db" }, func(c *Config) { c.Rules[1].Failure = "local-read" }} {
		config := TrialConfig("127.0.0.1:6379", "bounded_test")
		change(&config)
		if config.Validate() == nil {
			t.Fatal("unsafe admission configuration accepted")
		}
	}
	config := TrialConfig("127.0.0.1:6379", "bounded_test")
	for i := range config.Rules {
		if config.Rules[i].Action == "dm.send" {
			config.Rules[i].Failure = "verified-db"
		}
	}
	if config.Validate() == nil {
		t.Fatal("configuration enabled unverified DM database fallback")
	}
}
func TestMetricsAreOperationallyReadableAndBoundedWithoutSubjects(t *testing.T) {
	config := TrialConfig("127.0.0.1:1", "metrics_test")
	controller, err := New(config, "private-redis-password", &memoryNamespace{})
	if err != nil {
		t.Fatal(err)
	}
	defer controller.Close()
	controller.Metrics.add("post.create", "deny", time.Millisecond)
	controller.RecordFallback("post.create")
	var output bytes.Buffer
	logger := slog.New(slog.NewJSONHandler(&output, nil))
	controller.WriteMetrics(logger)
	lines := strings.Split(strings.TrimSpace(output.String()), "\n")
	if len(lines) != len(config.Rules) {
		t.Fatal("unbounded metric cardinality")
	}
	found := false
	for _, line := range lines {
		var value map[string]any
		if json.Unmarshal([]byte(line), &value) != nil {
			t.Fatal("invalid metric record")
		}
		if len(value) > 13 {
			t.Fatal("unexpected metric labels")
		}
		if value["action"] == "post.create" {
			found = true
			if value["denied"] != float64(1) || value["fallbacks"] != float64(1) || value["duration_ns_total"] == float64(0) {
				t.Fatal("metric outcome/duration absent")
			}
		}
	}
	if !found || strings.Contains(output.String(), "private-redis-password") || strings.Contains(output.String(), "subject") {
		t.Fatal("metrics disclosed private labels")
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	done := make(chan struct{})
	go func() { controller.LogMetrics(ctx, logger, time.Second); close(done) }()
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("metric worker did not stop")
	}
}

func TestCompleteServiceRulesRejectOmissionsUnknownAndCrossDomain(t *testing.T) {
	for _, service := range []string{"community", "verifier"} {
		config := TrialConfig("127.0.0.1:6379", "complete_test")
		for i := range config.Rules {
			scope := actionService[config.Rules[i].Action]
			if scope != "both" && scope != service {
				config.Rules[i].Mode = Off
			}
		}
		if err := config.ValidateFor(service); err != nil {
			t.Fatal("complete service configuration rejected", err)
		}
		missing := config
		missing.Rules = append([]Rule(nil), config.Rules[1:]...)
		if missing.ValidateFor(service) == nil {
			t.Fatal("required entry rule omission accepted")
		}
		unknown := config
		unknown.Rules = append(append([]Rule(nil), config.Rules...), Rule{Action: "arbitrary.action", Mode: Off, Windows: []Window{{1000, 1}}, Failure: "reject"})
		if unknown.ValidateFor(service) == nil {
			t.Fatal("unknown configured rule accepted")
		}
		cross := config
		cross.Rules = append([]Rule(nil), config.Rules...)
		for i := range cross.Rules {
			scope := actionService[cross.Rules[i].Action]
			if scope != "both" && scope != service {
				cross.Rules[i].Mode = Observe
				break
			}
		}
		if cross.ValidateFor(service) == nil {
			t.Fatal("cross-service active rule accepted")
		}
	}
}

func TestCommittedObserveProfilesAreCompleteAndContainNoCredentials(t *testing.T) {
	for _, service := range []string{"community", "verifier"} {
		raw, err := os.ReadFile("../../../../infra/ratelimit/" + service + "-observe.example.json")
		if err != nil {
			t.Fatal(err)
		}
		var value struct {
			Shared struct {
				Policy       Config `json:"policy"`
				KeyFile      string `json:"keyFile"`
				PasswordFile string `json:"passwordFile"`
			} `json:"sharedRateLimit"`
		}
		if json.Unmarshal(raw, &value) != nil || value.Shared.Policy.ValidateFor(service) != nil {
			t.Fatal("invalid committed service profile", service)
		}
		if value.Shared.KeyFile == "" || value.Shared.PasswordFile == "" {
			t.Fatal("profile embedded material instead of file references")
		}
		for _, rule := range value.Shared.Policy.Rules {
			if rule.Mode != Observe {
				t.Fatal("trial profile silently enables blocking", rule.Action)
			}
		}
		if strings.Contains(string(raw), `"password":`) || strings.Contains(string(raw), `"key":`) {
			t.Fatal("profile embeds credentials")
		}
	}
}

func TestUploadBytesRejectsBucketAndPolicyHashBindsMeaning(t *testing.T) {
	config := TrialConfig("127.0.0.1:6379", "hash_test")
	for i := range config.Rules {
		if config.Rules[i].Action == "upload.bytes" {
			config.Rules[i].Windows = nil
			config.Rules[i].Bucket = &Bucket{100, 1}
		}
	}
	if config.Validate() == nil {
		t.Fatal("unsupported byte settlement bucket accepted")
	}
	config = TrialConfig("127.0.0.1:6379", "hash_test")
	a, e := New(config, "first-private-password", &memoryNamespace{}, [32]byte{1})
	if e != nil {
		t.Fatal(e)
	}
	defer a.Close()
	config.Address = "127.0.0.1:6380"
	config.PoolSize = 4
	config.DeadlineMilliseconds = 200
	b, e := New(config, "other-private-password", &memoryNamespace{}, [32]byte{1})
	if e != nil {
		t.Fatal(e)
	}
	defer b.Close()
	if a.PolicyHash() != b.PolicyHash() {
		t.Fatal("transport material changed quota meaning")
	}
	c, e := New(config, "other-private-password", &memoryNamespace{}, [32]byte{2})
	if e != nil {
		t.Fatal(e)
	}
	defer c.Close()
	if b.PolicyHash() == c.PolicyHash() {
		t.Fatal("subject HMAC key rotation silently reset quota")
	}
	config.Rules[0].Mode = Enforce
	d, e := New(config, "", &memoryNamespace{}, [32]byte{1})
	if e != nil {
		t.Fatal(e)
	}
	defer d.Close()
	if d.PolicyHash() == b.PolicyHash() {
		t.Fatal("mode change did not require persisted policy transition")
	}
}
