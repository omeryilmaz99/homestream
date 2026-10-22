package music

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"image"
	"io"
	"net/http"
	"net/url"
	"os"
	"regexp"
	"strings"
	"sync"
	"time"

	"homestream/internal/names"
)

// onlineCovers looks covers up on Deezer and iTunes (no API keys needed).
type onlineCovers struct {
	itunes, deezer string
	client         *http.Client

	mu        sync.Mutex
	last      time.Time
	lastApple time.Time
}

func newOnline(itunes, deezer string) *onlineCovers {
	if itunes == "" {
		itunes = "https://itunes.apple.com"
	}
	if deezer == "" {
		deezer = "https://api.deezer.com"
	}
	return &onlineCovers{itunes: strings.TrimRight(itunes, "/"), deezer: strings.TrimRight(deezer, "/"),
		client: &http.Client{Timeout: 12 * time.Second}}
}

// wait spaces requests out (Deezer: 50 per 5 s, iTunes: ~20 per minute).
func (o *onlineCovers) wait(ctx context.Context, apple bool) error {
	o.mu.Lock()
	gap := 400 * time.Millisecond
	next := o.last.Add(gap)
	if apple {
		if n := o.lastApple.Add(3500 * time.Millisecond); n.After(next) {
			next = n
		}
	}
	now := time.Now()
	if next.Before(now) {
		next = now
	}
	o.last = next
	if apple {
		o.lastApple = next
	}
	o.mu.Unlock()
	select {
	case <-time.After(time.Until(next)):
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

var errHTTP = errors.New("http")

func (o *onlineCovers) getJSON(ctx context.Context, u string, v any) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return err
	}
	req.Header.Set("User-Agent", "HomeStream/1.0 (home music server)")
	resp, err := o.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("%w %d", errHTTP, resp.StatusCode)
	}
	return json.NewDecoder(io.LimitReader(resp.Body, 4<<20)).Decode(v)
}

var editionRe = regexp.MustCompile(`(?i)\s*[\(\[][^\)\]]*(deluxe|edition|remaster|version|single|ep|bonus|expanded|anniversary)[^\)\]]*[\)\]]|\s+-\s+(single|ep)$`)

func cleanForMatch(s string) string {
	return names.Key(editionRe.ReplaceAllString(s, ""))
}

func similar(a, b string) bool {
	a, b = cleanForMatch(a), cleanForMatch(b)
	if a == "" || b == "" {
		return false
	}
	return a == b || strings.HasPrefix(a, b) || strings.HasPrefix(b, a)
}

func artistMatch(want, got string) bool {
	w, g := names.Key(want), names.Key(got)
	if w == "" || g == "" {
		return false
	}
	return w == g || strings.Contains(g, w) || strings.Contains(w, g)
}

// find returns an image URL ("" when nothing matched). An error means the
// services could not be reached.
func (o *onlineCovers) find(ctx context.Context, artist, album, title string) (string, error) {
	if artist == "" || (album == "" && title == "") {
		return "", nil
	}
	reached := false
	var lastErr error
	if u, err := o.deezerFind(ctx, artist, album, title); err == nil {
		reached = true
		if u != "" {
			return u, nil
		}
	} else {
		lastErr = err
	}
	if u, err := o.itunesFind(ctx, artist, album, title); err == nil {
		reached = true
		if u != "" {
			return u, nil
		}
	} else if lastErr == nil {
		lastErr = err
	}
	if reached {
		return "", nil
	}
	return "", lastErr
}

func (o *onlineCovers) deezerFind(ctx context.Context, artist, album, title string) (string, error) {
	if err := o.wait(ctx, false); err != nil {
		return "", err
	}
	var res struct {
		Data []struct {
			Title   string `json:"title"`
			CoverXL string `json:"cover_xl"`
			Artist  struct {
				Name string `json:"name"`
			} `json:"artist"`
			Album struct {
				Title   string `json:"title"`
				CoverXL string `json:"cover_xl"`
			} `json:"album"`
		} `json:"data"`
	}
	var u string
	if album != "" {
		u = o.deezer + "/search/album?limit=10&q=" + url.QueryEscape(fmt.Sprintf(`artist:"%s" album:"%s"`, artist, album))
	} else {
		u = o.deezer + "/search/track?limit=10&q=" + url.QueryEscape(fmt.Sprintf(`artist:"%s" track:"%s"`, artist, title))
	}
	if err := o.getJSON(ctx, u, &res); err != nil {
		return "", err
	}
	for _, d := range res.Data {
		if !artistMatch(artist, d.Artist.Name) {
			continue
		}
		if album != "" && similar(album, d.Title) && d.CoverXL != "" {
			return d.CoverXL, nil
		}
		if album == "" && similar(title, d.Title) && d.Album.CoverXL != "" {
			return d.Album.CoverXL, nil
		}
	}
	return "", nil
}

func (o *onlineCovers) itunesFind(ctx context.Context, artist, album, title string) (string, error) {
	if err := o.wait(ctx, true); err != nil {
		return "", err
	}
	var res struct {
		Results []struct {
			ArtistName     string `json:"artistName"`
			CollectionName string `json:"collectionName"`
			TrackName      string `json:"trackName"`
			Artwork        string `json:"artworkUrl100"`
		} `json:"results"`
	}
	entity, term := "album", artist+" "+album
	if album == "" {
		entity, term = "song", artist+" "+title
	}
	u := o.itunes + "/search?country=TR&limit=10&media=music&entity=" + entity + "&term=" + url.QueryEscape(term)
	if err := o.getJSON(ctx, u, &res); err != nil {
		return "", err
	}
	for _, r := range res.Results {
		if r.Artwork == "" || !artistMatch(artist, r.ArtistName) {
			continue
		}
		if (album != "" && similar(album, r.CollectionName)) || (album == "" && similar(title, r.TrackName)) {
			return strings.Replace(r.Artwork, "100x100bb", "1000x1000bb", 1), nil
		}
	}
	return "", nil
}

// download saves an image after checking that it decodes.
func (o *onlineCovers) download(ctx context.Context, u, out string) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return err
	}
	req.Header.Set("User-Agent", "HomeStream/1.0 (home music server)")
	resp, err := o.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("%w %d", errHTTP, resp.StatusCode)
	}
	tmp := out + ".tmp"
	f, err := os.Create(tmp)
	if err != nil {
		return err
	}
	_, err = io.Copy(f, io.LimitReader(resp.Body, 8<<20))
	f.Close()
	if err != nil {
		os.Remove(tmp)
		return err
	}
	chk, err := os.Open(tmp)
	if err != nil {
		os.Remove(tmp)
		return err
	}
	_, _, err = image.DecodeConfig(chk)
	chk.Close()
	if err != nil {
		os.Remove(tmp)
		return fmt.Errorf("geçersiz görsel: %w", err)
	}
	return os.Rename(tmp, out)
}
