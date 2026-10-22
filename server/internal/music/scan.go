package music

import (
	"context"
	"log"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"homestream/internal/names"
)

// AudioExts are the recognised audio file extensions.
var AudioExts = map[string]bool{
	".mp3": true, ".flac": true, ".m4a": true, ".m4b": true, ".aac": true, ".ogg": true, ".oga": true,
	".opus": true, ".wav": true, ".wma": true, ".ape": true, ".wv": true, ".aiff": true, ".aif": true,
	".aifc": true, ".dsf": true, ".dff": true, ".mka": true, ".mpc": true, ".tta": true, ".ac3": true,
	".dts": true, ".mp2": true, ".amr": true, ".caf": true, ".weba": true, ".spx": true, ".tak": true,
	".alac": true, ".w64": true,
}

// VideoExts are video files that are played as music (their sound) in a
// music folder; the cover is a frame of the video.
var VideoExts = map[string]bool{
	".mp4": true, ".m4v": true, ".mov": true, ".webm": true, ".mkv": true, ".avi": true, ".flv": true,
	".3gp": true, ".ts": true, ".mpg": true, ".mpeg": true, ".wmv": true,
}

var imageExts = []string{".jpg", ".jpeg", ".png", ".webp"}

var skipDirs = map[string]bool{
	"@eadir": true, "$recycle.bin": true, "system volume information": true, "lost+found": true,
	"#recycle": true, "#snapshot": true, "recycler": true, "$recycle": true,
}

// IsMusicName reports whether a file name is a playable music file.
func IsMusicName(name string) bool {
	ext := strings.ToLower(filepath.Ext(name))
	return AudioExts[ext] || VideoExts[ext]
}

func isVideoName(name string) bool { return VideoExts[strings.ToLower(filepath.Ext(name))] }

// acceptFile filters junk (tiny files, macOS resource forks, samples).
func acceptFile(name string, size int64) bool {
	if strings.HasPrefix(name, ".") || !IsMusicName(name) {
		return false
	}
	return size >= 16<<10
}

type walked struct {
	abs, rel string
	dir      string
	size     int64
	mtime    int64
}

type dirFiles struct {
	images []string // image file names
}

type walker struct {
	ctx     context.Context
	files   []walked
	dirs    map[string]*dirFiles
	visited map[string]bool
	errs    int
}

func walkFolder(ctx context.Context, root string) *walker {
	w := &walker{ctx: ctx, dirs: map[string]*dirFiles{}, visited: map[string]bool{}}
	if real, err := filepath.EvalSymlinks(root); err == nil {
		w.visited[real] = true
	}
	w.walk(root, "", 0)
	return w
}

func (w *walker) walk(abs, rel string, depth int) {
	if depth > 40 || w.ctx.Err() != nil {
		return
	}
	entries, err := os.ReadDir(abs)
	if err != nil {
		w.errs++
		if w.errs < 20 {
			log.Printf("music: cannot read %s: %v", abs, err)
		}
		return
	}
	df := &dirFiles{}
	w.dirs[abs] = df
	for _, e := range entries {
		name := e.Name()
		if strings.HasPrefix(name, ".") {
			continue
		}
		full := filepath.Join(abs, name)
		mode := e.Type()
		var info os.FileInfo
		if mode&os.ModeSymlink != 0 {
			info, err = os.Stat(full)
			if err != nil {
				continue
			}
			mode = info.Mode().Type()
		}
		childRel := name
		if rel != "" {
			childRel = rel + "/" + name
		}
		switch {
		case mode.IsDir():
			if skipDirs[strings.ToLower(name)] {
				continue
			}
			if real, err := filepath.EvalSymlinks(full); err == nil {
				if w.visited[real] {
					continue
				}
				w.visited[real] = true
			}
			w.walk(full, childRel, depth+1)
		case mode.IsRegular():
			lower := strings.ToLower(name)
			for _, ext := range imageExts {
				if strings.HasSuffix(lower, ext) {
					df.images = append(df.images, name)
				}
			}
			if !IsMusicName(name) {
				continue
			}
			if info == nil {
				if info, err = e.Info(); err != nil {
					continue
				}
			}
			if !acceptFile(name, info.Size()) {
				continue
			}
			w.files = append(w.files, walked{abs: full, rel: childRel, dir: abs, size: info.Size(), mtime: info.ModTime().Unix()})
		}
	}
}

var coverNames = []string{"cover", "folder", "front", "album", "albumart", "albumartlarge", "artwork", "art", "poster"}

// dirCover finds the folder image of a directory (or of the album folder
// above a "CD1" folder).
func (w *walker) dirCover(dir string) string {
	try := func(d string) string {
		df := w.dirs[d]
		if df == nil || len(df.images) == 0 {
			return ""
		}
		lower := map[string]string{}
		for _, n := range df.images {
			lower[strings.ToLower(n)] = n
		}
		for _, b := range coverNames {
			for _, ext := range imageExts {
				if n, ok := lower[b+ext]; ok {
					return filepath.Join(d, n)
				}
			}
		}
		// "AlbumArt_{GUID}_Large.jpg" (Windows Media Player)
		for _, n := range df.images {
			l := strings.ToLower(n)
			if strings.HasPrefix(l, "albumart") && strings.Contains(l, "large") {
				return filepath.Join(d, n)
			}
		}
		if len(df.images) == 1 {
			return filepath.Join(d, df.images[0])
		}
		for _, n := range df.images {
			l := strings.ToLower(n)
			if strings.Contains(l, "cover") || strings.Contains(l, "front") || strings.Contains(l, "kapak") {
				return filepath.Join(d, n)
			}
		}
		return ""
	}
	if c := try(dir); c != "" {
		return c
	}
	if _, ok := isDiscDir(filepath.Base(dir)); ok {
		return try(filepath.Dir(dir))
	}
	return ""
}

func (l *Library) scan(ctx context.Context) error {
	l.setPhase("Müzikler taranıyor", 0, 0)
	folders, err := loadFolders(l.db)
	if err != nil {
		return err
	}
	old, err := loadTracks(l.db)
	if err != nil {
		return err
	}
	states := make(map[string]trackRow, len(old))
	byFolder := map[int64]int{}
	for _, r := range old {
		states[r.ID] = r
		byFolder[r.FolderID]++
	}
	now := time.Now().Unix()
	var rows, toProbe []trackRow
	seen := map[string]bool{}
	recent := false
	for _, f := range folders {
		if f.IsDefault {
			_ = os.MkdirAll(f.Path, 0o755)
		}
		avail := folderAvailable(f.Path, byFolder[f.ID] > 0 && !f.IsDefault)
		if avail != f.Available {
			if avail {
				log.Printf("music: folder %q is available again", f.Path)
			} else {
				log.Printf("music: folder %q is unavailable; its songs are hidden (not deleted)", f.Path)
			}
			setFolderAvailable(l.db, f.ID, avail)
		}
		if !avail {
			continue
		}
		w := walkFolder(ctx, f.Path)
		if ctx.Err() != nil {
			return ctx.Err()
		}
		for _, wf := range w.files {
			id := hashID("track", wf.abs)
			if seen[id] {
				continue
			}
			seen[id] = true
			r := trackRow{ID: id, FolderID: f.ID, RelPath: wf.rel, Size: wf.size, MTime: wf.mtime, DirCover: w.dirCover(wf.dir)}
			prev, had := states[id]
			if had {
				r.AddedAt = prev.AddedAt
				r.ProbeState, r.ProbeSize, r.ProbeMTime, r.Tags = prev.ProbeState, prev.ProbeSize, prev.ProbeMTime, prev.Tags
			}
			if r.AddedAt <= 0 || r.AddedAt > now {
				if len(old) == 0 {
					// first scan of the library: keep the files' own dates
					r.AddedAt = min(max(wf.mtime, 1), now)
				} else {
					r.AddedAt = now
				}
			}
			if !had {
				r.Tags = Tags{IsVideo: isVideoName(wf.abs)}
				fileFallback(&r.Tags, wf.rel)
			}
			rows = append(rows, r)
			changed := !had || prev.ProbeSize != wf.size || prev.ProbeMTime != wf.mtime || prev.ProbeState == 0
			if changed && l.cfg.FFprobe != "" {
				if now-wf.mtime < 60 {
					recent = true // probably still being copied
				} else {
					toProbe = append(toProbe, r)
				}
			}
		}
	}
	if err := upsertTracks(l.db, rows); err != nil {
		return err
	}
	avail := map[int64]bool{}
	if fs, err := loadFolders(l.db); err == nil {
		for _, f := range fs {
			avail[f.ID] = f.Available
		}
	}
	var gone []string
	for id, st := range states {
		if !seen[id] && avail[st.FolderID] {
			gone = append(gone, id)
		}
	}
	if len(gone) > 0 {
		log.Printf("music: %d files removed", len(gone))
		if err := deleteTracks(l.db, gone); err != nil {
			return err
		}
	}
	if err := l.Reload(); err != nil {
		return err
	}
	if recent {
		l.scheduleRescan(2 * time.Minute)
	}
	if len(toProbe) > 0 {
		l.probeAll(ctx, toProbe)
		if err := l.Reload(); err != nil {
			return err
		}
	}
	return ctx.Err()
}

func (l *Library) probeAll(ctx context.Context, rows []trackRow) {
	l.setPhase("Şarkı bilgileri okunuyor", 0, len(rows))
	jobs := make(chan trackRow)
	var wg sync.WaitGroup
	var mu sync.Mutex
	done, failed := 0, 0
	folders := map[int64]string{}
	if fs, err := loadFolders(l.db); err == nil {
		for _, f := range fs {
			folders[f.ID] = f.Path
		}
	}
	for i := 0; i < l.cfg.ProbeWorkers; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for r := range jobs {
				abs := filepath.Join(folders[r.FolderID], filepath.FromSlash(r.RelPath))
				t, err := l.probe(ctx, abs)
				state := 1
				if err != nil {
					if ctx.Err() != nil {
						return
					}
					state = 2
					log.Printf("music: probe %s: %v", r.RelPath, err)
					t = Tags{IsVideo: isVideoName(abs)}
				}
				if t.IsVideo && !isVideoName(abs) {
					t.IsVideo = false // e.g. a .m4a with a stray video stream
				}
				fileFallback(&t, r.RelPath)
				if err := setProbe(l.db, r.ID, state, r.Size, r.MTime, t); err != nil {
					log.Printf("music: store probe: %v", err)
				}
				mu.Lock()
				done++
				if err != nil {
					failed++
				}
				d := done
				mu.Unlock()
				l.setProgress(d)
				l.reloadThrottled()
			}
		}()
	}
loop:
	for _, r := range rows {
		select {
		case jobs <- r:
		case <-ctx.Done():
			break loop
		}
	}
	close(jobs)
	wg.Wait()
	if failed > 0 {
		log.Printf("music: %d of %d files could not be read", failed, len(rows))
	}
}

// displayPath is the path shown to users: "<folder name>/<rel>".
func displayPath(s *Snapshot, t *Track) string {
	for _, f := range s.Folders {
		if f.ID == t.FolderID {
			return f.Name + "/" + names.DisplayString(t.RelPath)
		}
	}
	return names.DisplayString(t.RelPath)
}
