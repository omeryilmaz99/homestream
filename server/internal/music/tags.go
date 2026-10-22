package music

import (
	"context"
	"encoding/json"
	"errors"
	"os/exec"
	"path"
	"regexp"
	"strconv"
	"strings"
	"time"
	"unicode"

	"homestream/internal/names"
)

// Tags are the facts read from a file (tags + stream info), with file name
// fallbacks applied.
type Tags struct {
	Title       string
	Artist      string
	AlbumArtist string
	Album       string
	TrackNo     int
	DiscNo      int
	Year        int
	Genre       string
	Duration    float64
	Codec       string
	Bitrate     int64
	SampleRate  int
	BitDepth    int
	Channels    int
	IsVideo     bool
	HasPic      bool
}

type probeJSON struct {
	Format struct {
		FormatName string            `json:"format_name"`
		Duration   string            `json:"duration"`
		BitRate    string            `json:"bit_rate"`
		Tags       map[string]string `json:"tags"`
	} `json:"format"`
	Streams []struct {
		CodecType        string            `json:"codec_type"`
		CodecName        string            `json:"codec_name"`
		SampleRate       string            `json:"sample_rate"`
		Channels         int               `json:"channels"`
		BitsPerSample    int               `json:"bits_per_sample"`
		BitsPerRawSample string            `json:"bits_per_raw_sample"`
		SampleFmt        string            `json:"sample_fmt"`
		BitRate          string            `json:"bit_rate"`
		Duration         string            `json:"duration"`
		Tags             map[string]string `json:"tags"`
		Disposition      map[string]int    `json:"disposition"`
	} `json:"streams"`
}

func (l *Library) probe(ctx context.Context, abs string) (Tags, error) {
	if l.cfg.FFprobe == "" {
		return Tags{}, errors.New("ffprobe yok")
	}
	ctx, cancel := context.WithTimeout(ctx, 60*time.Second)
	defer cancel()
	cmd := l.command(ctx, l.cfg.FFprobe, "-v", "error", "-print_format", "json", "-show_format", "-show_streams", abs)
	out, err := cmd.Output()
	if err != nil {
		var ee *exec.ExitError
		if errors.As(err, &ee) && len(ee.Stderr) > 0 {
			msg := strings.TrimSpace(string(ee.Stderr))
			if len(msg) > 200 {
				msg = msg[:200]
			}
			return Tags{}, errors.New(msg)
		}
		return Tags{}, err
	}
	return parseProbe(out)
}

// lookup finds a tag case-insensitively, trying several names.
func lookup(maps []map[string]string, keys ...string) string {
	for _, k := range keys {
		for _, m := range maps {
			for kk, v := range m {
				if strings.EqualFold(kk, k) {
					if v = cleanTag(v); v != "" {
						return v
					}
				}
			}
		}
	}
	return ""
}

func parseProbe(out []byte) (Tags, error) {
	var p probeJSON
	if err := json.Unmarshal(out, &p); err != nil {
		return Tags{}, err
	}
	var t Tags
	maps := []map[string]string{p.Format.Tags}
	audio := -1
	for i, s := range p.Streams {
		switch s.CodecType {
		case "audio":
			if audio < 0 {
				audio = i
			}
		case "video":
			if s.Disposition["attached_pic"] == 1 || s.CodecName == "mjpeg" || s.CodecName == "png" || s.CodecName == "bmp" || s.CodecName == "gif" {
				t.HasPic = true
			} else {
				t.IsVideo = true
			}
		}
	}
	if audio < 0 {
		return t, errors.New("ses akışı yok")
	}
	a := p.Streams[audio]
	maps = append(maps, a.Tags) // ogg/opus/flac in some containers keep tags on the stream
	t.Codec = a.CodecName
	t.SampleRate, _ = strconv.Atoi(a.SampleRate)
	t.Channels = a.Channels
	t.BitDepth = a.BitsPerSample
	if t.BitDepth == 0 {
		t.BitDepth, _ = strconv.Atoi(a.BitsPerRawSample)
	}
	if t.BitDepth == 0 && isLossless(t.Codec) {
		switch {
		case strings.HasPrefix(a.SampleFmt, "s16"):
			t.BitDepth = 16
		case strings.HasPrefix(a.SampleFmt, "s32"):
			t.BitDepth = 24 // flac/alac decode 24-bit into s32
		}
	}
	t.Bitrate, _ = strconv.ParseInt(a.BitRate, 10, 64)
	if t.Bitrate == 0 && !t.IsVideo {
		t.Bitrate, _ = strconv.ParseInt(p.Format.BitRate, 10, 64)
	}
	t.Duration, _ = strconv.ParseFloat(p.Format.Duration, 64)
	if t.Duration <= 0 {
		t.Duration, _ = strconv.ParseFloat(a.Duration, 64)
	}
	if t.Duration < 0 {
		t.Duration = 0
	}
	t.Title = lookup(maps, "title")
	t.Artist = lookup(maps, "artist", "performer", "author")
	t.AlbumArtist = lookup(maps, "album_artist", "albumartist", "album artist", "TPE2")
	t.Album = lookup(maps, "album")
	t.TrackNo = leadingInt(lookup(maps, "track", "tracknumber"))
	t.DiscNo = leadingInt(lookup(maps, "disc", "discnumber"))
	t.Year = parseYear(lookup(maps, "date", "year", "originaldate", "TDRC", "TYER", "creation_time"))
	t.Genre = cleanGenre(lookup(maps, "genre"))
	return t, nil
}

func isLossless(codec string) bool {
	switch codec {
	case "flac", "alac", "ape", "wavpack", "tta", "truehd", "mlp":
		return true
	}
	return strings.HasPrefix(codec, "pcm_") || strings.HasPrefix(codec, "dsd_")
}

var leadingIntRe = regexp.MustCompile(`^\s*(\d+)`)

func leadingInt(s string) int {
	m := leadingIntRe.FindStringSubmatch(s)
	if m == nil {
		return 0
	}
	n, _ := strconv.Atoi(m[1])
	if n > 9999 {
		return 0
	}
	return n
}

var yearRe = regexp.MustCompile(`(19|20)\d\d`)

func parseYear(s string) int {
	m := yearRe.FindString(s)
	if m == "" {
		return 0
	}
	y, _ := strconv.Atoi(m)
	return y
}

// cleanTag trims, makes valid UTF-8 and repairs Turkish text that was
// written as Latin-1 / Windows-1254 bytes and read back as Latin-1
// (e.g. "ÞarkÝ" → "Şarkİ", "Ýstanbul" → "İstanbul").
func cleanTag(s string) string {
	s = names.DisplayString(s)
	s = strings.TrimSpace(strings.Trim(s, "\x00"))
	if s == "" {
		return ""
	}
	return fixTurkish(s)
}

var trFix = strings.NewReplacer("Ý", "İ", "ý", "ı", "Þ", "Ş", "þ", "ş", "Ð", "Ğ", "ð", "ğ")

func fixTurkish(s string) string {
	if !strings.ContainsAny(s, "ÝýÞþÐð") {
		return s
	}
	// real Turkish letters present: the text is fine (Icelandic etc. aside)
	if strings.ContainsAny(s, "ıİşŞğĞ") {
		return s
	}
	return trFix.Replace(s)
}

func cleanGenre(g string) string {
	g = strings.TrimSpace(g)
	if g == "" {
		return ""
	}
	// ID3v1 numeric genres like "(17)" or "17"
	if m := numericGenreRe.FindStringSubmatch(g); m != nil {
		n, _ := strconv.Atoi(m[1])
		if n < len(id3Genres) {
			return id3Genres[n]
		}
		return ""
	}
	for _, sep := range []string{";", "/", "\\", ","} {
		if i := strings.Index(g, sep); i > 0 {
			g = strings.TrimSpace(g[:i])
		}
	}
	if g == "" || strings.EqualFold(g, "other") || strings.EqualFold(g, "unknown") || strings.EqualFold(g, "genre") {
		return ""
	}
	return titleCase(g)
}

// titleCase upper-cases the first letter of each word (Turkish-aware for i).
func titleCase(s string) string {
	rs := []rune(s)
	start := true
	for i, r := range rs {
		if unicode.IsLetter(r) {
			if start {
				if r == 'i' {
					rs[i] = 'İ'
				} else {
					rs[i] = unicode.ToUpper(r)
				}
			}
			start = false
		} else {
			start = r == ' ' || r == '-' || r == '&'
		}
	}
	return string(rs)
}

var id3Genres = []string{"Blues", "Classic Rock", "Country", "Dance", "Disco", "Funk", "Grunge", "Hip-Hop", "Jazz",
	"Metal", "New Age", "Oldies", "Other", "Pop", "R&B", "Rap", "Reggae", "Rock", "Techno", "Industrial", "Alternative",
	"Ska", "Death Metal", "Pranks", "Soundtrack", "Euro-Techno", "Ambient", "Trip-Hop", "Vocal", "Jazz+Funk", "Fusion",
	"Trance", "Classical", "Instrumental", "Acid", "House", "Game", "Sound Clip", "Gospel", "Noise", "Alternative Rock",
	"Bass", "Soul", "Punk", "Space", "Meditative", "Instrumental Pop", "Instrumental Rock", "Ethnic", "Gothic",
	"Darkwave", "Techno-Industrial", "Electronic", "Pop-Folk", "Eurodance", "Dream", "Southern Rock", "Comedy", "Cult",
	"Gangsta", "Top 40", "Christian Rap", "Pop/Funk", "Jungle", "Native American", "Cabaret", "New Wave",
	"Psychedelic", "Rave", "Showtunes", "Trailer", "Lo-Fi", "Tribal", "Acid Punk", "Acid Jazz", "Polka", "Retro",
	"Musical", "Rock & Roll", "Hard Rock"}

// ---------- file name fallbacks ----------

var (
	trackPrefixRe  = regexp.MustCompile(`^\s*(?:(\d)[-.](\d{1,2})|(\d{1,3}))(?:\s*[-._)]\s*|\s+)(.+)$`)
	yearParenRe    = regexp.MustCompile(`\s*[\(\[]\s*((?:19|20)\d\d)\s*[\)\]]\s*`)
	discDirRe      = regexp.MustCompile(`(?i)^(cd|disc|disk|disque)\s*[-_.]?\s*(\d{1,2})\b`)
	numericGenreRe = regexp.MustCompile(`^\(?(\d{1,3})\)?$`)
	yearTitleRe    = regexp.MustCompile(`^\s*((?:19|20)\d\d)\b`)
	junkRe         = regexp.MustCompile(`(?i)\s*[\(\[](official\s*(music\s*)?video|official\s*audio|lyrics?|lyric\s*video|audio|hd|hq|4k|1080p|720p|klip|video\s*klip|resmi\s*klip)[\)\]]`)
)

// isDiscDir reports whether a folder name looks like "CD1" / "Disc 2".
func isDiscDir(name string) (int, bool) {
	m := discDirRe.FindStringSubmatch(name)
	if m == nil {
		return 0, false
	}
	n, _ := strconv.Atoi(m[2])
	return n, true
}

// fileFallback fills missing title/artist/album/track from the file path
// (relative to the music folder, '/' separated).
func fileFallback(t *Tags, rel string) {
	base := names.DisplayString(path.Base(rel))
	base = strings.TrimSuffix(base, path.Ext(base))
	base = strings.ReplaceAll(base, "_", " ")
	base = strings.TrimSpace(junkRe.ReplaceAllString(base, ""))

	dir := path.Dir(rel)
	albumDir := ""
	if dir != "." {
		albumDir = names.DisplayString(path.Base(dir))
		if n, ok := isDiscDir(albumDir); ok {
			if t.DiscNo == 0 {
				t.DiscNo = n
			}
			if pd := path.Dir(dir); pd != "." {
				albumDir = names.DisplayString(path.Base(pd))
			} else {
				albumDir = ""
			}
		}
	}

	name := base
	if m := trackPrefixRe.FindStringSubmatch(name); m != nil && !looksLikeYearTitle(name) {
		no := 0
		if m[3] != "" {
			no, _ = strconv.Atoi(m[3])
		} else {
			d, _ := strconv.Atoi(m[1])
			no, _ = strconv.Atoi(m[2])
			if t.DiscNo == 0 {
				t.DiscNo = d
			}
		}
		if t.TrackNo == 0 && no > 0 && no < 1000 {
			t.TrackNo = no
		}
		name = strings.TrimSpace(m[4])
	}
	fileArtist := ""
	if a, b, ok := strings.Cut(name, " - "); ok && strings.TrimSpace(a) != "" && strings.TrimSpace(b) != "" {
		fileArtist, name = strings.TrimSpace(a), strings.TrimSpace(b)
	}
	if t.Title == "" {
		t.Title = name
		if t.Title == "" {
			t.Title = base
		}
	}
	// album folder like "Artist - Album (2010)"
	dirArtist, dirAlbum, dirYear := "", albumDir, 0
	if albumDir != "" {
		if m := yearParenRe.FindStringSubmatch(albumDir); m != nil {
			dirYear, _ = strconv.Atoi(m[1])
			dirAlbum = strings.TrimSpace(yearParenRe.ReplaceAllString(albumDir, " "))
		}
		if a, b, ok := strings.Cut(dirAlbum, " - "); ok && strings.TrimSpace(a) != "" && strings.TrimSpace(b) != "" {
			dirArtist, dirAlbum = strings.TrimSpace(a), strings.TrimSpace(b)
		}
	}
	// Müzik/<artist>/<album>/song: the folder above the album is the artist
	parentArtist := ""
	if albumRel := albumDirRel(dir); albumRel != "" {
		if pa := path.Dir(albumRel); pa != "." && path.Dir(pa) == "." && !genericMusicDir(path.Base(pa)) {
			parentArtist = names.DisplayString(path.Base(pa))
		}
	}
	if t.Artist == "" {
		switch {
		case fileArtist != "":
			t.Artist = fileArtist
		case dirArtist != "":
			t.Artist = dirArtist
		case parentArtist != "":
			t.Artist = parentArtist
		case t.Album == "" && albumDir != "" && path.Dir(dir) == "." && !genericMusicDir(albumDir):
			// Müzik/Tarkan/şarkı.mp3: a top level folder is most likely the artist
			t.Artist = albumDir
		}
	}
	if t.Album == "" && albumDir != "" && !genericMusicDir(albumDir) {
		// a top level artist folder with loose songs is not an album
		if !(dirArtist == "" && path.Dir(dir) == "." && t.Artist == albumDir) {
			t.Album = dirAlbum
		}
	}
	if t.Year == 0 {
		t.Year = dirYear
	}
	t.Title = fixTurkish(t.Title)
	t.Artist = fixTurkish(t.Artist)
	t.Album = fixTurkish(t.Album)
}

// albumDirRel is the album folder of a file's folder (skipping "CD1").
func albumDirRel(dir string) string {
	if dir == "." || dir == "" {
		return ""
	}
	if _, ok := isDiscDir(path.Base(dir)); ok {
		if pd := path.Dir(dir); pd != "." {
			return pd
		}
		return ""
	}
	return dir
}

var genericDirs = map[string]bool{
	"muzik": true, "muzikler": true, "music": true, "musics": true, "albumler": true, "albums": true,
	"karisik": true, "various": true, "various artists": true, "cesitli": true, "cesitli sanatcilar": true,
	"indirilenler": true, "downloads": true, "sarkilar": true, "songs": true, "klipler": true, "klip": true,
	"videolar": true, "videos": true, "playlist": true, "playlists": true, "yeni": true, "new": true,
	"mp3": true, "flac": true, "misc": true, "diger": true, "other": true, "single": true, "singles": true,
	"tekler": true, "tekli": true, "tek sarkilar": true,
}

func genericMusicDir(name string) bool { return genericDirs[names.Fold(name)] }

// looksLikeYearTitle avoids reading "1999 - Prince" as track 1999.
func looksLikeYearTitle(s string) bool {
	return yearTitleRe.MatchString(s)
}
