package names

import (
	"path"
	"strings"
)

var langCodes = map[string]string{}

var langNamesTR = map[string]string{
	"tr": "Türkçe", "en": "İngilizce", "de": "Almanca", "fr": "Fransızca", "es": "İspanyolca",
	"it": "İtalyanca", "ru": "Rusça", "ar": "Arapça", "ja": "Japonca", "ko": "Korece",
	"zh": "Çince", "pt": "Portekizce", "nl": "Felemenkçe", "pl": "Lehçe", "sv": "İsveççe",
	"no": "Norveççe", "da": "Danca", "fi": "Fince", "el": "Yunanca", "he": "İbranice",
	"hu": "Macarca", "cs": "Çekçe", "ro": "Romence", "bg": "Bulgarca", "fa": "Farsça",
	"az": "Azerbaycanca", "uk": "Ukraynaca", "hr": "Hırvatça", "sr": "Sırpça", "hi": "Hintçe",
}

func init() {
	add := func(code string, aliases ...string) {
		langCodes[code] = code
		for _, a := range aliases {
			langCodes[Fold(a)] = code
		}
	}
	add("tr", "tur", "turkish", "türkçe", "trk", "turk")
	add("en", "eng", "english", "ingilizce", "enG")
	add("de", "ger", "deu", "german", "almanca", "deutsch")
	add("fr", "fre", "fra", "french", "fransızca", "francais")
	add("es", "spa", "spanish", "ispanyolca", "espanol")
	add("it", "ita", "italian", "italyanca")
	add("ru", "rus", "russian", "rusça")
	add("ar", "ara", "arabic", "arapça")
	add("ja", "jpn", "japanese", "japonca")
	add("ko", "kor", "korean", "korece")
	add("zh", "chi", "zho", "chinese", "çince", "chs", "cht")
	add("pt", "por", "portuguese", "portekizce", "pob", "ptbr")
	add("nl", "dut", "nld", "dutch")
	add("pl", "pol", "polish")
	add("sv", "swe", "swedish")
	add("no", "nor", "norwegian", "nob")
	add("da", "dan", "danish")
	add("fi", "fin", "finnish")
	add("el", "gre", "ell", "greek")
	add("he", "heb", "hebrew")
	add("hu", "hun", "hungarian")
	add("cs", "cze", "ces", "czech")
	add("ro", "rum", "ron", "romanian")
	add("bg", "bul", "bulgarian")
	add("fa", "per", "fas", "persian", "farsi")
	add("az", "aze", "azerbaijani")
	add("uk", "ukr", "ukrainian")
	add("hr", "hrv", "croatian")
	add("sr", "srp", "serbian")
	add("hi", "hin", "hindi")
}

// LangName returns the Turkish display name of a language code ("" if unknown).
func LangName(code string) string { return langNamesTR[code] }

// NormalizeLang maps a language tag (tr, tur, Turkish, Türkçe…) to a 2-letter code.
func NormalizeLang(tag string) string { return langCodes[Fold(tag)] }

// SubInfo describes an external subtitle file.
type SubInfo struct {
	Language string
	Title    string
	Forced   bool
	Format   string
}

// ParseSubtitle extracts language/forced flags from an external subtitle
// file name. videoBase is the video's base name without extension ("" when
// the subtitle doesn't share the video's base name, e.g. Subs/2_English.srt).
func ParseSubtitle(videoBase, subName string) SubInfo {
	ext := strings.ToLower(strings.TrimPrefix(path.Ext(subName), "."))
	base := DisplayString(strings.TrimSuffix(subName, path.Ext(subName)))
	rest := base
	if videoBase != "" && strings.HasPrefix(strings.ToLower(base), strings.ToLower(DisplayString(videoBase))) {
		rest = base[len(DisplayString(videoBase)):]
	}
	info := SubInfo{Format: ext}
	sdh := false
	toks := strings.FieldsFunc(rest, func(r rune) bool {
		return r == '.' || r == '_' || r == '-' || r == ' ' || r == '[' || r == ']' || r == '(' || r == ')'
	})
	for _, t := range toks {
		f := Fold(t)
		switch f {
		case "forced", "zorunlu", "foreign":
			info.Forced = true
			continue
		case "sdh", "cc":
			sdh = true
			continue
		}
		if info.Language == "" {
			if c, ok := langCodes[f]; ok {
				info.Language = c
			}
		}
	}
	if n := LangName(info.Language); n != "" {
		info.Title = n
	} else {
		info.Title = "Harici altyazı"
	}
	if info.Forced {
		info.Title += " (Zorunlu)"
	}
	if sdh {
		info.Title += " (SDH)"
	}
	return info
}
