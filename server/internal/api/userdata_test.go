package api

import (
	"testing"

	"homestream/internal/store"
)

func TestApplyProgress(t *testing.T) {
	cases := []struct {
		name      string
		in        store.UserData
		pos, dur  float64
		played    bool
		position  float64
		playCount int
	}{
		{"start", store.UserData{}, 100, 5400, false, 100, 0},
		{"ratio threshold", store.UserData{}, 0.92 * 5400, 5400, true, 0, 1},
		{"just below ratio, >120s left", store.UserData{}, 0.90 * 5400, 5400, false, 0.90 * 5400, 0},
		{"remaining < 120s on long video", store.UserData{}, 5400 - 119, 5400, true, 0, 1},
		{"remaining rule needs duration > 600", store.UserData{}, 400, 500, false, 400, 0},
		{"short video ratio", store.UserData{}, 28, 30, true, 0, 1},
		{"credits after played: no double count", store.UserData{Played: true, PlayCount: 1}, 5390, 5400, true, 0, 1},
		{"rewatch finished counts again", store.UserData{Played: true, PlayCount: 1, Position: 3000}, 5300, 5400, true, 0, 2},
		{"rewatch in progress keeps played", store.UserData{Played: true, PlayCount: 1}, 600, 5400, true, 600, 1},
		{"unknown duration", store.UserData{}, 600, 0, false, 600, 0},
		{"negative position clamps", store.UserData{}, -5, 5400, false, 0, 0},
	}
	for _, c := range cases {
		got := applyProgress(c.in, c.pos, c.dur, 1000)
		if got.Played != c.played || got.Position != c.position || got.PlayCount != c.playCount || got.LastPlayedAt != 1000 {
			t.Errorf("%s: got %+v", c.name, got)
		}
	}
}

func TestApplyPlayed(t *testing.T) {
	u := applyPlayed(store.UserData{Position: 50, Liked: true}, true, 5)
	if !u.Played || u.Position != 0 || u.PlayCount != 1 || u.LastPlayedAt != 5 || !u.Liked {
		t.Fatalf("played: %+v", u)
	}
	u = applyPlayed(u, true, 6)
	if u.PlayCount != 1 {
		t.Fatalf("re-mark should not count: %+v", u)
	}
	u = applyPlayed(u, false, 7)
	if u.Played || u.Position != 0 || u.PlayCount != 1 || u.LastPlayedAt != 6 {
		t.Fatalf("unplayed: %+v", u)
	}
}

func TestToUTF8(t *testing.T) {
	cp1254 := []byte{'G', 0xF6, 'r', 'e', 'v', ' ', 0xFD, 0xFE, 0xFD, 'k', ' ', 0xF0, 0xDD}
	if got := string(toUTF8(cp1254)); got != "Görev ışık ğİ" {
		t.Errorf("cp1254: %q", got)
	}
	bom := append([]byte{0xEF, 0xBB, 0xBF}, []byte("Şeker")...)
	if got := string(toUTF8(bom)); got != "Şeker" {
		t.Errorf("bom: %q", got)
	}
	utf16 := []byte{0xFF, 0xFE, 0x5E, 0x01, 'e', 0} // "Şe" UTF-16LE
	if got := string(toUTF8(utf16)); got != "Şe" {
		t.Errorf("utf16: %q", got)
	}
	if got := string(toUTF8([]byte("Çay"))); got != "Çay" {
		t.Errorf("utf8: %q", got)
	}
}
