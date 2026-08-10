---
name: screencast-tutorial-video
description: Use when producing the actual screencast video from an approved storyboard, the user says "record the screencast", "produce the narrated MP4", "render the tutorial video", "make the video from my storyboard", or "cut the screencast together". Records each scene on the Linux host with the right engine (VHS for terminals, ffmpeg still-motion for native-app screenshots, headless Playwright for the browser, command cards for abstract commands), generates voice-over (OpenAI, or Piper for free/offline with no API key), overlays a caption bar, and concatenates the scenes into one 1920x1080 MP4. Requires an approved storyboard.md from screencast-storyboard; if none exists, route there first. Never claims a rendered video that was not produced.
---

# Screencast Tutorial Video

## Overview

This is the **production** half of the screencast workflow. It consumes an
approved `storyboard.md` (from `screencast-storyboard`) and produces one
narrated, captioned 1920x1080 MP4 that shows the real tool doing the real thing.

Everything runs natively on the **Linux host** (any distro/desktop), no
container. One engine per surface:

| Surface | Engine | Script |
|---|---|---|
| Terminal (Claude Code / any CLI) | VHS `.tape` → MP4 | `render-tape.sh` |
| Native app screenshot | ffmpeg `zoompan` + `drawbox` over a PNG still | `still-scene.sh` |
| Browser (docs / UI tours) | Playwright records the page headless at 1080p (no OS capture, no permissions, records only the page) | `browser-scene.sh` |
| Browser, real cursor (opt-in) | Kiosk Chromium on a virtual Xvfb display, xdotool moves/clicks/types, ffmpeg x11grab captures the screen live | `browser-scene-cursor.sh` |
| Abstract command | command card (still) | `make-card.sh` |

**Two browser engines.** `browser-scene.sh` (Method A, the default) is
headless, needs no extra host dependencies, and highlights whatever the
narration is discussing with an in-page outline instead of a cursor — for
most docs/UI tours that reads as clean, not as a compromise, so start here.
`browser-scene-cursor.sh` (Method B) is the opt-in alternative for a scene
that specifically needs a real, visibly-moving cursor: same `spec.json`
format as Method A, swap the script name, nothing else changes. It needs
`xdotool` + `Xvfb` (system packages, see Requirements below) and trades a
little text crispness for the real cursor (no 2x supersampling — exact 1:1
pixel mapping is what makes the on-screen coordinate math work). Ask which
engine a `browser-action` scene should use if the storyboard doesn't already
imply one; default to Method A when in doubt. See
`references/browser-playwright.md` for the full trade-offs and
`CLAUDE.md`'s "Cursor capture" section for the design.

Each scene is padded to its narration, gets a caption bar, and concatenates into
`final/tutorial.mp4`. Every scene is independently re-renderable, change one
line, re-run one script, re-concat. No timeline editing.

## Requirements (hard)

- An approved `storyboard.md` at `.tutorial-build/<slug>/storyboard.md`. If it is
  missing, direct the user to `screencast-storyboard` first, do not invent one.
- Linux host with `ffmpeg` (drawtext-capable), `vhs` (+ its own `ttyd`
  dependency), Node.js + npm, Playwright, and **one** narration engine:
  `OPENAI_API_KEY` + `jq` (OpenAI), or Piper (free, offline, no key, lower
  voice quality — `TUT_TTS=piper`). No ElevenLabs in this fork.

`preflight.sh` **checks** all of this and reports the real state; it never
installs anything itself. `./scripts/install-vhs.sh`,
`./scripts/install-node.sh`, and `./scripts/install-piper.sh` are separate,
opt-in, repo-local installers (see the top-level README's Prerequisites
table) — run them yourself, nothing here auto-installs.

## Requirements (optional, `browser-scene-cursor.sh` / Method B only)

- `xdotool` + `Xvfb` (system packages, like `ffmpeg`, not repo-local). Neither
  is needed for anything else in this skill; `preflight.sh` reports their
  state as a `WARN`, not a `MISS`, so their absence never blocks the main
  pipeline. `browser-scene-cursor.sh` re-checks and dies with the same fix
  command if you actually run it without them.

## Helper scripts

Run every script with `export TUT_SLUG=<slug>` set, **from the directory that
holds `.tutorial-build/`** (the build dir is resolved relative to the working
directory). To run from elsewhere, `export HDIR=<absolute build dir>`, the
scripts and `browser-scene.mjs` both honor it, so scenes never land in the wrong
folder. Scripts read `lib.sh` for shared paths and settings. For house defaults
(voice, tone, resolution) a preset loads automatically, `TUT_PRESET` defaults to
`default` (this fork's baseline settings); see `presets/README.md` to add your
own, or `TUT_PRESET=none` to skip. Override with `export TUT_TTS=piper` for
the free/offline engine.

| Script | Purpose |
|---|---|
| `preflight.sh` | Check (never install) host deps; create the build dir |
| `render-tape.sh <NN> <tape>` | Render a VHS terminal scene → `scenes/NN.mp4` |
| `still-scene.sh <NN> <png> [dur] [x:y:w:h]` | Ken Burns + highlight over a still → `scenes/NN.mp4` |
| `browser-scene.sh <NN> <spec.json>\|<url> [s]` | Playwright records the page headless → `scenes/NN.mp4` |
| `browser-scene-cursor.sh <NN> <spec.json>` | Real cursor (xdotool) on a kiosk Chromium, captured live with x11grab → `scenes/NN.mp4`. `... stop` tears down the session. |
| `make-card.sh <NN> <seconds> <command-text>` | Render a command card → `scenes/NN.mp4` |
| `narrate.sh voices` / `narrate.sh <NN> "<text>"` | List OpenAI voices / synthesize narration → `audio/NN.mp3` |
| `finish-scene.sh <NN>` | Pad video to narration, add lead/tail silence, mux audio, draw caption bar |
| `check-scene.sh <NN>` | Sanity-check one scene: raw/finished/audio duration, a still frame to eyeball, stub/overlong flags |
| `concat.sh` | Concatenate `final/scene-*.mp4` → `final/tutorial.mp4` |

Loaded-on-demand detail lives in `references/`: `terminal-vhs.md`,
`browser-playwright.md`, `desktop-stills.md`.

## Build directory

```
<cwd>/.tutorial-build/<slug>/
  storyboard.md            # from screencast-storyboard (input)
  specs/NN.json            # browser-scene.sh scene spec
  tapes/NN.tape            # normalized VHS tape (render-tape.sh writes this)
  stills/NN.png            # native-app screenshots you capture
  scenes/NN.mp4            # raw silent scene (any engine) or command card
  audio/NN.mp3             # narration (OpenAI)
  final/NN.caption.txt     # one-line caption for scene NN (empty = no bar)
  final/scene-NN.mp4       # padded + muxed + captioned
  final/tutorial.mp4       # concatenated result
```

`NN` is a zero-padded 3-digit scene number, numbered in steps of 10 (`010`,
`020`, `030`, ...) per `screencast-storyboard`'s schema, so a late insert
between two scenes costs nothing. Nothing is deleted at the end.

## Scene taxonomy

`intro` · `terminal` (VHS) · `desktop-still` · `browser-action` · `command-card`
· `outro`. The storyboard assigns each scene a `type`; map it to the engine in
the table above.

## Workflow

Create a todo per step.

1. **Load the approved storyboard.** Read `.tutorial-build/<slug>/storyboard.md`.
   If it does not exist, tell the user to run `screencast-storyboard` first and
   stop. If any scene still contains a `[NEEDS: ...]` marker, ask for the real
   value before recording that scene, do not fabricate it.

2. **Preflight.** `export TUT_SLUG=<slug>` then `./preflight.sh`. Report every
   dependency's real state. If it exits non-zero (a required dep is missing),
   **do not proceed and do not claim any video was produced**, report the
   blocker and the fix command it printed (it never installs anything itself).

3. **Pick a voice.** Run `./narrate.sh voices` (lists the OpenAI voice set),
   present the options, and ask which to use. Remember the choice as `TUT_VOICE`.

4. **Produce each scene** by `type`, in order. Write the one-line caption to
   `final/NN.caption.txt` first (empty file = no bar), then:
   - `terminal`: author a tape from `templates/scene.tape`, then
     `./render-tape.sh NN <tape>`.
   - `desktop-still`: capture `stills/NN.png`, then
     `./still-scene.sh NN stills/NN.png <dur> [highlight]`.
   - `browser-action`: write a scene spec (URL + `steps`: scroll / highlight /
     wait, plus goto / click / type / submit for multi-page flows) and
     `./browser-scene.sh NN <spec.json>` (default: headless, no cursor, no
     extra deps). If the storyboard specifically calls for a real,
     visibly-moving cursor, use `./browser-scene-cursor.sh NN <spec.json>`
     instead — same spec, needs `xdotool`+`Xvfb`. Either way it waits for
     fonts (no FOUT) and records only the page. See
     `references/browser-playwright.md` for the spec format and the two
     engines' trade-offs.
   - `command-card`: `./make-card.sh NN <seconds> "<command>"`.
   - `intro`/`outro`: usually a `desktop-still` or `command-card`.

5. **Narrate.** For each scene:
   ```
   export TUT_VOICE=<voice>          # from step 3
   ./narrate.sh NN "<narration text>"
   ```
   `narrate.sh` writes `audio/NN.mp3` via OpenAI `/v1/audio/speech` (model via
   `TUT_OPENAI_TTS_MODEL`, default `gpt-4o-mini-tts`) or, with `TUT_TTS=piper`,
   fully offline with no API key (lower voice quality, no per-character cost).
   **Pronunciation:** the OpenAI `instructions` field (`TUT_TTS_INSTRUCTIONS`) is
   unreliable for names, if a brand/term is mispronounced, respell it
   phonetically in the narration text itself (e.g. write "EN-jin-EX" for
   "Nginx"). Adjust the syllable emphasis until it lands. Applies to Piper too.

6. **Finish each scene.** `./finish-scene.sh NN` for every scene. It pads the
   video to the narration (never trims audio to fit video), adds ~1s lead/tail
   silence, muxes the audio, and draws the caption bar.

7. **Verify, don't just check the file exists.** Run `./check-scene.sh NN`
   on any `browser-action` or `terminal` scene whose outcome matters (a form
   submit, a command that changes state); it reports durations and drops a
   still frame from the middle of the clip so you can confirm the screen
   actually shows what the storyboard claims. A valid-length `.mp4` of the
   wrong state is the failure mode a size/existence check cannot catch. Where
   the tool exposes a way to read the result back (reload the page, query an
   API, re-run the command with a status flag), do that instead of eyeballing
   the recording.

8. **Concatenate and present.** `./concat.sh`, then show the user
   `.tutorial-build/<slug>/final/tutorial.mp4`. **Do not clean up.** On change
   requests, re-produce or re-finish only the affected scenes and re-run
   `concat.sh`. If any scene used `browser-scene-cursor.sh`, its Xvfb/Chromium
   session is left running for fast re-recording; `./browser-scene-cursor.sh
   stop` once the user is done reviewing, not before.

## Honesty rules (hard)

- **Never claim a rendered video that was not produced.** Only say
  `final/tutorial.mp4` exists after `concat.sh` succeeds and the file is there.
- **Report real preflight failures.** If `preflight.sh` finds a missing
  dependency, say so plainly and give the fix command it printed. Do not run
  the pipeline against a false green.
- **Never clean up the build dir** before the user is done reviewing.
- **Narration syncs to video, not the reverse.** `finish-scene.sh` pads the
  video to the audio; never trim the narration to fit the clip.

## Common mistakes

| Mistake | Fix |
|---|---|
| Asking for a real on-camera cursor | `browser-scene-cursor.sh` (Method B); needs `xdotool`+`Xvfb` (preflight's Method B section reports these). Default to `browser-scene.sh`'s highlight box unless the storyboard specifically calls for a moving cursor. |
| A flash of unstyled text at a scene start | Method A waits for `document.fonts.ready` and trims the first ~1.5s; keep that lead-trim when assembling. |
| Scenes landing in the wrong folder | Run from the build parent, or `export HDIR=<absolute>` so `.sh` and `.mjs` agree. |
| Recording a live terminal | Terminal scenes are VHS `.tape` files, not screen captures. |
| `preflight.sh` MISS lines | It only checks, never installs. Run the fix command it printed (`./scripts/install-vhs.sh`, `./scripts/install-node.sh`, `npm install`, `npx playwright install chromium`, or a system package). |
| Fabricating a config that was not in the storyboard | The storyboard already read the real source. If a scene has `[NEEDS: ...]`, ask; never invent. |
| Claiming the MP4 rendered when a step failed | Check the finish/concat logs; only report success when the file exists. |
| Cleaning up before approval | Leave the build dir intact until the user is done. |
| VHS output not 1920x1080 | `render-tape.sh` forces it; do not override Width/Height in the tape. |
| Customizing `WIN_X`/`WIN_Y`/`WIN_W`/`WIN_H` for a `browser-scene-cursor.sh` scene | Don't, for this engine specifically — kiosk mode fullscreens to the Xvfb screen, which only matches the on-screen coordinate math when the window already covers it (i.e. left at the `TUT_RES` default). Method A's window geometry has no such constraint. |
