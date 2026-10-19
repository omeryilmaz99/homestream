package api

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"homestream/internal/library"
	"homestream/internal/store"
)

func setup(t *testing.T, files ...string) *httptest.Server {
	t.Helper()
	dir := t.TempDir()
	lib := filepath.Join(dir, "lib")
	for _, f := range files {
		p := filepath.Join(lib, f)
		_ = os.MkdirAll(filepath.Dir(p), 0o755)
		fh, err := os.Create(p)
		if err != nil {
			t.Fatal(err)
		}
		_ = fh.Truncate(2 << 20)
		fh.Close()
		old := time.Now().Add(-time.Hour)
		_ = os.Chtimes(p, old, old)
	}
	st, err := store.Open(filepath.Join(dir, "db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { st.Close() })
	_ = st.EnsureDefaultFolder(lib, "HomeStream")
	l := library.New(library.Config{DataDir: filepath.Join(dir, "data")}, st)
	if err := l.ScanOnce(context.Background()); err != nil {
		t.Fatal(err)
	}
	srv := httptest.NewServer((&Server{Lib: l, St: st, Version: "test", DefaultName: "x"}).Handler())
	t.Cleanup(srv.Close)
	return srv
}

func get(t *testing.T, u string, v any) int {
	t.Helper()
	resp, err := http.Get(u)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if v != nil {
		_ = json.NewDecoder(resp.Body).Decode(v)
	}
	return resp.StatusCode
}

func TestSearchTurkishFolding(t *testing.T) {
	srv := setup(t,
		"Filmler/Görevimiz Gülmek (2019).mkv",
		"Filmler/İSTANBUL HATIRASI 2010.mkv",
		"Filmler/Işık Doğudan Yükselir.mkv",
		"Diziler/Çukur/Sezon 1/Çukur 1. Bölüm.mp4",
	)
	cases := map[string]string{
		"gorevimiz":        "Görevimiz Gülmek",
		"GÖREVİMİZ gülmek": "Görevimiz Gülmek",
		"istanbul":         "İSTANBUL HATIRASI",
		"hatırası":         "İSTANBUL HATIRASI",
		"ISIK":             "Işık Doğudan Yükselir",
		"isik dogudan":     "Işık Doğudan Yükselir",
	}
	for q, want := range cases {
		var res searchJSON
		get(t, srv.URL+"/api/search?q="+url.QueryEscape(q), &res)
		if len(res.Movies) != 1 || res.Movies[0].Title != want {
			t.Errorf("search %q: %+v", q, res.Movies)
		}
	}
	var res searchJSON
	get(t, srv.URL+"/api/search?q=cukur", &res)
	if len(res.Series) != 1 || res.Series[0].Title != "Çukur" {
		t.Errorf("series search: %+v", res.Series)
	}
	get(t, srv.URL+"/api/search?q=xyz", &res)
	if len(res.Movies)+len(res.Series)+len(res.Episodes) != 0 {
		t.Errorf("unexpected results")
	}
}

func TestPlaceholderImagesWithoutFFmpeg(t *testing.T) {
	srv := setup(t, "Filmler/Film (2010).mkv")
	var movies []ItemJSON
	get(t, srv.URL+"/api/movies", &movies)
	if len(movies) != 1 || !movies[0].PosterGenerated || movies[0].Duration != 0 {
		t.Fatalf("movies: %+v", movies)
	}
	for _, kind := range []string{"poster", "backdrop", "thumb"} {
		resp, err := http.Get(srv.URL + "/api/images/" + movies[0].ID + "/" + kind + "?w=320")
		if err != nil {
			t.Fatal(err)
		}
		resp.Body.Close()
		if resp.StatusCode != 200 || resp.Header.Get("Content-Type") != "image/jpeg" || resp.Header.Get("ETag") == "" {
			t.Errorf("%s: %d %v", kind, resp.StatusCode, resp.Header)
		}
	}
	var e map[string]string
	if code := get(t, srv.URL+"/api/nope", &e); code != 404 || !strings.Contains(e["error"], "Bulunamadı") {
		t.Errorf("404 json: %d %v", code, e)
	}
}
