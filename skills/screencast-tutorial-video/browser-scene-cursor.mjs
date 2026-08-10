// Method B browser engine step driver: drives an already-running, on-screen
// kiosk Chromium (browser.sh start, TUT_KIOSK=1, on the Xvfb display) over
// CDP. Steps that a real person would physically do - click, type, hover -
// move an actual cursor via hands.sh (xdotool); ffmpeg x11grab
// (browser-scene-cursor.sh, started/stopped around this script) is what
// actually records the screen, this script never touches video encoding.
// Steps with no physical component (scroll, highlight, wait, navigate) reuse
// the same page.evaluate() approach as Method A (browser-scene.mjs) - there's
// nothing for a cursor to do there either way, and it's one less thing to
// keep in sync between the two engines.
//
// Usage: node browser-scene-cursor.mjs <spec.json>
// Spec format: identical to Method A, see browser-scene.mjs and
// references/browser-playwright.md - the whole point is a spec can run under
// either engine unchanged. `typeJs` is accepted as a plain alias of `type`
// here: Method A only has two typing step kinds because Playwright's
// synthetic keystrokes can get swallowed by a live-rerendering field (a
// stale locator handle); xdotool types into whatever has real OS keyboard
// focus, which isn't tied to a locator handle, so that failure mode doesn't
// apply and there's nothing for a second step kind to work around.
// Env: HDIR, HANDS (path to hands.sh), WIN_X, WIN_Y, TUT_CDP_PORT.

import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const { chromium } = require('playwright'); // ESM import ignores NODE_PATH; require honors it

const [specArg] = process.argv.slice(2);
const CDP_PORT = process.env.TUT_CDP_PORT || '9222';
const CDP_URL = `http://127.0.0.1:${CDP_PORT}`;
const WIN_X = +(process.env.WIN_X || 0);
const WIN_Y = +(process.env.WIN_Y || 0);
const HANDS = process.env.HANDS || `${new URL('.', import.meta.url).pathname}hands.sh`;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function fail(msg) {
  console.error(`error: ${msg}`);
  process.exit(1);
}

if (!specArg) fail('usage: browser-scene-cursor.mjs <spec.json>');
const spec = JSON.parse(readFileSync(specArg, 'utf8'));

// Real, on-screen xdotool action. stdio 'inherit' so hands.sh's own errors
// (e.g. "xdotool not installed") surface directly instead of being swallowed.
function hand(args, envOverrides) {
  execFileSync(HANDS, args, { stdio: 'inherit', env: { ...process.env, ...envOverrides } });
}

// Playwright key names (page.keyboard.press style, also used by this spec
// format's {"press": ...} step) don't all match X keysym names xdotool
// expects. Covers the common ones; anything else passes through unchanged
// (most single-character and already-X-keysym-shaped names match as-is).
const XDOTOOL_KEY = {
  Enter: 'Return', Escape: 'Escape', Tab: 'Tab', Backspace: 'BackSpace',
  Delete: 'Delete', Space: 'space',
  ArrowUp: 'Up', ArrowDown: 'Down', ArrowLeft: 'Left', ArrowRight: 'Right',
};
function xdotoolKey(k) { return XDOTOOL_KEY[k] || k; }

const HL = '__tut_hl__';
async function highlight(locator) {
  const el = locator.first();
  if (!(await el.count())) return;
  await el.evaluate((node, cls) => {
    node.classList.add(cls);
    node.style.outline = '4px solid #f5c518';
    node.style.outlineOffset = '4px';
    node.style.borderRadius = '4px';
    node.scrollIntoView({ behavior: 'smooth', block: 'center' });
  }, HL).catch(() => {});
}
async function clearHighlights(page) {
  await page.evaluate((cls) => {
    document.querySelectorAll('.' + cls).forEach((n) => {
      n.style.outline = ''; n.style.outlineOffset = ''; n.classList.remove(cls);
    });
  }, HL).catch(() => {});
}
async function smoothScrollTo(page, targetY, overMs) {
  await page.evaluate(async ({ targetY, overMs }) => {
    const startY = window.scrollY;
    const dist = targetY - startY;
    const start = performance.now();
    await new Promise((resolve) => {
      function frame(now) {
        const t = Math.min(1, (now - start) / overMs);
        const ease = t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2; // easeInOutQuad
        window.scrollTo(0, startY + dist * ease);
        if (t < 1) requestAnimationFrame(frame); else resolve();
      }
      requestAnimationFrame(frame);
    });
  }, { targetY, overMs });
}
async function settle(page) {
  await page.evaluate(() => (document.fonts && document.fonts.ready) ? document.fonts.ready : Promise.resolve()).catch(() => {});
  await page.waitForTimeout(700);
}

// Element's real screen coordinates: viewport box + window origin. Kiosk mode
// (TUT_KIOSK=1 on browser.sh start) plus --force-device-scale-factor=1 means
// the viewport starts at exactly (WIN_X, WIN_Y) with no browser chrome and no
// DPI scaling to account for - the calibration offset the old browser.sh
// comment warned a "hands" tool would need, which kiosk mode sidesteps
// instead of computing.
async function screenCenter(locator) {
  const el = locator.first();
  await el.waitFor({ state: 'visible', timeout: 30000 });
  const b = await el.boundingBox();
  if (!b) throw new Error('no bounding box');
  return [Math.round(WIN_X + b.x + b.width / 2), Math.round(WIN_Y + b.y + b.height / 2)];
}

// Clicks in, then real select-all + delete before typing - same "always
// clear first" rule as Method A (a field can already hold a value), done
// with real keystrokes here instead of a JS value reset so every step in
// this engine stays on the same "actually happened on screen" footing.
async function clickAndClear(x, y) {
  hand(['click', String(x), String(y)]);
  hand(['key', 'ctrl+a']);
  hand(['key', 'BackSpace']);
}

const browser = await chromium.connectOverCDP(CDP_URL).catch(() =>
  fail('no browser session (run: TUT_KIOSK=1 browser.sh start <url>, or use browser-scene-cursor.sh which does this for you)'));
const ctx = browser.contexts()[0];
if (!ctx) fail('no browser context');
const page = ctx.pages()[0] || (await ctx.newPage());

// 'load', not 'networkidle': see browser-scene.mjs for why. Every scene
// navigates itself at the start, same as Method A, so a scene is
// independently re-renderable regardless of what the persisted session was
// last showing.
await page.goto(spec.url, { waitUntil: 'load', timeout: 30000 }).catch(() => {});
await settle(page);

for (const step of spec.steps || []) {
  try {
    if (step.waitMs) await sleep(step.waitMs);
    else if (step.goto) {
      await page.goto(step.goto, { waitUntil: 'load', timeout: 30000 });
      await settle(page);
    } else if (step.click) {
      const [x, y] = await screenCenter(page.locator(step.click));
      hand(['click', String(x), String(y)]);
    } else if (step.type || step.typeJs) {
      const { selector, text, delayMs } = step.type || step.typeJs;
      const [x, y] = await screenCenter(page.locator(selector));
      await clickAndClear(x, y);
      hand(['type', text], delayMs ? { TUT_HAND_TYPE_DELAY: String(delayMs) } : undefined);
    } else if (step.submit) {
      // Native form submission; requestSubmit fires the submit event so JS
      // handlers run. No cursor step: whatever visibly triggers this (an
      // Enter press, a click on a submit button) is its own step already.
      await page.evaluate((sel) => {
        const f = document.querySelector(sel);
        if (f) (f.requestSubmit ? f.requestSubmit() : f.submit());
      }, step.submit);
      await page.waitForLoadState('load').catch(() => {});
      await settle(page);
    } else if (step.press) hand(['key', xdotoolKey(step.press)]);
    else if (step.highlightText) await highlight(page.locator(`text=${step.highlightText}`));
    else if (step.highlightSelector) await highlight(page.locator(step.highlightSelector));
    else if (step.clearHighlights) await clearHighlights(page);
    else if (step.scrollTop) await smoothScrollTo(page, 0, step.overMs || 800);
    else if (step.scrollToText) {
      const el = page.locator(`text=${step.scrollToText}`).first();
      await el.evaluate((n) => n.scrollIntoView({ behavior: 'smooth', block: 'center' }));
      await sleep(step.overMs || 1200);
    } else if (step.scrollBy) {
      const y = await page.evaluate(() => window.scrollY);
      await smoothScrollTo(page, y + step.scrollBy, step.overMs || 1500);
    } else if (step.scrollThrough) {
      const bottom = await page.evaluate(() => document.body.scrollHeight - window.innerHeight);
      await smoothScrollTo(page, Math.max(0, bottom), step.overMs || 8000);
    }
  } catch (e) {
    // Same resilience as Method A: one bad step logs and moves on rather than
    // losing an entire live x11grab capture to it.
    console.error(`step failed: ${JSON.stringify(step)}: ${e.message.split('\n')[0]}`);
  }
}

console.log(`browser-scene-cursor: ${spec.url} done`);
// connectOverCDP's close() disconnects this client only, it doesn't kill the
// persistent kiosk browser (see browser.mjs's other subcommands, same
// pattern) - but it does release the CDP websocket, without which Node's
// event loop never empties and this process hangs forever after the last
// log line, leaving the caller's `kill -INT $CAP_PID` unreached and ffmpeg
// capturing indefinitely.
await browser.close();
