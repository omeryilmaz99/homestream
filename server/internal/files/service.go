// Package files is the server side of the Home Dosya app: browsing, transfers
// (resumable in both directions), file operations, a trash, disks and system
// status, all behind a password login that the app can remember.
package files

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"io"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

// Config holds what the service needs from the rest of the server.
type Config struct {
	DB            *sql.DB
	DataDir       string
	Home          string // the service user's home folder
	Library       string // default HomeStream folder
	DrivesDir     string // auto-mounted disks (/media/homestream)
	Version       string
	ServerID      string
	ServerName    func() string
	CheckPassword func(string) bool
	// LibraryDirs lists the media library folders (video + music), used for
	// shortcuts and to rescan after uploads into them.
	LibraryDirs func() []Place
	// OnChange is called (debounced) with a folder that changed through the app.
	OnChange func(dir string)
	// EjectCmd runs the disk helper ("eject <dir>" / "mount <dev>"); empty = sudo helper.
	EjectCmd []string
}

// Service implements the /api/files endpoints.
type Service struct {
	cfg  Config
	ctx  context.Context
	hub  *hub
	jobs *jobs

	mu       sync.Mutex
	sessions map[string]*session // by token hash
	fails    map[string]*failInfo

	locks   sync.Mutex
	pathUse map[string]int // uploads in progress (path → count)

	changeMu  sync.Mutex
	changeDue map[string]time.Time

	sys sysSampler
}

type session struct {
	ID       string `json:"id"`
	Device   string `json:"device"`
	Platform string `json:"platform"`
	Created  int64  `json:"created"`
	LastSeen int64  `json:"lastSeen"`
	LastIP   string `json:"lastIp"`
	hash     string
	saved    int64 // last_seen written to the database
}

type failInfo struct {
	n     int
	until time.Time
}

// New opens the session table and starts the background jobs.
func New(ctx context.Context, cfg Config) (*Service, error) {
	if cfg.ServerName == nil {
		cfg.ServerName = func() string { return "Home Stream" }
	}
	if cfg.Home == "" {
		cfg.Home, _ = os.UserHomeDir()
	}
	s := &Service{cfg: cfg, ctx: ctx, sessions: map[string]*session{}, fails: map[string]*failInfo{},
		pathUse: map[string]int{}, changeDue: map[string]time.Time{}}
	s.hub = newHub(s)
	s.jobs = newJobs(s)
	if _, err := cfg.DB.Exec(`CREATE TABLE IF NOT EXISTS file_sessions (
		token_hash TEXT PRIMARY KEY, id TEXT NOT NULL, device TEXT NOT NULL, platform TEXT NOT NULL,
		created INTEGER NOT NULL, last_seen INTEGER NOT NULL, last_ip TEXT NOT NULL)`); err != nil {
		return nil, err
	}
	rows, err := cfg.DB.Query(`SELECT token_hash, id, device, platform, created, last_seen, last_ip FROM file_sessions`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		ss := &session{}
		if err := rows.Scan(&ss.hash, &ss.ID, &ss.Device, &ss.Platform, &ss.Created, &ss.LastSeen, &ss.LastIP); err == nil {
			ss.saved = ss.LastSeen
			s.sessions[ss.hash] = ss
		}
	}
	go s.hub.run(ctx)
	go s.changeLoop(ctx)
	go s.watchDisks(ctx)
	return s, rows.Err()
}

// Register adds the routes to mux.
func (s *Service) Register(mux *http.ServeMux) {
	mux.HandleFunc("POST /api/files/login", s.handleLogin)
	a := func(pattern string, h http.HandlerFunc) { mux.HandleFunc(pattern, s.auth(h)) }
	a("POST /api/files/logout", s.handleLogout)
	a("GET /api/files/session", s.handleSession)
	a("GET /api/files/roots", s.handleRoots)
	a("GET /api/files/list", s.handleList)
	a("GET /api/files/stat", s.handleStat)
	a("GET /api/files/tree", s.handleTree)
	a("GET /api/files/search", s.handleSearch)
	a("GET /api/files/download", s.handleDownload)
	a("HEAD /api/files/download", s.handleDownload)
	a("GET /api/files/thumb", s.handleThumb)
	a("GET /api/files/hash", s.handleHash)
	a("GET /api/files/upload", s.handleUploadStatus)
	a("PUT /api/files/upload", s.handleUpload)
	a("DELETE /api/files/upload", s.handleUploadCancel)
	a("POST /api/files/mkdir", s.handleMkdir)
	a("POST /api/files/rename", s.handleRename)
	a("POST /api/files/delete", s.handleDelete)
	a("POST /api/files/copy", s.handleCopy)
	a("GET /api/files/jobs", s.handleJobs)
	a("DELETE /api/files/jobs/{id}", s.handleCancelJob)
	a("GET /api/files/trash", s.handleTrash)
	a("POST /api/files/trash/restore", s.handleTrashRestore)
	a("POST /api/files/trash/delete", s.handleTrashDelete)
	a("GET /api/files/system", s.handleSystem)
	a("GET /api/files/devices", s.handleDevices)
	a("POST /api/files/devices/eject", s.handleEject)
	a("POST /api/files/devices/mount", s.handleMount)
	a("DELETE /api/files/sessions/{id}", s.handleRevoke)
	a("GET /api/files/events", s.handleEvents)
	a("PUT /api/files/events/{id}/watch", s.handleWatch)
}

// ---------- helpers ----------

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
	body, err := io.ReadAll(io.LimitReader(r.Body, 4<<20))
	if err != nil {
		return err
	}
	if strings.TrimSpace(string(body)) == "" {
		return nil
	}
	return json.Unmarshal(body, v)
}

func randomHex(n int) string {
	b := make([]byte, n)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

func hashToken(t string) string {
	sum := sha256.Sum256([]byte(t))
	return hex.EncodeToString(sum[:])
}

func clientIP(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

// cleanPath validates an absolute path from a request.
func cleanPath(p string) (string, bool) {
	p = strings.TrimSpace(p)
	if p == "" || !filepath.IsAbs(p) || strings.ContainsRune(p, 0) {
		return "", false
	}
	return filepath.Clean(p), true
}

// validName rejects names that cannot be a single path element.
func validName(n string) bool {
	return n != "" && n != "." && n != ".." && !strings.ContainsAny(n, "/\x00") && len(n) <= 255
}

func (s *Service) pathParam(w http.ResponseWriter, r *http.Request) (string, bool) {
	p, ok := cleanPath(r.URL.Query().Get("path"))
	if !ok {
		writeError(w, http.StatusBadRequest, "Geçersiz yol")
	}
	return p, ok
}

// fsError turns an os error into a Turkish message and a status code.
func fsError(w http.ResponseWriter, err error, what string) {
	switch {
	case os.IsNotExist(err):
		writeError(w, http.StatusNotFound, what+": bulunamadı (silinmiş ya da taşınmış olabilir)")
	case os.IsPermission(err):
		writeError(w, http.StatusForbidden, what+": izin yok")
	case isNoSpace(err):
		writeError(w, http.StatusInsufficientStorage, what+": sunucuda yer kalmadı")
	case isReadOnly(err):
		writeError(w, http.StatusForbidden, what+": disk salt okunur")
	case os.IsExist(err):
		writeError(w, http.StatusConflict, what+": aynı adda bir öğe zaten var")
	default:
		writeError(w, http.StatusInternalServerError, what+": "+err.Error())
	}
}

// changed tells watchers that dir changed now, and schedules the library hook.
func (s *Service) changed(dirs ...string) {
	s.hub.notifyChange(dirs...)
	if s.cfg.OnChange == nil {
		return
	}
	s.changeMu.Lock()
	for _, d := range dirs {
		s.changeDue[d] = time.Now().Add(20 * time.Second)
	}
	s.changeMu.Unlock()
}

// changeLoop calls OnChange once a folder has been quiet for a while, so a
// large copy into the library triggers one rescan at the end.
func (s *Service) changeLoop(ctx context.Context) {
	t := time.NewTicker(5 * time.Second)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
		}
		var due []string
		s.changeMu.Lock()
		s.locks.Lock()
		busy := len(s.pathUse) > 0
		s.locks.Unlock()
		for d, at := range s.changeDue {
			if time.Now().After(at) && !busy && !s.jobs.busy() {
				due = append(due, d)
				delete(s.changeDue, d)
			}
		}
		s.changeMu.Unlock()
		if len(due) > 0 {
			for _, d := range due {
				s.cfg.OnChange(d)
			}
		}
	}
}
