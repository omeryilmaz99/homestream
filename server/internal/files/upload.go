package files

import (
	"errors"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"homestream/internal/names"
)

var (
	foldName    = names.Fold
	naturalLess = names.NaturalLess
)

// partPath is where an unfinished upload of p is kept: ".name.hspart" next to it.
func partPath(p string) string {
	return filepath.Join(filepath.Dir(p), "."+filepath.Base(p)+partSuffix)
}

// uniqueName returns "name (2).ext", "name (3).ext"… that does not exist yet.
func uniqueName(p string) string {
	if _, err := os.Lstat(p); os.IsNotExist(err) {
		return p
	}
	dir, base := filepath.Dir(p), filepath.Base(p)
	ext := filepath.Ext(base)
	stem := strings.TrimSuffix(base, ext)
	if ext == base { // ".bashrc"
		stem, ext = base, ""
	}
	for i := 2; i < 10000; i++ {
		c := filepath.Join(dir, stem+" ("+strconv.Itoa(i)+")"+ext)
		if _, err := os.Lstat(c); os.IsNotExist(err) {
			if _, err := os.Lstat(partPath(c)); os.IsNotExist(err) {
				return c
			}
		}
	}
	return filepath.Join(dir, stem+" ("+randomHex(3)+")"+ext)
}

func (s *Service) lockPath(p string) bool {
	s.locks.Lock()
	defer s.locks.Unlock()
	if s.pathUse[p] > 0 {
		return false
	}
	s.pathUse[p]++
	return true
}

func (s *Service) unlockPath(p string) {
	s.locks.Lock()
	if s.pathUse[p]--; s.pathUse[p] <= 0 {
		delete(s.pathUse, p)
	}
	s.locks.Unlock()
}

// handleUploadStatus tells the app how much of an upload already arrived, and
// whether the target exists (to ask before overwriting).
func (s *Service) handleUploadStatus(w http.ResponseWriter, r *http.Request) {
	p, ok := s.pathParam(w, r)
	if !ok {
		return
	}
	out := map[string]any{"path": p, "offset": 0, "exists": false}
	if st, err := os.Stat(partPath(p)); err == nil {
		out["offset"] = st.Size()
	}
	if st, err := os.Stat(p); err == nil {
		out["exists"] = true
		out["size"] = st.Size()
		out["mtime"] = st.ModTime().UnixMilli()
		out["dir"] = st.IsDir()
	}
	dir := filepath.Dir(p)
	if _, err := os.Stat(dir); err == nil {
		_, free := diskSpace(dir)
		out["free"] = free
		out["writable"] = writable(dir)
	}
	writeJSON(w, http.StatusOK, out)
}

// handleUpload receives a file (or the rest of it) into the ".hspart" file and
// renames it into place when complete.
//
//	PUT /api/files/upload?path=/x/y.mkv&offset=N&size=TOTAL&mtime=MS&conflict=overwrite|rename|fail
func (s *Service) handleUpload(w http.ResponseWriter, r *http.Request) {
	p, ok := s.pathParam(w, r)
	if !ok {
		return
	}
	q := r.URL.Query()
	offset, err1 := strconv.ParseInt(q.Get("offset"), 10, 64)
	size, err2 := strconv.ParseInt(q.Get("size"), 10, 64)
	if err1 != nil || err2 != nil || offset < 0 || size < 0 || offset > size {
		writeError(w, http.StatusBadRequest, "Geçersiz yükleme bilgisi")
		return
	}
	if !validName(filepath.Base(p)) {
		writeError(w, http.StatusBadRequest, "Geçersiz dosya adı")
		return
	}
	conflict := q.Get("conflict")
	dir := filepath.Dir(p)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		fsError(w, err, "Klasör oluşturulamadı")
		return
	}
	if !s.lockPath(p) {
		writeError(w, http.StatusConflict, "Bu dosya şu an başka bir cihazdan yükleniyor")
		return
	}
	defer s.unlockPath(p)

	if st, err := os.Stat(p); err == nil {
		if st.IsDir() {
			writeError(w, http.StatusConflict, "Aynı adda bir klasör var")
			return
		}
		if conflict != "overwrite" && conflict != "rename" && offset == 0 {
			writeJSON(w, http.StatusConflict, map[string]any{"error": "Bu dosya sunucuda zaten var", "exists": true,
				"size": st.Size(), "mtime": st.ModTime().UnixMilli()})
			return
		}
	}

	part := partPath(p)
	var cur int64
	if st, err := os.Stat(part); err == nil {
		cur = st.Size()
	}
	if offset == 0 && cur > 0 {
		cur = 0 // starting over
	} else if cur != offset {
		writeJSON(w, http.StatusConflict, map[string]any{"error": "Yükleme konumu uyuşmuyor", "offset": cur})
		return
	}
	if remaining := size - offset; remaining > 0 {
		if _, free := diskSpace(dir); free > 0 && uint64(remaining) > free {
			writeJSON(w, http.StatusInsufficientStorage, map[string]any{
				"error": "Sunucuda yeterli yer yok (" + human(uint64(remaining)) + " gerekli, " + human(free) + " boş)", "free": free})
			return
		}
	}
	flag := os.O_WRONLY | os.O_CREATE
	if offset == 0 {
		flag |= os.O_TRUNC
	}
	f, err := os.OpenFile(part, flag, 0o644)
	if err != nil {
		fsError(w, err, "Dosya yazılamadı")
		return
	}
	if _, err := f.Seek(offset, io.SeekStart); err != nil {
		f.Close()
		fsError(w, err, "Dosya yazılamadı")
		return
	}
	rc := http.NewResponseController(w)
	body := &deadlineReader{r: r.Body, rc: rc}
	n, copyErr := io.CopyBuffer(f, io.LimitReader(body, size-offset), make([]byte, 1<<20))
	syncErr := f.Sync()
	closeErr := f.Close()
	written := offset + n
	if copyErr == nil {
		copyErr = syncErr
	}
	if copyErr == nil {
		copyErr = closeErr
	}
	if copyErr != nil {
		var netErr interface{ Timeout() bool }
		if isNoSpace(copyErr) || isReadOnly(copyErr) || os.IsPermission(copyErr) {
			fsError(w, copyErr, "Dosya yazılamadı")
			return
		}
		if errors.As(copyErr, &netErr) || errors.Is(copyErr, io.ErrUnexpectedEOF) || strings.Contains(copyErr.Error(), "connection") {
			// the app comes back and continues from "written"
			writeJSON(w, http.StatusConflict, map[string]any{"error": "Bağlantı koptu", "offset": written})
			return
		}
		writeJSON(w, http.StatusConflict, map[string]any{"error": "Yükleme yarıda kaldı: " + copyErr.Error(), "offset": written})
		return
	}
	if written < size {
		writeJSON(w, http.StatusOK, map[string]any{"offset": written, "done": false})
		return
	}
	final := p
	if conflict == "rename" {
		final = uniqueName(p)
	}
	if err := os.Rename(part, final); err != nil {
		fsError(w, err, "Dosya kaydedilemedi")
		return
	}
	if ms, err := strconv.ParseInt(q.Get("mtime"), 10, 64); err == nil && ms > 0 {
		t := time.UnixMilli(ms)
		_ = os.Chtimes(final, t, t)
	}
	s.changed(dir)
	writeJSON(w, http.StatusOK, map[string]any{"offset": written, "done": true, "path": final})
}

func (s *Service) handleUploadCancel(w http.ResponseWriter, r *http.Request) {
	p, ok := s.pathParam(w, r)
	if !ok {
		return
	}
	if err := os.Remove(partPath(p)); err != nil && !os.IsNotExist(err) {
		fsError(w, err, "Silinemedi")
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

// deadlineReader extends the read deadline while data keeps coming, so a
// client that vanished (Wi-Fi off, laptop closed) frees the upload after 60 s.
type deadlineReader struct {
	r    io.Reader
	rc   *http.ResponseController
	last time.Time
}

func (d *deadlineReader) Read(b []byte) (int, error) {
	if now := time.Now(); now.Sub(d.last) > 5*time.Second {
		d.last = now
		_ = d.rc.SetReadDeadline(now.Add(60 * time.Second))
	}
	return d.r.Read(b)
}

func human(n uint64) string {
	const unit = 1024
	if n < unit {
		return strconv.FormatUint(n, 10) + " B"
	}
	div, exp := uint64(unit), 0
	for m := n / unit; m >= unit; m /= unit {
		div *= unit
		exp++
	}
	v := float64(n) / float64(div)
	return strconv.FormatFloat(v, 'f', 1, 64) + " " + string("KMGTPE"[exp]) + "B"
}
