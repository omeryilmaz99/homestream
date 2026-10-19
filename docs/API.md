# Home Stream API (v1)

Base URL: `http://<host>:8420`. JSON everywhere, UTF-8. No authentication (home LAN).
CORS: allow `*` (future web/TV clients).

Profile context: every request that returns or changes per-user data takes the
profile id from header `X-Profile: <profileId>` (or query `?profile=<id>` as a
fallback, used by external players / image URLs). Without a profile, `userData`
is omitted/zero and write endpoints return 400.

Errors: non-2xx with body `{"error": "message in Turkish"}`.

Times are unix seconds (integers). Durations/positions are seconds (float).

## Discovery

UDP port **8421**. Client broadcasts the ASCII datagram `HOMESTREAM_DISCOVER`
to 255.255.255.255:8421 (and to each interface broadcast). Server replies
(unicast to the sender) with JSON:
`{"app":"homestream","id":"<serverId>","name":"<serverName>","port":8420,"version":"1.0.0"}`.

## Objects

### Item (summary form, used in lists)
```json
{
  "id": "a1b2c3d4e5f60718",          // stable: first 16 hex of sha1(type + ":" + key)
  "type": "movie" | "series" | "episode",
  "title": "Inception",
  "year": 2010,                      // 0 if unknown
  "overview": "…",                   // may be ""
  "genres": ["Bilim Kurgu", "Aksiyon"],
  "rating": 8.4,                     // TMDB vote average, 0 if unknown
  "duration": 8880.5,                // seconds; for series: 0
  "poster": "/api/images/<id>/poster",     // always present (server falls back)
  "backdrop": "/api/images/<id>/backdrop", // always present (server falls back)
  "posterGenerated": true,           // true when no real poster exists (client overlays the title)
  "addedAt": 1760000000,
  "seriesId": "…",                   // episode only
  "seriesTitle": "Breaking Bad",     // episode only
  "season": 1, "episode": 2,         // episode only (season 0 = specials/unknown)
  "episodeCount": 62,                // series only
  "seasonCount": 5,                  // series only
  "unwatchedCount": 10,              // series only, per profile
  "userData": {
    "position": 1234.5,              // resume point, 0 = start
    "played": false,
    "playCount": 0,
    "lastPlayedAt": 0,
    "liked": false
  }
}
```

### Item (detail form, `GET /api/items/{id}`)
Summary fields plus:
- movie / episode: `"file": MediaFile`
- series: `"seasons": [{"number":1,"title":"1. Sezon","episodes":[Item(episode summary + file not needed)]}]`, and `"nextUp": Item|null` (episode to play for this profile: first in-progress, else first unplayed after last played, else first).
- episode: `"stillGenerated"` not needed; `backdrop` of an episode is its own frame thumbnail.

### MediaFile
```json
{
  "path": "Filmler/Inception (2010)/Inception.mkv",   // display path, relative to its library folder, prefixed with the folder's name
  "size": 12345678,
  "container": "matroska",
  "videoCodec": "hevc", "width": 3840, "height": 2160, "hdr": true,
  "bitrate": 25000000,
  "audio": [{"index":0,"codec":"eac3","language":"tur","channels":6,"title":"Türkçe DD+"}],
  "subtitles": [{"index":0,"codec":"subrip","language":"eng","title":"","forced":false,"default":false}],
  "externalSubtitles": [{"id":"<subId>","language":"tr","title":"Türkçe","format":"srt","url":"/api/subtitles/<subId>"}],
  "streamUrl": "/api/stream/<itemId>"
}
```
External subtitles: files next to the video whose name starts with the video's base
name and has extension srt/ass/ssa/vtt/sub/idx(+sub)/sup; also files inside a
`Subs`/`Subtitles`/`Altyazı` folder beside the video. Language parsed from
suffix like `Movie.tr.srt`, `Movie.Turkish.srt`, `Movie.eng.forced.srt`.

### Profile
```json
{"id":"p_xxxxxxxx","name":"Ömer","color":"#E50914","avatar":"😀","createdAt":1760000000}
```

## Endpoints

| Method | Path | Notes |
|---|---|---|
| GET | `/api/info` | `{"app":"homestream","id","name","version","itemCount","movieCount","seriesCount","episodeCount","scanning":bool}` |
| GET | `/api/profiles` | `[Profile]` |
| POST | `/api/profiles` | body `{name,color,avatar}` → Profile |
| PUT | `/api/profiles/{id}` | body `{name,color,avatar}` → Profile |
| DELETE | `/api/profiles/{id}` | deletes profile and its user data |
| GET | `/api/home` | `{"hero":[Item…≤6], "rows":[{"id":"continue","title":"Devam Et","items":[Item]}…]}` see below |
| GET | `/api/movies` | query `sort=title|added|year|rating|lastPlayed`, `order=asc|desc`, `genre=`, `filter=unwatched|watched|liked` → `[Item]` |
| GET | `/api/series` | same query → `[Item]` (series) |
| GET | `/api/genres` | `["Aksiyon", …]` |
| GET | `/api/items/{id}` | detail form |
| GET | `/api/items/{id}/related` | `{"next":Item|null,"episodes":[Item],"recommended":[Item]}` — `next` = next episode in series order (or next video file in the same folder for movies that are part of a numbered collection; else null). `episodes` = other episodes of the same season (≤20). `recommended` = up to 12 similar items. |
| POST | `/api/items/{id}/progress` | body `{"position":123.4,"duration":5400}` — stores resume point; if position/duration ≥ 0.92 or remaining < 120 s (and duration > 600) → mark played, position = 0, playCount++. Always updates lastPlayedAt. Returns userData. |
| POST | `/api/items/{id}/played` | body `{"played":true}`; on a series applies to all its episodes. Returns userData. |
| POST | `/api/items/{id}/like` | body `{"liked":true}` (movie or series) → userData |
| DELETE | `/api/items/{id}/progress` | remove from "continue watching" (position=0, keep played) |
| GET | `/api/search?q=` | `{"movies":[Item],"series":[Item],"episodes":[Item]}` accent/case-insensitive (Turkish İ/ı aware), matches title, series title, original file name |
| GET | `/api/browse?path=` | folder browser over library folders. `path=""` → library folder list. Response `{"path":"", "name":"Kütüphane", "parent":null, "entries":[{"name","path","type":"dir"|"video","size","itemId"?,"duration"?,"userData"?,"thumb"?}]}`. Paths are `<folderId>/<rel/path>`. Dirs first, natural sort (2 < 10). Only video files are listed. |
| GET | `/api/stream/{itemId}` | raw file, HTTP Range support, correct Content-Type, `Accept-Ranges: bytes`. Also works with `HEAD`. |
| GET | `/api/subtitles/{subId}` | the subtitle file (text files re-encoded to UTF-8 if they were cp1254/latin) |
| GET | `/api/images/{itemId}/{kind}` | kind = `poster` (2:3) | `backdrop` (16:9) | `thumb` (16:9 episode/movie frame). Query `w=` width (snapped to 160/320/480/780/1280/1920). JPEG, `Cache-Control: public, max-age=604800`, ETag. Fallback chain: local image file → TMDB → generated frame from the video (poster: center-crop of frame) → a dark generated placeholder. Never 404 for a known item. |
| GET | `/api/settings` | `{"serverName","libraryFolders":[{"id","path","name","available":bool,"itemCount"}],"tmdbApiKey":"(masked or empty)","tmdbEnabled":bool,"metadataLanguage":"tr-TR","scanIntervalMinutes":30}` |
| PUT | `/api/settings` | partial body with any of `serverName`, `tmdbApiKey`, `metadataLanguage`, `scanIntervalMinutes` |
| POST | `/api/folders` | body `{"path":"/media/disk1/Filmler","name":"Harici Disk"}` → adds a library folder and starts a scan |
| DELETE | `/api/folders/{id}` | removes a library folder (not the default HomeStream folder) and its items |
| GET | `/api/fs?path=/` | server filesystem directory picker: `{"path":"/media","parent":"/","dirs":[{"name","path"}]}` (hidden dirs and /proc,/sys,/dev,/run skipped) |
| POST | `/api/scan` | start a full scan (`{"refreshMetadata":false}` optional) |
| GET | `/api/scan/status` | `{"running":bool,"phase":"Dosyalar taranıyor","done":12,"total":340,"lastScanAt":1760000000,"lastError":""}` |

### Home rows (in this order, empty rows omitted)
1. `continue` "Devam Et" — in-progress movies/episodes (position > 0, not played), by lastPlayedAt desc.
2. `nextup` "Sıradaki Bölümler" — for series the profile watched recently (and not in `continue`), the next unplayed episode.
3. `recommended` "Senin İçin Önerilenler" — unwatched items scored by genre overlap with the profile's played/liked items + rating + small daily-seeded randomness. With no history: highest rated / random unwatched.
4. `recent` "Son İzlenenler" — played or partially played movies/series (series collapsed), lastPlayedAt desc.
5. `toprated` "En Beğenilenler" — items liked by any profile (like count desc) then by TMDB rating ≥ 7.
6. `added` "Son Eklenenler" — movies + series by addedAt desc.
7. `movies` "Filmler", `series` "Diziler" — random sample.
Up to 20 items per row. `hero` = up to 6 items with a real backdrop preferred (recommended + recently added).
