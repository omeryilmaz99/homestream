// Package library scans folders, probes files, fetches metadata and
// maintains the in-memory library snapshot.
package library

import (
	"context"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"sync"
	"sync/atomic"
	"time"

	"homestream/internal/store"
)

// Config holds runtime configuration.
type Config struct {
	DataDir        string
	DefaultLibrary string
	FFprobe        string // "" when missing
	FFmpeg         string // "" when missing
	Nice           string // path of nice(1) or ""
	TMDBBaseURL    string
	TMDBImageBase  string
	ProbeWorkers   int
}

// ScanStatus is reported by GET /api/scan/status.
type ScanStatus struct {
	Running         bool   `json:"running"`
	Phase           string `json:"phase"`
	Done            int    `json:"done"`
	Total           int    `json:"total"`
	LastScanAt      int64  `json:"lastScanAt"`
	LastError       string `json:"lastError"`
	Queued          bool   `json:"queued"`
	BackgroundTask  string `json:"backgroundTask"`
	BackgroundDone  int    `json:"backgroundDone"`
	BackgroundTotal int    `json:"backgroundTotal"`
}

// Library is the central library service.
type Library struct {
	Cfg    Config
	St     *store.Store
	Images *Images

	snap atomic.Pointer[Snapshot]

	mu          sync.Mutex
	status      ScanStatus
	pending     bool
	pendingMeta bool
	wake        chan struct{}
	rescanAt    time.Time

	reloadMu   sync.Mutex
	lastReload time.Time

	bgMu     sync.Mutex
	bgCancel context.CancelFunc

	// SkipDir, when set, tells the scanner to stay out of a folder (the
	// music folder inside the video library).
	SkipDir func(abs string) bool
}

// New creates the library service.
func New(cfg Config, st *store.Store) *Library {
	if cfg.ProbeWorkers <= 0 {
		cfg.ProbeWorkers = 3
	}
	if cfg.TMDBBaseURL == "" {
		cfg.TMDBBaseURL = "https://api.themoviedb.org/3"
	}
	if cfg.TMDBImageBase == "" {
		cfg.TMDBImageBase = "https://image.tmdb.org/t/p"
	}
	l := &Library{Cfg: cfg, St: st, wake: make(chan struct{}, 1)}
	l.Images = NewImages(filepath.Join(cfg.DataDir, "cache"), cfg.FFmpeg, cfg.Nice)
	l.status.LastScanAt, _ = strconv.ParseInt(st.GetSetting("lastScanAt"), 10, 64)
	if err := l.Reload(); err != nil {
		log.Printf("library: initial load failed: %v", err)
		l.snap.Store(buildSnapshot(nil, nil, nil, nil))
	}
	return l
}

// Snap returns the current snapshot.
func (l *Library) Snap() *Snapshot { return l.snap.Load() }

// Reload rebuilds the in-memory snapshot from the database.
func (l *Library) Reload() error {
	l.reloadMu.Lock()
	defer l.reloadMu.Unlock()
	folders, err := l.St.Folders()
	if err != nil {
		return err
	}
	files, err := l.St.LoadFiles()
	if err != nil {
		return err
	}
	series, err := l.St.LoadSeries()
	if err != nil {
		return err
	}
	meta, err := l.St.AllMeta()
	if err != nil {
		return err
	}
	l.snap.Store(buildSnapshot(folders, files, series, meta))
	l.lastReload = time.Now()
	return nil
}

// reloadThrottled reloads at most every 3 seconds.
func (l *Library) reloadThrottled() {
	l.reloadMu.Lock()
	recent := time.Since(l.lastReload) < 3*time.Second
	l.reloadMu.Unlock()
	if !recent {
		if err := l.Reload(); err != nil {
			log.Printf("library: reload: %v", err)
		}
	}
}

// Status returns the scan status.
func (l *Library) Status() ScanStatus {
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

// RequestScan queues a scan (merged with any pending request).
func (l *Library) RequestScan(refreshMeta bool) {
	l.mu.Lock()
	l.pending = true
	l.pendingMeta = l.pendingMeta || refreshMeta
	l.mu.Unlock()
	select {
	case l.wake <- struct{}{}:
	default:
	}
}

// Wake makes the scan loop re-evaluate its timer (e.g. after the interval changed).
func (l *Library) Wake() {
	select {
	case l.wake <- struct{}{}:
	default:
	}
}

func (l *Library) scanInterval() time.Duration {
	n, err := strconv.Atoi(l.St.GetSetting("scanIntervalMinutes"))
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
	l.RequestScan(false)
	for {
		interval := l.scanInterval()
		var timer <-chan time.Time
		l.mu.Lock()
		next := time.Time{}
		if interval > 0 {
			last := time.Unix(l.status.LastScanAt, 0)
			next = last.Add(interval)
		}
		if !l.rescanAt.IsZero() && (next.IsZero() || l.rescanAt.Before(next)) {
			next = l.rescanAt
		}
		pending := l.pending
		l.mu.Unlock()
		var t *time.Timer
		if !next.IsZero() {
			d := time.Until(next)
			if d < time.Second {
				d = time.Second
			}
			t = time.NewTimer(d)
			timer = t.C
		}
		if !pending {
			select {
			case <-ctx.Done():
				return
			case <-l.wake:
			case <-timer:
				l.mu.Lock()
				l.pending = true
				l.mu.Unlock()
			case <-time.After(5 * time.Minute): // re-evaluate interval changes
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
		refresh := l.pendingMeta
		l.pending, l.pendingMeta = false, false
		l.rescanAt = time.Time{}
		l.status.Running = true
		l.status.LastError = ""
		l.mu.Unlock()

		l.stopBackground()
		start := time.Now()
		err := l.scan(ctx, refresh)
		l.mu.Lock()
		l.status.Running = false
		l.status.Phase = ""
		l.status.Done, l.status.Total = 0, 0
		l.status.LastScanAt = time.Now().Unix()
		if err != nil && ctx.Err() == nil {
			l.status.LastError = err.Error()
		}
		last := l.status.LastScanAt
		l.mu.Unlock()
		_ = l.St.SetSetting("lastScanAt", strconv.FormatInt(last, 10))
		if ctx.Err() != nil {
			return
		}
		snap := l.Snap()
		log.Printf("scan: done in %s: %d movies, %d series, %d episodes", time.Since(start).Round(time.Millisecond),
			len(snap.Movies), len(snap.Series), len(snap.Episodes))
		l.startBackground(ctx)
	}
}

func (l *Library) setError(msg string) {
	l.mu.Lock()
	l.status.LastError = msg
	l.mu.Unlock()
}

func (l *Library) scheduleRescan(d time.Duration) {
	l.mu.Lock()
	at := time.Now().Add(d)
	if l.rescanAt.IsZero() || at.Before(l.rescanAt) {
		l.rescanAt = at
	}
	l.mu.Unlock()
	select {
	case l.wake <- struct{}{}:
	default:
	}
}

// ---------- background image generation ----------

func (l *Library) stopBackground() {
	l.bgMu.Lock()
	if l.bgCancel != nil {
		l.bgCancel()
		l.bgCancel = nil
	}
	l.bgMu.Unlock()
}

func (l *Library) startBackground(parent context.Context) {
	if !l.Images.CanGenerate() {
		return
	}
	ctx, cancel := context.WithCancel(parent)
	l.bgMu.Lock()
	if l.bgCancel != nil {
		l.bgCancel()
	}
	l.bgCancel = cancel
	l.bgMu.Unlock()
	go func() {
		defer cancel()
		snap := l.Snap()
		var todo []*Item
		for _, it := range snap.Movies {
			if !l.Images.HasFrame(it) {
				todo = append(todo, it)
			}
		}
		for _, it := range snap.Episodes {
			if !l.Images.HasFrame(it) {
				todo = append(todo, it)
			}
		}
		if len(todo) == 0 {
			return
		}
		l.setBG("Görseller hazırlanıyor", 0, len(todo))
		defer l.setBG("", 0, 0)
		var wg sync.WaitGroup
		sem := make(chan struct{}, 2)
		var done atomic.Int64
		for _, it := range todo {
			if ctx.Err() != nil {
				break
			}
			sem <- struct{}{}
			wg.Add(1)
			go func(it *Item) {
				defer func() { <-sem; wg.Done() }()
				l.Images.Frame(ctx, it)
				l.setBG("Görseller hazırlanıyor", int(done.Add(1)), len(todo))
			}(it)
		}
		wg.Wait()
	}()
}

func (l *Library) setBG(task string, done, total int) {
	l.mu.Lock()
	l.status.BackgroundTask, l.status.BackgroundDone, l.status.BackgroundTotal = task, done, total
	l.mu.Unlock()
}

// command builds an exec.Cmd running at low priority when nice is available.
func (l *Library) command(ctx context.Context, bin string, args ...string) *exec.Cmd {
	return lowPrio(ctx, l.Cfg.Nice, "10", bin, args...)
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

// LookTools finds ffprobe/ffmpeg/nice in PATH.
func LookTools() (ffprobe, ffmpeg, nice string) {
	ffprobe, _ = exec.LookPath("ffprobe")
	ffmpeg, _ = exec.LookPath("ffmpeg")
	nice, _ = exec.LookPath("nice")
	return
}

func fileExists(p string) bool {
	if p == "" {
		return false
	}
	st, err := os.Stat(p)
	return err == nil && st.Mode().IsRegular()
}

// ScanOnce runs a single synchronous scan (used by tests and tools).
func (l *Library) ScanOnce(ctx context.Context) error { return l.scan(ctx, false) }
