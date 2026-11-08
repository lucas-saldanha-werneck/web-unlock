#!/usr/bin/env bash
# web-unlock: show your own settings folder, the one that survives plugin updates.
# SKILL.md tells Claude to run this first and to read every "rules" file it lists.
# Usage: user-config.sh          print what is there (never prints the content of the env file)
#        user-config.sh --init   create the folder and seed sites.json from the bundled example (keeps existing files)
# Output, one item per line:
#   home <folder> (exists|missing)
#   rules <file>                       your rules: read before SKILL.md, they win where they disagree
#   reference <file> [replaces <bundled file>]
#   sites <file> (<N> hosts, from WEB_UNLOCK_SITES|your folder|the bundled example)
#   env <file> (present|absent)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; SKILL="$(dirname "$HERE")"
# shellcheck source=../lib/config.sh
. "$SKILL/lib/config.sh"
case "${1:-}" in
  "") ;;
  --init)
    mkdir -p "$WEB_UNLOCK_HOME/references"
    if [ -f "$WEB_UNLOCK_HOME/sites.json" ]; then echo "kept $WEB_UNLOCK_HOME/sites.json"
    else cp "$SKILL/sites.json" "$WEB_UNLOCK_HOME/sites.json"; echo "seeded $WEB_UNLOCK_HOME/sites.json"; fi ;;
  -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "user-config.sh: unknown option $1 (use --init or nothing)" >&2; exit 1 ;;
esac

if [ -d "$WEB_UNLOCK_HOME" ]; then echo "home $WEB_UNLOCK_HOME (exists)"; else echo "home $WEB_UNLOCK_HOME (missing)"; fi
for f in "$WEB_UNLOCK_HOME"/*.md; do [ -f "$f" ] && echo "rules $f"; done
for f in "$WEB_UNLOCK_HOME"/references/*; do
  [ -f "$f" ] || continue
  b="$SKILL/references/$(basename "$f")"
  if [ -f "$b" ]; then echo "reference $f replaces $b"; else echo "reference $f"; fi
done

SITES="$(wu_sites)"
if [ -n "${WEB_UNLOCK_SITES:-}" ]; then from="WEB_UNLOCK_SITES"
elif [ "$SITES" = "$WEB_UNLOCK_HOME/sites.json" ]; then from="your folder"
else from="the bundled example; run user-config.sh --init to get your own copy"; fi
PY="$(command -v python3 || command -v python || true)"
n="?"
if [ -n "$PY" ] && [ -f "$SITES" ]; then
  n=$("$PY" -c 'import json,sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
    h = d.get("hosts", d) if isinstance(d, dict) else {}
    print(len(h))
except Exception:
    print("unreadable")' "$SITES" 2>/dev/null || echo "?")
fi
[ -f "$SITES" ] || n="missing"
echo "sites $SITES ($n hosts, from $from)"
if [ -f "$ENV_FILE" ]; then echo "env $ENV_FILE (present)"; else echo "env $ENV_FILE (absent)"; fi
exit 0
