#!/usr/bin/env bash
# Opt-in installer for Piper (local, offline, free neural TTS - no API key, no
# account, no per-character cost) as a third narrate.sh engine alongside
# OpenAI. Installs into <repo>/.piper/: piper-tts (pip --target, not a venv -
# Debian/Ubuntu's python3-venv needs a separate sudo apt install and system
# `pip install` is blocked outright (PEP 668); --target sidesteps both, no
# sudo, nothing outside this repo) plus one default voice model from Hugging
# Face. Run manually:
#   ./scripts/install-piper.sh [voice]
# voice defaults to en_US-lessac-medium. Browse others:
#   https://huggingface.co/rhasspy/piper-voices/tree/v1.0.0
# Re-run with a different voice name to add it (existing voices are kept).
# Deleting this repo removes everything (.piper/ is gitignored).
#
# Quality trade-off: clearly intelligible but noticeably less natural than
# OpenAI's gpt-4o-mini-tts or ElevenLabs. Check the voice's MODEL_CARD (same
# URL, filename MODEL_CARD) for its dataset license before commercial use.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PIPER_DIR="$HERE/.piper"
SITE_DIR="$PIPER_DIR/site-packages"
VOICE="${1:-en_US-lessac-medium}"

command -v python3 >/dev/null || { echo "error: python3 not found" >&2; exit 1; }

echo "== installing piper-tts into $SITE_DIR (pip --target, no venv, no sudo) =="
python3 -m pip install --target "$SITE_DIR" piper-tts
PYTHONPATH="$SITE_DIR" python3 -m piper --help >/dev/null 2>&1 \
  && echo "  ok   piper-tts installed" \
  || { echo "error: piper-tts installed but 'python3 -m piper --help' failed" >&2; exit 1; }

# Voice model: two files (.onnx + .onnx.json) from the rhasspy/piper-voices
# Hugging Face dataset. voice name = <lang>_<REGION>-<speaker>-<quality>,
# e.g. en_US-lessac-medium -> lang=en region=en_US speaker=lessac quality=medium.
IFS='-' read -r locale speaker quality <<< "$VOICE"
lang="${locale%%_*}"
BASE_URL="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/${lang}/${locale}/${speaker}/${quality}"

mkdir -p "$PIPER_DIR/voices"
echo "== downloading voice: $VOICE =="
for ext in onnx onnx.json; do
  f="${VOICE}.${ext}"
  echo "  .. $BASE_URL/$f"
  curl -fsSL -o "$PIPER_DIR/voices/$f" "$BASE_URL/$f"
done
echo "  ok   $PIPER_DIR/voices/${VOICE}.onnx"

echo "== done. Run ./preflight.sh to verify, or ./narrate.sh voices to see it listed. =="
echo "Use it with: export TUT_TTS=piper (and TUT_VOICE=$VOICE if not the default)"
