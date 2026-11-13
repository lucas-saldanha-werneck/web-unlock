# Security policy

## Reporting a vulnerability

Please report security problems privately: open the **Security** tab of this repository and choose
**Report a vulnerability** (GitHub private vulnerability reporting). Please do not open a public issue
for a security problem. You will get an answer in the same thread.

## Supported versions

Only the latest release is supported. Fixes land in a new release; older versions are not patched.

## What this plugin accesses

- **Network:** `fetch.sh` requests the URL directly with `curl`, then (each only if present) through the local `oc` and Scrapling tools, `r.jina.ai`, the Firecrawl CLI, and Bright Data when its key and zone are set. `search.sh` sends your query to the first provider that answers: Exa's MCP endpoint through `mcporter` (no key), the Exa or Serper APIs (with a key), or the Tavily or Firecrawl CLIs. These services see the URLs and queries you send.
- **Secrets:** keys come from the environment or `~/.config/web-unlock/env`. That file is run as a shell script when the scripts load it. `fetch.sh` and `search.sh` export every value in it to the tools they start, and pass the Jina, Bright Data, Exa and Serper keys to `curl` as command-line headers, where other processes of your user can see them.
- **Browser:** `chrome-real.sh` starts a visible Chrome with its own profile `~/.chrome-automation-profile` and the debugging port on 127.0.0.1 (9223 by default). Any local program can drive that browser through the port, including the logins you make in it. The script never copies cookies from your main profile. On macOS, `login` brings the window to the front through `osascript` (System Events). `cdp.mjs` loads `playwright-core` from `PLAYWRIGHT_CORE_PATH`, the global npm folder or the current folder, and can save page HTML or run JavaScript in a page.
- **The browser you use every day:** SKILL.md also tells Claude it may drive your everyday Chrome and its logins through a browser extension (OpenCLI, Claude in Chrome) or through Chrome's remote debugging, when you have set those up.
- **Files:** a SessionStart hook creates `~/.config/web-unlock/` (`sites.json`, `env` with mode 600, `references/`) and never overwrites a file in it. The scripts never write `sites.json`; SKILL.md tells Claude to record working routes there, and to read your `*.md` files in that folder as instructions. Fetched pages are saved by default to `$TMPDIR/web-unlock/` and stay there.
