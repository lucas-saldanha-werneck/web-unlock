#!/usr/bin/env bash
# web-unlock: a REAL, headed Chrome in its OWN automation profile, with CDP on a fixed port.
#
# Why this shape (passes Cloudflare Turnstile where default automation browsers loop):
#  - Chrome 136+ ignores --remote-debugging-port on the default profile, so a separate --user-data-dir is required
#    (this is also what the Chrome DevTools team recommends).
#  - A FIXED port does not turn on navigator.webdriver (port 0, --headless and --remote-debugging-pipe do).
#    --disable-blink-features=AutomationControlled keeps it off.
#  - Headed uses the real GPU; headless falls back to a software renderer that anti-bot scripts flag.
#  - The profile starts EMPTY and has its own logins. Never copy cookies or Local Storage from your main profile:
#    Google accounts use device-bound session credentials (DBSC) and treat a copied cookie as theft, which can sign
#    you out of your main browser too.
#  - Port 9223 by default, because 9222 is what your main Chrome uses when you enable chrome://inspect remote debugging.
#  - It starts with no window and opens tabs in the background, so it does not steal focus (macOS: open -g).
#  - On macOS it prefers Google Chrome Beta when installed: a separate app bundle, so links you click elsewhere keep
#    opening in your main Chrome. Any Chrome or Chromium works; set CHROME_REAL_APP.
#
# Usage:
#   chrome-real.sh start [url]        start (or reuse) the automation Chrome; url opens in a background tab
#   chrome-real.sh start --fresh      recreate the EMPTY profile (loses its logins; refused while running)
#   chrome-real.sh login [url]        open url (default accounts.google.com) in the FOREGROUND to sign in once by hand
#   chrome-real.sh status | stop
# Env: CHROME_REAL_PORT (default 9223), CHROME_REAL_PROFILE (default ~/.chrome-automation-profile),
#      CHROME_REAL_APP (macOS: path to a .app; Linux: path or name of the Chrome binary)
# Then: node bin/cdp.mjs <url> --title  |  playwright connectOverCDP('http://127.0.0.1:9223')  |  agent-browser --cdp 9223 ...
# Platforms: macOS and Linux. Windows is not supported by this script.
set -uo pipefail
OS="$(uname -s 2>/dev/null || echo unknown)"
DST="${CHROME_REAL_PROFILE:-$HOME/.chrome-automation-profile}"
PORT="${CHROME_REAL_PORT:-9223}"
LOG="$DST/chrome-real.log"

case "$OS" in
  Darwin)
    if [ -n "${CHROME_REAL_APP:-}" ]; then APP="$CHROME_REAL_APP"
    elif [ -d "/Applications/Google Chrome Beta.app" ]; then APP="/Applications/Google Chrome Beta.app"
    else APP="/Applications/Google Chrome.app"; fi
    BIN="$APP/Contents/MacOS/$(basename "$APP" .app)"
    REAL_PROFILES="$HOME/Library/Application Support/Google/Chrome:$HOME/Library/Application Support/Google/Chrome Beta:$HOME/Library/Application Support/Chromium" ;;
  Linux)
    BIN="${CHROME_REAL_APP:-}"
    if [ -z "$BIN" ]; then for c in google-chrome-beta google-chrome google-chrome-stable chromium chromium-browser; do
      command -v "$c" >/dev/null && { BIN="$(command -v "$c")"; break; }; done; fi
    [ -n "$BIN" ] && [ "${BIN#/}" = "$BIN" ] && command -v "$BIN" >/dev/null && BIN="$(command -v "$BIN")"
    REAL_PROFILES="$HOME/.config/google-chrome:$HOME/.config/google-chrome-beta:$HOME/.config/chromium" ;;
  *) BIN=""; REAL_PROFILES="" ;;
esac

# Never point the automation profile at a real browser profile.
IFS=: read -r -a _real <<< "$REAL_PROFILES"
for r in "${_real[@]:-}"; do
  [ -n "$r" ] || continue
  case "$DST" in "$r"|"$r"/*) echo "REFUSED: CHROME_REAL_PROFILE points at a real browser profile ($DST). Use a separate folder."; exit 2;; esac
done
[ "$PORT" = 9222 ] && echo "WARNING: port 9222 is usually your main Chrome's remote debugging port. Prefer 9223." >&2

port_open() { (exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null; }
# pid of the MAIN process of this profile (not the helpers)
pid_of() {
  [ -n "$BIN" ] || return 0
  ps axo pid=,command= 2>/dev/null | grep -F -- "--user-data-dir=$DST" | grep -v -i "helper\|--type=" \
    | grep -E -- "--user-data-dir=${DST}( |\$)" | awk '{print $1}' | head -1 || true
}
# open a URL in a new tab; background unless $2 = false (CDP Target.createTarget). Needs Node 22+ (global WebSocket).
open_tab() {
  node -e '
    const [port,url,bg]=process.argv.slice(1);
    (async()=>{ const v=await (await fetch(`http://127.0.0.1:${port}/json/version`)).json();
      const ws=new WebSocket(v.webSocketDebuggerUrl);
      ws.onopen=()=>ws.send(JSON.stringify({id:1,method:"Target.createTarget",params:{url,background:bg!=="false"}}));
      ws.onmessage=e=>{const m=JSON.parse(e.data); if(m.id===1){console.log(m.error?("FAILED: "+m.error.message):("tab "+m.result.targetId+" -> "+url)); ws.close(); process.exit(m.error?1:0);}};
      ws.onerror=e=>{console.log("FAILED ws: "+(e.message||e)); process.exit(1)};
      setTimeout(()=>{console.log("FAILED: timeout"); process.exit(1)},10000);
    })().catch(e=>{console.log("FAILED: "+e.message); process.exit(1)});' "$PORT" "$1" "${2:-true}"
}
# login is the only case where the window SHOULD come to the front
activate() { [ "$OS" = Darwin ] && osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $1) to true" >/dev/null 2>&1 || true; }
launch() {
  local flags=(--user-data-dir="$DST" --remote-debugging-port="$PORT" --no-first-run --no-default-browser-check
    --disable-blink-features=AutomationControlled --disable-backgrounding-occluded-windows
    --disable-renderer-backgrounding --disable-background-timer-throttling --window-size=1280,900 --no-startup-window)
  if [ "$OS" = Darwin ]; then
    # -g: do not bring Chrome to the front; -n: a new instance (your main Chrome is untouched).
    open -g -n -a "$APP" --stdout "$LOG" --stderr "$LOG" --args "${flags[@]}"
  else
    nohup "$BIN" "${flags[@]}" >>"$LOG" 2>&1 &
  fi
}

cmd="${1:-status}"; shift || true
LOGIN=0; if [ "$cmd" = login ]; then LOGIN=1; cmd=start; set -- "${1:-https://accounts.google.com/}"; fi
case "$cmd" in
  start)
    case "$OS" in Darwin|Linux) ;; *) echo "UNSUPPORTED: chrome-real.sh runs on macOS and Linux only (this is $OS). Start Chrome yourself with --user-data-dir=<own folder> --remote-debugging-port=$PORT."; exit 3;; esac
    if [ "$OS" = Darwin ] && [ ! -x "$BIN" ]; then echo "FAILED: Chrome not found at $APP. Set CHROME_REAL_APP to a Chrome or Chromium .app."; exit 1; fi
    if [ "$OS" = Linux ] && [ -z "$BIN" ]; then echo "FAILED: no Chrome or Chromium binary found. Set CHROME_REAL_APP."; exit 1; fi
    FRESH=0; URL=""
    for a in "$@"; do case "$a" in --fresh) FRESH=1;; *) URL="$a";; esac; done
    if port_open; then
      P=$(pid_of)
      if [ -z "$P" ]; then echo "REFUSED: port $PORT is used by another process (not the automation Chrome in $DST). Pick another CHROME_REAL_PORT."; exit 1; fi
      [ "$FRESH" = 1 ] && { echo "REFUSED: --fresh while Chrome is running (pid $P). Run stop first."; exit 1; }
      echo "already running on port $PORT (pid $P)"
      if [ "$LOGIN" = 1 ]; then open_tab "$URL" false; activate "$P"; elif [ -n "$URL" ]; then open_tab "$URL"; fi; exit 0
    fi
    [ -n "$(pid_of)" ] && { echo "FAILED: Chrome for profile $DST is running (pid $(pid_of)) without port $PORT. Run stop and try again."; exit 1; }
    if [ "$FRESH" = 1 ]; then rm -rf "$DST"; echo "profile recreated EMPTY at $DST"; fi
    mkdir -p "$DST"; chmod 700 "$DST"
    launch
    for _ in $(seq 1 40); do port_open && break; sleep 0.5; done
    if port_open; then
      echo "OK automation Chrome (headed) | profile $DST | cdp http://127.0.0.1:$PORT | pid $(pid_of)"
      if [ "$LOGIN" = 1 ]; then open_tab "$URL" false; activate "$(pid_of)"; elif [ -n "$URL" ]; then open_tab "$URL"; fi
      echo "next: node $(dirname "$0")/cdp.mjs <url> --title   |   connectOverCDP('http://127.0.0.1:$PORT')"
    else echo "FAILED: port $PORT did not open. Log: $LOG"; tail -5 "$LOG" 2>/dev/null || true; exit 1; fi ;;
  status)
    P=$(pid_of)
    if port_open && [ -n "$P" ]; then echo "running | port $PORT | pid $P | profile $DST"
    elif port_open; then echo "port $PORT is used by ANOTHER process (not profile $DST)"
    else echo "stopped | profile $([ -d "$DST" ] && echo "exists at $DST" || echo "does not exist yet")"; fi ;;
  stop)
    P=$(pid_of)
    if [ -z "$P" ]; then echo "was not running"; exit 0; fi
    kill -TERM "$P"   # SIGTERM lets Chrome close cleanly; only this profile's process, never your main Chrome
    for _ in $(seq 1 20); do kill -0 "$P" 2>/dev/null || break; sleep 0.5; done
    if kill -0 "$P" 2>/dev/null; then echo "STILL ALIVE after 10 s (pid $P)"; exit 1; else echo "closed (pid $P)"; fi ;;
  -h|--help) echo "usage: chrome-real.sh start [--fresh] [url] | login [url] | status | stop" ;;
  *) echo "usage: chrome-real.sh start [--fresh] [url] | login [url] | status | stop"; exit 2 ;;
esac
