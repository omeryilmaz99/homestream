#!/usr/bin/env python3
"""End-to-end smoke test for homestream-server. Usage: smoke.py BASE_URL LIB1 EXT DISCOVERY_PORT"""
import json, os, socket, sys, time, struct, urllib.request, urllib.error

BASE, LIB1, EXT, DPORT = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
passed, failed = 0, []


def check(name, cond, info=""):
    global passed
    if cond:
        passed += 1
        print("  ok  ", name)
    else:
        failed.append(name)
        print("  FAIL", name, info)


def req(method, path, body=None, headers=None, raw=False):
    data = json.dumps(body).encode() if body is not None else None
    h = {"Content-Type": "application/json"}
    h.update(headers or {})
    r = urllib.request.Request(BASE + path, data=data, method=method, headers=h)
    try:
        resp = urllib.request.urlopen(r, timeout=30)
        status, hdrs, content = resp.status, resp.headers, resp.read()
    except urllib.error.HTTPError as e:
        status, hdrs, content = e.code, e.headers, e.read()
    if raw:
        return status, hdrs, content
    try:
        return status, json.loads(content) if content else None
    except Exception:
        return status, content


def wait_scan():
    time.sleep(0.5)
    for _ in range(240):
        s = req("GET", "/api/scan/status")[1]
        if not s["running"] and not s["queued"]:
            return s
        time.sleep(0.5)
    raise SystemExit("scan did not finish")


def jpeg_size(b):
    i = 2
    while i < len(b):
        if b[i] != 0xFF:
            i += 1
            continue
        m = b[i + 1]
        if m in (0xC0, 0xC1, 0xC2):
            h, w = struct.unpack(">HH", b[i + 5:i + 9])
            return w, h
        ln = struct.unpack(">H", b[i + 2:i + 4])[0]
        i += 2 + ln
    return None


def by_title(items):
    return {x["title"]: x for x in items}


print("== info / scan")
st, info = req("GET", "/api/info")
check("info app", st == 200 and info["app"] == "homestream" and info["version"] == "1.0.0", info)
st, s = req("POST", "/api/scan", {"refreshMetadata": False})
check("scan accepted", st == 202, st)
s = wait_scan()
check("scan status fields", all(k in s for k in ("running", "phase", "done", "total", "lastScanAt", "lastError")), s)
st, info = req("GET", "/api/info")
check("counts", (info["movieCount"], info["seriesCount"], info["episodeCount"]) == (5, 3, 8), info)

print("== profiles")
st, p = req("POST", "/api/profiles", {"name": "Ömer", "color": "#E50914", "avatar": "😀"})
check("create profile", st == 201 and p["id"].startswith("p_") and p["name"] == "Ömer", p)
PID = p["id"]
st, p2 = req("POST", "/api/profiles", {"name": "Ayşe"})
check("create profile 2 defaults", st == 201 and p2["color"] == "#E50914" and p2["avatar"], p2)
st, e = req("POST", "/api/profiles", {"name": "  "})
check("empty name rejected", st == 400 and "error" in e, e)
st, up = req("PUT", "/api/profiles/" + p2["id"], {"name": "Ayşe Y", "color": "#00FF00"})
check("update profile", st == 200 and up["name"] == "Ayşe Y" and up["color"] == "#00FF00", up)
st, ps = req("GET", "/api/profiles")
check("list profiles", st == 200 and len(ps) == 2, ps)
H = {"X-Profile": PID}

print("== lists")
st, movies = req("GET", "/api/movies", headers=H)
mt = by_title(movies)
check("movie titles", set(mt) == {"Görevimiz Gülmek", "Inception", "Rocky 1", "Rocky 2", "The Matrix"}, list(mt))
check("movie years", mt["Inception"]["year"] == 2010 and mt["The Matrix"]["year"] == 1999 and mt["Görevimiz Gülmek"]["year"] == 2019)
check("movie duration probed", abs(mt["Inception"]["duration"] - 30) < 1, mt["Inception"]["duration"])
check("local poster -> posterGenerated false", mt["Inception"]["posterGenerated"] is False and mt["The Matrix"]["posterGenerated"] is True)
check("summary has userData", "userData" in mt["Inception"])
st, ms = req("GET", "/api/movies?sort=year&order=desc")
check("sort year desc", [m["year"] for m in ms] == sorted([m["year"] for m in ms], reverse=True), [m["year"] for m in ms])
st, ms = req("GET", "/api/movies?sort=title")
check("sort title asc natural", [m["title"] for m in ms][2:4] == ["Rocky 1", "Rocky 2"], [m["title"] for m in ms])
st, series = req("GET", "/api/series", headers=H)
sr = by_title(series)
check("series titles", set(sr) == {"Breaking Bad", "Dark", "Kurtlar Vadisi"}, list(sr))
bb = sr["Breaking Bad"]
check("series counts", bb["episodeCount"] == 4 and bb["seasonCount"] == 2 and bb["unwatchedCount"] == 4 and bb["duration"] == 0, bb)
st, genres = req("GET", "/api/genres")
check("genres", st == 200 and genres == [], genres)

print("== item detail")
st, d = req("GET", "/api/items/" + bb["id"], headers=H)
check("series seasons", [x["number"] for x in d["seasons"]] == [1, 2] and d["seasons"][0]["title"] == "1. Sezon", d.get("seasons"))
eps1 = d["seasons"][0]["episodes"]
check("episode natural order", [e["episode"] for e in eps1] == [1, 2, 10], [e["episode"] for e in eps1])
check("episode title parsed", eps1[0]["title"] == "Pilot" and eps1[1]["title"] == "Bölüm 2", [e["title"] for e in eps1])
check("episode fields", eps1[0]["seriesId"] == bb["id"] and eps1[0]["seriesTitle"] == "Breaking Bad" and eps1[0]["season"] == 1)
check("nextUp first", d["nextUp"]["id"] == eps1[0]["id"], d["nextUp"])
st, kv = req("GET", "/api/items/" + sr["Kurtlar Vadisi"]["id"])
check("Turkish season/episodes", [e["episode"] for e in kv["seasons"][0]["episodes"]] == [2, 10] and kv["seasons"][0]["number"] == 1)
st, inc = req("GET", "/api/items/" + mt["Inception"]["id"], headers=H)
f = inc["file"]
check("media file path", f["path"] == "lib1/Filmler/Inception (2010)/Inception.mkv", f["path"])
check("media file probe", f["container"] == "matroska" and f["videoCodec"] == "h264" and f["width"] == 640 and f["height"] == 360, f)
check("audio tracks", f["audio"] and f["audio"][0]["language"] == "tur" and f["audio"][0]["title"] == "Türkçe", f["audio"])
check("embedded subs", f["subtitles"] and f["subtitles"][0]["language"] == "eng" and f["subtitles"][0]["codec"] == "subrip", f["subtitles"])
ext = f["externalSubtitles"]
check("external subs", len(ext) == 2 and ext[0]["language"] == "tr" and ext[0]["title"] == "Türkçe" and ext[1]["forced"], ext)
check("stream url", f["streamUrl"] == "/api/stream/" + inc["id"])
st, e = req("GET", "/api/items/0000000000000000")
check("unknown item 404", st == 404 and e["error"], e)

print("== related")
st, rel = req("GET", "/api/items/%s/related" % eps1[0]["id"], headers=H)
check("related next episode", rel["next"]["id"] == eps1[1]["id"], rel["next"])
check("related season episodes", [e["episode"] for e in rel["episodes"]] == [2, 10], [e["episode"] for e in rel["episodes"]])
check("related recommended", 0 < len(rel["recommended"]) <= 12 and all(r["id"] != bb["id"] for r in rel["recommended"]))
st, rel = req("GET", "/api/items/%s/related" % eps1[2]["id"])
check("related next across seasons", rel["next"]["season"] == 2 and rel["next"]["episode"] == 1, rel["next"])
st, rel = req("GET", "/api/items/%s/related" % mt["Rocky 1"]["id"])
check("collection next", rel["next"] and rel["next"]["title"] == "Rocky 2", rel["next"])
st, rel = req("GET", "/api/items/%s/related" % mt["Inception"]["id"])
check("no next for standalone movie", rel["next"] is None and rel["episodes"] == [], rel["next"])

print("== user data")
iid = mt["Inception"]["id"]
st, e = req("POST", "/api/items/%s/progress" % iid, {"position": 10, "duration": 30})
check("progress without profile -> 400", st == 400 and e["error"] == "Profil seçilmedi", e)
st, u = req("POST", "/api/items/%s/progress" % iid, {"position": 10, "duration": 30}, H)
check("progress stored", st == 200 and u["position"] == 10 and not u["played"] and u["lastPlayedAt"] > 0, u)
st, home = req("GET", "/api/home", headers=H)
rows = {r["id"]: r for r in home["rows"]}
check("continue row", "continue" in rows and rows["continue"]["title"] == "Devam Et" and rows["continue"]["items"][0]["id"] == iid, list(rows))
check("continue first row", home["rows"][0]["id"] == "continue")
st, u = req("POST", "/api/items/%s/progress" % iid, {"position": 28, "duration": 30}, H)
check("played threshold", u["played"] and u["position"] == 0 and u["playCount"] == 1, u)
st, u = req("POST", "/api/items/%s/progress" % iid, {"position": 29, "duration": 30}, H)
check("no double count during credits", u["playCount"] == 1, u)
st, home = req("GET", "/api/home", headers=H)
rows = {r["id"]: r for r in home["rows"]}
check("not in continue after played", "continue" not in rows or all(i["id"] != iid for i in rows["continue"]["items"]))
check("recent row", "recent" in rows and rows["recent"]["items"][0]["id"] == iid and rows["recent"]["title"] == "Son İzlenenler")
# episode played -> nextup
st, u = req("POST", "/api/items/%s/played" % eps1[0]["id"], {"played": True}, H)
check("mark episode played", u["played"] and u["playCount"] == 1, u)
st, home = req("GET", "/api/home", headers=H)
rows = {r["id"]: r for r in home["rows"]}
check("nextup row", "nextup" in rows and rows["nextup"]["items"][0]["id"] == eps1[1]["id"] and rows["nextup"]["title"] == "Sıradaki Bölümler", rows.get("nextup"))
check("recent collapses series", any(i["id"] == bb["id"] for i in rows["recent"]["items"]))
st, d = req("GET", "/api/items/" + bb["id"], headers=H)
check("series nextUp after played", d["nextUp"]["id"] == eps1[1]["id"] and d["unwatchedCount"] == 3)
st, u = req("POST", "/api/items/%s/progress" % eps1[1]["id"], {"position": 5, "duration": 30}, H)
st, d = req("GET", "/api/items/" + bb["id"], headers=H)
check("series nextUp in-progress", d["nextUp"]["id"] == eps1[1]["id"])
st, home = req("GET", "/api/home", headers=H)
rows = {r["id"]: r for r in home["rows"]}
check("nextup skips series in continue", "nextup" not in rows or all(i["seriesId"] != bb["id"] for i in rows["nextup"]["items"]))
st, u = req("DELETE", "/api/items/%s/progress" % eps1[1]["id"], headers=H)
check("delete progress", st == 200 and u["position"] == 0, u)
gid = mt["Görevimiz Gülmek"]["id"]
st, u = req("POST", "/api/items/%s/like" % gid, {"liked": True}, H)
check("like", u["liked"], u)
st, home = req("GET", "/api/home", headers=H)
rows = {r["id"]: r for r in home["rows"]}
check("toprated row", "toprated" in rows and rows["toprated"]["items"][0]["id"] == gid and rows["toprated"]["title"] == "En Beğenilenler")
check("row order", [r["id"] for r in home["rows"]] == [x for x in ["continue", "nextup", "recommended", "recent", "toprated", "added", "movies", "series"] if x in rows], [r["id"] for r in home["rows"]])
check("recommended excludes watched", all(i["id"] != iid for i in rows["recommended"]["items"]))
check("hero", 0 < len(home["hero"]) <= 6)
check("row limit", all(len(r["items"]) <= 20 for r in home["rows"]))
st, home2 = req("GET", "/api/home")
check("home without profile", st == 200 and "continue" not in {r["id"] for r in home2["rows"]})
st, u = req("POST", "/api/items/%s/played" % bb["id"], {"played": True}, H)
check("series played", u["played"], u)
st, s2 = req("GET", "/api/series?filter=watched", headers=H)
check("filter watched series", [x["title"] for x in s2] == ["Breaking Bad"] and s2[0]["unwatchedCount"] == 0, [x["title"] for x in s2])
st, s2 = req("GET", "/api/movies?filter=liked", headers=H)
check("filter liked", [x["id"] for x in s2] == [gid])
st, s2 = req("GET", "/api/movies?filter=unwatched", headers=H)
check("filter unwatched", iid not in [x["id"] for x in s2] and len(s2) == 4)
st, u = req("POST", "/api/items/%s/played" % bb["id"], {"played": False}, H)
check("series unplayed", not u["played"])

print("== search")
st, r = req("GET", "/api/search?q=gorevimiz")
check("search folding gorevimiz", [x["id"] for x in r["movies"]] == [gid], r)
st, r = req("GET", "/api/search?q=G%C3%96REV%C4%B0M%C4%B0Z")
check("search upper GÖREVİMİZ", [x["id"] for x in r["movies"]] == [gid])
st, r = req("GET", "/api/search?q=KURTLAR%20VAD%C4%B0S%C4%B0")
check("search series İ", [x["title"] for x in r["series"]] == ["Kurtlar Vadisi"], r["series"])
st, r = req("GET", "/api/search?q=pilot")
check("search episode", [x["title"] for x in r["episodes"]] == ["Pilot"], r["episodes"])
st, r = req("GET", "/api/search?q=bluray")
check("search by file name", [x["title"] for x in r["movies"]] == ["The Matrix"], r["movies"])
st, r = req("GET", "/api/search?q=")
check("empty search", r == {"movies": [], "series": [], "episodes": []})

print("== browse")
st, b = req("GET", "/api/browse?path=")
check("browse root", b["name"] == "Kütüphane" and b["parent"] is None and b["entries"][0]["type"] == "dir" and b["entries"][0]["path"] == "1", b)
st, b = req("GET", "/api/browse?path=1")
check("browse folder", [e["name"] for e in b["entries"]] == ["Diziler", "Filmler"] and b["parent"] == "", b)
st, b = req("GET", "/api/browse?path=1/Filmler", headers=H)
names_ = [e["name"] for e in b["entries"]]
check("browse dirs first + filters", names_ == ["Derin", "Inception (2010)", "Koleksiyon", "Görevimiz Gülmek.2019.1080p.WEB-DL.mp4"], names_)
st, b = req("GET", "/api/browse?path=1/Diziler/Kurtlar%20Vadisi/1.%20Sezon", headers=H)
check("browse natural sort", [e["name"] for e in b["entries"]] == ["2. Bölüm.mkv", "10. Bölüm.mp4"], b)
v = b["entries"][0]
check("browse video entry", v["type"] == "video" and v["itemId"] and v["duration"] > 0 and "userData" in v and v["thumb"].startswith("/api/images/"), v)
check("browse parent", b["parent"] == "1/Diziler/Kurtlar Vadisi", b["parent"])
st, b = req("GET", "/api/browse?path=1/../../etc")
check("browse traversal blocked", st in (400, 404), st)

print("== stream")
st, h, body = req("HEAD", "/api/stream/" + iid, raw=True)
size = int(h["Content-Length"])
check("HEAD stream", st == 200 and h["Accept-Ranges"] == "bytes" and h["Content-Type"] == "video/x-matroska" and size > 1000000, dict(h))
check("CORS header", h["Access-Control-Allow-Origin"] == "*")
st, h, body = req("GET", "/api/stream/" + iid, headers={"Range": "bytes=100-199"}, raw=True)
check("Range 206", st == 206 and h["Content-Range"] == "bytes 100-199/%d" % size and len(body) == 100, (st, dict(h)))
st, h, body = req("GET", "/api/stream/" + iid, headers={"Range": "bytes=%d-" % (size - 10)}, raw=True)
check("Range suffix", st == 206 and len(body) == 10)
st, h, body = req("GET", "/api/stream/" + mt["Görevimiz Gülmek"]["id"], headers={"Range": "bytes=0-9"}, raw=True)
check("mp4 mime", h["Content-Type"] == "video/mp4" and st == 206)
etag = h["ETag"]
st, h, body = req("GET", "/api/stream/" + mt["Görevimiz Gülmek"]["id"], headers={"Range": "bytes=0-9", "If-Range": etag}, raw=True)
check("If-Range match", st == 206)
st, h, body = req("GET", "/api/stream/" + mt["Görevimiz Gülmek"]["id"], headers={"Range": "bytes=0-9", "If-Range": '"nope"'}, raw=True)
check("If-Range mismatch -> 200", st == 200)

print("== subtitles")
st, h, body = req("GET", ext[0]["url"], raw=True)
txt = body.decode("utf-8")
check("cp1254 -> utf8", "Görevimiz çok güzel, ışık ve şeker!" in txt and h["Content-Type"] == "text/plain; charset=utf-8", txt)
st, h, body = req("GET", ext[0]["url"] + ".srt", raw=True)
check("subtitle with extension", st == 200)
st, e = req("GET", "/api/subtitles/ffffffffffffffff")
check("unknown subtitle 404", st == 404)

print("== images")
st, h, body = req("GET", mt["Inception"]["poster"] + "&w=300", raw=True)
check("poster local w=300 -> 320", st == 200 and h["Content-Type"] == "image/jpeg" and jpeg_size(body) == (320, 480) and "max-age=604800" in h["Cache-Control"], (st, jpeg_size(body)))
et = h["ETag"]
st, h, body = req("GET", mt["Inception"]["poster"] + "&w=300", headers={"If-None-Match": et}, raw=True)
check("poster 304", st == 304)
st, h, body = req("GET", "/api/images/%s/poster?w=480" % mt["The Matrix"]["id"], raw=True)
w_, h_ = jpeg_size(body)
check("generated poster 2:3 crop", st == 200 and w_ <= 480 and abs(w_ / h_ - 2 / 3) < 0.02, (w_, h_))
st, h, body = req("GET", "/api/images/%s/backdrop" % mt["The Matrix"]["id"], raw=True)
w_, h_ = jpeg_size(body)
check("backdrop frame 16:9", st == 200 and abs(w_ / h_ - 16 / 9) < 0.02, (w_, h_))
st, h, body = req("GET", "/api/images/%s/thumb?w=160" % eps1[0]["id"], raw=True)
check("episode thumb w=160", st == 200 and jpeg_size(body)[0] == 160, jpeg_size(body))
st, h, body = req("GET", "/api/images/%s/poster?w=1920" % bb["id"], raw=True)
check("series poster", st == 200 and len(body) > 1000)
st, h, body = req("GET", "/api/images/%s/banner" % bb["id"], raw=True)
check("bad image kind 400", st == 400)
st, h, body = req("GET", "/api/images/0000000000000000/poster", raw=True)
check("unknown image 404", st == 404)

print("== settings / folders")
st, s = req("GET", "/api/settings")
check("settings", s["serverName"] == "Test Sunucu" and s["metadataLanguage"] == "tr-TR" and s["scanIntervalMinutes"] == 30 and s["tmdbEnabled"] is False and s["libraryFolders"][0]["available"] and s["libraryFolders"][0]["itemCount"] == 13, s)
st, s = req("PUT", "/api/settings", {"serverName": "Salon", "scanIntervalMinutes": 60, "tmdbApiKey": "abcdef123456"})
check("put settings", s["serverName"] == "Salon" and s["scanIntervalMinutes"] == 60 and s["tmdbApiKey"] == "••••3456" and s["tmdbEnabled"], s)
st, s = req("PUT", "/api/settings", {"tmdbApiKey": "••••3456"})
check("masked key ignored", s["tmdbEnabled"], s)
st, info = req("GET", "/api/info")
check("name in info", info["name"] == "Salon")
s = wait_scan()
check("scan survives unreachable/invalid TMDB", s["lastError"] != "" and not s["running"], s)
st, s = req("PUT", "/api/settings", {"tmdbApiKey": ""})
check("clear tmdb key", s["tmdbEnabled"] is False and s["tmdbApiKey"] == "")
st, e = req("PUT", "/api/settings", {"metadataLanguage": "türkçe"})
check("bad language rejected", st == 400)
st, fo = req("POST", "/api/folders", {"path": EXT, "name": "Harici Disk"})
check("add folder", st == 201 and fo["name"] == "Harici Disk" and fo["id"] == "2", fo)
st, e = req("POST", "/api/folders", {"path": EXT})
check("duplicate folder 409", st == 409, e)
st, e = req("POST", "/api/folders", {"path": EXT + "/Harici"})
check("nested folder 409", st == 409, e)
st, e = req("POST", "/api/folders", {"path": "/does/not/exist"})
check("missing folder 400", st == 400 and e["error"] == "Klasör bulunamadı")
wait_scan()
st, movies = req("GET", "/api/movies", headers=H)
mt = by_title(movies)
check("external movie added", "Belgesel Gezegen" in mt and mt["Belgesel Gezegen"]["year"] == 2020, list(mt))
st, series = req("GET", "/api/series", headers=H)
sr = by_title(series)
check("series merged across folders", sr["Dark"]["episodeCount"] == 3, sr["Dark"])
st, d = req("GET", "/api/items/" + mt["Belgesel Gezegen"]["id"])
check("external display path", d["file"]["path"] == "Harici Disk/Harici/Belgesel.Gezegen.2020.mkv", d["file"]["path"])
bid = mt["Belgesel Gezegen"]["id"]
req("POST", "/api/items/%s/like" % bid, {"liked": True}, H)

print("== unavailable folder")
os.rename(EXT, EXT + ".gone")
req("POST", "/api/scan")
wait_scan()
st, movies = req("GET", "/api/movies", headers=H)
check("hidden when unavailable", "Belgesel Gezegen" not in by_title(movies))
st, series = req("GET", "/api/series", headers=H)
check("series episodes hidden", by_title(series)["Dark"]["episodeCount"] == 2)
st, s = req("GET", "/api/settings")
f2 = [x for x in s["libraryFolders"] if x["id"] == "2"][0]
check("folder marked unavailable, items kept", f2["available"] is False and f2["itemCount"] == 2, f2)
st, e = req("GET", "/api/items/" + bid)
check("hidden item 404", st == 404)
os.rename(EXT + ".gone", EXT)
req("POST", "/api/scan")
wait_scan()
st, movies = req("GET", "/api/movies", headers=H)
mt = by_title(movies)
check("items come back", "Belgesel Gezegen" in mt and mt["Belgesel Gezegen"]["id"] == bid)
check("user data kept", mt["Belgesel Gezegen"]["userData"]["liked"] is True)
# empty mount point counts as unavailable
os.rename(EXT, EXT + ".gone")
os.mkdir(EXT)
req("POST", "/api/scan")
wait_scan()
st, s = req("GET", "/api/settings")
f2 = [x for x in s["libraryFolders"] if x["id"] == "2"][0]
check("empty mount point -> unavailable", f2["available"] is False and f2["itemCount"] == 2, f2)
os.rmdir(EXT)
os.rename(EXT + ".gone", EXT)
req("POST", "/api/scan")
wait_scan()
# file truly removed
os.rename(EXT + "/Harici/Dark/Dark.S01E03.mp4", EXT + "/Dark.S01E03.mp4.bak")
req("POST", "/api/scan")
wait_scan()
st, series = req("GET", "/api/series")
check("deleted file removed", by_title(series)["Dark"]["episodeCount"] == 2)
os.rename(EXT + "/Dark.S01E03.mp4.bak", EXT + "/Harici/Dark/Dark.S01E03.mp4")
st, e = req("DELETE", "/api/folders/1")
check("default folder not removable", st == 400, e)
st, e = req("DELETE", "/api/folders/2")
check("remove folder", st == 200)
st, movies = req("GET", "/api/movies")
check("folder items removed", "Belgesel Gezegen" not in by_title(movies))

print("== fs picker")
st, fs = req("GET", "/api/fs?path=/")
dn = [d["name"] for d in fs["dirs"]]
check("fs root", fs["path"] == "/" and fs["parent"] is None and "tmp" in dn and "proc" not in dn and "sys" not in dn, dn)
st, fs = req("GET", "/api/fs?path=" + urllib.request.quote(os.path.dirname(LIB1)))
check("fs subdir", fs["parent"] == os.path.dirname(os.path.dirname(LIB1)) and any(d["name"] == "lib1" for d in fs["dirs"]), fs)

print("== discovery")
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.settimeout(3)
sock.sendto(b"HOMESTREAM_DISCOVER", ("127.0.0.1", DPORT))
try:
    data, _ = sock.recvfrom(2048)
    dj = json.loads(data)
    check("discovery reply", dj["app"] == "homestream" and dj["name"] == "Salon" and dj["port"] and dj["version"] == "1.0.0", dj)
except socket.timeout:
    check("discovery reply", False, "timeout")

print("== profile delete")
st, e = req("DELETE", "/api/profiles/" + PID)
check("delete profile", st == 200)
st, e = req("POST", "/api/items/%s/like" % gid, {"liked": True}, {"X-Profile": PID})
check("deleted profile rejected", st == 400)
st, home = req("GET", "/api/home")
check("likes of deleted profile gone", all(r["id"] != "toprated" or all(i["id"] != gid for i in r["items"]) for r in home["rows"]))

print("\n%d passed, %d failed" % (passed, len(failed)))
if failed:
    print("FAILED:", failed)
    sys.exit(1)
