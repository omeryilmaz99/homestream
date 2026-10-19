package library

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"homestream/internal/names"
)

// Errors returned by the TMDB client.
var (
	ErrTMDBAuth     = errors.New("TMDB API anahtarı geçersiz")
	errTMDBNotFound = errors.New("tmdb: not found")
)

// TMDB is a small rate-limited TMDB v3 client (api key or v4 bearer token).
type TMDB struct {
	base, imgBase string
	key           string
	bearer        bool
	client        *http.Client
	interval      time.Duration

	mu   sync.Mutex
	last time.Time
}

// NewTMDB creates a client. Keys that look like JWTs (v4 read access tokens)
// are sent as bearer tokens; others as api_key query parameter.
func NewTMDB(base, imgBase, key string) *TMDB {
	key = strings.TrimSpace(key)
	return &TMDB{
		base: strings.TrimRight(base, "/"), imgBase: strings.TrimRight(imgBase, "/"),
		key: key, bearer: strings.HasPrefix(key, "eyJ") || len(key) > 64,
		client:   &http.Client{Timeout: 10 * time.Second},
		interval: 120 * time.Millisecond,
	}
}

func (t *TMDB) wait(ctx context.Context) error {
	t.mu.Lock()
	next := t.last.Add(t.interval)
	now := time.Now()
	if next.Before(now) {
		next = now
	}
	t.last = next
	t.mu.Unlock()
	if d := time.Until(next); d > 0 {
		select {
		case <-time.After(d):
		case <-ctx.Done():
			return ctx.Err()
		}
	}
	return nil
}

func (t *TMDB) get(ctx context.Context, p string, q url.Values, out any) error {
	if q == nil {
		q = url.Values{}
	}
	if !t.bearer {
		q.Set("api_key", t.key)
	}
	u := t.base + p + "?" + q.Encode()
	for attempt := 0; attempt < 3; attempt++ {
		if err := t.wait(ctx); err != nil {
			return err
		}
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
		if err != nil {
			return err
		}
		req.Header.Set("Accept", "application/json")
		if t.bearer {
			req.Header.Set("Authorization", "Bearer "+t.key)
		}
		resp, err := t.client.Do(req)
		if err != nil {
			return err
		}
		body, err := io.ReadAll(io.LimitReader(resp.Body, 8<<20))
		resp.Body.Close()
		if err != nil {
			return err
		}
		switch {
		case resp.StatusCode == http.StatusTooManyRequests:
			d, _ := strconv.Atoi(resp.Header.Get("Retry-After"))
			if d <= 0 || d > 10 {
				d = 2
			}
			select {
			case <-time.After(time.Duration(d) * time.Second):
			case <-ctx.Done():
				return ctx.Err()
			}
			continue
		case resp.StatusCode == http.StatusUnauthorized:
			return ErrTMDBAuth
		case resp.StatusCode == http.StatusNotFound:
			return errTMDBNotFound
		case resp.StatusCode >= 300:
			return fmt.Errorf("tmdb: HTTP %d", resp.StatusCode)
		}
		return json.Unmarshal(body, out)
	}
	return fmt.Errorf("tmdb: rate limited")
}

type tmdbGenre struct {
	Name string `json:"name"`
}

type tmdbSearchResult struct {
	ID            int     `json:"id"`
	Title         string  `json:"title"`
	OriginalTitle string  `json:"original_title"`
	Name          string  `json:"name"`
	OriginalName  string  `json:"original_name"`
	ReleaseDate   string  `json:"release_date"`
	FirstAirDate  string  `json:"first_air_date"`
	Popularity    float64 `json:"popularity"`
}

type tmdbDetails struct {
	ID            int         `json:"id"`
	Title         string      `json:"title"`
	OriginalTitle string      `json:"original_title"`
	Name          string      `json:"name"`
	OriginalName  string      `json:"original_name"`
	Overview      string      `json:"overview"`
	Genres        []tmdbGenre `json:"genres"`
	VoteAverage   float64     `json:"vote_average"`
	PosterPath    string      `json:"poster_path"`
	BackdropPath  string      `json:"backdrop_path"`
	ReleaseDate   string      `json:"release_date"`
	FirstAirDate  string      `json:"first_air_date"`
}

type tmdbEpisode struct {
	EpisodeNumber int     `json:"episode_number"`
	SeasonNumber  int     `json:"season_number"`
	Name          string  `json:"name"`
	Overview      string  `json:"overview"`
	StillPath     string  `json:"still_path"`
	VoteAverage   float64 `json:"vote_average"`
}

type tmdbSeason struct {
	Episodes []tmdbEpisode `json:"episodes"`
}

func dateYear(s string) int {
	if len(s) >= 4 {
		y, _ := strconv.Atoi(s[:4])
		return y
	}
	return 0
}

// Search finds the best matching movie ("movie") or series ("tv").
func (t *TMDB) Search(ctx context.Context, kind, title string, year int, lang string) (int, error) {
	try := func(withYear bool) ([]tmdbSearchResult, error) {
		q := url.Values{"query": {title}, "language": {lang}, "include_adult": {"false"}}
		if withYear && year > 0 {
			if kind == "movie" {
				q.Set("year", strconv.Itoa(year))
			} else {
				q.Set("first_air_date_year", strconv.Itoa(year))
			}
		}
		var res struct {
			Results []tmdbSearchResult `json:"results"`
		}
		if err := t.get(ctx, "/search/"+kind, q, &res); err != nil {
			return nil, err
		}
		return res.Results, nil
	}
	results, err := try(true)
	if err != nil {
		return 0, err
	}
	best := pickResult(results, title, year)
	if best < 0 && year > 0 {
		if results, err = try(false); err != nil {
			return 0, err
		}
		best = pickResult(results, title, year)
	}
	if best < 0 {
		return 0, errTMDBNotFound
	}
	return results[best].ID, nil
}

func similarity(a, b string) float64 {
	a, b = names.Fold(a), names.Fold(b)
	if a == "" || b == "" {
		return 0
	}
	if a == b || strings.ReplaceAll(a, " ", "") == strings.ReplaceAll(b, " ", "") {
		return 1
	}
	if strings.Contains(a, b) || strings.Contains(b, a) {
		return 0.75
	}
	ta, tb := strings.Fields(a), strings.Fields(b)
	set := map[string]bool{}
	for _, x := range ta {
		set[x] = true
	}
	inter := 0
	for _, x := range tb {
		if set[x] {
			inter++
		}
	}
	union := len(ta) + len(tb) - inter
	if union == 0 {
		return 0
	}
	return float64(inter) / float64(union)
}

func pickResult(results []tmdbSearchResult, title string, year int) int {
	best, bestScore := -1, 0.0
	for i, r := range results {
		if i >= 10 {
			break
		}
		sim := 0.0
		for _, n := range []string{r.Title, r.OriginalTitle, r.Name, r.OriginalName} {
			if s := similarity(title, n); s > sim {
				sim = s
			}
		}
		if sim < 0.5 {
			continue
		}
		score := sim - 0.02*float64(i)
		ry := dateYear(r.ReleaseDate)
		if ry == 0 {
			ry = dateYear(r.FirstAirDate)
		}
		if year > 0 && ry > 0 {
			switch d := ry - year; {
			case d == 0:
				score += 0.5
			case d == 1 || d == -1:
				score += 0.3
			default:
				score -= 0.3
			}
		}
		if best < 0 || score > bestScore {
			best, bestScore = i, score
		}
	}
	return best
}

// Details fetches movie or tv details in lang.
func (t *TMDB) Details(ctx context.Context, kind string, id int, lang string) (*tmdbDetails, error) {
	var d tmdbDetails
	err := t.get(ctx, "/"+kind+"/"+strconv.Itoa(id), url.Values{"language": {lang}}, &d)
	return &d, err
}

// Season fetches one season of a series.
func (t *TMDB) Season(ctx context.Context, id, season int, lang string) (*tmdbSeason, error) {
	var s tmdbSeason
	err := t.get(ctx, "/tv/"+strconv.Itoa(id)+"/season/"+strconv.Itoa(season), url.Values{"language": {lang}}, &s)
	return &s, err
}

// Download saves an image (size like "w780") to dest.
func (t *TMDB) Download(ctx context.Context, size, imgPath, dest string) error {
	if imgPath == "" {
		return errTMDBNotFound
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, t.imgBase+"/"+size+imgPath, nil)
	if err != nil {
		return err
	}
	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("tmdb image: HTTP %d", resp.StatusCode)
	}
	if err := os.MkdirAll(filepath.Dir(dest), 0o755); err != nil {
		return err
	}
	tmp := dest + ".tmp"
	f, err := os.Create(tmp)
	if err != nil {
		return err
	}
	_, err = io.Copy(f, io.LimitReader(resp.Body, 30<<20))
	if cerr := f.Close(); err == nil {
		err = cerr
	}
	if err != nil {
		os.Remove(tmp)
		return err
	}
	return os.Rename(tmp, dest)
}

// isNetErr reports errors that indicate TMDB is unreachable.
func isNetErr(err error) bool {
	if err == nil || errors.Is(err, errTMDBNotFound) || errors.Is(err, ErrTMDBAuth) || errors.Is(err, context.Canceled) {
		return false
	}
	var ne net.Error
	if errors.As(err, &ne) {
		return true
	}
	var ue *url.Error
	return errors.As(err, &ue) || strings.Contains(err.Error(), "HTTP 5")
}
