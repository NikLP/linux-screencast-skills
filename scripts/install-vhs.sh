#!/usr/bin/env bash
# Opt-in installer for `vhs` and its own runtime dependency `ttyd`, as static
# Linux binaries downloaded straight into <repo>/.bin/. No sudo, no system
# package manager, nothing installed outside this repo, nothing runs
# automatically, run this yourself when you're ready:
#   ./scripts/install-vhs.sh
# Re-run any time to update to whatever is currently latest. Deleting this
# repo removes everything it downloaded (.bin/ is gitignored).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$HERE/.bin"
mkdir -p "$BIN_DIR"

arch="$(uname -m)"
case "$arch" in
  x86_64|amd64)  VHS_ARCH=x86_64 TTYD_ARCH=x86_64 ;;
  aarch64|arm64) VHS_ARCH=arm64  TTYD_ARCH=aarch64 ;;
  *)
    echo "error: no static binary mapping here for arch '$arch'." >&2
    echo "Install vhs manually: https://github.com/charmbracelet/vhs#installation" >&2
    echo "and ttyd manually: https://github.com/tsl0922/ttyd#installation" >&2
    exit 1
    ;;
esac

# Latest-release asset URL matching a filename regex, via the GitHub API.
# Plain curl+grep, not jq, so this script has no prerequisite of its own.
latest_asset_url() {  # latest_asset_url <owner/repo> <filename-regex>
  local repo="$1" pattern="$2"
  curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" \
    | grep -o '"browser_download_url": *"[^"]*"' \
    | sed -E 's/.*"(https:[^"]+)"/\1/' \
    | grep -E "$pattern" | head -1
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "== installing vhs (Linux/$VHS_ARCH) =="
VHS_URL="$(latest_asset_url charmbracelet/vhs "vhs_[0-9.]+_Linux_${VHS_ARCH}\.tar\.gz$")"
[ -n "$VHS_URL" ] || { echo "error: no vhs Linux/$VHS_ARCH release asset found" >&2; exit 1; }
echo "  .. $VHS_URL"
curl -fsSL -o "$TMP/vhs.tar.gz" "$VHS_URL"
tar -xzf "$TMP/vhs.tar.gz" -C "$TMP"
VHS_BIN="$(find "$TMP" -type f -name vhs | head -1)"
[ -n "$VHS_BIN" ] || { echo "error: no 'vhs' binary found inside the downloaded archive" >&2; exit 1; }
install -m 0755 "$VHS_BIN" "$BIN_DIR/vhs"
echo "  ok   $BIN_DIR/vhs"

echo "== installing ttyd (Linux/$TTYD_ARCH, vhs's own dependency) =="
TTYD_URL="$(latest_asset_url tsl0922/ttyd "ttyd\.${TTYD_ARCH}$")"
[ -n "$TTYD_URL" ] || { echo "error: no ttyd Linux/$TTYD_ARCH release asset found" >&2; exit 1; }
echo "  .. $TTYD_URL"
curl -fsSL -o "$BIN_DIR/ttyd" "$TTYD_URL"
chmod +x "$BIN_DIR/ttyd"
echo "  ok   $BIN_DIR/ttyd"

echo "== done. Run ./preflight.sh to verify. =="
