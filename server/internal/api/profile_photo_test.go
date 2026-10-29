package api

import (
	"bytes"
	"encoding/json"
	"image"
	"image/color"
	"image/jpeg"
	"image/png"
	"net/http"
	"testing"

	"homestream/internal/store"
)

func doJSON(t *testing.T, method, u, ct string, body []byte, v any) int {
	t.Helper()
	req, _ := http.NewRequest(method, u, bytes.NewReader(body))
	if ct != "" {
		req.Header.Set("Content-Type", ct)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if v != nil {
		_ = json.NewDecoder(resp.Body).Decode(v)
	}
	return resp.StatusCode
}

func TestProfileOrderAndPhoto(t *testing.T) {
	srv := setup(t)
	var ids []string
	for _, n := range []string{"A", "B", "C"} {
		var p store.Profile
		if c := doJSON(t, "POST", srv.URL+"/api/profiles", "application/json", []byte(`{"name":"`+n+`"}`), &p); c != 201 {
			t.Fatalf("create %s: %d", n, c)
		}
		ids = append(ids, p.ID)
	}
	var ps []store.Profile
	if c := doJSON(t, "PUT", srv.URL+"/api/profiles/order", "application/json",
		[]byte(`{"ids":["`+ids[2]+`","`+ids[0]+`"]}`), &ps); c != 200 {
		t.Fatalf("reorder: %d", c)
	}
	got := []string{ps[0].Name, ps[1].Name, ps[2].Name}
	if got[0] != "C" || got[1] != "A" || got[2] != "B" {
		t.Fatalf("order = %v", got)
	}
	// a new profile goes last
	doJSON(t, "POST", srv.URL+"/api/profiles", "application/json", []byte(`{"name":"D"}`), nil)
	get(t, srv.URL+"/api/profiles", &ps)
	if len(ps) != 4 || ps[3].Name != "D" || ps[0].Name != "C" {
		t.Fatalf("after create: %+v", ps)
	}

	// not an image
	if c := doJSON(t, "PUT", srv.URL+"/api/profiles/"+ids[0]+"/photo", "image/png", []byte("hello"), nil); c != 400 {
		t.Fatalf("bad photo: %d", c)
	}
	// a wide PNG becomes a square JPEG
	img := image.NewRGBA(image.Rect(0, 0, 900, 500))
	for y := 0; y < 500; y++ {
		for x := 0; x < 900; x++ {
			img.Set(x, y, color.RGBA{uint8(x), uint8(y), 80, 255})
		}
	}
	var buf bytes.Buffer
	_ = png.Encode(&buf, img)
	var p store.Profile
	if c := doJSON(t, "PUT", srv.URL+"/api/profiles/"+ids[0]+"/photo", "image/png", buf.Bytes(), &p); c != 200 || p.Photo == "" {
		t.Fatalf("upload: %d %+v", c, p)
	}
	resp, err := http.Get(srv.URL + p.Photo)
	if err != nil || resp.StatusCode != 200 {
		t.Fatalf("get photo: %v %v", err, resp)
	}
	out, err := jpeg.Decode(resp.Body)
	resp.Body.Close()
	if err != nil || out.Bounds().Dx() != 400 || out.Bounds().Dy() != 400 {
		t.Fatalf("photo: %v %v", err, out.Bounds())
	}
	get(t, srv.URL+"/api/profiles", &ps)
	for _, q := range ps {
		if q.ID == ids[0] && q.Photo != p.Photo {
			t.Fatalf("list photo %q want %q", q.Photo, p.Photo)
		}
	}
	if c := doJSON(t, "DELETE", srv.URL+"/api/profiles/"+ids[0]+"/photo", "", nil, &p); c != 200 || p.Photo != "" {
		t.Fatalf("delete photo: %d %+v", c, p)
	}
	if c := get(t, srv.URL+"/api/profiles/"+ids[0]+"/photo", nil); c != 404 {
		t.Fatalf("photo after delete: %d", c)
	}
}

func TestApplyOrientation(t *testing.T) {
	img := image.NewRGBA(image.Rect(0, 0, 4, 2))
	img.Set(0, 0, color.RGBA{255, 0, 0, 255}) // top-left red
	// orientation 6 = rotate 90° clockwise: top-left moves to top-right
	out := applyOrientation(img, 6)
	if out.Bounds().Dx() != 2 || out.Bounds().Dy() != 4 {
		t.Fatalf("size %v", out.Bounds())
	}
	if r, _, _, _ := out.At(1, 0).RGBA(); r>>8 != 255 {
		t.Fatalf("pixel not rotated")
	}
}
