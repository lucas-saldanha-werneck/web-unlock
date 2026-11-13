# Security policy

## Reporting a vulnerability

Please report security problems privately: open the **Security** tab of this repository and choose
**Report a vulnerability** (GitHub private vulnerability reporting). Please do not open a public issue
for a security problem. You will get an answer in the same thread.

## Supported versions

Only the latest release is supported. Fixes land in a new release; older versions are not patched.

## What this plugin accesses

- **Network:** `fetch.sh` requests the URL you ask for directly with `curl`, then through `r.jina.ai`, and only if you set the keys through Firecrawl or Bright Data. `search.sh` sends your query to Exa or Serper only when you set their keys. These services see the URLs and queries you send.
- **Secrets:** API keys are read from the environment or `~/.config/web-unlock/env` and sent only to their own service.
- **Browser:** `chrome-real.sh` starts a visible Chrome with its own profile `~/.chrome-automation-profile` and the debugging port bound to `127.0.0.1` (9223 by default). It never copies cookies from your main profile; logins you make in that profile stay there.
- **Files it writes:** a SessionStart hook creates `~/.config/web-unlock/` on first run and never overwrites a file in it. `sites.json` there records what worked per site.
