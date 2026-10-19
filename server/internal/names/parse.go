package names

import (
	"path"
	"regexp"
	"strconv"
	"strings"
	"time"
	"unicode"
)

// Kind of a parsed video file.
type Kind int

const (
	Movie Kind = iota
	Episode
)

// Parsed is the result of parsing a library-relative video path.
type Parsed struct {
	Kind  Kind
	Title string // movie title, or episode title ("" when unknown)
	Year  int

	SeriesTitle     string
	SeriesYear      int
	SeriesDir       string // library-relative dir of the series folder ("" if none)
	TitleFromFolder bool   // series title came from the immediate (non-season) parent folder
	FilePrefix      string // series title derived from the file name prefix (may be "")
	FilePrefixYear  int
	Season          int
	Episode         int
}

var (
	reSxxEyy   = regexp.MustCompile(`(?i)(?:^|[^a-z0-9])s(\d{1,3})[ ._-]*e(\d{1,4})`)
	reNxNN     = regexp.MustCompile(`(?i)(?:^|[^a-z0-9])(\d{1,2})x(\d{2,3})(?:[^a-z0-9]|$)`)
	reTrSE1    = regexp.MustCompile(`(?i)(?:^|[^\pL\d])(\d{1,2})[ ._-]*\.?[ ._-]*sezon[ ._-]*(\d{1,4})[ ._-]*\.?[ ._-]*b[oö]l[uü]m`)
	reTrSE2    = regexp.MustCompile(`(?i)sezon[ ._-]*(\d{1,2})[ ._-]*b[oö]l[uü]m[ ._-]*(\d{1,4})`)
	reEnSE     = regexp.MustCompile(`(?i)season[ ._-]*(\d{1,2})[ ._-]*(?:episode|ep)[ ._-]*(\d{1,4})`)
	reEpKw     = regexp.MustCompile(`(?i)(?:^|[^\pL\d])(?:episode|b[oö]l[uü]m)[ ._-]*(\d{1,4})(?:[^\d]|$)`)
	reEpKwTr   = regexp.MustCompile(`(?i)(?:^|[^\pL\d])(\d{1,4})[ ._-]*\.?[ ._-]*b[oö]l[uü]m(?:[^\pL]|$)`)
	reEpWeak   = regexp.MustCompile(`(?i)(?:^|[^a-z0-9])e(?:p|pisode)?[ ._-]*(\d{1,4})(?:[^\d]|$)`)
	reLeadNum  = regexp.MustCompile(`^(\d{1,3})(?:[ ._-]+|$)`)
	reSeasonEn = regexp.MustCompile(`(?i)(?:season|sezon)[ ._-]*(\d{1,2})`)
	reSeasonTr = regexp.MustCompile(`(?i)(?:^|[^\pL\d])(\d{1,2})[ ._-]*\.?[ ._-]*sezon`)

	reSeasonPure1 = regexp.MustCompile(`(?i)^(?:season|sezon|series|staffel|saison|temporada|seizoen|stagione)[ ._-]*(\d{1,3})(?:[ ._-]*\(?\d{4}\)?)?$`)
	reSeasonPure2 = regexp.MustCompile(`(?i)^s(\d{1,3})$`)
	reSeasonPure3 = regexp.MustCompile(`(?i)^(\d{1,3})[ ._-]*\.?[ ._-]*sezon$`)
	reSpecials    = regexp.MustCompile(`(?i)^(?:specials?|özel bölümler|ozel bolumler|season[ ._-]*0+|sezon[ ._-]*0+)$`)
	reSeasonPre1  = regexp.MustCompile(`(?i)^(.+?)[ ._-]+(?:season|sezon)[ ._-]*(\d{1,3})(?:[^0-9].*)?$`)
	reSeasonPre2  = regexp.MustCompile(`(?i)^(.+?)[ ._-]+(\d{1,2})[ ._-]*\.?[ ._-]*sezon(?:[^\pL].*)?$`)
	reSeasonPre3  = regexp.MustCompile(`(?i)^(.+?)[ ._-]+s(\d{1,2})(?:[ ._-].*)?$`)

	rePart     = regexp.MustCompile(`(?i)(?:^|[ ._\-\[(])(cd|disc|disk|part|pt)[ ._-]?(\d{1,2})(?:[^0-9]|$)`)
	reBrackets = regexp.MustCompile(`\[[^\]]*\]|\{[^}]*\}|【[^】]*】`)
	reWebsite  = regexp.MustCompile(`(?i)^www\.[^ ]+\s*[-–]?\s*`)
	reDigits   = regexp.MustCompile(`\d+`)

	reTagRes   = regexp.MustCompile(`^\d{3,4}[pi]$`)
	reTagCodec = regexp.MustCompile(`^[hx]\.?26[45]$`)
	reTagAudio = regexp.MustCompile(`^(ddp?|dd\+|aac|ac3|eac3|e-ac3|dts|truehd|atmos|flac)\d?(\.\d)?$`)
	reTagBits  = regexp.MustCompile(`^\d{1,2}bit$`)
	reTagPart  = regexp.MustCompile(`^(cd|disc|disk|part|pt)\d{1,2}$`)
)

var strongTags = setOf(
	"4k", "8k", "uhd", "fhd", "x264", "x265", "h264", "h265", "hevc", "avc", "xvid", "divx",
	"web-dl", "webdl", "web-rip", "webrip", "web-dlrip", "bluray", "blu-ray", "bdrip", "brrip", "bdremux", "remux",
	"dvdrip", "dvdscr", "dvd5", "dvd9", "hdrip", "hdtv", "pdtv", "hdr", "hdr10", "hdr10+", "dv", "dovi",
	"dolbyvision", "sdr", "ac3", "eac3", "aac", "dts", "dts-hd", "truehd", "atmos", "flac", "mp3", "opus",
	"yify", "yts", "rarbg", "ettv", "eztv", "hdcam", "camrip", "telesync", "amzn", "dsnp", "hmax",
	"atvp", "blutv", "exxen", "dublaj", "dublajlı", "dublajli", "altyazılı", "altyazili", "altyazı", "altyazi",
	"trdublaj", "tr-dublaj", "tr-altyazı", "720", "1080", "2160", "bdrip", "nf-dl",
)

var weakTags = setOf(
	"web", "hd", "sd", "dvd", "cam", "multi", "dual", "extended", "unrated", "uncut", "remastered",
	"imax", "proper", "repack", "rerip", "internal", "limited", "tr", "nf", "türkçe", "turkce", "hc",
	"dc", "complete", "hulu", "mubi", "turkish", "eng", "subbed", "dubbed",
)

var genericDirs = foldSet(
	"filmler", "film", "filmlerim", "movies", "movie", "films", "diziler", "dizi", "dizilerim",
	"series", "tv", "tv shows", "tvshows", "shows", "tv series", "videos", "videolar", "video",
	"downloads", "download", "indirilenler", "homestream", "media", "medya", "complete", "torrent",
	"torrents", "yeni", "new", "belgesel", "belgeseller", "documentaries", "documentary",
	"çizgi film", "çizgi filmler", "animasyon", "animation", "anime", "kids", "çocuk", "sinema",
	"cinema", "multimedia", "plex", "jellyfin", "emby", "library", "kütüphane", "arşiv", "archive",
)

var seriesRoots = foldSet("diziler", "dizi", "dizilerim", "series", "tv", "tv shows", "tvshows", "shows", "tv series")
var movieRoots = foldSet("filmler", "film", "filmlerim", "movies", "movie", "films")

var genericMovieNames = foldSet("movie", "film", "video", "sample", "filmi", "vts", "main", "feature", "title", "untitled")

func setOf(xs ...string) map[string]bool {
	m := make(map[string]bool, len(xs))
	for _, x := range xs {
		m[x] = true
	}
	return m
}

func foldSet(xs ...string) map[string]bool {
	m := make(map[string]bool, len(xs))
	for _, x := range xs {
		m[Fold(x)] = true
	}
	return m
}

// IsGenericDir reports whether a folder name is a generic container name
// ("Filmler", "Diziler", "Downloads", …) that does not name a title.
func IsGenericDir(name string) bool { return genericDirs[Fold(name)] }

type seasonInfo struct {
	isSeason bool
	season   int
	prefix   string // series title prefix inside the folder name ("Breaking Bad Season 1")
}

func atoi(s string) int { n, _ := strconv.Atoi(s); return n }

func seasonFolder(name string) seasonInfo {
	name = strings.TrimSpace(name)
	if name == "" {
		return seasonInfo{}
	}
	if reSpecials.MatchString(name) {
		return seasonInfo{isSeason: true, season: 0}
	}
	for _, re := range []*regexp.Regexp{reSeasonPure1, reSeasonPure2, reSeasonPure3} {
		if m := re.FindStringSubmatch(name); m != nil {
			return seasonInfo{isSeason: true, season: atoi(m[1])}
		}
	}
	for _, re := range []*regexp.Regexp{reSeasonPre1, reSeasonPre2, reSeasonPre3} {
		if m := re.FindStringSubmatch(name); m != nil {
			p, _ := CleanTitle(m[1])
			if p == "" {
				return seasonInfo{isSeason: true, season: atoi(m[2])}
			}
			return seasonInfo{isSeason: true, season: atoi(m[2]), prefix: m[1]}
		}
	}
	return seasonInfo{}
}

// IsSeasonFolder reports whether the folder name looks like a season folder.
func IsSeasonFolder(name string) bool { return seasonFolder(name).isSeason }

type epMatch struct {
	strength   int // 3 = with season, 2 = keyword, 1 = weak, 0 = none
	season     int
	hasSeason  bool
	episode    int
	start, end int
	lead       bool
}

func findEpisode(base string) epMatch {
	for _, re := range []*regexp.Regexp{reSxxEyy, reNxNN, reTrSE1, reTrSE2, reEnSE} {
		if m := re.FindStringSubmatchIndex(base); m != nil {
			return epMatch{strength: 3, season: atoi(base[m[2]:m[3]]), hasSeason: true,
				episode: atoi(base[m[4]:m[5]]), start: m[0], end: m[1]}
		}
	}
	seasonFromName := func(em *epMatch) {
		if m := reSeasonTr.FindStringSubmatch(base); m != nil {
			em.season, em.hasSeason = atoi(m[1]), true
		} else if m := reSeasonEn.FindStringSubmatch(base); m != nil {
			em.season, em.hasSeason = atoi(m[1]), true
		}
	}
	for _, re := range []*regexp.Regexp{reEpKw, reEpKwTr} {
		if m := re.FindStringSubmatchIndex(base); m != nil {
			em := epMatch{strength: 2, episode: atoi(base[m[2]:m[3]]), start: m[0], end: m[1]}
			seasonFromName(&em)
			// the prefix must not contain the "N. Sezon" part
			if loc := reSeasonTr.FindStringIndex(base); loc != nil && loc[0] < em.start {
				em.start = loc[0]
			} else if loc := reSeasonEn.FindStringIndex(base); loc != nil && loc[0] < em.start {
				em.start = loc[0]
			}
			return em
		}
	}
	if m := reEpWeak.FindStringSubmatchIndex(base); m != nil {
		em := epMatch{strength: 1, episode: atoi(base[m[2]:m[3]]), start: m[0], end: m[1]}
		seasonFromName(&em)
		return em
	}
	if m := reLeadNum.FindStringSubmatchIndex(base); m != nil {
		return epMatch{strength: 1, episode: atoi(base[m[2]:m[3]]), start: 0, end: m[1], lead: true}
	}
	return epMatch{}
}

// ParsePath parses a video path relative to its library folder ("/" separated).
func ParsePath(rel string) Parsed {
	rel = strings.Trim(strings.ReplaceAll(rel, "\\", "/"), "/")
	parts := strings.Split(rel, "/")
	file := parts[len(parts)-1]
	dirs := make([]string, 0, len(parts)-1)
	for _, d := range parts[:len(parts)-1] {
		dirs = append(dirs, DisplayString(d))
	}
	base := DisplayString(strings.TrimSuffix(file, path.Ext(file)))

	parent := ""
	if len(dirs) > 0 {
		parent = dirs[len(dirs)-1]
	}
	pInfo := seasonFolder(parent)

	seriesRootIdx := -1
	movieRoot := false
	for i, d := range dirs {
		k := Fold(d)
		if seriesRoots[k] && seriesRootIdx < 0 {
			seriesRootIdx = i
		}
		if movieRoots[k] {
			movieRoot = true
		}
	}
	inShowFolder := seriesRootIdx >= 0 && seriesRootIdx < len(dirs)-1

	m := findEpisode(base)
	cleanBase, baseYear := CleanTitle(base)

	isEp := false
	switch m.strength {
	case 3:
		isEp = true
	case 2:
		isEp = pInfo.isSeason || inShowFolder || (!movieRoot && baseYear == 0)
	default:
		isEp = pInfo.isSeason || inShowFolder
	}
	if !isEp {
		return parseMovie(base, cleanBase, baseYear, parent)
	}

	p := Parsed{Kind: Episode}
	// season
	switch {
	case m.hasSeason:
		p.Season = m.season
	case pInfo.isSeason:
		p.Season = pInfo.season
	default:
		p.Season = 1
	}
	// episode number + title
	if m.strength > 0 {
		p.Episode = m.episode
		p.Title = cleanEpisodeTitle(base[m.end:])
	} else {
		p.Episode = lastNumber(cleanBase)
		p.Title = cleanBase
	}
	if m.strength > 0 && m.start > 0 {
		p.FilePrefix, p.FilePrefixYear = CleanTitle(strings.TrimRight(base[:m.start], " ._-–"))
	}

	// series title
	var title string
	var year int
	join := func(n int) string { return strings.Join(dirs[:n], "/") }
	switch {
	case inShowFolder:
		show := dirs[seriesRootIdx+1]
		si := seasonFolder(show)
		name := show
		if si.isSeason {
			name = si.prefix
			if !m.hasSeason && !pInfo.isSeason {
				p.Season = si.season
			}
		}
		title, year = CleanTitle(name)
		p.SeriesDir = join(seriesRootIdx + 2)
		if len(dirs) == seriesRootIdx+2 && !si.isSeason {
			p.TitleFromFolder = true
		}
	case pInfo.isSeason && pInfo.prefix != "":
		title, year = CleanTitle(pInfo.prefix)
		p.SeriesDir = join(len(dirs))
		if len(dirs) >= 2 {
			if gt, _ := CleanTitle(dirs[len(dirs)-2]); Key(gt) == Key(title) {
				p.SeriesDir = join(len(dirs) - 1)
			}
		}
	case pInfo.isSeason:
		if len(dirs) >= 2 && !IsGenericDir(dirs[len(dirs)-2]) {
			title, year = folderTitle(dirs[len(dirs)-2])
			p.SeriesDir = join(len(dirs) - 1)
		}
	case len(dirs) > 0 && !IsGenericDir(parent):
		title, year = folderTitle(parent)
		n := len(dirs)
		if title == "" && len(dirs) >= 2 && !IsGenericDir(dirs[len(dirs)-2]) {
			title, year = folderTitle(dirs[len(dirs)-2])
			n--
		}
		if title != "" {
			p.TitleFromFolder = n == len(dirs)
			p.SeriesDir = join(n)
		}
	}
	if title == "" {
		title, year = p.FilePrefix, p.FilePrefixYear
		p.TitleFromFolder = false
	}
	if title == "" {
		title = "Bilinmeyen Dizi"
	}
	if year == 0 && p.FilePrefix != "" && Key(p.FilePrefix) == Key(title) {
		year = p.FilePrefixYear
	}
	p.SeriesTitle, p.SeriesYear = title, year
	if Key(p.Title) == Key(title) || isOnlyTags(p.Title) || Key(reDigits.ReplaceAllString(p.Title, "")) == Key(title) {
		p.Title = ""
	}
	return p
}

// folderTitle cleans a folder name used as a series title. Folders named
// like a single release ("Show.S01E01.720p") are reduced to the prefix.
func folderTitle(name string) (string, int) {
	if em := findEpisode(name); em.strength == 3 {
		name = name[:em.start]
	} else if si := seasonFolder(name); si.isSeason {
		name = si.prefix
	}
	return CleanTitle(name)
}

func isOnlyTags(s string) bool {
	return s != "" && reDigits.ReplaceAllString(Fold(s), "") == ""
}

func lastNumber(s string) int {
	nums := reDigits.FindAllString(s, -1)
	for i := len(nums) - 1; i >= 0; i-- {
		if len(nums[i]) <= 3 {
			return atoi(nums[i])
		}
	}
	return 0
}

func parseMovie(base, title string, year int, parent string) Parsed {
	part := ""
	if m := rePart.FindStringSubmatch(base); m != nil {
		label := map[string]string{"cd": "CD", "disc": "Disk", "disk": "Disk", "part": "Part", "pt": "Part"}[strings.ToLower(m[1])]
		part = label + " " + strconv.Itoa(atoi(m[2]))
	}
	if isGenericMovieName(title) && parent != "" && !IsGenericDir(parent) {
		if pt, py := CleanTitle(parent); pt != "" {
			title = pt
			if py > 0 {
				year = py
			}
		}
	} else if year == 0 && parent != "" && title != "" {
		if pt, py := CleanTitle(parent); py > 0 {
			kp, kt := Key(pt), Key(title)
			if kp == kt || strings.HasPrefix(kp, kt) || strings.HasPrefix(kt, kp) {
				year = py
			}
		}
	}
	if title == "" {
		title = strings.TrimSpace(base)
	}
	if part != "" && !strings.Contains(Fold(title), Fold(part)) {
		title += " (" + part + ")"
	}
	return Parsed{Kind: Movie, Title: title, Year: year}
}

func isGenericMovieName(t string) bool {
	k := Key(t)
	if k == "" || genericMovieNames[k] || len([]rune(k)) <= 2 || reTagPart.MatchString(k) {
		return true
	}
	if strings.HasPrefix(k, "bolum") || strings.HasPrefix(k, "part") || strings.HasPrefix(k, "cd") {
		if _, err := strconv.Atoi(strings.TrimLeft(k, "bolumpartcd")); err == nil {
			return true
		}
	}
	return false
}

func tagCore(tok string) string {
	return strings.ToLower(strings.Trim(tok, "()[]{}-–,:;!+"))
}

func isStrongTag(core string) bool {
	if core == "" {
		return false
	}
	if strongTags[core] || reTagRes.MatchString(core) || reTagCodec.MatchString(core) ||
		reTagAudio.MatchString(core) || reTagBits.MatchString(core) || reTagPart.MatchString(core) {
		return true
	}
	if i := strings.IndexByte(core, '-'); i > 0 {
		first := core[:i]
		return strongTags[first] || reTagRes.MatchString(first) || reTagCodec.MatchString(first) || reTagAudio.MatchString(first)
	}
	return false
}

func isYearToken(core string) (int, bool) {
	if len(core) != 4 || (core[:2] != "19" && core[:2] != "20") {
		return 0, false
	}
	y, err := strconv.Atoi(core)
	if err != nil || y > time.Now().Year()+1 || y < 1900 {
		return 0, false
	}
	return y, true
}

// CleanTitle turns a file or folder name into a display title and extracts
// a release year (0 when none).
func CleanTitle(s string) (string, int) { return cleanTitle(s, 1) }

var reMultiEp = regexp.MustCompile(`(?i)^(?:[-&+ ._]*e\d{1,4})+`)

// cleanEpisodeTitle cleans the text after an episode marker. Unlike titles,
// the very first token may already be a release tag.
func cleanEpisodeTitle(s string) string {
	s = reMultiEp.ReplaceAllString(strings.TrimSpace(s), "")
	s = strings.TrimLeft(s, " ._-–")
	t, _ := cleanTitle(s, 0)
	return t
}

func cleanTitle(s string, firstCut int) (string, int) {
	s = DisplayString(s)
	s = reWebsite.ReplaceAllString(s, "")
	s = reBrackets.ReplaceAllString(s, " ")
	s = strings.NewReplacer(".", " ", "_", " ", "+", " ").Replace(s)
	// "Movie(2010)" → "Movie (2010)"
	s = strings.ReplaceAll(s, "(", " (")
	s = strings.ReplaceAll(s, ")", ") ")
	toks := strings.Fields(s)
	if len(toks) == 0 {
		return "", 0
	}
	cut := len(toks)
	year := 0
	for i := len(toks) - 1; i >= 1; i-- {
		if y, ok := isYearToken(tagCore(toks[i])); ok {
			year, cut = y, i
			break
		}
	}
	strongAfter := make([]bool, len(toks)+1)
	for i := len(toks) - 1; i >= 0; i-- {
		strongAfter[i] = strongAfter[i+1] || isStrongTag(tagCore(toks[i]))
	}
	for i := firstCut; i < cut; i++ {
		c := tagCore(toks[i])
		if isStrongTag(c) || (weakTags[c] && strongAfter[i+1]) {
			cut = i
			break
		}
	}
	title := strings.Join(toks[:cut], " ")
	title = strings.ReplaceAll(title, "( )", "")
	title = strings.ReplaceAll(title, "()", "")
	title = strings.Trim(title, " -–:,;(")
	title = strings.TrimSpace(title)
	if strings.Count(title, "(") > strings.Count(title, ")") {
		title = strings.TrimSpace(strings.TrimSuffix(title, "("))
	}
	title = strings.Join(strings.Fields(title), " ")
	return smartTitleCase(title), year
}

func smartTitleCase(s string) string {
	hasLetter := false
	for _, r := range s {
		if unicode.IsUpper(r) {
			return s
		}
		if unicode.IsLetter(r) {
			hasLetter = true
		}
	}
	if !hasLetter {
		return s
	}
	turkish := strings.ContainsAny(s, "ğşıöüç")
	words := strings.Fields(s)
	for i, w := range words {
		rs := []rune(w)
		if turkish {
			rs[0] = unicode.TurkishCase.ToUpper(rs[0])
		} else {
			rs[0] = unicode.ToUpper(rs[0])
		}
		words[i] = string(rs)
	}
	return strings.Join(words, " ")
}
