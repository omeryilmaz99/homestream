package library

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"image"
	"image/jpeg"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"homestream/internal/store"
)

func mkVideo(t *testing.T, p string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		t.Fatal(err)
	}
	f, err := os.Create(p)
	if err != nil {
		t.Fatal(err)
	}
	if err := f.Truncate(2 << 20); err != nil {
		t.Fatal(err)
	}
	f.Close()
	old := time.Now().Add(-3 * time.Hour)
	_ = os.Chtimes(p, old, old)
}

func newTestLib(t *testing.T, cfg Config) (*Library, string) {
	t.Helper()
	dir := t.TempDir()
	lib := filepath.Join(dir, "lib")
	_ = os.MkdirAll(lib, 0o755)
	st, err := store.Open(filepath.Join(dir, "test.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { st.Close() })
	if err := st.EnsureDefaultFolder(lib, "HomeStream"); err != nil {
		t.Fatal(err)
	}
	cfg.DataDir = filepath.Join(dir, "data")
	cfg.DefaultLibrary = lib
	return New(cfg, st), lib
}

func tinyJPEG() []byte {
	var buf bytes.Buffer
	_ = jpeg.Encode(&buf, image.NewRGBA(image.Rect(0, 0, 20, 30)), nil)
	return buf.Bytes()
}

func fakeTMDB(t *testing.T, key string, bearer bool, hits *atomic.Int64) *httptest.Server {
	img := tinyJPEG()
	mux := http.NewServeMux()
	auth := func(r *http.Request) bool {
		if bearer {
			return r.Header.Get("Authorization") == "Bearer "+key
		}
		return r.URL.Query().Get("api_key") == key
	}
	js := func(w http.ResponseWriter, v any) { _ = json.NewEncoder(w).Encode(v) }
	mux.HandleFunc("/img/", func(w http.ResponseWriter, r *http.Request) { w.Write(img) })
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		hits.Add(1)
		if !auth(r) {
			w.WriteHeader(http.StatusUnauthorized)
			return
		}
		q := r.URL.Query()
		lang := q.Get("language")
		switch r.URL.Path {
		case "/search/movie":
			if q.Get("query") == "Inception" {
				js(w, map[string]any{"results": []map[string]any{
					{"id": 999, "title": "Inception Making Of", "original_title": "Inception: The Making", "release_date": "2011-01-01"},
					{"id": 27205, "title": "Başlangıç", "original_title": "Inception", "release_date": "2010-07-15"},
				}})
				return
			}
			js(w, map[string]any{"results": []any{}})
		case "/movie/27205":
			ov := ""
			if lang == "en-US" {
				ov = "A thief who steals corporate secrets."
			}
			js(w, map[string]any{"id": 27205, "title": map[bool]string{true: "Inception", false: "Başlangıç"}[lang == "en-US"],
				"original_title": "Inception", "overview": ov, "vote_average": 8.4, "release_date": "2010-07-15",
				"genres":      []map[string]any{{"name": "Bilim Kurgu"}, {"name": "Aksiyon"}},
				"poster_path": "/p.jpg", "backdrop_path": "/b.jpg"})
		case "/search/tv":
			js(w, map[string]any{"results": []map[string]any{{"id": 1396, "name": "Breaking Bad", "original_name": "Breaking Bad", "first_air_date": "2008-01-20"}}})
		case "/tv/1396":
			js(w, map[string]any{"id": 1396, "name": "Breaking Bad", "original_name": "Breaking Bad", "overview": "Kimya öğretmeni…",
				"vote_average": 8.9, "first_air_date": "2008-01-20", "genres": []map[string]any{{"name": "Dram"}, {"name": "Suç"}},
				"poster_path": "/sp.jpg", "backdrop_path": "/sb.jpg"})
		case "/tv/1396/season/1":
			js(w, map[string]any{"episodes": []map[string]any{
				{"episode_number": 1, "name": "Pilot", "overview": "Walter…", "still_path": "/s1.jpg", "vote_average": 7.9},
				{"episode_number": 2, "name": "Kedi Çantada", "overview": "", "still_path": ""},
			}})
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	})
	srv := httptest.NewServer(mux)
	t.Cleanup(srv.Close)
	return srv
}

func TestMetadataTMDB(t *testing.T) {
	for _, bearer := range []bool{false, true} {
		key := "0123456789abcdef0123456789abcdef"
		if bearer {
			key = "eyJhbGciOiJIUzI1NiJ9.eyJhdWQiOiJ4In0.signature-signature-signature"
		}
		var hits atomic.Int64
		srv := fakeTMDB(t, key, bearer, &hits)
		l, lib := newTestLib(t, Config{TMDBBaseURL: srv.URL, TMDBImageBase: srv.URL + "/img"})
		mkVideo(t, filepath.Join(lib, "Filmler", "Inception (2010)", "Inception.mkv"))
		mkVideo(t, filepath.Join(lib, "Filmler", "Bilinmeyen Bir Film 1999.mkv"))
		mkVideo(t, filepath.Join(lib, "Diziler", "Breaking Bad", "Season 1", "Breaking.Bad.S01E01.mkv"))
		mkVideo(t, filepath.Join(lib, "Diziler", "Breaking Bad", "Season 1", "Breaking.Bad.S01E02.mkv"))
		_ = l.St.SetSetting("tmdbApiKey", key)
		if err := l.scan(context.Background(), false); err != nil {
			t.Fatalf("scan: %v", err)
		}
		snap := l.Snap()
		var inc, unk *Item
		for _, m := range snap.Movies {
			switch m.ParsedTitle {
			case "Inception":
				inc = m
			case "Bilinmeyen Bir Film":
				unk = m
			}
		}
		if inc == nil || unk == nil {
			t.Fatalf("movies missing: %+v", snap.Movies)
		}
		if inc.Title != "Başlangıç" || inc.OriginalTitle != "Inception" || inc.TMDBID != 27205 || inc.Rating != 8.4 {
			t.Errorf("movie meta: %+v", inc)
		}
		if inc.Overview != "A thief who steals corporate secrets." {
			t.Errorf("en-US overview fallback: %q", inc.Overview)
		}
		if strings.Join(inc.Genres, ",") != "Bilim Kurgu,Aksiyon" || !inc.RealPoster() || !fileExists(inc.TMDBPoster) || !fileExists(inc.TMDBBackdrop) {
			t.Errorf("movie genres/images: %+v", inc)
		}
		if !strings.Contains(inc.Search, "inception") || !strings.Contains(inc.Search, "baslangic") {
			t.Errorf("search text: %q", inc.Search)
		}
		if unk.Title != "Bilinmeyen Bir Film" || unk.RealPoster() {
			t.Errorf("unknown movie: %+v", unk)
		}
		if m, ok := l.St.GetMeta(unk.ID); !ok || m.Status != "notfound" {
			t.Errorf("notfound not cached: %+v", m)
		}
		if len(snap.Series) != 1 {
			t.Fatalf("series: %d", len(snap.Series))
		}
		ser := snap.Series[0]
		if ser.Year != 2008 || strings.Join(ser.Genres, ",") != "Dram,Suç" || !ser.RealPoster() {
			t.Errorf("series meta: %+v", ser)
		}
		e1, e2 := ser.Episodes[0], ser.Episodes[1]
		if e1.Title != "Pilot" || e1.Overview != "Walter…" || !fileExists(e1.TMDBBackdrop) || e2.Title != "Kedi Çantada" {
			t.Errorf("episode meta: %+v / %+v", e1, e2)
		}
		if strings.Join(e1.Genres, ",") != "Dram,Suç" {
			t.Errorf("episode genres: %v", e1.Genres)
		}
		// second scan must be served from cache
		before := hits.Load()
		if err := l.scan(context.Background(), false); err != nil {
			t.Fatalf("rescan: %v", err)
		}
		if hits.Load() != before {
			t.Errorf("rescan hit TMDB %d times", hits.Load()-before)
		}
	}
}

func TestMetadataBadKey(t *testing.T) {
	var hits atomic.Int64
	srv := fakeTMDB(t, "right", false, &hits)
	l, lib := newTestLib(t, Config{TMDBBaseURL: srv.URL, TMDBImageBase: srv.URL + "/img"})
	mkVideo(t, filepath.Join(lib, "Inception (2010).mkv"))
	_ = l.St.SetSetting("tmdbApiKey", "wrong")
	err := l.scan(context.Background(), false)
	if !errors.Is(err, ErrTMDBAuth) {
		t.Fatalf("want auth error, got %v", err)
	}
	if len(l.Snap().Movies) != 1 {
		t.Fatal("movie should still be listed")
	}
}

func TestMetadataUnreachable(t *testing.T) {
	l, lib := newTestLib(t, Config{TMDBBaseURL: "http://127.0.0.1:1", TMDBImageBase: "http://127.0.0.1:1"})
	mkVideo(t, filepath.Join(lib, "A (2010).mkv"))
	mkVideo(t, filepath.Join(lib, "B (2011).mkv"))
	mkVideo(t, filepath.Join(lib, "C (2012).mkv"))
	mkVideo(t, filepath.Join(lib, "D (2013).mkv"))
	_ = l.St.SetSetting("tmdbApiKey", "k")
	start := time.Now()
	err := l.scan(context.Background(), false)
	if err == nil || time.Since(start) > 20*time.Second {
		t.Fatalf("err=%v after %s", err, time.Since(start))
	}
	if len(l.Snap().Movies) != 4 {
		t.Fatal("movies should be listed")
	}
	all, _ := l.St.AllMeta()
	if len(all) != 0 {
		t.Fatalf("nothing should be cached on network errors: %v", all)
	}
}

func TestScanRules(t *testing.T) {
	l, lib := newTestLib(t, Config{})
	mkVideo(t, filepath.Join(lib, "Filmler", "Movie (2010)", "Movie.mkv"))
	mkVideo(t, filepath.Join(lib, "Filmler", "Movie (2010)", "Movie.sample.mkv")) // sample < 300MB
	mkVideo(t, filepath.Join(lib, ".hidden", "X.mkv"))
	mkVideo(t, filepath.Join(lib, "$RECYCLE.BIN", "Y.mkv"))
	mkVideo(t, filepath.Join(lib, "Filmler", "image.iso"))
	_ = os.WriteFile(filepath.Join(lib, "Filmler", "small.mkv"), []byte("x"), 0o644)
	_ = os.WriteFile(filepath.Join(lib, "Filmler", "Movie (2010)", "Movie.tr.srt"), []byte("1"), 0o644)
	_ = os.WriteFile(filepath.Join(lib, "Filmler", "Movie (2010)", "folder.jpg"), tinyJPEG(), 0o644)
	_ = os.MkdirAll(filepath.Join(lib, "Filmler", "Movie (2010)", "Subs"), 0o755)
	_ = os.WriteFile(filepath.Join(lib, "Filmler", "Movie (2010)", "Subs", "2_English.srt"), []byte("1"), 0o644)
	_ = os.Symlink(filepath.Join(lib, "Filmler"), filepath.Join(lib, "Filmler", "Movie (2010)", "loop"))
	// non UTF-8 file name (cp1254 "Şeker")
	mkVideo(t, filepath.Join(lib, "Filmler", "\xdeeker (2001).mkv"))
	if err := l.scan(context.Background(), false); err != nil {
		t.Fatal(err)
	}
	snap := l.Snap()
	if len(snap.Movies) != 2 {
		for _, m := range snap.Movies {
			t.Log(m.RelPath)
		}
		t.Fatalf("want 2 movies, got %d", len(snap.Movies))
	}
	var mv *Item
	titles := map[string]bool{}
	for _, m := range snap.Movies {
		titles[m.Title] = true
		if m.Title == "Movie" {
			mv = m
		}
	}
	if !titles["Şeker"] || mv == nil {
		t.Fatalf("titles: %v", titles)
	}
	if len(mv.Subs) != 2 || mv.Subs[0].Language != "tr" || mv.Subs[1].Language != "en" {
		t.Errorf("subs: %+v", mv.Subs)
	}
	if !strings.HasSuffix(mv.LocalPoster, "folder.jpg") {
		t.Errorf("local poster: %q", mv.LocalPoster)
	}
	// incremental: unchanged files keep addedAt
	added := mv.AddedAt
	if err := l.scan(context.Background(), false); err != nil {
		t.Fatal(err)
	}
	if l.Snap().Items[mv.ID].AddedAt != added {
		t.Error("addedAt changed on rescan")
	}
}

// In a series folder every show folder is one series, however deep it is,
// and two show folders with the same name stay separate.
func TestSeriesFolderNesting(t *testing.T) {
	l, lib := newTestLib(t, Config{})
	root := filepath.Join(filepath.Dir(lib), "Diziler")
	mk := func(rel string) { mkVideo(t, filepath.Join(root, filepath.FromSlash(rel))) }
	mk("Yabancı/Breaking Bad/Season 1/Breaking.Bad.S01E01.mkv")
	mk("Yabancı/Breaking Bad/Season 1/Breaking.Bad.S01E02.mkv")
	mk("Türk/Örnek Klasör 1/01.mp4")
	mk("Türk/Örnek Klasör 1/02.mp4")
	mk("Türk/Örnek Klasör 2/Dizi 1/1.Bölüm.mp4")
	mk("Türk/Örnek Klasör 2/Dizi 1/2.Bölüm.mp4")
	mk("Türk/Örnek Klasör 2/Dizi 2/Bölümler/01.mkv")
	mk("Türk/Örnek Klasör 2/Dizi 2/Bölümler/02.mkv")
	mk("Türk/Örnek Klasör 2/Dizi 2/Bölümler/03.mkv")
	mk("Arşiv A/Kayıp/01.mp4")
	mk("Arşiv B/Kayıp/01.mp4")
	if _, err := l.St.AddFolder(root, "Diziler", store.FolderSeries); err != nil {
		t.Fatal(err)
	}
	if err := l.scan(context.Background(), false); err != nil {
		t.Fatal(err)
	}
	got := map[string]int{}
	for _, s := range l.Snap().Series {
		got[s.Title] += 1
		t.Logf("%s: %d bölüm", s.Title, len(s.Episodes))
	}
	want := map[string]int{"Breaking Bad": 1, "Örnek Klasör 1": 1, "Dizi 1": 1, "Dizi 2": 1, "Kayıp": 2}
	for k, v := range want {
		if got[k] != v {
			t.Errorf("%s: %d series, want %d (all: %v)", k, got[k], v, got)
		}
	}
	if len(got) != len(want) {
		t.Errorf("series: %v", got)
	}
}
