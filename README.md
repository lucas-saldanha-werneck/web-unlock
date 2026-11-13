# web-unlock

[![CI](https://github.com/lucas-saldanha-werneck/web-unlock/actions/workflows/test.yml/badge.svg)](https://github.com/lucas-saldanha-werneck/web-unlock/actions/workflows/test.yml)
[![License](https://img.shields.io/github/license/lucas-saldanha-werneck/web-unlock)](LICENSE)
[![Version](https://img.shields.io/badge/version-0.3.8-blue)](CHANGELOG.md)
[![web-unlock score](https://img.shields.io/badge/skill%20score-98.8%20A-brightgreen)](https://github.com/NVIDIA/SkillEvaluator)
[![plugin score (proposal)](https://img.shields.io/badge/plugin%20score%20(proposal)-98.8%20A-brightgreen)](https://github.com/NVIDIA/SkillEvaluator/issues/508)

A Claude Code skill for the moment a normal web fetch fails: a Cloudflare challenge, a 403, a captcha, an
authwall, an empty JavaScript shell. It gives Claude a ladder per kind of target, scripts that climb it, a
per-site registry of what worked, and a short doctrine for searches that end in "it does not exist".

[![web-unlock demo: tap to open the video](https://github.com/user-attachments/assets/d02b3b1b-c1cd-4a85-999e-f1b372d39e4b)](https://lucas-saldanha-werneck.github.io/web-unlock/demo.mp4)

<table>
<tr>
<td align="center"><img src="https://github.com/user-attachments/assets/f1f82ac9-d8ce-41e1-b2f3-4dc7f054a062" alt="A blocked page names the next step" width="320"><br>A blocked page names the next step</td>
<td align="center"><img src="https://github.com/user-attachments/assets/6de39d57-1b70-42fe-a239-d677b6ccbf3a" alt="It opens a real Chrome behind your work" width="320"><br>It opens a real Chrome behind your work</td>
<td align="center"><img src="https://github.com/user-attachments/assets/fc02e66c-64c6-4342-ab83-eb56d32bf4eb" alt="The route that worked is saved" width="320"><br>The route that worked is saved</td>
</tr>
</table>

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
| `bin/user-config.sh` | Shows your own settings folder (rules, references, registry, keys file), creating it first if it is missing |
| `bin/cdp.mjs <url>` | Drives that Chrome through Playwright's `connectOverCDP` in a background tab: `--title`, `--text`, `--html file`, `--eval js` |
| `bin/sites <host>` | Looks a host up in the registry: the bundled `sites.json` with yours laid on top (`--all` prints the merged registry) |
| `sites.json` | Bundled registry: host -> tags, route that worked, how. Yours is laid over it (`lib/sites.py`) |
| `sites.starter.json` | Starter for your own registry: `{"hosts": {}}` |
| `env.default` | Starter `env` file: every setting at its default, commented out |
| `lib/seed.mjs` | Creates your settings folder on first run (run by the plugin's `hooks/hooks.json` at session start) |
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
/plugin marketplace add lucas-saldanha-werneck/lucas-tools
/plugin install web-unlock@lucas-tools
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
`~/.config/web-unlock/sites.json`, laid over the skill's bundled one the same way. The guard does not read this skill's `env` file: if you move the registry
with `WEB_UNLOCK_SITES` or the folder with `WEB_UNLOCK_HOME`, also set the guard's `sites_file` option to the
same file.

## Settings

The plugin folder is replaced on every update, so your settings and your own things live in a folder of
yours: `~/.config/web-unlock` (or the folder in `WEB_UNLOCK_HOME`). The plugin creates that folder by itself
the first time it runs (a `SessionStart` hook; with `./install.sh`, the install does it), and
`skills/web-unlock/bin/user-config.sh` creates it too if it is missing (`--init` says what it seeded or kept).
It starts with an empty `sites.json` (`{"hosts": {}}`), an `env` file with every setting commented out at its
default (see the variables below), and an empty `references/`. The files it writes behave exactly like having
no folder. Nothing in that folder is touched by `/plugin update`, by `./install.sh` or by an uninstall, and the
seeding never overwrites or changes a file that is already there.

| In your folder | What it is for |
|---|---|
| `*.md` (for example `rules.md`) | Your own rules: the sites you log into, the accounts to check, tools you have, extra rungs, the language to answer in. The skill tells Claude to run `bin/user-config.sh` first and read these files before the rest of `SKILL.md`; where they disagree, yours win |
| `references/` | Your own reference notes. A file with the same name as one in the skill's `references/` replaces it; other files add to them |
| `sites.json` | Your registry, laid over the bundled one: the bundled hosts first, then yours; a host in both is your entry, whole. New bundled hosts from plugin updates still reach you. A full copy of an older bundled file keeps working (it overrides every host it lists). Claude records new routes here; `bin/sites <host>` shows the merged entry |
| `env` | Shell file read by every script: API keys and any setting from the table below (for example `WEB_UNLOCK_SEARCH_ORDER=...` or `CHROME_REAL_APP=...`). A variable already set in the environment wins. `fetch.sh` and `search.sh` export the file's values for the CLIs they call; `chrome-real.sh` takes only `CHROME_REAL_*` and does not pass API keys to Chrome. `chmod 600`; `user-config.sh` only says whether it exists |

`bin/user-config.sh` prints one line per item:

```
home /Users/me/.config/web-unlock (exists)
rules /Users/me/.config/web-unlock/rules.md
reference /Users/me/.config/web-unlock/references/search-doctrine.md replaces .../references/search-doctrine.md
sites /Users/me/.config/web-unlock/sites.json (93 hosts, from your folder; 98 with the bundled ones)
env /Users/me/.config/web-unlock/env (present)
```

If you also keep a personal skill called `web-unlock` in `~/.claude/skills/`, Claude sees two skills with
almost the same description (`web-unlock` and the plugin's `web-unlock:web-unlock`) and may load either.
Move its content into your folder (its rules into `rules.md`, its registry into `sites.json`, its notes into
`references/`) and remove the personal copy, or keep only the personal one.

### Variables

All optional. Each can be set in the environment or in the `env` file of your folder; a value already set in
the environment wins over the file. These settings reach this skill's scripts only, not web-unlock-guard.

| Env var | Default | Meaning |
|---|---|---|
| `WEB_UNLOCK_HOME` | `~/.config/web-unlock` | Your own folder. Environment only: a `WEB_UNLOCK_HOME` line in the `env` file is ignored |
| `WEB_UNLOCK_SITES` | `sites.json` in your folder | Your site registry, laid over the bundled one |
| `WEB_UNLOCK_ENV` | `env` in your folder | Shell file with API keys and settings, read by every script (environment only) |
| `WEB_UNLOCK_SEARCH_ORDER` | `exa-mcp exa serper tavily firecrawl` | Providers `search.sh` tries, in order (space or comma separated; ones left out are skipped) |
| `WEB_UNLOCK_TMP` | `$TMPDIR/web-unlock` | Where fetched pages go when `-o` is not given (made private, `chmod 700`; refused if it is a symlink or another user's folder). With `-o`, the page goes to exactly that file |
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
registry), the first-run seeding (created when missing, existing files byte-identical, overrides respected,
no crash on a read-only folder, seeded defaults behave like no folder), `chrome-real.sh` refusals, and
`install.sh`.

## Uninstall

```
/plugin uninstall web-unlock@lucas-tools
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

## Security

See [SECURITY.md](SECURITY.md) for what this plugin accesses and how to report a vulnerability.
