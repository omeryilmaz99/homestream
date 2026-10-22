package api

import (
	"bytes"
	"compress/gzip"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"errors"
	"hash/fnv"
	"log"
	"math/rand"
	"net/http"
	"os"
	"path"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"

	"homestream/internal/music"
	"homestream/internal/names"
)

// adminPasswordHash is the SHA-256 of the settings password (the same one
// the apps use for their settings lock). Server-wide music settings need it.
const adminPasswordHash = "2e5bac908bd740b5ddded3371ed1975f89e06d550f0db2c8e0fd9b10ac9218e8"

func (s *Server) musicRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/music/info", s.mInfo)
	mux.HandleFunc("GET /api/music/home", s.mHome)
	mux.HandleFunc("GET /api/music/tracks", s.mTracks)
	mux.HandleFunc("POST /api/music/tracks/batch", s.mTracksBatch)
	mux.HandleFunc("POST /api/music/tracks/{id}/played", s.mPlayed)
	mux.HandleFunc("GET /api/music/albums", s.mAlbums)
	mux.HandleFunc("GET /api/music/albums/{id}", s.mAlbum)
	mux.HandleFunc("GET /api/music/artists", s.mArtists)
	mux.HandleFunc("GET /api/music/artists/{id}", s.mArtist)
	mux.HandleFunc("GET /api/music/genres", s.mGenres)
	mux.HandleFunc("GET /api/music/search", s.mSearch)
	mux.HandleFunc("GET /api/music/browse", s.mBrowse)
	mux.HandleFunc("GET /api/music/liked", s.mLiked)
	mux.HandleFunc("POST /api/music/like", s.mLike)
	mux.HandleFunc("GET /api/music/playlists", s.mPlaylists)
	mux.HandleFunc("POST /api/music/playlists", s.mCreatePlaylist)
	mux.HandleFunc("GET /api/music/playlists/{id}", s.mPlaylist)
	mux.HandleFunc("PUT /api/music/playlists/{id}", s.mRenamePlaylist)
	mux.HandleFunc("DELETE /api/music/playlists/{id}", s.mDeletePlaylist)
	mux.HandleFunc("PUT /api/music/playlists/{id}/tracks", s.mSetPlaylistTracks)
	mux.HandleFunc("POST /api/music/playlists/{id}/tracks", s.mAddPlaylistTracks)
	mux.HandleFunc("GET /api/music/stream/{id}", s.mStream)
	mux.HandleFunc("GET /api/music/covers/{id}", s.mCover)
	mux.HandleFunc("GET /api/music/settings", s.mGetSettings)
	mux.HandleFunc("PUT /api/music/settings", s.mPutSettings)
	mux.HandleFunc("POST /api/music/folders", s.mAddFolder)
	mux.HandleFunc("DELETE /api/music/folders/{id}", s.mDeleteFolder)
	mux.HandleFunc("POST /api/music/admin/check", s.mAdminCheck)
	mux.HandleFunc("POST /api/music/scan", s.mScan)
	mux.HandleFunc("GET /api/music/scan/status", s.mScanStatus)
}

// writeJSONz writes JSON, gzip-compressed when it is large and the client accepts it.
func writeJSONz(w http.ResponseWriter, r *http.Request, status int, v any) {
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(v); err != nil {
		writeError(w, http.StatusInternalServerError, "Sunucu hatası")
		return
	}
	h := w.Header()
	h.Set("Content-Type", "application/json; charset=utf-8")
	h.Set("Cache-Control", "no-store")
	h.Add("Vary", "Accept-Encoding")
	if buf.Len() > 4096 && strings.Contains(r.Header.Get("Accept-Encoding"), "gzip") {
		h.Set("Content-Encoding", "gzip")
		w.WriteHeader(status)
		gz, _ := gzip.NewWriterLevel(w, gzip.BestSpeed)
		_, _ = gz.Write(buf.Bytes())
		_ = gz.Close()
		return
	}
	w.WriteHeader(status)
	_, _ = w.Write(buf.Bytes())
}

// requireAdmin checks the settings password (header X-Admin-Password).
func requireAdmin(w http.ResponseWriter, r *http.Request) bool {
	pw := strings.TrimSpace(r.Header.Get("X-Admin-Password"))
	sum := sha256.Sum256([]byte(pw))
	if pw != "" && subtle.ConstantTimeCompare([]byte(hex.EncodeToString(sum[:])), []byte(adminPasswordHash)) == 1 {
		return true
	}
	writeError(w, http.StatusForbidden, "Bu ayar için şifre gerekli (şifre yanlış)")
	return false
}

// ---------- JSON shapes ----------

type mTrackJSON struct {
	ID           string  `json:"id"`
	Title        string  `json:"title"`
	Artist       string  `json:"artist"`
	ArtistID     string  `json:"artistId"`
	Album        string  `json:"album"`
	AlbumID      string  `json:"albumId"`
	AlbumArtist  string  `json:"albumArtist"`
	TrackNo      int     `json:"trackNo"`
	DiscNo       int     `json:"discNo"`
	Year         int     `json:"year"`
	Genre        string  `json:"genre"`
	Duration     float64 `json:"duration"`
	Cover        string  `json:"cover"`
	CoverID      string  `json:"coverId"`
	IsVideo      bool    `json:"isVideo"`
	Codec        string  `json:"codec"`
	Bitrate      int64   `json:"bitrate"`
	SampleRate   int     `json:"sampleRate"`
	BitDepth     int     `json:"bitDepth"`
	Channels     int     `json:"channels"`
	Lossless     bool    `json:"lossless"`
	Size         int64   `json:"size"`
	Ext          string  `json:"ext"`
	Path         string  `json:"path"`
	Dir          string  `json:"dir"` // folder key for /api/music/browse
	AddedAt      int64   `json:"addedAt"`
	Liked        bool    `json:"liked"`
	PlayCount    int     `json:"playCount"`
	LastPlayedAt int64   `json:"lastPlayedAt"`
}

type mAlbumJSON struct {
	ID         string  `json:"id"`
	Title      string  `json:"title"`
	Artist     string  `json:"artist"`
	ArtistID   string  `json:"artistId"`
	Year       int     `json:"year"`
	Genre      string  `json:"genre"`
	TrackCount int     `json:"trackCount"`
	Duration   float64 `json:"duration"`
	Cover      string  `json:"cover"`
	AddedAt    int64   `json:"addedAt"`
}

type mArtistJSON struct {
	ID         string `json:"id"`
	Name       string `json:"name"`
	AlbumCount int    `json:"albumCount"`
	TrackCount int    `json:"trackCount"`
	Cover      string `json:"cover"`
}

type mPlaylistJSON struct {
	ID           string       `json:"id"`
	Name         string       `json:"name"`
	TrackCount   int          `json:"trackCount"`
	Duration     float64      `json:"duration"`
	Covers       []string     `json:"covers"`
	CreatedAt    int64        `json:"createdAt"`
	UpdatedAt    int64        `json:"updatedAt"`
	MissingCount int          `json:"missingCount"`
	Tracks       []mTrackJSON `json:"tracks,omitempty"`
	TrackIDs     []string     `json:"trackIds"`
}

// mCard is a home screen tile.
type mCard struct {
	Type     string      `json:"type"` // album | artist | playlist | track | liked
	ID       string      `json:"id"`
	Title    string      `json:"title"`
	Subtitle string      `json:"subtitle"`
	Cover    string      `json:"cover"`
	Covers   []string    `json:"covers,omitempty"`
	Track    *mTrackJSON `json:"track,omitempty"`
}

type mView struct {
	s    *Server
	snap *music.Snapshot
	ud   music.UserData
	pid  string
}

func (s *Server) mView(r *http.Request) *mView {
	pid := s.profileID(r)
	return &mView{s: s, snap: s.Music.Snap(), ud: s.Music.LoadUserData(pid), pid: pid}
}

func (v *mView) cover(id string) string { return v.s.Music.Covers.URL(v.snap, id) }

func lossless(codec string) bool {
	switch codec {
	case "flac", "alac", "ape", "wavpack", "tta", "truehd", "mlp", "tak":
		return true
	}
	return strings.HasPrefix(codec, "pcm_") || strings.HasPrefix(codec, "dsd_")
}

func (v *mView) track(t *music.Track) mTrackJSON {
	owner := v.s.Music.Covers.CoverOwner(t)
	p := v.ud.Plays[t.ID]
	_, liked := v.ud.Likes[t.ID]
	ext := strings.ToLower(filepath.Ext(t.AbsPath))
	if t.IsVideo {
		ext = ".mka"
	}
	aa := ""
	if t.AlbumRef != nil {
		aa = t.AlbumRef.Artist
	}
	return mTrackJSON{
		ID: t.ID, Title: t.Title, Artist: t.ArtistName, ArtistID: t.ArtistID, Album: t.Tags.Album, AlbumID: t.AlbumID,
		AlbumArtist: aa, TrackNo: t.TrackNo, DiscNo: t.DiscNo, Year: t.Year, Genre: t.Genre, Duration: t.Duration,
		Cover: v.cover(owner), CoverID: owner, IsVideo: t.IsVideo, Codec: t.Codec, Bitrate: t.Bitrate,
		SampleRate: t.SampleRate, BitDepth: t.BitDepth, Channels: t.Channels, Lossless: lossless(t.Codec),
		Size: t.Size, Ext: ext, Path: names.DisplayString(filepath.Base(t.AbsPath)), Dir: dirKey(t), AddedAt: t.AddedAt,
		Liked: liked, PlayCount: p.Count, LastPlayedAt: p.Last,
	}
}

// dirKey is the browse key of the folder a song is in.
func dirKey(t *music.Track) string {
	key := strconv.FormatInt(t.FolderID, 10)
	if d := path.Dir(t.RelPath); d != "." && d != "" {
		key += "/" + d
	}
	return key
}

func (v *mView) tracks(ts []*music.Track) []mTrackJSON {
	out := make([]mTrackJSON, 0, len(ts))
	for _, t := range ts {
		out = append(out, v.track(t))
	}
	return out
}

func (v *mView) album(a *music.Album) mAlbumJSON {
	return mAlbumJSON{ID: a.ID, Title: a.Title, Artist: a.Artist, ArtistID: a.ArtistID, Year: a.Year, Genre: a.Genre,
		TrackCount: len(a.Tracks), Duration: a.Duration, Cover: v.cover(a.ID), AddedAt: a.AddedAt}
}

func (v *mView) albums(as []*music.Album) []mAlbumJSON {
	out := make([]mAlbumJSON, 0, len(as))
	for _, a := range as {
		out = append(out, v.album(a))
	}
	return out
}

func (v *mView) artist(a *music.Artist) mArtistJSON {
	return mArtistJSON{ID: a.ID, Name: a.Name, AlbumCount: len(a.Albums), TrackCount: len(a.Tracks), Cover: v.cover(a.ID)}
}

func (v *mView) playlist(p music.Playlist, withTracks bool) mPlaylistJSON {
	out := mPlaylistJSON{ID: p.ID, Name: p.Name, CreatedAt: p.CreatedAt, UpdatedAt: p.UpdatedAt, Covers: []string{}, TrackIDs: []string{}}
	seenCover := map[string]bool{}
	for _, id := range p.TrackIDs {
		t := v.snap.Tracks[id]
		if t == nil {
			out.MissingCount++
			continue
		}
		out.TrackIDs = append(out.TrackIDs, id)
		out.TrackCount++
		out.Duration += t.Duration
		if owner := v.s.Music.Covers.CoverOwner(t); len(out.Covers) < 4 && !seenCover[owner] {
			seenCover[owner] = true
			out.Covers = append(out.Covers, v.cover(owner))
		}
		if withTracks {
			out.Tracks = append(out.Tracks, v.track(t))
		}
	}
	if withTracks && out.Tracks == nil {
		out.Tracks = []mTrackJSON{}
	}
	return out
}

func (v *mView) trackCard(t *music.Track) mCard {
	tj := v.track(t)
	return mCard{Type: "track", ID: t.ID, Title: t.Title, Subtitle: t.ArtistName, Cover: tj.Cover, Track: &tj}
}

func (v *mView) albumCard(a *music.Album) mCard {
	sub := a.Artist
	if a.Year > 0 {
		sub += " • " + strconv.Itoa(a.Year)
	}
	return mCard{Type: "album", ID: a.ID, Title: a.Title, Subtitle: sub, Cover: v.cover(a.ID)}
}

func (v *mView) artistCard(a *music.Artist) mCard {
	return mCard{Type: "artist", ID: a.ID, Title: a.Name, Subtitle: "Sanatçı", Cover: v.cover(a.ID)}
}

// ---------- handlers ----------

func (s *Server) mInfo(w http.ResponseWriter, r *http.Request) {
	snap := s.Music.Snap()
	st := s.Music.Status()
	writeJSON(w, http.StatusOK, map[string]any{
		"app": "homestream", "id": s.ServerID, "name": s.ServerName(), "version": s.Version,
		"trackCount": len(snap.Tracks), "albumCount": len(snap.Albums), "artistCount": len(snap.Artists),
		"scanning": st.Running, "music": true,
	})
}

func daySeed(extra string) int64 {
	h := fnv.New64a()
	_, _ = h.Write([]byte(time.Now().Format("2006-01-02") + extra))
	return int64(h.Sum64() >> 1)
}

func (s *Server) mHome(w http.ResponseWriter, r *http.Request) {
	v := s.mView(r)
	snap := v.snap
	type row struct {
		ID    string  `json:"id"`
		Title string  `json:"title"`
		Style string  `json:"style"` // square | round | wide
		Items []mCard `json:"items"`
	}
	var rows []row

	// recently played: albums (or single tracks), newest first
	type played struct {
		t    *music.Track
		last int64
	}
	var plays []played
	for id, p := range v.ud.Plays {
		if t := snap.Tracks[id]; t != nil {
			plays = append(plays, played{t, p.Last})
		}
	}
	sort.Slice(plays, func(i, j int) bool { return plays[i].last > plays[j].last })
	var recent []mCard
	seen := map[string]bool{}
	for _, p := range plays {
		if len(recent) >= 12 {
			break
		}
		if a := p.t.AlbumRef; a != nil && len(a.Tracks) > 1 {
			if !seen[a.ID] {
				seen[a.ID] = true
				recent = append(recent, v.albumCard(a))
			}
			continue
		}
		if !seen[p.t.ID] {
			seen[p.t.ID] = true
			recent = append(recent, v.trackCard(p.t))
		}
	}

	// quick tiles: liked songs, recent playlists, recent albums
	var quick []mCard
	if len(v.ud.Likes) > 0 {
		n := 0
		for id := range v.ud.Likes {
			if snap.Tracks[id] != nil {
				n++
			}
		}
		if n > 0 {
			quick = append(quick, mCard{Type: "liked", ID: "liked", Title: "Beğenilen Şarkılar", Subtitle: strconv.Itoa(n) + " şarkı"})
		}
	}
	if v.pid != "" {
		if pls, err := s.Music.Playlists(v.pid); err == nil {
			for _, p := range pls {
				if len(quick) >= 3 {
					break
				}
				pj := v.playlist(p, false)
				quick = append(quick, mCard{Type: "playlist", ID: p.ID, Title: p.Name, Subtitle: strconv.Itoa(pj.TrackCount) + " şarkı", Covers: pj.Covers})
			}
		}
	}
	for _, c := range recent {
		if len(quick) >= 6 {
			break
		}
		quick = append(quick, c)
	}
	if len(quick) < 6 {
		rnd := rand.New(rand.NewSource(daySeed("quick" + v.pid)))
		perm := rnd.Perm(len(snap.AlbumList))
		for _, i := range perm {
			if len(quick) >= 6 {
				break
			}
			a := snap.AlbumList[i]
			if !seen[a.ID] {
				seen[a.ID] = true
				quick = append(quick, v.albumCard(a))
			}
		}
	}
	if len(recent) > 0 {
		rows = append(rows, row{"recent", "Son Çalınanlar", "round", recent})
	}

	// mix: albums from the genres and artists the profile listens to
	genreScore := map[string]float64{}
	artistScore := map[string]float64{}
	for id, p := range v.ud.Plays {
		if t := snap.Tracks[id]; t != nil {
			genreScore[names.Key(t.Genre)] += float64(p.Count)
			artistScore[t.ArtistID] += float64(p.Count)
		}
	}
	for id := range v.ud.Likes {
		if t := snap.Tracks[id]; t != nil {
			genreScore[names.Key(t.Genre)] += 3
			artistScore[t.ArtistID] += 3
		}
	}
	rnd := rand.New(rand.NewSource(daySeed("mix" + v.pid)))
	type scored struct {
		a *music.Album
		s float64
	}
	var sc []scored
	for _, a := range snap.AlbumList {
		x := rnd.Float64() * 2
		x += genreScore[names.Key(a.Genre)] * 0.3
		x += artistScore[a.ArtistID] * 0.2
		sc = append(sc, scored{a, x})
	}
	sort.Slice(sc, func(i, j int) bool { return sc[i].s > sc[j].s })
	var mix []mCard
	for _, x := range sc {
		if len(mix) >= 15 {
			break
		}
		mix = append(mix, v.albumCard(x.a))
	}
	if len(mix) > 0 {
		rows = append(rows, row{"mix", "Senin İçin Karışık", "square", mix})
	}

	// recently added albums / singles
	type added struct {
		c  mCard
		at int64
	}
	var adds []added
	for _, a := range snap.AlbumList {
		adds = append(adds, added{v.albumCard(a), a.AddedAt})
	}
	for _, t := range snap.All {
		if t.AlbumRef == nil {
			adds = append(adds, added{v.trackCard(t), t.AddedAt})
		}
	}
	sort.SliceStable(adds, func(i, j int) bool { return adds[i].at > adds[j].at })
	var addCards []mCard
	for _, a := range adds {
		if len(addCards) >= 15 {
			break
		}
		addCards = append(addCards, a.c)
	}
	if len(addCards) > 0 {
		rows = append(rows, row{"added", "Son Eklenenler", "square", addCards})
	}

	// most played tracks
	top := make([]played, 0, len(plays))
	for _, p := range plays {
		top = append(top, p)
	}
	sort.SliceStable(top, func(i, j int) bool {
		return v.ud.Plays[top[i].t.ID].Count > v.ud.Plays[top[j].t.ID].Count
	})
	var topCards []mCard
	for _, p := range top {
		if len(topCards) >= 15 || v.ud.Plays[p.t.ID].Count < 2 {
			break
		}
		topCards = append(topCards, v.trackCard(p.t))
	}
	if len(topCards) >= 3 {
		rows = append(rows, row{"top", "En Çok Dinlediklerin", "square", topCards})
	}

	// artists
	arts := append([]*music.Artist(nil), snap.ArtistList...)
	sort.SliceStable(arts, func(i, j int) bool {
		si, sj := artistScore[arts[i].ID], artistScore[arts[j].ID]
		if si != sj {
			return si > sj
		}
		return len(arts[i].Tracks) > len(arts[j].Tracks)
	})
	var artCards []mCard
	for _, a := range arts {
		if len(artCards) >= 15 {
			break
		}
		if a.Name == music.UnknownArtist {
			continue
		}
		artCards = append(artCards, v.artistCard(a))
	}
	if len(artCards) > 0 {
		rows = append(rows, row{"artists", "Sanatçılar", "round", artCards})
	}

	// liked songs not heard for a while
	cutoff := time.Now().Add(-30 * 24 * time.Hour).Unix()
	var redis []mCard
	for id := range v.ud.Likes {
		t := snap.Tracks[id]
		if t == nil || v.ud.Plays[id].Last > cutoff {
			continue
		}
		redis = append(redis, v.trackCard(t))
	}
	if len(redis) >= 3 {
		rnd.Shuffle(len(redis), func(i, j int) { redis[i], redis[j] = redis[j], redis[i] })
		if len(redis) > 12 {
			redis = redis[:12]
		}
		rows = append(rows, row{"rediscover", "Yeniden Keşfet", "square", redis})
	}
	if quick == nil {
		quick = []mCard{}
	}
	if rows == nil {
		rows = []row{}
	}
	writeJSONz(w, r, http.StatusOK, map[string]any{"quick": quick, "rows": rows, "trackCount": len(snap.Tracks)})
}

func (s *Server) mTracks(w http.ResponseWriter, r *http.Request) {
	v := s.mView(r)
	q := r.URL.Query()
	list := v.snap.All
	if g := q.Get("genre"); g != "" {
		k := names.Key(g)
		list = nil
		for _, gg := range v.snap.Genres {
			if names.Key(gg.Name) == k {
				list = gg.Tracks
			}
		}
	}
	list = append([]*music.Track(nil), list...)
	switch q.Get("sort") {
	case "added":
		sort.SliceStable(list, func(i, j int) bool { return list[i].AddedAt > list[j].AddedAt })
	case "artist":
		sort.SliceStable(list, func(i, j int) bool {
			return names.NaturalLess(list[i].ArtistName, list[j].ArtistName)
		})
	case "album":
		sort.SliceStable(list, func(i, j int) bool { return names.NaturalLess(list[i].Tags.Album, list[j].Tags.Album) })
	case "plays":
		sort.SliceStable(list, func(i, j int) bool { return v.ud.Plays[list[i].ID].Count > v.ud.Plays[list[j].ID].Count })
	case "recent":
		sort.SliceStable(list, func(i, j int) bool { return v.ud.Plays[list[i].ID].Last > v.ud.Plays[list[j].ID].Last })
	}
	if q.Get("order") == "desc" && (q.Get("sort") == "" || q.Get("sort") == "title") {
		for i, j := 0, len(list)-1; i < j; i, j = i+1, j-1 {
			list[i], list[j] = list[j], list[i]
		}
	}
	writeJSONz(w, r, http.StatusOK, v.tracks(list))
}

func (s *Server) mTracksBatch(w http.ResponseWriter, r *http.Request) {
	var b struct {
		IDs []string `json:"ids"`
	}
	if err := readJSON(r, &b); err != nil {
		writeError(w, http.StatusBadRequest, "Geçersiz istek")
		return
	}
	v := s.mView(r)
	out := []mTrackJSON{}
	for _, id := range b.IDs {
		if t := v.snap.Tracks[id]; t != nil {
			out = append(out, v.track(t))
		}
	}
	writeJSONz(w, r, http.StatusOK, out)
}

func (s *Server) mPlayed(w http.ResponseWriter, r *http.Request) {
	pid := s.requireProfile(w, r)
	if pid == "" {
		return
	}
	id := r.PathValue("id")
	if s.Music.Snap().Tracks[id] == nil {
		writeError(w, http.StatusNotFound, "Şarkı bulunamadı")
		return
	}
	var b struct {
		At int64 `json:"at"`
	}
	_ = readJSON(r, &b)
	p, err := s.Music.AddPlay(pid, id, b.At)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Kaydedilemedi")
		return
	}
	writeJSON(w, http.StatusOK, p)
}

func (s *Server) mAlbums(w http.ResponseWriter, r *http.Request) {
	v := s.mView(r)
	list := append([]*music.Album(nil), v.snap.AlbumList...)
	switch r.URL.Query().Get("sort") {
	case "added":
		sort.SliceStable(list, func(i, j int) bool { return list[i].AddedAt > list[j].AddedAt })
	case "year":
		sort.SliceStable(list, func(i, j int) bool { return list[i].Year > list[j].Year })
	case "artist":
		sort.SliceStable(list, func(i, j int) bool { return names.NaturalLess(list[i].Artist, list[j].Artist) })
	case "recent":
		last := func(a *music.Album) int64 {
			var m int64
			for _, t := range a.Tracks {
				m = max(m, v.ud.Plays[t.ID].Last)
			}
			return m
		}
		sort.SliceStable(list, func(i, j int) bool { return last(list[i]) > last(list[j]) })
	}
	writeJSONz(w, r, http.StatusOK, v.albums(list))
}

func (s *Server) mAlbum(w http.ResponseWriter, r *http.Request) {
	v := s.mView(r)
	a := v.snap.Albums[r.PathValue("id")]
	if a == nil {
		writeError(w, http.StatusNotFound, "Albüm bulunamadı")
		return
	}
	var more []mAlbumJSON
	if ar := v.snap.Artists[a.ArtistID]; ar != nil {
		for _, o := range ar.Albums {
			if o.ID != a.ID && len(more) < 10 {
				more = append(more, v.album(o))
			}
		}
	}
	if more == nil {
		more = []mAlbumJSON{}
	}
	writeJSONz(w, r, http.StatusOK, map[string]any{"album": v.album(a), "tracks": v.tracks(a.Tracks), "moreByArtist": more})
}

func (s *Server) mArtists(w http.ResponseWriter, r *http.Request) {
	v := s.mView(r)
	out := make([]mArtistJSON, 0, len(v.snap.ArtistList))
	for _, a := range v.snap.ArtistList {
		out = append(out, v.artist(a))
	}
	writeJSONz(w, r, http.StatusOK, out)
}

func (s *Server) mArtist(w http.ResponseWriter, r *http.Request) {
	v := s.mView(r)
	a := v.snap.Artists[r.PathValue("id")]
	if a == nil {
		writeError(w, http.StatusNotFound, "Sanatçı bulunamadı")
		return
	}
	top := append([]*music.Track(nil), a.Tracks...)
	sort.SliceStable(top, func(i, j int) bool { return v.ud.Plays[top[i].ID].Count > v.ud.Plays[top[j].ID].Count })
	if len(top) > 10 {
		top = top[:10]
	}
	// albums of other artists this artist appears on
	var appears []*music.Album
	seen := map[string]bool{}
	for _, al := range a.Albums {
		seen[al.ID] = true
	}
	for _, t := range a.Tracks {
		if t.AlbumRef != nil && !seen[t.AlbumRef.ID] {
			seen[t.AlbumRef.ID] = true
			appears = append(appears, t.AlbumRef)
		}
	}
	writeJSONz(w, r, http.StatusOK, map[string]any{
		"artist": v.artist(a), "top": v.tracks(top), "albums": v.albums(a.Albums),
		"appearsOn": v.albums(appears), "tracks": v.tracks(a.Tracks),
	})
}

func (s *Server) mGenres(w http.ResponseWriter, r *http.Request) {
	v := s.mView(r)
	type g struct {
		Name       string `json:"name"`
		TrackCount int    `json:"trackCount"`
		Cover      string `json:"cover"`
	}
	out := []g{}
	for _, x := range v.snap.Genres {
		// a stable pick so the tile doesn't change every time
		t := x.Tracks[int(fnvString(x.Name)%uint64(len(x.Tracks)))]
		out = append(out, g{x.Name, len(x.Tracks), v.cover(s.Music.Covers.CoverOwner(t))})
	}
	writeJSONz(w, r, http.StatusOK, out)
}

func fnvString(s string) uint64 {
	h := fnv.New64a()
	_, _ = h.Write([]byte(s))
	return h.Sum64()
}

func matchScore(fold, title string, words []string, q string) int {
	for _, w := range words {
		if !strings.Contains(fold, w) {
			return -1
		}
	}
	ft := names.Fold(title)
	switch {
	case ft == q:
		return 0
	case strings.HasPrefix(ft, q):
		return 1
	case strings.Contains(ft, q):
		return 2
	}
	return 3
}

func (s *Server) mSearch(w http.ResponseWriter, r *http.Request) {
	v := s.mView(r)
	q := names.Fold(r.URL.Query().Get("q"))
	type folderHit struct {
		Name  string `json:"name"`
		Path  string `json:"path"`
		Count int    `json:"count"`
		Cover string `json:"cover"`
	}
	resp := map[string]any{"tracks": []mTrackJSON{}, "albums": []mAlbumJSON{}, "artists": []mArtistJSON{},
		"playlists": []mPlaylistJSON{}, "folders": []folderHit{}}
	if q == "" {
		writeJSON(w, http.StatusOK, resp)
		return
	}
	words := strings.Fields(q)
	type hit[T any] struct {
		x T
		s int
	}
	var th []hit[*music.Track]
	for _, t := range v.snap.All {
		if sc := matchScore(names.Fold(t.Title+" "+t.ArtistName+" "+t.Tags.Album+" "+t.AlbumArtist), t.Title, words, q); sc >= 0 {
			th = append(th, hit[*music.Track]{t, sc})
		}
	}
	sort.SliceStable(th, func(i, j int) bool { return th[i].s < th[j].s })
	tracks := []mTrackJSON{}
	for i, h := range th {
		if i >= 60 {
			break
		}
		tracks = append(tracks, v.track(h.x))
	}
	var ah []hit[*music.Album]
	for _, a := range v.snap.AlbumList {
		if sc := matchScore(names.Fold(a.Title+" "+a.Artist), a.Title, words, q); sc >= 0 {
			ah = append(ah, hit[*music.Album]{a, sc})
		}
	}
	sort.SliceStable(ah, func(i, j int) bool { return ah[i].s < ah[j].s })
	albums := []mAlbumJSON{}
	for i, h := range ah {
		if i >= 20 {
			break
		}
		albums = append(albums, v.album(h.x))
	}
	var rh []hit[*music.Artist]
	for _, a := range v.snap.ArtistList {
		if sc := matchScore(names.Fold(a.Name), a.Name, words, q); sc >= 0 {
			rh = append(rh, hit[*music.Artist]{a, sc})
		}
	}
	sort.SliceStable(rh, func(i, j int) bool { return rh[i].s < rh[j].s })
	artists := []mArtistJSON{}
	for i, h := range rh {
		if i >= 20 {
			break
		}
		artists = append(artists, v.artist(h.x))
	}
	playlists := []mPlaylistJSON{}
	if v.pid != "" {
		if pls, err := s.Music.Playlists(v.pid); err == nil {
			for _, p := range pls {
				if matchScore(names.Fold(p.Name), p.Name, words, q) >= 0 {
					playlists = append(playlists, v.playlist(p, false))
				}
			}
		}
	}
	folders := []folderHit{}
	keys := make([]string, 0)
	for k, n := range v.snap.Dirs {
		if n.Parent != "" && n.Count > 0 && matchScore(names.Fold(n.Name), n.Name, words, q) >= 0 {
			keys = append(keys, k)
		}
	}
	sort.Strings(keys)
	for _, k := range keys {
		if len(folders) >= 15 {
			break
		}
		n := v.snap.Dirs[k]
		folders = append(folders, folderHit{n.Name, n.Key, n.Count, v.dirCover(n)})
	}
	resp["tracks"], resp["albums"], resp["artists"], resp["playlists"], resp["folders"] = tracks, albums, artists, playlists, folders
	writeJSONz(w, r, http.StatusOK, resp)
}

func (v *mView) dirCover(n *music.DirNode) string {
	if n.First == nil {
		return v.cover(n.Key)
	}
	return v.cover(v.s.Music.Covers.CoverOwner(n.First))
}

func (s *Server) mBrowse(w http.ResponseWriter, r *http.Request) {
	v := s.mView(r)
	p := strings.Trim(r.URL.Query().Get("path"), "/")
	type dirJSON struct {
		Name  string `json:"name"`
		Path  string `json:"path"`
		Count int    `json:"count"`
		Cover string `json:"cover"`
	}
	if p == "" {
		dirs := []dirJSON{}
		for _, n := range v.snap.Roots {
			dirs = append(dirs, dirJSON{n.Name, n.Key, n.Count, v.dirCover(n)})
		}
		writeJSONz(w, r, http.StatusOK, map[string]any{"path": "", "name": "Klasörler", "parent": nil, "dirs": dirs, "tracks": []mTrackJSON{}})
		return
	}
	n := v.snap.Dirs[p]
	if n == nil {
		// folders without songs are not in the tree
		writeError(w, http.StatusNotFound, "Klasör bulunamadı (disk takılı mı?)")
		return
	}
	dirs := []dirJSON{}
	for _, d := range n.Subdirs {
		dirs = append(dirs, dirJSON{d.Name, d.Key, d.Count, v.dirCover(d)})
	}
	var tracks []*music.Track
	if r.URL.Query().Get("recursive") == "1" {
		var walk func(d *music.DirNode)
		walk = func(d *music.DirNode) {
			tracks = append(tracks, d.Tracks...)
			for _, sd := range d.Subdirs {
				walk(sd)
			}
		}
		walk(n)
	} else {
		tracks = n.Tracks
	}
	var parent any
	if n.Parent != "" {
		parent = n.Parent
	} else {
		parent = ""
	}
	writeJSONz(w, r, http.StatusOK, map[string]any{"path": n.Key, "name": n.Name, "parent": parent, "dirs": dirs,
		"tracks": v.tracks(tracks), "count": n.Count, "cover": v.dirCover(n)})
}

func (s *Server) mLiked(w http.ResponseWriter, r *http.Request) {
	v := s.mView(r)
	type liked struct {
		t  *music.Track
		at int64
	}
	var list []liked
	for id, at := range v.ud.Likes {
		if t := v.snap.Tracks[id]; t != nil {
			list = append(list, liked{t, at})
		}
	}
	sort.Slice(list, func(i, j int) bool { return list[i].at > list[j].at })
	ts := make([]*music.Track, len(list))
	for i, l := range list {
		ts[i] = l.t
	}
	writeJSONz(w, r, http.StatusOK, v.tracks(ts))
}

func (s *Server) mLike(w http.ResponseWriter, r *http.Request) {
	pid := s.requireProfile(w, r)
	if pid == "" {
		return
	}
	var b struct {
		IDs   []string `json:"ids"`
		Liked bool     `json:"liked"`
	}
	if err := readJSON(r, &b); err != nil || len(b.IDs) == 0 || len(b.IDs) > 5000 {
		writeError(w, http.StatusBadRequest, "Geçersiz istek")
		return
	}
	if err := s.Music.SetLiked(pid, b.IDs, b.Liked); err != nil {
		writeError(w, http.StatusInternalServerError, "Kaydedilemedi")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "liked": b.Liked})
}

// ---------- playlists ----------

func validName(n string) (string, bool) {
	n = strings.TrimSpace(n)
	if n == "" || len([]rune(n)) > 100 {
		return "", false
	}
	return n, true
}

func (s *Server) mPlaylists(w http.ResponseWriter, r *http.Request) {
	v := s.mView(r)
	out := []mPlaylistJSON{}
	if v.pid != "" {
		pls, err := s.Music.Playlists(v.pid)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "Çalma listeleri okunamadı")
			return
		}
		for _, p := range pls {
			out = append(out, v.playlist(p, false))
		}
	}
	writeJSONz(w, r, http.StatusOK, out)
}

func (s *Server) mCreatePlaylist(w http.ResponseWriter, r *http.Request) {
	pid := s.requireProfile(w, r)
	if pid == "" {
		return
	}
	var b struct {
		Name string   `json:"name"`
		IDs  []string `json:"ids"`
	}
	if err := readJSON(r, &b); err != nil {
		writeError(w, http.StatusBadRequest, "Geçersiz istek")
		return
	}
	name, ok := validName(b.Name)
	if !ok {
		writeError(w, http.StatusBadRequest, "Çalma listesine bir ad verin (en fazla 100 karakter)")
		return
	}
	p, err := s.Music.CreatePlaylist(pid, name, b.IDs)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Çalma listesi oluşturulamadı")
		return
	}
	writeJSON(w, http.StatusCreated, s.mView(r).playlist(p, true))
}

func (s *Server) playlistErr(w http.ResponseWriter, err error) {
	if errors.Is(err, music.ErrNotFound) {
		writeError(w, http.StatusNotFound, "Çalma listesi bulunamadı")
		return
	}
	writeError(w, http.StatusInternalServerError, "Çalma listesi kaydedilemedi")
}

func (s *Server) mPlaylist(w http.ResponseWriter, r *http.Request) {
	pid := s.requireProfile(w, r)
	if pid == "" {
		return
	}
	p, err := s.Music.GetPlaylist(pid, r.PathValue("id"))
	if err != nil {
		s.playlistErr(w, err)
		return
	}
	writeJSONz(w, r, http.StatusOK, s.mView(r).playlist(p, true))
}

func (s *Server) mRenamePlaylist(w http.ResponseWriter, r *http.Request) {
	pid := s.requireProfile(w, r)
	if pid == "" {
		return
	}
	var b struct {
		Name string `json:"name"`
	}
	if err := readJSON(r, &b); err != nil {
		writeError(w, http.StatusBadRequest, "Geçersiz istek")
		return
	}
	name, ok := validName(b.Name)
	if !ok {
		writeError(w, http.StatusBadRequest, "Çalma listesine bir ad verin (en fazla 100 karakter)")
		return
	}
	if err := s.Music.RenamePlaylist(pid, r.PathValue("id"), name); err != nil {
		s.playlistErr(w, err)
		return
	}
	s.mPlaylist(w, r)
}

func (s *Server) mDeletePlaylist(w http.ResponseWriter, r *http.Request) {
	pid := s.requireProfile(w, r)
	if pid == "" {
		return
	}
	if err := s.Music.DeletePlaylist(pid, r.PathValue("id")); err != nil {
		s.playlistErr(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func (s *Server) mSetPlaylistTracks(w http.ResponseWriter, r *http.Request) {
	pid := s.requireProfile(w, r)
	if pid == "" {
		return
	}
	var b struct {
		IDs []string `json:"ids"`
	}
	if err := readJSON(r, &b); err != nil || len(b.IDs) > 20000 {
		writeError(w, http.StatusBadRequest, "Geçersiz istek")
		return
	}
	id := r.PathValue("id")
	// songs that are not visible now (e.g. disk unplugged) stay in the list
	if old, err := s.Music.GetPlaylist(pid, id); err == nil {
		snap := s.Music.Snap()
		keep := map[string]bool{}
		for _, x := range b.IDs {
			keep[x] = true
		}
		for _, x := range old.TrackIDs {
			if snap.Tracks[x] == nil && !keep[x] {
				b.IDs = append(b.IDs, x)
			}
		}
	}
	if err := s.Music.SetPlaylistTracks(pid, id, b.IDs); err != nil {
		s.playlistErr(w, err)
		return
	}
	s.mPlaylist(w, r)
}

func (s *Server) mAddPlaylistTracks(w http.ResponseWriter, r *http.Request) {
	pid := s.requireProfile(w, r)
	if pid == "" {
		return
	}
	var b struct {
		IDs           []string `json:"ids"`
		SkipDuplicate bool     `json:"skipDuplicates"`
	}
	if err := readJSON(r, &b); err != nil || len(b.IDs) == 0 || len(b.IDs) > 20000 {
		writeError(w, http.StatusBadRequest, "Geçersiz istek")
		return
	}
	id := r.PathValue("id")
	p, err := s.Music.GetPlaylist(pid, id)
	if err != nil {
		s.playlistErr(w, err)
		return
	}
	have := map[string]bool{}
	for _, x := range p.TrackIDs {
		have[x] = true
	}
	ids := p.TrackIDs
	added := 0
	for _, x := range b.IDs {
		if b.SkipDuplicate && have[x] {
			continue
		}
		have[x] = true
		ids = append(ids, x)
		added++
	}
	if err := s.Music.SetPlaylistTracks(pid, id, ids); err != nil {
		s.playlistErr(w, err)
		return
	}
	p, _ = s.Music.GetPlaylist(pid, id)
	out := s.mView(r).playlist(p, false)
	writeJSON(w, http.StatusOK, map[string]any{"playlist": out, "added": added})
}

// ---------- stream & covers ----------

func (s *Server) mStream(w http.ResponseWriter, r *http.Request) {
	t := s.Music.Snap().Tracks[r.PathValue("id")]
	if t == nil {
		writeError(w, http.StatusNotFound, "Şarkı bulunamadı")
		return
	}
	p, mime := s.Music.StreamFile(r.Context(), t)
	f, err := os.Open(p)
	if err != nil {
		writeError(w, http.StatusNotFound, "Dosya açılamadı (disk takılı mı?)")
		return
	}
	defer f.Close()
	st, err := f.Stat()
	if err != nil || st.IsDir() {
		writeError(w, http.StatusNotFound, "Dosya açılamadı")
		return
	}
	w.Header().Set("Content-Type", mime)
	w.Header().Set("Accept-Ranges", "bytes")
	w.Header().Set("Cache-Control", "private, max-age=3600")
	w.Header().Set("Content-Disposition", "inline; filename*=UTF-8''"+urlPathEscape(t.ID+filepath.Ext(p)))
	http.ServeContent(w, r, "", st.ModTime(), f)
}

func urlPathEscape(s string) string {
	var b strings.Builder
	for _, c := range []byte(s) {
		if c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' || c == '.' || c == '-' || c == '_' {
			b.WriteByte(c)
		} else {
			b.WriteString("%" + strings.ToUpper(strconv.FormatInt(int64(c)+0x100, 16)[1:]))
		}
	}
	return b.String()
}

func (s *Server) mCover(w http.ResponseWriter, r *http.Request) {
	width, _ := strconv.Atoi(r.URL.Query().Get("w"))
	s.Music.Covers.Serve(w, r, r.PathValue("id"), width)
}

// ---------- settings ----------

func (s *Server) mSettingsJSON() map[string]any {
	folders, _ := s.Music.Folders()
	snap := s.Music.Snap()
	counts := map[int64]int{}
	for _, t := range snap.Tracks {
		counts[t.FolderID]++
	}
	type fj struct {
		music.Folder
		TrackCount int `json:"trackCount"`
	}
	out := []fj{}
	for _, f := range folders {
		out = append(out, fj{f, counts[f.ID]})
	}
	interval, err := strconv.Atoi(s.St.GetSetting("scanIntervalMinutes"))
	if err != nil {
		interval = 30
	}
	ff := s.Music.HasFFmpeg()
	return map[string]any{
		"serverName": s.ServerName(), "folders": out, "onlineCovers": s.St.GetSetting("music.onlineCovers") != "0",
		"scanIntervalMinutes": interval, "ffmpeg": ff,
	}
}

func (s *Server) mGetSettings(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, s.mSettingsJSON())
}

func (s *Server) mAdminCheck(w http.ResponseWriter, r *http.Request) {
	if !requireAdmin(w, r) {
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func (s *Server) mPutSettings(w http.ResponseWriter, r *http.Request) {
	if !requireAdmin(w, r) {
		return
	}
	var b struct {
		OnlineCovers        *bool `json:"onlineCovers"`
		ScanIntervalMinutes *int  `json:"scanIntervalMinutes"`
	}
	if err := readJSON(r, &b); err != nil {
		writeError(w, http.StatusBadRequest, "Geçersiz istek")
		return
	}
	if b.OnlineCovers != nil {
		v := "1"
		if !*b.OnlineCovers {
			v = "0"
		}
		_ = s.St.SetSetting("music.onlineCovers", v)
		if *b.OnlineCovers {
			s.Music.RefreshCovers(s.ctx())
		}
	}
	if b.ScanIntervalMinutes != nil {
		n := *b.ScanIntervalMinutes
		if n < 0 || n > 7*24*60 {
			writeError(w, http.StatusBadRequest, "Tarama aralığı 0 ile 10080 dakika arasında olmalı")
			return
		}
		_ = s.St.SetSetting("scanIntervalMinutes", strconv.Itoa(n))
		s.Music.Wake()
		s.Lib.Wake()
	}
	writeJSON(w, http.StatusOK, s.mSettingsJSON())
}

func (s *Server) mAddFolder(w http.ResponseWriter, r *http.Request) {
	if !requireAdmin(w, r) {
		return
	}
	var b struct {
		Path string `json:"path"`
		Name string `json:"name"`
	}
	if err := readJSON(r, &b); err != nil {
		writeError(w, http.StatusBadRequest, "Geçersiz istek")
		return
	}
	p := strings.TrimSpace(b.Path)
	if p == "" || !filepath.IsAbs(p) {
		writeError(w, http.StatusBadRequest, "Klasör yolu tam yol olmalı (ör. /media/disk/Müzik)")
		return
	}
	p = filepath.Clean(p)
	st, err := os.Stat(p)
	if err != nil || !st.IsDir() {
		writeError(w, http.StatusBadRequest, "Klasör bulunamadı")
		return
	}
	if _, err := os.ReadDir(p); err != nil {
		writeError(w, http.StatusBadRequest, "Klasör okunamıyor (izin yok)")
		return
	}
	if p == "/" {
		writeError(w, http.StatusBadRequest, "Bütün disk eklenemez; müziklerin olduğu klasörü seçin")
		return
	}
	folders, _ := s.Music.Folders()
	for _, f := range folders {
		if f.Path == p {
			writeError(w, http.StatusConflict, "Bu klasör zaten ekli")
			return
		}
		if strings.HasPrefix(p+"/", strings.TrimRight(f.Path, "/")+"/") || strings.HasPrefix(f.Path+"/", strings.TrimRight(p, "/")+"/") {
			writeError(w, http.StatusConflict, "Bu klasör, ekli \""+f.Name+"\" klasörüyle iç içe")
			return
		}
	}
	name := strings.TrimSpace(b.Name)
	if name == "" {
		name = names.DisplayString(filepath.Base(p))
	}
	f, err := s.Music.AddFolder(p, name)
	if err != nil {
		if errors.Is(err, music.ErrExists) {
			writeError(w, http.StatusConflict, "Bu klasör zaten ekli")
			return
		}
		writeError(w, http.StatusInternalServerError, "Klasör eklenemedi")
		return
	}
	log.Printf("music: folder added %q (%s)", p, name)
	writeJSON(w, http.StatusCreated, f)
}

func (s *Server) mDeleteFolder(w http.ResponseWriter, r *http.Request) {
	if !requireAdmin(w, r) {
		return
	}
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		writeError(w, http.StatusNotFound, "Klasör bulunamadı")
		return
	}
	folders, _ := s.Music.Folders()
	for _, f := range folders {
		if f.ID != id {
			continue
		}
		if f.IsDefault {
			writeError(w, http.StatusBadRequest, "Varsayılan Müzik klasörü kaldırılamaz")
			return
		}
		if err := s.Music.RemoveFolder(id); err != nil {
			writeError(w, http.StatusInternalServerError, "Klasör kaldırılamadı")
			return
		}
		log.Printf("music: folder removed %q", f.Path)
		writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
		return
	}
	writeError(w, http.StatusNotFound, "Klasör bulunamadı")
}

func (s *Server) mScan(w http.ResponseWriter, r *http.Request) {
	var b struct {
		RefreshCovers bool `json:"refreshCovers"`
	}
	_ = readJSON(r, &b)
	if b.RefreshCovers {
		s.Music.RefreshCovers(s.ctx())
	}
	s.Music.RequestScan()
	writeJSON(w, http.StatusAccepted, s.Music.Status())
}

func (s *Server) mScanStatus(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, s.Music.Status())
}
