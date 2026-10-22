// Package music is the music library: it scans the music folders, reads
// tags, finds covers (embedded, folder image, video frame, internet or a
// generated one) and keeps an in-memory snapshot for the API.
package music

import (
	"context"
	"database/sql"
	"errors"
	"io"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"sync"
	"sync/atomic"
	"time"
)

// Config holds runtime configuration.
type Config struct {
	DataDir       string
	DefaultFolder string // e.g. ~/HomeStream/Müzik
	FFprobe       string
	FFmpeg        string
	Nice          string
	ProbeWorkers  int
	// Online cover lookups (tests point these at a fake server).
	ITunesURL string
	DeezerURL string
	// GetSetting reads a server setting (scan interval, online covers).
	GetSetting func(string) string
}

// Status is reported by GET /api/music/scan/status.
type Status struct {
	Running    bool   `json:"running"`
	Phase      string `json:"phase"`
	Done       int    `json:"done"`
	Total      int    `json:"total"`
	LastScanAt int64  `json:"lastScanAt"`
	LastError  string `json:"lastError"`
	Queued     bool   `json:"queued"`
	CoverTask  string `json:"coverTask"`
	CoverDone  int    `json:"coverDone"`
	CoverTotal int    `json:"coverTotal"`
}

// Library is the music library service.
type Library struct {
	cfg    Config
	db     *sql.DB
	Covers *Covers

	snap atomic.Pointer[Snapshot]

	mu       sync.Mutex
	status   Status
	pending  bool
	wake     chan struct{}
	rescanAt time.Time

	reloadMu   sync.Mutex
	lastReload time.Time

	bgMu     sync.Mutex
	bgCancel context.CancelFunc
}

// New opens the music library (creating its tables and default folder).
func New(cfg Config, db *sql.DB) (*Library, error) {
	if cfg.ProbeWorkers <= 0 {
		cfg.ProbeWorkers = 3
	}
	if cfg.GetSetting == nil {
		cfg.GetSetting = func(string) string { return "" }
	}
	if err := migrate(db); err != nil {
		return nil, err
	}
	if cfg.DefaultFolder != "" {
		if err := os.MkdirAll(cfg.DefaultFolder, 0o755); err != nil {
			log.Printf("music: cannot create %s: %v", cfg.DefaultFolder, err)
		}
		if err := ensureDefaultFolder(db, cfg.DefaultFolder, filepath.Base(cfg.DefaultFolder)); err != nil {
			return nil, err
		}
	}
	l := &Library{cfg: cfg, db: db, wake: make(chan struct{}, 1)}
	l.Covers = newCovers(l, filepath.Join(cfg.DataDir, "cache", "music"))
	l.status.LastScanAt, _ = strconv.ParseInt(cfg.GetSetting("music.lastScanAt"), 10, 64)
	if err := l.Reload(); err != nil {
		log.Printf("music: initial load failed: %v", err)
		l.snap.Store(buildSnapshot(nil, nil))
	}
	return l, nil
}

// HasFFmpeg reports whether covers can be extracted and tags read.
func (l *Library) HasFFmpeg() bool { return l.cfg.FFmpeg != "" && l.cfg.FFprobe != "" }

// DB returns the database (used by the API for per-profile data).
func (l *Library) DB() *sql.DB { return l.db }

// Snap returns the current snapshot.
func (l *Library) Snap() *Snapshot { return l.snap.Load() }

// Reload rebuilds the snapshot from the database.
func (l *Library) Reload() error {
	l.reloadMu.Lock()
	defer l.reloadMu.Unlock()
	folders, err := loadFolders(l.db)
	if err != nil {
		return err
	}
	rows, err := loadTracks(l.db)
	if err != nil {
		return err
	}
	l.snap.Store(buildSnapshot(folders, rows))
	l.lastReload = time.Now()
	return nil
}

func (l *Library) reloadThrottled() {
	l.reloadMu.Lock()
	recent := time.Since(l.lastReload) < 3*time.Second
	l.reloadMu.Unlock()
	if !recent {
		if err := l.Reload(); err != nil {
			log.Printf("music: reload: %v", err)
		}
	}
}

// Folders returns the configured music folders.
func (l *Library) Folders() ([]Folder, error) { return loadFolders(l.db) }

// AddFolder adds a music folder and starts a scan.
func (l *Library) AddFolder(path, name string) (Folder, error) {
	f, err := addFolder(l.db, path, name)
	if err != nil {
		return f, err
	}
	_ = l.Reload()
	l.RequestScan()
	return f, nil
}

// RemoveFolder removes a (non-default) music folder and its tracks.
func (l *Library) RemoveFolder(id int64) error {
	if err := deleteFolder(l.db, id); err != nil {
		return err
	}
	return l.Reload()
}

// IsMusicDir reports whether abs is one of the music folders. The video
// scanner uses it to stay out of a music folder inside the video library.
func (l *Library) IsMusicDir(abs string) bool {
	for _, f := range l.Snap().Folders {
		if f.Path == abs {
			return true
		}
	}
	return false
}

// Status returns the scan status.
func (l *Library) Status() Status {
	l.mu.Lock()
	defer l.mu.Unlock()
	s := l.status
	s.Queued = l.pending
	return s
}

func (l *Library) setPhase(phase string, done, total int) {
	l.mu.Lock()
	l.status.Phase, l.status.Done, l.status.Total = phase, done, total
	l.mu.Unlock()
}

func (l *Library) setProgress(done int) {
	l.mu.Lock()
	l.status.Done = done
	l.mu.Unlock()
}

// RequestScan queues a scan.
func (l *Library) RequestScan() {
	l.mu.Lock()
	l.pending = true
	l.mu.Unlock()
	l.Wake()
}

// Wake makes the scan loop re-check its timers.
func (l *Library) Wake() {
	select {
	case l.wake <- struct{}{}:
	default:
	}
}

func (l *Library) scheduleRescan(d time.Duration) {
	l.mu.Lock()
	at := time.Now().Add(d)
	if l.rescanAt.IsZero() || at.Before(l.rescanAt) {
		l.rescanAt = at
	}
	l.mu.Unlock()
	l.Wake()
}

func (l *Library) scanInterval() time.Duration {
	n, err := strconv.Atoi(l.cfg.GetSetting("scanIntervalMinutes"))
	if err != nil {
		n = 30
	}
	if n <= 0 {
		return 0
	}
	return time.Duration(n) * time.Minute
}

// Run is the scan loop; it returns when ctx is cancelled.
func (l *Library) Run(ctx context.Context) {
	l.RequestScan()
	for {
		interval := l.scanInterval()
		l.mu.Lock()
		next := time.Time{}
		if interval > 0 {
			next = time.Unix(l.status.LastScanAt, 0).Add(interval)
		}
		if !l.rescanAt.IsZero() && (next.IsZero() || l.rescanAt.Before(next)) {
			next = l.rescanAt
		}
		pending := l.pending
		l.mu.Unlock()
		var timer <-chan time.Time
		var t *time.Timer
		if !next.IsZero() {
			d := max(time.Until(next), time.Second)
			t = time.NewTimer(d)
			timer = t.C
		}
		if !pending {
			select {
			case <-ctx.Done():
				if t != nil {
					t.Stop()
				}
				return
			case <-l.wake:
			case <-timer:
				l.mu.Lock()
				l.pending = true
				l.mu.Unlock()
			case <-time.After(5 * time.Minute):
			}
		}
		if t != nil {
			t.Stop()
		}
		l.mu.Lock()
		if !l.pending {
			l.mu.Unlock()
			continue
		}
		l.pending = false
		l.rescanAt = time.Time{}
		l.status.Running = true
		l.status.LastError = ""
		l.mu.Unlock()

		l.stopBackground()
		start := time.Now()
		err := l.scan(ctx)
		l.mu.Lock()
		l.status.Running = false
		l.status.Phase = ""
		l.status.Done, l.status.Total = 0, 0
		l.status.LastScanAt = time.Now().Unix()
		if err != nil && ctx.Err() == nil {
			l.status.LastError = err.Error()
			log.Printf("music: scan: %v", err)
		}
		last := l.status.LastScanAt
		l.mu.Unlock()
		if l.cfg.GetSetting != nil {
			l.setSetting("music.lastScanAt", strconv.FormatInt(last, 10))
		}
		if ctx.Err() != nil {
			return
		}
		snap := l.Snap()
		log.Printf("music: scan done in %s: %d tracks, %d albums, %d artists", time.Since(start).Round(time.Millisecond),
			len(snap.Tracks), len(snap.Albums), len(snap.Artists))
		l.startBackground(ctx)
	}
}

func (l *Library) setSetting(k, v string) {
	_, _ = l.db.Exec(`INSERT INTO settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value`, k, v)
}

// ---------- background cover pass ----------

func (l *Library) stopBackground() {
	l.bgMu.Lock()
	if l.bgCancel != nil {
		l.bgCancel()
		l.bgCancel = nil
	}
	l.bgMu.Unlock()
}

func (l *Library) startBackground(parent context.Context) {
	ctx, cancel := context.WithCancel(parent)
	l.bgMu.Lock()
	if l.bgCancel != nil {
		l.bgCancel()
	}
	l.bgCancel = cancel
	l.bgMu.Unlock()
	go func() {
		defer cancel()
		l.Covers.prepareAll(ctx)
	}()
}

// RefreshCovers forgets failed internet lookups and runs the cover pass again.
func (l *Library) RefreshCovers(ctx context.Context) {
	_, _ = l.db.Exec(`DELETE FROM music_covers WHERE status<>'ok'`)
	l.Covers.forgetLookups()
	l.startBackground(ctx)
}

func (l *Library) setCoverTask(task string, done, total int) {
	l.mu.Lock()
	l.status.CoverTask, l.status.CoverDone, l.status.CoverTotal = task, done, total
	l.mu.Unlock()
}

// ---------- helpers ----------

func (l *Library) command(ctx context.Context, bin string, args ...string) *exec.Cmd {
	return lowPrio(ctx, l.cfg.Nice, "10", bin, args...)
}

func lowPrio(ctx context.Context, nice, level, bin string, args ...string) *exec.Cmd {
	var cmd *exec.Cmd
	if nice != "" {
		cmd = exec.CommandContext(ctx, nice, append([]string{"-n", level, bin}, args...)...)
	} else {
		cmd = exec.CommandContext(ctx, bin, args...)
	}
	cmd.Stdin = nil
	cmd.WaitDelay = 2 * time.Second
	return cmd
}

func fileExists(p string) bool {
	if p == "" {
		return false
	}
	st, err := os.Stat(p)
	return err == nil && st.Mode().IsRegular()
}

// folderAvailable: an empty folder that had tracks before is most likely an
// unplugged disk; its tracks are hidden, not deleted.
func folderAvailable(p string, hadItems bool) bool {
	st, err := os.Stat(p)
	if err != nil || !st.IsDir() {
		return false
	}
	f, err := os.Open(p)
	if err != nil {
		return false
	}
	defer f.Close()
	entries, err := f.Readdirnames(1)
	if len(entries) == 0 {
		if err != nil && !errors.Is(err, io.EOF) {
			return false
		}
		return !hadItems
	}
	return true
}

// ScanOnce runs a synchronous scan (tests).
func (l *Library) ScanOnce(ctx context.Context) error { return l.scan(ctx) }
