# web-unlock: shared settings, sourced by the bin/ scripts. Not meant to be run on its own.
#
# Your own folder: $WEB_UNLOCK_HOME, else ~/.config/web-unlock. It sits outside the plugin, so plugin
# updates never touch it. It can hold:
#   env           shell file with API keys and any WEB_UNLOCK_* / CHROME_REAL_* setting (see wu_load_env)
#   sites.json    your registry, laid over the bundled one (same host = yours wins; see lib/sites.py)
#   *.md          your own rules, which SKILL.md tells Claude to read first
#   references/   your own reference notes (a file named like a bundled one replaces it)
# Callers set SKILL (this skill's folder) before sourcing, then call wu_load_env.

# The folder is fixed here, before the env file is read: a WEB_UNLOCK_HOME line inside that file is ignored,
# so every lookup uses the same folder.
WEB_UNLOCK_HOME="${WEB_UNLOCK_HOME:-$HOME/.config/web-unlock}"
ENV_FILE="${WEB_UNLOCK_ENV:-$WEB_UNLOCK_HOME/env}"

# wu_load_env export|local [KEY ...]
# Reads the env file in a subshell and takes its values for KEYs (default: every KEY=... line in the file).
# A variable already set in the environment wins over the file. "export" exports what it sets (for the CLIs
# that fetch.sh and search.sh call); "local" keeps it in this script only, so a launched browser does not
# inherit API keys.
wu_load_env() {
  local mode="$1" keys k line
  shift
  [ -f "$ENV_FILE" ] || return 0
  if [ $# -gt 0 ]; then keys="$*"
  else keys=$(sed -n 's/^[[:space:]]*\(export[[:space:]][[:space:]]*\)\{0,1\}\([A-Za-z_][A-Za-z0-9_]*\)=.*/\2/p' "$ENV_FILE"); fi
  [ -n "$keys" ] || return 0
  local vals
  # shellcheck disable=SC1090
  vals=$( set -a; . "$ENV_FILE" >/dev/null 2>&1; for k in $keys; do
    [ -n "${!k+x}" ] && printf '%s=%q\n' "$k" "${!k}"; done )
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    k="${line%%=*}"
    case "$k" in WEB_UNLOCK_HOME|WEB_UNLOCK_ENV|ENV_FILE|SKILL|HERE) continue;; esac
    [ -n "${!k+x}" ] && continue          # set by the caller: keep it
    eval "$line"
    [ "$mode" = export ] && export "${k?}"
  done <<EOF
$vals
EOF
  return 0
}

# Your registry file: $WEB_UNLOCK_SITES, else your folder's sites.json, else the bundled example (no file of
# yours). What the scripts read is the overlay of yours on the bundled one: wu_registry, lib/sites.py.
wu_sites() {
  if [ -n "${WEB_UNLOCK_SITES:-}" ]; then printf '%s\n' "$WEB_UNLOCK_SITES"
  elif [ -f "$WEB_UNLOCK_HOME/sites.json" ]; then printf '%s\n' "$WEB_UNLOCK_HOME/sites.json"
  else printf '%s\n' "$SKILL/sites.json"; fi
}

# wu_registry merged|lookup <host>|route <host>|count: the bundled registry with yours on top.
wu_registry() {
  local py yours
  py="$(command -v python3 || command -v python || true)"
  [ -n "$py" ] || return 1
  yours="$(wu_sites)"; [ "$yours" = "$SKILL/sites.json" ] && yours=""
  # tr: Python on Windows ends lines with CR LF
  "$py" "$SKILL/lib/sites.py" "$SKILL/sites.json" "$yours" "$@" | tr -d '\r'
}
