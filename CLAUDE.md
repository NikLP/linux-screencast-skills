# Claude Context for linux-screencast-skills

Two skills that produce narrated screencast tutorials of real AI tooling:
`screencast-storyboard` (read real docs -> approved storyboard) and
`screencast-tutorial-video` (record scenes -> captioned, voice-over MP4).
Linux host, any distro/desktop. `README.md` is the user-facing doc (quickstart,
requirements, fork differences); this file is for working on the code.

## Lineage

`drupal-tutorial-video` (Linux, `xdotool`/`x11grab`, ddev) -> ported to macOS
(`cliclick`/`avfoundation`) as `kanopi/screencast-skills` -> forked back to
Linux here. The macOS-only files (`record-browser.sh`,
`browser-scene-screencap.{sh,mjs}`, `references/capture-macos.md`) were removed.
`browser.sh`/`browser.mjs` (the Playwright "brain" that locates elements) was
kept and is the shared base of both browser engines:

- **Method A**, `browser-scene.sh`: headless, no cursor, the default.
- **Method B**, `browser-scene-cursor.sh` + `hands.sh` + `xvfb.sh` (built
  2026-08-10): real cursor via `xdotool`/`x11grab`. A port of
  `drupal-tutorial-video`'s working implementation, not a fresh design, minus
  the ddev container boundary and its workarounds. See "Cursor capture".

`finish-scene.sh`, `concat.sh` and `browser-scene.mjs` trace back to
`drupal-tutorial-video` the same way.

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

**Dependencies are repo-local where possible.** `vhs`/`ttyd` in `.bin/`,
Node/npm in `.node/`, Piper in `.piper/`, Playwright in `node_modules/`, all via
opt-in `scripts/install-*.sh` the user runs. `ffmpeg`, `jq`, `xdotool`, `Xvfb`
are system packages; Chromium is in Playwright's own cache. `preflight.sh` only
checks, never installs. The full table is in `README.md` (Requirements); keep it
in sync with `preflight.sh` when a dependency changes.

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

**ElevenLabs (`awaz`) is opt-in via `TUT_TTS=elevenlabs`**, not the default
(OpenAI/Piper are), but it is a real code path, not dead code. Note that
`narrate.sh` auto-picks ElevenLabs first if `ELEVENLABS_API_KEY` is set, then
OpenAI, then Piper. `awaz`'s CLI changed (now `awaz "text" -v <voice> -o <file>`,
no `speak` subcommand); `narrate.sh` was updated 2026-08-09 against the GitHub
README only, not a live run. Re-check `awaz --help` before trusting it.

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
  This is the same weakness X11 has always had (a real Wayland compositor withholds framebuffer access specifically to
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
  precursor.** The original ran the equivalent of `Xvfb`/`xdotool`/
  Chromium inside a ddev (Docker) container — if anything on that display
  were ever compromised (a malicious page achieving a Chromium sandbox
  escape, for instance, rare but real), the blast radius stopped at the
  container. This port runs them directly under the host user's own
  account instead, trading that isolation for not requiring Docker/ddev as
  a dependency (a much heavier ask for this repo's actual audience than
  `sudo apt install xdotool xvfb`, see README.md's Requirements section).
  Considered trade, not an oversight — but a host-level compromise of
  anything on that display isn't contained the way it was in the original.
  Note also that Docker itself isn't a security freebie to fall back on
  either: its daemon typically runs as root, and `docker` group membership
  is a well-known path to host root by default. A lighter-weight sandbox
  (`bubblewrap`/`firejail`) around just the Method B process trio would
  recover some of the original's isolation without reintroducing a full
  Docker dependency; not built, evaluate if this ever needs hardening.
- **Two of the four opt-in installer scripts don't verify downloads.**
  `install-node.sh` checks nodejs.org's `SHASUMS256.txt`; `npm install` and
  Playwright use lockfile integrity. `install-vhs.sh` fetches GitHub's "latest"
  `charmbracelet/vhs` and `tsl0922/ttyd` with no checksum (not reproducible),
  and `install-piper.sh`'s Hugging Face voice download is the same. No `sudo`,
  but "no sudo" was never the trust boundary: a bad binary already has your
  user's SSH keys and cookies. Pin and checksum `install-vhs.sh` if upstream
  publishes checksums. Known gap, not fixed.

## Method B: lessons from a real recording session (2026-08-10)

Recorded producing a 6-scene Drupal admin tutorial end to end
(`annotations-editorial-recipe` in a separate project). All four items below
were real, observed failures, not theoretical — each cost a re-record before
the cause was found.

- **"Pre cruft": the first beat of every clip can show the *previous* scene's
  page, not this scene's.** `browser-scene-cursor.sh` starts `x11grab`
  capturing immediately, then `browser-scene-cursor.mjs` still has to boot
  Node, `require('playwright')`, and `connectOverCDP` before it ever calls
  `page.goto(spec.url)` — a real, observed 1-2s gap during which whatever the
  persistent kiosk session was last showing (the prior scene's end state, or
  leftover manual `browser.sh open`/`box` testing) is what's on screen and
  gets recorded. It reads as a jarring flash to the wrong page, not a
  cosmetic FOUT (Method A's font-ready wait doesn't apply here; this is a
  real prior page, not unstyled markup). **Workaround, not a script fix:**
  before invoking `browser-scene-cursor.sh <NN> <spec>`, first run
  `DISPLAY=$XVFB_DISPLAY browser.sh open '<the spec's own url>'` and a short
  `sleep 1`. This makes the stale content already *correct* for the scene
  about to record, so `browser-scene-cursor.mjs`'s own `goto` becomes a
  harmless same-page reload instead of a visible wrong-content flash. Doing
  this by hand before every single scene is real, repeated overhead; the
  actual fix belongs in `browser-scene-cursor.sh` itself (pre-navigate to
  `spec.url` — or at minimum `about:blank` — right after confirming/starting
  the session and before starting `x11grab`), not yet done here.
- **`role=link[name="..."]` can silently match zero elements even when the
  text is right there and `text=`/a CSS selector finds it instantly.**
  Hit on a Drupal local-action button ("+ Add annotation type", Gin theme):
  `role=link[name="Add annotation type"]` timed out after the full 30s
  (`locator.waitFor` gives no hint *why* it found nothing), while
  `text=Add annotation type` and `a.button--action` both resolved
  immediately. Cause: the element likely carries an explicit `role="button"`
  that overrides its implicit `<a>` link role, so Playwright's role engine
  (correctly, per ARIA) excludes it from `role=link` queries. The lesson
  isn't "avoid role= locators", it's: **a 30s role= timeout with plausible-
  looking text is not proof the text is wrong** — verify the actual
  candidate locator against the live, already-authenticated session with
  `DISPLAY=$XVFB_DISPLAY browser.sh box '<locator>'` (returns center
  coordinates on a hit, throws the same `waitFor` timeout on a miss) *before*
  writing it into a spec and burning a full recording pass on it. This
  verify-live step is what actually caught every locator issue below too.
- **`#edit-submit` is not reliably the visible primary action on Drupal
  content-entity forms with Gin's revision sidebar.** Worked fine on plain
  `ConfigFormBase`/`EntityForm` admin forms (target-type toggles, field
  scoping), but on a `ContentEntityForm` with Gin's moderation sidebar
  active, `#edit-submit` resolved to a near-zero-size element in the
  top-left corner, not the actual green "Save" button Gin renders top-right
  — `role=button[name="Save"]` hit the real one. Root cause not fully
  chased (likely a visually-hidden/relocated duplicate for Gin's responsive
  sticky-actions layout), but the practical rule: **don't assume `#edit-
  submit` is the right target on a revisionable content-entity form; verify
  with `browser.sh box` and cross-check against an actual screenshot**
  (`page.screenshot()` over the CDP connection, or `still-scene.sh`-style
  capture) before trusting the coordinates, same as the point above.
- **`xdotool type`/`key` (Method B's real-keystroke path) hard-fails on
  multi-byte UTF-8 it can't encode as an X11 keysym sequence** — an em dash
  (`—`) produced `Invalid multi-byte sequence encountered` /
  `xdo_enter_text_window reported an error` and aborted mid-string, having
  already typed everything up to that character. `typeJs` is **not** a
  workaround for this on Method B: per the header comment in
  `browser-scene-cursor.mjs`, it's accepted as a plain alias of `type` here
  (unlike Method A, where the two kinds exist for a different reason —
  stale-locator swallowing on a live-rerendering field — Method B types into
  real OS keyboard focus, so that failure mode doesn't apply and there was
  never a second, JS-based typing path to fall back to). **Consequence worse
  than the failed keystrokes alone:** per-step failures are caught and
  logged (`step failed: ...`) but execution *continues to the next step* —
  if a `click` on a Save/Submit button follows the failed `type` in the same
  spec, it still fires, silently persisting the truncated text as if it were
  complete. Always verify saved state after any `type` step with non-ASCII
  punctuation (read it back from wherever the tool under test stores it, not
  just "the step didn't error"), and prefer plain ASCII punctuation (a comma
  instead of an em dash, `--` instead of `—`) in typed text for Method B
  scenes to avoid the failure entirely.

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
- **`browser-scene-cursor.sh` should pre-navigate before `x11grab` starts.**
  Would close the "pre cruft" gap documented above at the source instead of
  requiring every caller to manually `browser.sh open <url>` + `sleep 1`
  before each `browser-scene-cursor.sh` call. Concretely: move (or add) a
  `page.goto(spec.url)` in `browser-scene-cursor.mjs` — or the simpler
  `browser.sh open about:blank` — to run *before* `browser-scene-cursor.sh`
  backgrounds the `ffmpeg -f x11grab` capture, not after. Proposed
  2026-08-10 from a real recording session, not implemented.

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
3. Add a `CHANGELOG.md` entry (the file doesn't exist yet; create it).
4. Run `./scripts/validate-frontmatter.sh` and `./scripts/check-codex-parity.sh`.
