#!/usr/bin/env bash
# Virtual X11 display for Method B (real-cursor browser scenes,
# browser-scene-cursor.sh): gives xdotool (real cursor input) and ffmpeg
# x11grab (real screen capture) an X server to talk to, regardless of whether
# the real desktop is X11, Wayland, or headless/CI. See the repo root
# CLAUDE.md's "Cursor capture" section for why X11-via-Xvfb, not native
# Wayland. Method A (browser-scene.sh) is headless/off-screen and never
# touches this.
#   ./xvfb.sh start   # idempotent: no-op if already up on $XVFB_DISPLAY
#   ./xvfb.sh stop
#   ./xvfb.sh status
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

# Matches on the literal display arg so this only ever touches the Xvfb
# instance this repo started, never an unrelated one on the host (e.g. a
# desktop-manager-owned :0, or another tool's :99 collision would just fail
# to bind and get caught by the "did not come up" check below).
running() { pgrep -f "Xvfb ${XVFB_DISPLAY} " >/dev/null 2>&1; }

case "${1:-}" in
  start)
    if running; then
      echo "Xvfb already up on $XVFB_DISPLAY"
    else
      command -v Xvfb >/dev/null || die "Xvfb not installed: $(pkg_install_hint xvfb)"
      mkdir -p "$HDIR"
      # -ac disables X11 access control (fine, nothing but our own tools ever
      # points at this display); -nolisten tcp keeps it off the network.
      nohup Xvfb "$XVFB_DISPLAY" -screen 0 "${RES}x24" -ac -nolisten tcp \
        >"$HDIR/xvfb.log" 2>&1 &
      disown
      for _ in $(seq 1 20); do
        running && break
        sleep 0.25
      done
      running || die "Xvfb did not come up on $XVFB_DISPLAY (see $HDIR/xvfb.log)"
      echo "Xvfb up on $XVFB_DISPLAY (${RES})"
    fi
    ;;
  stop)
    if running; then
      pkill -f "Xvfb ${XVFB_DISPLAY} " || true
      echo "Xvfb stopped ($XVFB_DISPLAY)"
    else
      echo "Xvfb not running on $XVFB_DISPLAY"
    fi
    ;;
  status)
    running && echo "up ($XVFB_DISPLAY)" || { echo "down ($XVFB_DISPLAY)"; exit 1; }
    ;;
  *) die "usage: xvfb.sh start|stop|status" ;;
esac
