#!/usr/bin/env bash
# The "hands" for Method B (real-cursor browser scenes): visible cursor
# movement, clicks, and typing on the virtual Xvfb display (xvfb.sh), driven
# by browser-scene-cursor.mjs. Ported from drupal-tutorial-video's hands.sh,
# made host-native (that version ran inside a ddev container over `ddev exec`;
# this repo has no container, so DISPLAY is just an env var, no exec boundary
# to cross). Its base64 `type64` workaround for shell-metacharacter mangling
# across that `ddev exec` hop is dropped for the same reason: callers here
# invoke this script directly (execFileSync, no shell), so there's nothing to
# mangle a plain `type` argument.
#   ./hands.sh move CX CY
#   ./hands.sh hover CX CY
#   ./hands.sh click [CX CY]
#   ./hands.sh type "text to type"
#   ./hands.sh key ctrl+a          # xdotool/X keysym names, e.g. Return, BackSpace
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"
export DISPLAY="${DISPLAY:-$XVFB_DISPLAY}"

command -v xdotool >/dev/null || die "xdotool not installed: $(pkg_install_hint xdotool)"

STEPS="${TUT_HAND_STEPS:-25}"            # cursor interpolation steps (higher = smoother/slower)
STEP_SLEEP="${TUT_HAND_STEP_SLEEP:-0.012}"
TYPE_DELAY="${TUT_HAND_TYPE_DELAY:-60}"  # ms between keystrokes

move() {
  local tx="$1" ty="$2" cx cy i nx ny
  eval "$(xdotool getmouselocation --shell)"   # sets X, Y
  cx="$X"; cy="$Y"
  for i in $(seq 1 "$STEPS"); do
    nx=$(( cx + (tx - cx) * i / STEPS ))
    ny=$(( cy + (ty - cy) * i / STEPS ))
    xdotool mousemove "$nx" "$ny"
    sleep "$STEP_SLEEP"
  done
}

cmd="${1:?usage: hands.sh move|hover|click|type|key ...}"; shift
case "$cmd" in
  move)  move "$1" "$2" ;;
  hover) move "$1" "$2" ;;
  click)
    if [ "$#" -ge 2 ]; then move "$1" "$2"; fi
    sleep 0.15
    xdotool click 1
    ;;
  type)  xdotool type --clearmodifiers --delay "$TYPE_DELAY" -- "$1" ;;
  key)   xdotool key --clearmodifiers -- "$1" ;;
  *) die "unknown command: $cmd (move|hover|click|type|key)" ;;
esac
