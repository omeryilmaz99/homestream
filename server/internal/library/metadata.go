package library

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"path/filepath"
	"strconv"
	"time"

	"homestream/internal/names"
	"homestream/internal/store"
)

// MetadataLanguage returns the configured TMDB language.
func (l *Library) MetadataLanguage() string {
	if v := l.St.GetSetting("metadataLanguage"); v != "" {
		return v
	}
	return "tr-TR"
}

func (l *Library) metaPath(id, kind string) string {
	return filepath.Join(l.Cfg.DataDir, "meta", id[:2], id+"-"+kind+".jpg")
}

type metaFetcher struct {
	l        *Library
	t        *TMDB
	lang     string
	netErrs  int
	authFail bool
}

var errAbort = errors.New("abort")

// track returns errAbort when the phase should stop.
func (f *metaFetcher) track(err error) error {
	switch {
	case err == nil:
		f.netErrs = 0
	case errors.Is(err, ErrTMDBAuth):
		f.authFail = true
		return errAbort
	case errors.Is(err, context.Canceled):
		return errAbort
	case isNetErr(err):
		f.netErrs++
		if f.netErrs >= 3 {
			return errAbort
		}
	}
	return nil
}

func movieQuery(it *Item, lang string) string {
	return "movie|" + names.Key(it.ParsedTitle) + "|" + strconv.Itoa(it.ParsedYear) + "|" + lang
}

func seriesQuery(it *Item, lang string) string {
	return "tv|" + names.Key(it.ParsedTitle) + "|" + strconv.Itoa(it.ParsedYear) + "|" + lang
}

func episodeQuery(ser store.MetaRow, ep *Item) string {
	return ser.Query + "|" + strconv.Itoa(ser.TMDBID) + "|" + strconv.Itoa(ep.Season) + "x" + strconv.Itoa(ep.Episode)
}

func needsFetch(m store.MetaRow, ok bool, q string, refresh bool) bool {
	if refresh || !ok || m.Query != q {
		return true
	}
	if m.Status == "notfound" {
		return time.Since(time.Unix(m.FetchedAt, 0)) > 72*time.Hour
	}
	if m.Poster != "" && !fileExists(m.Poster) || m.Backdrop != "" && !fileExists(m.Backdrop) {
		return true // image cache was deleted
	}
	return false
}

// fetchMetadata runs the optional TMDB phase.
func (l *Library) fetchMetadata(ctx context.Context, refresh bool) error {
	key := l.St.GetSetting("tmdbApiKey")
	if key == "" {
		return nil
	}
	lang := l.MetadataLanguage()
	f := &metaFetcher{l: l, t: NewTMDB(l.Cfg.TMDBBaseURL, l.Cfg.TMDBImageBase, key), lang: lang}
	snap := l.Snap()
	meta, err := l.St.AllMeta()
	if err != nil {
		return err
	}
	var movies, series []*Item
	for _, it := range snap.Movies {
		m, ok := meta[it.ID]
		if needsFetch(m, ok, movieQuery(it, lang), refresh) {
			movies = append(movies, it)
		}
	}
	for _, it := range snap.Series {
		m, ok := meta[it.ID]
		if needsFetch(m, ok, seriesQuery(it, lang), refresh) {
			series = append(series, it)
			continue
		}
		if ok && m.Status == "ok" {
			for _, ep := range it.Episodes {
				if ep.Episode == 0 {
					continue
				}
				em, eok := meta[ep.ID]
				if !eok || em.Query != episodeQuery(m, ep) {
					series = append(series, it)
					break
				}
			}
		}
	}
	total := len(movies) + len(series)
	if total == 0 {
		return nil
	}
	log.Printf("metadata: fetching %d movies, %d series from TMDB (%s)", len(movies), len(series), lang)
	l.setPhase("Bilgiler indiriliyor", 0, total)
	done := 0
	var phaseErr error
	for _, it := range movies {
		if err := f.track(f.movie(ctx, it)); err != nil {
			phaseErr = err
			break
		}
		done++
		l.setProgress(done)
		l.reloadThrottled()
	}
	if phaseErr == nil {
		for _, it := range series {
			m, ok := meta[it.ID]
			if err := f.track(f.series(ctx, it, m, ok && !needsFetch(m, ok, seriesQuery(it, lang), refresh))); err != nil {
				phaseErr = err
				break
			}
			done++
			l.setProgress(done)
			l.reloadThrottled()
		}
	}
	if phaseErr != nil {
		if f.authFail {
			log.Printf("metadata: TMDB rejected the API key")
			return ErrTMDBAuth
		}
		if ctx.Err() != nil {
			return ctx.Err()
		}
		log.Printf("metadata: TMDB unreachable, will retry on next scan")
		return errors.New("TMDB'ye ulaşılamadı; bir sonraki taramada tekrar denenecek")
	}
	return nil
}

func genresJSON(gs []tmdbGenre) string {
	out := make([]string, 0, len(gs))
	for _, g := range gs {
		if g.Name != "" {
			out = append(out, g.Name)
		}
	}
	b, _ := json.Marshal(out)
	return string(b)
}

// details fetches details with an en-US overview fallback.
func (f *metaFetcher) details(ctx context.Context, kind string, id int) (*tmdbDetails, error) {
	d, err := f.t.Details(ctx, kind, id, f.lang)
	if err != nil {
		return nil, err
	}
	if d.Overview == "" && f.lang != "en-US" {
		if en, err := f.t.Details(ctx, kind, id, "en-US"); err == nil {
			d.Overview = en.Overview
		} else if isNetErr(err) || errors.Is(err, ErrTMDBAuth) {
			return nil, err
		}
	}
	return d, nil
}

func (f *metaFetcher) images(ctx context.Context, id string, d *tmdbDetails, m *store.MetaRow) error {
	if d.PosterPath != "" {
		p := f.l.metaPath(id, "poster")
		if err := f.t.Download(ctx, "w780", d.PosterPath, p); err != nil {
			if isNetErr(err) {
				return err
			}
		} else {
			m.Poster = p
		}
	}
	if d.BackdropPath != "" {
		p := f.l.metaPath(id, "backdrop")
		if err := f.t.Download(ctx, "w1280", d.BackdropPath, p); err != nil {
			if isNetErr(err) {
				return err
			}
		} else {
			m.Backdrop = p
		}
	}
	return nil
}

func (f *metaFetcher) movie(ctx context.Context, it *Item) error {
	q := movieQuery(it, f.lang)
	now := time.Now().Unix()
	id, err := f.t.Search(ctx, "movie", it.ParsedTitle, it.ParsedYear, f.lang)
	if errors.Is(err, errTMDBNotFound) {
		return f.l.St.PutMeta(store.MetaRow{ID: it.ID, Query: q, Status: "notfound", FetchedAt: now})
	}
	if err != nil {
		return err
	}
	d, err := f.details(ctx, "movie", id)
	if err != nil {
		if errors.Is(err, errTMDBNotFound) {
			return f.l.St.PutMeta(store.MetaRow{ID: it.ID, Query: q, Status: "notfound", FetchedAt: now})
		}
		return err
	}
	m := store.MetaRow{ID: it.ID, Query: q, Status: "ok", TMDBID: d.ID, Title: d.Title, OriginalTitle: d.OriginalTitle,
		Overview: d.Overview, Genres: genresJSON(d.Genres), Rating: d.VoteAverage, Year: dateYear(d.ReleaseDate), FetchedAt: now}
	if err := f.images(ctx, it.ID, d, &m); err != nil {
		return err
	}
	return f.l.St.PutMeta(m)
}

func (f *metaFetcher) series(ctx context.Context, it *Item, m store.MetaRow, haveSeries bool) error {
	now := time.Now().Unix()
	if !haveSeries {
		q := seriesQuery(it, f.lang)
		id, err := f.t.Search(ctx, "tv", it.ParsedTitle, it.ParsedYear, f.lang)
		if errors.Is(err, errTMDBNotFound) {
			return f.l.St.PutMeta(store.MetaRow{ID: it.ID, Query: q, Status: "notfound", FetchedAt: now})
		}
		if err != nil {
			return err
		}
		d, err := f.details(ctx, "tv", id)
		if err != nil {
			if errors.Is(err, errTMDBNotFound) {
				return f.l.St.PutMeta(store.MetaRow{ID: it.ID, Query: q, Status: "notfound", FetchedAt: now})
			}
			return err
		}
		m = store.MetaRow{ID: it.ID, Query: q, Status: "ok", TMDBID: d.ID, Title: d.Name, OriginalTitle: d.OriginalName,
			Overview: d.Overview, Genres: genresJSON(d.Genres), Rating: d.VoteAverage, Year: dateYear(d.FirstAirDate), FetchedAt: now}
		if err := f.images(ctx, it.ID, d, &m); err != nil {
			return err
		}
		if err := f.l.St.PutMeta(m); err != nil {
			return err
		}
	}
	// episodes, season by season
	bySeason := map[int][]*Item{}
	for _, ep := range it.Episodes {
		if ep.Episode > 0 {
			bySeason[ep.Season] = append(bySeason[ep.Season], ep)
		}
	}
	for season, eps := range bySeason {
		s, err := f.t.Season(ctx, m.TMDBID, season, f.lang)
		if errors.Is(err, errTMDBNotFound) {
			for _, ep := range eps {
				_ = f.l.St.PutMeta(store.MetaRow{ID: ep.ID, Query: episodeQuery(m, ep), Status: "notfound", FetchedAt: now})
			}
			continue
		}
		if err != nil {
			return err
		}
		byNum := map[int]tmdbEpisode{}
		missingOverview := false
		for _, e := range s.Episodes {
			byNum[e.EpisodeNumber] = e
		}
		for _, ep := range eps {
			if e, ok := byNum[ep.Episode]; ok && e.Overview == "" {
				missingOverview = true
			}
		}
		if missingOverview && f.lang != "en-US" {
			if en, err := f.t.Season(ctx, m.TMDBID, season, "en-US"); err == nil {
				for _, e := range en.Episodes {
					if x, ok := byNum[e.EpisodeNumber]; ok && x.Overview == "" {
						x.Overview = e.Overview
						byNum[e.EpisodeNumber] = x
					}
				}
			}
		}
		for _, ep := range eps {
			e, ok := byNum[ep.Episode]
			if !ok {
				_ = f.l.St.PutMeta(store.MetaRow{ID: ep.ID, Query: episodeQuery(m, ep), Status: "notfound", FetchedAt: now})
				continue
			}
			em := store.MetaRow{ID: ep.ID, Query: episodeQuery(m, ep), Status: "ok", TMDBID: m.TMDBID, Title: e.Name,
				Overview: e.Overview, Rating: e.VoteAverage, FetchedAt: now}
			if e.StillPath != "" {
				p := f.l.metaPath(ep.ID, "still")
				if err := f.t.Download(ctx, "original", e.StillPath, p); err == nil {
					em.Backdrop = p
				} else if isNetErr(err) {
					return err
				}
			}
			if err := f.l.St.PutMeta(em); err != nil {
				return err
			}
		}
	}
	return nil
}
