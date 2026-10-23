package music

import (
	"bytes"
	"context"
	"fmt"
	"image"
	"image/color"
	"image/jpeg"
	_ "image/png" // folder images
	"log"
	"math"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"golang.org/x/image/draw"
	_ "golang.org/x/image/webp" // folder images

	"homestream/internal/names"
)

// CoverWidths are the sizes clients may request (square images).
var CoverWidths = []int{96, 160, 320, 480, 640, 1000}

func snapCover(w int) int {
	if w <= 0 {
		return 480
	}
	for _, x := range CoverWidths {
		if x >= w {
			return x
		}
	}
	return CoverWidths[len(CoverWidths)-1]
}

// source kinds
const (
	srcDir         = "dir"
	srcEmbedded    = "emb"
	srcFrame       = "frame"
	srcWeb         = "web"
	srcPlaceholder = "ph"
)

type coverSrc struct {
	kind  string
	path  string // dir/web: the image file
	track *Track // emb/frame: the file to extract from
	seed  string // placeholder seed
	key   string // stable description, used for versions and cache names
}

// Covers resolves, extracts, renders and serves cover images.
type Covers struct {
	l      *Library
	dir    string
	srcDir string
	outDir string

	sfMu  sync.Mutex
	calls map[string]*sfCall

	mu     sync.Mutex
	failed map[string]time.Time // extraction failures by source key
	web    map[string]coverRow  // internet lookups by lookup key

	extractSem chan struct{}
	renderSem  chan struct{}
	online     *onlineCovers
}

type sfCall struct {
	wg  sync.WaitGroup
	val string
	err error
}

func newCovers(l *Library, dir string) *Covers {
	c := &Covers{
		l: l, dir: dir, srcDir: filepath.Join(dir, "src"), outDir: filepath.Join(dir, "r"),
		calls: map[string]*sfCall{}, failed: map[string]time.Time{}, web: allCoverRows(l.db),
		extractSem: make(chan struct{}, 2), renderSem: make(chan struct{}, 3),
	}
	c.online = newOnline(l.cfg.ITunesURL, l.cfg.DeezerURL)
	_ = os.MkdirAll(c.srcDir, 0o755)
	_ = os.MkdirAll(c.outDir, 0o755)
	return c
}

func (c *Covers) do(key string, fn func() (string, error)) (string, error) {
	c.sfMu.Lock()
	if call, ok := c.calls[key]; ok {
		c.sfMu.Unlock()
		call.wg.Wait()
		return call.val, call.err
	}
	call := &sfCall{}
	call.wg.Add(1)
	c.calls[key] = call
	c.sfMu.Unlock()
	func() {
		defer func() {
			if r := recover(); r != nil {
				call.err = fmt.Errorf("panic: %v", r)
			}
		}()
		call.val, call.err = fn()
	}()
	call.wg.Done()
	c.sfMu.Lock()
	delete(c.calls, key)
	c.sfMu.Unlock()
	return call.val, call.err
}

func (c *Covers) forgetLookups() {
	c.mu.Lock()
	c.web = allCoverRows(c.l.db)
	c.failed = map[string]time.Time{}
	c.mu.Unlock()
}

func (c *Covers) onlineEnabled() bool {
	return c.l.cfg.GetSetting("music.onlineCovers") != "0"
}

func (c *Covers) isFailed(key string) bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	t, ok := c.failed[key]
	return ok && time.Since(t) < 12*time.Hour
}

func (c *Covers) webRow(key string) (coverRow, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	r, ok := c.web[key]
	return r, ok
}

func embSrc(t *Track) coverSrc {
	k := "emb:" + t.ID + ":" + strconv.FormatInt(t.Size, 10) + ":" + strconv.FormatInt(t.MTime, 10)
	return coverSrc{kind: srcEmbedded, track: t, key: k}
}

func frameSrc(t *Track) coverSrc {
	k := "frame:" + t.ID + ":" + strconv.FormatInt(t.Size, 10) + ":" + strconv.FormatInt(t.MTime, 10)
	return coverSrc{kind: srcFrame, track: t, key: k}
}

func albumLookupKey(al *Album) string {
	if al.Artist == "" || al.Artist == VariousArtists || al.Artist == UnknownArtist {
		return ""
	}
	return "a:" + names.Key(primaryArtist(al.Artist)) + "|" + names.Key(al.Title)
}

func trackLookupKey(t *Track) string {
	if t.ArtistName == "" || t.ArtistName == UnknownArtist || t.Title == "" {
		return ""
	}
	return "t:" + names.Key(t.ArtistName) + "|" + names.Key(t.Title)
}

// usable tells whether a source can be used right now (nothing is extracted).
func (c *Covers) usable(s coverSrc) bool {
	switch s.kind {
	case srcEmbedded, srcFrame:
		return c.l.cfg.FFmpeg != "" && !c.isFailed(s.key)
	}
	return true
}

func (c *Covers) webSrc(key string) (coverSrc, bool) {
	if key == "" {
		return coverSrc{}, false
	}
	if r, ok := c.webRow(key); ok && r.Status == "ok" && r.Path != "" {
		return coverSrc{kind: srcWeb, path: r.Path, key: "web:" + r.Path}, true
	}
	return coverSrc{}, false
}

// albumSource picks the cover source of an album.
func (c *Covers) albumSource(al *Album) coverSrc {
	for _, t := range al.Tracks {
		if t.DirCover != "" {
			return coverSrc{kind: srcDir, path: t.DirCover, key: "dir:" + t.DirCover}
		}
	}
	for _, t := range al.Tracks {
		if t.HasPic {
			if s := embSrc(t); c.usable(s) {
				return s
			}
		}
	}
	for _, t := range al.Tracks {
		if t.IsVideo {
			if s := frameSrc(t); c.usable(s) {
				return s
			}
		}
	}
	if s, ok := c.webSrc(albumLookupKey(al)); ok {
		return s
	}
	if len(al.Tracks) > 0 {
		if s, ok := c.webSrc(trackLookupKey(al.Tracks[0])); ok {
			return s
		}
	}
	return coverSrc{kind: srcPlaceholder, seed: al.ID, key: "ph:" + al.ID}
}

// trackOwnSource is the track's own cover when it should not share the album's.
func (c *Covers) trackOwnSource(t *Track) (coverSrc, bool) {
	if t.HasPic {
		if s := embSrc(t); c.usable(s) {
			return s, true
		}
	}
	if t.IsVideo {
		if s := frameSrc(t); c.usable(s) {
			return s, true
		}
	}
	return coverSrc{}, false
}

// CoverOwner returns the id whose cover a track shows: its album's id, or
// its own id when it has its own picture (videos, compilations, singles).
func (c *Covers) CoverOwner(t *Track) string {
	al := t.AlbumRef
	if al == nil {
		return t.ID
	}
	if t.IsVideo || (t.HasPic && al.Artist == VariousArtists) {
		if _, ok := c.trackOwnSource(t); ok {
			return t.ID
		}
	}
	return al.ID
}

func (c *Covers) trackSource(t *Track) coverSrc {
	if owner := c.CoverOwner(t); owner != t.ID && t.AlbumRef != nil {
		return c.albumSource(t.AlbumRef)
	}
	if s, ok := c.trackOwnSource(t); ok {
		return s
	}
	if t.DirCover != "" {
		return coverSrc{kind: srcDir, path: t.DirCover, key: "dir:" + t.DirCover}
	}
	if s, ok := c.webSrc(trackLookupKey(t)); ok {
		return s
	}
	return coverSrc{kind: srcPlaceholder, seed: t.ID, key: "ph:" + t.ID}
}

// sourceFor resolves any id (track, album or artist).
func (c *Covers) sourceFor(s *Snapshot, id string) (coverSrc, bool) {
	if al := s.Albums[id]; al != nil {
		return c.albumSource(al), true
	}
	if t := s.Tracks[id]; t != nil {
		return c.trackSource(t), true
	}
	if a := s.Artists[id]; a != nil {
		if len(a.Albums) > 0 {
			return c.albumSource(a.Albums[0]), true
		}
		if len(a.Tracks) > 0 {
			return c.trackSource(a.Tracks[0]), true
		}
		return coverSrc{kind: srcPlaceholder, seed: a.ID, key: "ph:" + a.ID}, true
	}
	return coverSrc{}, false
}

// placeholderVersion changes when the generated cover design changes, so
// apps and the disk cache pick up the new pictures.
const placeholderVersion = "art3"

// Version is a short token that changes when the cover of id changes.
func (c *Covers) Version(s *Snapshot, id string) string {
	src, ok := c.sourceFor(s, id)
	if !ok {
		return "0"
	}
	if src.kind == srcPlaceholder {
		return hashID("v", src.key+"|"+placeholderVersion)[:6]
	}
	return hashID("v", src.key+"|v2")[:6]
}

// URL is the API path of the cover of id (with a cache-busting version).
func (c *Covers) URL(s *Snapshot, id string) string {
	return "/api/music/covers/" + id + "?v=" + c.Version(s, id)
}

// IsGenerated tells whether id would get a generated placeholder.
func (c *Covers) IsGenerated(s *Snapshot, id string) bool {
	src, ok := c.sourceFor(s, id)
	return !ok || src.kind == srcPlaceholder
}

// file returns the image file of a source, extracting it when needed.
func (c *Covers) file(ctx context.Context, src coverSrc) string {
	switch src.kind {
	case srcDir, srcWeb:
		if fileExists(src.path) {
			return src.path
		}
		return ""
	case srcEmbedded, srcFrame:
		out := filepath.Join(c.srcDir, hashID("src", src.key)+".jpg")
		if fileExists(out) {
			return out
		}
		if !c.usable(src) {
			return ""
		}
		p, err := c.do("x:"+out, func() (string, error) {
			if fileExists(out) {
				return out, nil
			}
			select {
			case c.extractSem <- struct{}{}:
			case <-ctx.Done():
				return "", ctx.Err()
			}
			defer func() { <-c.extractSem }()
			return out, c.extract(src, out)
		})
		if err != nil {
			if ctx.Err() == nil {
				c.mu.Lock()
				c.failed[src.key] = time.Now()
				c.mu.Unlock()
				log.Printf("music: cover of %s: %v", src.track.RelPath, err)
			}
			return ""
		}
		return p
	}
	return ""
}

func (c *Covers) extract(src coverSrc, out string) error {
	t := src.track
	tmp := out + ".tmp"
	defer os.Remove(tmp)
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()
	run := func(ts float64) error {
		args := []string{"-nostdin", "-hide_banner", "-loglevel", "error"}
		if ts > 0 {
			args = append(args, "-ss", strconv.FormatFloat(ts, 'f', 2, 64))
		}
		args = append(args, "-i", t.AbsPath, "-an", "-map", "0:v:0", "-frames:v", "1",
			"-vf", "scale=trunc(iw*sar/2)*2:ih,setsar=1,scale='min(1280,iw)':-2", "-q:v", "2", "-f", "image2", "-y", tmp)
		cmd := lowPrio(ctx, c.l.cfg.Nice, "15", c.l.cfg.FFmpeg, args...)
		var stderr bytes.Buffer
		cmd.Stderr = &stderr
		if err := cmd.Run(); err != nil {
			msg := strings.TrimSpace(stderr.String())
			if len(msg) > 200 {
				msg = msg[:200]
			}
			return fmt.Errorf("%v: %s", err, msg)
		}
		if st, err := os.Stat(tmp); err != nil || st.Size() == 0 {
			return fmt.Errorf("ffmpeg görsel üretmedi")
		}
		return nil
	}
	ts := 0.0
	if src.kind == srcFrame {
		ts = 20
		if t.Duration > 0 {
			ts = math.Min(t.Duration*0.3, 60)
		}
	}
	err := run(ts)
	if err != nil && ts > 0 {
		err = run(0) // shorter than we thought
	}
	if err != nil {
		return err
	}
	return os.Rename(tmp, out)
}

// Serve writes the cover of id at the requested width.
func (c *Covers) Serve(w http.ResponseWriter, r *http.Request, id string, width int) {
	s := c.l.Snap()
	src, ok := c.sourceFor(s, id)
	if !ok {
		// unknown ids (e.g. a deleted song in a playlist) still get a picture
		src = coverSrc{kind: srcPlaceholder, seed: id, key: "ph:" + id}
	}
	width = snapCover(width)
	file := ""
	if src.kind != srcPlaceholder {
		file = c.file(r.Context(), src)
		if file == "" {
			// fall back to the next best source (the failure is remembered)
			if src2, ok := c.sourceFor(s, id); ok && src2.key != src.key {
				src = src2
				if src.kind != srcPlaceholder {
					file = c.file(r.Context(), src)
				}
			}
		}
	}
	key := hashID("ph", src.key+"|"+strconv.Itoa(width)+"|"+placeholderVersion)
	if file != "" {
		if st, err := os.Stat(file); err == nil {
			key = hashID("img", fmt.Sprintf("%s|%d|%d|%d", file, st.Size(), st.ModTime().UnixNano(), width))
		} else {
			file = ""
		}
	}
	seed := src.seed
	if seed == "" {
		seed = id
	}
	safeID := id
	if len(safeID) < 2 {
		safeID = "__"
	}
	prefix := fmt.Sprintf("%s-%d-", safeID, width)
	cachePath := filepath.Join(c.outDir, safeID[:2], prefix+key+".jpg")
	if !fileExists(cachePath) {
		_, err := c.do("r:"+cachePath, func() (string, error) {
			if fileExists(cachePath) {
				return cachePath, nil
			}
			c.renderSem <- struct{}{}
			defer func() { <-c.renderSem }()
			data, err := renderCover(file, seed, width)
			if err != nil {
				log.Printf("music: render cover %s: %v (placeholder)", id, err)
				if data, err = renderCover("", seed, width); err != nil {
					return "", err
				}
			}
			if err := os.MkdirAll(filepath.Dir(cachePath), 0o755); err != nil {
				return "", err
			}
			tmp := cachePath + ".tmp"
			if err := os.WriteFile(tmp, data, 0o644); err != nil {
				return "", err
			}
			if err := os.Rename(tmp, cachePath); err != nil {
				return "", err
			}
			if old, _ := filepath.Glob(filepath.Join(filepath.Dir(cachePath), prefix+"*.jpg")); len(old) > 1 {
				for _, o := range old {
					if o != cachePath {
						_ = os.Remove(o)
					}
				}
			}
			return cachePath, nil
		})
		if err != nil {
			data, err2 := renderCover("", seed, width)
			if err2 != nil {
				http.Error(w, `{"error":"Kapak oluşturulamadı"}`, http.StatusInternalServerError)
				return
			}
			w.Header().Set("Content-Type", "image/jpeg")
			w.Header().Set("Cache-Control", "no-cache")
			_, _ = w.Write(data)
			return
		}
	}
	f, err := os.Open(cachePath)
	if err != nil {
		http.Error(w, `{"error":"Kapak okunamadı"}`, http.StatusInternalServerError)
		return
	}
	defer f.Close()
	st, _ := f.Stat()
	w.Header().Set("Content-Type", "image/jpeg")
	w.Header().Set("Cache-Control", "public, max-age=604800")
	w.Header().Set("ETag", `"`+key+`"`)
	if src.kind == srcPlaceholder {
		w.Header().Set("X-Cover-Generated", "1")
	}
	http.ServeContent(w, r, "", st.ModTime(), f)
}

// renderCover produces a square JPEG from an image file, or a placeholder.
func renderCover(src, seed string, width int) ([]byte, error) {
	var out image.Image
	if src != "" {
		f, err := os.Open(src)
		if err != nil {
			return nil, err
		}
		img, _, err := image.Decode(f)
		f.Close()
		if err != nil {
			return nil, err
		}
		b := img.Bounds()
		if b.Dx() < 8 || b.Dy() < 8 {
			return nil, fmt.Errorf("görsel çok küçük")
		}
		crop := b
		if b.Dx() > b.Dy() {
			x0 := b.Min.X + (b.Dx()-b.Dy())/2
			crop = image.Rect(x0, b.Min.Y, x0+b.Dy(), b.Max.Y)
		} else if b.Dy() > b.Dx() {
			y0 := b.Min.Y + (b.Dy()-b.Dx())/2
			crop = image.Rect(b.Min.X, y0, b.Max.X, y0+b.Dx())
		}
		w := min(width, crop.Dx()) // never upscale
		dst := image.NewRGBA(image.Rect(0, 0, w, w))
		draw.CatmullRom.Scale(dst, dst.Bounds(), img, crop, draw.Src, nil)
		out = dst
	} else {
		out = Placeholder(seed, width)
	}
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, out, &jpeg.Options{Quality: 88}); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

// ---------- placeholder art ----------

// Sky top, middle and horizon glow. The app uses the same list for covers
// it cannot load, so both draw the same pictures.
var palettes = [][3]color.RGBA{
	{rgb(0x1B, 0x1A, 0x4A), rgb(0x6A, 0x4F, 0xD8), rgb(0xF0, 0x8B, 0xC0)},
	{rgb(0x0F, 0x1C, 0x4D), rgb(0x3B, 0x5B, 0xDB), rgb(0xB7, 0x8C, 0xF5)},
	{rgb(0x2A, 0x10, 0x36), rgb(0x9B, 0x3F, 0xA8), rgb(0xFF, 0x9A, 0x7A)},
	{rgb(0x0E, 0x23, 0x40), rgb(0x2F, 0x7F, 0xA8), rgb(0x9E, 0xE6, 0xE0)},
	{rgb(0x24, 0x11, 0x4A), rgb(0x8E, 0x44, 0xF0), rgb(0xFF, 0xB8, 0x6B)},
	{rgb(0x1A, 0x0F, 0x2E), rgb(0xC2, 0x47, 0x7F), rgb(0xFF, 0xC2, 0xD6)},
	{rgb(0x12, 0x1A, 0x3A), rgb(0x5A, 0x6C, 0xF0), rgb(0xE6, 0xA3, 0xFF)},
	{rgb(0x30, 0x16, 0x34), rgb(0xE0, 0x56, 0x7A), rgb(0xFF, 0xD0, 0x8A)},
}

func rgb(r, g, b uint8) color.RGBA { return color.RGBA{r, g, b, 255} }

func seedOf(s string) uint32 {
	var h uint32 = 2166136261
	for i := 0; i < len(s); i++ {
		h ^= uint32(s[i])
		h *= 16777619
	}
	return h
}

func smooth(e0, e1, x float64) float64 {
	t := math.Max(0, math.Min(1, (x-e0)/(e1-e0)))
	return t * t * (3 - 2*t)
}

func mix(a, b, t float64) float64 { return a + (b-a)*t }

type fcol [3]float64

func fc(c color.RGBA) fcol { return fcol{float64(c.R), float64(c.G), float64(c.B)} }

func lerpC(a, b fcol, t float64) fcol {
	return fcol{mix(a[0], b[0], t), mix(a[1], b[1], t), mix(a[2], b[2], t)}
}

// Placeholder draws an abstract gradient picture (misty mountains or silk
// waves) picked by seed.
func Placeholder(seed string, size int) image.Image {
	h := seedOf(seed)
	p := palettes[h%uint32(len(palettes))]
	top, mid, glow := fc(p[0]), fc(p[1]), fc(p[2])
	black := fcol{0, 0, 0}
	white := fcol{255, 255, 255}
	r := func(shift uint, lo, hi float64) float64 {
		return lo + float64((h>>shift)&0xff)/255*(hi-lo)
	}
	mountains := (h>>11)%2 == 0
	img := image.NewRGBA(image.Rect(0, 0, size, size))
	s := float64(size)
	px := 1.2 / s
	gx := r(3, 0.3, 0.7)

	type ridge struct{ base, amp, f1, f2, ph float64 }
	var ridges []ridge
	if mountains {
		for k := 0; k < 3; k++ {
			ridges = append(ridges, ridge{
				base: 0.56 + float64(k)*0.13, amp: 0.13 - float64(k)*0.025,
				f1: r(uint(5+k*3), 1.2, 2.6), f2: r(uint(9+k*2), 3.0, 5.5), ph: r(uint(13+k), 0, 6.28),
			})
		}
	} else {
		for k := 0; k < 5; k++ {
			ridges = append(ridges, ridge{
				base: 0.22 + float64(k)*0.17, amp: r(uint(7+k), 0.06, 0.14), ph: r(uint(9+k*2), 0, 6.28),
			})
		}
	}
	tilt := r(5, -0.35, 0.35)

	for y := 0; y < size; y++ {
		v := (float64(y) + 0.5) / s
		// sky
		var sky fcol
		switch {
		case v < 0.5:
			sky = lerpC(top, mid, v/0.5)
		case v < 0.78:
			sky = lerpC(mid, glow, (v-0.5)/0.28)
		default:
			sky = glow
		}
		for x := 0; x < size; x++ {
			u := (float64(x) + 0.5) / s
			c := sky
			// glow (setting sun)
			gd := math.Hypot(u-gx, v-0.625) / 0.7
			c = lerpC(c, glow, 0.75*math.Max(0, 1-gd))
			for k, rg := range ridges {
				fk := float64(k)
				if mountains {
					edge := rg.base - rg.amp*(0.65*math.Sin(u*rg.f1*math.Pi+rg.ph)+0.35*math.Sin(u*rg.f2*math.Pi+rg.ph*1.7))
					in := smooth(edge-px, edge+px, v)
					if in <= 0 {
						continue
					}
					t := (v - (rg.base - rg.amp)) / (1 - rg.base + rg.amp)
					lt := lerpC(mid, top, 0.25+fk*0.25)
					lb := lerpC(top, black, 0.35+fk*0.2)
					layer := lerpC(lerpC(c, lt, 0.92), lb, math.Max(0, math.Min(1, t)))
					c = lerpC(c, layer, in)
				} else {
					edge := rg.base + tilt*(u-0.5) + rg.amp*math.Sin(u*2.2*math.Pi+rg.ph)
					in := smooth(edge-px, edge+px, v)
					if in <= 0 {
						continue
					}
					light := k%2 == 0
					var wc fcol
					a0 := 0.45
					if light {
						wc = lerpC(glow, white, 0.15)
						a0 = 0.32
					} else {
						wc = lerpC(top, black, 0.2)
					}
					fade := math.Max(0, 1-(v-(rg.base-rg.amp))/0.35)
					c = lerpC(c, wc, a0*fade*in)
				}
			}
			// vignette
			vd := math.Hypot(u-0.5, v-0.5) / 0.95
			dark := 1 - 0.28*math.Min(1, vd)
			img.SetRGBA(x, y, color.RGBA{
				uint8(math.Max(0, math.Min(255, c[0]*dark))),
				uint8(math.Max(0, math.Min(255, c[1]*dark))),
				uint8(math.Max(0, math.Min(255, c[2]*dark))),
				255,
			})
		}
	}
	return img
}

// ---------- background preparation ----------

// prepareAll extracts album covers and looks covers up on the internet so
// that lists show the real picture right away.
func (c *Covers) prepareAll(ctx context.Context) {
	s := c.l.Snap()
	type job struct {
		src    coverSrc
		lookup string
		al     *Album
		t      *Track
	}
	var jobs []job
	seen := map[string]bool{}
	online := c.onlineEnabled()
	add := func(src coverSrc, lookupKey string, al *Album, t *Track) {
		switch src.kind {
		case srcEmbedded, srcFrame:
			out := filepath.Join(c.srcDir, hashID("src", src.key)+".jpg")
			if !seen[src.key] && !fileExists(out) {
				seen[src.key] = true
				jobs = append(jobs, job{src: src})
			}
		case srcPlaceholder:
			if online && lookupKey != "" && !seen[lookupKey] && c.needLookup(lookupKey) {
				seen[lookupKey] = true
				jobs = append(jobs, job{lookup: lookupKey, al: al, t: t})
			}
		}
	}
	for _, al := range s.AlbumList {
		add(c.albumSource(al), albumLookupKey(al), al, nil)
		for _, t := range al.Tracks {
			if c.CoverOwner(t) == t.ID {
				add(c.trackSource(t), "", nil, nil)
			}
		}
	}
	for _, t := range s.All {
		if t.AlbumRef == nil {
			add(c.trackSource(t), trackLookupKey(t), nil, t)
		}
	}
	if len(jobs) == 0 {
		return
	}
	c.l.setCoverTask("Kapaklar hazırlanıyor", 0, len(jobs))
	defer c.l.setCoverTask("", 0, 0)
	offline := 0
	for i, j := range jobs {
		if ctx.Err() != nil {
			return
		}
		if j.lookup != "" {
			if offline >= 3 {
				continue // no internet: try again after the next scan
			}
			ok := c.lookupOnline(ctx, j.lookup, j.al, j.t)
			if ok == lookupOffline {
				offline++
			} else {
				offline = 0
			}
		} else {
			_ = c.file(ctx, j.src)
		}
		c.l.setCoverTask("Kapaklar hazırlanıyor", i+1, len(jobs))
		if i%25 == 0 {
			c.l.reloadThrottled()
		}
	}
	_ = c.l.Reload() // new versions for the lists
}

func (c *Covers) needLookup(key string) bool {
	r, ok := c.webRow(key)
	if !ok {
		return true
	}
	age := time.Since(time.Unix(r.FetchedAt, 0))
	switch r.Status {
	case "ok":
		return !fileExists(r.Path)
	case "notfound":
		return age > 30*24*time.Hour
	}
	return age > 6*time.Hour
}

type lookupResult int

const (
	lookupFound lookupResult = iota
	lookupNotFound
	lookupOffline
)

func (c *Covers) lookupOnline(ctx context.Context, key string, al *Album, t *Track) lookupResult {
	var artist, album, title string
	if al != nil {
		artist, album = primaryArtist(al.Artist), al.Title
	} else if t != nil {
		artist, title = t.ArtistName, t.Title
	}
	url, err := c.online.find(ctx, artist, album, title)
	now := time.Now().Unix()
	if err != nil {
		if ctx.Err() == nil {
			c.saveWeb(key, coverRow{Status: "error", FetchedAt: now})
		}
		return lookupOffline
	}
	if url == "" {
		c.saveWeb(key, coverRow{Status: "notfound", FetchedAt: now})
		return lookupNotFound
	}
	out := filepath.Join(c.srcDir, "web-"+hashID("web", key)+".jpg")
	if err := c.online.download(ctx, url, out); err != nil {
		if ctx.Err() == nil {
			c.saveWeb(key, coverRow{Status: "error", FetchedAt: now})
		}
		return lookupOffline
	}
	c.saveWeb(key, coverRow{Status: "ok", Path: out, FetchedAt: now})
	return lookupFound
}

func (c *Covers) saveWeb(key string, r coverRow) {
	putCoverRow(c.l.db, key, r)
	c.mu.Lock()
	c.web[key] = r
	c.mu.Unlock()
}
