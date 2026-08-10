#!/usr/bin/env bash
# Preflight: check (never install) everything screencast-tutorial-video needs
# on the Linux host. Run with TUT_SLUG set. Reports every dependency's real
# state and exits non-zero if a required one is missing, never proceed on a
# false green. This never runs a package manager, npm -g, curl, or sudo, it
# only reports the exact fix command; you run it.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

ok()   { echo "  ok   $*"; }
info() { echo "  ..   $*"; }
warn() { echo "  WARN $*"; }
MISSING=0
need() { echo "  MISS $*"; MISSING=1; }
# pkg_install_hint() comes from lib.sh, shared with xvfb.sh/browser-scene-cursor.sh.

echo "== screencast-tutorial-video preflight (slug: $TUT_SLUG) =="

# 1. Build directory (local output tree, not a system install).
mkdir -p "$HDIR"/{tapes,stills,scenes,audio,cards,final}
ok "build dir $HDIR ready"

# 2. ffmpeg / ffprobe, with the drawtext filter (every caption bar and command
#    card depends on it).
if command -v "$FFMPEG" >/dev/null 2>&1 || [ -x "$FFMPEG" ]; then
  ok "ffmpeg present ($FFMPEG)"
  if "$FFMPEG" -hide_banner -filters 2>/dev/null | grep -w drawtext >/dev/null 2>&1; then
    ok "ffmpeg has the drawtext filter"
  else
    need "ffmpeg has no drawtext filter (needs libfreetype+libfontconfig): $(pkg_install_hint ffmpeg)"
  fi
else
  need "ffmpeg missing: $(pkg_install_hint ffmpeg)"
fi
if command -v "$FFPROBE" >/dev/null 2>&1 || [ -x "$FFPROBE" ]; then
  ok "ffprobe present ($FFPROBE)"
else
  need "ffprobe missing: $(pkg_install_hint ffmpeg)"
fi

# 3. vhs + its own ttyd dependency. Both are opt-in installed, repo-local, via
#    scripts/install-vhs.sh (BIN_DIR is already on PATH, see lib.sh).
if command -v vhs >/dev/null; then
  ok "vhs present ($(command -v vhs))"
else
  need "vhs missing: ./scripts/install-vhs.sh (downloads a static binary into $BIN_DIR, no sudo)"
fi
if command -v ttyd >/dev/null; then
  ok "ttyd present ($(command -v ttyd))"
else
  need "ttyd missing (vhs's own runtime dependency): ./scripts/install-vhs.sh (downloads a static binary into $BIN_DIR, no sudo)"
fi

# 4. Node + npm + local Playwright (browser scenes). Playwright installs
#    locally (npm install, node_modules/ in the repo root), not globally.
# Node/npm are checked independently: Debian/Ubuntu's `nodejs` package ships
# without `npm` (separate package), and that `npm` package drags in ~300
# transitive node-* packages plus a native build toolchain. ./scripts/install-node.sh
# sidesteps both by vendoring the official nodejs.org tarball into .node/
# (already on PATH via lib.sh if present) - the recommended fix either way.
if command -v node >/dev/null; then
  ok "node present ($(node -v))"
else
  need "node missing: ./scripts/install-node.sh (downloads a self-contained Node.js into $NODE_DIR, no sudo)"
fi
if command -v npm >/dev/null; then
  ok "npm present ($(npm -v))"
else
  need "npm missing: ./scripts/install-node.sh (downloads a self-contained Node.js+npm into $NODE_DIR, no sudo; avoids Debian's ~300-package npm split)"
fi
if command -v node >/dev/null && command -v npm >/dev/null; then
  if ( cd "$REPO_ROOT" && node -e "require.resolve('playwright')" ) >/dev/null 2>&1; then
    ok "playwright present"
    if ( cd "$REPO_ROOT" && node -e "
      const { chromium } = require('playwright');
      process.exit(require('fs').existsSync(chromium.executablePath()) ? 0 : 1);
    " ) >/dev/null 2>&1; then
      ok "chromium present"
    else
      need "chromium missing: npx playwright install chromium (from $REPO_ROOT)"
    fi
  else
    need "playwright missing: npm install (from $REPO_ROOT; installs locally into node_modules/, not global)"
  fi
fi

# 5. TTS engine: OpenAI or Piper (free/offline) in this fork (narrate.sh's
#    ElevenLabs branch is unused without a key; leaving it doesn't cost
#    anything but this fork doesn't expect it). Neither is a hard requirement:
#    narration is the only thing that needs one, every other scene type works
#    regardless.
TTS_OK=0
if [ -n "${OPENAI_API_KEY:-}" ]; then
  if command -v jq >/dev/null; then
    ok "TTS: OpenAI ready (model ${TUT_OPENAI_TTS_MODEL:-gpt-4o-mini-tts})"
    TTS_OK=1
  else
    need "jq missing (required to build the OpenAI TTS request): $(pkg_install_hint jq)"
  fi
else
  warn "OPENAI_API_KEY is not set. OpenAI narration unavailable until it is."
fi
if [ -d "$PIPER_SITE_DIR" ]; then
  if compgen -G "$PIPER_VOICES_DIR/*.onnx" >/dev/null 2>&1; then
    ok "TTS: Piper ready (free, offline; $(compgen -G "$PIPER_VOICES_DIR/*.onnx" | wc -l) voice(s) downloaded)"
    TTS_OK=1
  else
    warn "Piper installed but no voice model downloaded: ./scripts/install-piper.sh"
  fi
elif command -v python3 >/dev/null && python3 -m pip --version >/dev/null 2>&1; then
  warn "Piper not installed (free, offline, no API key): ./scripts/install-piper.sh"
else
  # install-piper.sh itself needs python3's pip module (Debian/Ubuntu splits
  # this into a separate package, not guaranteed present on a minimal
  # install); check it here so the fix command is the real blocker, not a
  # script that will fail partway through with a confusing pip error.
  warn "Piper not installed, and its own prerequisite is missing too: python3's pip module. $(pkg_install_hint python3-pip), then: ./scripts/install-piper.sh"
fi
[ "$TTS_OK" = 1 ] || warn "No TTS engine ready yet (OpenAI or Piper). Narration (narrate.sh) will fail until one is; every other scene type still works."

# 6. Method B (real-cursor browser-action scenes: browser-scene-cursor.sh),
#    entirely optional. Method A (browser-scene.sh) is the default and needs
#    none of this, so a missing dependency here is a WARN, never a MISS - it
#    must not block the main pipeline. browser-scene-cursor.sh re-checks these
#    itself and dies with the same hint if you actually run it without them.
if command -v xdotool >/dev/null; then
  ok "Method B: xdotool present ($(command -v xdotool))"
else
  warn "Method B (real-cursor browser scenes): xdotool missing, optional: $(pkg_install_hint xdotool)"
fi
if command -v Xvfb >/dev/null; then
  ok "Method B: Xvfb present ($(command -v Xvfb))"
else
  warn "Method B (real-cursor browser scenes): Xvfb missing, optional: $(pkg_install_hint xvfb)"
fi
if (command -v "$FFMPEG" >/dev/null 2>&1 || [ -x "$FFMPEG" ]) && "$FFMPEG" -hide_banner -devices 2>/dev/null | grep -w x11grab >/dev/null 2>&1; then
  ok "Method B: ffmpeg has the x11grab device"
else
  warn "Method B (real-cursor browser scenes): this ffmpeg build has no x11grab device, optional: $(pkg_install_hint ffmpeg)"
fi

echo "== preflight complete =="
if [ "$MISSING" = 1 ]; then
  die "one or more required dependencies are missing (see MISS lines above). Do not proceed until they are installed."
fi
