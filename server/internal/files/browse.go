package files

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"image"
	_ "image/gif"
	"image/jpeg"
	_ "image/png"
	"io"
	"io/fs"
	"mime"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"golang.org/x/image/draw"
	_ "golang.org/x/image/webp"
)

func itoa(n int) string { return strconv.Itoa(n) }

// Place is a shortcut shown in the app (home, library folders, disks).
type Place struct {
	Name string `json:"name"`
	Path string `json:"path"`
	Kind string `json:"kind"` // home | library | music | disk | root
	// filled in by the service
	Total     uint64 `json:"total,omitempty"`
	Free      uint64 `json:"free,omitempty"`
	Available bool   `json:"available"`
}

var hiddenSystem = map[string]bool{"/proc": true, "/sys": true, "/dev": true, "/run": true}

func (s *Service) places() []Place {
	var out []Place
	seen := map[string]bool{}
	add := func(p Place) {
		if p.Path == "" || seen[p.Path] {
			return
		}
		seen[p.Path] = true
		st, err := os.Stat(p.Path)
		p.Available = err == nil && st.IsDir()
		if p.Available {
			p.Total, p.Free = diskSpace(p.Path)
		}
		out = append(out, p)
	}
	add(Place{Name: "Ana klasör", Path: s.cfg.Home, Kind: "home"})
	if s.cfg.Library != "" {
		add(Place{Name: filepath.Base(s.cfg.Library), Path: s.cfg.Library, Kind: "library"})
	}
	if s.cfg.LibraryDirs != nil {
		for _, p := range s.cfg.LibraryDirs() {
			add(p)
		}
	}
	if s.cfg.DrivesDir != "" {
		if des, err := os.ReadDir(s.cfg.DrivesDir); err == nil {
			for _, de := range des {
				if de.IsDir() && !strings.HasPrefix(de.Name(), ".") {
					add(Place{Name: de.Name(), Path: filepath.Join(s.cfg.DrivesDir, de.Name()), Kind: "disk"})
				}
			}
		}
	}
	for _, m := range mounts() {
		if m.removable || strings.HasPrefix(m.Dir, "/media/") || strings.HasPrefix(m.Dir, "/mnt/") {
			add(Place{Name: filepath.Base(m.Dir), Path: m.Dir, Kind: "disk"})
		}
	}
	add(Place{Name: "Sistem (/)", Path: "/", Kind: "root"})
	return out
}

func (s *Service) handleRoots(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{"home": s.cfg.Home, "places": s.places(), "server": s.serverInfo()})
}

type entryJSON struct {
	Name   string `json:"name"`
	Dir    bool   `json:"dir"`
	Size   int64  `json:"size"`
	Mtime  int64  `json:"mtime"` // ms
	Link   bool   `json:"link,omitempty"`
	Hidden bool   `json:"hidden,omitempty"`
	Mode   string `json:"mode,omitempty"`
	Broken bool   `json:"broken,omitempty"`
	Count  int    `json:"count,omitempty"` // entries in a folder (-1 = unknown)
}

const partSuffix = ".hspart"

func isPart(name string) bool {
	return strings.HasPrefix(name, ".") && strings.HasSuffix(name, partSuffix)
}

func entryOf(dir string, de fs.DirEntry) (entryJSON, bool) {
	name := de.Name()
	full := filepath.Join(dir, name)
	if hiddenSystem[full] || isPart(name) || name == trashDirName {
		return entryJSON{}, false
	}
	e := entryJSON{Name: name, Hidden: strings.HasPrefix(name, ".")}
	info, err := de.Info()
	if err != nil {
		return entryJSON{}, false
	}
	if info.Mode()&os.ModeSymlink != 0 {
		e.Link = true
		if t, err := os.Stat(full); err == nil {
			info = t
		} else {
			e.Broken = true
		}
	}
	e.Dir = info.IsDir()
	e.Mtime = info.ModTime().UnixMilli()
	e.Mode = info.Mode().Perm().String()
	if !e.Dir {
		e.Size = info.Size()
	}
	return e, true
}

func (s *Service) handleList(w http.ResponseWriter, r *http.Request) {
	p, ok := s.pathParam(w, r)
	if !ok {
		return
	}
	st, err := os.Stat(p)
	if err != nil {
		fsError(w, err, "Klasör açılamadı")
		return
	}
	if !st.IsDir() {
		writeError(w, http.StatusBadRequest, "Bu bir klasör değil")
		return
	}
	des, err := os.ReadDir(p)
	if err != nil && len(des) == 0 {
		fsError(w, err, "Klasör açılamadı")
		return
	}
	entries := make([]entryJSON, 0, len(des))
	for _, de := range des {
		if e, ok := entryOf(p, de); ok {
			entries = append(entries, e)
		}
	}
	// folder sizes are not computed (slow); counts are cheap enough for small lists
	if len(entries) <= 400 {
		var wg sync.WaitGroup
		sem := make(chan struct{}, 8)
		for i := range entries {
			if !entries[i].Dir {
				continue
			}
			wg.Add(1)
			sem <- struct{}{}
			go func(i int) {
				defer wg.Done()
				defer func() { <-sem }()
				f, err := os.Open(filepath.Join(p, entries[i].Name))
				if err != nil {
					entries[i].Count = -1
					return
				}
				names, _ := f.Readdirnames(10001)
				f.Close()
				entries[i].Count = len(names)
			}(i)
		}
		wg.Wait()
	}
	sort.Slice(entries, func(i, j int) bool {
		if entries[i].Dir != entries[j].Dir {
			return entries[i].Dir
		}
		return naturalLess(entries[i].Name, entries[j].Name)
	})
	total, free := diskSpace(p)
	var parent any
	if p != "/" {
		parent = filepath.Dir(p)
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"path": p, "parent": parent, "entries": entries, "total": total, "free": free,
		"writable": writable(p), "mtime": st.ModTime().UnixMilli(),
	})
}

func (s *Service) handleStat(w http.ResponseWriter, r *http.Request) {
	p, ok := s.pathParam(w, r)
	if !ok {
		return
	}
	lst, err := os.Lstat(p)
	if err != nil {
		if os.IsNotExist(err) {
			writeJSON(w, http.StatusOK, map[string]any{"exists": false, "path": p})
			return
		}
		fsError(w, err, "Bilgi alınamadı")
		return
	}
	de := fs.FileInfoToDirEntry(lst)
	e, _ := entryOf(filepath.Dir(p), de)
	e.Name = filepath.Base(p)
	out := map[string]any{"exists": true, "path": p, "entry": e}
	if e.Dir && r.URL.Query().Get("deep") == "1" {
		ctx, cancel := context.WithTimeout(r.Context(), 20*time.Second)
		defer cancel()
		files, dirs, size, done := 0, 0, int64(0), true
		_ = filepath.WalkDir(p, func(_ string, d fs.DirEntry, err error) error {
			if ctx.Err() != nil {
				done = false
				return filepath.SkipAll
			}
			if err != nil {
				return nil
			}
			if d.IsDir() {
				dirs++
			} else if info, err := d.Info(); err == nil && info.Mode().IsRegular() {
				files++
				size += info.Size()
			}
			return nil
		})
		out["files"], out["dirs"], out["size"], out["complete"] = files, max(dirs-1, 0), size, done
	}
	writeJSON(w, http.StatusOK, out)
}

type treeFile struct {
	Rel   string `json:"rel"`
	Size  int64  `json:"size"`
	Mtime int64  `json:"mtime"`
}

const treeLimit = 200000

// handleTree lists every file under a folder (for downloading a whole folder).
func (s *Service) handleTree(w http.ResponseWriter, r *http.Request) {
	p, ok := s.pathParam(w, r)
	if !ok {
		return
	}
	hidden := r.URL.Query().Get("hidden") == "1"
	files := []treeFile{}
	dirs := []string{}
	var total int64
	truncated := false
	err := filepath.WalkDir(p, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			if path == p {
				return err
			}
			return nil
		}
		if r.Context().Err() != nil {
			return r.Context().Err()
		}
		name := d.Name()
		if path != p && (isPart(name) || name == trashDirName || (!hidden && strings.HasPrefix(name, ".")) || hiddenSystem[path]) {
			if d.IsDir() {
				return filepath.SkipDir
			}
			return nil
		}
		rel, _ := filepath.Rel(p, path)
		if d.IsDir() {
			if rel != "." {
				dirs = append(dirs, filepath.ToSlash(rel))
			}
			return nil
		}
		info, err := d.Info()
		if err != nil || !info.Mode().IsRegular() {
			return nil
		}
		if len(files) >= treeLimit {
			truncated = true
			return filepath.SkipAll
		}
		files = append(files, treeFile{Rel: filepath.ToSlash(rel), Size: info.Size(), Mtime: info.ModTime().UnixMilli()})
		total += info.Size()
		return nil
	})
	if err != nil {
		fsError(w, err, "Klasör okunamadı")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"path": p, "files": files, "dirs": dirs, "size": total, "truncated": truncated})
}

// handleSearch finds names containing q (case and Turkish letters folded) under path.
func (s *Service) handleSearch(w http.ResponseWriter, r *http.Request) {
	p, ok := s.pathParam(w, r)
	if !ok {
		return
	}
	q := foldName(strings.TrimSpace(r.URL.Query().Get("q")))
	if q == "" {
		writeError(w, http.StatusBadRequest, "Aranacak bir şey yaz")
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 15*time.Second)
	defer cancel()
	type hit struct {
		entryJSON
		Path string `json:"path"`
	}
	hits := []hit{}
	scanned := 0
	complete := true
	_ = filepath.WalkDir(p, func(path string, d fs.DirEntry, err error) error {
		if ctx.Err() != nil {
			complete = false
			return filepath.SkipAll
		}
		if err != nil || path == p {
			return nil
		}
		if hiddenSystem[path] || d.Name() == trashDirName {
			return filepath.SkipDir
		}
		scanned++
		if strings.Contains(foldName(d.Name()), q) {
			if e, ok := entryOf(filepath.Dir(path), d); ok {
				hits = append(hits, hit{e, path})
				if len(hits) >= 500 {
					complete = false
					return filepath.SkipAll
				}
			}
		}
		return nil
	})
	writeJSON(w, http.StatusOK, map[string]any{"results": hits, "scanned": scanned, "complete": complete})
}

func (s *Service) handleDownload(w http.ResponseWriter, r *http.Request) {
	p, ok := s.pathParam(w, r)
	if !ok {
		return
	}
	f, err := os.Open(p)
	if err != nil {
		fsError(w, err, "Dosya açılamadı")
		return
	}
	defer f.Close()
	st, err := f.Stat()
	if err != nil || st.IsDir() {
		writeError(w, http.StatusBadRequest, "Bu bir dosya değil")
		return
	}
	name := filepath.Base(p)
	disp := "attachment"
	if r.URL.Query().Get("inline") == "1" {
		disp = "inline"
	}
	w.Header().Set("Content-Disposition", disp+"; filename*=UTF-8''"+url.PathEscape(name))
	if ct := mime.TypeByExtension(strings.ToLower(filepath.Ext(name))); ct != "" {
		w.Header().Set("Content-Type", ct)
	} else {
		w.Header().Set("Content-Type", "application/octet-stream")
	}
	w.Header().Set("X-File-Size", strconv.FormatInt(st.Size(), 10))
	w.Header().Set("X-File-Mtime", strconv.FormatInt(st.ModTime().UnixMilli(), 10))
	// a stalled reader must not hold the file forever
	rc := http.NewResponseController(w)
	http.ServeContent(&deadlineWriter{ResponseWriter: w, rc: rc}, r, name, st.ModTime(), f)
}

// deadlineWriter pushes the write deadline forward on each write, so a client
// that stops reading is dropped after a minute.
type deadlineWriter struct {
	http.ResponseWriter
	rc   *http.ResponseController
	last time.Time
}

func (d *deadlineWriter) Write(b []byte) (int, error) {
	if now := time.Now(); now.Sub(d.last) > 5*time.Second {
		d.last = now
		_ = d.rc.SetWriteDeadline(now.Add(60 * time.Second))
	}
	return d.ResponseWriter.Write(b)
}

var thumbSem = make(chan struct{}, 2)

func (s *Service) handleThumb(w http.ResponseWriter, r *http.Request) {
	p, ok := s.pathParam(w, r)
	if !ok {
		return
	}
	size, _ := strconv.Atoi(r.URL.Query().Get("w"))
	if size <= 0 || size > 1024 {
		size = 256
	}
	st, err := os.Stat(p)
	if err != nil || st.IsDir() {
		writeError(w, http.StatusNotFound, "Önizleme yok")
		return
	}
	if st.Size() > 60<<20 {
		writeError(w, http.StatusUnprocessableEntity, "Önizleme için dosya çok büyük")
		return
	}
	etag := `"` + strconv.FormatInt(st.ModTime().UnixNano(), 36) + "-" + strconv.Itoa(size) + `"`
	if r.Header.Get("If-None-Match") == etag {
		w.WriteHeader(http.StatusNotModified)
		return
	}
	cacheDir := filepath.Join(s.cfg.DataDir, "file-thumbs")
	sum := sha256.Sum256([]byte(p + "|" + etag))
	cachePath := filepath.Join(cacheDir, hex.EncodeToString(sum[:12])+".jpg")
	if data, err := os.ReadFile(cachePath); err == nil {
		writeThumb(w, etag, data)
		return
	}
	select {
	case thumbSem <- struct{}{}:
		defer func() { <-thumbSem }()
	case <-r.Context().Done():
		return
	}
	f, err := os.Open(p)
	if err != nil {
		fsError(w, err, "Önizleme")
		return
	}
	defer f.Close()
	cfg, _, err := image.DecodeConfig(f)
	if err != nil || cfg.Width*cfg.Height > 80_000_000 {
		writeError(w, http.StatusUnprocessableEntity, "Önizleme yapılamıyor")
		return
	}
	_, _ = f.Seek(0, io.SeekStart)
	img, _, err := image.Decode(f)
	if err != nil {
		writeError(w, http.StatusUnprocessableEntity, "Önizleme yapılamıyor")
		return
	}
	b := img.Bounds()
	tw, th := b.Dx(), b.Dy()
	if tw > size || th > size {
		if tw >= th {
			th = max(1, th*size/tw)
			tw = size
		} else {
			tw = max(1, tw*size/th)
			th = size
		}
	}
	dst := image.NewRGBA(image.Rect(0, 0, tw, th))
	draw.ApproxBiLinear.Scale(dst, dst.Bounds(), img, b, draw.Src, nil)
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, dst, &jpeg.Options{Quality: 80}); err != nil {
		writeError(w, http.StatusInternalServerError, "Önizleme yapılamadı")
		return
	}
	_ = os.MkdirAll(cacheDir, 0o755)
	_ = os.WriteFile(cachePath, buf.Bytes(), 0o644)
	writeThumb(w, etag, buf.Bytes())
}

func writeThumb(w http.ResponseWriter, etag string, data []byte) {
	w.Header().Set("Content-Type", "image/jpeg")
	w.Header().Set("ETag", etag)
	w.Header().Set("Cache-Control", "private, max-age=86400")
	_, _ = w.Write(data)
}

var hashSem = make(chan struct{}, 2)

// handleHash returns the SHA-256 of a file (to verify a transfer).
func (s *Service) handleHash(w http.ResponseWriter, r *http.Request) {
	p, ok := s.pathParam(w, r)
	if !ok {
		return
	}
	select {
	case hashSem <- struct{}{}:
		defer func() { <-hashSem }()
	case <-r.Context().Done():
		return
	}
	f, err := os.Open(p)
	if err != nil {
		fsError(w, err, "Doğrulama")
		return
	}
	defer f.Close()
	h := sha256.New()
	n, err := io.Copy(h, &ctxReader{r.Context(), f})
	if err != nil {
		if r.Context().Err() == nil {
			fsError(w, err, "Doğrulama")
		}
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"sha256": hex.EncodeToString(h.Sum(nil)), "size": n})
}

type ctxReader struct {
	ctx context.Context
	r   io.Reader
}

func (c *ctxReader) Read(b []byte) (int, error) {
	if err := c.ctx.Err(); err != nil {
		return 0, err
	}
	return c.r.Read(b)
}
