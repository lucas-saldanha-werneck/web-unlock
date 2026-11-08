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
| `bin/user-config.sh` | Shows your own settings folder (rules, references, registry, keys file); `--init` creates it |
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

The guard finds this skill on its own, whether it sits at `~/.claude/skills/web-unlock` (the `./install.sh`
way) or is installed as this plugin (guard 0.4.0 or later), and it reads the same registry,
`~/.config/web-unlock/sites.json`. To use another file, point the guard's `sites_file` and this skill's
`WEB_UNLOCK_SITES` at it.

## Your own folder (survives plugin updates)

The plugin folder is replaced on every update, so your own things live in a folder of yours:
`~/.config/web-unlock` (or the folder in `WEB_UNLOCK_HOME`). Create it with
`skills/web-unlock/bin/user-config.sh --init`, which seeds `sites.json` from the bundled example and never
overwrites a file you have.

| In your folder | What it is for |
|---|---|
| `*.md` (for example `rules.md`) | Your own rules: the sites you log into, the accounts to check, tools you have, extra rungs, the language to answer in. The skill tells Claude to run `bin/user-config.sh` first and read these files before the rest of `SKILL.md`; where they disagree, yours win |
| `references/` | Your own reference notes. A file with the same name as one in the skill's `references/` replaces it; other files add to them |
| `sites.json` | Your registry. The scripts use it before the bundled example, and Claude records new routes here |
| `env` | Shell file sourced by every script: API keys and any setting from the table below (for example `WEB_UNLOCK_SEARCH_ORDER=...` or `CHROME_REAL_APP=...`). `chmod 600`; `user-config.sh` only says whether it exists |

`bin/user-config.sh` prints one line per item:

```
home /Users/me/.config/web-unlock (exists)
rules /Users/me/.config/web-unlock/rules.md
reference /Users/me/.config/web-unlock/references/search-doctrine.md replaces .../references/search-doctrine.md
sites /Users/me/.config/web-unlock/sites.json (93 hosts, from your folder)
env /Users/me/.config/web-unlock/env (present)
```

Nothing in that folder is touched by `/plugin update`, by `./install.sh` or by an uninstall.

If you also keep a personal skill called `web-unlock` in `~/.claude/skills/`, Claude sees two skills with
almost the same description (`web-unlock` and the plugin's `web-unlock:web-unlock`) and may load either.
Move its content into your folder (its rules into `rules.md`, its registry into `sites.json`, its notes into
`references/`) and remove the personal copy, or keep only the personal one.

## Configuration

All optional. Each can be set in the environment or in the `env` file of your folder.

| Env var | Default | Meaning |
|---|---|---|
| `WEB_UNLOCK_HOME` | `~/.config/web-unlock` | Your own folder (environment only, since the `env` file lives inside it) |
| `WEB_UNLOCK_SITES` | `sites.json` in your folder if it exists, else the bundled example | Site registry |
| `WEB_UNLOCK_ENV` | `env` in your folder | Shell file with API keys and settings, sourced by every script |
| `WEB_UNLOCK_SEARCH_ORDER` | `exa-mcp exa serper tavily firecrawl` | Providers `search.sh` tries, in order (space or comma separated; ones left out are skipped) |
| `WEB_UNLOCK_TMP` | `$TMPDIR/web-unlock` | Where fetched pages go when `-o` is not given |
| `WEB_UNLOCK_ACCEPT_LANGUAGE` | `en-US,en;q=0.9` | `Accept-Language` for plain curl |
| `WEB_UNLOCK_NO_SCRAPLING` | unset | `1` skips Scrapling in `fetch.sh` |
| `CHROME_REAL_PORT` | `9223` | CDP port of the automation Chrome (9222 is usually your main Chrome's) |
| `CHROME_REAL_PROFILE` | `~/.chrome-automation-profile` | Its profile folder. Refuses your real Chrome profile |
| `CHROME_REAL_APP` | macOS: Chrome Beta if installed, else Chrome. Linux: first of google-chrome-beta, google-chrome, chromium | Browser to launch |
| `PLAYWRIGHT_CORE_PATH` | local, then global npm | Where `cdp.mjs` finds `playwright-core` |

Keys read from the env file, each optional: `EXA_API_KEY`, `SERPER_API_KEY`, `JINA_API_KEY`,
`BRIGHTDATA_API_KEY` + `BRIGHTDATA_UNLOCKER_ZONE`. Keep the file out of any repo (`chmod 600`).


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
failover, order and normalization, the user folder (`WEB_UNLOCK_HOME`, its `env`, rules, references and
registry), `chrome-real.sh` refusals, and `install.sh`.

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
