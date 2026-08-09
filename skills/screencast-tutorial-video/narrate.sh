#!/usr/bin/env bash
# Generate scene narration to audio/NN.mp3, from any of three TTS engines. Run
# with TUT_SLUG set.
#   ./narrate.sh voices              # list voices for the active engine
#   ./narrate.sh 030 "the narration text for scene 030"
#
# Engine selection (TUT_TTS): "elevenlabs", "openai", or "piper". Default:
# elevenlabs if ELEVENLABS_API_KEY is set, else openai if OPENAI_API_KEY is
# set, else piper if installed (./scripts/install-piper.sh).
#   ElevenLabs: awaz + ELEVENLABS_API_KEY (Text-to-Speech + Voices-read perms).
#               Opt-in only, e.g. for a cloned/premium voice; the default
#               preset is OpenAI/Piper. awaz's CLI has changed
#               shape since this was last verified against a real key/run:
#               current usage is `awaz "text" -v <voice> -o <file>` (no
#               `speak` subcommand, no --no-play/--no-stream/--voice-id, per
#               https://github.com/ahmadawais/awaz). Re-check against
#               `awaz --help` before trusting this path on a fresh install.
#   OpenAI:     OPENAI_API_KEY, POST /v1/audio/speech (model gpt-4o-mini-tts).
#   Piper:      free, offline, no account/key. Noticeably less natural than the
#               other two, but zero cost and no credits needed. See
#               ./scripts/install-piper.sh and README.md's Prerequisites table.
# Voice: TUT_VOICE (engine-specific id/name/model). OpenAI model:
# TUT_OPENAI_TTS_MODEL.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

# Resolve the engine.
TTS="${TUT_TTS:-}"
if [ -z "$TTS" ]; then
  if [ -n "${ELEVENLABS_API_KEY:-}" ]; then TTS=elevenlabs
  elif [ -n "${OPENAI_API_KEY:-}" ]; then TTS=openai
  elif [ -d "$PIPER_SITE_DIR" ]; then TTS=piper
  else die "no TTS engine available: set OPENAI_API_KEY (OpenAI), install Piper for free (./scripts/install-piper.sh), or set TUT_TTS explicitly"
  fi
fi

OPENAI_VOICES="alloy ash ballad cedar coral echo fable marin nova onyx sage shimmer verse"
OPENAI_MODEL="${TUT_OPENAI_TTS_MODEL:-gpt-4o-mini-tts}"

list_voices() {
  case "$TTS" in
    elevenlabs)
      command -v awaz >/dev/null || die "awaz not installed (npm i -g awaz)"
      awaz voices
      ;;
    openai)
      echo "OpenAI TTS voices (model $OPENAI_MODEL):"
      local v
      for v in $OPENAI_VOICES; do echo "  $v"; done
      echo "Set one with: export TUT_VOICE=<voice>"
      ;;
    piper)
      if [ -d "$PIPER_VOICES_DIR" ] && compgen -G "$PIPER_VOICES_DIR/*.onnx" >/dev/null 2>&1; then
        echo "Piper voices downloaded in $PIPER_VOICES_DIR:"
        local f
        for f in "$PIPER_VOICES_DIR"/*.onnx; do echo "  $(basename "${f%.onnx}")"; done
      else
        echo "No Piper voices downloaded yet: ./scripts/install-piper.sh [voice]"
      fi
      echo "Browse the full catalog: https://huggingface.co/rhasspy/piper-voices/tree/v1.0.0"
      echo "Set one with: export TUT_VOICE=<voice> (downloaded model name, no .onnx)"
      ;;
    *) die "unknown TUT_TTS: $TTS (use elevenlabs, openai, or piper)" ;;
  esac
}

synth() {
  local nn text out
  nn="$(printf '%03d' "$((10#${1:?scene number required}))")"
  text="${2:?narration text required}"
  mkdir -p "$HDIR/audio"
  out="$HDIR/audio/${nn}.mp3"
  case "$TTS" in
    elevenlabs)
      command -v awaz >/dev/null || die "awaz not installed (npm i -g awaz)"
      [ -n "${ELEVENLABS_API_KEY:-}" ] || die "ELEVENLABS_API_KEY is not set"
      local voice="${TUT_VOICE:-}"
      # shellcheck disable=SC2086
      if [ -n "$voice" ]; then
        awaz -v "$voice" -o "$out" ${TUT_TTS_FLAGS:-} "$text"
      else
        awaz -o "$out" ${TUT_TTS_FLAGS:-} "$text"
      fi
      [ -s "$out" ] || die "awaz reported success but wrote no audio to $out"
      ;;
    openai)
      [ -n "${OPENAI_API_KEY:-}" ] || die "OPENAI_API_KEY is not set"
      command -v jq >/dev/null || die "jq required to build the OpenAI request (brew install jq)"
      local voice="${TUT_VOICE:-alloy}" payload code
      # Optional TUT_TTS_INSTRUCTIONS steers tone and pronunciation (gpt-4o-mini-tts).
      payload="$(jq -n --arg m "$OPENAI_MODEL" --arg v "$voice" --arg i "$text" \
        --arg ins "${TUT_TTS_INSTRUCTIONS:-}" \
        '{model:$m, voice:$v, input:$i, response_format:"mp3"} + (if $ins=="" then {} else {instructions:$ins} end)')"
      code="$(curl -sS -w '%{http_code}' -o "$out" \
        -X POST https://api.openai.com/v1/audio/speech \
        -H "Authorization: Bearer ${OPENAI_API_KEY}" \
        -H "Content-Type: application/json" \
        -d "$payload")"
      if [ "$code" != "200" ]; then
        local msg="$out"
        # On error the body is JSON, not audio, surface it and remove the stub.
        [ -f "$out" ] && msg="$(cat "$out")"
        rm -f "$out"
        die "OpenAI TTS failed (HTTP $code): $msg"
      fi
      ;;
    piper)
      [ -d "$PIPER_SITE_DIR" ] || die "piper not installed (./scripts/install-piper.sh)"
      local voice="${TUT_VOICE:-en_US-lessac-medium}" model wav
      model="$PIPER_VOICES_DIR/${voice}.onnx"
      [ -f "$model" ] || die "piper voice not downloaded: $model (./scripts/install-piper.sh $voice)"
      wav="$(mktemp --suffix=.wav)"
      PYTHONPATH="$PIPER_SITE_DIR" python3 -m piper -m "$model" -f "$wav" -- "$text" \
        || { rm -f "$wav"; die "piper synthesis failed"; }
      # Piper writes WAV; convert to mp3 so audio/NN.mp3 matches every other engine.
      "$FFMPEG" -y -i "$wav" -codec:a libmp3lame "$out" >/dev/null 2>&1
      rm -f "$wav"
      [ -s "$out" ] || die "piper produced no audio (ffmpeg WAV->mp3 conversion may have failed)"
      ;;
    *) die "unknown TUT_TTS: $TTS (use elevenlabs, openai, or piper)" ;;
  esac
  echo "narration scene $nn ($TTS) -> $out"
}

cmd="${1:?usage: narrate.sh voices | narrate.sh <NN> \"<text>\"}"
case "$cmd" in
  voices) list_voices ;;
  *)      synth "$@" ;;
esac
