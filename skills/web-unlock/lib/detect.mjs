// web-unlock: block detector, layer inference and escalation map. No dependencies.
// Used by bin/blocked and bin/fetch.sh. The web-unlock-guard plugin also loads this file when its
// `skill_dir` points at this skill folder, so the exports (detect, inferLayer, NEXT_LAYER,
// firstHost) and the layer names must stay compatible with the guard's bundled detector.
//
// detect(text, { status, expectPage }) returns { blocked, reason, vendor, match }.
// The word "captcha" in prose does not count; only widget markers do.

const STRONG = [
  // Cloudflare
  [/cf-mitigated:\s*challenge/i, 'cloudflare-challenge', 'cloudflare'],
  [/Performing security verification/i, 'cloudflare-turnstile', 'cloudflare'],
  [/__cf_chl_|cf_chl_opt|cType:\s*'managed'/i, 'cloudflare-challenge', 'cloudflare'],
  [/<title>\s*Just a moment\.\.\.\s*<\/title>|(^|\n)\s*[✓✗]?\s*Just a moment\.\.\.\s*($|\n)/i, 'cloudflare-js-challenge', 'cloudflare'],
  [/Attention Required!\s*\|\s*Cloudflare|Sorry, you have been blocked/i, 'cloudflare-waf-block', 'cloudflare'],
  [/Enable JavaScript and cookies to continue/i, 'cloudflare-js-challenge', 'cloudflare'],
  // Other anti-bot vendors
  [/captcha-delivery\.com/i, 'datadome', 'datadome'],
  [/_pxAppId|px-captcha/i, 'perimeterx', 'perimeterx'],
  [/\bKPSDK\b/, 'kasada', 'kasada'],
  [/_Incapsula_Resource|Incapsula incident ID/i, 'incapsula', 'imperva'],
  [/Access Denied.{0,200}Reference #[0-9a-f.]+/is, 'akamai-block', 'akamai'],
  // Site walls seen on large public sites (Mercado Libre / Mercado Livre, LinkedIn)
  [/Hubo un error accediendo a esta pagina/i, 'mercadolibre-error-wall', 'mercadolibre'],
  [/Por segurança, complete esta etapa/i, 'mercadolibre-captcha-wall', 'mercadolibre'],
  [/Para continuar, acesse sua conta/i, 'mercadolibre-login-wall', 'mercadolibre'],
  [/linkedin\.com\/authwall|\bauthwall\b/i, 'authwall', 'linkedin'],
  // Reader proxies (r.jina.ai) that return the target's error as a page
  [/Warning:\s*Target URL returned error\s*(4\d\d|5\d\d)/i, 'reader-target-error', 'reader'],
  [/"name":\s*"AbuseAlleviationError"|Anonymous access to domain [a-z0-9.-]+ blocked/i, 'reader-anonymous-blocked', 'reader'],
  // A scraping provider that refuses the site
  [/we do not support this site|This website is no longer supported/i, 'provider-refused', 'provider'],
  // Generic denial as a title or heading
  [/<title>\s*Access Denied\s*<\/title>|<h1[^>]*>\s*Access Denied\s*<\/h1>/i, 'access-denied', 'generic'],
  [/(^|\n)HTTP\/[0-9.]+\s+(401|403|406|429|451|503)\b/i, 'http-blocked-status', 'http'],
  // curl -f prints the status as an error line and no body
  [/curl: \(22\) The requested URL returned error:?\s*(401|403|406|429|451|503)\b/i, 'http-blocked-status', 'http'],
];
// Widget markers: ordinary pages embed these too (a contact form with Turnstile or reCAPTCHA).
// They count only on a thin page: under 600 visible characters of HTML, or under 2000 characters
// of plain text such as a browser accessibility snapshot.
const WIDGET = [
  [/Verify you are human|Widget containing a Cloudflare security challenge/i, 'cloudflare-turnstile', 'cloudflare'],
  [/challenges\.cloudflare\.com|\/cdn-cgi\/challenge-platform\/|cf-turnstile/i, 'cloudflare-challenge', 'cloudflare'],
  [/g-recaptcha|recaptcha\/api\.js|hcaptcha\.com\/1\/api\.js/i, 'captcha-widget', 'captcha'],
];
// Short error pages: only counted when the whole output is small, so docs prose does not trigger it.
const SHORT_PAGE = /Too Many Requests|Rate limit exceeded|\bForbidden\b|Access Denied|Request blocked|Something went wrong|try again later|Service Unavailable/i;
// A Portuguese error wall ("Ocorreu um erro. Por favor, tente novamente"), as Mercado Livre serves it. The
// phrase is common in i18n strings and API messages, so it counts only in the visible text of a short page
// (HTML without scripts, or reader/plain-text output that is not JSON), and is named after Mercado Livre
// only when the page is from Mercado Livre.
const PT_ERROR_WALL = /Ocorreu um erro\. Por favor, tente novamente/i;
const MERCADOLIVRE = /mercado ?li[bv]re/i;
const BLOCKED_STATUS = [401, 403, 406, 429, 451, 503];

function visibleText(t) {
  return t.replace(/<script[\s\S]*?<\/script>|<style[\s\S]*?<\/style>|<noscript[\s\S]*?<\/noscript>/gi, ' ')
    .replace(/<[^>]+>/g, ' ').replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&#\d+;|&[a-z]+;/gi, ' ')
    .replace(/\s+/g, ' ').trim();
}

const hit = (m, reason, vendor) => ({ blocked: true, reason, vendor, match: m[0].slice(0, 80).replace(/\s+/g, ' ') });

export function detect(text, opts = {}) {
  const t = String(text || '');
  const status = opts && opts.status ? Number(opts.status) : null;
  if (status && BLOCKED_STATUS.includes(status)) {
    return { blocked: true, reason: 'http-' + status, vendor: 'http', match: 'status ' + status };
  }
  // Signatures run on the raw text and on the visible text (wall phrases are split by tags in HTML).
  const vis = /<[a-z!/][^>]*>/i.test(t) ? visibleText(t) : null;
  for (const [re, reason, vendor] of STRONG) {
    const m = re.exec(t) || (vis && re.exec(vis));
    if (m) return hit(m, reason, vendor);
  }
  const thin = vis !== null ? vis.length < 600 : t.length < 2000;
  if (thin) {
    for (const [re, reason, vendor] of WIDGET) {
      const m = re.exec(t) || (vis && re.exec(vis));
      if (m) return hit(m, reason, vendor);
    }
  }
  // Shell page: lots of HTML, almost no visible text (a JS-rendered block or login page).
  if (vis !== null && t.length > 10000 && vis.length < 600) {
    return { blocked: true, reason: 'shell-page', vendor: 'structural', match: `${t.length} bytes of HTML, ${vis.length} visible chars` };
  }
  const pageText = vis !== null ? vis : (/^\s*[[{]/.test(t) ? null : t);
  if (pageText !== null && pageText.length < 2000) {
    const m = PT_ERROR_WALL.exec(pageText);
    if (m) {
      const ml = MERCADOLIVRE.test(t);
      return hit(m, ml ? 'mercadolibre-error-wall' : 'error-wall', ml ? 'mercadolibre' : 'generic');
    }
  }
  if (t.length < 2000) {
    const m = SHORT_PAGE.exec(t);
    if (m) return { blocked: true, reason: 'short-error-page', vendor: 'http', match: m[0] };
  }
  // Weak structural signal: only when the caller expected a real page.
  if (opts && opts.expectPage) {
    const visible = vis !== null ? vis : t.replace(/\s+/g, ' ').trim();
    if (visible.length < 100) return { blocked: true, reason: 'suspiciously-short', vendor: 'structural', match: `${visible.length} visible chars` };
  }
  return { blocked: false, reason: null, vendor: null, match: null };
}

// Which "method" (layer) a command uses. web-unlock-guard counts strikes per host + layer.
export function inferLayer(cmd) {
  const c = String(cmd || '');
  if (/\bagent-browser\b/.test(c)) {
    if (/--auto-connect|--cdp\b/.test(c)) return 'browser-real';
    if (/--provider\b/.test(c)) return 'browser-cloud';
    return 'browser-automation';
  }
  if (/chrome-real\.sh|cdp\.mjs|connectOverCDP|claude\s+--chrome|\bopencli\b/.test(c)) return 'browser-real';
  if (/\bpatchright\b|\bcamoufox\b|\bnodriver\b|\bzendriver\b|\bscrapling\b|\bpinchtab\b/.test(c)) return 'browser-stealth';
  if (/\bplaywright\b|\bpuppeteer\b|\bselenium\b|--headless|--remote-debugging-port/.test(c)) return 'browser-automation';
  if (/\bfirecrawl\b|r\.jina\.ai/.test(c)) return 'fetch-render';
  if (/api\.apify\.com|\bapify\b|brightdata|scrapfly|scraperapi|zenrows/.test(c)) return 'fetch-unlock';
  if (/\bcurl\b|\bwget\b|\bhttpx?\b|curl_cffi|urllib|requests\.get|fetch\(/.test(c)) return 'http';
  return null;
}

export const NEXT_LAYER = {
  'http': 'a rendering fetcher (r.jina.ai or Firecrawl) or a stealth fetcher (scrapling extract fetch --solve-cloudflare)',
  'fetch-render': 'a stealth fetcher (Scrapling), an unlocker service, the site\'s own API, or a real headed browser',
  'fetch-unlock': 'a real headed browser (web-unlock bin/chrome-real.sh, agent-browser --auto-connect, claude --chrome)',
  'browser-automation': 'a real headed browser (bin/chrome-real.sh + bin/cdp.mjs, agent-browser --auto-connect, or claude --chrome)',
  'browser-stealth': 'a real headed browser or a cloud browser',
  'browser-real': 'the user: a captcha or login needs a human once, then the session persists',
  'browser-cloud': 'the user, or the site\'s internal API (record the request and replay it)',
};

export function firstHost(s) {
  const m = /https?:\/\/([a-z0-9.-]+\.[a-z]{2,})/i.exec(String(s || ''));
  if (!m) return null;
  const h = m[1].toLowerCase();
  if (/^(localhost|127\.0\.0\.1|0\.0\.0\.0)$/.test(h)) return null;
  return h.replace(/^www\./, '');
}
