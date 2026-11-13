---
name: web-unlock
description: >-
  Second step of web access, for when a normal fetch or search failed or was not enough. Use when a page comes back blocked or empty ("Just a moment", "Verify you are human", 403/429, captcha, authwall, a JavaScript shell, r.jina.ai "Warning - Target URL returned error"), when the target is a site that needs the user's login, when a host is already listed in sites.json, when a real Chrome must be driven, or before concluding "it does not exist" or publishing a price list or search-based table. Also when the user says "the site blocked it", "log into the account on X", "force the read", "use the real Chrome". Not the first step: plain page reads and searches start with the normal tools (WebFetch, WebSearch, curl).
version: "0.3.8"
metadata:
  author: Lucas Saldanha Werneck <lucas@2olhares.com>
  tags: [web, scraping, anti-bot, browser]
---

# web-unlock: what to do when the normal fetch does not get through

**First step of web access = your normal tools** (WebFetch, WebSearch, `curl -s URL -o file`, `oc open URL` from [only-cli](https://github.com/only-cli/oc) if installed, `r.jina.ai`,
`gh` for GitHub, `yt-dlp` for video captions). This skill starts when they return a block, an empty shell or
nothing, or when the target is a logged-in, Cloudflare or anti-bot site you already know about.

**Main rule:** classify the target -> pick its ladder -> stop at the first step that works -> **2 failures on
the same layer = move up a layer** -> record the result in `sites.json`.

The [web-unlock-guard](https://github.com/lucas-saldanha-werneck/web-unlock-guard) plugin, if installed,
enforces this with hooks: it denies the third identical try, default automation browsers and headless
browsers on Cloudflare sites, and `--remote-debugging-port` without `--user-data-dir`. If it denies a call,
follow its message; it names the next layer.

Paths below are relative to this skill's base directory (the folder that holds this SKILL.md): `bin/`,
`lib/detect.mjs`, `sites.json`, `references/`. Every key and every external tool is optional; each script says
what it skipped.

## Purpose
Get through a page or search that the normal tools could not read (a block, a captcha, an authwall, an empty JavaScript shell, a logged-in site), one layer at a time, and record what worked per site.

## Instructions
1. Run `bin/user-config.sh` and read the user's rules files; they win over this file.
2. Run `bin/sites <host>`; if the host has a `route`, use it.
3. Otherwise classify the target (search, public page, logged-in site, public anti-bot site) and follow its section below, one layer at a time.
4. After 2 failures on the same layer, move up a layer.
5. When a route worked or failed, record it in the user's `sites.json`.

## Before anything: the user's own folder
Run `bin/user-config.sh` once per task. It prints the user's settings folder (`~/.config/web-unlock`, or
`$WEB_UNLOCK_HOME`), which lives outside this plugin so updates never overwrite it:
- `rules <file>`: the user's own rules (accounts and sites they log into, tools they have, their language,
  extra steps). **Read every rules file before going on. Where it disagrees with this file, the user's file
  wins.**
- `reference <file> [replaces <bundled file>]`: the user's reference notes. Read one instead of the bundled
  file it replaces; the others add to `references/`.
- `sites <file>`: the registry in use (step 0 below).
- `env <file>`: API keys and settings that the scripts load by themselves. Never print it.

If the folder is missing, carry on with this file alone.

## 0. First: check `sites.json`
Run `bin/sites <host>`: it prints the matching entries of the registry, which is the bundled `sites.json` with
the user's file (the `sites` line above) laid on top; a host in both is the user's entry. Keys match the host,
its parent domains and `*.domain`. If the host has a `route`,
go straight to it. If `route` is `null`, the `how` field says what already failed: do not repeat it.

## P1. Search (when the normal search came back thin)
| | Tool | When |
|---|---|---|
| A | The agent's built-in web search | default |
| B | `bin/search.sh "query"` | failover across providers: free Exa MCP (needs `mcporter`), Exa API (`EXA_API_KEY`), Serper = Google results (`SERPER_API_KEY`; `--gl br --hl pt-br` for local commerce), Tavily CLI (`tvly`), Firecrawl CLI. `--provider all` compares them |
| C | A research or academic search tool you have | answers with citations |

`search.sh` prints one JSON object per line: `{provider,title,url,snippet}`. Free endpoints rate-limit
parallel calls: run searches one at a time.

Existence or price questions (concluding "it does not exist", publishing a table): read
`references/search-doctrine.md` before you close a negative.

## P2. Read a public page the normal fetch could not read
`bin/fetch.sh <url> [-o file] [--start L1]` runs the cascade itself and prints **one line**:
`OK <layer> <file> <bytes>` or `BLOCKED <layer> <reason> | L2: ...`. The body never goes to the terminal. If
plain curl already failed, pass `--start L1` (it tries r.jina.ai once more, then Scrapling and Firecrawl if
installed).

| | Layer | Tool |
|---|---|---|
| A | L0 http | `curl -s -o` with a browser user agent. Returns raw HTML |
| B0 | L1 render, first | `oc raw <url>` ([only-cli](https://github.com/only-cli/oc): `npm install -g --allow-scripts=koffi @only-cli/oc`; free, local, Chrome TLS identity). Exit 2 = no readable text (JavaScript-only page, challenge, wall): move on. `fetch.sh` tries it before r.jina.ai when it is installed. Tested 2026-11-09: read Indeed search results behind Cloudflare where r.jina.ai got the challenge page; fails on JavaScript-only pages |
| B | L1 render | `r.jina.ai` (free, clean markdown; **"Warning: Target URL returned error NNN" is a block**, not content) |
| B1 | L1 stealth, local (if installed) | Scrapling: `scrapling extract fetch <url> <file.md> --solve-cloudflare`. Free and local, passes Cloudflare Turnstile and interstitials in HTTP mode with a spoofed TLS fingerprint. Try it **before** paid services. If it asks for a browser install, run `scrapling install --force` |
| B2 | L1 render, paid (if installed) | `firecrawl scrape`. Uses credits; refuses some sites (LinkedIn) |
| B3 | Local stealth browsers (if installed) | PinchTab, Camoufox or a patched Playwright, **headed**. Use when you need another fingerprint or the page needs clicks |
| C | L2 unlock | the route from `sites.json` (a site-specific scraper or API), or Bright Data Web Unlocker (`BRIGHTDATA_API_KEY` + `BRIGHTDATA_UNLOCKER_ZONE`) |
| D | Cloud browser (if you have a key) | Kernel, Browser Use or similar: stealth and proxy in the cloud, almost no local memory |

**Scrapling's boundary:** it passes **Cloudflare**, it does **not** solve captchas (reCAPTCHA, hCaptcha,
GeeTest), and it is not for logged-in sites. Those go to P3.

Manual `curl`: always `curl -s ... -o <file>`, never the body to the terminal.

Video: a YouTube watch page through r.jina.ai is a 401 shell. Captions come from
`yt-dlp --write-auto-sub --skip-download <url>` (works from a residential IP; datacenter IPs get "confirm
you're not a bot").

## P3. Operate a LOGGED-IN site (the user's own accounts)
**Check the active account before any write.** On sites with several accounts (personal vs. page, several
Google accounts), read on screen which account is active (name, handle, email) before the first click that
changes anything, and compare it with the target account. Different -> stop and switch. Say "active account:
X" in your answer.

Against Cloudflare, use a browser that looks human: **headed, real GPU, `navigator.webdriver=false`**.
Default automation browsers (Playwright's bundled Chromium, `agent-browser` without `--auto-connect`,
anything `--headless`) loop on Turnstile. See `references/why-a-real-browser.md`.

| | Route | How | Window |
|---|---|---|---|
| A | The site's internal API | DevTools -> Copy as cURL (or a HAR of the submit) -> replay with the same cookies | none |
| B | **The user's own Chrome, through an extension** | OpenCLI (`opencli <platform> ...`, `opencli browser`) or Claude in Chrome (`claude --chrome`). No CDP, no webdriver flag. Claude in Chrome pauses and asks the user on captcha or login | the open Chrome |
| C | **The user's own Chrome, through CDP** | enable `chrome://inspect/#remote-debugging` once (Chrome 144+), then `agent-browser --auto-connect open <url>`. Each new connection shows an "Allow" dialog and brings Chrome to the front: prefer B or D | the open Chrome |
| D | **A real Chrome in its own automation profile** | `bin/chrome-real.sh start [url]`: headed Chrome in `~/.chrome-automation-profile` (EMPTY profile, its **own** logins), fixed port **9223**, `--disable-blink-features=AutomationControlled`, no startup window, tabs in the background (does not steal focus). Drive it with `node bin/cdp.mjs <url> --title\|--text\|--html f`, or `connectOverCDP('http://127.0.0.1:9223')` and create tabs with `Target.createTarget {background:true}` (**not** `ctx.newPage()`, which brings Chrome to the front). `chrome-real.sh login` opens a page in front so the user signs in once by hand. `status` / `stop`. **Never copy cookies from the real profile** (Google signs the user out everywhere) | its own window, behind |
| E | `agent-browser` with a saved profile | **only sites WITHOUT Cloudflare**, headless | none |

Close the tabs you opened when you finish (`cdp.mjs` closes its own unless `--keep`).

**Captcha:** if your tools let you see and click the page, you may try the challenge once on screen. If that
fails, hand it to the user and say what you tried. **2FA:** use a code source the user already set up for you
(a password manager CLI with TOTP, a mail or SMS tool), else ask the user. A solved login persists in that
profile. Never use a paid captcha-solving service on the user's own accounts.

## P3-public. Interact with a public anti-bot site (no account)
**Read only (no clicks): start with Scrapling** (`scrapling extract fetch <url> <file> --solve-cloudflare`, or
`StealthySession` in Python for several pages with one session). Move to a browser only to **interact**.
**Interact:** a local stealth browser (PinchTab, Camoufox) or route D above. Then:
A = `agent-browser` headless, **only if the host is not tagged `cloudflare` in `sites.json`** (after a click,
`agent-browser wait --load networkidle` before reading) -> B = route D (`chrome-real.sh`) -> C = a cloud
browser with stealth and proxy (needs the provider's key).

> **Block signals: `references/block-signals.md`**: load it when `bin/blocked` says OK but the page looks
> like a shell, or to add a pattern to the detector. Test any saved output with `node bin/blocked <file>`.

## When you finish a web task
A new route worked or failed -> update the user's `sites.json` (host, tags, route, how, verified = date).
Without that the next session rediscovers it. Write to the `sites.json` in the user's folder (run
`bin/user-config.sh --init` first if it does not exist), never to the plugin folder, which updates overwrite.
Add or replace only that host's entry under `"hosts"`: the bundled hosts already apply.

## Prerequisites
- `bash`, `curl`, `node` 22+ and `python3`.
- Everything else is optional (Scrapling, Firecrawl, Bright Data, search API keys, Chrome, `playwright-core`): each script checks, skips what is missing and says so. See "Optional requirements" in the README.

## Limitations
- Detection works on text patterns: an unknown block page reads as OK, and a page that quotes a block signature can read as blocked.
- Free endpoints (r.jina.ai, the Exa MCP) rate-limit parallel calls; run them one at a time.
- `chrome-real.sh` runs on macOS and Linux only; on Linux it was never run against a real Chrome.

## Troubleshooting
- `fetch.sh` prints `BLOCKED ... L2 unavailable`: there is no Bright Data key or zone; follow the next steps it prints, or move to the browser routes.
- `chrome-real.sh` finds no browser: it prints where it looked; set `CHROME_REAL_APP`.
- `cdp.mjs` exits with code 3: `playwright-core` is missing; it prints the install hint.

## Examples
- A plain fetch of a product page returns "Just a moment...". Run `bin/fetch.sh <url>`; it prints one line, `OK <layer> <file> <bytes>` or `BLOCKED <layer> <reason>`, and the body goes to the file, not the terminal.
- The user says "log into my account on X". Check `bin/sites X`, then use the user's own Chrome (route B or C) or `bin/chrome-real.sh start <url>` (route D), and say which account is active before any write.
- The user says "the site blocked it" or "use the real Chrome". Read the block signals, move up one layer from the one that failed, and record the result in `sites.json`.
- Before saying "it does not exist" or publishing a price table built from searches, read `references/search-doctrine.md` first.
