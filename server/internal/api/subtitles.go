package api

import (
	"bytes"
	"io"
	"net/http"
	"os"
	"strings"
	"unicode/utf8"

	"golang.org/x/text/encoding/charmap"
	"golang.org/x/text/encoding/unicode"
	"golang.org/x/text/transform"
)

// toUTF8 converts subtitle text to UTF-8 without BOM. Text that is not valid
// UTF-8 is assumed to be Windows-1254 (Turkish), a superset-compatible
// choice for Latin-1 files as well.
func toUTF8(data []byte) []byte {
	switch {
	case bytes.HasPrefix(data, []byte{0xEF, 0xBB, 0xBF}):
		return data[3:]
	case bytes.HasPrefix(data, []byte{0xFF, 0xFE}):
		if out, _, err := transform.Bytes(unicode.UTF16(unicode.LittleEndian, unicode.ExpectBOM).NewDecoder(), data); err == nil {
			return bytes.TrimPrefix(out, []byte{0xEF, 0xBB, 0xBF})
		}
	case bytes.HasPrefix(data, []byte{0xFE, 0xFF}):
		if out, _, err := transform.Bytes(unicode.UTF16(unicode.BigEndian, unicode.ExpectBOM).NewDecoder(), data); err == nil {
			return bytes.TrimPrefix(out, []byte{0xEF, 0xBB, 0xBF})
		}
	}
	if utf8.Valid(data) {
		return data
	}
	// UTF-16 without BOM: lots of NUL bytes at odd/even positions
	if len(data) > 64 && bytes.Count(data[:64], []byte{0}) > 16 {
		order := unicode.LittleEndian
		if data[0] == 0 {
			order = unicode.BigEndian
		}
		if out, _, err := transform.Bytes(unicode.UTF16(order, unicode.IgnoreBOM).NewDecoder(), data); err == nil && utf8.Valid(out) {
			return out
		}
	}
	out, _, err := transform.Bytes(charmap.Windows1254.NewDecoder(), data)
	if err != nil {
		return bytes.ToValidUTF8(data, []byte("?"))
	}
	return out
}

func isBinary(data []byte) bool {
	n := min(len(data), 4096)
	return bytes.Count(data[:n], []byte{0}) > n/20
}

func (s *Server) handleSubtitle(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if i := strings.IndexByte(id, '.'); i > 0 {
		id = id[:i] // allow /api/subtitles/<id>.srt
	}
	sub := s.Lib.Snap().Subs[id]
	if sub == nil {
		writeError(w, http.StatusNotFound, "Altyazı bulunamadı")
		return
	}
	f, err := os.Open(sub.Path)
	if err != nil {
		writeError(w, http.StatusNotFound, "Altyazı dosyası bulunamadı")
		return
	}
	defer f.Close()
	w.Header().Set("Cache-Control", "no-cache")
	if sub.Format == "sup" {
		st, _ := f.Stat()
		w.Header().Set("Content-Type", "application/octet-stream")
		http.ServeContent(w, r, "", st.ModTime(), f)
		return
	}
	data, err := io.ReadAll(io.LimitReader(f, 64<<20))
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Altyazı okunamadı")
		return
	}
	// binary formats (VobSub .sub, .idx companions with binary data) are served raw
	if isBinary(data) && sub.Format != "srt" && sub.Format != "ass" && sub.Format != "ssa" && sub.Format != "vtt" {
		w.Header().Set("Content-Type", "application/octet-stream")
		_, _ = w.Write(data)
		return
	}
	out := toUTF8(data)
	ct := "text/plain; charset=utf-8"
	switch sub.Format {
	case "vtt":
		ct = "text/vtt; charset=utf-8"
	case "ass", "ssa":
		ct = "text/x-ssa; charset=utf-8"
	}
	w.Header().Set("Content-Type", ct)
	_, _ = w.Write(out)
}
