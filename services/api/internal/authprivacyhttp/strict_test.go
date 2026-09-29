package authprivacyhttp

import (
	"errors"
	"net/http"
	"strings"
	"testing"
	"time"
)

func TestStrictJSONRejectsAmbiguousInputs(t *testing.T) {
	tests := []string{
		`{"email":"first","email":"second"}`,
		`{"email":"first","\u0065mail":"second"}`,
		`{"email":null}`,
		`{"email":"first"} {"email":"second"}`,
		`{"email":"first"} true`,
		`{"email":"\ud800"}`,
		`{"email":"\udfff"}`,
		"{\"email\":\"\xff\"}",
		`["email"]`,
		`{"nested":{"a":1,"a":2}}`,
		`{"email":"x",}`,
	}
	for _, input := range tests {
		t.Run(input, func(t *testing.T) {
			if _, err := parseObject(strings.NewReader(input), 1024); err == nil {
				t.Fatal("accepted ambiguous JSON")
			}
		})
	}
	if _, err := parseObject(strings.NewReader(`{"email":"valid \ud83d\ude00"}`), 1024); err != nil {
		t.Fatalf("valid paired scalar: %v", err)
	}
	if _, err := parseObject(strings.NewReader(`{"email":"\\ud800"}`), 1024); err != nil {
		t.Fatalf("literal escape: %v", err)
	}
	if _, err := parseObject(strings.NewReader(`{"email":"`+strings.Repeat("x", 1024)+`"}`), 1024); !errors.Is(err, errTooLarge) {
		t.Fatalf("bound error: %v", err)
	}
}

func TestStrictObjectFieldsAndTypes(t *testing.T) {
	for _, input := range []string{`{"Email":"x"}`, `{"email":"x","extra":1}`, `{"email":9}`, `{"email":[]}`, `{"email":{}}`, `{}`} {
		object, err := parseObject(strings.NewReader(input), 1024)
		if err == nil {
			err = fields(object, []string{"email"}, nil)
		}
		if err == nil {
			_, err = stringField(object, "email")
		}
		if err == nil {
			t.Fatalf("accepted invalid schema %s", input)
		}
	}
	object, err := parseObject(strings.NewReader(`{"retry":1e1}`), 1024)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = integerField(object, "retry", 1, 300); err == nil {
		t.Fatal("accepted exponent instead of integer-seconds encoding")
	}
}

func TestStrictHeadersAndCapabilities(t *testing.T) {
	value := strings.Repeat("A", 43)
	for _, header := range []http.Header{
		{"Authorization": {"OtpRequestResult " + value, "OtpRequestResult " + value}},
		{"Authorization": {"OtpRequestResult " + value}, "authorization": {"OtpRequestResult " + value}},
		{"Authorization": {"Bearer " + value}},
		{"Authorization": {"OtpRequestResult  " + value}},
		{"Authorization": {"OtpRequestResult\t" + value}},
		{"Authorization": {"OtpRequestResult " + value + "="}},
		{"Authorization": {"OtpRequestResult " + strings.Repeat("A", 42) + "B"}},
	} {
		if _, err := capability(header, "OtpRequestResult"); err == nil {
			t.Fatal("accepted malformed or mixed capability")
		}
	}
	if _, err := capability(http.Header{"Authorization": {"OtpRequestResult " + value}}, "OtpRequestResult"); err != nil {
		t.Fatal(err)
	}
}

func TestNetworkIdentityAndIndependentBudgets(t *testing.T) {
	a, err := canonicalNetwork("192.0.2.9:12")
	if err != nil {
		t.Fatal(err)
	}
	b, err := canonicalNetwork("[::ffff:192.0.2.9]:9999")
	if err != nil || a != b {
		t.Fatalf("mapped address split budget: %q %q %v", a, b, err)
	}
	a, _ = canonicalNetwork("[2001:db8:1::12]:12")
	b, _ = canonicalNetwork("[2001:db8:1::99]:99")
	if a != b {
		t.Fatal("IPv6 interface identifier split budget")
	}
	for _, remote := range []string{"hostname:99", "192.0.2.9", "192.0.2.9:bad", "192.0.2.9:99999"} {
		if _, err := canonicalNetwork(remote); err == nil {
			t.Fatalf("accepted %s", remote)
		}
	}
	limiter, err := newNetworkLimiter(NetworkLimits{Key: [32]byte{1}, MutationCapacity: 1, QueryCapacity: 1, Window: time.Minute, MaxEntries: 1}, VerifierService)
	if err != nil {
		t.Fatal(err)
	}
	if retry, err := limiter.allow("192.0.2.9:1", false); err != nil || retry != 0 {
		t.Fatal("first mutation blocked")
	}
	if retry, _ := limiter.allow("192.0.2.9:2", false); retry < 1 {
		t.Fatal("port change bypassed mutation budget")
	}
	if retry, _ := limiter.allow("192.0.2.9:3", true); retry != 0 {
		t.Fatal("mutation exhausted query budget")
	}
	if retry, _ := limiter.allow("192.0.2.9:4", true); retry < 1 {
		t.Fatal("query budget bypassed")
	}
	if retry, _ := limiter.allow("192.0.2.10:1", false); retry < 1 {
		t.Fatal("full map allowed unbounded new entries")
	}
}

func TestNetworkBudgetConstructorRejectsMissingOrUnboundedPolicy(t *testing.T) {
	valid := NetworkLimits{Key: [32]byte{1}, MutationCapacity: 1, QueryCapacity: 1, Window: time.Minute, MaxEntries: 100}
	for _, change := range []func(*NetworkLimits){
		func(v *NetworkLimits) { v.Key = [32]byte{} },
		func(v *NetworkLimits) { v.MutationCapacity = 0 },
		func(v *NetworkLimits) { v.QueryCapacity = 10001 },
		func(v *NetworkLimits) { v.Window = 6 * time.Minute },
		func(v *NetworkLimits) { v.MaxEntries = 0 },
	} {
		invalid := valid
		change(&invalid)
		if _, err := newNetworkLimiter(invalid, VerifierService); err == nil {
			t.Fatal("accepted invalid rate policy")
		}
	}
}
