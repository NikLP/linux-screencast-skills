# Browser scenes

A `browser-action` scene shows a web UI (claude.ai, a dashboard, a docs site).
**Method A** (Playwright, headless) is the default, use it unless a scene
specifically needs a real, visibly-moving cursor. **Method B** (real cursor,
`browser-scene-cursor.sh`) is the opt-in alternative, see the end of this
file. Both engines share the exact same `spec.json` format — write the spec
once, run it under either.

---

## Method A (recommended): Playwright records the page

`browser-scene.sh` drives Playwright and records the page **headless, off-screen,
at exactly 1920x1080**. No OS screen capture, no Screen-Recording permission, no
cursor calibration, no Retina scaling, and it records **only the page**, so
nothing else on your desktop can leak into frame. Text is crisp
(`deviceScaleFactor: 2`, supersampled to 1080p).

```bash
./browser-scene.sh 030 specs/030.json      # spec-driven (preferred)
./browser-scene.sh 030 "https://claude.ai" 8   # simple: load, gentle scroll, hold
```

### Scene spec (JSON)

```json
{ "url": "https://example.com", "steps": [
  {"waitMs": 2500},
  {"highlightText": "Human Review"},
  {"waitMs": 2000},
  {"clearHighlights": true},
  {"scrollThrough": true, "overMs": 16000},
  {"waitMs": 1500}
]}
```

Step kinds:

| Step | Effect |
|---|---|
| `{"waitMs": N}` | Hold N ms |
| `{"highlightText": "…"}` / `{"highlightSelector": "css"}` | Outline the first match (gold) and scroll it into center |
| `{"clearHighlights": true}` | Remove outlines |
| `{"scrollToText": "…", "overMs": N}` | Smooth-scroll an element into center |
| `{"scrollBy": px, "overMs": N}` | Smooth-scroll down by px |
| `{"scrollThrough": true, "overMs": N}` | Smooth-scroll top→bottom over N ms (adapts to page length; bigger N = slower) |
| `{"scrollTop": true, "overMs": N}` | Smooth-scroll back to top |

Interaction steps, for multi-page tours (click through a flow, run a search):

| Step | Effect |
|---|---|
| `{"goto": "url"}` | Navigate to a new URL mid-scene (waits for `load` + fonts) |
| `{"click": "locator"}` | Click the first match (Playwright locator: `text=…`, css, `role=…`) |
| `{"type": {"selector": "css", "text": "…", "delayMs": N}}` | Focus the field and type real keystrokes, one every N ms (default 60) |
| `{"typeJs": {"selector": "css", "text": "…", "delayMs": N}}` | Set the field's value character by character via JS `input` events |
| `{"press": "Enter"}` | Press a key on the focused element |
| `{"submit": "form css"}` | Submit the form natively (`requestSubmit`), then wait for the new page |

**`type` vs `typeJs`:** prefer `type` (real keystrokes). But a live-search UI
that re-renders its input mid-typing silently swallows real keystrokes (the
locator points at a detached node), if the typed text stops short in the
recording, switch to `typeJs`, which looks identical on camera.

**Both clear the field first, unconditionally.** A field can already hold a
value, a page default, state carried over from an earlier step in the same
spec, before the storyboard's own text arrives, and typing into that appends
rather than replaces (a search box that reads "foofoo" instead of "foo" is
this bug, not a typo in the spec). Clearing an already-empty field costs
nothing, so there is no flag to opt out of it. If a scene's point is
appending to existing text, write the step with the full final text (what the
field should read after both parts), not as two separate `type` steps.

**Page loads use `load`, not `networkidle`.** Apps that hold connections open
(Google Docs, websockets, analytics beacons) never reach networkidle, and the
whole timeout would be recorded as dead air. Budget post-load rendering with an
explicit `waitMs` after `goto`/`click`.

**Cosmetic blockers:** dismiss cookie banners and tooltips with a `click` step
before the tour starts (e.g. OneTrust: `{"click": "#onetrust-accept-btn-handler"}`,
preceded by a `waitMs` long enough for the banner to mount, it loads async).

### FOUT (flash of unstyled text)

Web fonts load a beat after first paint, so the very start of a recording can
flash unstyled. Method A waits for `document.fonts.ready` before running steps,
and the assembly trims the first ~1.5, 2s of each clip as a backstop. When you
size a scene, record long and trim: `ffmpeg -i raw.mp4 -ss 2.0 -t <need>` drops
the load-in and cuts to length. So a spec's total step time should be
`need + ~3s` of headroom.

### Highlights

Method A highlights an element by outlining it in-page (cleaner and more precise
than a cursor). There is no visible cursor in Method A, for a tour that is a
feature, not a gap.

---

## Locators

Playwright locator strings: `"text=New chat"`, `"#prompt"`,
`"role=button[name='Send']"`. Prefer visible text or roles over brittle CSS.

## Gotchas

- **Logins / secrets:** Method A launches a fresh, non-persistent browser
  context per scene, nothing carries over between calls. Method B's session
  does persist login state in `chrome-profile/` across scenes (see below) —
  log in once before recording there, or use a scene that needs no
  credentials. Either way, never type a real password on camera: whatever a
  scene navigates to and types is exactly as exposed as any other browser
  session, regardless of which engine recorded it.

---

## Method B: real cursor (`browser-scene-cursor.sh`)

A real, visibly-moving OS cursor: `xdotool` moves/clicks/types on a kiosk
Chromium running on a virtual `Xvfb` display, `ffmpeg -f x11grab` records the
screen live, cropped to the window region. Ported from
`drupal-tutorial-video`'s working `xdotool`/`x11grab` implementation (see the
repo root `CLAUDE.md`'s "Cursor capture" section for the full design and why
`Xvfb`, not native Wayland).

```bash
./browser-scene-cursor.sh 030 specs/030.json     # same spec.json as Method A
./browser-scene-cursor.sh stop                   # tear down when fully done
```

**Same spec format as Method A** (see above) — that's the point, a spec can
run under either engine unchanged, with two differences in how this engine
executes it:

- `click`, `type`, and `typeJs` become real, on-screen actions: a real cursor
  moves to the element (via Playwright's `boundingBox()`, not a hand-measured
  coordinate — this engine still uses Method A's precondition, it just adds a
  real click/type on top instead of a synthetic one), clicks, and — for
  `type`/`typeJs` — clears the field with a real `Ctrl+A`+`Backspace` before
  typing with real keystrokes. `typeJs` behaves identically to `type` here:
  Method A only needed two typing step kinds because Playwright's synthetic
  keystrokes can get swallowed by a live-rerendering field (a stale locator
  handle); `xdotool` types into whatever has real OS keyboard focus, which
  isn't tied to a locator handle, so that failure mode doesn't apply.
- Everything else (`scroll*`, `highlight*`, `waitMs`, `goto`, `press`,
  `submit`) runs exactly like Method A, no cursor involved either way.

**Extra host deps, checked but never installed:** `xdotool` + `Xvfb` (system
packages, like `ffmpeg`). `preflight.sh`'s Method B section reports these as
optional `WARN`s, never blocking; `browser-scene-cursor.sh` re-checks and
dies with the install command if you actually run it without them.

**Trade-offs vs Method A:**

- A little less crisp text: Method A supersamples at `deviceScaleFactor: 2`
  and downscales; Method B needs exact 1:1 pixel mapping (kiosk mode,
  `--force-device-scale-factor=1`) so a Playwright bounding box converts
  straight to an `xdotool` screen coordinate with no chrome-height
  calibration guess.
- Real click/type precision, not DOM precision: a real `Ctrl+A` in a
  non-text-input element (a contenteditable region that didn't actually
  focus, say) can select more than intended, the same way it would for an
  actual person. Method A's `fill()`/`typeJs` are DOM-exact regardless of
  what's focused.
- Session state persists across scenes: the kiosk Chromium and its
  `chrome-profile/` (so logins survive) stay up between
  `browser-scene-cursor.sh` calls for fast re-recording, unlike Method A's
  fresh headless browser per call. Log in once, `stop` only when fully done.
- **Don't customize `WIN_X`/`WIN_Y`/`WIN_W`/`WIN_H`** for this engine — kiosk
  mode fullscreens to the `Xvfb` screen's own size, which only matches the
  coordinate math when the window already covers the whole virtual screen
  (true at the `TUT_RES` default, WIN_* left unset). Method A's window
  geometry has no such constraint.
- **The `Xvfb` display has no authentication and no process isolation.**
  Method A's headless recording never opens a real display at all, so none of
  this applies to it. Method B's `xvfb.sh` starts `Xvfb` with `-ac` (X11
  access control off), so any other process running as your own user account
  can point `DISPLAY=$XVFB_DISPLAY` at it and read the framebuffer or inject
  its own input, no prompt. And unlike `drupal-tutorial-video` (this engine's
  reference), which ran the equivalent of `Xvfb`+`xdotool`+Chromium inside a
  disposable ddev/Docker container, this port runs them directly on the host
  — a deliberate trade for not requiring Docker as a dependency, not an
  oversight, but it means nothing here contains a compromise of that
  Chromium process the way a container would. See CLAUDE.md's "Known
  security trade-offs" section for the full reasoning.
