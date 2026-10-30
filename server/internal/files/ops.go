package files

import (
	"encoding/json"
	"errors"
	"io"
	"io/fs"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"syscall"
	"time"
)

// protected paths can never be renamed, moved or deleted from the app.
func (s *Service) protected(p string) bool {
	if p == "/" || filepath.Dir(p) == "/" { // /home, /etc, /media …
		return true
	}
	for _, q := range []string{s.cfg.Home, s.cfg.Library, s.cfg.DataDir, s.cfg.DrivesDir, filepath.Dir(s.cfg.Home)} {
		if q != "" && p == filepath.Clean(q) {
			return true
		}
	}
	if s.cfg.DrivesDir != "" && filepath.Dir(p) == filepath.Clean(s.cfg.DrivesDir) {
		return true // a disk's mount point
	}
	return false
}

func (s *Service) handleMkdir(w http.ResponseWriter, r *http.Request) {
	var b struct {
		Path string `json:"path"`
	}
	if err := readJSON(r, &b); err != nil {
		writeError(w, http.StatusBadRequest, "Geçersiz istek")
		return
	}
	p, ok := cleanPath(b.Path)
	if !ok || !validName(filepath.Base(p)) {
		writeError(w, http.StatusBadRequest, "Geçersiz klasör adı")
		return
	}
	if err := os.Mkdir(p, 0o755); err != nil {
		fsError(w, err, "Klasör oluşturulamadı")
		return
	}
	s.changed(filepath.Dir(p))
	writeJSON(w, http.StatusCreated, map[string]any{"path": p})
}

func (s *Service) handleRename(w http.ResponseWriter, r *http.Request) {
	var b struct {
		Path string `json:"path"`
		Name string `json:"name"`
	}
	if err := readJSON(r, &b); err != nil {
		writeError(w, http.StatusBadRequest, "Geçersiz istek")
		return
	}
	p, ok := cleanPath(b.Path)
	name := strings.TrimSpace(b.Name)
	if !ok || !validName(name) {
		writeError(w, http.StatusBadRequest, "Geçersiz ad")
		return
	}
	if s.protected(p) {
		writeError(w, http.StatusForbidden, "Bu klasörün adı değiştirilemez")
		return
	}
	dst := filepath.Join(filepath.Dir(p), name)
	if dst == p {
		writeJSON(w, http.StatusOK, map[string]any{"path": p})
		return
	}
	// "a.txt" → "A.txt" on a case-insensitive disk is the same file
	if _, err := os.Lstat(dst); err == nil && !strings.EqualFold(dst, p) {
		writeError(w, http.StatusConflict, "Aynı adda bir öğe zaten var")
		return
	}
	if err := os.Rename(p, dst); err != nil {
		fsError(w, err, "Ad değiştirilemedi")
		return
	}
	s.changed(filepath.Dir(p))
	writeJSON(w, http.StatusOK, map[string]any{"path": dst})
}

// ---------- delete / trash ----------

const trashDirName = ".homestream-trash"

type trashMeta struct {
	ID      string `json:"id"`
	Name    string `json:"name"`
	Orig    string `json:"orig"`
	Deleted int64  `json:"deleted"`
	Dir     bool   `json:"dir"`
	Size    int64  `json:"size"`
	Trash   string `json:"-"`
}

// trashFor picks a trash folder on the same disk as p (so deleting is a
// quick rename), or "" when there is none.
func (s *Service) trashFor(p string) string {
	dev, ok := deviceOf(p)
	if !ok {
		return ""
	}
	cands := []string{filepath.Join(s.cfg.Home, ".local", "share", "homestream", "trash")}
	if root := mountRoot(p); root != "" && root != "/" {
		cands = append([]string{filepath.Join(root, trashDirName)}, cands...)
	}
	for _, c := range cands {
		base := c
		for { // the trash itself may not exist yet: check its closest parent
			if d, ok := deviceOf(base); ok {
				if d == dev && writable(base) {
					if err := os.MkdirAll(c, 0o755); err == nil {
						return c
					}
				}
				break
			}
			if base == "/" {
				break
			}
			base = filepath.Dir(base)
		}
	}
	return ""
}

func (s *Service) trashDirs() []string {
	out := []string{filepath.Join(s.cfg.Home, ".local", "share", "homestream", "trash")}
	for _, m := range mounts() {
		if m.Dir != "/" {
			t := filepath.Join(m.Dir, trashDirName)
			if st, err := os.Stat(t); err == nil && st.IsDir() {
				out = append(out, t)
			}
		}
	}
	return out
}

func treeSize(p string) int64 {
	var n int64
	_ = filepath.WalkDir(p, func(_ string, d fs.DirEntry, err error) error {
		if err == nil && !d.IsDir() {
			if i, err := d.Info(); err == nil {
				n += i.Size()
			}
		}
		return nil
	})
	return n
}

func (s *Service) handleDelete(w http.ResponseWriter, r *http.Request) {
	var b struct {
		Paths     []string `json:"paths"`
		Permanent bool     `json:"permanent"`
	}
	if err := readJSON(r, &b); err != nil || len(b.Paths) == 0 {
		writeError(w, http.StatusBadRequest, "Geçersiz istek")
		return
	}
	type result struct {
		Path  string `json:"path"`
		Error string `json:"error,omitempty"`
		Trash bool   `json:"trash"`
	}
	var results []result
	noTrash := []string{}
	dirs := map[string]bool{}
	for _, raw := range b.Paths {
		p, ok := cleanPath(raw)
		if !ok {
			results = append(results, result{Path: raw, Error: "Geçersiz yol"})
			continue
		}
		if s.protected(p) {
			results = append(results, result{Path: p, Error: "Bu klasör silinemez"})
			continue
		}
		st, err := os.Lstat(p)
		if err != nil {
			results = append(results, result{Path: p, Error: "Bulunamadı"})
			continue
		}
		if b.Permanent {
			if err := os.RemoveAll(p); err != nil {
				results = append(results, result{Path: p, Error: errText(err)})
				continue
			}
			dirs[filepath.Dir(p)] = true
			results = append(results, result{Path: p})
			continue
		}
		t := s.trashFor(p)
		if t == "" {
			noTrash = append(noTrash, p)
			continue
		}
		meta := trashMeta{ID: time.Now().Format("20060102-150405") + "-" + randomHex(3), Name: filepath.Base(p), Orig: p,
			Deleted: time.Now().UnixMilli(), Dir: st.IsDir()}
		if st.IsDir() {
			meta.Size = treeSize(p)
		} else {
			meta.Size = st.Size()
		}
		holder := filepath.Join(t, meta.ID)
		if err := os.MkdirAll(holder, 0o755); err != nil {
			results = append(results, result{Path: p, Error: errText(err)})
			continue
		}
		if err := os.Rename(p, filepath.Join(holder, meta.Name)); err != nil {
			_ = os.Remove(holder)
			if errors.Is(err, syscall.EXDEV) {
				noTrash = append(noTrash, p)
				continue
			}
			results = append(results, result{Path: p, Error: errText(err)})
			continue
		}
		mj, _ := json.Marshal(meta)
		_ = os.WriteFile(filepath.Join(holder, ".meta.json"), mj, 0o644)
		dirs[filepath.Dir(p)] = true
		results = append(results, result{Path: p, Trash: true})
	}
	for d := range dirs {
		s.changed(d)
	}
	writeJSON(w, http.StatusOK, map[string]any{"results": results, "noTrash": noTrash})
}

func errText(err error) string {
	switch {
	case os.IsPermission(err):
		return "İzin yok"
	case isReadOnly(err):
		return "Disk salt okunur"
	case os.IsNotExist(err):
		return "Bulunamadı"
	case isNoSpace(err):
		return "Yer kalmadı"
	}
	var pe *fs.PathError
	if errors.As(err, &pe) {
		return pe.Err.Error()
	}
	return err.Error()
}

func (s *Service) trashItems() []trashMeta {
	var out []trashMeta
	for _, t := range s.trashDirs() {
		des, _ := os.ReadDir(t)
		for _, de := range des {
			data, err := os.ReadFile(filepath.Join(t, de.Name(), ".meta.json"))
			if err != nil {
				continue
			}
			var m trashMeta
			if json.Unmarshal(data, &m) == nil && m.ID == de.Name() {
				m.Trash = t
				out = append(out, m)
			}
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Deleted > out[j].Deleted })
	return out
}

func (s *Service) handleTrash(w http.ResponseWriter, r *http.Request) {
	items := s.trashItems()
	var total int64
	for _, m := range items {
		total += m.Size
	}
	if items == nil {
		items = []trashMeta{}
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": items, "size": total})
}

func (s *Service) handleTrashRestore(w http.ResponseWriter, r *http.Request) {
	var b struct {
		IDs []string `json:"ids"`
	}
	if err := readJSON(r, &b); err != nil {
		writeError(w, http.StatusBadRequest, "Geçersiz istek")
		return
	}
	want := map[string]bool{}
	for _, id := range b.IDs {
		want[id] = true
	}
	restored, failed := []string{}, []map[string]string{}
	for _, m := range s.trashItems() {
		if !want[m.ID] {
			continue
		}
		dst := m.Orig
		_ = os.MkdirAll(filepath.Dir(dst), 0o755)
		if _, err := os.Lstat(dst); err == nil {
			dst = uniqueName(dst)
		}
		if err := os.Rename(filepath.Join(m.Trash, m.ID, m.Name), dst); err != nil {
			failed = append(failed, map[string]string{"id": m.ID, "error": errText(err)})
			continue
		}
		_ = os.RemoveAll(filepath.Join(m.Trash, m.ID))
		restored = append(restored, dst)
		s.changed(filepath.Dir(dst))
	}
	writeJSON(w, http.StatusOK, map[string]any{"restored": restored, "failed": failed})
}

// handleTrashDelete deletes the given trash items for good (all when ids is empty and all=true).
func (s *Service) handleTrashDelete(w http.ResponseWriter, r *http.Request) {
	var b struct {
		IDs []string `json:"ids"`
		All bool     `json:"all"`
	}
	if err := readJSON(r, &b); err != nil {
		writeError(w, http.StatusBadRequest, "Geçersiz istek")
		return
	}
	want := map[string]bool{}
	for _, id := range b.IDs {
		want[id] = true
	}
	n := 0
	for _, m := range s.trashItems() {
		if b.All || want[m.ID] {
			if os.RemoveAll(filepath.Join(m.Trash, m.ID)) == nil {
				n++
			}
		}
	}
	writeJSON(w, http.StatusOK, map[string]any{"deleted": n})
}

// ---------- copy / move on the server (background jobs) ----------

type job struct {
	ID        string   `json:"id"`
	Kind      string   `json:"kind"` // copy | move
	Dest      string   `json:"dest"`
	Names     []string `json:"names"`
	Total     int64    `json:"total"`
	Done      int64    `json:"done"`
	Files     int      `json:"files"`
	FilesDone int      `json:"filesDone"`
	Current   string   `json:"current"`
	State     string   `json:"state"` // running | done | failed | canceled
	Error     string   `json:"error,omitempty"`
	Started   int64    `json:"started"`
	Finished  int64    `json:"finished,omitempty"`
	Skipped   int      `json:"skipped"`
	cancel    chan struct{}
}

type jobs struct {
	s    *Service
	mu   sync.Mutex
	list []*job
}

func newJobs(s *Service) *jobs { return &jobs{s: s} }

func (j *jobs) busy() bool {
	j.mu.Lock()
	defer j.mu.Unlock()
	for _, jb := range j.list {
		if jb.State == "running" {
			return true
		}
	}
	return false
}

func (j *jobs) snapshot() []job {
	j.mu.Lock()
	defer j.mu.Unlock()
	out := make([]job, 0, len(j.list))
	for _, jb := range j.list {
		out = append(out, *jb)
	}
	return out
}

func (j *jobs) update(jb *job, f func()) {
	j.mu.Lock()
	f()
	cp := *jb
	j.mu.Unlock()
	j.s.hub.broadcast("job", cp)
}

var errCanceled = errors.New("canceled")

func (s *Service) handleCopy(w http.ResponseWriter, r *http.Request) {
	var b struct {
		Paths    []string `json:"paths"`
		Dest     string   `json:"dest"`
		Move     bool     `json:"move"`
		Conflict string   `json:"conflict"` // rename (default) | overwrite | skip
	}
	if err := readJSON(r, &b); err != nil || len(b.Paths) == 0 {
		writeError(w, http.StatusBadRequest, "Geçersiz istek")
		return
	}
	dest, ok := cleanPath(b.Dest)
	if !ok {
		writeError(w, http.StatusBadRequest, "Geçersiz hedef")
		return
	}
	if st, err := os.Stat(dest); err != nil || !st.IsDir() {
		writeError(w, http.StatusBadRequest, "Hedef klasör bulunamadı")
		return
	}
	var srcs []string
	for _, raw := range b.Paths {
		p, ok := cleanPath(raw)
		if !ok {
			continue
		}
		if b.Move && s.protected(p) {
			writeError(w, http.StatusForbidden, filepath.Base(p)+" taşınamaz")
			return
		}
		if dest == p || strings.HasPrefix(dest+"/", p+"/") {
			writeError(w, http.StatusBadRequest, "Bir klasör kendi içine kopyalanamaz")
			return
		}
		srcs = append(srcs, p)
	}
	if len(srcs) == 0 {
		writeError(w, http.StatusBadRequest, "Geçersiz istek")
		return
	}
	jb := &job{ID: randomHex(5), Kind: "copy", Dest: dest, State: "running", Started: time.Now().UnixMilli(), cancel: make(chan struct{})}
	if b.Move {
		jb.Kind = "move"
	}
	for _, p := range srcs {
		jb.Names = append(jb.Names, filepath.Base(p))
	}
	s.jobs.mu.Lock()
	// keep the last 30 jobs
	if len(s.jobs.list) > 30 {
		s.jobs.list = s.jobs.list[len(s.jobs.list)-30:]
	}
	s.jobs.list = append(s.jobs.list, jb)
	s.jobs.mu.Unlock()
	go s.runCopy(jb, srcs, dest, b.Move, b.Conflict)
	writeJSON(w, http.StatusAccepted, *jb)
}

func (s *Service) runCopy(jb *job, srcs []string, dest string, move bool, conflict string) {
	if conflict == "" {
		conflict = "rename"
	}
	// size first, for the progress bar (moves on the same disk are instant)
	var total int64
	files := 0
	for _, p := range srcs {
		_ = filepath.WalkDir(p, func(_ string, d fs.DirEntry, err error) error {
			if err == nil && !d.IsDir() {
				if i, err := d.Info(); err == nil {
					total += i.Size()
					files++
				}
			}
			return nil
		})
	}
	s.jobs.update(jb, func() { jb.Total = total; jb.Files = files })
	changed := map[string]bool{dest: true}
	var err error
	for _, src := range srcs {
		target := filepath.Join(dest, filepath.Base(src))
		if _, e := os.Lstat(target); e == nil {
			switch conflict {
			case "skip":
				s.jobs.update(jb, func() { jb.Skipped++ })
				continue
			case "overwrite":
				if move && sameFile(src, target) {
					continue
				}
				if e := os.RemoveAll(target); e != nil {
					err = e
				}
			default:
				target = uniqueName(target)
			}
		}
		if err != nil {
			break
		}
		if move {
			if e := os.Rename(src, target); e == nil {
				changed[filepath.Dir(src)] = true
				sz := treeSize(target)
				s.jobs.update(jb, func() { jb.Done += sz; jb.FilesDone++ })
				continue
			} else if !errors.Is(e, syscall.EXDEV) {
				err = e
				break
			}
		}
		if e := s.copyTree(jb, src, target); e != nil {
			err = e
			_ = os.RemoveAll(target) // no half copies left behind
			break
		}
		if move {
			if e := os.RemoveAll(src); e != nil {
				err = e
				break
			}
			changed[filepath.Dir(src)] = true
		}
	}
	for d := range changed {
		s.changed(d)
	}
	s.jobs.update(jb, func() {
		jb.Finished = time.Now().UnixMilli()
		jb.Current = ""
		switch {
		case errors.Is(err, errCanceled):
			jb.State = "canceled"
		case err != nil:
			jb.State = "failed"
			jb.Error = errText(err)
		default:
			jb.State = "done"
		}
	})
}

func sameFile(a, b string) bool {
	sa, e1 := os.Stat(a)
	sb, e2 := os.Stat(b)
	return e1 == nil && e2 == nil && os.SameFile(sa, sb)
}

func (s *Service) copyTree(jb *job, src, dst string) error {
	return filepath.WalkDir(src, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		select {
		case <-jb.cancel:
			return errCanceled
		default:
		}
		rel, _ := filepath.Rel(src, path)
		target := filepath.Join(dst, rel)
		info, err := d.Info()
		if err != nil {
			return err
		}
		switch {
		case d.IsDir():
			return os.MkdirAll(target, info.Mode().Perm()|0o700)
		case info.Mode()&os.ModeSymlink != 0:
			l, err := os.Readlink(path)
			if err != nil {
				return err
			}
			return os.Symlink(l, target)
		case !info.Mode().IsRegular():
			return nil // devices, sockets
		}
		s.jobs.update(jb, func() { jb.Current = rel })
		if err := s.copyFile(jb, path, target, info); err != nil {
			return err
		}
		s.jobs.update(jb, func() { jb.FilesDone++ })
		return nil
	})
}

func (s *Service) copyFile(jb *job, src, dst string, info fs.FileInfo) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.OpenFile(dst, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, info.Mode().Perm())
	if err != nil {
		return err
	}
	buf := make([]byte, 1<<20)
	last := time.Now()
	var pending int64
	for {
		select {
		case <-jb.cancel:
			out.Close()
			return errCanceled
		default:
		}
		n, rerr := in.Read(buf)
		if n > 0 {
			if _, werr := out.Write(buf[:n]); werr != nil {
				out.Close()
				return werr
			}
			pending += int64(n)
			if time.Since(last) > 300*time.Millisecond {
				p := pending
				pending = 0
				last = time.Now()
				s.jobs.update(jb, func() { jb.Done += p })
			}
		}
		if rerr == io.EOF {
			break
		}
		if rerr != nil {
			out.Close()
			return rerr
		}
	}
	p := pending
	s.jobs.update(jb, func() { jb.Done += p })
	if err := out.Close(); err != nil {
		return err
	}
	_ = os.Chtimes(dst, info.ModTime(), info.ModTime())
	return nil
}

func (s *Service) handleJobs(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, s.jobs.snapshot())
}

func (s *Service) handleCancelJob(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	s.jobs.mu.Lock()
	defer s.jobs.mu.Unlock()
	for _, jb := range s.jobs.list {
		if jb.ID == id {
			if jb.State == "running" {
				select {
				case <-jb.cancel:
				default:
					close(jb.cancel)
				}
			}
			writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
			return
		}
	}
	writeError(w, http.StatusNotFound, "İş bulunamadı")
}
