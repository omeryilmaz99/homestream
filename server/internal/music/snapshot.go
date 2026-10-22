package music

import (
	"crypto/sha1"
	"encoding/hex"
	"path"
	"path/filepath"
	"sort"
	"strconv"
	"strings"

	"homestream/internal/names"
)

// VariousArtists is the album artist of compilations.
const VariousArtists = "Çeşitli Sanatçılar"

// UnknownArtist is shown when a track has no artist at all.
const UnknownArtist = "Bilinmeyen Sanatçı"

func hashID(kind, key string) string {
	h := sha1.Sum([]byte(kind + ":" + key))
	return hex.EncodeToString(h[:8])
}

// Track is an in-memory song.
type Track struct {
	ID       string
	FolderID int64
	RelPath  string // relative to its music folder, '/' separated
	AbsPath  string
	Dir      string // absolute directory
	Size     int64
	MTime    int64
	AddedAt  int64
	DirCover string
	Probed   bool
	Tags

	AlbumID    string
	ArtistID   string
	ArtistName string // display artist ("" → UnknownArtist)
	AlbumRef   *Album

	sortKey string
	fold    string // folded title + artist + album for search
}

// Album groups tracks with the same album name in the same folder.
type Album struct {
	ID       string
	Title    string
	Artist   string
	ArtistID string
	Year     int
	Genre    string
	Dir      string
	Tracks   []*Track
	Duration float64
	AddedAt  int64
	sortKey  string
	fold     string
}

// Artist is a performer with their albums and tracks.
type Artist struct {
	ID      string
	Name    string
	Albums  []*Album
	Tracks  []*Track
	sortKey string
	fold    string
}

// Genre lists the tracks of a genre.
type Genre struct {
	Name   string
	Tracks []*Track
}

// DirNode is a folder in the browse tree.
type DirNode struct {
	Key     string // "<folderId>" or "<folderId>/<rel>"
	Name    string
	Parent  string // "" for folder roots
	Subdirs []*DirNode
	Tracks  []*Track // direct children
	Count   int      // all tracks below
	First   *Track   // a track used for the folder's cover
}

// Snapshot is an immutable view of the music library.
type Snapshot struct {
	Folders    []Folder
	Tracks     map[string]*Track
	All        []*Track // sorted by artist, album, track
	Albums     map[string]*Album
	AlbumList  []*Album // sorted by title
	Artists    map[string]*Artist
	ArtistList []*Artist
	Genres     []*Genre
	Dirs       map[string]*DirNode
	Roots      []*DirNode
}

func primaryArtist(s string) string {
	s = strings.TrimSpace(s)
	for _, sep := range []string{";", " feat. ", " feat ", " ft. ", " Feat. ", " Ft. ", " FEAT. "} {
		if i := strings.Index(s, sep); i > 0 {
			s = strings.TrimSpace(s[:i])
		}
	}
	return s
}

func albumDirOf(dir string) string {
	if _, ok := isDiscDir(filepath.Base(dir)); ok {
		return filepath.Dir(dir)
	}
	return dir
}

func buildSnapshot(folders []Folder, rows []trackRow) *Snapshot {
	s := &Snapshot{
		Folders: folders, Tracks: map[string]*Track{}, Albums: map[string]*Album{}, Artists: map[string]*Artist{},
		Dirs: map[string]*DirNode{},
	}
	fmap := map[int64]Folder{}
	for _, f := range folders {
		fmap[f.ID] = f
	}
	albumArtists := map[string]map[string]int{}
	albumOrder := map[string][]string{}
	artist := func(name string) *Artist {
		key := names.Key(name)
		if key == "" {
			key = names.Key(UnknownArtist)
			name = UnknownArtist
		}
		id := hashID("artist", key)
		a := s.Artists[id]
		if a == nil {
			a = &Artist{ID: id, Name: name, sortKey: names.SortKey(name), fold: names.Fold(name)}
			s.Artists[id] = a
		}
		return a
	}
	for _, r := range rows {
		f, ok := fmap[r.FolderID]
		if !ok || !f.Available {
			continue
		}
		abs := filepath.Join(f.Path, filepath.FromSlash(r.RelPath))
		t := &Track{
			ID: r.ID, FolderID: r.FolderID, RelPath: r.RelPath, AbsPath: abs, Dir: filepath.Dir(abs),
			Size: r.Size, MTime: r.MTime, AddedAt: r.AddedAt, DirCover: r.DirCover, Probed: r.ProbeState == 1,
			Tags: r.Tags,
		}
		if t.Title == "" {
			t.Title = strings.TrimSuffix(path.Base(r.RelPath), path.Ext(r.RelPath))
		}
		t.ArtistName = primaryArtist(t.Artist)
		if t.ArtistName == "" {
			t.ArtistName = primaryArtist(t.AlbumArtist)
		}
		ar := artist(t.ArtistName)
		t.ArtistID = ar.ID
		ar.Tracks = append(ar.Tracks, t)
		if t.ArtistName == "" {
			t.ArtistName = UnknownArtist
		}
		if t.Album != "" {
			adir := albumDirOf(t.Dir)
			t.AlbumID = hashID("album", names.Key(t.Album)+"|"+adir)
			al := s.Albums[t.AlbumID]
			if al == nil {
				al = &Album{ID: t.AlbumID, Title: t.Album, Dir: adir}
				s.Albums[t.AlbumID] = al
				albumArtists[t.AlbumID] = map[string]int{}
			}
			al.Tracks = append(al.Tracks, t)
			al.Duration += t.Duration
			if t.AddedAt > al.AddedAt {
				al.AddedAt = t.AddedAt
			}
			if t.Year > 0 && (al.Year == 0 || t.Year < al.Year) {
				al.Year = t.Year
			}
			if al.Genre == "" {
				al.Genre = t.Genre
			}
			aa := strings.TrimSpace(t.AlbumArtist)
			if aa == "" {
				aa = t.ArtistName
			}
			if _, ok := albumArtists[t.AlbumID][aa]; !ok {
				albumOrder[t.AlbumID] = append(albumOrder[t.AlbumID], aa)
			}
			albumArtists[t.AlbumID][aa]++
			t.Album = al.Title
		}
		t.sortKey = names.SortKey(t.Title)
		t.fold = names.Fold(t.Title + " " + t.Artist + " " + t.AlbumArtist + " " + t.Album)
		s.Tracks[t.ID] = t
		s.All = append(s.All, t)
	}
	// albums: artist, order
	for id, al := range s.Albums {
		counts := albumArtists[id]
		if len(counts) == 1 {
			al.Artist = albumOrder[id][0]
		} else {
			best, bn, total := "", 0, 0
			for _, k := range albumOrder[id] {
				total += counts[k]
				if counts[k] > bn {
					best, bn = k, counts[k]
				}
			}
			if bn*2 > total {
				al.Artist = best
			} else {
				al.Artist = VariousArtists
			}
		}
		if al.Artist != VariousArtists {
			a := artist(primaryArtist(al.Artist))
			al.ArtistID = a.ID
			a.Albums = append(a.Albums, al)
		}
		sort.SliceStable(al.Tracks, func(i, j int) bool { return trackLess(al.Tracks[i], al.Tracks[j]) })
		for _, t := range al.Tracks {
			t.Album = al.Title
			t.albumPtr(al)
		}
		al.sortKey = names.SortKey(al.Title)
		al.fold = names.Fold(al.Title + " " + al.Artist)
		s.AlbumList = append(s.AlbumList, al)
	}
	sort.SliceStable(s.AlbumList, func(i, j int) bool {
		return names.NaturalLessKey(s.AlbumList[i].sortKey, s.AlbumList[j].sortKey)
	})
	for _, a := range s.Artists {
		if len(a.Tracks) == 0 && len(a.Albums) == 0 {
			continue
		}
		sort.SliceStable(a.Albums, func(i, j int) bool {
			if a.Albums[i].Year != a.Albums[j].Year {
				return a.Albums[i].Year > a.Albums[j].Year
			}
			return names.NaturalLessKey(a.Albums[i].sortKey, a.Albums[j].sortKey)
		})
		sort.SliceStable(a.Tracks, func(i, j int) bool { return libraryLess(a.Tracks[i], a.Tracks[j]) })
		s.ArtistList = append(s.ArtistList, a)
	}
	for id, a := range s.Artists {
		if len(a.Tracks) == 0 && len(a.Albums) == 0 {
			delete(s.Artists, id)
		}
	}
	sort.SliceStable(s.ArtistList, func(i, j int) bool {
		return names.NaturalLessKey(s.ArtistList[i].sortKey, s.ArtistList[j].sortKey)
	})
	sort.SliceStable(s.All, func(i, j int) bool { return libraryLess(s.All[i], s.All[j]) })

	// genres
	gmap := map[string]*Genre{}
	for _, t := range s.All {
		if t.Genre == "" {
			continue
		}
		k := names.Key(t.Genre)
		g := gmap[k]
		if g == nil {
			g = &Genre{Name: t.Genre}
			gmap[k] = g
		}
		g.Tracks = append(g.Tracks, t)
	}
	for _, g := range gmap {
		s.Genres = append(s.Genres, g)
	}
	sort.SliceStable(s.Genres, func(i, j int) bool {
		if len(s.Genres[i].Tracks) != len(s.Genres[j].Tracks) {
			return len(s.Genres[i].Tracks) > len(s.Genres[j].Tracks)
		}
		return s.Genres[i].Name < s.Genres[j].Name
	})

	// folder tree
	for _, f := range folders {
		if !f.Available {
			continue
		}
		root := &DirNode{Key: strconv.FormatInt(f.ID, 10), Name: f.Name}
		s.Dirs[root.Key] = root
		s.Roots = append(s.Roots, root)
	}
	var node func(fid int64, rel string) *DirNode
	node = func(fid int64, rel string) *DirNode {
		key := strconv.FormatInt(fid, 10)
		if rel != "" && rel != "." {
			key += "/" + rel
		}
		if n := s.Dirs[key]; n != nil {
			return n
		}
		parentRel := path.Dir(rel)
		if parentRel == "." {
			parentRel = ""
		}
		p := node(fid, parentRel)
		n := &DirNode{Key: key, Name: names.DisplayString(path.Base(rel)), Parent: p.Key}
		s.Dirs[key] = n
		p.Subdirs = append(p.Subdirs, n)
		return n
	}
	for _, t := range s.All {
		if s.Dirs[strconv.FormatInt(t.FolderID, 10)] == nil {
			continue
		}
		d := path.Dir(t.RelPath)
		if d == "." {
			d = ""
		}
		n := node(t.FolderID, d)
		n.Tracks = append(n.Tracks, t)
		for x := n; x != nil; x = s.Dirs[x.Parent] {
			x.Count++
			if x.First == nil {
				x.First = t
			}
			if x.Parent == "" {
				break
			}
		}
	}
	for _, n := range s.Dirs {
		sort.SliceStable(n.Subdirs, func(i, j int) bool { return names.NaturalLess(n.Subdirs[i].Name, n.Subdirs[j].Name) })
		sort.SliceStable(n.Tracks, func(i, j int) bool { return folderLess(n.Tracks[i], n.Tracks[j]) })
	}
	return s
}

func (t *Track) albumPtr(a *Album) { t.AlbumRef = a }

// trackLess orders tracks inside an album.
func trackLess(a, b *Track) bool {
	if a.DiscNo != b.DiscNo {
		return a.DiscNo < b.DiscNo
	}
	if a.TrackNo != b.TrackNo {
		if a.TrackNo == 0 || b.TrackNo == 0 {
			return b.TrackNo == 0
		}
		return a.TrackNo < b.TrackNo
	}
	return names.NaturalLess(a.RelPath, b.RelPath)
}

// folderLess orders tracks inside a folder (as the files are named).
func folderLess(a, b *Track) bool {
	if a.Dir == b.Dir && a.AlbumID != "" && a.AlbumID == b.AlbumID && (a.TrackNo > 0 || b.TrackNo > 0) {
		return trackLess(a, b)
	}
	return names.NaturalLess(path.Base(a.RelPath), path.Base(b.RelPath))
}

// libraryLess orders all songs: by title.
func libraryLess(a, b *Track) bool {
	if a.sortKey != b.sortKey {
		return names.NaturalLessKey(a.sortKey, b.sortKey)
	}
	return a.ID < b.ID
}
