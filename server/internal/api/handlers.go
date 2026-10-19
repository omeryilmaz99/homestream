package api

import (
	"encoding/json"
	"errors"
	"log"
	"mime"
	"net/http"
	"os"
	"path"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"homestream/internal/library"
	"homestream/internal/names"
	"homestream/internal/store"
)

// ---------- info ----------

func (s *Server) handleInfo(w http.ResponseWriter, r *http.Request) {
	snap := s.Lib.Snap()
	st := s.Lib.Status()
	writeJSON(w, http.StatusOK, map[string]any{
		"app": "homestream", "id": s.ServerID, "name": s.ServerName(), "version": s.Version,
		"itemCount":  len(snap.Movies) + len(snap.Series),
		"movieCount": len(snap.Movies), "seriesCount": len(snap.Series), "episodeCount": len(snap.Episodes),
		"scanning": st.Running,
	})
}

// ---------- profiles ----------

var reColor = regexp.MustCompile(`^#[0-9A-Fa-f]{6}$`)

type profileBody struct {
	Name   *string `json:"name"`
	Color  *string `json:"color"`
	Avatar *string `json:"avatar"`
}

func (s *Server) handleProfiles(w http.ResponseWriter, r *http.Request) {
	ps, err := s.St.Profiles()
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Profiller okunamadı")
		return
	}
	writeJSON(w, http.StatusOK, ps)
}

func validateProfile(p *store.Profile, b profileBody) string {
	if b.Name != nil {
		p.Name = strings.TrimSpace(*b.Name)
	}
	if b.Color != nil {
		p.Color = strings.TrimSpace(*b.Color)
	}
	if b.Avatar != nil {
		p.Avatar = strings.TrimSpace(*b.Avatar)
	}
	if p.Name == "" {
		return "Profil adı boş olamaz"
	}
	if utf8.RuneCountInString(p.Name) > 40 {
		return "Profil adı en fazla 40 karakter olabilir"
	}
	if !reColor.MatchString(p.Color) {
		p.Color = "#E50914"
	}
	if p.Avatar == "" || utf8.RuneCountInString(p.Avatar) > 16 {
		p.Avatar = "😀"
	}
	return ""
}

func (s *Server) handleCreateProfile(w http.ResponseWriter, r *http.Request) {
	var b profileBody
	if err := readJSON(r, &b); err != nil {
		writeError(w, http.StatusBadRequest, "Geçersiz istek")
		return
	}
	var p store.Profile
	if msg := validateProfile(&p, b); msg != "" {
		writeError(w, http.StatusBadRequest, msg)
		return
	}
	created, err := s.St.CreateProfile(p.Name, p.Color, p.Avatar)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "Profil oluşturulamadı")
		return
	}
	writeJSON(w, http.StatusCreated, created)
}

func (s *Server) handleUpdateProfile(w http.ResponseWriter, r *http.Request) {
	p, ok := s.St.Profile(r.PathValue("id"))
	if !ok {
		writeError(w, http.StatusNotFound, "Profil bulunamadı")
		return
	}
	var b profileBody
	if err := readJSON(r, &b); err != nil {
		writeError(w, http.StatusBadRequest, "Geçersiz istek")
		return
	}
	if msg := validateProfile(&p, b); msg != "" {
		writeError(w, http.StatusBadRequest, msg)
		return
	}
	if err := s.St.UpdateProfile(p); err != nil {
		writeError(w, http.StatusInternalServerError, "Profil güncellenemedi")
		return
	}
	writeJSON(w, http.StatusOK, p)
}

func (s *Server) handleDeleteProfile(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if _, ok := s.St.Profile(id); !ok {
		writeError(w, http.StatusNotFound, "Profil bulunamadı")
		return
	}
	if err := s.St.DeleteProfile(id); err != nil {
		writeError(w, http.StatusInternalServerError, "Profil silinemedi")
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

// ---------- lists ----------

func (s *Server) handleHome(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, s.newView(s.profileID(r)).home())
}

func (s *Server) handleGenres(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, s.Lib.Snap().Genres)
}

func (s *Server) handleList(kind string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		v := s.newView(s.profileID(r))
		src := v.snap.Movies
		if kind == "series" {
			src = v.snap.Series
		}
		q := r.URL.Query()
		genre := names.Fold(q.Get("genre"))
		filter := q.Get("filter")
		list := make([]*library.Item, 0, len(src))
		for _, it := range src {
			if genre != "" {
				found := false
				for _, g := range it.Genres {
					if names.Fold(g) == genre {
						found = true
						break
					}
				}
				if !found {
					continue
				}
			}
			ud := v.userData(it)
			switch filter {
			case "unwatched":
				if it.Type == "series" && v.unwatched(it) == 0 || it.Type != "series" && ud.Played {
					continue
				}
			case "watched":
				if !ud.Played {
					continue
				}
			case "liked":
				if !ud.Liked {
					continue
				}
			}
			list = append(list, it)
		}
		sortBy := q.Get("sort")
		order := q.Get("order")
		desc := order == "desc"
		if order == "" {
			desc = sortBy != "" && sortBy != "title"
		}
		var key func(it *library.Item) float64
		switch sortBy {
		case "added":
			key = func(it *library.Item) float64 { return float64(it.AddedAt) }
		case "year":
			key = func(it *library.Item) float64 { return float64(it.Year) }
		case "rating":
			key = func(it *library.Item) float64 { return it.Rating }
		case "lastPlayed":
			key = func(it *library.Item) float64 { return float64(v.userData(it).LastPlayedAt) }
		}
		if key != nil {
			sort.SliceStable(list, func(i, j int) bool {
				a, b := key(list[i]), key(list[j])
				if a == b {
					return false // keep title order
				}
				if desc {
					return a > b
				}
				return a < b
			})
		} else if desc {
			for i, j := 0, len(list)-1; i < j; i, j = i+1, j-1 {
				list[i], list[j] = list[j], list[i]
			}
		}
		writeJSON(w, http.StatusOK, v.items(list))
	}
}

// ---------- items ----------

func (s *Server) lookup(w http.ResponseWriter, r *http.Request) (*view, *library.Item) {
	v := s.newView(s.profileID(r))
	it := v.snap.Items[r.PathValue("id")]
	if it == nil {
		writeError(w, http.StatusNotFound, "İçerik bulunamadı")
		return nil, nil
	}
	return v, it
}

func (s *Server) handleItem(w http.ResponseWriter, r *http.Request) {
	v, it := s.lookup(w, r)
	if it == nil {
		return
	}
	writeJSON(w, http.StatusOK, v.detail(it))
}

func (s *Server) handleRelated(w http.ResponseWriter, r *http.Request) {
	v, it := s.lookup(w, r)
	if it == nil {
		return
	}
	writeJSON(w, http.StatusOK, v.related(it))
}

func (s *Server) handleProgress(w http.ResponseWriter, r *http.Request) {
	p := s.requireProfile(w, r)
	if p == "" {
		return
	}
	_, it := s.lookup(w, r)
	if it == nil {
		return
	}
	if it.Type == "series" {
		writeError(w, http.StatusBadRequest, "Dizi için ilerleme kaydedilemez; bir bölüm seçin")
		return
	}
	var b struct {
		Position float64 `json:"position"`
		Duration float64 `json:"duration"`
	}
	if err := readJSON(r, &b); err != nil {
		writeError(w, http.StatusBadRequest, "Geçersiz istek")
		return
	}
	dur := b.Duration
	if dur <= 0 {
		dur = it.Duration
	}
	u := applyProgress(s.St.GetUserData(p, it.ID), b.Position, dur, time.Now().Unix())
	if err := s.St.PutUserData(p, map[string]store.UserData{it.ID: u}); err != nil {
		writeError(w, http.StatusInternalServerError, "Kaydedilemedi")
		return
	}
	writeJSON(w, http.StatusOK, u)
}

func (s *Server) handleClearProgress(w http.ResponseWriter, r *http.Request) {
	p := s.requireProfile(w, r)
	if p == "" {
		return
	}
	v, it := s.lookup(w, r)
	if it == nil {
		return
	}
	rows := map[string]store.UserData{}
	targets := []*library.Item{it}
	if it.Type == "series" {
		targets = it.Episodes
	}
	for _, t := range targets {
		u := v.ud[t.ID]
		if u.Position != 0 {
			u.Position = 0
			rows[t.ID] = u
		}
	}
	if err := s.St.PutUserData(p, rows); err != nil {
		writeError(w, http.StatusInternalServerError, "Kaydedilemedi")
		return
	}
	writeJSON(w, http.StatusOK, s.newView(p).userData(it))
}

func (s *Server) handlePlayed(w http.ResponseWriter, r *http.Request) {
	p := s.requireProfile(w, r)
	if p == "" {
		return
	}
	v, it := s.lookup(w, r)
	if it == nil {
		return
	}
	var b struct {
		Played *bool `json:"played"`
	}
	if err := readJSON(r, &b); err != nil {
		writeError(w, http.StatusBadRequest, "Geçersiz istek")
		return
	}
	played := b.Played == nil || *b.Played
	now := time.Now().Unix()
	rows := map[string]store.UserData{}
	targets := []*library.Item{it}
	if it.Type == "series" {
		targets = it.Episodes
	}
	for _, t := range targets {
		rows[t.ID] = applyPlayed(v.ud[t.ID], played, now)
	}
	if err := s.St.PutUserData(p, rows); err != nil {
		writeError(w, http.StatusInternalServerError, "Kaydedilemedi")
		return
	}
	writeJSON(w, http.StatusOK, s.newView(p).userData(it))
}

func (s *Server) handleLike(w http.ResponseWriter, r *http.Request) {
	p := s.requireProfile(w, r)
	if p == "" {
		return
	}
	v, it := s.lookup(w, r)
	if it == nil {
		return
	}
	var b struct {
		Liked *bool `json:"liked"`
	}
	if err := readJSON(r, &b); err != nil {
		writeError(w, http.StatusBadRequest, "Geçersiz istek")
		return
	}
	u := v.ud[it.ID]
	u.Liked = b.Liked == nil || *b.Liked
	if err := s.St.PutUserData(p, map[string]store.UserData{it.ID: u}); err != nil {
		writeError(w, http.StatusInternalServerError, "Kaydedilemedi")
		return
	}
	writeJSON(w, http.StatusOK, s.newView(p).userData(it))
}

func (s *Server) handleSearch(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, s.newView(s.profileID(r)).search(r.URL.Query().Get("q")))
}

// ---------- browse ----------

type browseEntry struct {
	Name     string          `json:"name"`
	Path     string          `json:"path"`
	Type     string          `json:"type"`
	Size     int64           `json:"size"`
	ItemID   string          `json:"itemId,omitempty"`
	Duration *float64        `json:"duration,omitempty"`
	UserData *store.UserData `json:"userData,omitempty"`
	Thumb    string          `json:"thumb,omitempty"`
}

func (s *Server) handleBrowse(w http.ResponseWriter, r *http.Request) {
	v := s.newView(s.profileID(r))
	p := strings.Trim(r.URL.Query().Get("path"), "/")
	resp := map[string]any{"path": p, "name": "Kütüphane", "parent": nil}
	entries := []browseEntry{}
	if p == "" {
		for _, f := range v.snap.Folders {
			if f.Available {
				entries = append(entries, browseEntry{Name: f.Name, Path: f.IDString(), Type: "dir"})
			}
		}
		resp["entries"] = entries
		writeJSON(w, http.StatusOK, resp)
		return
	}
	fid, rel, _ := strings.Cut(p, "/")
	var folder *library.FolderInfo
	for i := range v.snap.Folders {
		if v.snap.Folders[i].IDString() == fid {
			folder = &v.snap.Folders[i]
		}
	}
	if folder == nil {
		writeError(w, http.StatusNotFound, "Klasör bulunamadı")
		return
	}
	if !folder.Available {
		writeError(w, http.StatusNotFound, "Bu klasöre şu anda erişilemiyor (disk takılı mı?)")
		return
	}
	rel = strings.TrimPrefix(path.Clean("/"+rel), "/")
	abs := folder.Path
	if rel != "" {
		abs = filepath.Join(folder.Path, filepath.FromSlash(rel))
	}
	if abs != folder.Path && !strings.HasPrefix(abs, strings.TrimRight(folder.Path, "/")+"/") {
		writeError(w, http.StatusBadRequest, "Geçersiz yol")
		return
	}
	des, err := os.ReadDir(abs)
	if err != nil {
		writeError(w, http.StatusNotFound, "Klasör bulunamadı")
		return
	}
	prefix := fid
	if rel != "" {
		prefix = fid + "/" + rel
	}
	var dirs, vids []browseEntry
	for _, de := range des {
		name := de.Name()
		if strings.HasPrefix(name, ".") {
			continue
		}
		full := filepath.Join(abs, name)
		info, err := os.Stat(full) // follows symlinks
		if err != nil {
			continue
		}
		if info.IsDir() {
			if library.SkipDirName(name) {
				continue
			}
			dirs = append(dirs, browseEntry{Name: names.DisplayString(name), Path: prefix + "/" + name, Type: "dir"})
			continue
		}
		if !info.Mode().IsRegular() || !library.AcceptVideo(name, info.Size()) {
			continue
		}
		e := browseEntry{Name: names.DisplayString(name), Path: prefix + "/" + name, Type: "video", Size: info.Size()}
		if it := v.snap.ByPath[full]; it != nil {
			e.ItemID = it.ID
			d := it.Duration
			e.Duration = &d
			u := v.userData(it)
			e.UserData = &u
			e.Thumb = imageURL(it.ID, "thumb", s.Lib.Images.Version(it, "thumb"))
		}
		vids = append(vids, e)
	}
	sort.SliceStable(dirs, func(i, j int) bool { return names.NaturalLess(dirs[i].Name, dirs[j].Name) })
	sort.SliceStable(vids, func(i, j int) bool { return names.NaturalLess(vids[i].Name, vids[j].Name) })
	entries = append(append(entries, dirs...), vids...)
	resp["entries"] = entries
	if rel == "" {
		resp["name"] = folder.Name
		resp["parent"] = ""
	} else {
		resp["name"] = names.DisplayString(path.Base(rel))
		if pd := path.Dir(rel); pd == "." {
			resp["parent"] = fid
		} else {
			resp["parent"] = fid + "/" + pd
		}
	}
	resp["path"] = prefix
	writeJSON(w, http.StatusOK, resp)
}

// ---------- stream ----------

var videoMIME = map[string]string{
	".mkv": "video/x-matroska", ".mp4": "video/mp4", ".m4v": "video/mp4", ".avi": "video/x-msvideo",
	".divx": "video/x-msvideo", ".mov": "video/quicktime", ".wmv": "video/x-ms-wmv", ".ts": "video/mp2t",
	".m2ts": "video/mp2t", ".mts": "video/mp2t", ".webm": "video/webm", ".flv": "video/x-flv",
	".mpg": "video/mpeg", ".mpeg": "video/mpeg", ".vob": "video/mpeg", ".ogv": "video/ogg",
	".3gp": "video/3gpp", ".rmvb": "application/vnd.rn-realmedia-vbr",
}

func (s *Server) handleStream(w http.ResponseWriter, r *http.Request) {
	it := s.Lib.Snap().Items[r.PathValue("id")]
	if it == nil || it.Type == "series" {
		writeError(w, http.StatusNotFound, "İçerik bulunamadı")
		return
	}
	f, err := os.Open(it.AbsPath)
	if err != nil {
		writeError(w, http.StatusNotFound, "Dosya bulunamadı (disk takılı mı?)")
		return
	}
	defer f.Close()
	st, err := f.Stat()
	if err != nil || !st.Mode().IsRegular() {
		writeError(w, http.StatusNotFound, "Dosya bulunamadı")
		return
	}
	ct := videoMIME[strings.ToLower(filepath.Ext(it.AbsPath))]
	if ct == "" {
		ct = "application/octet-stream"
	}
	h := w.Header()
	h.Set("Content-Type", ct)
	h.Set("Accept-Ranges", "bytes")
	h.Set("ETag", `"`+strconv.FormatInt(st.Size(), 36)+"-"+strconv.FormatInt(st.ModTime().UnixNano(), 36)+`"`)
	h.Set("Content-Disposition", mime.FormatMediaType("inline", map[string]string{"filename": names.DisplayString(it.FileName)}))
	h.Set("Cache-Control", "no-cache")
	if r.Method == http.MethodGet {
		if rg := r.Header.Get("Range"); rg == "" || strings.HasPrefix(rg, "bytes=0-") {
			log.Printf("stream: %s (%s)", it.Title, r.RemoteAddr)
		}
	}
	http.ServeContent(w, r, "", st.ModTime(), f)
}

// ---------- images ----------

func (s *Server) handleImage(w http.ResponseWriter, r *http.Request) {
	kind := r.PathValue("kind")
	if kind != "poster" && kind != "backdrop" && kind != "thumb" {
		writeError(w, http.StatusBadRequest, "Geçersiz görsel türü")
		return
	}
	it := s.Lib.Snap().Items[r.PathValue("id")]
	if it == nil {
		writeError(w, http.StatusNotFound, "İçerik bulunamadı")
		return
	}
	width, _ := strconv.Atoi(r.URL.Query().Get("w"))
	s.Lib.Images.Serve(w, r, it, kind, width)
}

// ---------- settings ----------

type folderJSON struct {
	ID        string `json:"id"`
	Path      string `json:"path"`
	Name      string `json:"name"`
	Available bool   `json:"available"`
	ItemCount int    `json:"itemCount"`
	IsDefault bool   `json:"isDefault"`
}

func (s *Server) folderJSON(f store.Folder) folderJSON {
	return folderJSON{ID: f.IDString(), Path: names.DisplayString(f.Path), Name: f.Name, Available: f.Available,
		ItemCount: s.St.FolderFileCount(f.ID), IsDefault: f.IsDefault}
}

func maskKey(k string) string {
	if k == "" {
		return ""
	}
	if len(k) <= 4 {
		return "••••"
	}
	return "••••" + k[len(k)-4:]
}

func (s *Server) settingsJSON() map[string]any {
	folders, _ := s.St.Folders()
	fj := []folderJSON{}
	for _, f := range folders {
		fj = append(fj, s.folderJSON(f))
	}
	key := s.St.GetSetting("tmdbApiKey")
	interval, err := strconv.Atoi(s.St.GetSetting("scanIntervalMinutes"))
	if err != nil {
		interval = 30
	}
	return map[string]any{
		"serverName": s.ServerName(), "libraryFolders": fj, "tmdbApiKey": maskKey(key), "tmdbEnabled": key != "",
		"metadataLanguage": s.Lib.MetadataLanguage(), "scanIntervalMinutes": interval,
		"ffmpegAvailable": s.Lib.Cfg.FFmpeg != "" && s.Lib.Cfg.FFprobe != "",
	}
}

func (s *Server) handleGetSettings(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, s.settingsJSON())
}

var reLang = regexp.MustCompile(`^[a-z]{2}(-[A-Z]{2})?$`)

func (s *Server) handlePutSettings(w http.ResponseWriter, r *http.Request) {
	var b map[string]json.RawMessage
	if err := readJSON(r, &b); err != nil {
		writeError(w, http.StatusBadRequest, "Geçersiz istek")
		return
	}
	str := func(k string) (string, bool, bool) {
		raw, ok := b[k]
		if !ok {
			return "", false, true
		}
		var v string
		if err := json.Unmarshal(raw, &v); err != nil {
			return "", true, false
		}
		return strings.TrimSpace(v), true, true
	}
	rescan := false
	if v, ok, valid := str("serverName"); ok {
		if !valid || utf8.RuneCountInString(v) > 60 {
			writeError(w, http.StatusBadRequest, "Geçersiz sunucu adı")
			return
		}
		_ = s.St.SetSetting("serverName", v)
	}
	if v, ok, valid := str("tmdbApiKey"); ok {
		if !valid {
			writeError(w, http.StatusBadRequest, "Geçersiz TMDB anahtarı")
			return
		}
		old := s.St.GetSetting("tmdbApiKey")
		if v != maskKey(old) && v != old {
			_ = s.St.SetSetting("tmdbApiKey", v)
			rescan = v != ""
		}
	}
	if v, ok, valid := str("metadataLanguage"); ok {
		if !valid || !reLang.MatchString(v) {
			writeError(w, http.StatusBadRequest, "Geçersiz dil kodu (ör. tr-TR)")
			return
		}
		if v != s.Lib.MetadataLanguage() {
			_ = s.St.SetSetting("metadataLanguage", v)
			rescan = true
		}
	}
	if raw, ok := b["scanIntervalMinutes"]; ok {
		var n float64
		if err := json.Unmarshal(raw, &n); err != nil || n < 0 {
			writeError(w, http.StatusBadRequest, "Geçersiz tarama aralığı")
			return
		}
		m := int(n)
		if m > 0 && m < 5 {
			m = 5
		}
		if m > 1440 {
			m = 1440
		}
		_ = s.St.SetSetting("scanIntervalMinutes", strconv.Itoa(m))
		s.Lib.Wake()
	}
	if rescan {
		s.Lib.RequestScan(false)
	}
	writeJSON(w, http.StatusOK, s.settingsJSON())
}

// ---------- folders ----------

func (s *Server) handleAddFolder(w http.ResponseWriter, r *http.Request) {
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
		writeError(w, http.StatusBadRequest, "Klasör yolu tam yol olmalı (ör. /media/disk/Filmler)")
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
	folders, _ := s.St.Folders()
	for _, f := range folders {
		if f.Path == p {
			writeError(w, http.StatusConflict, "Bu klasör zaten kütüphanede")
			return
		}
		if strings.HasPrefix(p+"/", strings.TrimRight(f.Path, "/")+"/") || strings.HasPrefix(f.Path+"/", strings.TrimRight(p, "/")+"/") {
			writeError(w, http.StatusConflict, "Bu klasör, kütüphanedeki \""+f.Name+"\" klasörüyle iç içe")
			return
		}
	}
	name := strings.TrimSpace(b.Name)
	if name == "" {
		name = names.DisplayString(filepath.Base(p))
	}
	f, err := s.St.AddFolder(p, name)
	if err != nil {
		if errors.Is(err, store.ErrExists) {
			writeError(w, http.StatusConflict, "Bu klasör zaten kütüphanede")
			return
		}
		writeError(w, http.StatusInternalServerError, "Klasör eklenemedi")
		return
	}
	log.Printf("folders: added %q (%s)", p, name)
	_ = s.Lib.Reload()
	s.Lib.RequestScan(false)
	writeJSON(w, http.StatusCreated, s.folderJSON(f))
}

func (s *Server) handleDeleteFolder(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		writeError(w, http.StatusNotFound, "Klasör bulunamadı")
		return
	}
	folders, _ := s.St.Folders()
	for _, f := range folders {
		if f.ID != id {
			continue
		}
		if f.IsDefault {
			writeError(w, http.StatusBadRequest, "Varsayılan HomeStream klasörü kaldırılamaz")
			return
		}
		if err := s.St.DeleteFolder(id); err != nil {
			writeError(w, http.StatusInternalServerError, "Klasör kaldırılamadı")
			return
		}
		log.Printf("folders: removed %q", f.Path)
		_ = s.Lib.Reload()
		writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
		return
	}
	writeError(w, http.StatusNotFound, "Klasör bulunamadı")
}

// ---------- fs picker ----------

var fsSkip = map[string]bool{"/proc": true, "/sys": true, "/dev": true, "/run": true}

func (s *Server) handleFS(w http.ResponseWriter, r *http.Request) {
	p := strings.TrimSpace(r.URL.Query().Get("path"))
	if p == "" {
		p = "/"
	}
	if !filepath.IsAbs(p) {
		writeError(w, http.StatusBadRequest, "Geçersiz yol")
		return
	}
	p = filepath.Clean(p)
	des, err := os.ReadDir(p)
	if err != nil {
		writeError(w, http.StatusBadRequest, "Klasör açılamadı")
		return
	}
	type dirJSON struct {
		Name string `json:"name"`
		Path string `json:"path"`
	}
	dirs := []dirJSON{}
	for _, de := range des {
		name := de.Name()
		full := filepath.Join(p, name)
		if strings.HasPrefix(name, ".") || fsSkip[full] || name == "lost+found" {
			continue
		}
		if !de.IsDir() {
			if de.Type()&os.ModeSymlink == 0 {
				continue
			}
			if st, err := os.Stat(full); err != nil || !st.IsDir() {
				continue
			}
		}
		dirs = append(dirs, dirJSON{Name: names.DisplayString(name), Path: full})
	}
	sort.SliceStable(dirs, func(i, j int) bool { return names.NaturalLess(dirs[i].Name, dirs[j].Name) })
	var parent any
	if p != "/" {
		parent = filepath.Dir(p)
	}
	writeJSON(w, http.StatusOK, map[string]any{"path": p, "parent": parent, "dirs": dirs})
}

// ---------- scan ----------

func (s *Server) handleScan(w http.ResponseWriter, r *http.Request) {
	var b struct {
		RefreshMetadata bool `json:"refreshMetadata"`
	}
	_ = readJSON(r, &b)
	s.Lib.RequestScan(b.RefreshMetadata)
	writeJSON(w, http.StatusAccepted, s.Lib.Status())
}

func (s *Server) handleScanStatus(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, s.Lib.Status())
}
