# web-unlock: shared settings, sourced by the bin/ scripts. Not meant to be run on its own.
#
# Your own folder: $WEB_UNLOCK_HOME, else ~/.config/web-unlock. It sits outside the plugin, so plugin
# updates never touch it. It can hold:
#   env           shell file sourced here: API keys and any WEB_UNLOCK_* / CHROME_REAL_* setting
#   sites.json    your registry (used before the bundled example)
#   *.md          your own rules, which SKILL.md tells Claude to read first
#   references/   your own reference notes (a file named like a bundled one replaces it)
# Callers set SKILL (this skill's folder) before sourcing.
WEB_UNLOCK_HOME="${WEB_UNLOCK_HOME:-$HOME/.config/web-unlock}"
ENV_FILE="${WEB_UNLOCK_ENV:-$WEB_UNLOCK_HOME/env}"
# shellcheck disable=SC1090
[ -f "$ENV_FILE" ] && { set -a; . "$ENV_FILE"; set +a; }

# Registry: $WEB_UNLOCK_SITES, else your folder's sites.json, else the bundled example.
wu_sites() {
  if [ -n "${WEB_UNLOCK_SITES:-}" ]; then printf '%s\n' "$WEB_UNLOCK_SITES"
  elif [ -f "$WEB_UNLOCK_HOME/sites.json" ]; then printf '%s\n' "$WEB_UNLOCK_HOME/sites.json"
  else printf '%s\n' "$SKILL/sites.json"; fi
}
