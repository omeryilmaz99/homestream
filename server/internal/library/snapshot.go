package library

import (
	"crypto/sha1"
	"encoding/hex"
	"encoding/json"
	"path"
	"path/filepath"
	"sort"
	"strings"

	"homestream/internal/names"
	"homestream/internal/store"
)

// MediaInfo is the ffprobe result stored per file.
type MediaInfo struct {
	Container  string       `json:"container"`
	VideoCodec string       `json:"videoCodec"`
	Width      int          `json:"width"`
	Height     int          `json:"height"`
	HDR        bool         `json:"hdr"`
	Bitrate    int64        `json:"bitrate"`
	Audio      []AudioTrack `json:"audio"`
	Subtitles  []SubTrack   `json:"subtitles"`
}

type AudioTrack struct {
	Index    int    `json:"index"`
	Codec    string `json:"codec"`
	Language string `json:"language"`
	Channels int    `json:"channels"`
	Title    string `json:"title"`
	Default  bool   `json:"default"`
}

type SubTrack struct {
	Index    int    `json:"index"`
	Codec    string `json:"codec"`
	Language string `json:"language"`
	Title    string `json:"title"`
	Forced   bool   `json:"forced"`
	Default  bool   `json:"default"`
}

// ExtSub is an external subtitle file.
type ExtSub struct {
	ID       string `json:"id"`
	Path     string `json:"path"` // absolute; never sent to clients
	Language string `json:"language"`
	Title    string `json:"title"`
	Format   string `json:"format"`
	Forced   bool   `json:"forced"`
}

// Item is an in-memory library entry (movie, series or episode).
type Item struct {
	ID       string
	Type     string
	Title    string
	SortKey  string
	Year     int
	Overview string
	Genres   []string
	Rating   float64
	Duration float64
	AddedAt  int64

	// movie / episode
	FolderID   int64
	FolderName string
	RelPath    string
	AbsPath    string
	FileName   string
	Size       int64
	MTime      int64
	Media      *MediaInfo
	Subs       []ExtSub

	// episode
	SeriesID string
	Series   *Item
	Season   int
	Episode  int

	// series
	Episodes   []*Item
	SeasonNums []int
	Dir        string

	LocalPoster, LocalBackdrop string
	TMDBPoster, TMDBBackdrop   string
	TMDBID                     int
	OriginalTitle              string

	Search string // folded searchable text

	ParsedTitle string // title from the file name (before TMDB)
	ParsedYear  int
}

// RealPoster reports whether a non-generated poster exists.
func (it *Item) RealPoster() bool {
	if it.Type == "episode" && it.Series != nil {
		return it.Series.RealPoster()
	}
	return it.LocalPoster != "" || it.TMDBPoster != ""
}

// RealBackdrop reports whether a non-generated backdrop exists.
func (it *Item) RealBackdrop() bool { return it.LocalBackdrop != "" || it.TMDBBackdrop != "" }

// FirstEpisode returns the first episode of a series (or nil).
func (it *Item) FirstEpisode() *Item {
	if len(it.Episodes) == 0 {
		return nil
	}
	return it.Episodes[0]
}

// FolderInfo is a library folder with counters.
type FolderInfo struct {
	store.Folder
	ItemCount int
}

// Snapshot is an immutable view of the visible library.
type Snapshot struct {
	Items    map[string]*Item
	Movies   []*Item
	Series   []*Item
	Episodes []*Item
	Subs     map[string]*ExtSub
	ByPath   map[string]*Item
	Folders  []FolderInfo
	Genres   []string
}

// HashID returns the stable 16-hex id used for items/subtitles.
func HashID(kind, key string) string {
	h := sha1.Sum([]byte(kind + ":" + key))
	return hex.EncodeToString(h[:])[:16]
}

// SeasonOrder sorts specials (season 0) after regular seasons.
func SeasonOrder(s int) int {
	if s == 0 {
		return 1 << 20
	}
	return s
}

// EpisodeLess orders episodes in watch order.
func EpisodeLess(a, b *Item) bool {
	if SeasonOrder(a.Season) != SeasonOrder(b.Season) {
		return SeasonOrder(a.Season) < SeasonOrder(b.Season)
	}
	if a.Episode != b.Episode {
		// unnumbered (0) episodes after numbered ones
		if a.Episode == 0 || b.Episode == 0 {
			return b.Episode == 0
		}
		return a.Episode < b.Episode
	}
	return names.NaturalLess(a.FileName, b.FileName)
}

func parseGenres(s string) []string {
	var g []string
	if s != "" {
		_ = json.Unmarshal([]byte(s), &g)
	}
	if g == nil {
		g = []string{}
	}
	return g
}

func buildSnapshot(folders []store.Folder, files []store.FileRow, series []store.SeriesRow, meta map[string]store.MetaRow) *Snapshot {
	s := &Snapshot{
		Items:  map[string]*Item{},
		Subs:   map[string]*ExtSub{},
		ByPath: map[string]*Item{},
	}
	fmap := map[int64]store.Folder{}
	counts := map[int64]int{}
	for _, f := range folders {
		fmap[f.ID] = f
	}
	seriesItems := map[string]*Item{}
	for _, r := range series {
		it := &Item{ID: r.ID, Type: "series", Title: r.Title, Year: r.Year, Dir: r.Dir,
			LocalPoster: r.LocalPoster, LocalBackdrop: r.LocalBackdrop, Genres: []string{},
			ParsedTitle: r.Title, ParsedYear: r.Year}
		if m, ok := meta[r.ID]; ok && m.Status == "ok" {
			applyMeta(it, m)
		}
		seriesItems[r.ID] = it
	}
	for _, r := range files {
		f, ok := fmap[r.FolderID]
		if !ok {
			continue
		}
		counts[r.FolderID]++
		if !f.Available {
			continue
		}
		abs := filepath.Join(f.Path, filepath.FromSlash(r.RelPath))
		it := &Item{
			ID: r.ID, Type: r.Type, Title: r.Title, Year: r.Year, Duration: r.Duration, AddedAt: r.AddedAt,
			FolderID: r.FolderID, FolderName: f.Name, RelPath: r.RelPath, AbsPath: abs,
			FileName: path.Base(r.RelPath), Size: r.Size, MTime: r.MTime,
			Season: r.Season, Episode: r.Episode, SeriesID: r.SeriesID,
			LocalPoster: r.LocalPoster, LocalBackdrop: r.LocalBackdrop, Genres: []string{},
			ParsedTitle: r.Title, ParsedYear: r.Year,
		}
		if r.Media != "" {
			var mi MediaInfo
			if json.Unmarshal([]byte(r.Media), &mi) == nil {
				it.Media = &mi
			}
		}
		if r.Subs != "" {
			_ = json.Unmarshal([]byte(r.Subs), &it.Subs)
		}
		if m, ok := meta[r.ID]; ok && m.Status == "ok" {
			applyMeta(it, m)
		}
		if it.Type == "episode" {
			ser := seriesItems[r.SeriesID]
			if ser == nil {
				continue
			}
			it.Series = ser
			ser.Episodes = append(ser.Episodes, it)
			if it.Title == "" {
				if it.Episode > 0 {
					it.Title = "Bölüm " + itoa(it.Episode)
				} else {
					it.Title = names.DisplayString(strings.TrimSuffix(it.FileName, path.Ext(it.FileName)))
				}
			}
			s.Episodes = append(s.Episodes, it)
		} else {
			s.Movies = append(s.Movies, it)
		}
		if it.Title == "" {
			it.Title = names.DisplayString(it.FileName)
		}
		s.Items[it.ID] = it
		s.ByPath[abs] = it
		for i := range it.Subs {
			s.Subs[it.Subs[i].ID] = &it.Subs[i]
		}
	}
	for _, ser := range seriesItems {
		if len(ser.Episodes) == 0 {
			continue
		}
		sort.SliceStable(ser.Episodes, func(i, j int) bool { return EpisodeLess(ser.Episodes[i], ser.Episodes[j]) })
		seen := map[int]bool{}
		for _, e := range ser.Episodes {
			if e.AddedAt > ser.AddedAt {
				ser.AddedAt = e.AddedAt
			}
			if !seen[e.Season] {
				seen[e.Season] = true
				ser.SeasonNums = append(ser.SeasonNums, e.Season)
			}
			e.Genres = ser.Genres
			if e.Year == 0 {
				e.Year = ser.Year
			}
		}
		s.Series = append(s.Series, ser)
		s.Items[ser.ID] = ser
	}
	genreSet := map[string]bool{}
	for _, it := range s.Items {
		it.SortKey = names.SortKey(it.Title)
		parts := []string{it.Title, it.OriginalTitle}
		if it.Type == "episode" {
			parts = append(parts, it.Series.Title, it.Series.OriginalTitle, it.FileName)
		} else if it.Type == "movie" {
			parts = append(parts, it.FileName)
		}
		it.Search = names.Fold(strings.Join(parts, " "))
		if it.Type != "episode" {
			for _, g := range it.Genres {
				genreSet[g] = true
			}
		}
	}
	sortByTitle(s.Movies)
	sortByTitle(s.Series)
	for g := range genreSet {
		s.Genres = append(s.Genres, g)
	}
	sort.Slice(s.Genres, func(i, j int) bool { return names.NaturalLess(s.Genres[i], s.Genres[j]) })
	if s.Genres == nil {
		s.Genres = []string{}
	}
	for _, f := range folders {
		s.Folders = append(s.Folders, FolderInfo{Folder: f, ItemCount: counts[f.ID]})
	}
	return s
}

func sortByTitle(items []*Item) {
	sort.SliceStable(items, func(i, j int) bool {
		c := names.NaturalCompareKeys(items[i].SortKey, items[j].SortKey)
		if c != 0 {
			return c < 0
		}
		return items[i].Year < items[j].Year
	})
}

func applyMeta(it *Item, m store.MetaRow) {
	if m.Title != "" {
		it.Title = m.Title
	}
	it.OriginalTitle = m.OriginalTitle
	if m.Overview != "" {
		it.Overview = m.Overview
	}
	if g := parseGenres(m.Genres); len(g) > 0 {
		it.Genres = g
	}
	it.Rating = m.Rating
	if m.Year > 0 && it.Type != "episode" {
		it.Year = m.Year
	}
	it.TMDBID = m.TMDBID
	it.TMDBPoster = m.Poster
	it.TMDBBackdrop = m.Backdrop
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	neg := n < 0
	if neg {
		n = -n
	}
	var b [20]byte
	i := len(b)
	for n > 0 {
		i--
		b[i] = byte('0' + n%10)
		n /= 10
	}
	if neg {
		i--
		b[i] = '-'
	}
	return string(b[i:])
}
