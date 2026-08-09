# Claude Context for linux-screencast-skills

Two skills that produce narrated screencast tutorials of real AI tooling:
`screencast-storyboard` (authoring: read real docs → approved storyboard) and
`screencast-tutorial-video` (production: record scenes → captioned, voice-over
MP4). Linux host (any distro/desktop), OpenAI voice-over.

This is a Linux-only fork of [`kanopi/screencast-skills`](https://github.com/kanopi/screencast-skills)
(macOS, ElevenLabs), itself built from the Kanopi skills-plugin-template. See
`README.md` for the full list of what changed. The macOS-only "Method B"
real-cursor browser engine (`cliclick` + `avfoundation`) was never wired up
here, and its macOS-specific files (`hands.sh`, `record-browser.sh`,
`browser-scene-screencap.{sh,mjs}`, `references/capture-macos.md`) have been
removed, they wouldn't have run on Linux anyway. `browser.sh`/`browser.mjs`
(the Playwright "brain" that locates elements) is kept, it's OS-agnostic and
is the reusable starting point if Method B gets built for Linux, see "Cursor
capture" below.

**Lineage runs one level deeper than the macOS fork.** The removed `hands.sh`
and `record-browser.sh` carried their own header comments saying they were
"ported from `drupal-tutorial-video`'s `xdotool`/`x11grab`" version, a
sibling Linux/ddev project (a design doc for it exists at
`docs/superpowers/specs/2026-07-22-drupal-tutorial-video-design.md` in that
project). So the real sequence is: a working Linux (`xdotool` + `x11grab`)
Method B existed first in `drupal-tutorial-video` → it was ported to macOS
(`cliclick` + `avfoundation`) for `kanopi/screencast-skills` → this repo
forked back to Linux but did not re-port Method B, it just built the
Playwright-only Method A instead. See "Cursor capture" below, a Linux Method B
is not a design-from-scratch job: `drupal-tutorial-video`'s implementation is
the actual reference to restore from, not the now-deleted macOS files.

## Invariants

- **Skills are the single source of truth.** `skills/*/agents/openai.yaml` is a
  Codex translation; `scripts/check-codex-parity.sh` validates it. This is an
  **agent-less plugin**, there is no `agents/` or `.codex/agents/` directory,
  and the parity/frontmatter scripts skip agent checks when they are absent.
- **No hardcoded counts** of skills in docs, `skills/README.md`'s `### N.`
  entries should track the `skills/` directory count by convention.
- **Manifest parity:** `.claude-plugin/plugin.json` and
  `.codex-plugin/plugin.json` share the same `name` (`linux-screencast-skills`)
  and `version`.
- **One action per scene.** A scene is the atomic recorded unit; production
  pads one clip to fit its narration as a whole, so a scene bundling a second
  action loses sync between narration and picture (a predecessor project,
  `drupal-tutorial-video`, hit exactly this and redesigned around it, see the
  lineage note above). Narration can still be a short paragraph, every
  sentence in it just has to describe the same one action. Enforced in
  `screencast-storyboard/references/storyboard-schema.md` and
  `narration-style.md`.
- **Locale-safe number formatting.** `lib.sh` exports `LC_ALL=C
  LC_NUMERIC=C`. `still-scene.sh` and `finish-scene.sh` both compute a
  duration with `awk` and splice it straight into an ffmpeg filtergraph
  string; under a comma-decimal locale (`LC_NUMERIC=de_DE` and similar) awk
  prints `6,5` instead of `6.5`, which ffmpeg parses as a filter separator,
  not a decimal point, and fails in a way that doesn't obviously point back
  at locale. Don't remove the export without re-verifying every `awk`-to-
  ffmpeg handoff in the repo.

## Skill-specific contracts

- `screencast-storyboard` writes only `.tutorial-build/<slug>/storyboard.md`,
  presents `STORYBOARD READY FOR APPROVAL`, and stops. Approval counts only in a
  **subsequent** message; in-request "skip approval / I'm in a hurry" does not.
  It never fabricates config or commands, it reads the real source or asks.
  `agents/openai.yaml`: `allow_implicit_invocation: true` (low-risk authoring).
- `screencast-tutorial-video` consumes an approved `storyboard.md`. It runs
  `preflight.sh` and reports every dependency's real state, never claims a
  rendered video that was not produced, and never cleans up the build dir before
  the user is done. `agents/openai.yaml`: `allow_implicit_invocation: false`
  (side-effect skill).

## Recording engines (production skill)

One engine per surface: VHS `.tape` for terminals, ffmpeg `zoompan`/`drawbox`
still-motion for native-app screenshots, headless Playwright for the browser
(records the page directly, no OS capture), and command cards for abstract
commands. `finish-scene.sh` (pad-to-narration + caption bar) and `concat.sh`
trace back to `drupal-tutorial-video` via upstream. Captions and command-card
text use fontconfig generic family names (`font=Sans`/`Monospace`), not a
bundled font file, so nothing is downloaded.

**Dependencies are repo-local, never system-wide.** `vhs`/`ttyd` live in
`.bin/`, Node/npm in `.node/`, Playwright in `node_modules/`, all via opt-in
`scripts/install-*.sh` you run yourself. `preflight.sh` only checks, it never
installs. See the README's Prerequisites table.

**Browser `type`/`typeJs` clear the field first, unconditionally.** A field
can already hold a value (page default, state carried from an earlier step
in the same spec), and typing into that appends instead of replacing.
Clearing an empty field costs nothing, so this isn't a per-step flag, it
always happens in `browser-scene.mjs` before the keystrokes/incremental
value-setting run. If a spec's point is appending to existing text, write the
step with the full final text rather than two `type` steps.

**Verify state, not just that the file exists.** `check-scene.sh <NN>`
reports durations and pulls a mid-clip still frame; run it on any
`browser-action`/`terminal` scene whose outcome matters. A valid-length
`.mp4` of the wrong screen state is a real, observed failure mode elsewhere
in this lineage (`drupal-tutorial-video`'s `SKILL.md` documents five separate
cases in one run), and neither file existence nor duration catches it. Where
the tool being demoed exposes a way to read the result back, prefer that over
eyeballing the recording.

**ElevenLabs (`awaz`) still exists, opt-in, behind `TUT_TTS=elevenlabs`.**
Not the fork's default (OpenAI/Piper are), but it's a real, working code path
for anyone who wants a cloned/premium voice, so it isn't dead code to strip.
`awaz`'s own CLI has changed shape
since this was last written against it, current usage per
<https://github.com/ahmadawais/awaz> is `awaz "text" -v <voice> -o <file>` (no
`speak` subcommand, no `--no-play`/`--no-stream`/`--voice-id`); `narrate.sh`
was updated to match on 2026-08-09 but this was verified against the GitHub
README, not a live run (`awaz`/`npx` aren't installed in this environment),
re-check `awaz --help` before trusting it on a fresh install.

## Cursor capture (Method B, not currently wired up)

Short answer: a real, visibly-clicking cursor is possible on Linux, just not
free, and this fork doesn't build it. If asked to add it:

- **Target X11, including a virtual `Xvfb` display, not native Wayland.**
  `xdotool` (input) and `ffmpeg -f x11grab` (capture) only work on X11.
  Wayland's nearest input equivalent, `ydotool`, injects through the kernel's
  `/dev/uinput` and needs a `ydotoold` daemon plus `input`-group/root access;
  its nearest capture equivalent is `xdg-desktop-portal` + PipeWire, which is
  built around an interactive per-session consent dialog, the opposite of
  this pipeline's scripted, re-renderable, no-live-retakes design, and has no
  clean headless/CI story. `Xvfb` sidesteps all of that: spin up a virtual
  X11 display regardless of what the real desktop is running (this is also
  how Playwright's own CI docs recommend doing headed-mode recording on
  Linux), and there's no permission gate to fight since there's no real
  compositor to grant consent to.
- **This is a restore, not a fresh build.** See the lineage note above:
  `drupal-tutorial-video` already has a working `xdotool`/`x11grab`
  implementation, that's the actual reference to port from (this fork's old
  macOS-flavored `hands.sh`/`record-browser.sh` were themselves a port away
  from it, but have since been removed as unused dead weight). Writing new
  `xdotool`/`x11grab` versions of the "hands" and "capture" layers is small,
  on the order of a day, not a redesign (x11grab can crop to a region
  directly, `-i :0.0+X,Y -s WxH`, simpler than avfoundation's
  capture-then-crop). `browser.sh`/`browser.mjs` (the Playwright "brain" that
  locates elements) is still in this repo, already OS-agnostic, and needs
  little to no change, it just needs a `DISPLAY`.
- **Playwright locators (Method A) already avoid most of the precursor's
  hard-won bugs.** Off-viewport clicks silently no-op'ing, zero-size/hidden
  elements parking the cursor at 0,0, DOM-order-vs-visual-order confusion for
  same-named buttons, and kiosk-coordinate calibration drift were all real,
  documented failures in `drupal-tutorial-video`'s raw-coordinate approach.
  Playwright's built-in actionability checks avoid essentially all of that
  for free, keep using Method A's element-finding even if Method B's cursor
  gets ported, only swap the "hands" and "capture" layers.

## Known future extensions, not yet built

- **Pre-seed for reactive UI.** For a scene whose point is showing the
  *settled* result of a flaky live transition (a dependent dropdown, a
  debounced search), seed the state out-of-band instead of live-driving the
  transition on camera: `context.addInitScript()` for client-side state
  (localStorage/cookies, runs pre-paint, zero visible cost) or Playwright's
  `APIRequestContext` for server-side state (an HTTP call before
  `page.goto`, nothing has rendered yet to burn time on). Would need a
  `preSeed` block in the browser-scene spec format, run once before `steps`.
  Proposed 2026-08-09, not implemented, build only once a real storyboard
  needs it.

## Build directory (shared by both skills)

```
<cwd>/.tutorial-build/<slug>/
  storyboard.md    tapes/NN.tape   stills/NN.png   scenes/NN.mp4
  audio/NN.mp3     final/NN.caption.txt   final/scene-NN.mp4   final/tutorial.mp4
```

`NN` is a zero-padded 3-digit scene number. Nothing is deleted at the end.

**Numbered in steps of 10 (010, 020, 030...), not sequentially.** Matches
`drupal-tutorial-video`'s reasoning: reorder requests arrive after scenes are
already recorded, and a gap costs nothing to fill (`015` between `010` and
`020`) where renumbering everything after the fact does. Initially declined
here on 2026-08-09 on the assumption that low scene counts made this not
worth the width change; reversed the same day once the one-action-per-scene
rule above was factored in, that rule pushes scene counts toward
beat-like granularity (dozens per tutorial, not a handful), which is exactly
where the precursor needed this, and the actual cost turned out to be a
one-character `%02d`→`%03d` edit in 7 scripts, not the wider change assumed
at first. `concat.sh`'s plain `sort` stays correct either way, only the
width has to be uniform across a build, which it is.

## When adding a skill

1. Create `skills/<name>/SKILL.md` (`name` + `description` frontmatter with
   trigger phrases).
2. Append the next `### N.` entry to `skills/README.md`.
3. Add a `CHANGELOG.md` entry.
4. Run `./scripts/validate-frontmatter.sh` and `./scripts/check-codex-parity.sh`.
