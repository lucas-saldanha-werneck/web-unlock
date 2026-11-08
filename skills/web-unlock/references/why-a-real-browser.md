# Why a real, headed browser (verified facts)

Load this when a browser route fails with no clear reason, or before you change Chrome or stealth flags.

- Chrome 136+ silently ignores `--remote-debugging-port` on the default profile. A separate `--user-data-dir`
  is required. Chrome 144+ also has the `chrome://inspect/#remote-debugging` toggle for your main profile: it
  shows an "Allow" dialog per connection, and `/json/version` returns 404 in that mode (read
  `DevToolsActivePort` in the profile folder instead).
- `navigator.webdriver=true` is set by `--headless`, `--remote-debugging-pipe` and `--remote-debugging-port=0`.
  A fixed port does not set it. `--disable-blink-features=AutomationControlled` turns it off.
- Headless Chrome fails Cloudflare largely because WebGL reports a software renderer (SwiftShader). A headed
  browser with the real GPU passes.
- Do not clone your real Chrome profile into the automation profile. Google accounts use device-bound session
  credentials (DBSC): the copy cannot refresh the bound cookie, Google treats it as cookie theft, and can sign
  you out in your main browser too. Give the automation profile its own logins, made once by hand.
- `connectOverCDP` hangs on a tab with no URL and times out at 30 s by default. `bin/cdp.mjs` closes empty tabs
  first and uses 90 s.
- Local stealth in 2026 is headed or nothing: patched automation libraries pass far more often headed than
  headless.
- There is no ready-made open-source router that goes HTTP -> unlocker -> browser -> stealth on its own. Mature
  agents solve captchas with a human handoff.
