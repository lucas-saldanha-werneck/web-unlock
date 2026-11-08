#!/usr/bin/env bash
# web-unlock: show your own settings folder, the one that survives plugin updates.
# SKILL.md tells Claude to run this first and to read every "rules" file it lists.
# Usage: user-config.sh          create the folder if it is missing (quietly), then print what is there
#                                (never prints the content of the env file)
#        user-config.sh --init   the same, saying for each file whether it was seeded or kept
# Seeding (lib/seed.mjs) writes an empty sites.json (laid over the bundled one), env.default, references/. It never
# overwrites or changes a file that exists.
# Output, one item per line:
#   home <folder> (exists|missing)
#   rules <file>                       your rules: read before SKILL.md, they win where they disagree
#   reference <file> [replaces <bundled file>]
#   sites <file> (<N> hosts, from WEB_UNLOCK_SITES|your folder|the bundled example; <M> with the bundled ones)
#   env <file> (present|absent)
set -uo pipefail
# Find this script's real folder, following symlinks (readlink without -f works on macOS bash 3.2 too).
_self="$0"; _n=0
while [ -L "$_self" ] && [ $_n -lt 40 ]; do _n=$((_n+1)); _l="$(readlink "$_self")"; case "$_l" in /*) _self="$_l";; *) _self="$(dirname "$_self")/$_l";; esac; done
HERE="$(cd "$(dirname "$_self")" && pwd)"; SKILL="$(dirname "$HERE")"
# shellcheck source=../lib/config.sh
. "$SKILL/lib/config.sh"
wu_load_env local WEB_UNLOCK_SITES
NODE="$(command -v node || true)"
# The same seeding the plugin's SessionStart hook runs; WEB_UNLOCK_SITES from the env file counts too.
seed() { [ -n "$NODE" ] || return 1; WEB_UNLOCK_HOME="$WEB_UNLOCK_HOME" WEB_UNLOCK_SITES="${WEB_UNLOCK_SITES:-}" "$NODE" "$SKILL/lib/seed.mjs" "$@"; }
case "${1:-}" in
  "") seed >/dev/null 2>&1 ;;
  --init)
    [ -n "$NODE" ] || { echo "user-config.sh: --init needs node on PATH" >&2; exit 1; }
    seed --verbose || { echo "user-config.sh: could not create $WEB_UNLOCK_HOME" >&2; exit 1; } ;;
  -h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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
else from="the bundled example"; fi
n="?"; m="?"
if [ "$from" = "the bundled example" ]; then read -r _ m < <(wu_registry count 2>/dev/null); n="$m"
elif [ -f "$SITES" ]; then
  read -r n m < <(wu_registry count 2>/dev/null)
  # a file that is there but is not JSON: say so
  PY="$(command -v python3 || command -v python || true)"
  if [ -n "$PY" ] && ! "$PY" -c 'import json,sys; json.load(open(sys.argv[1], encoding="utf-8"))' "$SITES" 2>/dev/null; then n="unreadable"; fi
fi
[ -n "$n" ] || n="?"; [ -n "$m" ] || m="?"
[ -f "$SITES" ] || n="missing"
echo "sites $SITES ($n hosts, from $from; $m with the bundled ones)"
if [ -f "$ENV_FILE" ]; then echo "env $ENV_FILE (present)"; else echo "env $ENV_FILE (absent)"; fi
exit 0
