#!/usr/bin/env bash
# web-unlock: read a public page through a cascade of layers, moving up only when the detector says BLOCKED.
#   L0 http (plain curl)
#   L1 render (r.jina.ai -> Scrapling stealth fetch, if installed -> Firecrawl, if installed)
#   L2 unlock (a known route from sites.json -> Bright Data Web Unlocker, if keys are set)
# Usage: fetch.sh <url> [-o output] [--start L0|L1|L2] [--stop L0|L1|L2]
# Output: one line, "OK <layer> <file> <bytes>" or "BLOCKED <last layer> <reason>".
# The page body always goes to a file, never to the terminal.
# Exit code: 0 = OK, 2 = blocked, 1 = usage error.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; SKILL="$(dirname "$HERE")"
usage() { echo "usage: fetch.sh <url> [-o output] [--start L0|L1|L2] [--stop L0|L1|L2]"; }
case "${1:-}" in ""|-h|--help) usage; [ -n "${1:-}" ] && exit 0; exit 1;; esac
URL="$1"; shift
OUT=""; START=L0; STOP=L2
while [ $# -gt 0 ]; do case "$1" in
  -o) OUT="$2"; shift 2;; --start) START="$2"; shift 2;; --stop) STOP="$2"; shift 2;;
  *) echo "fetch.sh: unknown option $1" >&2; usage >&2; exit 1;; esac; done

# Your folder ($WEB_UNLOCK_HOME, default ~/.config/web-unlock): optional env file with keys and settings
# (JINA_API_KEY, BRIGHTDATA_API_KEY, BRIGHTDATA_UNLOCKER_ZONE, WEB_UNLOCK_*), and your sites.json.
# shellcheck source=../lib/config.sh
. "$SKILL/lib/config.sh"
SITES="$(wu_sites)"
PY="$(command -v python3 || command -v python || true)"
command -v node >/dev/null || { echo "BLOCKED none node-missing | fetch.sh needs node on PATH for the block detector"; exit 2; }

HOST=$(printf '%s' "$URL" | sed -E 's#^[a-zA-Z]+://##; s#/.*##; s#:.*##; s#^www\.##' | tr 'A-Z' 'a-z')
SLUG=$(printf '%s' "$URL" | sed -E 's#^[a-zA-Z]+://##; s#[^A-Za-z0-9]+#-#g' | cut -c1-80)
TMP="${WEB_UNLOCK_TMP:-${TMPDIR:-/tmp}/web-unlock}"; mkdir -p "$TMP"
OUT="${OUT:-$TMP/$SLUG.md}"
mkdir -p "$(dirname "$OUT")"
UA="${WEB_UNLOCK_UA:-Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36}"
LANG_HDR="${WEB_UNLOCK_ACCEPT_LANGUAGE:-en-US,en;q=0.9}"
ge() { [ "${1#L}" -ge "${2#L}" ]; }  # ge L1 L0 -> true
size() { wc -c < "$1" | tr -d ' '; }
LAST="none"; REASON=""
check() { # $1 file, $2 optional HTTP status -> 0 if the page is OK
  local r rc; r=$(node "$HERE/blocked" "$1" ${2:+--status "$2"} --expect-page 2>/dev/null); rc=$?
  REASON="$r"; return $rc
}

# L0: plain HTTP
if ge L0 "$START" && ge "$STOP" L0; then
  LAST=L0-curl; f="$TMP/$SLUG.L0.html"
  code=$(curl -sL --compressed -A "$UA" -H "Accept-Language: $LANG_HDR" --max-time 30 -o "$f" -w '%{http_code}' "$URL" 2>/dev/null) || code=000
  if [ -s "$f" ] && check "$f" "$code"; then
    dst="${OUT%.md}.html"; cp "$f" "$dst"; echo "OK L0-curl $dst $(size "$f") http=$code"; exit 0
  fi
fi

# L1: render. r.jina.ai (free), then Scrapling (free, local), then Firecrawl (paid credits).
if ge L1 "$START" && ge "$STOP" L1; then
  LAST=L1-jina; f="$TMP/$SLUG.L1.jina.md"
  curl -s --max-time 60 -o "$f" -H "Accept: text/markdown" ${JINA_API_KEY:+-H "Authorization: Bearer $JINA_API_KEY"} "https://r.jina.ai/$URL" 2>/dev/null
  if [ -s "$f" ] && check "$f"; then cp "$f" "$OUT"; echo "OK L1-jina $OUT $(size "$f")"; exit 0; fi
  if command -v scrapling >/dev/null && [ "${WEB_UNLOCK_NO_SCRAPLING:-0}" != 1 ]; then
    LAST=L1-scrapling; f="$TMP/$SLUG.L1.scrapling.md"; rm -f "$f"
    scrapling extract fetch "$URL" "$f" --solve-cloudflare >"$TMP/$SLUG.scrapling.log" 2>&1 || true
    if [ -s "$f" ] && check "$f"; then cp "$f" "$OUT"; echo "OK L1-scrapling $OUT $(size "$f")"; exit 0; fi
  fi
  if command -v firecrawl >/dev/null; then
    LAST=L1-firecrawl; f="$TMP/$SLUG.L1.fc.md"; rm -f "$f"
    firecrawl scrape "$URL" --format markdown --only-main-content -o "$f" >/dev/null 2>"$TMP/$SLUG.fc.err" || true
    if [ -s "$f" ] && check "$f"; then cp "$f" "$OUT"; echo "OK L1-firecrawl $OUT $(size "$f")"; exit 0; fi
    grep -qi "do not support\|no longer supported" "$TMP/$SLUG.fc.err" 2>/dev/null && REASON="BLOCKED:provider-refused (firecrawl)"
  fi
fi

# L2: unlock. A route that already worked for this host (sites.json), else Bright Data if configured.
if ge L2 "$START" && ge "$STOP" L2; then
  KNOWN=""
  if [ -n "$PY" ] && [ -f "$SITES" ]; then
    KNOWN=$("$PY" - "$SITES" "$HOST" <<'EOF' 2>/dev/null
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8")).get("hosts", {})
except Exception:
    sys.exit(0)
h = sys.argv[2]; parts = h.split(".")
keys = []
for i in range(len(parts) - 1):
    k = ".".join(parts[i:])
    keys.append(k)
    if i > 0:
        keys.append("*." + k)
for k in keys:
    e = d.get(k)
    if e and e.get("alias_of"):
        e = d.get(e["alias_of"])
    if e and e.get("route"):
        print("%s: %s" % (e["route"], e.get("how", "")))
        break
EOF
)
  fi
  if [ -n "$KNOWN" ]; then
    echo "BLOCKED $LAST ${REASON:-blocked} | L2: use the known route for $HOST -> $KNOWN"; exit 2
  fi
  if [ -n "${BRIGHTDATA_API_KEY:-}" ] && [ -n "${BRIGHTDATA_UNLOCKER_ZONE:-}" ]; then
    LAST=L2-brightdata; f="$TMP/$SLUG.L2.bd.md"
    curl -s --max-time 90 -o "$f" -X POST "https://api.brightdata.com/request" \
      -H "Authorization: Bearer $BRIGHTDATA_API_KEY" -H "Content-Type: application/json" \
      -d "{\"zone\":\"$BRIGHTDATA_UNLOCKER_ZONE\",\"url\":\"$URL\",\"format\":\"raw\",\"data_format\":\"markdown\"}" 2>/dev/null
    if [ -s "$f" ] && check "$f"; then cp "$f" "$OUT"; echo "OK L2-brightdata $OUT $(size "$f")"; exit 0; fi
  else
    echo "BLOCKED $LAST ${REASON:-blocked} | L2 unavailable: no route for $HOST in $SITES and no BRIGHTDATA_API_KEY/BRIGHTDATA_UNLOCKER_ZONE in $ENV_FILE. Next: a site-specific scraper or API, or a real headed browser (bin/chrome-real.sh + bin/cdp.mjs)."; exit 2
  fi
fi
echo "BLOCKED $LAST ${REASON:-blocked}"; exit 2
