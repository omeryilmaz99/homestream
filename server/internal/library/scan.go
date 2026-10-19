package library

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log"
	"os"
	"path"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"

	"homestream/internal/names"
	"homestream/internal/store"
)

// VideoExts are the recognised video file extensions.
var VideoExts = map[string]bool{
	".mkv": true, ".mp4": true, ".m4v": true, ".avi": true, ".mov": true, ".wmv": true, ".ts": true,
	".m2ts": true, ".mts": true, ".webm": true, ".flv": true, ".mpg": true, ".mpeg": true, ".vob": true,
	".ogv": true, ".3gp": true, ".rmvb": true, ".divx": true,
}

var subExts = map[string]bool{".srt": true, ".ass": true, ".ssa": true, ".vtt": true, ".sub": true, ".idx": true, ".sup": true}
var imageExts = []string{".jpg", ".jpeg", ".png"}

var skipDirs = map[string]bool{
	"@eadir": true, "$recycle.bin": true, "system volume information": true, "lost+found": true,
	"#recycle": true, "#snapshot": true, "recycler": true, "$recycle": true,
}

var subDirNames = map[string]bool{"subs": true, "subtitles": true, "altyazi": true, "altyazilar": true, "sub": true, "subtitle": true}

const (
	minVideoSize  = 1 << 20
	sampleMaxSize = 300 << 20
)

// IsVideoName reports whether a file name has a video extension.
func IsVideoName(name string) bool { return VideoExts[strings.ToLower(filepath.Ext(name))] }

// SkipDirName reports whether a directory should be ignored while walking.
func SkipDirName(name string) bool {
	return strings.HasPrefix(name, ".") || skipDirs[strings.ToLower(name)]
}

// AcceptVideo applies the size / sample filters.
func AcceptVideo(name string, size int64) bool {
	if strings.HasPrefix(name, ".") || !IsVideoName(name) || size < minVideoSize {
		return false
	}
	if size < sampleMaxSize && strings.Contains(strings.ToLower(name), "sample") {
		return false
	}
	return true
}

type walkedFile struct {
	abs, rel string
	dir      string
	name     string
	size     int64
	mtime    int64
	ctime    int64
}

type dirInfo struct {
	files   []string
	subdirs []string
	lower   map[string]string // lower-case name → real name (files)
	videos  int
}

func (d *dirInfo) find(name string) string {
	if d == nil {
		return ""
	}
	if d.lower == nil {
		d.lower = make(map[string]string, len(d.files))
		for _, f := range d.files {
			d.lower[strings.ToLower(f)] = f
		}
	}
	return d.lower[strings.ToLower(name)]
}

type walker struct {
	ctx     context.Context
	root    string
	files   []walkedFile
	dirs    map[string]*dirInfo
	visited map[fileKey]bool
	errs    int
}

func walkFolder(ctx context.Context, root string) (*walker, error) {
	w := &walker{ctx: ctx, root: root, dirs: map[string]*dirInfo{}, visited: map[fileKey]bool{}}
	if k, ok := statKey(root); ok {
		w.visited[k] = true
	}
	w.walk(root, "", 0)
	return w, ctx.Err()
}

func (w *walker) walk(abs, rel string, depth int) {
	if depth > 40 || w.ctx.Err() != nil {
		return
	}
	entries, err := os.ReadDir(abs)
	if err != nil {
		w.errs++
		if w.errs < 20 {
			log.Printf("scan: cannot read %s: %v", abs, err)
		}
		return
	}
	di := &dirInfo{}
	w.dirs[abs] = di
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
			if SkipDirName(name) {
				continue
			}
			di.subdirs = append(di.subdirs, name)
			k, ok := statKey(full)
			if ok {
				if w.visited[k] {
					continue // symlink loop or already walked
				}
				w.visited[k] = true
			}
			w.walk(full, childRel, depth+1)
		case mode.IsRegular():
			di.files = append(di.files, name)
			if !IsVideoName(name) {
				continue
			}
			if info == nil {
				info, err = e.Info()
				if err != nil {
					continue
				}
			}
			if !AcceptVideo(name, info.Size()) {
				continue
			}
			di.videos++
			w.files = append(w.files, walkedFile{
				abs: full, rel: childRel, dir: abs, name: name,
				size: info.Size(), mtime: info.ModTime().Unix(), ctime: changeTime(info),
			})
		}
	}
}

type seriesAgg struct {
	titles map[string]int
	years  map[int]int
	dirs   map[string]int
	order  []string
}

func (a *seriesAgg) best() (string, int, string) {
	pick := func(m map[string]int) string {
		best, bn := "", -1
		for _, k := range a.order {
			if n, ok := m[k]; ok && n > bn {
				best, bn = k, n
			}
		}
		return best
	}
	title := pick(a.titles)
	year, yn := 0, 0
	for y, n := range a.years {
		if y > 0 && (n > yn || (n == yn && y < year)) {
			year, yn = y, n
		}
	}
	dir, dn := "", 0
	dirKeys := make([]string, 0, len(a.dirs))
	for d := range a.dirs {
		dirKeys = append(dirKeys, d)
	}
	sort.Strings(dirKeys)
	for _, d := range dirKeys {
		if d != "" && a.dirs[d] > dn {
			dir, dn = d, a.dirs[d]
		}
	}
	return title, year, dir
}

// scan runs one full scan.
func (l *Library) scan(ctx context.Context, refreshMeta bool) error {
	l.setPhase("Dosyalar taranıyor", 0, 0)
	folders, err := l.St.Folders()
	if err != nil {
		return err
	}
	states, err := l.St.FileStates()
	if err != nil {
		return err
	}
	byFolder := map[int64]int{}
	for _, s := range states {
		byFolder[s.FolderID]++
	}
	now := time.Now().Unix()
	var rows []store.FileRow
	var toProbe []store.FileRow
	seen := map[string]bool{}
	aggs := map[string]*seriesAgg{}
	seriesDirInfo := map[string]*dirInfo{}
	walkers := map[string]*walker{}
	recent := false
	var lastErr error

	for _, f := range folders {
		if f.IsDefault {
			_ = os.MkdirAll(f.Path, 0o755)
		}
		// the empty-folder heuristic (unmounted disk) only applies to extra folders
		avail := folderAvailable(f.Path, byFolder[f.ID] > 0 && !f.IsDefault)
		if avail != f.Available {
			if avail {
				log.Printf("scan: folder %q is available again", f.Path)
			} else {
				log.Printf("scan: folder %q is unavailable; its items are hidden (not deleted)", f.Path)
			}
		}
		_ = l.St.SetFolderAvailable(f.ID, avail)
		if !avail {
			continue
		}
		w, err := walkFolder(ctx, f.Path)
		if err != nil {
			return err
		}
		walkers[f.Path] = w

		parsed := make([]names.Parsed, len(w.files))
		for i, wf := range w.files {
			parsed[i] = names.ParsePath(wf.rel)
		}
		applyMultiPrefixRule(w.files, parsed)

		for i, wf := range w.files {
			p := parsed[i]
			typ := "movie"
			if p.Kind == names.Episode {
				typ = "episode"
			}
			id := HashID(typ, wf.abs)
			if seen[id] {
				continue
			}
			seen[id] = true
			di := w.dirs[wf.dir]
			base := strings.TrimSuffix(wf.name, path.Ext(wf.name))
			r := store.FileRow{
				ID: id, Type: typ, FolderID: f.ID, RelPath: wf.rel, Size: wf.size, MTime: wf.mtime,
				Title: p.Title, Year: p.Year, Season: p.Season, Episode: p.Episode,
			}
			if st, ok := states[id]; ok && st.AddedAt > 0 {
				r.AddedAt = st.AddedAt
			} else {
				r.AddedAt = max(wf.mtime, wf.ctime)
				if r.AddedAt > now || r.AddedAt <= 0 {
					r.AddedAt = now
				}
			}
			if typ == "episode" {
				key := names.Key(p.SeriesTitle)
				r.SeriesID = HashID("series", key)
				a := aggs[r.SeriesID]
				if a == nil {
					a = &seriesAgg{titles: map[string]int{}, years: map[int]int{}, dirs: map[string]int{}}
					aggs[r.SeriesID] = a
				}
				if _, ok := a.titles[p.SeriesTitle]; !ok {
					a.order = append(a.order, p.SeriesTitle)
				}
				a.titles[p.SeriesTitle]++
				a.years[p.SeriesYear]++
				sdir := ""
				if p.SeriesDir != "" {
					sdir = filepath.Join(f.Path, filepath.FromSlash(p.SeriesDir))
					seriesDirInfo[sdir] = w.dirs[sdir]
				}
				a.dirs[sdir]++
				r.LocalBackdrop = findImage(di, wf.dir, base+"-thumb", base)
			} else {
				single := di != nil && di.videos == 1 && wf.dir != f.Path
				r.LocalPoster = findImage(di, wf.dir, base+"-poster", base)
				r.LocalBackdrop = findImage(di, wf.dir, base+"-fanart", base+"-backdrop")
				if single {
					if r.LocalPoster == "" {
						r.LocalPoster = findImage(di, wf.dir, "poster", "folder", "cover", "movie")
					}
					if r.LocalBackdrop == "" {
						r.LocalBackdrop = findImage(di, wf.dir, "fanart", "backdrop", "background", "art")
					}
				}
			}
			subs := findSubtitles(w, wf, base, di)
			if len(subs) > 0 {
				b, _ := json.Marshal(subs)
				r.Subs = string(b)
			}
			rows = append(rows, r)

			st, ok := states[id]
			needProbe := !ok || st.ProbeState != 1 || st.ProbeSize != wf.size || st.ProbeMTime != wf.mtime
			if needProbe && l.Cfg.FFprobe != "" {
				if now-wf.mtime < 60 {
					recent = true // probably still being copied; retry soon
				} else {
					toProbe = append(toProbe, r) // includes earlier failures: retried every scan
				}
			}
		}
	}
	if err := l.St.UpsertFiles(rows); err != nil {
		return err
	}
	// remove items that disappeared from available folders
	avail := map[int64]bool{}
	if fs, err := l.St.Folders(); err == nil {
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
		log.Printf("scan: %d files removed", len(gone))
		if err := l.St.DeleteFiles(gone); err != nil {
			return err
		}
	}
	// series
	var srows []store.SeriesRow
	for id, a := range aggs {
		title, year, dir := a.best()
		sr := store.SeriesRow{ID: id, Title: title, Year: year, Dir: dir}
		if dir != "" {
			di := seriesDirInfo[dir]
			sr.LocalPoster = findImage(di, dir, "poster", "folder", "cover", "show")
			sr.LocalBackdrop = findImage(di, dir, "fanart", "backdrop", "background", "art")
		}
		srows = append(srows, sr)
	}
	if err := l.St.ReplaceSeries(srows); err != nil {
		return err
	}
	if err := l.Reload(); err != nil {
		return err
	}
	if recent {
		l.scheduleRescan(2 * time.Minute)
	}

	// probe phase
	if len(toProbe) > 0 {
		if err := l.probeAll(ctx, toProbe); err != nil {
			lastErr = err
		}
		if err := l.Reload(); err != nil {
			return err
		}
	}
	if ctx.Err() != nil {
		return ctx.Err()
	}
	// metadata phase
	if err := l.fetchMetadata(ctx, refreshMeta); err != nil {
		lastErr = err
	}
	if err := l.Reload(); err != nil {
		return err
	}
	return lastErr
}

// applyMultiPrefixRule: when a folder holds episodes of several different
// shows (by file name prefix), the folder name is not the series title.
func applyMultiPrefixRule(files []walkedFile, parsed []names.Parsed) {
	byDir := map[string][]int{}
	for i := range files {
		if parsed[i].Kind == names.Episode && parsed[i].TitleFromFolder {
			byDir[files[i].dir] = append(byDir[files[i].dir], i)
		}
	}
	for _, idx := range byDir {
		keys := map[string]bool{}
		for _, i := range idx {
			if k := names.Key(parsed[i].FilePrefix); k != "" {
				keys[k] = true
			}
		}
		if len(keys) < 2 {
			continue
		}
		for _, i := range idx {
			p := &parsed[i]
			if p.FilePrefix != "" {
				p.SeriesTitle, p.SeriesYear, p.SeriesDir, p.TitleFromFolder = p.FilePrefix, p.FilePrefixYear, "", false
			}
		}
	}
}

// folderAvailable decides whether a library folder is usable. An empty
// folder that previously had items is considered unavailable (most likely an
// unmounted disk's mount point).
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
			return false // unreadable
		}
		return !hadItems // empty: probably an unmounted disk
	}
	return true
}

func findImage(di *dirInfo, dir string, bases ...string) string {
	if di == nil {
		return ""
	}
	for _, b := range bases {
		for _, ext := range imageExts {
			if n := di.find(b + ext); n != "" {
				return filepath.Join(dir, n)
			}
		}
	}
	return ""
}

func isSubFile(name string) bool { return subExts[strings.ToLower(filepath.Ext(name))] }

func matchesBase(name, base string) bool {
	ln, lb := strings.ToLower(name), strings.ToLower(base)
	if !strings.HasPrefix(ln, lb) {
		return false
	}
	rest := ln[len(lb):]
	return rest == "" || rest[0] == '.' || rest[0] == '_'
}

func findSubtitles(w *walker, wf walkedFile, base string, di *dirInfo) []ExtSub {
	if di == nil {
		return nil
	}
	single := di.videos == 1
	var out []ExtSub
	seen := map[string]bool{}
	add := func(dir, name string, prefixMatched bool) {
		full := filepath.Join(dir, name)
		if seen[full] {
			return
		}
		ext := strings.ToLower(filepath.Ext(name))
		if ext == ".sub" {
			// VobSub pair: the .idx represents it
			stem := strings.TrimSuffix(name, filepath.Ext(name))
			if d := w.dirs[dir]; d != nil && d.find(stem+".idx") != "" {
				return
			}
		}
		seen[full] = true
		vb := ""
		if prefixMatched {
			vb = base
		}
		info := names.ParseSubtitle(vb, name)
		out = append(out, ExtSub{ID: HashID("sub", full), Path: full, Language: info.Language,
			Title: info.Title, Format: info.Format, Forced: info.Forced})
	}
	for _, f := range di.files {
		if !isSubFile(f) {
			continue
		}
		if matchesBase(f, base) {
			add(wf.dir, f, true)
		} else if single {
			add(wf.dir, f, false)
		}
	}
	for _, sd := range di.subdirs {
		if !subDirNames[names.Fold(sd)] {
			continue
		}
		subDir := filepath.Join(wf.dir, sd)
		sdi := w.dirs[subDir]
		if sdi == nil {
			continue
		}
		for _, f := range sdi.files {
			if !isSubFile(f) {
				continue
			}
			if matchesBase(f, base) {
				add(subDir, f, true)
			} else if single {
				add(subDir, f, false)
			}
		}
		// RARBG layout: Subs/<video base>/2_English.srt
		for _, inner := range sdi.subdirs {
			if !strings.EqualFold(inner, base) {
				continue
			}
			innerDir := filepath.Join(subDir, inner)
			if idi := w.dirs[innerDir]; idi != nil {
				for _, f := range idi.files {
					if isSubFile(f) {
						add(innerDir, f, false)
					}
				}
			}
		}
	}
	sort.SliceStable(out, func(i, j int) bool {
		if (out[i].Language == "tr") != (out[j].Language == "tr") {
			return out[i].Language == "tr"
		}
		if out[i].Forced != out[j].Forced {
			return !out[i].Forced
		}
		return names.NaturalLess(filepath.Base(out[i].Path), filepath.Base(out[j].Path))
	})
	return out
}

// probeAll probes files with a bounded worker pool.
func (l *Library) probeAll(ctx context.Context, rows []store.FileRow) error {
	l.setPhase("Dosyalar inceleniyor", 0, len(rows))
	snap := l.Snap()
	jobs := make(chan store.FileRow)
	var wg sync.WaitGroup
	var mu sync.Mutex
	done, failed := 0, 0
	for i := 0; i < l.Cfg.ProbeWorkers; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for r := range jobs {
				abs := ""
				if it := snap.Items[r.ID]; it != nil {
					abs = it.AbsPath
				}
				if abs == "" {
					continue
				}
				mi, dur, err := l.probe(ctx, abs)
				state := 1
				media := ""
				if err != nil {
					state = 2
					if ctx.Err() == nil {
						log.Printf("probe: %s: %v", r.RelPath, err)
					}
				} else {
					b, _ := json.Marshal(mi)
					media = string(b)
				}
				if ctx.Err() != nil {
					return
				}
				if err := l.St.SetProbe(r.ID, state, r.Size, r.MTime, media, dur); err != nil {
					log.Printf("probe: store: %v", err)
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
	for _, r := range rows {
		select {
		case jobs <- r:
		case <-ctx.Done():
		}
		if ctx.Err() != nil {
			break
		}
	}
	close(jobs)
	wg.Wait()
	if failed > 0 {
		log.Printf("probe: %d of %d files could not be probed (will retry on next scan)", failed, len(rows))
	}
	return nil
}
