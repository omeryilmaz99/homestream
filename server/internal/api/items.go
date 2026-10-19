package api

import (
	"path"
	"strings"

	"homestream/internal/library"
	"homestream/internal/names"
	"homestream/internal/store"
)

// ItemJSON is the summary form of an item.
type ItemJSON struct {
	ID              string         `json:"id"`
	Type            string         `json:"type"`
	Title           string         `json:"title"`
	Year            int            `json:"year"`
	Overview        string         `json:"overview"`
	Genres          []string       `json:"genres"`
	Rating          float64        `json:"rating"`
	Duration        float64        `json:"duration"`
	Poster          string         `json:"poster"`
	Backdrop        string         `json:"backdrop"`
	Thumb           string         `json:"thumb"`
	PosterGenerated bool           `json:"posterGenerated"`
	AddedAt         int64          `json:"addedAt"`
	SeriesID        string         `json:"seriesId,omitempty"`
	SeriesTitle     string         `json:"seriesTitle,omitempty"`
	Season          *int           `json:"season,omitempty"`
	Episode         *int           `json:"episode,omitempty"`
	EpisodeCount    *int           `json:"episodeCount,omitempty"`
	SeasonCount     *int           `json:"seasonCount,omitempty"`
	UnwatchedCount  *int           `json:"unwatchedCount,omitempty"`
	UserData        store.UserData `json:"userData"`
}

// MediaFileJSON describes the playable file.
type MediaFileJSON struct {
	Path              string               `json:"path"`
	FileName          string               `json:"fileName"`
	Size              int64                `json:"size"`
	Container         string               `json:"container"`
	VideoCodec        string               `json:"videoCodec"`
	Width             int                  `json:"width"`
	Height            int                  `json:"height"`
	HDR               bool                 `json:"hdr"`
	Bitrate           int64                `json:"bitrate"`
	Audio             []library.AudioTrack `json:"audio"`
	Subtitles         []library.SubTrack   `json:"subtitles"`
	ExternalSubtitles []ExtSubJSON         `json:"externalSubtitles"`
	StreamURL         string               `json:"streamUrl"`
}

// ExtSubJSON is an external subtitle reference.
type ExtSubJSON struct {
	ID       string `json:"id"`
	Language string `json:"language"`
	Title    string `json:"title"`
	Format   string `json:"format"`
	Forced   bool   `json:"forced"`
	URL      string `json:"url"`
}

type seasonJSON struct {
	Number   int        `json:"number"`
	Title    string     `json:"title"`
	Episodes []ItemJSON `json:"episodes"`
}

type seriesDetailJSON struct {
	ItemJSON
	Seasons []seasonJSON `json:"seasons"`
	NextUp  *ItemJSON    `json:"nextUp"`
}

type fileDetailJSON struct {
	ItemJSON
	File MediaFileJSON `json:"file"`
}

// view converts snapshot items for one request/profile.
type view struct {
	s       *Server
	snap    *library.Snapshot
	profile string
	ud      map[string]store.UserData
}

func (s *Server) newView(profile string) *view {
	ud, _ := s.St.UserDataMap(profile)
	return &view{s: s, snap: s.Lib.Snap(), profile: profile, ud: ud}
}

func intp(n int) *int { return &n }

// userData returns the profile's user data (aggregated for series).
func (v *view) userData(it *library.Item) store.UserData {
	if it.Type != "series" {
		return v.ud[it.ID]
	}
	u := store.UserData{Liked: v.ud[it.ID].Liked}
	allPlayed := len(it.Episodes) > 0
	minCount := -1
	for _, e := range it.Episodes {
		eu := v.ud[e.ID]
		if !eu.Played {
			allPlayed = false
		}
		if eu.LastPlayedAt > u.LastPlayedAt {
			u.LastPlayedAt = eu.LastPlayedAt
		}
		if minCount < 0 || eu.PlayCount < minCount {
			minCount = eu.PlayCount
		}
	}
	u.Played = allPlayed
	if allPlayed && minCount > 0 {
		u.PlayCount = minCount
	}
	return u
}

func (v *view) unwatched(it *library.Item) int {
	n := 0
	for _, e := range it.Episodes {
		if !v.ud[e.ID].Played {
			n++
		}
	}
	return n
}

func imageURL(id, kind, ver string) string {
	return "/api/images/" + id + "/" + kind + "?v=" + ver
}

func (v *view) item(it *library.Item) ItemJSON {
	im := v.s.Lib.Images
	j := ItemJSON{
		ID: it.ID, Type: it.Type, Title: it.Title, Year: it.Year, Overview: it.Overview, Genres: it.Genres,
		Rating: it.Rating, Duration: it.Duration, AddedAt: it.AddedAt,
		Poster:          imageURL(it.ID, "poster", im.Version(it, "poster")),
		Backdrop:        imageURL(it.ID, "backdrop", im.Version(it, "backdrop")),
		Thumb:           imageURL(it.ID, "thumb", im.Version(it, "thumb")),
		PosterGenerated: !it.RealPoster(),
		UserData:        v.userData(it),
	}
	if j.Genres == nil {
		j.Genres = []string{}
	}
	switch it.Type {
	case "episode":
		j.SeriesID = it.SeriesID
		if it.Series != nil {
			j.SeriesTitle = it.Series.Title
		}
		j.Season, j.Episode = intp(it.Season), intp(it.Episode)
	case "series":
		j.EpisodeCount = intp(len(it.Episodes))
		j.SeasonCount = intp(len(it.SeasonNums))
		j.UnwatchedCount = intp(v.unwatched(it))
		j.Duration = 0
	}
	return j
}

func (v *view) items(list []*library.Item) []ItemJSON {
	out := make([]ItemJSON, 0, len(list))
	for _, it := range list {
		out = append(out, v.item(it))
	}
	return out
}

func (v *view) itemPtr(it *library.Item) *ItemJSON {
	if it == nil {
		return nil
	}
	j := v.item(it)
	return &j
}

func containerFromExt(name string) string {
	switch strings.ToLower(path.Ext(name)) {
	case ".mkv":
		return "matroska"
	case ".webm":
		return "webm"
	case ".mp4", ".m4v":
		return "mp4"
	case ".mov":
		return "mov"
	case ".avi", ".divx":
		return "avi"
	case ".ts", ".m2ts", ".mts":
		return "mpegts"
	case ".wmv":
		return "asf"
	case ".mpg", ".mpeg", ".vob":
		return "mpeg"
	}
	return strings.TrimPrefix(strings.ToLower(path.Ext(name)), ".")
}

func (v *view) mediaFile(it *library.Item) MediaFileJSON {
	m := MediaFileJSON{
		Path:     names.DisplayString(it.FolderName + "/" + it.RelPath),
		FileName: names.DisplayString(it.FileName),
		Size:     it.Size, StreamURL: "/api/stream/" + it.ID,
		Audio: []library.AudioTrack{}, Subtitles: []library.SubTrack{}, ExternalSubtitles: []ExtSubJSON{},
		Container: containerFromExt(it.FileName),
	}
	if mi := it.Media; mi != nil {
		m.Container, m.VideoCodec, m.Width, m.Height, m.HDR, m.Bitrate = mi.Container, mi.VideoCodec, mi.Width, mi.Height, mi.HDR, mi.Bitrate
		if mi.Audio != nil {
			m.Audio = mi.Audio
		}
		if mi.Subtitles != nil {
			m.Subtitles = mi.Subtitles
		}
	}
	for _, s := range it.Subs {
		m.ExternalSubtitles = append(m.ExternalSubtitles, ExtSubJSON{
			ID: s.ID, Language: s.Language, Title: s.Title, Format: s.Format, Forced: s.Forced,
			URL: "/api/subtitles/" + s.ID,
		})
	}
	return m
}

func seasonTitle(n int) string {
	if n == 0 {
		return "Özel Bölümler"
	}
	return itoa(n) + ". Sezon"
}

func itoa(n int) string {
	if n < 0 {
		return "-" + itoa(-n)
	}
	if n < 10 {
		return string(rune('0' + n))
	}
	return itoa(n/10) + string(rune('0'+n%10))
}

// detail returns the detail form of an item.
func (v *view) detail(it *library.Item) any {
	switch it.Type {
	case "series":
		d := seriesDetailJSON{ItemJSON: v.item(it), Seasons: []seasonJSON{}}
		idx := map[int]int{}
		for _, e := range it.Episodes {
			i, ok := idx[e.Season]
			if !ok {
				i = len(d.Seasons)
				idx[e.Season] = i
				d.Seasons = append(d.Seasons, seasonJSON{Number: e.Season, Title: seasonTitle(e.Season), Episodes: []ItemJSON{}})
			}
			d.Seasons[i].Episodes = append(d.Seasons[i].Episodes, v.item(e))
		}
		d.NextUp = v.itemPtr(v.nextUp(it, false))
		return d
	default:
		return fileDetailJSON{ItemJSON: v.item(it), File: v.mediaFile(it)}
	}
}

// nextUp picks the episode to play: first in-progress, else first unplayed
// after the most recently played one, else (unless strict) the first episode.
// With strict=true, nil is returned when nothing sensible follows.
func (v *view) nextUp(ser *library.Item, strict bool) *library.Item {
	eps := ser.Episodes
	if len(eps) == 0 {
		return nil
	}
	for _, e := range eps {
		u := v.ud[e.ID]
		if u.Position > 0 && !u.Played {
			return e
		}
	}
	lastIdx, lastAt := -1, int64(0)
	for i, e := range eps {
		u := v.ud[e.ID]
		if u.Played && u.LastPlayedAt >= lastAt {
			lastIdx, lastAt = i, u.LastPlayedAt
		}
	}
	if lastIdx >= 0 {
		for _, e := range eps[lastIdx+1:] {
			if !v.ud[e.ID].Played {
				return e
			}
		}
		if strict {
			return nil
		}
		for _, e := range eps {
			if !v.ud[e.ID].Played {
				return e
			}
		}
	} else if strict {
		return nil
	}
	return eps[0]
}
