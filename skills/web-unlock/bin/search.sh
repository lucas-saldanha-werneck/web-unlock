#!/usr/bin/env bash
# web-unlock: web search with failover between providers. Normalized output, one JSON object per line:
#   {"provider":..,"title":..,"url":..,"snippet":..}
# Default order (each one is skipped when it is not available; WEB_UNLOCK_SEARCH_ORDER changes it,
# e.g. "serper exa-mcp" — space or comma separated, providers left out are not tried):
#   exa-mcp   free Exa MCP endpoint through `mcporter` (no key)
#   exa       Exa API            (needs EXA_API_KEY)
#   serper    Google results     (needs SERPER_API_KEY)
#   tavily    Tavily CLI `tvly`
#   firecrawl Firecrawl CLI `firecrawl search`
# Usage: search.sh "query" [-n 5] [--provider exa-mcp|exa|serper|tavily|firecrawl|all] [--gl CC] [--hl LANG]
#   --gl/--hl: country and language for Serper (Google), e.g. --gl br --hl pt-br for local commerce.
# Exit code: 0 = at least one result, 1 = no provider answered.
set -uo pipefail
usage() { echo 'usage: search.sh "query" [-n 5] [--provider exa-mcp|exa|serper|tavily|firecrawl|all] [--gl CC] [--hl LANG]'; }
case "${1:-}" in ""|-h|--help) usage; [ -n "${1:-}" ] && exit 0; exit 1;; esac
Q="$1"; shift
N=5; PROV=auto; GL=""; HL=""
while [ $# -gt 0 ]; do case "$1" in
  -n) N="$2"; shift 2;; --provider) PROV="$2"; shift 2;; --gl) GL="$2"; shift 2;; --hl) HL="$2"; shift 2;;
  *) echo "search.sh: unknown option $1" >&2; usage >&2; exit 1;; esac; done
# -n goes into the JSON of the search APIs as a number: accept only a positive integer.
case "$N" in ''|*[!0-9]*|0) echo "search.sh: -n needs a positive whole number, got: $N" >&2; usage >&2; exit 1;; esac
# Find this script's real folder, following symlinks (readlink without -f works on macOS bash 3.2 too).
_self="$0"; _n=0
while [ -L "$_self" ] && [ $_n -lt 40 ]; do _n=$((_n+1)); _l="$(readlink "$_self")"; case "$_l" in /*) _self="$_l";; *) _self="$(dirname "$_self")/$_l";; esac; done
HERE="$(cd "$(dirname "$_self")" && pwd)"; SKILL="$(dirname "$HERE")"
# shellcheck source=../lib/config.sh
. "$SKILL/lib/config.sh"
wu_load_env export   # env file in your folder: keys, WEB_UNLOCK_SEARCH_ORDER (exported for tvly/firecrawl)
PY="$(command -v python3 || command -v python || true)"
export PYTHONIOENCODING=utf-8
[ -n "$PY" ] || { echo '{"error":"search.sh needs python3 on PATH"}' >&2; exit 1; }
TMP="${WEB_UNLOCK_TMP:-${TMPDIR:-/tmp}/web-unlock}"; mkdir -p "$TMP"; F="$TMP/search.$$.json"
trap 'rm -f "$F"' EXIT
jstr() { printf '%s' "$1" | "$PY" -c 'import json,sys;print(json.dumps(sys.stdin.read()))'; }
norm() { "$PY" -c '
import json, re, sys
prov = sys.argv[1]
try:
    d = json.load(open(sys.argv[2], encoding="utf-8"))
except Exception:
    sys.exit(1)
rows = []
if prov == "exa-mcp":
    txt = "\n".join(c.get("text", "") for c in d.get("content", []) if isinstance(c, dict)) if isinstance(d, dict) else ""
    for blk in re.split(r"\n(?=Title: )", txt):
        m = re.search(r"^Title: (.*)$", blk, re.M); u = re.search(r"^URL: (\S+)", blk, re.M)
        if not (m and u):
            continue
        h = blk.split("Highlights:", 1)[1] if "Highlights:" in blk else ""
        rows.append((m.group(1).strip(), u.group(1).strip(), re.sub(r"\s+", " ", h).strip()))
elif prov == "exa":
    for r in d.get("results", []):
        hl = r.get("highlights") or []
        rows.append((r.get("title"), r.get("url"), r.get("text") or (hl[0] if hl else "")))
elif prov == "serper":
    rows = [(r.get("title"), r.get("link"), r.get("snippet")) for r in d.get("organic", [])]
elif prov == "tavily":
    rows = [(r.get("title"), r.get("url"), r.get("content")) for r in d.get("results", [])]
elif prov == "firecrawl":
    data = d.get("data", d) if isinstance(d, dict) else d
    data = data.get("web", data) if isinstance(data, dict) else data
    rows = [(r.get("title"), r.get("url"), r.get("description") or (r.get("markdown") or "")[:300]) for r in (data or [])]
n = 0
for t, u, s in rows:
    if not u:
        continue
    print(json.dumps({"provider": prov, "title": (t or "")[:200], "url": u, "snippet": (s or "")[:400].replace("\n", " ")}, ensure_ascii=False))
    n += 1
sys.exit(0 if n else 1)' "$1" "$2"; }
try_exa_mcp() { command -v mcporter >/dev/null || return 1
  mcporter call exa.web_search_exa query="$Q" numResults="$N" --output json > "$F" 2>/dev/null && norm exa-mcp "$F"; }
try_exa() { [ -n "${EXA_API_KEY:-}" ] || return 1
  curl -s --max-time 30 -o "$F" -X POST https://api.exa.ai/search -H "x-api-key: $EXA_API_KEY" -H "Content-Type: application/json" \
    -d "{\"query\":$(jstr "$Q"),\"numResults\":$N,\"type\":\"auto\",\"contents\":{\"highlights\":true}}" && norm exa "$F"; }
try_serper() { [ -n "${SERPER_API_KEY:-}" ] || return 1
  local extra=""; [ -n "$GL" ] && extra="$extra,\"gl\":$(jstr "$GL")"; [ -n "$HL" ] && extra="$extra,\"hl\":$(jstr "$HL")"
  curl -s --max-time 30 -o "$F" -X POST https://google.serper.dev/search -H "X-API-KEY: $SERPER_API_KEY" -H "Content-Type: application/json" \
    -d "{\"q\":$(jstr "$Q"),\"num\":$N$extra}" && norm serper "$F"; }
try_tavily() { command -v tvly >/dev/null || return 1
  tvly search "$Q" --max-results "$N" --json > "$F" 2>/dev/null && norm tavily "$F"; }
try_firecrawl() { command -v firecrawl >/dev/null || return 1
  firecrawl search "$Q" --limit "$N" --json -o "$F" >/dev/null 2>&1 && norm firecrawl "$F"; }
run() { case "$1" in exa-mcp) try_exa_mcp;; exa) try_exa;; serper) try_serper;; tavily) try_tavily;; firecrawl) try_firecrawl;;
  *) echo "search.sh: unknown provider $1" >&2; return 1;; esac; }
ALL="${WEB_UNLOCK_SEARCH_ORDER:-exa-mcp exa serper tavily firecrawl}"
ALL="$(printf '%s' "$ALL" | tr ',' ' ')"
if [ "$PROV" = all ]; then ok=1; for p in $ALL; do run "$p" && ok=0; done; exit $ok; fi
if [ "$PROV" != auto ]; then run "$PROV"; exit $?; fi
for p in $ALL; do run "$p" && exit 0; done
echo "{\"error\":\"no provider answered (exa-mcp needs mcporter; exa/serper need a key in $ENV_FILE; tavily/firecrawl need their CLI). Fall back to the agent's built-in web search.\"}" >&2
exit 1
