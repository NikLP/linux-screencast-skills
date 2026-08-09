#!/usr/bin/env bash
# Sanity-check one scene beyond "the file exists". Run with TUT_SLUG set.
#   ./check-scene.sh 030
# A valid-length .mp4 of the wrong screen is the failure a size/existence check
# cannot catch (a predecessor project hit this five separate times in one run).
# Reports raw and finished durations, extracts a still frame to eyeball, and
# flags the two failure shapes that are easy to produce and easy to miss:
# an unfinalized stub and a scene that ran far longer than expected.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

NN="$(printf '%03d' "$((10#${1:?scene number required}))")"

raw="$HDIR/scenes/${NN}.mp4"
fin="$HDIR/final/scene-${NN}.mp4"
[ -f "$raw" ] || die "scenes/${NN}.mp4 not found (produce the scene first)"

rdur="$(cduration "$raw" 2>/dev/null || echo 0)"
printf 'scene %s raw:      %ss   (%s bytes)\n' "$NN" "$rdur" "$(wc -c < "$raw")"
if [ -f "$fin" ]; then
  fdur="$(cduration "$fin" 2>/dev/null || echo 0)"
  printf 'scene %s finished: %ss   (%s bytes)\n' "$NN" "$fdur" "$(wc -c < "$fin")"
fi
if [ -f "$HDIR/audio/${NN}.mp3" ]; then
  adur="$(cduration "$HDIR/audio/${NN}.mp3" 2>/dev/null || echo 0)"
  printf 'scene %s audio:    %ss\n' "$NN" "$adur"
fi

# Middle-of-clip still: confirms the screen shows what the scene claims, not
# just that ffmpeg produced *a* frame. Open dropdowns, hover states, and
# tooltips are gone by the time you'd think to screenshot after the fact;
# this frame is the actual recorded truth.
mid="$(awk -v d="$rdur" 'BEGIN{ m=d/2; print (m>0? m: 0) }')"
"$FFMPEG" -y -ss "${mid}" -i "$raw" -frames:v 1 "$HDIR/final/${NN}.frame.png" >/dev/null 2>&1 || true
echo "frame -> $HDIR/final/${NN}.frame.png (open it to confirm the screen shows what the scene claims)"

if awk -v d="$rdur" 'BEGIN{exit !(d+0 < 0.4)}'; then
  echo "  WARN raw capture <0.4s: the capture may not have finalized."
fi
if awk -v d="$rdur" 'BEGIN{exit !(d+0 > 90)}'; then
  echo "  WARN raw capture >90s: check the tape's Sleep / spec's waitMs, this is usually a pacing mistake, not the intended scene."
fi

echo "Two checks this cannot do for you: identical file size to the previous scene usually means nothing changed on screen, and for any scene that submits a form or changes state, read the actual result back (reload the page, query the API, whatever the tool exposes) rather than trusting the clip."
