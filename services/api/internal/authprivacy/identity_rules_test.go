package authprivacy

import (
	"errors"
	"strings"
	"testing"
	"time"
	"unicode"
)

func TestIdentityNicknameRules(t *testing.T) {
	t.Logf("server Unicode tables: %s", unicode.Version)
	for _, example := range []struct { input, want string }{
		{"海风", "海风"}, {"Ab", "Ab"}, {"ab", "ab"}, {"アオ", "アオ"},
		{"あお", "あお"}, {"한글", "한글"}, {"12", "12"}, {"。！", "。！"},
		{"コー", "コー"}, {"あー", "あー"}, {"〆风", "〆风"}, {"ｶﾞｷﾞ", "ｶﾞｷﾞ"}, {"ｺｰ", "ｺｰ"}, {"コ〱", "コ〱"},
		{"e\u0301a", "éa"}, {"か\u3099あ", "があ"}, {"가나", "가나"},
		{"ᄀ\u0300ᅡ", "ᄀ\u0300ᅡ"}, {strings.Repeat("中",12), strings.Repeat("中",12)},
		{strings.Repeat("e\u0301",12), strings.Repeat("é",12)},
	} {
		if got, err := ValidateIdentityNickname(example.input); err != nil || got != example.want {
			t.Errorf("%q normalization=%q want=%q: %v", example.input, got, example.want, err)
		}
	}
	for _, input := range []string{
		"", "a", "e\u0301", "가", "ｶﾞ", "ﾞab", strings.Repeat("中",13),
		strings.Repeat("a",11)+"ᄀ\u0300ᅡ", " a", "a ", "a\tb", "a\nb",
		"a\u00a0b", "a\u3000b", "a\u200bb", "a\u200db", "a\u034fb", "a\ufeffb",
		"a\u180bb", "a\u180db", "a\u180fb", "a\u17b4b", "a\u17b5b",
		"a\ufe0fb", "a\U000e0100b", "a\u3164b", "a\u115fb", "a\uffa0b",
		"海😀", "a♥", "ab🚩", "1\u20e3a", "a\u203cb", "a\u3030b",
		"аb", "αβ", "אב", "\u0301ab", "a\u309bb", string([]byte{0xff,'a','b'}),
	} {
		if _, err := ValidateIdentityNickname(input); !errors.Is(err, ErrIdentityInvalidName) {
			t.Errorf("invalid nickname %q accepted: %v", input, err)
		}
	}
}

func TestIdentitySixCalendarMonthsClampInShanghai(t *testing.T) {
	for _, example := range []struct { from, want string }{
		{"2026-09-13T01:02:03Z", "2027-03-13T01:02:03Z"},
		{"2026-08-31T12:34:56Z", "2027-02-28T12:34:56Z"},
		{"2027-08-31T12:34:56Z", "2028-02-29T12:34:56Z"},
		{"2026-03-31T15:59:59Z", "2026-09-30T15:59:59Z"},
		// The Shanghai date is April 1, so no March 31 clamp applies.
		{"2026-03-31T16:00:00Z", "2026-09-30T16:00:00Z"},
		{"2026-10-31T18:00:00Z", "2027-04-30T18:00:00Z"},
	} {
		at, _ := time.Parse(time.RFC3339, example.from)
		want, _ := time.Parse(time.RFC3339, example.want)
		if got := identityNextCreateAt(3, &at); got == nil || !got.Equal(want) {
			t.Errorf("six months after %s: %v want=%s", example.from, got, example.want)
		}
		if identityNextCreateAt(2, &at) != nil || identityNextCreateAt(3, nil) != nil {
			t.Fatal("cooldown started before third successful creation")
		}
	}
}

func TestIdentityRenameRollingThirtyDays(t *testing.T) {
	if identityRenameAvailableAt(nil) != nil {
		t.Fatal("creation started nickname rename interval")
	}
	at := time.Date(2026,1,31,16,0,0,123,time.UTC)
	got := identityRenameAvailableAt(&at)
	if got == nil || !got.Equal(at.Add(720*time.Hour)) {
		t.Fatal("rename interval used calendar month or lost precision")
	}
}
