package names

import "testing"

func TestParseAs(t *testing.T) {
	cases := []struct {
		rel, kind, folder string
		kindWant          Kind
		title, series     string
		season, episode   int
		seriesDir         string
	}{
		{"Breaking Bad S01E02.mkv", "movies", "Arşiv", Movie, "Breaking Bad S01E02", "", 0, 0, ""},
		{"Dune (2021)/Dune.mkv", "movies", "Arşiv", Movie, "Dune", "", 0, 0, ""},
		{"Kurtlar Vadisi/Sezon 2/Bolum 05.mkv", "series", "Diziler2", Episode, "", "Kurtlar Vadisi", 2, 5, "Kurtlar Vadisi"},
		{"Sezon 1/03.mkv", "series", "Ezel", Episode, "", "Ezel", 1, 3, "."},
		{"Ezel 7.mkv", "series", "Ezel", Episode, "", "Ezel", 1, 7, "."},
		{"Breaking Bad S01E03.mkv", "series", "Arsiv", Episode, "", "Breaking Bad", 1, 3, ""},
		{"Filmler/Inception (2010).mkv", "auto", "HomeStream", Movie, "Inception", "", 0, 0, ""},
	}
	for _, c := range cases {
		p := ParseAs(c.rel, c.kind, c.folder)
		if p.Kind != c.kindWant {
			t.Errorf("%s (%s): kind %v, want %v", c.rel, c.kind, p.Kind, c.kindWant)
			continue
		}
		if c.kindWant == Movie {
			if p.Title != c.title {
				t.Errorf("%s: title %q, want %q", c.rel, p.Title, c.title)
			}
			continue
		}
		if p.SeriesTitle != c.series || p.Season != c.season || p.Episode != c.episode || p.SeriesDir != c.seriesDir {
			t.Errorf("%s: got %q S%d E%d dir %q, want %q S%d E%d dir %q", c.rel, p.SeriesTitle, p.Season, p.Episode, p.SeriesDir, c.series, c.season, c.episode, c.seriesDir)
		}
	}
}
