package music

import (
	"image"
	"image/png"
	"os"
	"strconv"
	"testing"

	"golang.org/x/image/draw"
)

func TestPlaceholderGrid(t *testing.T) {
	out := os.Getenv("PH_OUT")
	if out == "" {
		t.Skip()
	}
	grid := image.NewRGBA(image.Rect(0, 0, 4*240, 4*240))
	for i := 0; i < 16; i++ {
		img := Placeholder("seed"+strconv.Itoa(i*7), 240)
		draw.Draw(grid, image.Rect((i%4)*240, (i/4)*240, (i%4+1)*240, (i/4+1)*240), img, image.Point{}, draw.Src)
	}
	f, _ := os.Create(out)
	png.Encode(f, grid)
	f.Close()
}
