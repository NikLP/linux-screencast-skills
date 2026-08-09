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

# Package-manager-specific install command for a system dependency, so a MISS
# line always tells you exactly what to run instead of a generic name.
pkg_install_hint() {  # pkg_install_hint <pkg>
  local pkg="$1"
  if command -v apt-get >/dev/null; then echo "sudo apt-get install -y $pkg"
  elif command -v dnf >/dev/null; then echo "sudo dnf install -y $pkg"
  elif command -v pacman >/dev/null; then echo "sudo pacman -S $pkg"
  elif command -v apk >/dev/null; then echo "sudo apk add $pkg"
  else echo "install '$pkg' with your distro's package manager"
  fi
}

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
else
  warn "Piper not installed (free, offline, no API key): ./scripts/install-piper.sh"
fi
[ "$TTS_OK" = 1 ] || warn "No TTS engine ready yet (OpenAI or Piper). Narration (narrate.sh) will fail until one is; every other scene type still works."

echo "== preflight complete =="
if [ "$MISSING" = 1 ]; then
  die "one or more required dependencies are missing (see MISS lines above). Do not proceed until they are installed."
fi
