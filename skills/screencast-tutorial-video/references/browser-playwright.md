# Browser scenes

A `browser-action` scene shows a web UI (claude.ai, a dashboard, a docs site).
**Method A** (Playwright, headless) is the only engine wired up in this fork,
use it for everything. See the end of this file if you're building a
real-cursor "Method B".

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

- **Logins / secrets:** log in before recording (profile persists in
  `chrome-profile/`), or use a scene that needs no credentials. Never type a real
  password on camera.

---

## Real-cursor capture ("Method B"), not implemented

Upstream's macOS-only real-cursor engine (`cliclick` + `avfoundation`) was
never ported here, and its macOS-specific files (`hands.sh`,
`record-browser.sh`, `browser-scene-screencap.{sh,mjs}`,
`references/capture-macos.md`) have been removed. What survives:
`browser.sh`/`browser.mjs`, the Playwright "brain" that launches a headed
Chromium at a fixed position/size and returns an element's on-screen box
(`browser.sh box "text=New chat"`, `browser.sh snapshot` to dump the a11y
tree) without doing any visible clicking itself, already OS-agnostic.

A Linux port needs new "hands" (move/click/type, e.g. `xdotool`) and
"capture" (e.g. `ffmpeg -f x11grab`, cropped to the browser window region)
scripts in place of the deleted macOS ones. See the repo root `CLAUDE.md`'s
"Cursor capture" section for the full plan, it's a restore from
`drupal-tutorial-video`'s existing `xdotool`/`x11grab` implementation, not a
from-scratch design.
