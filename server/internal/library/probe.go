package library

import (
	"context"
	"encoding/json"
	"errors"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

type ffprobeOut struct {
	Format struct {
		FormatName string `json:"format_name"`
		Duration   string `json:"duration"`
		BitRate    string `json:"bit_rate"`
	} `json:"format"`
	Streams []struct {
		CodecType     string            `json:"codec_type"`
		CodecName     string            `json:"codec_name"`
		Width         int               `json:"width"`
		Height        int               `json:"height"`
		Channels      int               `json:"channels"`
		ColorTransfer string            `json:"color_transfer"`
		Duration      string            `json:"duration"`
		Tags          map[string]string `json:"tags"`
		Disposition   map[string]int    `json:"disposition"`
		SideData      []struct {
			Type string `json:"side_data_type"`
		} `json:"side_data_list"`
	} `json:"streams"`
}

func (l *Library) probe(ctx context.Context, path string) (*MediaInfo, float64, error) {
	if l.Cfg.FFprobe == "" {
		return nil, 0, errors.New("ffprobe yok")
	}
	ctx, cancel := context.WithTimeout(ctx, 90*time.Second)
	defer cancel()
	cmd := l.command(ctx, l.Cfg.FFprobe, "-v", "error", "-print_format", "json", "-show_format", "-show_streams", path)
	out, err := cmd.Output()
	if err != nil {
		var ee *exec.ExitError
		if errors.As(err, &ee) && len(ee.Stderr) > 0 {
			msg := strings.TrimSpace(string(ee.Stderr))
			if len(msg) > 200 {
				msg = msg[:200]
			}
			return nil, 0, errors.New(msg)
		}
		return nil, 0, err
	}
	return parseProbe(out, path)
}

func tag(m map[string]string, k string) string {
	if v, ok := m[k]; ok {
		return v
	}
	for kk, v := range m {
		if strings.EqualFold(kk, k) {
			return v
		}
	}
	return ""
}

func parseProbe(out []byte, path string) (*MediaInfo, float64, error) {
	var p ffprobeOut
	if err := json.Unmarshal(out, &p); err != nil {
		return nil, 0, err
	}
	mi := &MediaInfo{Audio: []AudioTrack{}, Subtitles: []SubTrack{}}
	ext := strings.ToLower(strings.TrimPrefix(filepath.Ext(path), "."))
	formats := strings.Split(p.Format.FormatName, ",")
	switch {
	case strings.Contains(p.Format.FormatName, "matroska"):
		mi.Container = "matroska"
		if ext == "webm" {
			mi.Container = "webm"
		}
	case strings.Contains(p.Format.FormatName, "mov"):
		switch ext {
		case "mov":
			mi.Container = "mov"
		case "3gp":
			mi.Container = "3gp"
		default:
			mi.Container = "mp4"
		}
	default:
		mi.Container = formats[0]
	}
	dur, _ := strconv.ParseFloat(p.Format.Duration, 64)
	mi.Bitrate, _ = strconv.ParseInt(p.Format.BitRate, 10, 64)
	hasVideo := false
	for _, s := range p.Streams {
		switch s.CodecType {
		case "video":
			if s.Disposition["attached_pic"] == 1 || hasVideo {
				continue
			}
			hasVideo = true
			mi.VideoCodec, mi.Width, mi.Height = s.CodecName, s.Width, s.Height
			if s.ColorTransfer == "smpte2084" || s.ColorTransfer == "arib-std-b67" {
				mi.HDR = true
			}
			for _, sd := range s.SideData {
				if strings.Contains(strings.ToLower(sd.Type), "dovi") || strings.Contains(sd.Type, "Dolby Vision") {
					mi.HDR = true
				}
			}
			if dur == 0 {
				dur, _ = strconv.ParseFloat(s.Duration, 64)
			}
		case "audio":
			mi.Audio = append(mi.Audio, AudioTrack{
				Index: len(mi.Audio), Codec: s.CodecName, Language: tag(s.Tags, "language"),
				Channels: s.Channels, Title: tag(s.Tags, "title"), Default: s.Disposition["default"] == 1,
			})
		case "subtitle":
			mi.Subtitles = append(mi.Subtitles, SubTrack{
				Index: len(mi.Subtitles), Codec: s.CodecName, Language: tag(s.Tags, "language"),
				Title: tag(s.Tags, "title"), Forced: s.Disposition["forced"] == 1, Default: s.Disposition["default"] == 1,
			})
		}
	}
	if !hasVideo {
		return mi, dur, errors.New("video akışı yok")
	}
	if dur < 0 {
		dur = 0
	}
	return mi, dur, nil
}
