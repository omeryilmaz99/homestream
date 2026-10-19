package names

import (
	"sort"
	"testing"
)

func TestFold(t *testing.T) {
	cases := map[string]string{
		"Görevimiz Gülmek":   "gorevimiz gulmek",
		"İSTANBUL":           "istanbul",
		"ISPARTA":            "isparta",
		"ılık":               "ilik",
		"Çağrı Şeker":        "cagri seker",
		"Schindler's List":   "schindlers list",
		"Amélie":             "amelie",
		"  Mr. Robot!! ":     "mr robot",
		"KURTLAR VADİSİ":     "kurtlar vadisi",
		"Kurtlar Vadisi":     "kurtlar vadisi",
		"Bölüm_10":           "bolum 10",
		"\xfeeker":           "seker", // cp1254 ş
		"Spider-Man: No Way": "spider man no way",
	}
	for in, want := range cases {
		if got := Fold(in); got != want {
			t.Errorf("Fold(%q) = %q, want %q", in, got, want)
		}
	}
	if Key("Mr. Robot") != Key("mr robot") || Key("Mr.Robot") != Key("MR ROBOT") {
		t.Error("Key mismatch")
	}
	if Key("ÖZEL") != Key("özel") || Key("ışık") != Key("IŞIK") {
		t.Error("Key turkish mismatch")
	}
}

func TestNaturalSort(t *testing.T) {
	in := []string{"Bölüm 10", "bölüm 2", "Bölüm 1", "Episode 02", "Episode 1", "a", "Çay", "Zeytin", "Bölüm 01"}
	sort.SliceStable(in, func(i, j int) bool { return NaturalLess(in[i], in[j]) })
	want := []string{"a", "Bölüm 1", "Bölüm 01", "bölüm 2", "Bölüm 10", "Çay", "Episode 1", "Episode 02", "Zeytin"}
	for i := range want {
		if in[i] != want[i] {
			t.Fatalf("got %q, want %q", in, want)
		}
	}
	if !NaturalLess("S01E02", "S01E10") || NaturalLess("file10", "file9") {
		t.Error("natural compare wrong")
	}
}

func TestCleanTitle(t *testing.T) {
	cases := []struct {
		in    string
		title string
		year  int
	}{
		{"The.Matrix.1999.1080p.BluRay.x264", "The Matrix", 1999},
		{"Inception (2010)", "Inception", 2010},
		{"Inception(2010)", "Inception", 2010},
		{"Görevimiz Gülmek 2019 1080p WEB-DL", "Görevimiz Gülmek", 2019},
		{"Recep.İvedik.6.2019.WEB-DL.x264", "Recep İvedik 6", 2019},
		{"Avengers.Endgame.2019.2160p.UHD.BluRay.x265.10bit.HDR.TrueHD.7.1.Atmos-TERMINAL", "Avengers Endgame", 2019},
		{"[YTS.MX] Parasite (2019) [1080p]", "Parasite", 2019},
		{"1917", "1917", 0},
		{"1917 (2019)", "1917", 2019},
		{"2001 A Space Odyssey", "2001 A Space Odyssey", 0},
		{"Blade Runner 2049 (2017)", "Blade Runner 2049", 2017},
		{"2012.2009.1080p", "2012", 2009},
		{"Charlotte's Web 2006", "Charlotte's Web", 2006},
		{"the.dark.knight.2008.720p", "The Dark Knight", 2008},
		{"kış uykusu 2014", "Kış Uykusu", 2014},
		{"Movie Name 720p HDTV x264-GRP", "Movie Name", 0},
		{"Babam ve Oğlum Türkçe Dublaj 1080p", "Babam ve Oğlum", 0},
		{"Spider-Man.No.Way.Home.2021.HDR.2160p", "Spider-Man No Way Home", 2021},
		{"www.torrentsite.com - Joker 2019 1080p", "Joker", 2019},
		{"Ayla_The_Daughter_of_War_2017", "Ayla The Daughter of War", 2017},
		{"Movie DDP5.1 x265", "Movie", 0},
	}
	for _, c := range cases {
		title, year := CleanTitle(c.in)
		if title != c.title || year != c.year {
			t.Errorf("CleanTitle(%q) = %q,%d want %q,%d", c.in, title, year, c.title, c.year)
		}
	}
}

func TestParsePath(t *testing.T) {
	type want struct {
		kind    Kind
		title   string
		year    int
		series  string
		syear   int
		season  int
		episode int
		sdir    string
	}
	M := func(title string, year int) want { return want{kind: Movie, title: title, year: year} }
	E := func(series string, season, ep int, title string) want {
		return want{kind: Episode, series: series, season: season, episode: ep, title: title}
	}
	cases := []struct {
		path string
		w    want
		chk  func(p Parsed) bool
	}{
		// movies
		{"Filmler/Inception (2010)/Inception.mkv", M("Inception", 2010), nil},
		{"Filmler/Inception (2010)/movie.mkv", M("Inception", 2010), nil},
		{"Inception (2010)/film.mp4", M("Inception", 2010), nil},
		{"The.Matrix.1999.1080p.BluRay.x264.mkv", M("The Matrix", 1999), nil},
		{"Filmler/Görevimiz Gülmek.2019.1080p.mkv", M("Görevimiz Gülmek", 2019), nil},
		{"Filmler/Avatar/CD1.avi", M("Avatar (CD 1)", 0), nil},
		{"Filmler/Kill Bill Vol 1 (2003)/Kill.Bill.2003.CD2.avi", M("Kill Bill (CD 2)", 2003), nil},
		{"Filmler/Star.Wars.Episode.1.The.Phantom.Menace.1999.mkv", M("Star Wars Episode 1 The Phantom Menace", 1999), nil},
		{"Filmler/Harry Potter ve Ölüm Yadigarları Bölüm 1 (2010).mkv", M("Harry Potter ve Ölüm Yadigarları Bölüm 1", 2010), nil},
		{"Filmler/1917.mkv", M("1917", 0), nil},
		{"Filmler/Koleksiyon/Rocky 2 (1979).mkv", M("Rocky 2", 1979), nil},
		{"Filmler/Joker/Joker.2019.1080p.mkv", M("Joker", 2019), nil},

		// SxxEyy forms
		{"Diziler/Breaking Bad/Season 1/Breaking.Bad.S01E02.720p.mkv", E("Breaking Bad", 1, 2, ""), nil},
		{"Breaking Bad/Season 1/Breaking.Bad.S01E02.Cats.in.the.Bag.720p.mkv", E("Breaking Bad", 1, 2, "Cats in the Bag"), nil},
		{"Breaking.Bad.s1e2.mkv", E("Breaking Bad", 1, 2, ""), nil},
		{"Show/Show.S01E02E03.mkv", E("Show", 1, 2, ""), nil},
		{"Friends.1x02.The.One.With.mkv", E("Friends", 1, 2, "The One With"), nil},
		{"Dark/Dark.S01.E05.mkv", E("Dark", 1, 5, ""), nil},
		{"Dark.2017.S02E03.1080p.mkv", want{kind: Episode, series: "Dark", syear: 2017, season: 2, episode: 3}, nil},
		{"The Office (US)/S03/The.Office.US.S03E10.mkv", E("The Office (US)", 3, 10, ""), nil},
		{"Diziler/Breaking.Bad.S01.1080p.BluRay/Breaking.Bad.S01E01.mkv", E("Breaking Bad", 1, 1, ""), nil},
		{"Diziler/Breaking Bad Season 2/Breaking.Bad.S02E01.mkv", E("Breaking Bad", 2, 1, ""), nil},
		{"Lost/Season 1/Episode 2.mkv", E("Lost", 1, 2, ""), nil},
		{"Lost/Season 3/Lost - Episode 12 - Title Here.mkv", E("Lost", 3, 12, "Title Here"), nil},
		{"Breaking Bad (2008)/Season 01/01 - Pilot.mkv", want{kind: Episode, series: "Breaking Bad", syear: 2008, season: 1, episode: 1, title: "Pilot"}, nil},
		{"Breaking Bad/Specials/Breaking.Bad.S00E01.mkv", E("Breaking Bad", 0, 1, ""), nil},
		{"Breaking Bad/Specials/Making Of.mkv", E("Breaking Bad", 0, 0, "Making Of"), nil},
		{"Show.S01E02.1080p.WEB-DL/Show.S01E02.1080p.WEB-DL.mkv", E("Show", 1, 2, ""), nil},
		{"Season 1/Lone.Show.S01E03.mkv", E("Lone Show", 1, 3, ""), nil},

		// Turkish
		{"Kurtlar Vadisi/Sezon 1/Bölüm 2.mp4", E("Kurtlar Vadisi", 1, 2, ""), nil},
		{"Kurtlar Vadisi/1. Sezon/2. Bölüm.mp4", E("Kurtlar Vadisi", 1, 2, ""), nil},
		{"Kurtlar Vadisi/Sezon 2/Kurtlar Vadisi 10. Bölüm.mp4", E("Kurtlar Vadisi", 2, 10, ""), nil},
		{"Diziler/Yargı/Yargı 1. Sezon 5. Bölüm.mp4", E("Yargı", 1, 5, ""), nil},
		{"Yargı Sezon 2 Bölüm 7.mp4", E("Yargı", 2, 7, ""), nil},
		{"Diziler/Yargı/Yargı.2.Bölüm.mp4", E("Yargı", 1, 2, ""), nil},
		{"Diziler/Ezel/Ezel Bölüm 12.avi", E("Ezel", 1, 12, ""), nil},
		{"Ezel Bölüm 12.avi", E("Ezel", 1, 12, ""), nil},
		{"Leyla ile Mecnun/Sezon 1/E03.mkv", E("Leyla ile Mecnun", 1, 3, ""), nil},
		{"Leyla ile Mecnun/Sezon 1/Ep 04 Bir Başlık.mkv", E("Leyla ile Mecnun", 1, 4, "Bir Başlık"), nil},
		{"Leyla ile Mecnun/2. Sezon/03 - Başlık.mkv", E("Leyla ile Mecnun", 2, 3, "Başlık"), nil},
		{"Diziler/Avrupa Yakası/01.mp4", E("Avrupa Yakası", 1, 1, ""), nil},
		{"Diziler/Avrupa Yakası/Avrupa Yakası 12.mp4", E("Avrupa Yakası", 1, 12, ""), nil},
		{"Diziler/Avrupa Yakası/Sezon 3/05.mp4", E("Avrupa Yakası", 3, 5, ""), nil},
		{"Diziler/Avrupa Yakası 2. Sezon/05.mp4", E("Avrupa Yakası", 2, 5, ""), nil},

		// leading number outside season folder → movie
		{"Filmler/02 - Something.mkv", M("02 - Something", 0), nil},
	}
	for _, c := range cases {
		p := ParsePath(c.path)
		w := c.w
		bad := p.Kind != w.kind
		if w.kind == Movie {
			bad = bad || p.Title != w.title || p.Year != w.year
		} else {
			bad = bad || p.SeriesTitle != w.series || p.Season != w.season || p.Episode != w.episode || p.Title != w.title
			if w.syear != 0 && p.SeriesYear != w.syear {
				bad = true
			}
		}
		if w.sdir != "" && p.SeriesDir != w.sdir {
			bad = true
		}
		if bad {
			t.Errorf("ParsePath(%q) = %+v\n  want %+v", c.path, p, w)
		}
	}
}

func TestSeriesDir(t *testing.T) {
	cases := map[string]string{
		"Diziler/Breaking Bad/Season 1/x.S01E01.mkv": "Diziler/Breaking Bad",
		"Breaking Bad/S01/x.S01E01.mkv":              "Breaking Bad",
		"Dark/Dark.S01E01.mkv":                       "Dark",
		"Dark.S01E01.mkv":                            "",
		"Diziler/Yargı/Sezon 1/Bölüm 1.mp4":          "Diziler/Yargı",
	}
	for in, want := range cases {
		if got := ParsePath(in).SeriesDir; got != want {
			t.Errorf("SeriesDir(%q) = %q, want %q", in, got, want)
		}
	}
	if !ParsePath("Dark/Dark.S01E01.mkv").TitleFromFolder {
		t.Error("TitleFromFolder expected")
	}
}

func TestParseSubtitle(t *testing.T) {
	cases := []struct {
		video, sub string
		lang       string
		forced     bool
		title      string
	}{
		{"Movie", "Movie.tr.srt", "tr", false, "Türkçe"},
		{"Movie", "Movie.Turkish.srt", "tr", false, "Türkçe"},
		{"Movie", "Movie.eng.forced.srt", "en", true, "İngilizce (Zorunlu)"},
		{"Movie", "Movie.srt", "", false, "Harici altyazı"},
		{"", "2_English.srt", "en", false, "İngilizce"},
		{"Movie", "Movie.TÜRKÇE.ass", "tr", false, "Türkçe"},
		{"Movie.2010.1080p", "Movie.2010.1080p.en.sdh.srt", "en", false, "İngilizce (SDH)"},
	}
	for _, c := range cases {
		got := ParseSubtitle(c.video, c.sub)
		if got.Language != c.lang || got.Forced != c.forced || got.Title != c.title {
			t.Errorf("ParseSubtitle(%q,%q) = %+v", c.video, c.sub, got)
		}
	}
}
