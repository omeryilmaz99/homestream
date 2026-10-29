package api

import (
	"bytes"
	"encoding/binary"
	"errors"
	"image"
	"image/jpeg"
	_ "image/png" // uploads
	"io"
	"net/http"
	"os"
	"path/filepath"

	"golang.org/x/image/draw"
	_ "golang.org/x/image/webp" // uploads

	"homestream/internal/store"
)

// Profile photos: uploaded once (from any device), cropped to a square,
// stored as data/profiles/<id>.jpg and shared by every app on the server.

const (
	photoMaxUpload = 20 << 20
	photoSize      = 400
)

func (s *Server) photoPath(id string) string {
	return filepath.Join(s.Lib.Cfg.DataDir, "profiles", id+".jpg")
}

// profileOut turns the stored photo token into a URL for the apps.
func profileOut(p store.Profile) store.Profile {
	if p.Photo != "" {
		p.Photo = "/api/profiles/" + p.ID + "/photo?v=" + p.Photo
	}
	return p
}

func (s *Server) handleReorderProfiles(w http.ResponseWriter, r *http.Request) {
	var b struct {
		IDs []string `json:"ids"`
	}
	if err := readJSON(r, &b); err != nil || len(b.IDs) == 0 {
		writeError(w, http.StatusBadRequest, "Geçersiz istek")
		return
	}
	if err := s.St.ReorderProfiles(b.IDs); err != nil {
		writeError(w, http.StatusInternalServerError, "Sıra kaydedilemedi")
		return
	}
	s.handleProfiles(w, r)
}

func (s *Server) handleSetProfilePhoto(w http.ResponseWriter, r *http.Request) {
	p, ok := s.St.Profile(r.PathValue("id"))
	if !ok {
		writeError(w, http.StatusNotFound, "Profil bulunamadı")
		return
	}
	data, err := io.ReadAll(io.LimitReader(r.Body, photoMaxUpload+1))
	if err != nil {
		writeError(w, http.StatusBadRequest, "Fotoğraf okunamadı")
		return
	}
	if len(data) > photoMaxUpload {
		writeError(w, http.StatusRequestEntityTooLarge, "Fotoğraf çok büyük (en fazla 20 MB)")
		return
	}
	img, err := decodePhoto(data)
	if err != nil {
		writeError(w, http.StatusBadRequest, "Bu dosya bir fotoğraf değil (JPG, PNG veya WEBP olmalı)")
		return
	}
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, squarePhoto(img, photoSize), &jpeg.Options{Quality: 88}); err != nil {
		writeError(w, http.StatusInternalServerError, "Fotoğraf kaydedilemedi")
		return
	}
	path := s.photoPath(p.ID)
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		writeError(w, http.StatusInternalServerError, "Fotoğraf kaydedilemedi")
		return
	}
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, buf.Bytes(), 0o644); err != nil || os.Rename(tmp, path) != nil {
		_ = os.Remove(tmp)
		writeError(w, http.StatusInternalServerError, "Fotoğraf kaydedilemedi")
		return
	}
	p.Photo = store.RandomHex(4)
	if err := s.St.SetProfilePhoto(p.ID, p.Photo); err != nil {
		writeError(w, http.StatusInternalServerError, "Fotoğraf kaydedilemedi")
		return
	}
	writeJSON(w, http.StatusOK, profileOut(p))
}

func (s *Server) handleDeleteProfilePhoto(w http.ResponseWriter, r *http.Request) {
	p, ok := s.St.Profile(r.PathValue("id"))
	if !ok {
		writeError(w, http.StatusNotFound, "Profil bulunamadı")
		return
	}
	_ = os.Remove(s.photoPath(p.ID))
	if err := s.St.SetProfilePhoto(p.ID, ""); err != nil {
		writeError(w, http.StatusInternalServerError, "Fotoğraf kaldırılamadı")
		return
	}
	p.Photo = ""
	writeJSON(w, http.StatusOK, p)
}

func (s *Server) handleProfilePhoto(w http.ResponseWriter, r *http.Request) {
	p, ok := s.St.Profile(r.PathValue("id"))
	if !ok || p.Photo == "" {
		writeError(w, http.StatusNotFound, "Fotoğraf yok")
		return
	}
	f, err := os.Open(s.photoPath(p.ID))
	if err != nil {
		writeError(w, http.StatusNotFound, "Fotoğraf yok")
		return
	}
	defer f.Close()
	st, err := f.Stat()
	if err != nil {
		writeError(w, http.StatusNotFound, "Fotoğraf yok")
		return
	}
	h := w.Header()
	h.Set("Content-Type", "image/jpeg")
	h.Set("ETag", `"`+p.Photo+`"`)
	// the URL carries the version, so it can be cached for long
	if r.URL.Query().Get("v") == p.Photo {
		h.Set("Cache-Control", "public, max-age=31536000, immutable")
	} else {
		h.Set("Cache-Control", "no-cache")
	}
	http.ServeContent(w, r, "", st.ModTime(), f)
}

// decodePhoto decodes JPEG/PNG/WEBP and applies the JPEG EXIF orientation
// (phone cameras store portrait photos sideways with a rotation flag).
func decodePhoto(data []byte) (image.Image, error) {
	img, _, err := image.Decode(bytes.NewReader(data))
	if err != nil {
		return nil, err
	}
	b := img.Bounds()
	if b.Dx() < 8 || b.Dy() < 8 {
		return nil, errors.New("too small")
	}
	// shrink big camera photos first, so rotating them stays cheap
	return applyOrientation(shrink(img, 3*photoSize), jpegOrientation(data)), nil
}

// shrink scales img down so its shorter side is at most max pixels.
func shrink(img image.Image, max int) image.Image {
	b := img.Bounds()
	short := min(b.Dx(), b.Dy())
	if short <= max {
		return img
	}
	w, h := b.Dx()*max/short, b.Dy()*max/short
	dst := image.NewRGBA(image.Rect(0, 0, w, h))
	draw.ApproxBiLinear.Scale(dst, dst.Bounds(), img, b, draw.Src, nil)
	return dst
}

// squarePhoto crops the centre square and scales it to size x size.
func squarePhoto(img image.Image, size int) image.Image {
	b := img.Bounds()
	side := min(b.Dx(), b.Dy())
	x0 := b.Min.X + (b.Dx()-side)/2
	// portraits: keep a bit more of the top, where faces usually are
	y0 := b.Min.Y + (b.Dy()-side)/3
	src := image.Rect(x0, y0, x0+side, y0+side)
	if side < size {
		size = side
	}
	dst := image.NewRGBA(image.Rect(0, 0, size, size))
	draw.CatmullRom.Scale(dst, dst.Bounds(), img, src, draw.Src, nil)
	return dst
}

// jpegOrientation returns the EXIF orientation (1-8) of a JPEG, or 1.
func jpegOrientation(data []byte) int {
	if len(data) < 4 || data[0] != 0xFF || data[1] != 0xD8 {
		return 1
	}
	i := 2
	for i+4 <= len(data) {
		if data[i] != 0xFF {
			return 1
		}
		marker := data[i+1]
		if marker == 0xDA || marker == 0xD9 { // start of scan / end
			return 1
		}
		n := int(binary.BigEndian.Uint16(data[i+2:]))
		if n < 2 || i+2+n > len(data) {
			return 1
		}
		seg := data[i+4 : i+2+n]
		if marker == 0xE1 && len(seg) > 14 && string(seg[:6]) == "Exif\x00\x00" {
			return exifOrientation(seg[6:])
		}
		i += 2 + n
	}
	return 1
}

func exifOrientation(t []byte) int {
	if len(t) < 8 {
		return 1
	}
	var bo binary.ByteOrder
	switch string(t[:2]) {
	case "II":
		bo = binary.LittleEndian
	case "MM":
		bo = binary.BigEndian
	default:
		return 1
	}
	off := int(bo.Uint32(t[4:]))
	if off+2 > len(t) {
		return 1
	}
	count := int(bo.Uint16(t[off:]))
	for k := 0; k < count; k++ {
		e := off + 2 + k*12
		if e+12 > len(t) {
			return 1
		}
		if bo.Uint16(t[e:]) == 0x0112 { // Orientation
			v := int(bo.Uint16(t[e+8:]))
			if v >= 1 && v <= 8 {
				return v
			}
			return 1
		}
	}
	return 1
}

// applyOrientation rotates/flips img according to an EXIF orientation.
func applyOrientation(img image.Image, o int) image.Image {
	if o <= 1 || o > 8 {
		return img
	}
	b := img.Bounds()
	w, h := b.Dx(), b.Dy()
	swap := o >= 5
	dw, dh := w, h
	if swap {
		dw, dh = h, w
	}
	dst := image.NewRGBA(image.Rect(0, 0, dw, dh))
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			var dx, dy int
			switch o {
			case 2:
				dx, dy = w-1-x, y
			case 3:
				dx, dy = w-1-x, h-1-y
			case 4:
				dx, dy = x, h-1-y
			case 5:
				dx, dy = y, x
			case 6:
				dx, dy = h-1-y, x
			case 7:
				dx, dy = h-1-y, w-1-x
			case 8:
				dx, dy = y, w-1-x
			}
			dst.Set(dx, dy, img.At(b.Min.X+x, b.Min.Y+y))
		}
	}
	return dst
}
