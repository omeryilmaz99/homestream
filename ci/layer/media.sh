#!/bin/bash
# Test films: 1080p H.264 with a Turkish .srt (hardware decodable, should
# play on the video layer) and 10-bit H.264 (not hardware decodable, should
# reopen with the texture renderer).
set -e
mkdir -p ci-lib/Filmler
ffmpeg -v error -y -f lavfi -i testsrc2=size=1920x1080:rate=24 -f lavfi -i sine=frequency=440:sample_rate=48000 \
  -t 120 -c:v libx264 -preset veryfast -pix_fmt yuv420p -g 48 -c:a aac -b:a 128k ci-lib/Filmler/Layertest.2020.mkv
ffmpeg -v error -y -f lavfi -i testsrc2=size=1280x720:rate=24 -f lavfi -i sine=frequency=660:sample_rate=48000 \
  -t 90 -c:v libx264 -preset veryfast -pix_fmt yuv420p10le -profile:v high10 -g 48 -c:a aac -b:a 128k ci-lib/Filmler/Hidepth.2018.mkv
python3 - <<'PY'
lines = []
for i in range(40):
    s, e = i * 3, i * 3 + 2.5
    f = lambda t: "00:%02d:%02d,%03d" % (int(t) // 60, int(t) % 60, int((t % 1) * 1000))
    lines.append(f"{i+1}\n{f(s)} --> {f(e)}\nAltyazı satırı {i+1} — Çok güzel ğüşiöç\n")
open("ci-lib/Filmler/Layertest.2020.tr.srt", "w").write("\n".join(lines))
PY
ffprobe -v error -show_entries stream=codec_name,profile,pix_fmt,width,height -of compact ci-lib/Filmler/*.mkv
ls -la ci-lib/Filmler
