package library

import (
	"bytes"
	"context"
	"fmt"
	"image"
	"image/color"
	"image/jpeg"
	_ "image/png"
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
)

// Image widths clients may request.
var ImageWidths = []int{160, 320, 480, 780, 1280, 1920}

// SnapWidth snaps a requested width to the supported set.
func SnapWidth(w int, kind string) int {
	if w <= 0 {
		if kind == "poster" {
			return 480
		}
		return 1280
	}
	for _, x := range ImageWidths {
		if x >= w {
			return x
		}
	}
	return ImageWidths[len(ImageWidths)-1]
}

// Images renders, caches and serves item images.
type Images struct {
	dir       string
	framesDir string
	ffmpeg    string
	nice      string
	frameSem  chan struct{}
	renderSem chan struct{}

	sfMu  sync.Mutex
	calls map[string]*sfCall

	mu     sync.Mutex
	frames map[string]bool
	failed map[string]time.Time
}

type sfCall struct {
	wg  sync.WaitGroup
	val string
	err error
}

// NewImages creates the image service rooted at dir.
func NewImages(dir, ffmpeg, nice string) *Images {
	im := &Images{
		dir: filepath.Join(dir, "images"), framesDir: filepath.Join(dir, "frames"),
		ffmpeg: ffmpeg, nice: nice,
		frameSem: make(chan struct{}, 2), renderSem: make(chan struct{}, 4),
		calls: map[string]*sfCall{}, frames: map[string]bool{}, failed: map[string]time.Time{},
	}
	_ = os.MkdirAll(im.dir, 0o755)
	_ = os.MkdirAll(im.framesDir, 0o755)
	if entries, err := os.ReadDir(im.framesDir); err == nil {
		for _, e := range entries {
			if strings.HasSuffix(e.Name(), ".jpg") {
				im.frames[e.Name()] = true
			} else if strings.HasSuffix(e.Name(), ".tmp") {
				_ = os.Remove(filepath.Join(im.framesDir, e.Name()))
			}
		}
	}
	return im
}

// singleflight
func (im *Images) do(key string, fn func() (string, error)) (string, error) {
	im.sfMu.Lock()
	if c, ok := im.calls[key]; ok {
		im.sfMu.Unlock()
		c.wg.Wait()
		return c.val, c.err
	}
	c := &sfCall{}
	c.wg.Add(1)
	im.calls[key] = c
	im.sfMu.Unlock()
	func() {
		defer func() {
			if r := recover(); r != nil {
				c.err = fmt.Errorf("panic: %v", r)
			}
		}()
		c.val, c.err = fn()
	}()
	c.wg.Done()
	im.sfMu.Lock()
	delete(im.calls, key)
	im.sfMu.Unlock()
	return c.val, c.err
}

// CanGenerate reports whether ffmpeg is available.
func (im *Images) CanGenerate() bool { return im.ffmpeg != "" }

func (im *Images) frameName(it *Item) string {
	return it.ID + "-" + HashID("f", strconv.FormatInt(it.Size, 10)+":"+strconv.FormatInt(it.MTime, 10))[:8] + ".jpg"
}

// HasFrame reports whether a frame grab exists for the item.
func (im *Images) HasFrame(it *Item) bool {
	if it.AbsPath == "" {
		return true
	}
	im.mu.Lock()
	defer im.mu.Unlock()
	return im.frames[im.frameName(it)]
}

// Frame returns the path of the item's frame grab, generating it if needed ("" on failure).
func (im *Images) Frame(ctx context.Context, it *Item) string {
	if it == nil || it.AbsPath == "" {
		return ""
	}
	name := im.frameName(it)
	p := filepath.Join(im.framesDir, name)
	im.mu.Lock()
	have := im.frames[name]
	failedAt, failed := im.failed[name]
	im.mu.Unlock()
	if have {
		return p
	}
	if !im.CanGenerate() || (failed && time.Since(failedAt) < 6*time.Hour) {
		return ""
	}
	res, err := im.do("frame:"+name, func() (string, error) {
		select {
		case im.frameSem <- struct{}{}:
		case <-ctx.Done():
			return "", ctx.Err()
		}
		defer func() { <-im.frameSem }()
		if err := im.grab(it, p); err != nil {
			return "", err
		}
		return p, nil
	})
	if err != nil {
		if ctx.Err() == nil {
			im.mu.Lock()
			im.failed[name] = time.Now()
			im.mu.Unlock()
		}
		return ""
	}
	return res
}

func (im *Images) grab(it *Item, out string) error {
	t := it.Duration * 0.25
	if it.Duration <= 0 {
		t = 30
	}
	tmp := out + ".tmp"
	defer os.Remove(tmp)
	run := func(ts float64, vf string) error {
		ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
		defer cancel()
		args := []string{"-nostdin", "-hide_banner", "-loglevel", "error",
			"-ss", strconv.FormatFloat(ts, 'f', 2, 64), "-i", it.AbsPath,
			"-map", "0:v:0", "-frames:v", "1", "-vf", vf, "-q:v", "3", "-f", "image2", "-y", tmp}
		cmd := lowPrio(ctx, im.nice, "15", im.ffmpeg, args...)
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
			return fmt.Errorf("ffmpeg kare üretmedi")
		}
		return nil
	}
	plain := "scale=trunc(iw*sar/2)*2:ih,setsar=1,scale=1280:-2"
	var err error
	if it.Media != nil && it.Media.HDR {
		tm := "zscale=t=linear:npl=100,format=gbrpf32le,zscale=p=bt709,tonemap=tonemap=hable:desat=0,zscale=t=bt709:m=bt709:r=tv,format=yuv420p," + plain
		err = run(t, tm)
		if err != nil {
			err = run(t, plain)
		}
	} else {
		err = run(t, plain)
	}
	if err != nil && t > 0 {
		err = run(0, plain)
	}
	if err != nil {
		log.Printf("images: frame for %s failed: %v", it.FileName, err)
		return err
	}
	if err := os.Rename(tmp, out); err != nil {
		return err
	}
	name := filepath.Base(out)
	im.mu.Lock()
	im.frames[name] = true
	delete(im.failed, name)
	im.mu.Unlock()
	// remove frames of older file versions
	if old, _ := filepath.Glob(filepath.Join(im.framesDir, it.ID+"-*.jpg")); len(old) > 0 {
		for _, o := range old {
			if filepath.Base(o) != name {
				_ = os.Remove(o)
				im.mu.Lock()
				delete(im.frames, filepath.Base(o))
				im.mu.Unlock()
			}
		}
	}
	return nil
}

func usable(p string, check bool) bool {
	if p == "" {
		return false
	}
	if !check {
		return true
	}
	return fileExists(p)
}

// source resolves the image file for item/kind following the fallback
// chain. "" means: use a generated placeholder. With gen=false nothing is
// generated and no files are stat'ed (used for cache-busting versions).
func (im *Images) source(ctx context.Context, it *Item, kind string, gen bool) string {
	frame := func(x *Item) string {
		if x == nil {
			return ""
		}
		if gen {
			return im.Frame(ctx, x)
		}
		if im.HasFrame(x) && x.AbsPath != "" {
			return "frame:" + im.frameName(x)
		}
		return ""
	}
	firstOf := func(ps ...string) string {
		for _, p := range ps {
			if usable(p, gen) {
				return p
			}
		}
		return ""
	}
	switch it.Type {
	case "episode":
		if kind == "poster" {
			if it.Series != nil {
				return im.source(ctx, it.Series, "poster", gen)
			}
			return frame(it)
		}
		if p := firstOf(it.LocalBackdrop, it.TMDBBackdrop); p != "" {
			return p
		}
		if f := frame(it); f != "" {
			return f
		}
		if it.Series != nil {
			return im.source(ctx, it.Series, "backdrop", gen)
		}
	case "series":
		var p string
		if kind == "poster" {
			p = firstOf(it.LocalPoster, it.TMDBPoster)
		} else {
			p = firstOf(it.LocalBackdrop, it.TMDBBackdrop)
		}
		if p != "" {
			return p
		}
		return frame(it.FirstEpisode())
	default:
		switch kind {
		case "poster":
			if p := firstOf(it.LocalPoster, it.TMDBPoster); p != "" {
				return p
			}
			return frame(it)
		case "thumb":
			if f := frame(it); f != "" {
				return f
			}
			return firstOf(it.LocalBackdrop, it.TMDBBackdrop)
		default:
			if p := firstOf(it.LocalBackdrop, it.TMDBBackdrop); p != "" {
				return p
			}
			return frame(it)
		}
	}
	return ""
}

// Version returns a short token that changes when the image source changes
// (used as ?v= in image URLs so clients' long-lived caches stay correct).
func (im *Images) Version(it *Item, kind string) string {
	src := im.source(context.Background(), it, kind, false)
	if src == "" {
		return "0"
	}
	return HashID("v", src)[:6]
}

// Serve writes the image for item/kind at the requested width.
func (im *Images) Serve(w http.ResponseWriter, r *http.Request, it *Item, kind string, width int) {
	width = SnapWidth(width, kind)
	src := im.source(r.Context(), it, kind, true)
	var key string
	if src != "" {
		st, err := os.Stat(src)
		if err != nil {
			src = ""
		} else {
			key = HashID("img", fmt.Sprintf("%s|%s|%d|%d|%d", kind, src, st.Size(), st.ModTime().UnixNano(), width))
		}
	}
	if src == "" {
		key = HashID("ph", fmt.Sprintf("%s|%s|%d|v1", it.ID, kind, width))
	}
	prefix := fmt.Sprintf("%s-%s-%d-", it.ID, kind, width)
	cachePath := filepath.Join(im.dir, it.ID[:2], prefix+key+".jpg")
	if !fileExists(cachePath) {
		_, err := im.do("render:"+cachePath, func() (string, error) {
			if fileExists(cachePath) {
				return cachePath, nil
			}
			im.renderSem <- struct{}{}
			defer func() { <-im.renderSem }()
			data, err := renderImage(src, it.ID, kind, width)
			if err != nil {
				log.Printf("images: render %s %s: %v (using placeholder)", it.ID, kind, err)
				data, err = renderImage("", it.ID, kind, width)
				if err != nil {
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
			// last resort: render in memory
			data, err2 := renderImage("", it.ID, kind, width)
			if err2 != nil {
				http.Error(w, `{"error":"Görsel oluşturulamadı"}`, http.StatusInternalServerError)
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
		http.Error(w, `{"error":"Görsel okunamadı"}`, http.StatusInternalServerError)
		return
	}
	defer f.Close()
	st, _ := f.Stat()
	w.Header().Set("Content-Type", "image/jpeg")
	w.Header().Set("Cache-Control", "public, max-age=604800")
	w.Header().Set("ETag", `"`+key+`"`)
	http.ServeContent(w, r, "", st.ModTime(), f)
}

func aspectFor(kind string) float64 {
	if kind == "poster" {
		return 2.0 / 3.0
	}
	return 16.0 / 9.0
}

func renderImage(src, id, kind string, width int) ([]byte, error) {
	aspect := aspectFor(kind)
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
		if b.Dx() < 2 || b.Dy() < 2 {
			return nil, fmt.Errorf("görsel çok küçük")
		}
		crop := b
		cur := float64(b.Dx()) / float64(b.Dy())
		if math.Abs(cur-aspect)/aspect > 0.03 {
			if cur > aspect { // too wide
				nw := int(float64(b.Dy()) * aspect)
				x0 := b.Min.X + (b.Dx()-nw)/2
				crop = image.Rect(x0, b.Min.Y, x0+nw, b.Max.Y)
			} else {
				nh := int(float64(b.Dx()) / aspect)
				y0 := b.Min.Y + (b.Dy()-nh)/2
				crop = image.Rect(b.Min.X, y0, b.Max.X, y0+nh)
			}
		}
		w := width
		if crop.Dx() < w {
			w = crop.Dx() // never upscale
		}
		h := int(math.Round(float64(w) * float64(crop.Dy()) / float64(crop.Dx())))
		if h < 1 {
			h = 1
		}
		dst := image.NewRGBA(image.Rect(0, 0, w, h))
		draw.CatmullRom.Scale(dst, dst.Bounds(), img, crop, draw.Src, nil)
		out = dst
	} else {
		out = placeholder(id, width, int(math.Round(float64(width)/aspect)))
	}
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, out, &jpeg.Options{Quality: 85}); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

func hsv(h, s, v float64) (float64, float64, float64) {
	h = math.Mod(h, 360) / 60
	i := math.Floor(h)
	f := h - i
	p, q, t := v*(1-s), v*(1-s*f), v*(1-s*(1-f))
	switch int(i) {
	case 0:
		return v, t, p
	case 1:
		return q, v, p
	case 2:
		return p, v, t
	case 3:
		return p, q, v
	case 4:
		return t, p, v
	}
	return v, p, q
}

// placeholder draws a dark diagonal gradient with a soft vignette whose hue
// is derived from the item id.
func placeholder(id string, w, h int) image.Image {
	var seed uint32
	for i := 0; i < len(id); i++ {
		seed = seed*31 + uint32(id[i])
	}
	hue := float64(seed % 360)
	r1, g1, b1 := hsv(hue, 0.55, 0.30)
	r2, g2, b2 := hsv(hue+35, 0.65, 0.07)
	img := image.NewRGBA(image.Rect(0, 0, w, h))
	cx, cy := float64(w)/2, float64(h)*0.4
	maxd := math.Hypot(float64(w), float64(h)) / 2
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			t := (float64(x)/float64(w) + float64(y)/float64(h)) / 2
			d := math.Hypot(float64(x)-cx, float64(y)-cy) / maxd
			vig := 1 - 0.45*d*d
			r := (r1*(1-t) + r2*t) * vig
			g := (g1*(1-t) + g2*t) * vig
			b := (b1*(1-t) + b2*t) * vig
			img.SetRGBA(x, y, color.RGBA{uint8(r * 255), uint8(g * 255), uint8(b * 255), 255})
		}
	}
	return img
}
