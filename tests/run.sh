#!/usr/bin/env bash
# web-unlock tests. No network: curl, mcporter, tvly and scrapling are fakes on a sandboxed PATH,
# HOME is a temp folder. Runs on Linux, macOS and Windows (Git Bash). Needs node and python on PATH.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SK="$ROOT/skills/web-unlock"
FAIL=0; PASS=0
pass() { PASS=$((PASS+1)); printf 'PASS  %s\n' "$1"; }
fail() { FAIL=$((FAIL+1)); printf 'FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '      %s\n' "$2"; }

NODE="$(command -v node || true)"
PY=""; for c in python3 python; do command -v "$c" >/dev/null && "$c" -c 'import sys' 2>/dev/null && { PY="$(command -v "$c")"; break; }; done
[ -n "$NODE" ] || { echo "FAIL: node is not on PATH"; exit 1; }
[ -n "$PY" ] || { echo "FAIL: python is not on PATH"; exit 1; }

T="$(mktemp -d 2>/dev/null || mktemp -d -t webunlock)"
trap 'rm -rf "$T"' EXIT
export HOME="$T/home" USERPROFILE="$T/home" TMPDIR="$T/tmp" WEB_UNLOCK_TMP="$T/tmp/web-unlock"
mkdir -p "$HOME" "$TMPDIR"
unset CLAUDE_CONFIG_DIR WEB_UNLOCK_SITES WEB_UNLOCK_ENV WEB_UNLOCK_HOME WEB_UNLOCK_SEARCH_ORDER EXA_API_KEY SERPER_API_KEY JINA_API_KEY BRIGHTDATA_API_KEY BRIGHTDATA_UNLOCKER_ZONE
DUMMY="dummy-value"   # stands in for an API key; the fakes never check it
# A path node sees the same way bash does. Git Bash leaves a /tmp/... path that runs through a regular file
# unconverted, and node would then read it as C:\tmp\...; the mixed form C:/... works in both.
wp() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }

# ---------- 1. detector on the samples ----------
echo "== detector =="
for f in "$ROOT"/tests/samples/*; do
  name=$(basename "$f")
  out=$("$NODE" "$SK/bin/blocked" "$f" 2>&1); rc=$?
  if [[ "$name" == ok-* ]]; then exp=0; else exp=2; fi
  if [ "$rc" -eq "$exp" ]; then pass "$name -> $out"; else fail "$name (rc=$rc, want $exp)" "$out"; fi
done
out=$(printf 'fine page body that is long enough to be a real page, with plenty of visible text in it for the check to pass.' | "$NODE" "$SK/bin/blocked" - --status 403); rc=$?
[ $rc -eq 2 ] && [[ "$out" == *http-403* ]] && pass "--status 403 marks a page blocked" || fail "--status 403" "$out"
printf 'tiny' > "$T/tiny.txt"
out=$("$NODE" "$SK/bin/blocked" --expect-page "$T/tiny.txt"); rc=$?
[ $rc -eq 2 ] && [[ "$out" == *suspiciously-short* ]] && pass "--expect-page flags a near-empty page (flag before file)" || fail "--expect-page" "$out"
# Installed plugins live under ~/.claude; a {"type":"commonjs"} package.json above them must not break the detector.
mkdir -p "$T/cjs/parent"
printf '{"type":"commonjs"}\n' > "$T/cjs/package.json"
cp -R "$SK/bin" "$SK/lib" "$T/cjs/parent/"
out=$(printf 'fine page body that is long enough to be a real page, with plenty of visible text in it for the check to pass.' | "$NODE" "$T/cjs/parent/bin/blocked" - 2>&1); rc=$?
[ $rc -eq 0 ] && [[ "$out" == OK* ]] && pass "detector runs under a parent package.json with type commonjs" || fail "commonjs parent (rc=$rc)" "$out"
cp "$SK/lib/detect.mjs" "$T/detect.mjs"
out=$(cd "$T" && "$NODE" --input-type=module -e "
import { detect, inferLayer, firstHost, NEXT_LAYER } from './detect.mjs';
const r = [inferLayer('curl -s https://a.com -o f'), inferLayer('agent-browser open https://a.com'),
  inferLayer('agent-browser --auto-connect open https://a.com'), inferLayer('scrapling extract fetch https://a.com f'),
  inferLayer('curl -s https://r.jina.ai/https://a.com'), firstHost('see https://www.Example.com/x'),
  typeof NEXT_LAYER['http'], detect('hello').blocked];
console.log(r.join(','));" 2>&1)
[ "$out" = "http,browser-automation,browser-real,browser-stealth,fetch-render,example.com,string,false" ] \
  && pass "exports match web-unlock-guard's interface (detect, inferLayer, firstHost, NEXT_LAYER)" || fail "guard interface" "$out"

# ---------- sandboxed PATH with fakes ----------
SB="$T/bin"; mkdir -p "$SB"
printf '#!/bin/sh\nexec "%s" "$@"\n' "$NODE" > "$SB/node"
printf '#!/bin/sh\nexec "%s" "$@"\n' "$PY" > "$SB/python3"
# Fake curl: copies $FAKE_<kind>_BODY to the -o file, prints the status for -w, logs URL and body.
cat > "$SB/curl" <<'EOF'
#!/usr/bin/env bash
out=""; w=""; url=""; data=""
while [ $# -gt 0 ]; do case "$1" in
  -o) out="$2"; shift 2;; -w) w="$2"; shift 2;; -d) data="$2"; shift 2;;
  -A|-H|-X|--max-time) shift 2;;
  http*) url="$1"; shift;; *) shift;; esac; done
printf '%s | %s\n' "$url" "$data" >> "$FAKE_LOG"
case "$url" in
  https://r.jina.ai/*) body="${FAKE_JINA_BODY:-}"; code=200;;
  https://api.brightdata.com/*) body="${FAKE_BD_BODY:-}"; code=200;;
  https://google.serper.dev/*) body="${FAKE_SERPER_BODY:-}"; code=200;;
  https://api.exa.ai/*) body="${FAKE_EXA_BODY:-}"; code=200;;
  *) body="${FAKE_L0_BODY:-}"; code="${FAKE_L0_CODE:-200}"
     # a network failure: real curl writes nothing, prints 000 for -w and exits non-zero
     if [ "${FAKE_L0_FAIL:-}" = 1 ]; then [ -n "$w" ] && printf '000'; exit 7; fi;;
esac
if [ -n "$body" ] && [ -n "$out" ]; then cp "$body" "$out"; elif [ -n "$out" ]; then : > "$out"; fi
[ -n "$w" ] && printf '%s' "$code"
exit 0
EOF
chmod +x "$SB"/*
export FAKE_LOG="$T/curl.log"; : > "$FAKE_LOG"
P="$SB:/usr/bin:/bin"
S="$ROOT/tests/samples"
GOOD="$S/ok-docs-page.html"; GOODMD="$S/ok-prose-mentions-captcha.md"
CF="$S/cloudflare-just-a-moment.html"; RTE="$S/reader-target-error.txt"
fetch() { env PATH="$P" bash "$SK/bin/fetch.sh" "$@"; }

echo "== fetch.sh =="
out=$(FAKE_L0_BODY="$GOOD" fetch https://docs.example.com/hooks); rc=$?
[ $rc -eq 0 ] && [[ "$out" == "OK L0-curl "* ]] && pass "L0 serves a normal page" || fail "L0 ok" "$out"
f=$(printf '%s' "$out" | awk '{print $3}'); cmp -s "$f" "$GOOD" && pass "L0 output file holds the page" || fail "L0 output file" "$f"

out=$(FAKE_L0_BODY="$CF" FAKE_L0_CODE=403 FAKE_JINA_BODY="$GOODMD" fetch https://blocked.example.com/a -o "$T/out/a.md"); rc=$?
[ $rc -eq 0 ] && [[ "$out" == "OK L1-jina $T/out/a.md "* ]] && pass "L0 blocked (403 + Cloudflare) -> L1 r.jina.ai" || fail "L1 jina" "$out"

cat > "$SB/scrapling" <<'EOF'
#!/usr/bin/env bash
# fake: scrapling extract fetch <url> <file> ...
cp "$FAKE_SCRAPLING_BODY" "$4"
EOF
chmod +x "$SB/scrapling"
out=$(FAKE_L0_BODY="$CF" FAKE_JINA_BODY="$RTE" FAKE_SCRAPLING_BODY="$GOODMD" fetch https://blocked.example.com/b); rc=$?
[ $rc -eq 0 ] && [[ "$out" == "OK L1-scrapling "* ]] && pass "reader error page is a block -> Scrapling (when installed)" || fail "L1 scrapling" "$out"
out=$(WEB_UNLOCK_NO_SCRAPLING=1 FAKE_L0_BODY="$CF" FAKE_JINA_BODY="$RTE" FAKE_SCRAPLING_BODY="$GOODMD" fetch https://blocked.example.com/b); rc=$?
[ $rc -eq 2 ] && pass "WEB_UNLOCK_NO_SCRAPLING=1 skips Scrapling" || fail "no-scrapling" "$out"
rm -f "$SB/scrapling"

out=$(FAKE_L0_BODY="$CF" FAKE_JINA_BODY="$RTE" fetch https://blocked.example.com/c); rc=$?
[ $rc -eq 2 ] && [[ "$out" == *"L2 unavailable"* ]] && [[ "$out" == *"BLOCKED L1-jina"* ]] \
  && pass "all layers blocked, no route, no keys -> clear BLOCKED line, exit 2" || fail "L2 unavailable" "$out"

cat > "$T/sites.json" <<'EOF'
{"hosts": {"example.com": {"tags": ["antibot"], "route": "fetch-unlock", "how": "the site's JSON API at /api/items"},
           "*.shop.test": {"route": "browser-real", "how": "chrome-real.sh"},
           "m.example.net": {"alias_of": "example.com"}}}
EOF
out=$(WEB_UNLOCK_SITES="$T/sites.json" FAKE_L0_BODY="$CF" FAKE_JINA_BODY="$RTE" fetch https://www.sub.example.com/x); rc=$?
[ $rc -eq 2 ] && [[ "$out" == *"known route for sub.example.com -> fetch-unlock: the site's JSON API"* ]] \
  && pass "sites.json route found through a parent domain" || fail "sites parent" "$out"
out=$(WEB_UNLOCK_SITES="$T/sites.json" FAKE_L0_BODY="$CF" FAKE_JINA_BODY="$RTE" fetch https://a.shop.test/x)
[[ "$out" == *"browser-real: chrome-real.sh"* ]] && pass "sites.json *.domain wildcard" || fail "sites wildcard" "$out"
out=$(WEB_UNLOCK_SITES="$T/sites.json" FAKE_L0_BODY="$CF" FAKE_JINA_BODY="$RTE" fetch https://m.example.net/x)
[[ "$out" == *"fetch-unlock"* ]] && pass "sites.json alias_of" || fail "sites alias" "$out"
mkdir -p "$HOME/.config/web-unlock"; cp "$T/sites.json" "$HOME/.config/web-unlock/sites.json"
out=$(FAKE_L0_BODY="$CF" FAKE_JINA_BODY="$RTE" fetch https://example.com/x)
[[ "$out" == *"fetch-unlock"* ]] && pass "user registry in ~/.config/web-unlock/sites.json wins over the bundled one" || fail "user registry" "$out"
rm -f "$HOME/.config/web-unlock/sites.json"

printf '%s=%s\n' BRIGHTDATA_API_KEY "$DUMMY" BRIGHTDATA_UNLOCKER_ZONE zone1 > "$HOME/.config/web-unlock/env"
out=$(FAKE_L0_BODY="$CF" FAKE_JINA_BODY="$RTE" FAKE_BD_BODY="$GOODMD" fetch https://blocked.example.com/d); rc=$?
[ $rc -eq 0 ] && [[ "$out" == "OK L2-brightdata "* ]] && pass "keys from ~/.config/web-unlock/env enable Bright Data at L2" || fail "L2 brightdata" "$out"
rm -f "$HOME/.config/web-unlock/env"

: > "$FAKE_LOG"
out=$(FAKE_L0_BODY="$GOOD" FAKE_JINA_BODY="$GOODMD" fetch https://docs.example.com/x --start L1 2>&1)
grep -q "^https://docs.example.com/x |" "$FAKE_LOG" && fail "--start L1 must skip L0" "$(cat "$FAKE_LOG")" || pass "--start L1 skips plain curl"
out=$(fetch https://x.example --bogus 2>&1); rc=$?
[ $rc -eq 1 ] && pass "unknown option -> usage, exit 1" || fail "unknown option" "$out"

echo "== search.sh =="
search() { env PATH="$P" bash "$SK/bin/search.sh" "$@"; }
out=$(search "hooks" 2>"$T/err"); rc=$?
[ $rc -eq 1 ] && grep -q "no provider answered" "$T/err" && pass "no provider available -> exit 1 with a hint" || fail "no provider" "$out $(cat "$T/err")"
printf '{"organic":[{"title":"Hooks","link":"https://docs.example.com/hooks","snippet":"Hook events"},{"title":"No link"}]}' > "$T/serper.json"
: > "$FAKE_LOG"
out=$(SERPER_API_KEY="$DUMMY" FAKE_SERPER_BODY="$T/serper.json" search "ferramenta x" --gl br --hl pt-br); rc=$?
[ $rc -eq 0 ] && [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 1 ] && [[ "$out" == *'"provider": "serper"'* ]] \
  && pass "Serper with a key: one normalized JSON line (rows without a URL dropped)" || fail "serper" "$out"
grep -q '"gl":"br","hl":"pt-br"' "$FAKE_LOG" && pass "--gl/--hl reach the Serper request" || fail "gl/hl" "$(cat "$FAKE_LOG")"
cat > "$SB/mcporter" <<'EOF'
#!/usr/bin/env bash
printf '%s' '{"content":[{"type":"text","text":"Title: Exa hit\nURL: https://exa.example/a\nHighlights: some text\n\nTitle: Second\nURL: https://exa.example/b\n"}]}'
EOF
chmod +x "$SB/mcporter"
out=$(SERPER_API_KEY="$DUMMY" FAKE_SERPER_BODY="$T/serper.json" search "q"); rc=$?
[ $rc -eq 0 ] && [[ "$out" == *'"provider": "exa-mcp"'* ]] && [[ "$out" != *serper* ]] \
  && pass "free Exa MCP (mcporter) goes first and stops the failover" || fail "exa-mcp first" "$out"
out=$(SERPER_API_KEY="$DUMMY" FAKE_SERPER_BODY="$T/serper.json" search "q" --provider all)
[[ "$out" == *exa-mcp* ]] && [[ "$out" == *serper* ]] && pass "--provider all queries every available provider" || fail "provider all" "$out"
rm -f "$SB/mcporter"
printf '#!/usr/bin/env bash\ncat "%s"\n' "$S/ok-search-json.txt" > "$SB/tvly"; chmod +x "$SB/tvly"
out=$(search "q" --provider tavily); rc=$?
[ $rc -eq 0 ] && [[ "$out" == *'"provider": "tavily"'* ]] && pass "--provider tavily uses the tvly CLI" || fail "tavily" "$out"

out=$(WEB_UNLOCK_SEARCH_ORDER="serper,tavily" SERPER_API_KEY="$DUMMY" FAKE_SERPER_BODY="$T/serper.json" search "q"); rc=$?
[ $rc -eq 0 ] && [[ "$out" == *'"provider": "serper"'* ]] && [[ "$out" != *tavily* ]] \
  && pass "WEB_UNLOCK_SEARCH_ORDER puts serper before tavily" || fail "search order" "$out"
mkdir -p "$HOME/.config/web-unlock"; echo 'WEB_UNLOCK_SEARCH_ORDER="tavily"' > "$HOME/.config/web-unlock/env"
out=$(SERPER_API_KEY="$DUMMY" FAKE_SERPER_BODY="$T/serper.json" search "q"); rc=$?
[ $rc -eq 0 ] && [[ "$out" == *'"provider": "tavily"'* ]] && [[ "$out" != *serper* ]] \
  && pass "settings in the user folder's env file reach search.sh" || fail "env-file order" "$out"
rm -f "$HOME/.config/web-unlock/env"
out=$(WEB_UNLOCK_SEARCH_ORDER="bogus" search "q" 2>"$T/err"); rc=$?
[ $rc -eq 1 ] && grep -q "unknown provider bogus" "$T/err" && pass "unknown provider in WEB_UNLOCK_SEARCH_ORDER -> exit 1 with its name" || fail "bogus order" "$out $(cat "$T/err")"

echo "== user folder (WEB_UNLOCK_HOME, user-config.sh) =="
uc() { env PATH="$P" bash "$SK/bin/user-config.sh" "$@"; }
out=$(uc); rc=$?
[ $rc -eq 0 ] && [[ "$out" == *"home $HOME/.config/web-unlock (exists)"* ]] && [[ "$out" == *"sites $HOME/.config/web-unlock/sites.json"*"from your folder"* ]] \
  && cmp -s "$HOME/.config/web-unlock/sites.json" "$SK/sites.starter.json" && [[ "$out" != *"rules "* ]] \
  && pass "user-config.sh on first use seeds the registry quietly; no rules" || fail "uc empty" "$out"
U="$T/mine"
out=$(WEB_UNLOCK_HOME="$U" uc --init); rc=$?
[ $rc -eq 0 ] && cmp -s "$U/sites.json" "$SK/sites.starter.json" && [ -d "$U/references" ] && [[ "$out" == *"sites $U/sites.json"*"from your folder"* ]] \
  && pass "--init seeds WEB_UNLOCK_HOME/sites.json and references/" || fail "uc init" "$out"
echo '{"hosts":{"a.example":{},"b.example":{}}}' > "$U/sites.json"
WEB_UNLOCK_HOME="$U" uc --init >/dev/null
grep -q a.example "$U/sites.json" && pass "--init keeps an existing sites.json" || fail "uc init keeps"
printf '# my rules\n' > "$U/rules.md"; printf 'x\n' > "$U/references/search-doctrine.md"; printf 'y\n' > "$U/references/mine.md"
printf 'SECRET_THING=%s\n' "$DUMMY" > "$U/env"
out=$(WEB_UNLOCK_HOME="$U" uc)
[[ "$out" == *"rules $U/rules.md"* ]] && pass "rules files in the user folder are listed" || fail "uc rules" "$out"
[[ "$out" == *"reference $U/references/search-doctrine.md replaces $SK/references/search-doctrine.md"* ]] && [[ "$out" == *"reference $U/references/mine.md"$'\n'* || "$out" == *"reference $U/references/mine.md" ]] \
  && pass "user references: same name replaces the bundled one, others add" || fail "uc refs" "$out"
[[ "$out" == *"(2 hosts, from your folder;"* ]] && pass "registry from the user folder, with its host count" || fail "uc sites" "$out"
[[ "$out" == *"env $U/env (present)"* ]] && [[ "$out" != *"$DUMMY"* ]] && pass "env file reported present, values never printed" || fail "uc env" "$out"
out=$(WEB_UNLOCK_HOME="$U" WEB_UNLOCK_SITES="$T/sites.json" uc)
[[ "$out" == *"sites $T/sites.json (3 hosts, from WEB_UNLOCK_SITES;"* ]] && pass "WEB_UNLOCK_SITES wins over the user folder" || fail "uc env sites" "$out"
cp "$T/sites.json" "$U/sites.json"
out=$(WEB_UNLOCK_HOME="$U" FAKE_L0_BODY="$CF" FAKE_JINA_BODY="$RTE" fetch https://example.com/x)
[[ "$out" == *"fetch-unlock"* ]] && pass "fetch.sh reads the registry in WEB_UNLOCK_HOME" || fail "fetch home" "$out"
printf '%s=%s\n' BRIGHTDATA_API_KEY "$DUMMY" BRIGHTDATA_UNLOCKER_ZONE zone1 > "$U/env"
out=$(WEB_UNLOCK_HOME="$U" FAKE_L0_BODY="$CF" FAKE_JINA_BODY="$RTE" FAKE_BD_BODY="$GOODMD" fetch https://blocked.test/e); rc=$?
[ $rc -eq 0 ] && [[ "$out" == "OK L2-brightdata "* ]] && pass "fetch.sh loads keys from WEB_UNLOCK_HOME/env" || fail "fetch home env" "$out"
echo "CHROME_REAL_PORT=9222" > "$U/env"
out=$(WEB_UNLOCK_HOME="$U" CHROME_REAL_PROFILE="$T/prof" env PATH="$P" bash "$SK/bin/chrome-real.sh" status 2>&1)
[[ "$out" == *"WARNING: port 9222"* ]] && pass "chrome-real.sh reads CHROME_REAL_* from the user folder's env file" || fail "chrome env" "$out"
out=$(uc --bogus 2>&1); rc=$?
[ $rc -eq 1 ] && pass "user-config.sh unknown option -> exit 1" || fail "uc bogus" "$out"

echo "== review fixes =="
out=$("$NODE" "$SK/bin/blocked" "$S/generic-pt-error-page.html"); [[ "$out" == *"error-wall (generic)"* ]] && pass "Portuguese error wall on a non-Mercado Livre page is labelled generic" || fail "pt wall label generic" "$out"
out=$("$NODE" "$SK/bin/blocked" "$S/mercadolivre-pt-error-wall.txt"); [[ "$out" == *"mercadolibre-error-wall (mercadolibre)"* ]] && pass "the same wall on Mercado Livre keeps its Mercado Livre label" || fail "pt wall label ml" "$out"
# 3: a variable set by the caller wins over the env file
mkdir -p "$HOME/.config/web-unlock"; echo 'WEB_UNLOCK_SEARCH_ORDER="tavily"' > "$HOME/.config/web-unlock/env"
out=$(WEB_UNLOCK_SEARCH_ORDER="serper" SERPER_API_KEY="$DUMMY" FAKE_SERPER_BODY="$T/serper.json" search "q"); rc=$?
[ $rc -eq 0 ] && [[ "$out" == *'"provider": "serper"'* ]] && pass "explicit WEB_UNLOCK_SEARCH_ORDER beats the env file" || fail "explicit beats file" "$out"
rm -f "$HOME/.config/web-unlock/env"
# 9: WEB_UNLOCK_HOME inside the env file is ignored, so all lookups use one folder
H9="$T/h9"; mkdir -p "$H9" "$T/elsewhere"; echo '{"hosts":{"one.example":{}}}' > "$H9/sites.json"
printf 'WEB_UNLOCK_HOME=%s\n' "$T/elsewhere" > "$H9/env"
out=$(WEB_UNLOCK_HOME="$H9" env PATH="$P" bash "$SK/bin/user-config.sh")
[[ "$out" == *"home $H9 (exists)"* ]] && [[ "$out" == *"sites $H9/sites.json (1 hosts, from your folder;"* ]] \
  && pass "WEB_UNLOCK_HOME in the env file is ignored" || fail "home in env file" "$out"
# 6: host count matches what fetch.sh reads ("hosts" only) and skips "_" notes
echo '{"_doc":"x","hosts":{"_note":"y","a.example":{},"b.example":{}}}' > "$H9/sites.json"
out=$(WEB_UNLOCK_HOME="$H9" env PATH="$P" bash "$SK/bin/user-config.sh")
[[ "$out" == *"(2 hosts, from your folder;"* ]] && pass "host count skips _doc and _ notes" || fail "count notes" "$out"
echo '{"a.example":{},"b.example":{}}' > "$H9/sites.json"
out=$(WEB_UNLOCK_HOME="$H9" env PATH="$P" bash "$SK/bin/user-config.sh")
[[ "$out" == *"(2 hosts, from your folder;"* ]] && pass "a file without \"hosts\" is a flat host map, as fetch.sh and the guard read it" || fail "count no hosts" "$out"
# 7: --init failure is reported, not "seeded"
printf 'x' > "$T/afile"
out=$(WEB_UNLOCK_HOME="$(wp "$T/afile")/sub" env PATH="$P" bash "$SK/bin/user-config.sh" --init 2>&1); rc=$?
[ $rc -ne 0 ] && [[ "$out" != *seeded* ]] && pass "--init that cannot create the folder exits non-zero" || fail "init failure" "rc=$rc $out"
# 4: scripts work through a symlink (skipped where ln -s copies, as on Git Bash)
mkdir -p "$T/links"; ln -s "$SK/bin/user-config.sh" "$T/links/uc" 2>/dev/null; ln -s "$SK/bin/search.sh" "$T/links/search" 2>/dev/null
if [ -L "$T/links/uc" ]; then
  out=$(env PATH="$P" bash "$T/links/uc" 2>&1); rc=$?
  [ $rc -eq 0 ] && [[ "$out" == *"sites "* ]] && pass "user-config.sh runs through a symlink" || fail "symlink uc" "$out"
  echo 'WEB_UNLOCK_SEARCH_ORDER="tavily"' > "$HOME/.config/web-unlock/env"
  out=$(env PATH="$P" SERPER_API_KEY="$DUMMY" FAKE_SERPER_BODY="$T/serper.json" bash "$T/links/search" q 2>&1); rc=$?
  rm -f "$HOME/.config/web-unlock/env"
  [ $rc -eq 0 ] && [[ "$out" == *'"provider": "tavily"'* ]] && pass "search.sh through a symlink still loads the env file" || fail "symlink search" "$out"
else pass "symlink checks skipped: ln -s made a copy on this system"; fi
# 5: chrome-real.sh does not export the env file's API keys to the processes it starts
H5="$T/h5"; mkdir -p "$H5"; printf '%s=%s\n' SOME_API_KEY "$DUMMY" CHROME_REAL_PORT 9231 > "$H5/env"
printf '#!/bin/sh\nenv > "%s"\n' "$T/ps-env.txt" > "$SB/ps"; chmod +x "$SB/ps"; rm -f "$T/ps-env.txt"
out=$(WEB_UNLOCK_HOME="$H5" CHROME_REAL_APP="$T/fake-chrome" CHROME_REAL_PROFILE="$T/prof5" env PATH="$P" bash "$SK/bin/chrome-real.sh" status 2>&1)
if [ -f "$T/ps-env.txt" ]; then
  ! grep -q SOME_API_KEY "$T/ps-env.txt" && pass "chrome-real.sh keeps API keys out of child processes" || fail "chrome env leak" "key found in the child's environment"
else pass "chrome-real child-env check skipped: no process lookup on this OS ($out)"; fi
rm -f "$SB/ps"
# 5b: with the real ps, a profile that no browser uses is "not running" (the lookup used to match its own grep)
if command -v ps >/dev/null 2>&1 && ps axo pid=,command= >/dev/null 2>&1; then
  bad=0
  for _ in 1 2 3 4 5; do
    out=$(CHROME_REAL_APP="$T/fake-chrome" CHROME_REAL_PROFILE="$T/profile-of-nobody" CHROME_REAL_PORT=59123 bash "$SK/bin/chrome-real.sh" stop 2>&1)
    [ "$out" = "was not running" ] || bad=1
  done
  [ $bad = 0 ] && pass "chrome-real.sh does not take its own process lookup for a running Chrome" || fail "chrome pid self-match" "$out"
else pass "chrome-real self-match check skipped: no ps on this system"; fi
# 10: install.sh seeds the folder through user-config.sh --init (which also makes references/)
H10="$T/h10"; out=$(WEB_UNLOCK_HOME="$H10" CLAUDE_CONFIG_DIR="$T/cc10" bash "$ROOT/install.sh" 2>&1); rc=$?
[ $rc -eq 0 ] && [ -f "$H10/sites.json" ] && [ -d "$H10/references" ] && pass "install.sh seeds through user-config.sh --init" || fail "install init" "rc=$rc $out"
NONODE="/usr/bin:/bin"
if env PATH="$NONODE" bash -c "command -v node" >/dev/null 2>&1; then pass "install.sh without node: skipped (node is in $NONODE)"
else
  H11="$T/h11"; out=$(env PATH="$NONODE" WEB_UNLOCK_HOME="$H11" CLAUDE_CONFIG_DIR="$T/cc11" bash "$ROOT/install.sh" 2>&1); rc=$?
  [ $rc -eq 0 ] && [ -f "$T/cc11/skills/web-unlock/SKILL.md" ] && [[ "$out" == *"not created now"* ]] \
    && pass "install.sh without node still installs the skill and says the folder waits" || fail "install no node" "rc=$rc $out"
fi

echo "== first-run seed (lib/seed.mjs, SessionStart hook) =="
SEED="$SK/lib/seed.mjs"
# what the plugin's hook runs: node seed.mjs, with only HOME set
SH="$T/seedhome"; mkdir -p "$SH"
out=$(env -u WEB_UNLOCK_HOME HOME="$SH" USERPROFILE="$SH" "$NODE" "$SEED" </dev/null 2>&1); rc=$?
[ $rc -eq 0 ] && [ -z "$out" ] && cmp -s "$SH/.config/web-unlock/sites.json" "$SK/sites.starter.json" \
  && cmp -s "$SH/.config/web-unlock/env" "$SK/env.default" && [ -d "$SH/.config/web-unlock/references" ] \
  && pass "missing folder -> created with sites.json, env and references/, silently, exit 0" || fail "seed missing" "rc=$rc $out"
n=$("$PY" -c 'import json,sys; d=json.load(open(sys.argv[1],encoding="utf-8")); print(d["hosts"] == {} and "_doc" in d)' "$SH/.config/web-unlock/sites.json" 2>&1)
[ "$n" = "True" ] && pass "seeded sites.json is empty ({\"hosts\": {}} + _doc), not a copy of the bundled one" || fail "seed hosts key" "$n"
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) pass "env file mode check skipped on Windows";;
  *) m=$(ls -l "$SH/.config/web-unlock/env" | cut -c1-10)
     [ "$m" = "-rw-------" ] && pass "seeded env file is private (600)" || fail "env mode" "$m";; esac
# existing files: byte-identical afterwards
printf '{"hosts":{"mine.example":{"route":"http"}}}\n' > "$SH/.config/web-unlock/sites.json"
printf 'EXA_API_KEY=%s\n' "$DUMMY" > "$SH/.config/web-unlock/env"
cp "$SH/.config/web-unlock/sites.json" "$T/sites.before"; cp "$SH/.config/web-unlock/env" "$T/env.before"
out=$(env -u WEB_UNLOCK_HOME HOME="$SH" USERPROFILE="$SH" "$NODE" "$SEED" 2>&1); rc=$?
[ $rc -eq 0 ] && [ -z "$out" ] && cmp -s "$T/sites.before" "$SH/.config/web-unlock/sites.json" && cmp -s "$T/env.before" "$SH/.config/web-unlock/env" \
  && pass "existing sites.json and env are byte-identical after a seed" || fail "seed keeps" "rc=$rc $out"
out=$(WEB_UNLOCK_HOME="$SH/.config/web-unlock" uc --init); rc=$?
[ $rc -eq 0 ] && [[ "$out" == *"kept "*"sites.json"* ]] && cmp -s "$T/sites.before" "$SH/.config/web-unlock/sites.json" \
  && pass "--init says kept and leaves the file alone" || fail "init kept" "$out"
# env overrides: WEB_UNLOCK_HOME, WEB_UNLOCK_ENV, WEB_UNLOCK_SITES
SH2="$T/seedhome2"; mkdir -p "$SH2"
out=$(HOME="$SH2" USERPROFILE="$SH2" WEB_UNLOCK_HOME="$T/override" "$NODE" "$SEED" 2>&1); rc=$?
[ $rc -eq 0 ] && [ -f "$T/override/sites.json" ] && [ -f "$T/override/env" ] && [ ! -e "$SH2/.config" ] \
  && pass "WEB_UNLOCK_HOME is respected (nothing under ~/.config)" || fail "seed override" "rc=$rc $out"
out=$(HOME="$SH2" USERPROFILE="$SH2" WEB_UNLOCK_HOME="$T/override2" WEB_UNLOCK_ENV="$T/keys/web.env" WEB_UNLOCK_SITES="$T/sites.json" "$NODE" "$SEED" 2>&1); rc=$?
[ $rc -eq 0 ] && [ -f "$T/keys/web.env" ] && [ ! -e "$T/override2/env" ] && [ ! -e "$T/override2/sites.json" ] \
  && pass "WEB_UNLOCK_ENV and WEB_UNLOCK_SITES are respected" || fail "seed env/sites override" "rc=$rc $out"
# cannot write: never crashes, never prints
printf 'x' > "$T/afile2"
out=$(HOME="$SH2" USERPROFILE="$SH2" WEB_UNLOCK_HOME="$(wp "$T/afile2")/sub" "$NODE" "$SEED" 2>&1); rc=$?
[ $rc -eq 0 ] && [ -z "$out" ] && pass "folder that cannot be created (path under a file) -> exit 0, no output" || fail "seed unwritable" "rc=$rc $out"
mkdir -p "$T/rel"
out=$(cd "$T/rel" && HOME="$SH2" USERPROFILE="$SH2" WEB_UNLOCK_HOME="relhome" "$NODE" "$SEED" 2>&1); rc=$?
[ $rc -eq 0 ] && [ -z "$out" ] && [ -z "$(ls -A "$T/rel")" ] && pass "relative WEB_UNLOCK_HOME is not seeded into the current folder" || fail "seed relative" "rc=$rc $out $(ls -A "$T/rel")"
mkdir -p "$T/ro"; chmod 555 "$T/ro"
if [ -w "$T/ro" ]; then pass "read-only folder check skipped: this user can write anyway (root or Windows)"
else
  out=$(HOME="$SH2" USERPROFILE="$SH2" WEB_UNLOCK_HOME="$T/ro/web-unlock" "$NODE" "$SEED" 2>&1); rc=$?
  [ $rc -eq 0 ] && [ -z "$out" ] && [ ! -e "$T/ro/web-unlock" ] && pass "read-only parent folder -> exit 0, no output" || fail "seed readonly" "rc=$rc $out"
fi
chmod 755 "$T/ro"
# WEB_UNLOCK_SITES set in the env file (not the environment) also means "no copy here", as user-config.sh reads it
SH3="$T/seedhome3"; mkdir -p "$SH3/.config/web-unlock"
printf '# mine\nexport WEB_UNLOCK_SITES="$HOME/shared/sites.json"\n' > "$SH3/.config/web-unlock/env"
out=$(env -u WEB_UNLOCK_HOME -u WEB_UNLOCK_SITES HOME="$SH3" USERPROFILE="$SH3" "$NODE" "$SEED" 2>&1); rc=$?
[ $rc -eq 0 ] && [ ! -e "$SH3/.config/web-unlock/sites.json" ] && [ -d "$SH3/.config/web-unlock/references" ] \
  && pass "WEB_UNLOCK_SITES in the env file: the hook does not copy the registry" || fail "seed sites from env file" "rc=$rc $out $(ls -A "$SH3/.config/web-unlock")"
# a write that fails half-way (disk full) leaves no empty file behind; the next run seeds it whole
SH4="$T/seedhome4"; mkdir -p "$SH4"
FAILW="data:text/javascript,import fs from 'node:fs'; fs.writeSync = () => { throw Object.assign(new Error('no space'), { code: 'ENOSPC' }); };"
out=$(env -u WEB_UNLOCK_HOME HOME="$SH4" USERPROFILE="$SH4" "$NODE" --import "$FAILW" "$SEED" 2>&1); rc=$?
[ $rc -eq 0 ] && [ ! -e "$SH4/.config/web-unlock/sites.json" ] && [ ! -e "$SH4/.config/web-unlock/env" ] \
  && pass "failed write -> no empty sites.json or env left behind" || fail "seed failed write" "rc=$rc $out $(ls -A "$SH4/.config/web-unlock" 2>&1)"
env -u WEB_UNLOCK_HOME HOME="$SH4" USERPROFILE="$SH4" "$NODE" "$SEED"
cmp -s "$SH4/.config/web-unlock/env" "$SK/env.default" && cmp -s "$SH4/.config/web-unlock/sites.json" "$SK/sites.starter.json" \
  && pass "and the next run seeds both files whole" || fail "seed after failed write"
# the seeded folder behaves exactly like no folder at all (only the registry's path in messages differs)
NOF="$T/nofolder"; SEEDED="$T/seededfolder"
WEB_UNLOCK_HOME="$SEEDED" "$NODE" "$SEED"
same=1; diffs=""
[ -f "$SEEDED/sites.json" ] && [ -f "$SEEDED/env" ] || { same=0; diffs="seed did not write $SEEDED"; }
for u in https://www.reddit.com/r/x https://blocked.example.com/z https://youtube.com/watch?v=1; do
  a=$(WEB_UNLOCK_HOME="$NOF" FAKE_L0_BODY="$CF" FAKE_JINA_BODY="$RTE" fetch "$u" 2>&1 | sed -e "s#$NOF#H#g" -e "s#$SK/sites.json#H/sites.json#g")
  b=$(WEB_UNLOCK_HOME="$SEEDED" FAKE_L0_BODY="$CF" FAKE_JINA_BODY="$RTE" fetch "$u" 2>&1 | sed "s#$SEEDED#H#g")
  [ "$a" = "$b" ] || { same=0; diffs="$diffs | fetch $u: [$a] vs [$b]"; }
done
a=$(WEB_UNLOCK_HOME="$NOF" SERPER_API_KEY="$DUMMY" FAKE_SERPER_BODY="$T/serper.json" search "q" 2>&1)
b=$(WEB_UNLOCK_HOME="$SEEDED" SERPER_API_KEY="$DUMMY" FAKE_SERPER_BODY="$T/serper.json" search "q" 2>&1)
[ "$a" = "$b" ] || { same=0; diffs="$diffs | search: [$a] vs [$b]"; }
a=$(WEB_UNLOCK_HOME="$NOF" CHROME_REAL_PORT=1 CHROME_REAL_PROFILE="$T/prof" env PATH="$P" bash "$SK/bin/chrome-real.sh" status 2>&1)
b=$(WEB_UNLOCK_HOME="$SEEDED" CHROME_REAL_PORT=1 CHROME_REAL_PROFILE="$T/prof" env PATH="$P" bash "$SK/bin/chrome-real.sh" status 2>&1)
[ "$a" = "$b" ] || { same=0; diffs="$diffs | chrome-real: [$a] vs [$b]"; }
[ ! -e "$NOF" ] || { same=0; diffs="$diffs | fetch/search created $NOF"; }
[ $same = 1 ] && pass "seeded defaults behave like no folder (fetch.sh on registry hosts, search.sh, chrome-real.sh)" || fail "seeded = none" "$diffs"
# the plugin hook points at this script
"$PY" - "$ROOT/hooks/hooks.json" "$ROOT" <<'PYEOF' && pass "hooks/hooks.json: a SessionStart hook runs lib/seed.mjs with node" || fail "hooks.json"
import json, os, sys
h = json.load(open(sys.argv[1], encoding="utf-8"))["hooks"]["SessionStart"][0]["hooks"][0]
assert h["command"] == "node", h
f = h["args"][0].replace("${CLAUDE_PLUGIN_ROOT}", sys.argv[2])
assert os.path.isfile(f), f
PYEOF

echo "== registry overlay (bundled first, yours on top) =="
# a fake bundled skill so a "plugin update" can be simulated without touching the real one
FS="$T/fakeskill"; mkdir -p "$FS"; cp -R "$SK/bin" "$SK/lib" "$FS/"
printf '{"hosts":{"bundled.example":{"route":"http","how":"bundled-only"},"both.example":{"route":"http","how":"bundled-entry","tags":["x"]},"alias.example":{"alias_of":"bundled.example"}}}\n' > "$FS/sites.json"
cp "$SK/sites.starter.json" "$FS/"
OV="$T/overlay"; mkdir -p "$OV"
printf '{"hosts":{"mine.example":{"route":"browser-real","how":"user-only"},"both.example":{"route":"api","how":"user-entry"}}}\n' > "$OV/sites.json"
lk() { WEB_UNLOCK_HOME="$OV" env PATH="$P" bash "$FS/bin/sites" "$1" 2>&1; }
[[ "$(lk mine.example)" == *'"how": "user-only"'* ]] && pass "overlay: a host only in your file is found" || fail "overlay user-only" "$(lk mine.example)"
[[ "$(lk https://www.bundled.example/x)" == *'"how": "bundled-only"'* ]] && pass "overlay: a host only in the bundled file is found" || fail "overlay bundled-only" "$(lk bundled.example)"
out=$(lk both.example)
[[ "$out" == *'"how": "user-entry"'* ]] && [[ "$out" != *bundled-entry* ]] && [[ "$out" != *tags* ]] \
  && pass "overlay: same host in both -> your whole entry wins (no bundled fields mixed in)" || fail "overlay both" "$out"
[[ "$(lk alias.example)" == *'"how": "bundled-only"'* ]] && pass "overlay: alias_of is followed in the merged view" || fail "overlay alias" "$(lk alias.example)"
out=$(WEB_UNLOCK_HOME="$OV" FAKE_L0_BODY="$CF" FAKE_JINA_BODY="$RTE" env PATH="$P" bash "$FS/bin/fetch.sh" https://bundled.example/x 2>&1)
[[ "$out" == *"known route for bundled.example -> http: bundled-only"* ]] && pass "fetch.sh reads the merged view (bundled host)" || fail "fetch overlay bundled" "$out"
out=$(WEB_UNLOCK_HOME="$OV" FAKE_L0_BODY="$CF" FAKE_JINA_BODY="$RTE" env PATH="$P" bash "$FS/bin/fetch.sh" https://both.example/x 2>&1)
[[ "$out" == *"-> api: user-entry"* ]] && pass "fetch.sh reads the merged view (your entry wins)" || fail "fetch overlay both" "$out"
# a seeded user gets a host the next plugin version adds to the bundled file
SU="$T/seeduser"; WEB_UNLOCK_HOME="$SU" "$NODE" "$FS/lib/seed.mjs"
cmp -s "$SU/sites.json" "$FS/sites.starter.json" || fail "overlay seed" "not seeded from the starter"
printf '{"hosts":{"new-in-update.example":{"route":"fetch-render","how":"added later"}}}\n' > "$FS/sites.json"
[[ "$(WEB_UNLOCK_HOME="$SU" env PATH="$P" bash "$FS/bin/sites" new-in-update.example)" == *'"how": "added later"'* ]] \
  && pass "overlay: a bundled update reaches a seeded user" || fail "overlay update" "$(WEB_UNLOCK_HOME="$SU" bash "$FS/bin/sites" new-in-update.example)"
# an old user file that is a full copy of the bundled registry keeps working: it overrides what it lists
cp "$SK/sites.json" "$T/fullcopy.json"
first=$("$PY" -c 'import json,sys; print(next(k for k in json.load(open(sys.argv[1],encoding="utf-8"))["hosts"] if not k.startswith("_")))' "$SK/sites.json")
out=$(WEB_UNLOCK_SITES="$T/fullcopy.json" env PATH="$P" bash "$SK/bin/sites" "$first")
[ -n "$out" ] && pass "overlay: a full copy of the bundled file still works ($first found)" || fail "overlay full copy" "$out"
out=$(WEB_UNLOCK_HOME="$OV" env PATH="$P" bash "$FS/bin/user-config.sh")
[[ "$out" == *"(2 hosts, from your folder; 3 with the bundled ones)"* ]] && pass "user-config.sh shows your hosts and the merged count" || fail "overlay count" "$out"

echo "== chrome-real.sh / cdp.mjs =="
out=$(env PATH="$P" CHROME_REAL_PORT=1 CHROME_REAL_PROFILE="$T/prof" bash "$SK/bin/chrome-real.sh" status 2>&1)
[[ "$out" == stopped* ]] && pass "status with nothing running -> stopped" || fail "status" "$out"
case "$(uname -s)" in
  Darwin) REALP="$HOME/Library/Application Support/Google/Chrome/Default";;
  Linux) REALP="$HOME/.config/google-chrome/Default";;
  *) REALP="";;
esac
if [ -n "$REALP" ]; then
  out=$(env PATH="$P" CHROME_REAL_PROFILE="$REALP" bash "$SK/bin/chrome-real.sh" start 2>&1); rc=$?
  [ $rc -eq 2 ] && [[ "$out" == REFUSED* ]] && pass "refuses to use a real Chrome profile" || fail "real profile refusal" "$out"
else
  out=$(env PATH="$P" CHROME_REAL_PROFILE="$T/prof" bash "$SK/bin/chrome-real.sh" start 2>&1); rc=$?
  [ $rc -eq 3 ] && [[ "$out" == UNSUPPORTED* ]] && pass "Windows: start says unsupported, exit 3" || fail "windows unsupported" "$out"
fi
out=$(env PATH="$P" bash "$SK/bin/chrome-real.sh" bogus 2>&1); rc=$?
[ $rc -eq 2 ] && pass "unknown subcommand -> usage, exit 2" || fail "bogus subcommand" "$out"
out=$(cd "$T" && env PATH="$P" PLAYWRIGHT_CORE_PATH="$T/none/" "$NODE" "$SK/bin/cdp.mjs" https://a.example --port 1 2>&1); rc=$?
{ [ $rc -eq 3 ] || [ $rc -eq 4 ]; } && pass "cdp.mjs exits cleanly with no playwright or no Chrome (rc=$rc)" || fail "cdp.mjs" "$out"
# cdp.mjs takes CHROME_REAL_PORT and PLAYWRIGHT_CORE_PATH from your env file too, like chrome-real.sh does
mkdir -p "$T/fakepw/node_modules/playwright-core" "$T/cdpenv"
printf 'module.exports = { chromium: { connectOverCDP() { throw new Error("not reached"); } } };\n' > "$T/fakepw/node_modules/playwright-core/index.js"
printf 'CHROME_REAL_PORT=1\nPLAYWRIGHT_CORE_PATH="%s/"  # fake\n' "$(wp "$T/fakepw")" > "$T/cdpenv/env"
out=$(cd "$T" && env -u CHROME_REAL_PORT -u PLAYWRIGHT_CORE_PATH PATH="$P" WEB_UNLOCK_HOME="$(wp "$T/cdpenv")" "$NODE" "$SK/bin/cdp.mjs" https://a.example 2>&1); rc=$?
[ $rc -eq 4 ] && [[ "$out" == *"on port 1:"* ]] && pass "cdp.mjs reads CHROME_REAL_PORT and PLAYWRIGHT_CORE_PATH from the env file" || fail "cdp env file" "rc=$rc $out"
out=$(cd "$T" && env PATH="$P" CHROME_REAL_PORT=2 WEB_UNLOCK_HOME="$(wp "$T/cdpenv")" "$NODE" "$SK/bin/cdp.mjs" https://a.example 2>&1); rc=$?
[[ "$out" == *"on port 2:"* ]] && pass "cdp.mjs: the environment wins over the env file" || fail "cdp env wins" "rc=$rc $out"

echo "== audit fixes, round 2 =="
# WU-01: a network failure on a URL fetched before must not serve the old copy as OK
out=$(FAKE_L0_BODY="$GOOD" fetch https://again.example.com/p); rc=$?
out=$(FAKE_L0_FAIL=1 FAKE_JINA_BODY="$RTE" fetch https://again.example.com/p); rc=$?
[ $rc -ne 0 ] && [[ "$out" != OK* ]] && pass "WU-01: curl failure does not serve the previous run's file" || fail "WU-01 stale L0 file" "rc=$rc $out"
# WU-04: a symlink planted under a predictable name in the temp folder is not written through
VICTIM="$T/victim.txt"; echo "precious" > "$VICTIM"
SLUGP="planted-example-com-x"
ln -s "$VICTIM" "$WEB_UNLOCK_TMP/$SLUGP.L0.html" 2>/dev/null
if [ -L "$WEB_UNLOCK_TMP/$SLUGP.L0.html" ]; then
  out=$(FAKE_L0_BODY="$GOOD" fetch https://planted.example.com/x -o "$T/out/planted.html"); rc=$?
  [ "$(cat "$VICTIM")" = precious ] && pass "WU-04: work files are not written through a planted symlink" || fail "WU-04 symlink" "victim overwritten: $out"
else pass "WU-04 symlink check skipped: no symlinks on this system"; fi
mkdir -p "$T/realtmp"; ln -s "$T/realtmp" "$T/linktmp" 2>/dev/null
if [ -L "$T/linktmp" ]; then
  out=$(WEB_UNLOCK_TMP="$T/linktmp" FAKE_L0_BODY="$GOOD" fetch https://x.example.com/y 2>&1); rc=$?
  [ $rc -eq 1 ] && [[ "$out" == *REFUSED* ]] && pass "WU-04: a temp folder that is a symlink is refused" || fail "WU-04 tmp symlink" "rc=$rc $out"
else pass "WU-04 temp-symlink check skipped: no symlinks on this system"; fi
# WU-09: an error page (404/500) with a body is not OK at L0
out=$(FAKE_L0_BODY="$GOOD" FAKE_L0_CODE=404 FAKE_JINA_BODY="$RTE" fetch https://err.example.com/missing); rc=$?
[[ "$out" != "OK L0-curl"* ]] && pass "WU-09: HTTP 404 with a body is not OK L0" || fail "WU-09 404" "$out"
out=$(FAKE_L0_BODY="$GOOD" FAKE_L0_CODE=502 FAKE_JINA_BODY="$RTE" fetch https://err.example.com/bad); rc=$?
[[ "$out" != "OK L0-curl"* ]] && pass "WU-09: HTTP 502 with a body is not OK L0" || fail "WU-09 502" "$out"
out=$("$NODE" "$SK/bin/blocked" "$GOOD" --status 404 --expect-page); rc=$?
[ $rc -eq 2 ] && [[ "$out" == *http-404* ]] && pass "WU-09: blocked --status 404 --expect-page is not a page" || fail "WU-09 detector" "$out"
# WU-10: L0 writes to the -o file asked for
out=$(FAKE_L0_BODY="$GOOD" fetch https://docs.example.com/o -o "$T/out/saida.txt"); rc=$?
[ $rc -eq 0 ] && [[ "$out" == "OK L0-curl $T/out/saida.txt "* ]] && cmp -s "$T/out/saida.txt" "$GOOD" \
  && pass "WU-10: L0 honors -o exactly" || fail "WU-10 -o name" "$out"
# WU-07: a failed copy to the destination is not OK
echo "not a folder" > "$T/afile"
out=$(FAKE_L0_BODY="$GOOD" fetch https://docs.example.com/c -o "$T/afile/x.html" 2>&1); rc=$?
[ $rc -ne 0 ] && [[ "$out" != OK* ]] && pass "WU-07: an unwritable -o is reported, not OK" || fail "WU-07 cp" "rc=$rc $out"
# WU-08: the Bright Data body is valid JSON even with quotes in the URL
printf '%s=%s\n' BRIGHTDATA_API_KEY "$DUMMY" BRIGHTDATA_UNLOCKER_ZONE "'zo\"ne'" > "$HOME/.config/web-unlock/env"   # the file is shell: quoted
: > "$FAKE_LOG"
out=$(FAKE_L0_BODY="$CF" FAKE_JINA_BODY="$RTE" FAKE_BD_BODY="$GOODMD" fetch 'https://q.example.com/a"b')   # no backslash: Git Bash rewrites it in arguments; rc=$?
body=$(grep '^https://api.brightdata.com' "$FAKE_LOG" | sed 's/^[^|]*| //')
chk=$(printf '%s' "$body" | "$NODE" -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const j=JSON.parse(s);console.log(j.url+"|"+j.zone)}catch(e){console.log("BAD "+e.message)}})')
[ "$chk" = 'https://q.example.com/a"b|zo"ne' ] && pass "WU-08: Bright Data JSON escapes the URL and zone" || fail "WU-08 json" "$chk / $body"
rm -f "$HOME/.config/web-unlock/env"
# WU-11: search.sh -n must be a number
out=$(EXA_API_KEY="$DUMMY" FAKE_EXA_BODY="$S/ok-search-json.txt" search "q" -n '1,"x":2' --provider exa 2>&1); rc=$?
[ $rc -eq 1 ] && [[ "$out" == *"-n"* ]] && pass "WU-11: search.sh rejects a non-numeric -n" || fail "WU-11 -n" "rc=$rc $out"
# WU-02: PLAYWRIGHT_CORE_PATH without a trailing slash still finds the package
mkdir -p "$T/pw2/node_modules/playwright-core" "$T/noenv"
printf 'process.stderr.write("FAKEPW2-LOADED\\n"); module.exports = { chromium: {} };\n' > "$T/pw2/node_modules/playwright-core/index.js"
out=$(cd "$T/noenv" && env PATH="$P" CHROME_REAL_PORT=1 WEB_UNLOCK_HOME="$(wp "$T/noenv")" PLAYWRIGHT_CORE_PATH="$(wp "$T/pw2")" "$NODE" "$SK/bin/cdp.mjs" https://a.example 2>&1); rc=$?
[[ "$out" == *FAKEPW2-LOADED* ]] && pass "WU-02: PLAYWRIGHT_CORE_PATH works without a trailing slash" || fail "WU-02 no slash" "rc=$rc $out"
# WU-06: a playwright-core in the current folder does not win over the one next to the skill
mkdir -p "$T/cdpcopy/node_modules/playwright-core" "$T/cwdpw/node_modules/playwright-core"
cp -R "$SK" "$T/cdpcopy/skill"
printf 'process.stderr.write("BUNDLED-PW\\n"); module.exports = { chromium: {} };\n' > "$T/cdpcopy/node_modules/playwright-core/index.js"
printf 'process.stderr.write("CWD-PW\\n"); module.exports = { chromium: {} };\n' > "$T/cwdpw/node_modules/playwright-core/index.js"
out=$(cd "$T/cwdpw" && env -u PLAYWRIGHT_CORE_PATH PATH="$P" CHROME_REAL_PORT=1 WEB_UNLOCK_HOME="$(wp "$T/noenv")" "$NODE" "$T/cdpcopy/skill/bin/cdp.mjs" https://a.example 2>&1); rc=$?
[[ "$out" == *BUNDLED-PW* ]] && [[ "$out" != *CWD-PW* ]] && pass "WU-06: cdp.mjs does not load playwright from the current folder first" || fail "WU-06 cwd first" "rc=$rc $out"
# WU-12: the tab is closed when navigation fails
mkdir -p "$T/pw12/node_modules/playwright-core"
cat > "$T/pw12/node_modules/playwright-core/index.js" <<'PWEOF'
const fs = require('fs');
const tag = () => fs.readFileSync(process.env.FAKE_TAG_FILE, 'utf8');
const page = { url: () => tag(), goto: async () => { throw new Error('fake navigation timeout'); },
  close: async () => { fs.writeFileSync(process.env.FAKE_CLOSED_FILE, 'closed'); } };
module.exports = { chromium: { connectOverCDP: async () => ({ contexts: () => [{ pages: () => [page] }], close: async () => {} }) } };
PWEOF
rm -f "$T/cdp.port" "$T/cdp.tag" "$T/cdp.closed"
"$NODE" "$ROOT/tests/fake-cdp.mjs" "$(wp "$T/cdp.port")" "$(wp "$T/cdp.tag")" & CDPPID=$!
for _ in $(seq 1 50); do [ -s "$T/cdp.port" ] && break; sleep 0.1; done
out=$(cd "$T/noenv" && env PATH="$P" WEB_UNLOCK_HOME="$(wp "$T/noenv")" PLAYWRIGHT_CORE_PATH="$(wp "$T/pw12")/" FAKE_TAG_FILE="$(wp "$T/cdp.tag")" FAKE_CLOSED_FILE="$(wp "$T/cdp.closed")" "$NODE" "$SK/bin/cdp.mjs" https://a.example --port "$(cat "$T/cdp.port" 2>/dev/null)" 2>&1); rc=$?
kill $CDPPID 2>/dev/null; wait $CDPPID 2>/dev/null
[ $rc -ne 0 ] && [[ "$out" == *"fake navigation timeout"* ]] && [ -f "$T/cdp.closed" ] && pass "WU-12: cdp.mjs closes its tab when navigation fails" || fail "WU-12 tab left open" "rc=$rc closed=$([ -f "$T/cdp.closed" ] && echo yes || echo no) $out"
# WU-03: start --fresh refuses a folder this script did not create
case "$(uname -s)" in
  Darwin) mkdir -p "$T/Fake.app/Contents/MacOS"; printf '#!/bin/sh\nexit 0\n' > "$T/Fake.app/Contents/MacOS/Fake"; chmod +x "$T/Fake.app/Contents/MacOS/Fake"; FAKEAPP="$T/Fake.app";;
  Linux) printf '#!/bin/sh\nexit 0\n' > "$T/fakechrome"; chmod +x "$T/fakechrome"; FAKEAPP="$T/fakechrome";;
  *) FAKEAPP="";;
esac
if [ -n "$FAKEAPP" ]; then
  mkdir -p "$T/precious"; echo keep > "$T/precious/notes.txt"
  out=$(env PATH="$P" CHROME_REAL_APP="$FAKEAPP" CHROME_REAL_PORT=1 CHROME_REAL_PROFILE="$T/precious" bash "$SK/bin/chrome-real.sh" start --fresh 2>&1); rc=$?
  [ $rc -ne 0 ] && [[ "$out" == REFUSED* ]] && [ -f "$T/precious/notes.txt" ] && pass "WU-03: start --fresh refuses a folder chrome-real.sh did not create" || fail "WU-03 fresh" "rc=$rc $out"
else pass "WU-03 check skipped: chrome-real.sh start is not supported on this OS"; fi
# WU-05: uninstall refuses a folder install.sh did not create
mkdir -p "$T/cc5/skills/web-unlock"; echo mine > "$T/cc5/skills/web-unlock/SKILL.md"
out=$(CLAUDE_CONFIG_DIR="$T/cc5" bash "$ROOT/install.sh" --uninstall 2>&1); rc=$?
[ $rc -ne 0 ] && [ -f "$T/cc5/skills/web-unlock/SKILL.md" ] && pass "WU-05: uninstall keeps a copy it did not install" || fail "WU-05 uninstall" "rc=$rc $out"

echo "== install.sh =="
out=$(bash "$ROOT/install.sh" --dry-run 2>&1); rc=$?
[ $rc -eq 0 ] && [[ "$out" == *"/.claude/skills/web-unlock"* ]] && [ ! -e "$HOME/.claude/skills/web-unlock" ] \
  && pass "install --dry-run prints the plan and writes nothing" || fail "install dry-run" "$out"
bash "$ROOT/install.sh" >/dev/null 2>&1
[ -f "$HOME/.claude/skills/web-unlock/SKILL.md" ] && [ -f "$HOME/.claude/skills/web-unlock/lib/detect.mjs" ] \
  && [ -f "$HOME/.config/web-unlock/sites.json" ] && pass "install copies the skill and seeds ~/.config/web-unlock/sites.json" || fail "install"
echo '{"hosts":{"mine.example":{"route":"http"}}}' > "$HOME/.config/web-unlock/sites.json"
bash "$ROOT/install.sh" >/dev/null 2>&1
grep -q mine.example "$HOME/.config/web-unlock/sites.json" && pass "reinstall keeps the user's sites.json" || fail "keep sites.json"
bash "$ROOT/install.sh" --uninstall >/dev/null 2>&1
[ ! -e "$HOME/.claude/skills/web-unlock" ] && [ -f "$HOME/.config/web-unlock/sites.json" ] \
  && pass "uninstall removes the skill copy and keeps the user's registry" || fail "uninstall"

echo
echo "$PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
