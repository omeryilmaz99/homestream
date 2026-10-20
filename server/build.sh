#!/usr/bin/env bash
# Builds static Linux binaries into dist/ (amd64 + arm64).
set -euo pipefail
cd "$(dirname "$0")"
VERSION="${VERSION:-1.2.1}"
GO="${GO:-$(command -v go || echo /usr/local/go/bin/go)}"
export GOTOOLCHAIN="${GOTOOLCHAIN:-local}"
mkdir -p dist
for arch in amd64 arm64; do
  echo "building dist/homestream-server-linux-$arch ($VERSION)"
  CGO_ENABLED=0 GOOS=linux GOARCH="$arch" "$GO" build -trimpath \
    -ldflags "-s -w -X main.version=$VERSION" \
    -o "dist/homestream-server-linux-$arch" .
done
cp install.sh dist/install.sh
(cd dist && sha256sum homestream-server-linux-* > SHA256SUMS)
ls -l dist
