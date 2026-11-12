#!/usr/bin/env bash
# web-unlock: read a public page through a cascade of layers, moving up only when the detector says BLOCKED.
#   L0 http (plain curl)
#   L1 render (oc, if installed -> r.jina.ai -> Scrapling stealth fetch, if installed -> Firecrawl, if installed)
#   L2 unlock (a known route from sites.json -> Bright Data Web Unlocker, if keys are set)
# Usage: fetch.sh <url> [-o output] [--start L0|L1|L2] [--stop L0|L1|L2]
# Output: one line, "OK <layer> <file> <bytes>" or "BLOCKED <last layer> <reason>".
# The page body always goes to a file, never to the terminal.
# Exit code: 0 = OK, 2 = blocked, 1 = usage error or the output could not be written.
set -uo pipefail
# Find this script's real folder, following symlinks (readlink without -f works on macOS bash 3.2 too).
_self="$0"; _n=0
while [ -L "$_self" ] && [ $_n -lt 40 ]; do _n=$((_n+1)); _l="$(readlink "$_self")"; case "$_l" in /*) _self="$_l";; *) _self="$(dirname "$_self")/$_l";; esac; done
HERE="$(cd "$(dirname "$_self")" && pwd)"; SKILL="$(dirname "$HERE")"
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
wu_load_env export
SITES="$(wu_sites)"
PY="$(command -v python3 || command -v python || true)"
command -v node >/dev/null || { echo "BLOCKED none node-missing | fetch.sh needs node on PATH for the block detector"; exit 2; }

HOST=$(printf '%s' "$URL" | sed -E 's#^[a-zA-Z]+://##; s#/.*##; s#:.*##; s#^www\.##' | tr 'A-Z' 'a-z')
SLUG=$(printf '%s' "$URL" | sed -E 's#^[a-zA-Z]+://##; s#[^A-Za-z0-9]+#-#g' | cut -c1-80)
TMP="${WEB_UNLOCK_TMP:-${TMPDIR:-/tmp}/web-unlock}"; mkdir -p "$TMP" 2>/dev/null
# /tmp can be shared between users: use the folder only if it is ours and not a symlink, and keep it private.
if [ -L "$TMP" ] || [ ! -d "$TMP" ] || [ ! -O "$TMP" ]; then
  echo "REFUSED: temp folder $TMP is a symlink, missing or owned by another user. Set WEB_UNLOCK_TMP to a folder of yours."; exit 1
fi
chmod 700 "$TMP" 2>/dev/null
# Work files go to a fresh folder per run: no file left by an earlier run (or planted) is ever read or written through.
WORK="$(mktemp -d "$TMP/run.XXXXXX")" || { echo "FAILED: cannot create a work folder in $TMP"; exit 1; }
trap 'rm -rf "$WORK"' EXIT
OUT_GIVEN=0; [ -n "$OUT" ] && OUT_GIVEN=1
OUT="${OUT:-$TMP/$SLUG.md}"
mkdir -p "$(dirname "$OUT")" 2>/dev/null
UA="${WEB_UNLOCK_UA:-Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36}"
LANG_HDR="${WEB_UNLOCK_ACCEPT_LANGUAGE:-en-US,en;q=0.9}"
ge() { [ "${1#L}" -ge "${2#L}" ]; }  # ge L1 L0 -> true
size() { wc -c < "$1" | tr -d ' '; }
LAST="none"; REASON=""
deliver() { # $1 work file, $2 destination: copy or fail loudly (never "OK" for a file that is not there)
  cp "$1" "$2" 2>/dev/null || { echo "FAILED $LAST cannot write $2"; exit 1; }
}
check() { # $1 file, $2 optional HTTP status -> 0 if the page is OK
  local r rc; r=$(node "$HERE/blocked" "$1" ${2:+--status "$2"} --expect-page 2>/dev/null); rc=$?
  REASON="$r"; return $rc
}

# L0: plain HTTP
if ge L0 "$START" && ge "$STOP" L0; then
  LAST=L0-curl; f="$WORK/L0.html"; rm -f "$f"
  code=$(curl -sL --compressed -A "$UA" -H "Accept-Language: $LANG_HDR" --max-time 30 -o "$f" -w '%{http_code}' "$URL" 2>/dev/null); crc=$?
  [ $crc -eq 0 ] || code=000
  # Only a complete transfer with a 2xx/3xx status is a page; an error page (404, 500...) moves on like a block.
  case "$code" in 2??|3??) ;; *) [ "$code" = 000 ] && REASON="BLOCKED:curl-failed (exit $crc)" || REASON="BLOCKED:http-$code";; esac
  if [ $crc -eq 0 ] && case "$code" in 2??|3??) true;; *) false;; esac && [ -s "$f" ] && check "$f" "$code"; then
    # The default name ends in .md; plain HTTP gives HTML, so it gets .html. An -o you passed is used as is.
    if [ "$OUT_GIVEN" = 1 ]; then dst="$OUT"; else dst="${OUT%.md}.html"; fi
    deliver "$f" "$dst"; echo "OK L0-curl $dst $(size "$f") http=$code"; exit 0
  fi
fi

# L1: render. oc (only-cli, free, local, Chrome TLS identity; if installed), then r.jina.ai (free),
# then Scrapling (free, local), then Firecrawl (paid credits).
if ge L1 "$START" && ge "$STOP" L1; then
  if command -v oc >/dev/null 2>&1 && oc --help 2>/dev/null | grep -q 'oc open'; then
    LAST=L1-oc; f="$WORK/L1.oc.md"
    TO="$(command -v timeout || command -v gtimeout || true)"
    OC_HOME="$TMP/oc-home" ${TO:+$TO 60} oc raw "$URL" >"$f" 2>"$WORK/oc.err"; ocrc=$?
    if [ "$ocrc" -eq 0 ] && [ -s "$f" ] && check "$f"; then deliver "$f" "$OUT"; echo "OK L1-oc $OUT $(size "$f")"; exit 0; fi
    [ "$ocrc" -eq 2 ] && REASON="BLOCKED:oc-no-readable-text (JavaScript-only page, challenge or wall)"
  fi
  LAST=L1-jina; f="$WORK/L1.jina.md"; rm -f "$f"
  curl -s --max-time 60 -o "$f" -H "Accept: text/markdown" ${JINA_API_KEY:+-H "Authorization: Bearer $JINA_API_KEY"} "https://r.jina.ai/$URL" 2>/dev/null; crc=$?
  if [ $crc -eq 0 ] && [ -s "$f" ] && check "$f"; then deliver "$f" "$OUT"; echo "OK L1-jina $OUT $(size "$f")"; exit 0; fi
  if command -v scrapling >/dev/null && [ "${WEB_UNLOCK_NO_SCRAPLING:-0}" != 1 ]; then
    LAST=L1-scrapling; f="$WORK/L1.scrapling.md"; rm -f "$f"
    scrapling extract fetch "$URL" "$f" --solve-cloudflare >"$WORK/scrapling.log" 2>&1 || true
    if [ -s "$f" ] && check "$f"; then deliver "$f" "$OUT"; echo "OK L1-scrapling $OUT $(size "$f")"; exit 0; fi
  fi
  if command -v firecrawl >/dev/null; then
    LAST=L1-firecrawl; f="$WORK/L1.fc.md"; rm -f "$f"
    firecrawl scrape "$URL" --format markdown --only-main-content -o "$f" >/dev/null 2>"$WORK/fc.err" || true
    if [ -s "$f" ] && check "$f"; then deliver "$f" "$OUT"; echo "OK L1-firecrawl $OUT $(size "$f")"; exit 0; fi
    grep -qi "do not support\|no longer supported" "$WORK/fc.err" 2>/dev/null && REASON="BLOCKED:provider-refused (firecrawl)"
  fi
fi

# L2: unlock. A route that already worked for this host (registry: bundled + yours), else Bright Data.
if ge L2 "$START" && ge "$STOP" L2; then
  KNOWN=$(wu_registry route "$HOST" 2>/dev/null)  # the bundled registry with yours on top
  if [ -n "$KNOWN" ]; then
    echo "BLOCKED $LAST ${REASON:-blocked} | L2: use the known route for $HOST -> $KNOWN"; exit 2
  fi
  if [ -n "${BRIGHTDATA_API_KEY:-}" ] && [ -n "${BRIGHTDATA_UNLOCKER_ZONE:-}" ]; then
    LAST=L2-brightdata; f="$WORK/L2.bd.md"; rm -f "$f"
    # Built by node so quotes or backslashes in the URL or zone cannot break the JSON.
    BODY=$(node -e 'console.log(JSON.stringify({zone:process.argv[1],url:process.argv[2],format:"raw",data_format:"markdown"}))' "$BRIGHTDATA_UNLOCKER_ZONE" "$URL")
    curl -s --max-time 90 -o "$f" -X POST "https://api.brightdata.com/request" \
      -H "Authorization: Bearer $BRIGHTDATA_API_KEY" -H "Content-Type: application/json" \
      -d "$BODY" 2>/dev/null; crc=$?
    if [ $crc -eq 0 ] && [ -s "$f" ] && check "$f"; then deliver "$f" "$OUT"; echo "OK L2-brightdata $OUT $(size "$f")"; exit 0; fi
  else
    echo "BLOCKED $LAST ${REASON:-blocked} | L2 unavailable: no route for $HOST in the registry ($SITES over the bundled one) and no BRIGHTDATA_API_KEY/BRIGHTDATA_UNLOCKER_ZONE in $ENV_FILE. Next: a site-specific scraper or API, or a real headed browser (bin/chrome-real.sh + bin/cdp.mjs)."; exit 2
  fi
fi
echo "BLOCKED $LAST ${REASON:-blocked}"; exit 2
