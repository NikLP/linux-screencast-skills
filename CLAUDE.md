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
`browser-scene-screencap.{sh,mjs}`, `references/capture-macos.md`) were
removed, they wouldn't have run on Linux anyway. `browser.sh`/`browser.mjs`
(the Playwright "brain" that locates elements) was kept, OS-agnostic, and is
now the shared foundation both browser engines build on: Method A
(`browser-scene.sh`, headless, no cursor, the default) and the Linux-native
Method B built on 2026-08-10 (`browser-scene-cursor.sh` + `hands.sh` +
`xvfb.sh`, real cursor via `xdotool`/`x11grab`), see "Cursor capture" below.

**Lineage runs one level deeper than the macOS fork.** The removed `hands.sh`
and `record-browser.sh` carried their own header comments saying they were
"ported from `drupal-tutorial-video`'s `xdotool`/`x11grab`" version, a
sibling Linux/ddev project (a design doc for it exists at
`docs/superpowers/specs/2026-07-22-drupal-tutorial-video-design.md` in that
project). So the real sequence is: a working Linux (`xdotool` + `x11grab`)
Method B existed first in `drupal-tutorial-video` → it was ported to macOS
(`cliclick` + `avfoundation`) for `kanopi/screencast-skills` → this repo
forked back to Linux, built the Playwright-only Method A first, and later
restored a Linux-native Method B (`browser-scene-cursor.sh`) — a port from
`drupal-tutorial-video`'s working implementation, not a from-scratch design,
same as `browser-scene.mjs`/`finish-scene.sh`/`concat.sh` before it. See
"Cursor capture" below for what carried over unchanged and what didn't (this
repo has no ddev container, so the container-exec boundary and its
workarounds are gone; `browser.sh`/`browser.mjs`'s persistent-CDP-session
design replaces `drupal-tutorial-video`'s `agent-browser` CLI).

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

## Cursor capture (Method B, built 2026-08-10)

A real, visibly-clicking cursor, on Linux, without native Wayland support:
`browser-scene-cursor.sh` (+ `browser-scene-cursor.mjs`, `hands.sh`,
`xvfb.sh`). Opt-in, extra host deps (`xdotool`+`Xvfb`), same `spec.json`
format as Method A. See `references/browser-playwright.md` for usage and
trade-offs; this section is the design record.

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
  compositor to grant consent to. `xvfb.sh` owns start/stop/status; it's
  idempotent (matches `pgrep -f "Xvfb $XVFB_DISPLAY "`, so a second `start`
  from a later scene is a no-op) and never touched by Method A.
- **A restore, not a fresh build, same as the lineage note above says.**
  `drupal-tutorial-video`'s working `xdotool`/`x11grab` implementation is the
  actual reference this was ported from. What carried over unchanged: the
  cursor-interpolation `move()` loop in `hands.sh`, the `click`/`type`/`key`
  vocabulary, and x11grab's `-video_size WxH -i $DISPLAY+X,Y` for the
  crop-on-capture (simpler than avfoundation's capture-then-crop). What
  changed, because this repo has no ddev container to cross: `hands.sh` lost
  its `ddev exec` wrapper and its `type64`
  base64-encoding workaround (that existed only to survive shell-metacharacter
  mangling across the `ddev exec bash -lc "..."` hop; `browser-scene-cursor.mjs`
  calls `hands.sh` via `execFileSync`, argv passed directly, no shell in
  between, nothing to mangle). What's structurally new: `drupal-tutorial-video`
  drove the browser with `agent-browser` (an external npm CLI) inside the
  container; this repo drives it with `browser.sh`/`browser.mjs`'s own
  persistent-CDP-session design (`start` once, reused across scenes, see
  below), since that "brain" already existed here and Method A already
  depends on it.
- **Playwright locators avoid the precursor's raw-coordinate bugs, kept for
  Method B too.** Off-viewport clicks silently no-op'ing, zero-size/hidden
  elements parking the cursor at 0,0, DOM-order-vs-visual-order confusion for
  same-named buttons, and kiosk-coordinate calibration drift were all real,
  documented failures in `drupal-tutorial-video`'s raw-coordinate approach.
  Method B still locates every target with a Playwright `boundingBox()` (same
  precondition Method A uses), it only adds a real `xdotool` click/type on
  top of that instead of a synthetic Playwright one — the element-finding
  logic that avoided those bugs is unchanged, only the "hands" and "capture"
  layers are new.
- **Kiosk mode is what makes the coordinate math work, not a cosmetic
  choice.** `browser.sh start` takes `TUT_KIOSK=1` (off by default, since
  `browser.sh` is also meant for interactive use where a normal omnibox
  helps) to add `--kiosk`, stripping all browser chrome so the Playwright
  viewport starts at exactly the window's origin. Screen coordinate =
  `WIN_X/Y + viewport offset`, no chrome-height calibration guess — the
  exact calibration problem the original (pre-Method-B)
  `browser.sh`/`browser.mjs` comments flagged as unsolved. The trade-off:
  kiosk fullscreens to the `Xvfb` screen's own size, so this only holds when
  the window already covers the whole virtual screen (true at the `TUT_RES`
  default with `WIN_*` unset) — customizing
  `WIN_X`/`WIN_Y`/`WIN_W`/`WIN_H` independently of `TUT_RES` breaks the
  coordinate math for this engine specifically.
- **Session persists across scenes, teardown is explicit.** `xvfb.sh start`
  and `browser.sh start` are idempotent (checked via a `curl` probe of the
  CDP port before relaunching), so consecutive `browser-scene-cursor.sh`
  calls in one recording session reuse the same kiosk Chromium and its
  `chrome-profile/` (logins persist). `browser-scene-cursor.sh stop` tears
  both down; nothing does this automatically, matching this skill's
  never-clean-up-before-the-user-is-done rule.
- **Capture is two-pass.** `ffmpeg -f x11grab -preset ultrafast` writes a raw
  temp file live (fast enough not to drop frames during real-time capture),
  then a second `-preset medium` pass scales/pads/fps-normalizes it into
  `scenes/NN.mp4` in the exact format every other engine produces, so
  `finish-scene.sh`/`concat.sh` see a consistent input regardless of which
  engine made a given scene.

## Known security trade-offs

Recorded 2026-08-10 from a design discussion, not fixed here. Read before
extending Method B or the installer scripts.

- **The `Xvfb` display (Method B) has no authentication.** `xvfb.sh` starts
  it with `-ac` (X11 access control off) and `-nolisten tcp` (no network
  access) — closed to the network, but open to anything else running as your
  own user account. Any local process that points `DISPLAY=$XVFB_DISPLAY`
  (`:99` by default, predictable) at it can read the framebuffer or inject
  its own mouse/keyboard input, no permission prompt, no consent dialog.
  This is the same weakness X11 has always had (see Marcus's own rationale
  for using it, quoted in the lineage discussion this section came from: a
  real Wayland compositor withholds framebuffer access specifically to
  prevent this), just relocated from your real desktop to this virtual one.
  The blast radius is smaller — only this recording, not your whole session
  — not zero. Don't read "it's an isolated display" as "nothing on it can be
  exposed."
- **Isolation from other apps is not the same as content safety.** Nothing
  but this pipeline's own scripted actions ever renders on the `Xvfb`
  display, so other real content (email, chat, other browser tabs) can't
  leak onto it. But whatever a scene's spec navigates to and types on that
  display is exactly as exposed as any other browser session —
  `chrome-profile/` persists real logins across scenes by design (see
  "Session persists across scenes" above). The "never type a real password
  on camera" rule (`references/browser-playwright.md`'s Gotchas) is the
  actual safeguard here, the display's isolation doesn't substitute for it.
- **No container/process boundary, unlike the `drupal-tutorial-video`
  precursor.** Marcus's original ran the equivalent of `Xvfb`/`xdotool`/
  Chromium inside a ddev (Docker) container — if anything on that display
  were ever compromised (a malicious page achieving a Chromium sandbox
  escape, for instance, rare but real), the blast radius stopped at the
  container. This port runs them directly under the host user's own
  account instead, trading that isolation for not requiring Docker/ddev as
  a dependency (a much heavier ask for this repo's actual audience than
  `sudo apt install xdotool xvfb`, see README.md's Prerequisites framing).
  Considered trade, not an oversight — but a host-level compromise of
  anything on that display isn't contained the way it was in the original.
  Note also that Docker itself isn't a security freebie to fall back on
  either: its daemon typically runs as root, and `docker` group membership
  is a well-known path to host root by default. A lighter-weight sandbox
  (`bubblewrap`/`firejail`) around just the Method B process trio would
  recover some of the original's isolation without reintroducing a full
  Docker dependency; not built, evaluate if this ever needs hardening.
- **Two of the four opt-in installer scripts don't verify what they
  download.** `scripts/install-node.sh` checksums its download against
  nodejs.org's own `SHASUMS256.txt`, and `npm install`/Playwright's Chromium
  download go through npm's own lockfile integrity checks — both fine.
  `scripts/install-vhs.sh` does neither: it fetches whatever GitHub
  currently reports as "latest release" for `charmbracelet/vhs` and
  `tsl0922/ttyd` over HTTPS with no checksum or signature check, and
  re-running it tracks "latest" rather than a pinned version, so it isn't
  even reproducible. `scripts/install-piper.sh`'s voice-model download
  (`.onnx`/`.onnx.json` from Hugging Face) has the same gap. None of this
  needs `sudo`, which limits it to the invoking user's own privileges, not
  system-wide — but "no sudo" was never the actual trust boundary; a
  compromised binary already has everything your user account has (SSH
  keys, browser cookies, etc.) without needing root. Worth pinning +
  checksumming `install-vhs.sh` if either upstream repo publishes release
  checksums; not done here, known gap, not a verified-safe state.

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
