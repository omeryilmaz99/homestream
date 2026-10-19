#!/bin/bash
# builds fake libraries under $S/lib1 (default) and $S/ext (second folder)
set -e
S="${1:?work dir}"
rm -rf "$S/lib1" "$S/ext" "$S/data"
A="$S/base/a.mkv"; B="$S/base/b.mp4"
L="$S/lib1"
mk() { mkdir -p "$(dirname "$2")"; cp "$1" "$2"; }
mk "$A" "$L/Filmler/Inception (2010)/Inception.mkv"
mk "$B" "$L/Filmler/Görevimiz Gülmek.2019.1080p.WEB-DL.mp4"
mk "$A" "$L/Filmler/Koleksiyon/Rocky 1 (1976).mkv"
mk "$B" "$L/Filmler/Koleksiyon/Rocky 2 (1979).mp4"
mk "$A" "$L/Filmler/Derin/İç İçe/Klasör/The.Matrix.1999.1080p.BluRay.x264.mkv"
mk "$A" "$L/Diziler/Breaking Bad/Season 1/Breaking.Bad.S01E01.Pilot.720p.mkv"
mk "$B" "$L/Diziler/Breaking Bad/Season 1/Breaking.Bad.S01E02.mp4"
mk "$A" "$L/Diziler/Breaking Bad/Season 1/Breaking.Bad.S01E10.mkv"
mk "$B" "$L/Diziler/Breaking Bad/Season 2/Breaking.Bad.S02E01.mp4"
mk "$A" "$L/Diziler/Dark/Dark.S01E01.mkv"
mk "$B" "$L/Diziler/Dark/Dark.S01E02.mkv"
mk "$A" "$L/Diziler/Kurtlar Vadisi/1. Sezon/2. Bölüm.mkv"
mk "$B" "$L/Diziler/Kurtlar Vadisi/1. Sezon/10. Bölüm.mp4"
# tiny/sample files that must be skipped
head -c 2000000 "$A" > "$L/Filmler/Inception (2010)/inception-sample.mkv"
head -c 1000 "$A" > "$L/Filmler/tiny.mkv"
mkdir -p "$L/.hidden" && cp "$B" "$L/.hidden/Secret.mp4"
mkdir -p "$L/@eaDir" && cp "$B" "$L/@eaDir/Thumb.mp4"
# Turkish subtitle in cp1254
printf '1\r\n00:00:01,000 --> 00:00:04,000\r\nGörevimiz çok güzel, ışık ve şeker!\r\n' | iconv -f utf-8 -t cp1254 > "$L/Filmler/Inception (2010)/Inception.tr.srt"
printf '1\n00:00:01,000 --> 00:00:04,000\nHello\n' > "$L/Filmler/Inception (2010)/Inception.eng.forced.srt"
# local poster for Inception
ffmpeg -loglevel error -f lavfi -i "color=c=red:s=400x600" -frames:v 1 "$L/Filmler/Inception (2010)/poster.jpg"
# symlink loop
ln -s "$L/Filmler" "$L/Filmler/Derin/loop"
# external folder
E="$S/ext/Harici"
mk "$A" "$E/Belgesel.Gezegen.2020.mkv"
mk "$B" "$E/Dark/Dark.S01E03.mp4"
