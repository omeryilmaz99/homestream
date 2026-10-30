package files

import (
	"bufio"
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	_ "modernc.org/sqlite"
)

type env struct {
	t    *testing.T
	srv  *httptest.Server
	tok  string
	home string
}

func setup(t *testing.T) *env {
	t.Helper()
	dir := t.TempDir()
	db, err := sql.Open("sqlite", filepath.Join(dir, "db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { db.Close() })
	home := filepath.Join(dir, "home")
	_ = os.MkdirAll(filepath.Join(home, "HomeStream"), 0o755)
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)
	s, err := New(ctx, Config{DB: db, DataDir: filepath.Join(dir, "data"), Home: home, Library: filepath.Join(home, "HomeStream"),
		ServerID: "test", CheckPassword: func(p string) bool { return p == "gizli" }})
	if err != nil {
		t.Fatal(err)
	}
	mux := http.NewServeMux()
	s.Register(mux)
	srv := httptest.NewServer(mux)
	t.Cleanup(srv.Close)
	e := &env{t: t, srv: srv, home: home}
	var out struct {
		Token string `json:"token"`
	}
	if c := e.do("POST", "/api/files/login", map[string]string{"password": "gizli", "device": "test"}, &out); c != 200 || out.Token == "" {
		t.Fatalf("login: %d", c)
	}
	e.tok = out.Token
	return e
}

func (e *env) req(method, path string, body io.Reader, hdr map[string]string) *http.Response {
	e.t.Helper()
	r, _ := http.NewRequest(method, e.srv.URL+path, body)
	if e.tok != "" {
		r.Header.Set("Authorization", "Bearer "+e.tok)
	}
	for k, v := range hdr {
		r.Header.Set(k, v)
	}
	resp, err := http.DefaultClient.Do(r)
	if err != nil {
		e.t.Fatal(err)
	}
	return resp
}

func (e *env) do(method, path string, body any, out any) int {
	e.t.Helper()
	var rd io.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		rd = bytes.NewReader(b)
	}
	resp := e.req(method, path, rd, nil)
	defer resp.Body.Close()
	if out != nil {
		_ = json.NewDecoder(resp.Body).Decode(out)
	}
	return resp.StatusCode
}

func q(p string) string { return url.QueryEscape(p) }

func TestLoginRequired(t *testing.T) {
	e := setup(t)
	e.tok = ""
	if c := e.do("GET", "/api/files/list?path="+q(e.home), nil, nil); c != 401 {
		t.Fatalf("want 401, got %d", c)
	}
	if c := e.do("POST", "/api/files/login", map[string]string{"password": "yanlis"}, nil); c != 403 {
		t.Fatalf("wrong password: %d", c)
	}
}

func TestUploadResumeDownload(t *testing.T) {
	e := setup(t)
	data := bytes.Repeat([]byte("0123456789"), 100000) // 1 MB
	target := filepath.Join(e.home, "yeni klasör", "film.mkv")
	size := len(data)
	// first part only (the connection "drops")
	resp := e.req("PUT", "/api/files/upload?path="+q(target)+"&offset=0&size="+itoa(size), bytes.NewReader(data[:300000]), nil)
	resp.Body.Close()
	var st struct {
		Offset int64 `json:"offset"`
		Exists bool  `json:"exists"`
	}
	e.do("GET", "/api/files/upload?path="+q(target), nil, &st)
	if st.Offset != 300000 || st.Exists {
		t.Fatalf("status after partial: %+v", st)
	}
	// wrong offset is refused with the real one
	var bad struct {
		Offset int64 `json:"offset"`
	}
	resp = e.req("PUT", "/api/files/upload?path="+q(target)+"&offset=100&size="+itoa(size), bytes.NewReader(data[100:]), nil)
	_ = json.NewDecoder(resp.Body).Decode(&bad)
	resp.Body.Close()
	if resp.StatusCode != 409 || bad.Offset != 300000 {
		t.Fatalf("bad offset: %d %+v", resp.StatusCode, bad)
	}
	// the rest
	resp = e.req("PUT", "/api/files/upload?path="+q(target)+"&offset=300000&size="+itoa(size)+"&mtime=1600000000000", bytes.NewReader(data[300000:]), nil)
	var done struct {
		Done bool `json:"done"`
	}
	_ = json.NewDecoder(resp.Body).Decode(&done)
	resp.Body.Close()
	if !done.Done {
		t.Fatal("upload not done")
	}
	got, _ := os.ReadFile(target)
	if !bytes.Equal(got, data) {
		t.Fatal("content differs")
	}
	if fi, _ := os.Stat(target); fi.ModTime().UnixMilli() != 1600000000000 {
		t.Fatal("mtime not kept")
	}
	// existing file → conflict unless asked
	resp = e.req("PUT", "/api/files/upload?path="+q(target)+"&offset=0&size=3", strings.NewReader("abc"), nil)
	resp.Body.Close()
	if resp.StatusCode != 409 {
		t.Fatalf("want conflict, got %d", resp.StatusCode)
	}
	resp = e.req("PUT", "/api/files/upload?path="+q(target)+"&offset=0&size=3&conflict=rename", strings.NewReader("abc"), nil)
	resp.Body.Close()
	if _, err := os.Stat(filepath.Join(e.home, "yeni klasör", "film (2).mkv")); err != nil {
		t.Fatal("renamed copy missing")
	}
	// ranged download (resume)
	resp = e.req("GET", "/api/files/download?path="+q(target), nil, map[string]string{"Range": "bytes=999990-"})
	b, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if resp.StatusCode != 206 || string(b) != "0123456789" {
		t.Fatalf("range: %d %q", resp.StatusCode, b)
	}
	// listing hides the partial files
	var list struct {
		Entries []entryJSON `json:"entries"`
	}
	e.do("GET", "/api/files/list?path="+q(filepath.Dir(target)), nil, &list)
	if len(list.Entries) != 2 {
		t.Fatalf("entries: %+v", list.Entries)
	}
}

func TestTrashAndRestore(t *testing.T) {
	e := setup(t)
	p := filepath.Join(e.home, "not.txt")
	_ = os.WriteFile(p, []byte("x"), 0o644)
	var res struct {
		Results []struct {
			Trash bool `json:"trash"`
		} `json:"results"`
	}
	e.do("POST", "/api/files/delete", map[string]any{"paths": []string{p}}, &res)
	if len(res.Results) != 1 || !res.Results[0].Trash {
		t.Fatalf("delete: %+v", res)
	}
	if _, err := os.Stat(p); !os.IsNotExist(err) {
		t.Fatal("file still there")
	}
	var tr struct {
		Items []trashMeta `json:"items"`
	}
	e.do("GET", "/api/files/trash", nil, &tr)
	if len(tr.Items) != 1 {
		t.Fatalf("trash: %+v", tr)
	}
	e.do("POST", "/api/files/trash/restore", map[string]any{"ids": []string{tr.Items[0].ID}}, nil)
	if _, err := os.Stat(p); err != nil {
		t.Fatal("not restored")
	}
	// the home folder itself is protected
	e.do("POST", "/api/files/delete", map[string]any{"paths": []string{e.home}, "permanent": true}, nil)
	if _, err := os.Stat(e.home); err != nil {
		t.Fatal("home deleted!")
	}
}

func TestCopyJobAndEvents(t *testing.T) {
	e := setup(t)
	src := filepath.Join(e.home, "a")
	_ = os.MkdirAll(filepath.Join(src, "alt"), 0o755)
	_ = os.WriteFile(filepath.Join(src, "alt", "b.txt"), []byte("merhaba"), 0o644)
	dst := filepath.Join(e.home, "HomeStream")

	resp := e.req("GET", "/api/files/events?watch="+q(dst), nil, nil)
	defer resp.Body.Close()
	events := make(chan string, 50)
	go func() {
		sc := bufio.NewScanner(resp.Body)
		for sc.Scan() {
			if ev, ok := strings.CutPrefix(sc.Text(), "event: "); ok {
				events <- ev
			}
		}
	}()
	if ev := <-events; ev != "hello" {
		t.Fatalf("first event %q", ev)
	}
	if c := e.do("POST", "/api/files/copy", map[string]any{"paths": []string{src}, "dest": dst}, nil); c != 202 {
		t.Fatalf("copy: %d", c)
	}
	deadline := time.After(5 * time.Second)
	sawChange := false
	for !sawChange {
		select {
		case ev := <-events:
			sawChange = ev == "change"
		case <-deadline:
			t.Fatal("no change event")
		}
	}
	if b, _ := os.ReadFile(filepath.Join(dst, "a", "alt", "b.txt")); string(b) != "merhaba" {
		t.Fatal("copy missing")
	}
	// copying a folder into itself is refused
	if c := e.do("POST", "/api/files/copy", map[string]any{"paths": []string{src}, "dest": filepath.Join(src, "alt")}, nil); c != 400 {
		t.Fatalf("self copy: %d", c)
	}
}
