package library

import (
	"context"
	"encoding/json"
	"log"
	"os"
	"path/filepath"
	"sort"
	"time"

	"homestream/internal/store"
)

// WatchDrives adds every disk mounted under dir (one sub-folder per disk, see
// the automount helper in install.sh) as a library folder, and rescans when a
// disk appears, disappears or comes back. A disk folder is added only once: if
// the user removes it in the app it stays removed.
func (l *Library) WatchDrives(ctx context.Context, dir string) {
	if dir == "" {
		return
	}
	check := func() {
		entries, err := os.ReadDir(dir)
		if err != nil && !os.IsNotExist(err) {
			return
		}
		seen := l.seenDrives()
		folders, err := l.St.Folders()
		if err != nil {
			return
		}
		known := map[string]bool{}
		changed := false
		for _, f := range folders {
			known[f.Path] = true
			if filepath.Dir(f.Path) != filepath.Clean(dir) {
				continue
			}
			// availability flipped since the last scan → rescan
			if folderAvailable(f.Path, l.St.FolderFileCount(f.ID) > 0) != f.Available {
				changed = true
			}
		}
		added := false
		for _, e := range entries {
			if !e.IsDir() || e.Name()[0] == '.' {
				continue
			}
			p := filepath.Join(dir, e.Name())
			if known[p] || seen[p] {
				continue
			}
			seen[p] = true
			added = true
			if _, err := l.St.AddFolder(p, e.Name(), store.FolderAuto); err != nil {
				log.Printf("drives: cannot add %s: %v", p, err)
				continue
			}
			log.Printf("drives: new disk %q added to the library", p)
			changed = true
		}
		if added {
			l.saveSeenDrives(seen)
		}
		if changed {
			if err := l.Reload(); err != nil {
				log.Printf("drives: reload: %v", err)
			}
			l.RequestScan(false)
		}
	}
	check()
	t := time.NewTicker(15 * time.Second)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			check()
		}
	}
}

func (l *Library) seenDrives() map[string]bool {
	var list []string
	_ = json.Unmarshal([]byte(l.St.GetSetting("seenDrives")), &list)
	m := make(map[string]bool, len(list))
	for _, p := range list {
		m[p] = true
	}
	return m
}

func (l *Library) saveSeenDrives(m map[string]bool) {
	list := make([]string, 0, len(m))
	for p := range m {
		list = append(list, p)
	}
	sort.Strings(list)
	b, _ := json.Marshal(list)
	_ = l.St.SetSetting("seenDrives", string(b))
}
