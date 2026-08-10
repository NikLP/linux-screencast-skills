#!/usr/bin/env bash
# Method B browser engine (opt-in, extra host deps): drives a REAL, on-screen
# kiosk Chromium on a virtual Xvfb display with xdotool for actual cursor
# movement/clicks/typing, captured live with ffmpeg x11grab, for scenes that
# specifically need a visibly-moving cursor rather than Method A's in-page
# highlight box. Same spec.json format as browser-scene.sh (Method A); swap
# the script name to switch engines, nothing else changes. Run with TUT_SLUG
# set, same as every other script here.
#   ./browser-scene-cursor.sh <NN> <spec.json>
#   ./browser-scene-cursor.sh stop   # tear down the Xvfb/Chromium session once you're fully done
# Needs xdotool + Xvfb (system packages; preflight.sh's Method B section
# reports these but never installs them) - Method A needs neither. See
# CLAUDE.md's "Cursor capture" section and references/browser-playwright.md
# for the full design and trade-offs (a bit less crisp text than Method A: no
# 2x supersampling, since exact 1:1 pixel mapping is what makes the
# xdotool coordinate math work).
#
# Don't set WIN_X/WIN_Y/WIN_W/WIN_H away from the TUT_RES default (0,0,
# matching TUT_RES exactly) for this engine: kiosk mode fullscreens to the
# Xvfb screen's own size, which only lines up with the coordinate math
# (screen = WIN_X/Y + Playwright viewport offset) when the window already
# covers the whole virtual screen. Method A's WIN_* geometry has no such
# constraint, it's just a developer-inspection window size.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

if [ "${1:-}" = "stop" ]; then
  DISPLAY="$XVFB_DISPLAY" "$HERE/browser.sh" stop 2>/dev/null || true
  # Belt and suspenders alongside browser.sh's CDP-close attempt above: a
  # user-data-dir match is unique to this session (unlike matching on the
  # bare process name), so it can't catch an unrelated Chromium on the host.
  pkill -f -- "--user-data-dir=${HDIR}/chrome-profile" 2>/dev/null || true
  # An x11grab capture has no -t duration, so a run that dies before reaching
  # its own `kill -INT $CAP_PID` (killed mid-scene, or a hang like the CDP
  # socket leak this engine used to have) leaves it recording indefinitely;
  # stop is the designated recovery path, so it must reap this too. Matched
  # on this session's raw output path, so it can't catch an unrelated ffmpeg.
  pkill -f -- "x11grab.*${HDIR}/scenes/.raw-" 2>/dev/null || true
  "$HERE/xvfb.sh" stop
  exit 0
fi

NN="$(printf '%03d' "$((10#${1:?usage: browser-scene-cursor.sh <NN> <spec.json> | stop}))")"
SPEC="${2:?usage: browser-scene-cursor.sh <NN> <spec.json>}"
[ -f "$SPEC" ] || die "spec not found: $SPEC"

command -v xdotool >/dev/null || die "xdotool not installed: $(pkg_install_hint xdotool)"
command -v Xvfb >/dev/null || die "Xvfb not installed: $(pkg_install_hint xvfb)"
command -v curl >/dev/null || die "curl not installed: $(pkg_install_hint curl)"
"$FFMPEG" -hide_banner -devices 2>/dev/null | grep -w x11grab >/dev/null 2>&1 \
  || die "this ffmpeg build has no x11grab device (needed for Method B capture): $(pkg_install_hint ffmpeg)"
command -v node >/dev/null || die "node not installed. Run preflight.sh."
export NODE_PATH="${NODE_PATH:+$NODE_PATH:}$(npm root -g 2>/dev/null || true)"

"$HERE/xvfb.sh" start

# Reuse an already-running kiosk session (persists login state in
# $HDIR/chrome-profile across scenes, see references/browser-playwright.md);
# start one only if none is up yet. browser-scene-cursor.mjs navigates to
# spec.url itself, so which URL this starts on doesn't matter.
if ! curl -sf "http://127.0.0.1:${CDP_PORT}/json/version" >/dev/null 2>&1; then
  DISPLAY="$XVFB_DISPLAY" TUT_KIOSK=1 "$HERE/browser.sh" start about:blank
fi

mkdir -p "$HDIR/scenes"
RAW="$HDIR/scenes/.raw-${NN}.mp4"
rm -f "$RAW"

# -draw_mouse 1 is x11grab's default, but it's the one flag this whole engine
# exists for, so make it explicit rather than trust an implicit default.
DISPLAY="$XVFB_DISPLAY" nohup "$FFMPEG" -y -f x11grab -draw_mouse 1 -video_size "${WIN_W}x${WIN_H}" \
  -framerate "$FPS" -i "${XVFB_DISPLAY}+${WIN_X},${WIN_Y}" \
  -codec:v libx264 -preset ultrafast -pix_fmt yuv420p "$RAW" \
  >"$HDIR/scenes/${NN}.capture.log" 2>&1 &
CAP_PID=$!
sleep 0.5
kill -0 "$CAP_PID" 2>/dev/null || die "x11grab capture failed to start (see $HDIR/scenes/${NN}.capture.log)"

set +e
DISPLAY="$XVFB_DISPLAY" HANDS="$HERE/hands.sh" \
  node "$HERE/browser-scene-cursor.mjs" "$SPEC"
STATUS=$?
set -e

# SIGINT lets ffmpeg finalize the moov atom cleanly (a bare kill/SIGTERM can
# leave a stub file; ported from drupal-tutorial-video's record-beat.sh).
kill -INT "$CAP_PID" 2>/dev/null || true
for _ in $(seq 1 40); do
  kill -0 "$CAP_PID" 2>/dev/null || break
  sleep 0.25
done

[ "$STATUS" -eq 0 ] || die "step driver failed (see above); capture in $RAW may be incomplete"
[ -s "$RAW" ] || die "x11grab produced no output (see $HDIR/scenes/${NN}.capture.log)"

# Normalize to the exact format every engine produces (RES/FPS, yuv420p), same
# final pass as Method A (browser-scene.mjs), so finish-scene.sh/concat.sh see
# a consistent scenes/NN.mp4 regardless of which engine made it.
"$FFMPEG" -y -i "$RAW" \
  -vf "scale=${RES/x/:}:force_original_aspect_ratio=decrease,pad=${RES/x/:}:(ow-iw)/2:(oh-ih)/2,fps=${FPS}" \
  -c:v libx264 -preset medium -pix_fmt yuv420p "$HDIR/scenes/${NN}.mp4" \
  >"$HDIR/scenes/${NN}.normalize.log" 2>&1
[ -s "$HDIR/scenes/${NN}.mp4" ] || die "normalize pass produced no output (see $HDIR/scenes/${NN}.normalize.log)"
rm -f "$RAW"

echo "browser scene $NN (cursor) -> $HDIR/scenes/${NN}.mp4"
