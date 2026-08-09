# Linux Screencast Skills

Two Claude Code / Codex skills that turn "here is what the demo should cover"
into a narrated, captioned tutorial video of the **real tool doing the real
thing**. Built for training videos that explain AI tooling, but stack-agnostic:
it records any terminal, native app, or browser workflow.

Linux host, any distro/desktop. OpenAI voice-over.

This is a Linux-only fork of [`kanopi/screencast-skills`](https://github.com/kanopi/screencast-skills)
(MIT, Copyright Kanopi Studios; see `LICENSE.md`), which targets macOS only.
The upstream also credits prior art: the
[`drupal-tutorial-video`](https://github.com/kanopi/drupal-skills) skill.

**What changed from upstream:**

- Runs on Linux instead of macOS (`preflight.sh` no longer hard-blocks on
  non-Darwin; the ffmpeg/Node/VHS pipeline was already OS-agnostic underneath).
- The "real cursor visibly clicking" browser engine (Method B: macOS's
  `cliclick` + `avfoundation`) is **not ported** and not available here. Only
  the default, recommended engine is used: headless Playwright records the
  page directly and draws a highlight box instead of a cursor. See
  `skills/screencast-tutorial-video/SKILL.md` for the deferred-feature note,
  and `CLAUDE.md`'s "Cursor capture" section for what a Linux port would
  actually take (short version: yes, it's possible, on X11/Xvfb; native
  Wayland capture is a materially bigger, separate undertaking).
- OpenAI (or [Piper](https://github.com/OHF-voice/piper1-gpl) for free/offline)
  is the **default** TTS engine. ElevenLabs via `awaz` still works
  (`TUT_TTS=elevenlabs`, `ELEVENLABS_API_KEY`) for anyone who wants a
  cloned/premium voice; it is opt-in, not the fork's default story. `awaz`'s
  own CLI has changed since this was last written against it (no more
  `speak` subcommand); if `narrate.sh`'s `elevenlabs` case starts failing,
  re-check `awaz --help` against `narrate.sh`'s invocation before assuming
  the key or account is the problem.
- No brand fonts are downloaded; caption bars and command cards use whatever
  sans/monospace font fontconfig resolves on the host.
- `preflight.sh` only **checks** dependencies and prints fix commands; it never
  installs anything itself. See Prerequisites below.
- Playwright installs locally (`npm install`, `node_modules/` inside this
  repo) instead of globally, and `vhs` installs into `.bin/` inside this repo
  via an explicit, opt-in script. The whole thing is removable with `rm -rf`
  on this directory (plus, if you want to reclaim the Chromium download,
  `npx playwright uninstall`).

## The two skills

### 1. `screencast-storyboard`, author the script (dependency-free)

Input: what the demo should cover. It **reads the tool's real README, install
command, and config JSON** so the transcript's commands and config are
accurate, drafts `.tutorial-build/<slug>/storyboard.md` (ordered scenes with
type, on-screen actions, narration, one-line caption, and pacing), presents it,
emits `STORYBOARD READY FOR APPROVAL`, and stops for your approval. It never
invents config or commands, and the storyboard stands on its own, it can feed
a human presenter or another tool.

**One action per scene** is a hard rule, not a style choice: production pads
a whole scene's clip to fit its narration as one unit, so a scene with two
actions behind one narration block has nothing keeping the second action in
sync with where the narration gets to it. Narration itself can run to a short
paragraph, just every sentence in it has to describe that same one action.

Trigger phrases: "script a tutorial", "draft the transcript and timeline for a
demo", "outline a screencast walkthrough".

### 2. `screencast-tutorial-video`, produce the video (Linux host)

Input: an approved `storyboard.md`. It records each scene with the right engine
and assembles one MP4:

| Surface | Engine |
|---|---|
| Terminal (Claude Code / any CLI) | **VHS** `.tape` → MP4, declarative typing, deterministic, re-renderable |
| Native app screenshot | **ffmpeg `zoompan` + `drawbox`** motion over PNG stills |
| Browser (claude.ai / dashboards) | **Playwright**, headless, records the page directly at 1080p; highlights elements instead of showing a cursor |
| Abstract command | **command card** (still frame) |

A real, visibly-clicking on-screen cursor for the browser engine (upstream's
"Method B") is not available in this fork, see the Requirements note below.

Each scene gets narration (OpenAI, or [Piper](https://github.com/OHF-voice/piper1-gpl)
for free/offline with no API key, `TUT_TTS=piper`), a bottom caption bar, and
is padded to the narration length; scenes concatenate into `final/tutorial.mp4`.
Every scene is independently re-renderable, change one line, re-run one
script, re-concat. No timeline video editing.

`check-scene.sh <NN>` sanity-checks a scene beyond "the file exists": raw and
finished durations, a still frame pulled from the middle of the clip so you
can confirm the screen actually shows what the storyboard claims, and flags
for an unfinalized stub or a scene that ran suspiciously long. A valid-length
`.mp4` of the wrong screen state is a real failure mode a size check misses.

Trigger phrases: "record the screencast from my storyboard", "produce the
narrated MP4", "render the tutorial video with voice-over and captions".

## Why this beats transcript → Google Vids avatar

`screencast-storyboard` writes the transcript+timeline you already produce by
hand (its output can still feed Google Vids). `screencast-tutorial-video` then
shows the real tool, which an avatar reader can't. Terminal scenes are `.tape`
files: perfect typing, no retakes, seconds to re-render.

## Prerequisites (production skill)

`preflight.sh` only **checks** these and tells you the fix command; it never
installs anything on its own. The storyboard skill has no dependencies at all.

Distro doesn't matter here, only CPU arch does: `vhs`/`ttyd`/Node all install
as static/self-contained binaries keyed off `uname -m` (x86_64/arm64), not
`apt`/`dnf`/`pacman`, so Ubuntu, Fedora, and Arch are equally supported. The
one dependency that goes through the system package manager is `ffmpeg`
itself.

| Dependency | Why | Install |
|---|---|---|
| `ffmpeg` + `ffprobe`, with the `drawtext` filter (built against libfreetype + libfontconfig) | Every non-terminal scene, captions, command cards | Your distro's package manager (`apt`/`dnf`/`pacman`/`apk`); most distro builds already have `drawtext` (confirmed on Ubuntu/Debian, Fedora, Arch) |
| `vhs` (and its own dependency `ttyd`) | Renders terminal scenes from `.tape` files | `./scripts/install-vhs.sh` — downloads Charm's/tsl0922's static Linux binaries into `.bin/` inside this repo, no `sudo`, nothing installed system-wide |
| Node.js + npm | Runs the browser engine | `./scripts/install-node.sh` — downloads the official nodejs.org tarball into `.node/` inside this repo. (Debian/Ubuntu's `npm` package pulls in ~300 transitive packages plus a native build toolchain; this sidesteps that entirely.) |
| Playwright + Chromium | Headless browser recording | `npm install` (local, `node_modules/` inside this repo) then `npx playwright install chromium` (downloads into Playwright's own `~/.cache/ms-playwright`, its standard location) |

Narration (`narrate.sh`) needs **one** of these; everything else works without either:

| Engine | Why you'd pick it | Install |
|---|---|---|
| OpenAI (`TUT_TTS=openai`, the default when its key is set) | More natural voice, low per-character cost | `jq` (your distro's package manager) + `OPENAI_API_KEY` in your environment |
| [Piper](https://github.com/OHF-voice/piper1-gpl) (`TUT_TTS=piper`) | Free, offline, no account or API key at all; noticeably less natural than OpenAI | `./scripts/install-piper.sh` — `pip install --target` (no venv, no sudo, sidesteps Debian's separate `python3-venv` package and PEP 668's system-pip block) into `.piper/site-packages`, plus one voice model downloaded from Hugging Face into `.piper/voices/`. Check the voice's `MODEL_CARD` for its dataset license before commercial use. |

Nothing here writes outside this repo except Playwright's own Chromium cache.
`rm -rf` on this directory (optionally plus `npx playwright uninstall`) removes
everything.

## Repo tooling

Built from the [Kanopi skills-plugin-template](https://github.com/kanopi/skills-plugin-template).
Checks that should pass before any push:

```bash
./scripts/validate-frontmatter.sh
./scripts/check-codex-parity.sh
```
