#!/usr/bin/env bash
# Opt-in installer for a self-contained Node.js + npm (the official nodejs.org
# tarball) into <repo>/.node/. Debian/Ubuntu's `npm` package unbundles npm's
# own dependencies into ~300+ separate node-* system packages plus a native
# build toolchain (node-gyp), a test framework (node-tap), even WebAssembly
# tools (wabt), none of which this repo needs. This sidesteps all of that: no
# sudo, no system package manager, nothing installed outside this repo. Run
# manually:
#   ./scripts/install-node.sh
# Re-run any time to update. Deleting this repo removes everything (.node/ is
# gitignored). Any existing system Node.js is left untouched; this only wins
# inside this repo's scripts because lib.sh puts .node/bin first on PATH.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NODE_DIR="$HERE/.node"

arch="$(uname -m)"
case "$arch" in
  x86_64|amd64)  NODE_ARCH=x64 ;;
  aarch64|arm64) NODE_ARCH=arm64 ;;
  *)
    echo "error: no official Node.js Linux build for arch '$arch'." >&2
    echo "Install Node.js manually: https://nodejs.org" >&2
    exit 1
    ;;
esac

# Pin to the v22.x LTS line (a plain-text SHASUMS listing, no JSON parsing
# needed): grep the exact tarball filename for our arch out of it.
LINE=latest-v22.x
echo "== resolving current Node.js $LINE tarball (linux-$NODE_ARCH) =="
SHASUMS="$(curl -fsSL "https://nodejs.org/dist/${LINE}/SHASUMS256.txt")"
FILENAME="$(echo "$SHASUMS" | grep -o "node-v[0-9.]*-linux-${NODE_ARCH}\.tar\.gz" | head -1)"
[ -n "$FILENAME" ] || { echo "error: could not find a linux-$NODE_ARCH tarball in $LINE" >&2; exit 1; }
URL="https://nodejs.org/dist/${LINE}/${FILENAME}"
echo "  .. $URL"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
curl -fsSL -o "$TMP/$FILENAME" "$URL"
echo "$SHASUMS" | grep "$FILENAME" | (cd "$TMP" && sha256sum -c -)

rm -rf "$NODE_DIR"
mkdir -p "$NODE_DIR"
tar -xzf "$TMP/$FILENAME" -C "$NODE_DIR" --strip-components=1

echo "  ok   $NODE_DIR ($("$NODE_DIR/bin/node" -v), npm $("$NODE_DIR/bin/npm" -v))"
echo "== done. Run ./preflight.sh to verify. =="
