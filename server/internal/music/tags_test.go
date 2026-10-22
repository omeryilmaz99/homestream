package music

import "testing"

func TestFixTurkish(t *testing.T) {
	cases := map[string]string{
		"Barýþ Manço":    "Barış Manço",
		"ÝSTANBUL":       "İSTANBUL",
		"Daðlar":         "Dağlar",
		"Normal Title":   "Normal Title",
		"Şarkı ý (keep)": "Şarkı ý (keep)", // already Turkish: left alone
	}
	for in, want := range cases {
		if got := fixTurkish(in); got != want {
			t.Errorf("fixTurkish(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestCleanGenre(t *testing.T) {
	cases := map[string]string{
		"(17)":              "Rock",
		"13":                "Pop",
		"rock; pop":         "Rock",
		"türk sanat müziği": "Türk Sanat Müziği",
		"indie/alternative": "İndie",
		"Other":             "",
		"":                  "",
	}
	for in, want := range cases {
		if got := cleanGenre(in); got != want {
			t.Errorf("cleanGenre(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestFileFallback(t *testing.T) {
	type want struct {
		title, artist, album string
		track, disc, year    int
	}
	cases := []struct {
		rel  string
		want want
	}{
		{"Tarkan - Karma (2001)/03 Kuzu Kuzu.mp3", want{"Kuzu Kuzu", "Tarkan", "Karma", 3, 0, 2001}},
		{"Pink Floyd/The Wall/CD2/01 Hey You.flac", want{"Hey You", "Pink Floyd", "The Wall", 1, 2, 0}},
		{"Karışık/05. Müslüm Gürses - Affet.m4a", want{"Affet", "Müslüm Gürses", "", 5, 0, 0}},
		{"Klipler/Sezen Aksu - Gülümse (Official Video).mp4", want{"Gülümse", "Sezen Aksu", "", 0, 0, 0}},
		{"Tarkan/Şımarık.mp3", want{"Şımarık", "Tarkan", "", 0, 0, 0}},
		{"1999 - Prince.mp3", want{"Prince", "1999", "", 0, 0, 0}},
		{"loose_song.opus", want{"loose song", "", "", 0, 0, 0}},
		{"Sertab Erener/Album/1-04 Song.flac", want{"Song", "Sertab Erener", "Album", 4, 1, 0}},
	}
	for _, c := range cases {
		var tg Tags
		fileFallback(&tg, c.rel)
		got := want{tg.Title, tg.Artist, tg.Album, tg.TrackNo, tg.DiscNo, tg.Year}
		if got != c.want {
			t.Errorf("fileFallback(%q) = %+v, want %+v", c.rel, got, c.want)
		}
	}
}

func TestTagsWin(t *testing.T) {
	tg := Tags{Title: "Real Title", Artist: "Real Artist", Album: "Real Album", TrackNo: 7}
	fileFallback(&tg, "Other Artist - Other Album/01 File Name.mp3")
	if tg.Title != "Real Title" || tg.Artist != "Real Artist" || tg.Album != "Real Album" || tg.TrackNo != 7 {
		t.Errorf("tags were overwritten: %+v", tg)
	}
}

func TestIsDiscDir(t *testing.T) {
	for in, want := range map[string]int{"CD1": 1, "Disc 2": 2, "disk-3": 3, "CD 12": 12} {
		if n, ok := isDiscDir(in); !ok || n != want {
			t.Errorf("isDiscDir(%q) = %d,%v", in, n, ok)
		}
	}
	if _, ok := isDiscDir("CDs I like"); ok {
		t.Error("CDs I like is not a disc folder")
	}
}
