# web-unlock

A Claude Code skill for the moment a normal web fetch fails: a Cloudflare challenge, a 403, a captcha, an
authwall, an empty JavaScript shell. It gives Claude a ladder per kind of target, scripts that climb it, a
per-site registry of what worked, and a short doctrine for searches that end in "it does not exist".

Without it, Claude tends to retry the same blocked request with small changes, or to give up and say the page
can't be read. Most blocks have a known next step: a rendering reader, a stealth fetcher, the site's own API, or
a real headed Chrome instead of a default automation browser.

## What's inside

| Path (in `skills/web-unlock/`) | What it does |
|---|---|
| `SKILL.md` | The ladders: search (P1), read a public page (P2), operate a logged-in site (P3), interact with a public anti-bot site |
| `bin/fetch.sh <url>` | Reads a page through a cascade: plain curl -> r.jina.ai -> Scrapling -> Firecrawl -> a known route or Bright Data. Prints one line (`OK <layer> <file> <bytes>` or `BLOCKED ...`); the body goes to a file |
| `bin/search.sh "query"` | Search with failover: free Exa MCP -> Exa API -> Serper (Google) -> Tavily -> Firecrawl. One JSON object per result line |
| `bin/blocked <file>` | Block detector: `OK` or `BLOCKED:<reason>` (Cloudflare, DataDome, PerimeterX, Kasada, Imperva, Akamai, captcha widgets, authwalls, reader errors, shells) |
| `bin/chrome-real.sh` | Starts a real, headed Chrome in its own empty profile with CDP on port 9223, without stealing focus |
| `bin/cdp.mjs <url>` | Drives that Chrome through Playwright's `connectOverCDP` in a background tab: `--title`, `--text`, `--html file`, `--eval js` |
| `sites.json` | Example registry: host -> tags, route that worked, how |
| `references/` | Search doctrine, why a real browser passes where automation fails, the list of block signals |

## Example

```
$ skills/web-unlock/bin/fetch.sh https://example.com
OK L0-curl /tmp/web-unlock/example-com.html 577 http=200

$ skills/web-unlock/bin/fetch.sh https://blocked.example.com/page
BLOCKED L1-jina BLOCKED:reader-target-error (reader) - Warning: Target URL returned error 403 | L2 unavailable: no route for blocked.example.com ...
```

In a session, Claude loads the skill when a page comes back blocked, or when you say "the site blocked it",
"use the real Chrome", "log into my account on X".

## Install

As a plugin:

```
/plugin marketplace add lucas-saldanha-werneck/web-unlock
/plugin install web-unlock@web-unlock
```

Or as a plain skill folder (copies to `~/.claude/skills/web-unlock` and seeds `~/.config/web-unlock/sites.json`):

```
git clone https://github.com/lucas-saldanha-werneck/web-unlock && cd web-unlock
./install.sh            # --dry-run to see the plan
```

Use one or the other, not both.

## Works well with web-unlock-guard

[web-unlock-guard](https://github.com/lucas-saldanha-werneck/web-unlock-guard) is the enforcement half: hooks
that deny the third identical try on a blocked host, headless and default automation browsers on Cloudflare
sites, and `--remote-debugging-port` without `--user-data-dir`. This skill is the "what to do instead" half.
They use the same layer names and the same `sites.json` format.

The guard finds this skill on its own when it sits at `~/.claude/skills/web-unlock` (the `./install.sh` way).
With the plugin install, set the guard's `skill_dir` option to this plugin's `skills/web-unlock` folder, or
point both at one registry: the guard's `sites_file` and this skill's `WEB_UNLOCK_SITES` to the same file.

## Configuration

All optional.

| Env var | Default | Meaning |
|---|---|---|
| `WEB_UNLOCK_SITES` | `~/.config/web-unlock/sites.json` if it exists, else the bundled example | Site registry |
| `WEB_UNLOCK_ENV` | `~/.config/web-unlock/env` | Shell file with API keys, sourced by `fetch.sh` and `search.sh` |
| `WEB_UNLOCK_TMP` | `$TMPDIR/web-unlock` | Where fetched pages go when `-o` is not given |
| `WEB_UNLOCK_ACCEPT_LANGUAGE` | `en-US,en;q=0.9` | `Accept-Language` for plain curl |
| `WEB_UNLOCK_NO_SCRAPLING` | unset | `1` skips Scrapling in `fetch.sh` |
| `CHROME_REAL_PORT` | `9223` | CDP port of the automation Chrome (9222 is usually your main Chrome's) |
| `CHROME_REAL_PROFILE` | `~/.chrome-automation-profile` | Its profile folder. Refuses your real Chrome profile |
| `CHROME_REAL_APP` | macOS: Chrome Beta if installed, else Chrome. Linux: first of google-chrome-beta, google-chrome, chromium | Browser to launch |
| `PLAYWRIGHT_CORE_PATH` | local, then global npm | Where `cdp.mjs` finds `playwright-core` |

Keys read from the env file, each optional: `EXA_API_KEY`, `SERPER_API_KEY`, `JINA_API_KEY`,
`BRIGHTDATA_API_KEY` + `BRIGHTDATA_UNLOCKER_ZONE`. Keep the file out of any repo (`chmod 600`).

Keep your registry outside the plugin folder (plugin updates replace it): copy `skills/web-unlock/sites.json`
to `~/.config/web-unlock/sites.json` and add hosts as you learn them. The skill tells Claude to write there.

## Requirements

- `bash`, `curl`, `node` 22+ (the detector, `cdp.mjs`, CDP tab creation), `python3` (registry lookup, search
  output).

## Optional requirements

Nothing below is needed. Each script checks and skips what is missing, and says so.

| Tool | Used by | Without it |
|---|---|---|
| [Scrapling](https://github.com/D4Vinci/Scrapling) (`scrapling` CLI) | `fetch.sh` L1, P2/P3 in the skill | skipped; the cascade goes on to Firecrawl or L2 |
| [Firecrawl](https://firecrawl.dev) CLI (paid credits) | `fetch.sh` L1, `search.sh` | skipped |
| Bright Data Web Unlocker (key + zone) | `fetch.sh` L2 | `fetch.sh` prints `BLOCKED ... L2 unavailable` with next steps |
| `mcporter` (free Exa MCP endpoint) | `search.sh` first provider | next provider |
| Exa or Serper API key | `search.sh` | next provider; with none at all, Claude falls back to its built-in search |
| Tavily CLI (`tvly`) | `search.sh` | next provider |
| Google Chrome / Chrome Beta / Chromium | `chrome-real.sh` | it prints where it looked and how to set `CHROME_REAL_APP` |
| `playwright-core` (npm) | `cdp.mjs` | exits with an install hint (code 3) |
| OpenCLI, Claude in Chrome, agent-browser, PinchTab, Camoufox, cloud browsers (Kernel, Browser Use), Apify | named in the skill's ladders | Claude skips those rungs |
| [web-unlock-guard](https://github.com/lucas-saldanha-werneck/web-unlock-guard) | enforces the ladder | the skill still works; nothing stops repeated retries |

## Platform

- `fetch.sh`, `search.sh`, `blocked`: macOS, Linux, Windows (Git Bash).
- `chrome-real.sh`: macOS and Linux. On Windows it says it is unsupported; start Chrome yourself with
  `--user-data-dir=<own folder> --remote-debugging-port=9223` and use `cdp.mjs`.
- Tests run on all three in CI.

## Tests

```
bash tests/run.sh
```

No network: `curl`, `mcporter`, `tvly` and `scrapling` are fakes on a sandboxed `PATH`, and `HOME` is a temp
folder. It covers the detector on synthetic block pages, every `fetch.sh` layer and registry lookup, search
failover and normalization, `chrome-real.sh` refusals, and `install.sh`.

## Uninstall

```
/plugin uninstall web-unlock@web-unlock
/plugin marketplace remove web-unlock
```

or `./install.sh --uninstall`. Your registry and keys in `~/.config/web-unlock` stay; delete that folder
yourself if you want. `rm -rf ~/.chrome-automation-profile` removes the automation Chrome's profile.

## Limits

- The live checks were `fetch.sh` (L0 and r.jina.ai) and `search.sh` (free Exa MCP) on macOS against public
  pages. `chrome-real.sh start` and `cdp.mjs` against a real Chrome were not re-run for this release; on Linux
  they were never run.
- Detection works on text patterns. An unknown block page reads as OK, and a page that quotes a block
  signature can read as blocked.
- Free endpoints (r.jina.ai, the Exa MCP) rate-limit parallel calls. Run them one at a time.

## License

MIT

Built with Claude Code
