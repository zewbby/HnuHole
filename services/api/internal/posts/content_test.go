package posts

import (
	"bufio"
	"errors"
	"os"
	"strconv"
	"strings"
	"testing"
)

// 官方 Unicode 16 conformance 数据是独立判据，不从当前库生成期望值。
func TestUnicode16OfficialGraphemeConformance(t *testing.T) {
	file, err := os.Open("testdata/GraphemeBreakTest-16.0.0.txt")
	if err != nil {
		t.Fatal(err)
	}
	defer file.Close()
	scanner := bufio.NewScanner(file)
	line, cases := 0, 0
	for scanner.Scan() {
		line++
		data := strings.TrimSpace(strings.SplitN(scanner.Text(), "#", 2)[0])
		if data == "" {
			continue
		}
		var text strings.Builder
		breaks := 0
		for _, token := range strings.Fields(data) {
			switch token {
			case "÷":
				breaks++
			case "×":
			default:
				r, err := strconv.ParseInt(token, 16, 32)
				if err != nil {
					t.Fatalf("bad fixture line %d", line)
				}
				text.WriteRune(rune(r))
			}
		}
		got, err := CountGraphemes(text.String())
		if err != nil || got != breaks-1 {
			t.Errorf("Unicode16 fixture line %d: got %d want %d: %v", line, got, breaks-1, err)
		}
		cases++
	}
	if err := scanner.Err(); err != nil {
		t.Fatal(err)
	}
	if cases != 1093 {
		t.Fatalf("unexpected Unicode16 conformance count %d", cases)
	}
}

func TestContentLimitsAndOriginalText(t *testing.T) {
	for _, c := range []struct {
		title, body string
		want        error
	}{
		{strings.Repeat("👩‍💻", 15), strings.Repeat("e\u0301", 3000), nil},
		{strings.Repeat("字", 16), "a", ErrContentInvalid},
		{"a", strings.Repeat("字", 3001), ErrContentInvalid},
		{" \t\r\n字 ", " !\n ", nil},
		{" \t\r\n\u00a0\u2003 ", "a", ErrContentInvalid},
		{"\u200b\u200c\u200d\ufe0f\U000e0100", "a", ErrContentInvalid},
		{"a\x00", "a", ErrContentInvalid},
		{"a\x1b", "a", ErrContentInvalid},
		{"a\u0085", "a", ErrContentInvalid},
		{string([]byte{0xed, 0xa0, 0x80}), "a", ErrContentInvalid},
		{"a", string([]byte{0xff}), ErrContentInvalid},
		{"", "a", ErrContentInvalid},
		{"a", "", ErrContentInvalid},
		{"😀" + strings.Repeat("\u0301", 2046), "a", nil},
		{"😀" + strings.Repeat("\u0301", 2047), "a", ErrPayloadTooLarge},
		{"a", "😀" + strings.Repeat("\u0301", 32766), nil},
		{"a", "😀" + strings.Repeat("\u0301", 32767), ErrPayloadTooLarge},
	} {
		if err := ValidateContent(c.title, c.body); !errors.Is(err, c.want) {
			t.Fatalf("title bytes=%d body bytes=%d got=%v want=%v", len(c.title), len(c.body), err, c.want)
		}
	}
}

func TestUnicode16FrozenInvisibleProperties(t *testing.T) {
	// 新工具链升级不能把版本判定悄悄换成其 unicode 包的数据。
	whitespace, ignored := 0, 0
	for r := rune(0); r <= 0x10ffff; r++ {
		if unicode16WhiteSpace(r) {
			whitespace++
		}
		if unicode16DefaultIgnorable(r) {
			ignored++
			if err := ValidateContent(string(r), "a"); !errors.Is(err, ErrContentInvalid) {
				t.Fatalf("invisible scalar U+%04X accepted", r)
			}
		}
	}
	if whitespace != 25 || ignored != 4174 {
		t.Fatalf("Unicode16 property cardinality drift: %d/%d", whitespace, ignored)
	}
}
