#!/usr/bin/env bash
# web-unlock: optional install WITHOUT the plugin system.
# Copies skills/web-unlock to ~/.claude/skills/web-unlock (where web-unlock-guard looks for a companion skill
# by default) and seeds your own registry at ~/.config/web-unlock/sites.json (never overwritten).
# Usage: ./install.sh [--dry-run] [--uninstall]
# Use this OR the plugin install, not both, or Claude sees the skill twice.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/skills/web-unlock"
DST="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/web-unlock"
CFG="${WEB_UNLOCK_HOME:-$HOME/.config/web-unlock}"
DRY=0; UNINSTALL=0
for a in "$@"; do case "$a" in
  --dry-run) DRY=1;; --uninstall) UNINSTALL=1;;
  -h|--help) echo "usage: ./install.sh [--dry-run] [--uninstall]"; exit 0;;
  *) echo "unknown option: $a" >&2; exit 1;; esac; done
run() { if [ $DRY = 1 ]; then echo "would run: $*"; else "$@"; fi; }

if [ $UNINSTALL = 1 ]; then
  if [ -e "$DST" ]; then run rm -rf "$DST"; echo "removed $DST"; else echo "nothing at $DST"; fi
  echo "kept your registry and keys in $CFG (delete that folder yourself if you want)"
  exit 0
fi

[ -f "$SRC/SKILL.md" ] || { echo "skills/web-unlock not found next to install.sh" >&2; exit 1; }
if [ -e "$DST" ] && [ ! -f "$DST/.installed-by-web-unlock" ]; then
  echo "REFUSED: $DST exists and was not installed by this script. Move it away first." >&2; exit 1
fi
run mkdir -p "$(dirname "$DST")"
run rm -rf "$DST"
run cp -R "$SRC" "$DST"
[ $DRY = 1 ] || touch "$DST/.installed-by-web-unlock"
run chmod +x "$DST/bin/fetch.sh" "$DST/bin/search.sh" "$DST/bin/chrome-real.sh" "$DST/bin/blocked" "$DST/bin/cdp.mjs" "$DST/bin/user-config.sh"
echo "skill: $DST"
if [ -f "$CFG/sites.json" ]; then
  echo "registry: kept your $CFG/sites.json"
else
  run mkdir -p "$CFG"
  run cp "$SRC/sites.json" "$CFG/sites.json"
  echo "registry: seeded $CFG/sites.json from the bundled example"
fi
echo "optional keys file: $CFG/env (EXA_API_KEY, SERPER_API_KEY, JINA_API_KEY, BRIGHTDATA_API_KEY, BRIGHTDATA_UNLOCKER_ZONE)"
