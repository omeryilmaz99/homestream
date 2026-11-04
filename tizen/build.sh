#!/bin/bash
# Builds a signed HomeStream.wgt with the Tizen CLI (Tizen Studio).
#   ./build.sh                -> signs with the active profile of Certificate Manager
#   ./build.sh my-profile     -> signs with that security profile
#   ./build.sh --unsigned     -> plain zip (what CI publishes; sign it before installing)
set -e
cd "$(dirname "$0")"
out=.buildResult
rm -rf "$out" HomeStream.wgt
mkdir -p "$out"
cp -r config.xml index.html icon.png css js "$out"/

if [ "$1" = "--unsigned" ]; then
  (cd "$out" && zip -qr ../HomeStream.wgt .)
else
  command -v tizen >/dev/null || { echo "tizen komutu bulunamadı: Tizen Studio'nun tools/ide/bin klasörünü PATH'e ekle"; exit 1; }
  if [ -n "$1" ]; then tizen package -t wgt -s "$1" -- "$out"; else tizen package -t wgt -- "$out"; fi
  mv "$out"/*.wgt HomeStream.wgt
fi
rm -rf "$out"
ls -la HomeStream.wgt
