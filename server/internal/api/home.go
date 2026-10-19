package api

import (
	"hash/fnv"
	"math"
	"math/rand"
	"path"
	"regexp"
	"sort"
	"strings"
	"time"

	"homestream/internal/library"
	"homestream/internal/names"
)

const rowLimit = 20

type rowJSON struct {
	ID    string     `json:"id"`
	Title string     `json:"title"`
	Items []ItemJSON `json:"items"`
}

type homeJSON struct {
	Hero []ItemJSON `json:"hero"`
	Rows []rowJSON  `json:"rows"`
}

func dailyRand(profile, salt string) *rand.Rand {
	h := fnv.New64a()
	h.Write([]byte(profile + "|" + salt + "|" + time.Now().Format("2006-01-02")))
	return rand.New(rand.NewSource(int64(h.Sum64())))
}

func limit(list []*library.Item, n int) []*library.Item {
	if len(list) > n {
		return list[:n]
	}
	return list
}

// inProgress lists movies/episodes with a resume point, newest first.
func (v *view) continueItems() []*library.Item {
	var out []*library.Item
	for id, u := range v.ud {
		if u.Position <= 0 || u.Played {
			continue
		}
		if it := v.snap.Items[id]; it != nil && it.Type != "series" {
			out = append(out, it)
		}
	}
	sort.Slice(out, func(i, j int) bool {
		a, b := v.ud[out[i].ID].LastPlayedAt, v.ud[out[j].ID].LastPlayedAt
		if a != b {
			return a > b
		}
		return out[i].ID < out[j].ID
	})
	return out
}

func (v *view) seriesLastPlayed(ser *library.Item) int64 {
	var last int64
	for _, e := range ser.Episodes {
		u := v.ud[e.ID]
		if (u.Played || u.Position > 0) && u.LastPlayedAt > last {
			last = u.LastPlayedAt
		}
	}
	return last
}

func (v *view) nextUpItems(cont []*library.Item) []*library.Item {
	inCont := map[string]bool{}
	for _, it := range cont {
		if it.Type == "episode" {
			inCont[it.SeriesID] = true
		}
	}
	type cand struct {
		ep   *library.Item
		last int64
	}
	var cands []cand
	for _, ser := range v.snap.Series {
		if inCont[ser.ID] {
			continue
		}
		last := v.seriesLastPlayed(ser)
		if last == 0 {
			continue
		}
		if ep := v.nextUp(ser, true); ep != nil {
			cands = append(cands, cand{ep, last})
		}
	}
	sort.Slice(cands, func(i, j int) bool { return cands[i].last > cands[j].last })
	out := make([]*library.Item, 0, len(cands))
	for _, c := range cands {
		out = append(out, c.ep)
	}
	return out
}

// genreWeights builds the profile's taste vector from played/liked items.
func (v *view) genreWeights() map[string]float64 {
	w := map[string]float64{}
	for id, u := range v.ud {
		it := v.snap.Items[id]
		if it == nil {
			continue
		}
		weight := 0.0
		if u.Played {
			weight += 1
		} else if u.Position > 0 {
			weight += 0.5
		}
		if u.Liked {
			weight += 2
		}
		if weight == 0 {
			continue
		}
		if it.Type == "episode" {
			weight *= 0.25 // many episodes of one show shouldn't dominate
		}
		for _, g := range it.Genres {
			w[g] += weight
		}
	}
	return w
}

func (v *view) isUnwatched(it *library.Item) bool {
	if it.Type == "series" {
		for _, e := range it.Episodes {
			u := v.ud[e.ID]
			if u.Played || u.Position > 0 {
				return false
			}
		}
		return true
	}
	u := v.ud[it.ID]
	return !u.Played && u.Position == 0
}

func (v *view) recommendedItems() []*library.Item {
	weights := v.genreWeights()
	maxW := 0.0
	for _, x := range weights {
		maxW = math.Max(maxW, x)
	}
	rng := dailyRand(v.profile, "rec")
	type scored struct {
		it    *library.Item
		score float64
	}
	var list []scored
	all := append(append([]*library.Item{}, v.snap.Movies...), v.snap.Series...)
	for _, it := range all {
		if !v.isUnwatched(it) {
			continue
		}
		score := it.Rating / 10 * 1.5
		if maxW > 0 && len(it.Genres) > 0 {
			aff := 0.0
			for _, g := range it.Genres {
				aff += weights[g] / maxW
			}
			score += 3 * aff / math.Sqrt(float64(len(it.Genres)))
		}
		score += rng.Float64() * 1.2
		list = append(list, scored{it, score})
	}
	sort.SliceStable(list, func(i, j int) bool { return list[i].score > list[j].score })
	out := make([]*library.Item, 0, len(list))
	for _, s := range list {
		out = append(out, s.it)
	}
	return out
}

func (v *view) recentItems() []*library.Item {
	last := map[string]int64{}
	for id, u := range v.ud {
		if u.LastPlayedAt == 0 || (!u.Played && u.Position <= 0) {
			continue
		}
		it := v.snap.Items[id]
		if it == nil || it.Type == "series" {
			continue
		}
		key := it.ID
		if it.Type == "episode" {
			key = it.SeriesID
		}
		if u.LastPlayedAt > last[key] {
			last[key] = u.LastPlayedAt
		}
	}
	var out []*library.Item
	for id := range last {
		if it := v.snap.Items[id]; it != nil {
			out = append(out, it)
		}
	}
	sort.Slice(out, func(i, j int) bool {
		if last[out[i].ID] != last[out[j].ID] {
			return last[out[i].ID] > last[out[j].ID]
		}
		return out[i].ID < out[j].ID
	})
	return out
}

func (v *view) topRatedItems() []*library.Item {
	likes := v.s.St.LikeCounts()
	var liked, rated []*library.Item
	for _, list := range [][]*library.Item{v.snap.Movies, v.snap.Series} {
		for _, it := range list {
			if likes[it.ID] > 0 {
				liked = append(liked, it)
			} else if it.Rating >= 7 {
				rated = append(rated, it)
			}
		}
	}
	sort.SliceStable(liked, func(i, j int) bool {
		if likes[liked[i].ID] != likes[liked[j].ID] {
			return likes[liked[i].ID] > likes[liked[j].ID]
		}
		return liked[i].Rating > liked[j].Rating
	})
	sort.SliceStable(rated, func(i, j int) bool { return rated[i].Rating > rated[j].Rating })
	return append(liked, rated...)
}

func (v *view) addedItems() []*library.Item {
	all := append(append([]*library.Item{}, v.snap.Movies...), v.snap.Series...)
	sort.SliceStable(all, func(i, j int) bool { return all[i].AddedAt > all[j].AddedAt })
	return all
}

func (v *view) sample(list []*library.Item, salt string) []*library.Item {
	cp := append([]*library.Item{}, list...)
	rng := dailyRand(v.profile, salt)
	rng.Shuffle(len(cp), func(i, j int) { cp[i], cp[j] = cp[j], cp[i] })
	return limit(cp, rowLimit)
}

func (v *view) home() homeJSON {
	h := homeJSON{Hero: []ItemJSON{}, Rows: []rowJSON{}}
	add := func(id, title string, items []*library.Item) {
		items = limit(items, rowLimit)
		if len(items) > 0 {
			h.Rows = append(h.Rows, rowJSON{ID: id, Title: title, Items: v.items(items)})
		}
	}
	cont := v.continueItems()
	rec := v.recommendedItems()
	added := v.addedItems()
	add("continue", "Devam Et", cont)
	add("nextup", "Sıradaki Bölümler", v.nextUpItems(cont))
	add("recommended", "Senin İçin Önerilenler", rec)
	add("recent", "Son İzlenenler", v.recentItems())
	add("toprated", "En Beğenilenler", v.topRatedItems())
	add("added", "Son Eklenenler", added)
	add("movies", "Filmler", v.sample(v.snap.Movies, "movies"))
	add("series", "Diziler", v.sample(v.snap.Series, "series"))

	// hero: recommended + recently added, real backdrops first
	seen := map[string]bool{}
	var withBD, without []*library.Item
	for _, it := range append(limit(rec, 12), limit(added, 12)...) {
		if seen[it.ID] {
			continue
		}
		seen[it.ID] = true
		if it.RealBackdrop() {
			withBD = append(withBD, it)
		} else {
			without = append(without, it)
		}
	}
	h.Hero = v.items(limit(append(withBD, without...), 6))
	return h
}

var reDigitsAPI = regexp.MustCompile(`\d+`)

func collectionKey(it *library.Item) string {
	return names.Key(reDigitsAPI.ReplaceAllString(it.ParsedTitle, ""))
}

func leadingNumber(name string) bool {
	return len(name) > 0 && name[0] >= '0' && name[0] <= '9'
}

// nextInFolder returns the next movie of a numbered collection in the same folder.
func (v *view) nextInFolder(it *library.Item) *library.Item {
	dir := path.Dir(it.RelPath)
	var sibs []*library.Item
	for _, m := range v.snap.Movies {
		if m.FolderID == it.FolderID && path.Dir(m.RelPath) == dir {
			sibs = append(sibs, m)
		}
	}
	if len(sibs) < 2 {
		return nil
	}
	sort.SliceStable(sibs, func(i, j int) bool { return names.NaturalLess(sibs[i].FileName, sibs[j].FileName) })
	for i, m := range sibs {
		if m.ID != it.ID || i+1 >= len(sibs) {
			continue
		}
		next := sibs[i+1]
		if ck := collectionKey(it); ck != "" && ck == collectionKey(next) && reDigitsAPI.MatchString(it.FileName) {
			return next
		}
		if leadingNumber(it.FileName) && leadingNumber(next.FileName) {
			return next
		}
	}
	return nil
}

func jaccard(a, b []string) float64 {
	if len(a) == 0 || len(b) == 0 {
		return 0
	}
	set := map[string]bool{}
	for _, x := range a {
		set[x] = true
	}
	inter := 0
	for _, x := range b {
		if set[x] {
			inter++
		}
	}
	return float64(inter) / float64(len(a)+len(b)-inter)
}

func pairJitter(a, b string) float64 {
	h := fnv.New32a()
	h.Write([]byte(a + b))
	return float64(h.Sum32()%1000) / 1000
}

// similar returns up to n items similar to it.
func (v *view) similar(it *library.Item, n int) []*library.Item {
	base := it
	if it.Type == "episode" && it.Series != nil {
		base = it.Series
	}
	type scored struct {
		it    *library.Item
		score float64
	}
	var list []scored
	for _, group := range [][]*library.Item{v.snap.Movies, v.snap.Series} {
		for _, c := range group {
			if c.ID == base.ID {
				continue
			}
			score := 3*jaccard(base.Genres, c.Genres) + c.Rating/10 + pairJitter(base.ID, c.ID)*0.8
			if (c.Type == "series") == (base.Type == "series") {
				score += 0.5
			}
			if base.Type == "movie" && c.Type == "movie" && c.FolderID == base.FolderID && path.Dir(c.RelPath) == path.Dir(base.RelPath) && path.Dir(base.RelPath) != "." {
				score += 0.7
			}
			if v.ud[c.ID].Played {
				score -= 0.5
			}
			list = append(list, scored{c, score})
		}
	}
	sort.SliceStable(list, func(i, j int) bool { return list[i].score > list[j].score })
	out := []*library.Item{}
	for i := 0; i < len(list) && i < n; i++ {
		out = append(out, list[i].it)
	}
	return out
}

type relatedJSON struct {
	Next        *ItemJSON  `json:"next"`
	Episodes    []ItemJSON `json:"episodes"`
	Recommended []ItemJSON `json:"recommended"`
}

func (v *view) related(it *library.Item) relatedJSON {
	r := relatedJSON{Episodes: []ItemJSON{}}
	switch it.Type {
	case "episode":
		ser := it.Series
		var season []*library.Item
		cur := -1
		for i, e := range ser.Episodes {
			if e.ID == it.ID && i+1 < len(ser.Episodes) {
				r.Next = v.itemPtr(ser.Episodes[i+1])
			}
			if e.Season == it.Season {
				if e.ID == it.ID {
					cur = len(season)
				}
				season = append(season, e)
			}
		}
		// window of up to 20 other episodes, starting just after the current one
		var others []*library.Item
		for i := 1; i < len(season) && len(others) < 20; i++ {
			others = append(others, season[(cur+i)%len(season)])
		}
		sort.SliceStable(others, func(i, j int) bool { return library.EpisodeLess(others[i], others[j]) })
		r.Episodes = v.items(others)
	case "series":
		r.Next = v.itemPtr(v.nextUp(it, false))
	default:
		r.Next = v.itemPtr(v.nextInFolder(it))
	}
	r.Recommended = v.items(v.similar(it, 12))
	return r
}

type searchJSON struct {
	Movies   []ItemJSON `json:"movies"`
	Series   []ItemJSON `json:"series"`
	Episodes []ItemJSON `json:"episodes"`
}

func (v *view) search(q string) searchJSON {
	res := searchJSON{Movies: []ItemJSON{}, Series: []ItemJSON{}, Episodes: []ItemJSON{}}
	fq := names.Fold(q)
	if fq == "" {
		return res
	}
	toks := strings.Fields(fq)
	match := func(list []*library.Item, max int) []*library.Item {
		type scored struct {
			it    *library.Item
			score int
		}
		var out []scored
		for _, it := range list {
			ok := true
			for _, t := range toks {
				if !strings.Contains(it.Search, t) {
					ok = false
					break
				}
			}
			if !ok {
				continue
			}
			ft := names.Fold(it.Title)
			score := 3
			switch {
			case ft == fq:
				score = 0
			case strings.HasPrefix(ft, fq):
				score = 1
			case strings.Contains(ft, fq):
				score = 2
			}
			out = append(out, scored{it, score})
		}
		sort.SliceStable(out, func(i, j int) bool { return out[i].score < out[j].score })
		items := []*library.Item{}
		for i := 0; i < len(out) && i < max; i++ {
			items = append(items, out[i].it)
		}
		return items
	}
	res.Movies = v.items(match(v.snap.Movies, 50))
	series := match(v.snap.Series, 50)
	res.Series = v.items(series)
	matchedSeries := map[string]bool{}
	for _, s := range series {
		matchedSeries[s.ID] = true
	}
	// episodes of a matched series are only listed when their own title matches
	var eps []*library.Item
	for _, e := range v.snap.Episodes {
		if matchedSeries[e.SeriesID] && !strings.Contains(names.Fold(e.Title), fq) {
			continue
		}
		eps = append(eps, e)
	}
	sort.SliceStable(eps, func(i, j int) bool {
		if eps[i].SeriesID != eps[j].SeriesID {
			return eps[i].Series.SortKey < eps[j].Series.SortKey
		}
		return library.EpisodeLess(eps[i], eps[j])
	})
	res.Episodes = v.items(match(eps, 50))
	return res
}
