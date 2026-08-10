# Storyboard schema

The `storyboard.md` this skill writes is the contract `screencast-tutorial-video`
consumes. Write it as readable Markdown with one section per scene, in order.

## File header

```markdown
# Storyboard: <human title>

- Slug: <kebab-slug>
- Target resolution: 1920x1080
- Voice: <to be chosen at production, or a note>
- Goal: <one sentence>
```

## One section per scene

Number scenes from `010`, in steps of 10 (`010`, `020`, `030`, ...), 3-digit
zero-padded. Reorder requests arrive after scenes are already recorded, and a
plain `020` between `010` and `030` costs nothing to insert later; renumbering
everything after the fact does not. Use a heading and a labeled list so both a
human and the production skill can read it:

```markdown
## Scene 010, <short title>

- type: intro | terminal | desktop-still | browser-action | command-card | outro
- actions: <the single action that happens on screen>
- narration: <what describes that one action; a sentence or a short
  paragraph, following narration-style.md>
- caption: <one short line, or empty for no caption bar>
- pacing: <approx seconds, and any timing notes>
```

### One action per scene (hard rule)

A scene is the atomic recorded unit: **one action.** This is not a style
preference, it is what keeps the picture and the voice-over in sync.
`screencast-tutorial-video` records a scene as a single clip and pads *that
whole clip* to fit its narration; that only keeps things in sync if there is
one visual event to anchor to. If a scene bundles a second action behind
more narration, there is nothing keeping the video's second action aligned
with where the narration gets to describing it, only the total duration
matches at the end. A multi-step admin flow (a predecessor project learned
this the hard way) is several scenes, numbered in sequence, each with its own
action, not one scene with a long `actions` list.

The narration itself can run to a short paragraph, several sentences are
fine, as long as every sentence is still describing that same one action (the
click, the command, the screen). The moment a sentence starts describing the
*next* action, split the scene.

### Field notes

- **type**, picks the recording engine downstream:
  - `intro` / `outro`, usually a still or a short browser/terminal shot.
  - `terminal`, a CLI command. Put the **exact command** in `actions` (it
    becomes a VHS `.tape`). Real commands only.
  - `desktop-still`, a native-app screen (e.g. Claude Desktop → Settings →
    MCP). Name the screen and what to zoom/highlight; production animates a PNG.
  - `browser-action`, a real step in a web UI. Name the URL, the element to
    click, and any text to type. Production locates the element and, by
    default, highlights it in-page; note here if the scene specifically
    needs a real, visibly-moving cursor instead (production's opt-in engine
    for that).
  - `command-card`, a single command shown as a still card. Put the exact
    command in `actions`.
- **actions**, the single concrete action for this scene (a `browser-action`
  scene's `goto`/`click`/`type` sequence that has no visible narration beat in
  between still counts as one action). For `terminal`/`command-card` include
  the literal command. For `browser-action` include the URL and a selector or
  visible label for the target. For `desktop-still` name the exact screen.
- **narration**, describes this scene's one action; a sentence or a short
  paragraph, or empty. Follow `references/narration-style.md`.
- **caption**, one short line for the bottom bar, or empty.
- **pacing**, rough seconds; note if a step needs to linger.

## Accuracy markers

If a real value is not yet known, write `[NEEDS: <what, from where>]` in place of
the invented value rather than guessing. Example:

```markdown
- actions: paste the MCP config into claude_desktop_config.json:
  [NEEDS: real mcpServers block from the server's README]
```

The production skill treats a `[NEEDS: ...]` marker as a blocker and will ask
for the real value before recording that scene.

## Example scene

```markdown
## Scene 020, Add the MCP server

- type: terminal
- actions: run `claude mcp add github -- npx -y @modelcontextprotocol/server-github`
- narration: Add the server with claude m c p add. Give it a name and the command that starts it.
- caption: Add the MCP server
- pacing: ~7s; let the success line show for a beat
```
