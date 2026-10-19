#!/bin/bash
# End-to-end smoke test: builds a fake library with ffmpeg, runs the server
# on a random port and exercises every endpoint (scripts/smoke.py).
# Usage: scripts/e2e.sh [path/to/binary]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
BIN="${1:-$HERE/../dist/homestream-server-linux-amd64}"
W="$(mktemp -d)"; trap 'kill $PID 2>/dev/null || true; rm -rf "$W"' EXIT
mkdir -p "$W/base"
printf '1\n00:00:01,000 --> 00:00:05,000\nEmbedded English line\n' > "$W/base/emb.srt"
ffmpeg -loglevel error -f lavfi -i "testsrc2=duration=30:size=640x360:rate=25,noise=alls=40:allf=t+u" -f lavfi -i "sine=frequency=440:duration=30" \
  -i "$W/base/emb.srt" -map 0 -map 1 -map 2 -c:v libx264 -preset ultrafast -crf 32 -c:a aac -c:s srt \
  -metadata:s:a:0 language=tur -metadata:s:a:0 title="Türkçe" -metadata:s:s:0 language=eng "$W/base/a.mkv"
ffmpeg -loglevel error -f lavfi -i "testsrc=duration=30:size=640x360:rate=25,noise=alls=25:allf=t" -f lavfi -i "sine=frequency=660:duration=30" \
  -c:v libx264 -preset ultrafast -b:v 600k -c:a aac -shortest -movflags +faststart "$W/base/b.mp4"
bash "$HERE/mklib.sh" "$W" >/dev/null
find "$W/lib1" "$W/ext" -type f -exec touch -d "3 hours ago" {} +
PORT=$((20000 + RANDOM % 20000)); DPORT=$((PORT + 1))
HOMESTREAM_DISCOVERY_PORT=$DPORT "$BIN" --port $PORT --data "$W/data" --library "$W/lib1" --name "Test Sunucu" > "$W/server.log" 2>&1 &
PID=$!
sleep 2
python3 "$HERE/smoke.py" "http://127.0.0.1:$PORT" "$W/lib1" "$W/ext" $DPORT || { tail -50 "$W/server.log"; exit 1; }
