package music

import (
	"bytes"
	"context"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

var audioMIME = map[string]string{
	".mp3": "audio/mpeg", ".flac": "audio/flac", ".m4a": "audio/mp4", ".m4b": "audio/mp4", ".aac": "audio/aac",
	".ogg": "audio/ogg", ".oga": "audio/ogg", ".opus": "audio/ogg", ".wav": "audio/wav", ".wma": "audio/x-ms-wma",
	".ape": "audio/x-ape", ".wv": "audio/x-wavpack", ".aiff": "audio/aiff", ".aif": "audio/aiff", ".aifc": "audio/aiff",
	".dsf": "audio/x-dsf", ".dff": "audio/x-dff", ".mka": "audio/x-matroska", ".mpc": "audio/x-musepack",
	".tta": "audio/x-tta", ".ac3": "audio/ac3", ".dts": "audio/vnd.dts", ".mp2": "audio/mpeg", ".amr": "audio/amr",
	".caf": "audio/x-caf", ".weba": "audio/webm", ".spx": "audio/ogg", ".w64": "audio/wav",
	".mp4": "video/mp4", ".m4v": "video/mp4", ".mov": "video/quicktime", ".webm": "video/webm",
	".mkv": "video/x-matroska", ".avi": "video/x-msvideo", ".flv": "video/x-flv", ".3gp": "video/3gpp",
	".ts": "video/mp2t", ".mpg": "video/mpeg", ".mpeg": "video/mpeg", ".wmv": "video/x-ms-wmv",
}

// MIMEType returns the content type for a file name.
func MIMEType(name string) string {
	if m, ok := audioMIME[strings.ToLower(filepath.Ext(name))]; ok {
		return m
	}
	return "application/octet-stream"
}

func (l *Library) audioCachePath(t *Track) string {
	return filepath.Join(l.cfg.DataDir, "cache", "music", "audio",
		t.ID+"-"+hashID("a", strconv.FormatInt(t.Size, 10)+":"+strconv.FormatInt(t.MTime, 10))[:8]+".mka")
}

// StreamFile returns the file to send for a track. For a video it is the
// sound only (copied, not re-encoded, into a small .mka file), so phones
// don't download the picture; the original is used when that fails.
func (l *Library) StreamFile(ctx context.Context, t *Track) (path, mime string) {
	if !t.IsVideo || l.cfg.FFmpeg == "" {
		return t.AbsPath, MIMEType(t.AbsPath)
	}
	out := l.audioCachePath(t)
	if fileExists(out) {
		return out, "audio/x-matroska"
	}
	if l.Covers.isFailed("audio:" + out) {
		return t.AbsPath, MIMEType(t.AbsPath)
	}
	_, err := l.Covers.do("a:"+out, func() (string, error) {
		if fileExists(out) {
			return out, nil
		}
		return out, l.extractAudio(t, out)
	})
	if err != nil {
		l.Covers.mu.Lock()
		l.Covers.failed["audio:"+out] = time.Now()
		l.Covers.mu.Unlock()
		log.Printf("music: audio of %s: %v (sending the video file)", t.RelPath, err)
		return t.AbsPath, MIMEType(t.AbsPath)
	}
	return out, "audio/x-matroska"
}

func (l *Library) extractAudio(t *Track, out string) error {
	if err := os.MkdirAll(filepath.Dir(out), 0o755); err != nil {
		return err
	}
	tmp := out + ".tmp"
	defer os.Remove(tmp)
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Minute)
	defer cancel()
	cmd := lowPrio(ctx, l.cfg.Nice, "5", l.cfg.FFmpeg, "-nostdin", "-hide_banner", "-loglevel", "error",
		"-i", t.AbsPath, "-map", "0:a:0", "-vn", "-sn", "-dn", "-c:a", "copy", "-f", "matroska", "-y", tmp)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		msg := strings.TrimSpace(stderr.String())
		if len(msg) > 200 {
			msg = msg[:200]
		}
		return fmt.Errorf("%v: %s", err, msg)
	}
	if st, err := os.Stat(tmp); err != nil || st.Size() < 1024 {
		return fmt.Errorf("ses çıkarılamadı")
	}
	// remove the sound of older versions of this file
	if old, _ := filepath.Glob(filepath.Join(filepath.Dir(out), t.ID+"-*.mka")); len(old) > 0 {
		for _, o := range old {
			_ = os.Remove(o)
		}
	}
	return os.Rename(tmp, out)
}
