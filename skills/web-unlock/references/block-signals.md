# Block signals (what `bin/blocked` recognizes)

Load this when `bin/blocked` says OK but the page looks like a shell, or when you add a pattern to the detector.

Strong signals (always count):
- Cloudflare: `cf-mitigated: challenge` (the official header), "Just a moment...", "Performing security
  verification", `__cf_chl_` / `cf_chl_opt`, "Attention Required! | Cloudflare", "Sorry, you have been
  blocked", "Enable JavaScript and cookies to continue".
- Other vendors: DataDome `captcha-delivery.com`, PerimeterX `_pxAppId` / `px-captcha`, Kasada `KPSDK`,
  Imperva `_Incapsula_Resource`, Akamai "Access Denied ... Reference #".
- Site walls: Mercado Libre "Hubo un error accediendo a esta pagina", "Por segurança, complete esta etapa",
  "Para continuar, acesse sua conta"; LinkedIn `authwall`.
- Reader proxies: r.jina.ai "Warning: Target URL returned error 4xx/5xx" (the page looks fine but is a shell),
  `AbuseAlleviationError` / "Anonymous access to domain ... blocked".
- Provider refusal: Firecrawl "we do not support this site".
- `HTTP/1.1 401|403|406|429|451|503` status lines, `curl: (22) ... error: 403`, or `--status` passed in.

Signals that count only on a thin page (under 600 visible characters of HTML, or 2000 of plain text):
- "Verify you are human", the Turnstile widget, `challenges.cloudflare.com`, `/cdn-cgi/challenge-platform/`,
  `g-recaptcha`, `recaptcha/api.js`, `hcaptcha.com/1/api.js`. Ordinary pages embed these in forms.

Structural:
- Shell page: more than 10 KB of HTML with under 600 visible characters.
- Short error page (under 2000 characters) with "Access Denied", "Too Many Requests", "Forbidden", ...
- With `--expect-page`: fewer than 100 visible characters.

Does not count: the word "captcha" in prose.

Test: `node bin/blocked <file>` prints `OK` or `BLOCKED:<reason>`. Suite: `bash tests/run.sh` from the repo root.
