// Package names contains filename parsing, Turkish-aware text folding and
// natural sorting helpers.
package names

import (
	"strings"
	"unicode"
	"unicode/utf8"

	"golang.org/x/text/encoding/charmap"
	"golang.org/x/text/unicode/norm"
)

// special folds that are not handled by NFD decomposition (or need Turkish rules).
var foldRunes = map[rune]string{
	'İ': "i", 'I': "i", 'ı': "i", 'i': "i",
	'ß': "ss", 'æ': "ae", 'Æ': "ae", 'ø': "o", 'Ø': "o",
	'đ': "d", 'Đ': "d", 'ł': "l", 'Ł': "l", 'œ': "oe", 'Œ': "oe",
}

func foldRune(r rune, b *strings.Builder) bool {
	if r < utf8.RuneSelf {
		switch {
		case r >= 'A' && r <= 'Z':
			if r == 'I' {
				b.WriteByte('i')
			} else {
				b.WriteByte(byte(r + 32))
			}
			return true
		case (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9'):
			b.WriteByte(byte(r))
			return true
		}
		return false
	}
	if m, ok := foldRunes[r]; ok {
		b.WriteString(m)
		return true
	}
	if unicode.IsLetter(r) || unicode.IsDigit(r) {
		b.WriteRune(unicode.ToLower(r))
		return true
	}
	return false
}

// Fold produces a search/compare form of s: lower case, accents stripped
// (Turkish aware: İ/I/ı/i all become "i", ş→s, ğ→g, ü→u, ö→o, ç→c),
// apostrophes removed, any other punctuation collapsed to single spaces.
func Fold(s string) string {
	s = DisplayString(s)
	s = norm.NFD.String(s)
	var b strings.Builder
	b.Grow(len(s))
	space := false
	for _, r := range s {
		if unicode.Is(unicode.Mn, r) {
			continue
		}
		if r == '\'' || r == '’' || r == '`' || r == '´' {
			continue
		}
		if foldRune(r, &b) {
			space = false
			continue
		}
		if !space && b.Len() > 0 {
			b.WriteByte(' ')
			space = true
		}
	}
	return strings.TrimRight(b.String(), " ")
}

// Key is the grouping key of a title: Fold without spaces.
func Key(s string) string {
	return strings.ReplaceAll(Fold(s), " ", "")
}

// DisplayString makes sure a (file system) string is valid UTF-8. Invalid
// byte sequences are interpreted as Windows-1254 (Turkish), which is the most
// likely legacy encoding for this audience.
func DisplayString(s string) string {
	if utf8.ValidString(s) {
		return s
	}
	out, err := charmap.Windows1254.NewDecoder().String(s)
	if err != nil || !utf8.ValidString(out) {
		return strings.ToValidUTF8(s, "?")
	}
	return out
}

// sortFold folds for sorting: like Fold but keeps punctuation as-is (lowered).
func sortFold(s string) string {
	s = norm.NFD.String(DisplayString(s))
	var b strings.Builder
	b.Grow(len(s))
	for _, r := range s {
		if unicode.Is(unicode.Mn, r) {
			continue
		}
		if !foldRune(r, &b) {
			b.WriteRune(r)
		}
	}
	return b.String()
}

// SortKey returns a precomputed key usable with NaturalLessKey.
func SortKey(s string) string {
	k := sortFold(s)
	// Ignore leading articles for sorting titles? Keep it simple: no.
	return k
}
