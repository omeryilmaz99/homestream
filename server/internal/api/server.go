// Package api implements the Home Stream HTTP API.
package api

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log"
	"net/http"
	"runtime/debug"
	"strings"
	"time"

	"homestream/internal/library"
	"homestream/internal/music"
	"homestream/internal/store"
)

// Server holds API dependencies.
type Server struct {
	Lib         *library.Library
	St          *store.Store
	Version     string
	DefaultName string
	Port        int
	ServerID    string
	Music       *music.Library
	Ctx         context.Context // lives as long as the server (background jobs)
}

func (s *Server) ctx() context.Context {
	if s.Ctx != nil {
		return s.Ctx
	}
	return context.Background()
}

// ServerName returns the configured server name.
func (s *Server) ServerName() string {
	if v := s.St.GetSetting("serverName"); v != "" {
		return v
	}
	return s.DefaultName
}

// Handler returns the root HTTP handler.
func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/info", s.handleInfo)
	mux.HandleFunc("GET /api/profiles", s.handleProfiles)
	mux.HandleFunc("POST /api/profiles", s.handleCreateProfile)
	mux.HandleFunc("PUT /api/profiles/{id}", s.handleUpdateProfile)
	mux.HandleFunc("DELETE /api/profiles/{id}", s.handleDeleteProfile)
	mux.HandleFunc("GET /api/home", s.handleHome)
	mux.HandleFunc("GET /api/movies", s.handleList("movie"))
	mux.HandleFunc("GET /api/series", s.handleList("series"))
	mux.HandleFunc("GET /api/genres", s.handleGenres)
	mux.HandleFunc("GET /api/items/{id}", s.handleItem)
	mux.HandleFunc("GET /api/items/{id}/related", s.handleRelated)
	mux.HandleFunc("POST /api/items/{id}/progress", s.handleProgress)
	mux.HandleFunc("DELETE /api/items/{id}/progress", s.handleClearProgress)
	mux.HandleFunc("POST /api/items/{id}/played", s.handlePlayed)
	mux.HandleFunc("POST /api/items/{id}/like", s.handleLike)
	mux.HandleFunc("GET /api/search", s.handleSearch)
	mux.HandleFunc("GET /api/browse", s.handleBrowse)
	mux.HandleFunc("GET /api/stream/{id}", s.handleStream)
	mux.HandleFunc("GET /api/subtitles/{id}", s.handleSubtitle)
	mux.HandleFunc("GET /api/images/{id}/{kind}", s.handleImage)
	mux.HandleFunc("GET /api/settings", s.handleGetSettings)
	mux.HandleFunc("PUT /api/settings", s.handlePutSettings)
	mux.HandleFunc("POST /api/folders", s.handleAddFolder)
	mux.HandleFunc("DELETE /api/folders/{id}", s.handleDeleteFolder)
	mux.HandleFunc("PATCH /api/folders/{id}", s.handleUpdateFolder)
	mux.HandleFunc("GET /api/fs", s.handleFS)
	mux.HandleFunc("POST /api/scan", s.handleScan)
	mux.HandleFunc("GET /api/scan/status", s.handleScanStatus)
	if s.Music != nil {
		s.musicRoutes(mux)
	}
	mux.HandleFunc("/api/", func(w http.ResponseWriter, r *http.Request) {
		writeError(w, http.StatusNotFound, "Bulunamadı")
	})
	mux.HandleFunc("GET /{$}", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		_, _ = io.WriteString(w, "Home Stream sunucusu çalışıyor. Uygulamadan bu adrese bağlanın.\n")
	})
	return s.middleware(mux)
}

type statusWriter struct {
	http.ResponseWriter
	status int
	n      int64
}

func (w *statusWriter) WriteHeader(code int) {
	if w.status == 0 {
		w.status = code
	}
	w.ResponseWriter.WriteHeader(code)
}

func (w *statusWriter) Write(b []byte) (int, error) {
	if w.status == 0 {
		w.status = http.StatusOK
	}
	n, err := w.ResponseWriter.Write(b)
	w.n += int64(n)
	return n, err
}

// ReadFrom keeps sendfile(2) working for streams.
func (w *statusWriter) ReadFrom(r io.Reader) (int64, error) {
	if w.status == 0 {
		w.status = http.StatusOK
	}
	if rf, ok := w.ResponseWriter.(io.ReaderFrom); ok {
		n, err := rf.ReadFrom(r)
		w.n += n
		return n, err
	}
	n, err := io.Copy(w.ResponseWriter, r)
	w.n += n
	return n, err
}

func (w *statusWriter) Unwrap() http.ResponseWriter { return w.ResponseWriter }

func (s *Server) middleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		h := w.Header()
		h.Set("Access-Control-Allow-Origin", "*")
		h.Set("Access-Control-Allow-Headers", "Content-Type, X-Profile, X-Admin-Password, Range, If-None-Match, If-Range")
		h.Set("Access-Control-Allow-Methods", "GET, HEAD, POST, PUT, DELETE, OPTIONS")
		h.Set("Access-Control-Expose-Headers", "Content-Range, Content-Length, Accept-Ranges, ETag")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		sw := &statusWriter{ResponseWriter: w}
		defer func() {
			if rec := recover(); rec != nil {
				if rec == http.ErrAbortHandler {
					panic(rec)
				}
				log.Printf("panic: %s %s: %v\n%s", r.Method, r.URL.Path, rec, debug.Stack())
				if sw.status == 0 {
					writeError(sw, http.StatusInternalServerError, "Sunucu hatası")
				}
			}
			p := r.URL.Path
			quiet := strings.HasPrefix(p, "/api/images/") || strings.HasPrefix(p, "/api/stream/") ||
				strings.HasPrefix(p, "/api/music/covers/") || strings.HasPrefix(p, "/api/music/stream/") ||
				p == "/api/music/scan/status" || strings.HasSuffix(p, "/played") ||
				p == "/api/scan/status" || strings.HasSuffix(p, "/progress") || r.Method == http.MethodHead
			if !quiet || sw.status >= 500 {
				log.Printf("%s %s %d %s", r.Method, r.URL.RequestURI(), sw.status, time.Since(start).Round(time.Millisecond))
			}
		}()
		next.ServeHTTP(sw, r)
	})
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	enc := json.NewEncoder(w)
	enc.SetEscapeHTML(false)
	_ = enc.Encode(v)
}

func writeError(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]string{"error": msg})
}

func readJSON(r *http.Request, v any) error {
	body, err := io.ReadAll(io.LimitReader(r.Body, 1<<20))
	if err != nil {
		return err
	}
	if len(strings.TrimSpace(string(body))) == 0 {
		return nil
	}
	return json.Unmarshal(body, v)
}

var errNoProfile = errors.New("no profile")

// profileID returns the request's profile id ("" when absent or unknown).
func (s *Server) profileID(r *http.Request) string {
	id := strings.TrimSpace(r.Header.Get("X-Profile"))
	if id == "" {
		id = strings.TrimSpace(r.URL.Query().Get("profile"))
	}
	if id == "" {
		return ""
	}
	if _, ok := s.St.Profile(id); !ok {
		return ""
	}
	return id
}

// requireProfile writes a 400 and returns "" when no valid profile is given.
func (s *Server) requireProfile(w http.ResponseWriter, r *http.Request) string {
	id := s.profileID(r)
	if id == "" {
		writeError(w, http.StatusBadRequest, "Profil seçilmedi")
	}
	return id
}
