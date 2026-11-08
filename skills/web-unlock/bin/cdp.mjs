#!/usr/bin/env node
// web-unlock: drive the automation Chrome started by chrome-real.sh through Playwright's connectOverCDP.
// Two fixes that matter in practice: close tabs with no URL first (they hang Target.setAutoAttach), and a 90 s
// connect timeout (the 30 s default runs out). Output is always short; HTML goes to a file.
// Usage: cdp.mjs <url> [--title] [--text] [--html <file>] [--eval "<js>"] [--wait <ms>] [--port 9223] [--keep]
// Needs Node 22+ and playwright-core (or playwright) installed locally, globally, or at $PLAYWRIGHT_CORE_PATH.
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { execSync } from 'node:child_process';

const a = process.argv.slice(2);
if (a.includes('-h') || a.includes('--help')) {
  console.log('usage: cdp.mjs <url> [--title] [--text] [--html <file>] [--eval "<js>"] [--wait <ms>] [--port 9223] [--keep]');
  process.exit(0);
}
const valueFlags = new Set(['--html', '--eval', '--wait', '--port']);
let url = null;
for (let i = 0; i < a.length; i++) {
  if (valueFlags.has(a[i])) { i++; continue; }
  if (!a[i].startsWith('--')) { url = a[i]; break; }
}
const opt = k => { const i = a.indexOf(k); return i >= 0 ? a[i + 1] : null; };
const port = opt('--port') || process.env.CHROME_REAL_PORT || '9223';
const wait = Number(opt('--wait') || 1500);
if (!url) { console.error('usage: cdp.mjs <url> [--title|--text|--html f|--eval js]'); process.exit(2); }

function loadPlaywright() {
  const bases = [];
  if (process.env.PLAYWRIGHT_CORE_PATH) bases.push(process.env.PLAYWRIGHT_CORE_PATH);
  bases.push(path.join(process.cwd(), 'noop.js'), import.meta.url);
  try {
    const g = execSync('npm root -g', { stdio: ['ignore', 'pipe', 'ignore'], timeout: 10000 }).toString().trim();
    if (g) bases.push(path.join(g, 'noop.js'), path.join(g, '@playwright', 'cli', 'node_modules', 'noop.js'), path.join(g, 'playwright', 'node_modules', 'noop.js'));
  } catch { /* npm missing: try the other places */ }
  for (const base of bases) {
    const req = createRequire(base.endsWith('/') ? base + 'noop.js' : base);
    for (const name of ['playwright-core', 'playwright']) {
      try { const m = req(name); if (m.chromium) return m.chromium; } catch { /* next */ }
    }
  }
  return null;
}
const chromium = loadPlaywright();
if (!chromium) {
  console.error('playwright-core not found. Install it (npm i -g playwright-core) or set PLAYWRIGHT_CORE_PATH to a folder that contains node_modules/playwright-core.');
  process.exit(3);
}

// 1) close targets with no URL (they make connectOverCDP hang)
try {
  const list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
  for (const t of list) if (t.type === 'page' && (!t.url || t.url === 'about:blank') && list.length > 1) await fetch(`http://127.0.0.1:${port}/json/close/${t.id}`).catch(() => {});
} catch (e) { console.error(`CDP is not answering on port ${port}: ${e.message}. Run chrome-real.sh start`); process.exit(4); }

// 2) a new tab IN THE BACKGROUND (Target.createTarget background:true). ctx.newPage() would bring Chrome to the front.
const tag = `cdpmjs-${process.pid}-${Date.now()}`;
const bgTarget = async () => {
  const v = await (await fetch(`http://127.0.0.1:${port}/json/version`)).json();
  return new Promise((ok, ko) => {
    const ws = new WebSocket(v.webSocketDebuggerUrl);
    const t = setTimeout(() => { ws.close(); ko(new Error('timeout createTarget')); }, 15000);
    ws.onopen = () => ws.send(JSON.stringify({ id: 1, method: 'Target.createTarget', params: { url: `about:blank#${tag}`, background: true } }));
    ws.onmessage = e => { const m = JSON.parse(e.data); if (m.id === 1) { clearTimeout(t); ws.close(); m.error ? ko(new Error(m.error.message)) : ok(m.result.targetId); } };
    ws.onerror = e => { clearTimeout(t); ko(new Error('ws: ' + (e.message || e))); };
  });
};
await bgTarget();

const browser = await chromium.connectOverCDP({ endpointURL: `http://127.0.0.1:${port}`, timeout: 90000 });
try {
  const ctx = browser.contexts()[0];
  let page = null;
  for (let i = 0; i < 20 && !page; i++) { page = ctx.pages().find(p => p.url().includes(tag)) || null; if (!page) await new Promise(r => setTimeout(r, 250)); }
  if (!page) throw new Error('the background tab did not show up in the context');
  await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 });
  await page.waitForTimeout(wait);
  const title = await page.title();
  const out = { url: page.url(), title };
  if (a.includes('--text')) out.text = (await page.evaluate(() => document.body?.innerText || '')).slice(0, 20000);
  if (opt('--html')) { fs.writeFileSync(opt('--html'), await page.content()); out.html = opt('--html'); }
  if (opt('--eval')) out.eval = await page.evaluate(opt('--eval'));
  if (/Just a moment|Attention Required|Access Denied/i.test(title)) out.blocked = true;
  console.log(JSON.stringify(out, null, a.includes('--text') ? 0 : 1));
  if (!a.includes('--keep')) await page.close();
} finally { await browser.close().catch(() => {}); }
