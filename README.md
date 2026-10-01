# Linux Screencast Skills

Two skills for Claude Code (and Codex) that turn "here's what the demo should
cover" into a narrated, captioned tutorial video of the real tool doing the
real thing.

1. **`screencast-storyboard`** writes the script. It reads the tool's real docs
   and config, drafts a scene-by-scene `storyboard.md`, then stops so you can
   approve it.
2. **`screencast-tutorial-video`** makes the video from an approved storyboard:
   it records each scene, adds a voice-over and a caption bar, and joins
   everything into one 1920x1080 MP4.

Works on any Linux distro and desktop. Records terminals, browsers, and
screenshots of native apps.

## Quickstart

Run these from the root of this repo. You only need steps 1-4 once.

```bash
# 1. System package (the only thing that needs sudo)
sudo apt install ffmpeg jq          # or dnf / pacman / apk

# 2. Local tools, installed inside this repo (no sudo)
./scripts/install-vhs.sh            # terminal recorder
./scripts/install-node.sh           # Node.js + npm
npm install
npx playwright install chromium     # browser recorder

# 3. A voice for the narration: pick ONE
export OPENAI_API_KEY=sk-...        # natural voice, costs a little
./scripts/install-piper.sh          # or: free, offline, less natural
                                    #     (then: export TUT_TTS=piper)

# 4. Check everything
./skills/screencast-tutorial-video/preflight.sh
```

Then, in Claude Code:

1. Ask: *"Script a tutorial showing how to add an MCP server in Claude Code."*
   You get a `storyboard.md` and a `STORYBOARD READY FOR APPROVAL` message.
2. Read it, ask for changes if needed, then reply with your approval.
3. Ask: *"Record the screencast from my storyboard."*
4. Your video is at `.tutorial-build/<slug>/final/tutorial.mp4`.

To fix one scene, re-run just that scene and re-join. There's no video editor
involved. `check-scene.sh <NN>` shows you a still frame from the middle of a
scene so you can confirm the screen shows what the storyboard says.

## Requirements

The storyboard skill needs nothing. Everything below is for the video skill.
`preflight.sh` checks all of it, prints the exact fix for anything missing, and
never installs anything itself.

| What | Needed for | Where it lives | How to get it |
|---|---|---|---|
| `ffmpeg` and `ffprobe` (with the `drawtext` filter) | Everything except terminal-only scenes: captions, cards, stitching | **System-wide** | Package manager. Standard distro builds already include `drawtext`. |
| `jq` | OpenAI narration only | **System-wide** | Package manager |
| `vhs` and `ttyd` | Terminal scenes | **Local file**: `.bin/` in this repo | `./scripts/install-vhs.sh` |
| Node.js and npm | Browser scenes | **Local file**: `.node/` in this repo | `./scripts/install-node.sh` |
| Playwright | Browser scenes | **Local file**: `node_modules/` in this repo | `npm install` |
| Chromium | Browser scenes | **User-wide**: `~/.cache/ms-playwright` (Playwright's own cache) | `npx playwright install chromium` |
| OpenAI API key | Narration, option 1 | **Environment variable**: `OPENAI_API_KEY` | Your OpenAI account |
| Piper and a voice model | Narration, option 2 (free, offline) | **Local file**: `.piper/` in this repo | `./scripts/install-piper.sh` (needs `python3` with `pip`) |
| `xdotool` and `Xvfb` | Optional: browser scenes with a visible moving cursor | **System-wide** | Package manager (`xvfb` on Debian/Ubuntu) |
| ElevenLabs (`awaz`) and key | Optional: premium or cloned voice | **Environment variable**: `ELEVENLABS_API_KEY`, plus `TUT_TTS=elevenlabs` | Your ElevenLabs account |

You need **one** narration option (OpenAI or Piper). Without either, every
scene type still works except the voice-over.

Your CPU architecture matters (x86_64 or arm64), your distro doesn't: the
local tools are downloaded as ready-made binaries.

### Uninstalling

Delete this directory. The only thing outside it is Chromium's cache; remove
that with `npx playwright uninstall`. The system packages are yours to remove.

### Security note

`install-vhs.sh` and the Piper voice download fetch the latest release over
HTTPS with **no checksum check**, so they aren't reproducible and aren't
verified. `install-node.sh`, `npm install` and the Chromium download do verify
what they fetch. None of these use `sudo`, but a bad download would still run
as you. Details are in `CLAUDE.md`.

## How each scene is recorded

| Scene is... | Recorded with |
|---|---|
| A terminal (Claude Code, any CLI) | VHS: a typed script, so it is repeatable |
| A screenshot of a native app | ffmpeg zoom and highlight over the image |
| A browser (default) | Playwright, headless. Highlights elements; no cursor is shown |
| A browser, with a real cursor (opt-in) | `xdotool` and `ffmpeg x11grab` on a virtual `Xvfb` screen |
| A command with nothing to show | A "command card" still image |

Use the default browser engine unless a scene really needs to show a cursor
moving and clicking.

**One action per scene.** Each scene's clip is stretched to fit its narration
as a whole. If a scene did two things, the second would drift out of sync with
the voice. Narration can be a short paragraph as long as it only describes that
one action.

## Where this came from

A Linux-only fork of [`kanopi/screencast-skills`](https://github.com/kanopi/screencast-skills)
(MIT, Copyright Kanopi Studios), which only runs on macOS. Differences:

- Runs on Linux. The real-cursor browser engine is rebuilt with `xdotool` and
  `Xvfb` instead of the macOS-only `cliclick`.
- OpenAI or Piper is the default voice. ElevenLabs still works but is opt-in.
- Tools install inside this repo, not system-wide, via scripts you run yourself.
- No brand fonts are downloaded; captions use your system's default fonts.

## Contributing

Run both before any push:

```bash
./scripts/validate-frontmatter.sh
./scripts/check-codex-parity.sh
```

Built from the [Kanopi skills-plugin-template](https://github.com/kanopi/skills-plugin-template).
Design notes and gotchas for working on the code are in `CLAUDE.md`.
