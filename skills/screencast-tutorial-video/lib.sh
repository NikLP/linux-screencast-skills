#!/usr/bin/env bash
# Shared config for the screencast-tutorial-video helper scripts (Linux host).
# Source this from every script. Run scripts from the directory where you want
# the .tutorial-build/ tree to live (usually your project root), with TUT_SLUG set.
# To run from anywhere, export an absolute HDIR (or TUT_BUILD_DIR) so the .sh
# scripts and browser-scene.mjs agree on the build dir regardless of cwd.
#
# Linux fork of kanopi/screencast-skills (macOS). WIN_* below is consumed by
# browser.sh/browser.mjs, the OS-agnostic Playwright "brain" kept as a head
# start for a future real-cursor Method B port (the macOS-only hands.sh /
# record-browser.sh / AVF_SCREEN / OFF_* have been removed as dead weight).
# See the repo root CLAUDE.md's "Cursor capture" section.
set -euo pipefail

# A comma-decimal locale (e.g. LC_NUMERIC=de_DE) makes awk print durations
# like "6,5" instead of "6.5"; still-scene.sh and finish-scene.sh both feed
# awk output straight into an ffmpeg filtergraph (stop_duration=, -t), where
# the comma is a filter separator, not a decimal point, and the failure is a
# cryptic ffmpeg parse error, not an obvious one. One export here covers every
# script that sources lib.sh instead of repeating it per script.
export LC_ALL=C LC_NUMERIC=C

# Brand/project preset. Defaults to `default` (this fork's baseline settings);
# switch with `export TUT_PRESET=<name>` (see presets/README.md to add your
# own), or skip presets entirely with `export TUT_PRESET=none`. Presets use
# ${VAR:-default}, so an explicit env var still wins. See presets/README.md.
TUT_PRESET="${TUT_PRESET:-default}"
if [ "$TUT_PRESET" != "none" ]; then
  _LIBDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [ -f "$_LIBDIR/presets/${TUT_PRESET}.env" ]; then
    # shellcheck disable=SC1090
    source "$_LIBDIR/presets/${TUT_PRESET}.env"
  else
    echo "warn: preset not found: $_LIBDIR/presets/${TUT_PRESET}.env" >&2
  fi
fi

: "${TUT_SLUG:?set TUT_SLUG to the tutorial slug, e.g. export TUT_SLUG=mcp-github-claude-code}"

# Capture settings (override with TUT_* env vars if needed).
RES="${TUT_RES:-1920x1080}"
FPS="${TUT_FPS:-25}"

# Browser window geometry for the browser-action scenes. The window is
# launched at this origin and size (see browser.sh/browser.mjs).
WIN_X="${TUT_WIN_X:-0}"
WIN_Y="${TUT_WIN_Y:-0}"
WIN_W="${TUT_WIN_W:-1920}"
WIN_H="${TUT_WIN_H:-1080}"

# Method B (real-cursor browser scenes: xvfb.sh/hands.sh/browser-scene-cursor.sh)
# only. A virtual X11 display, so xdotool (input) and ffmpeg x11grab (capture)
# have an X server to talk to regardless of whether the real desktop is X11,
# Wayland, or headless/CI - see CLAUDE.md's "Cursor capture" section for why.
# CDP_PORT is the debugging port the persistent kiosk Chromium listens on.
# Method A (browser-scene.sh) is fully headless/off-screen and uses neither.
XVFB_DISPLAY="${TUT_XVFB_DISPLAY:-:99}"
CDP_PORT="${TUT_CDP_PORT:-9222}"

# Build directory: single host path (no container mount anymore). An exported
# HDIR wins, so wrappers can pass an absolute path to both the .sh scripts and
# browser-scene.mjs (they must agree, or scenes land in the wrong dir).
HDIR="${HDIR:-${TUT_BUILD_DIR:-.tutorial-build}/${TUT_SLUG}}"
# Resolve to an absolute path: several scripts cd into $HDIR, which would break
# relative font/asset paths (ffmpeg falls back to a default font silently).
case "$HDIR" in /*) ;; *) HDIR="$(pwd)/${HDIR}" ;; esac

# Caption bars and command cards draw text via ffmpeg's fontconfig-backed
# `drawtext=font=...` (generic family name, e.g. Sans/Monospace), not a
# bundled font file, so whatever's already installed on the host is used, see
# finish-scene.sh and make-card.sh. No font download, nothing to configure here.

# Repo-local tool dirs, so this repo never depends on system-installed vhs,
# ttyd, node, or npm. `scripts/install-vhs.sh` downloads vhs + its own ttyd
# dependency into .bin/; `scripts/install-node.sh` downloads a self-contained
# Node.js + npm into .node/ (Debian/Ubuntu's `npm` package pulls in ~300
# transitive packages this repo doesn't need). Prepending both to PATH means
# every script that sources lib.sh finds them, with no per-script changes,
# and vhs itself (which shells out to `ttyd` by bare name) finds ttyd too.
# readlink -f resolves BASH_SOURCE to its real, physical path first: plain
# `dirname`+`cd ../..` walks up the LOGICAL path, which is wrong when this
# file is reached through a symlink (e.g. a project's .claude/skills/<name>
# symlinked or submoduled in) - the ../.. would walk up the symlink's parent
# directories instead of the real repo's.
REPO_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"
BIN_DIR="${TUT_BIN_DIR:-${REPO_ROOT}/.bin}"
NODE_DIR="${TUT_NODE_DIR:-${REPO_ROOT}/.node}"
[ -d "$BIN_DIR" ] && export PATH="$BIN_DIR:$PATH"
[ -d "$NODE_DIR/bin" ] && export PATH="$NODE_DIR/bin:$PATH"

# Piper (free, offline, local TTS - narrate.sh's third engine alongside
# OpenAI). `scripts/install-piper.sh` installs piper-tts via `pip --target`
# (not a venv: Debian/Ubuntu's python3-venv needs its own sudo apt install,
# and a plain system `pip install` is blocked by PEP 668; --target avoids
# both) into .piper/site-packages, and downloads voice models into
# .piper/voices/. Invoked as system `python3 -m piper`, PYTHONPATH pointed at
# site-packages (narrate.sh does this), not a bare binary on PATH.
PIPER_DIR="${TUT_PIPER_DIR:-${REPO_ROOT}/.piper}"
PIPER_SITE_DIR="${TUT_PIPER_SITE_DIR:-${PIPER_DIR}/site-packages}"
PIPER_VOICES_DIR="${TUT_PIPER_VOICES_DIR:-${PIPER_DIR}/voices}"

# Pick a drawtext-capable ffmpeg. Most distro ffmpeg packages already have it
# (libfreetype/libfontconfig); this just verifies and lets $TUT_FFMPEG override.
# preflight.sh reports the fix if none qualifies.
_pick_ffmpeg() {
  local c
  for c in "${TUT_FFMPEG:-}" "$(command -v ffmpeg 2>/dev/null || true)"; do
    [ -n "$c" ] || continue
    command -v "$c" >/dev/null 2>&1 || [ -x "$c" ] || continue
    # No `grep -q`: it exits early, SIGPIPEs ffmpeg, and under `set -o pipefail`
    # that marks the pipeline failed, wrongly rejecting a good binary. Plain
    # grep reads all input, so the pipeline status is grep's alone.
    if "$c" -hide_banner -filters 2>/dev/null | grep -w drawtext >/dev/null 2>&1; then
      echo "$c"; return 0
    fi
  done
  # Fall back to plain ffmpeg (no drawtext) so scenes without text still render;
  # preflight flags the missing filter.
  command -v ffmpeg >/dev/null 2>&1 && { command -v ffmpeg; return 0; }
  echo ffmpeg
}
FFMPEG="$(_pick_ffmpeg)"
# ffprobe next to the chosen ffmpeg if present, else PATH ffprobe.
_FFDIR="$(dirname "$FFMPEG")"
if [ -x "$_FFDIR/ffprobe" ]; then
  FFPROBE="${TUT_FFPROBE:-$_FFDIR/ffprobe}"
else
  FFPROBE="${TUT_FFPROBE:-$(command -v ffprobe 2>/dev/null || echo ffprobe)}"
fi

# ffprobe a media file (host path) for its duration in seconds.
cduration() {
  "$FFPROBE" -v error -show_entries format=duration -of csv=p=0 "$1"
}

die() { echo "error: $*" >&2; exit 1; }

# Package-manager-specific install command for a system dependency (ffmpeg,
# and Method B's xdotool/xvfb), so a MISS/die line always tells you exactly
# what to run instead of a generic name. Shared by preflight.sh, xvfb.sh, and
# browser-scene-cursor.sh.
pkg_install_hint() {  # pkg_install_hint <pkg>
  local pkg="$1"
  if command -v apt-get >/dev/null; then echo "sudo apt-get install -y $pkg"
  elif command -v dnf >/dev/null; then echo "sudo dnf install -y $pkg"
  elif command -v pacman >/dev/null; then echo "sudo pacman -S $pkg"
  elif command -v apk >/dev/null; then echo "sudo apk add $pkg"
  else echo "install '$pkg' with your distro's package manager"
  fi
}
