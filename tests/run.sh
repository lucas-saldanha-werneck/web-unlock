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
  *) body="${FAKE_L0_BODY:-}"; code="${FAKE_L0_CODE:-200}";;
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
  && cmp -s "$HOME/.config/web-unlock/sites.json" "$SK/sites.json" && [[ "$out" != *"rules "* ]] \
  && pass "user-config.sh on first use seeds the registry quietly; no rules" || fail "uc empty" "$out"
U="$T/mine"
out=$(WEB_UNLOCK_HOME="$U" uc --init); rc=$?
[ $rc -eq 0 ] && cmp -s "$U/sites.json" "$SK/sites.json" && [ -d "$U/references" ] && [[ "$out" == *"sites $U/sites.json"*"from your folder"* ]] \
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
[[ "$out" == *"(2 hosts, from your folder)"* ]] && pass "registry from the user folder, with its host count" || fail "uc sites" "$out"
[[ "$out" == *"env $U/env (present)"* ]] && [[ "$out" != *"$DUMMY"* ]] && pass "env file reported present, values never printed" || fail "uc env" "$out"
out=$(WEB_UNLOCK_HOME="$U" WEB_UNLOCK_SITES="$T/sites.json" uc)
[[ "$out" == *"sites $T/sites.json (3 hosts, from WEB_UNLOCK_SITES)"* ]] && pass "WEB_UNLOCK_SITES wins over the user folder" || fail "uc env sites" "$out"
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
[[ "$out" == *"home $H9 (exists)"* ]] && [[ "$out" == *"sites $H9/sites.json (1 hosts, from your folder)"* ]] \
  && pass "WEB_UNLOCK_HOME in the env file is ignored" || fail "home in env file" "$out"
# 6: host count matches what fetch.sh reads ("hosts" only) and skips "_" notes
echo '{"_doc":"x","hosts":{"_note":"y","a.example":{},"b.example":{}}}' > "$H9/sites.json"
out=$(WEB_UNLOCK_HOME="$H9" env PATH="$P" bash "$SK/bin/user-config.sh")
[[ "$out" == *"(2 hosts, from your folder)"* ]] && pass "host count skips _doc and _ notes" || fail "count notes" "$out"
echo '{"a.example":{},"b.example":{}}' > "$H9/sites.json"
out=$(WEB_UNLOCK_HOME="$H9" env PATH="$P" bash "$SK/bin/user-config.sh")
[[ "$out" == *"(0 hosts, from your folder)"* ]] && pass "a file without \"hosts\" counts 0, as fetch.sh reads it" || fail "count no hosts" "$out"
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
# 10: install.sh seeds the folder through user-config.sh --init (which also makes references/)
H10="$T/h10"; out=$(WEB_UNLOCK_HOME="$H10" CLAUDE_CONFIG_DIR="$T/cc10" bash "$ROOT/install.sh" 2>&1); rc=$?
[ $rc -eq 0 ] && [ -f "$H10/sites.json" ] && [ -d "$H10/references" ] && pass "install.sh seeds through user-config.sh --init" || fail "install init" "rc=$rc $out"

echo "== first-run seed (lib/seed.mjs, SessionStart hook) =="
SEED="$SK/lib/seed.mjs"
# what the plugin's hook runs: node seed.mjs, with only HOME set
SH="$T/seedhome"; mkdir -p "$SH"
out=$(env -u WEB_UNLOCK_HOME HOME="$SH" USERPROFILE="$SH" "$NODE" "$SEED" </dev/null 2>&1); rc=$?
[ $rc -eq 0 ] && [ -z "$out" ] && cmp -s "$SH/.config/web-unlock/sites.json" "$SK/sites.json" \
  && cmp -s "$SH/.config/web-unlock/env" "$SK/env.default" && [ -d "$SH/.config/web-unlock/references" ] \
  && pass "missing folder -> created with sites.json, env and references/, silently, exit 0" || fail "seed missing" "rc=$rc $out"
n=$("$PY" -c 'import json,sys; d=json.load(open(sys.argv[1],encoding="utf-8")); print(len([k for k in d["hosts"] if not k.startswith("_")]))' "$SH/.config/web-unlock/sites.json" 2>&1)
nb=$("$PY" -c 'import json,sys; d=json.load(open(sys.argv[1],encoding="utf-8")); print(len([k for k in d["hosts"] if not k.startswith("_")]))' "$SK/sites.json" 2>&1)
[ "$n" = "$nb" ] && [ "$n" -gt 0 ] && pass "seeded sites.json keeps the hosts under \"hosts\" ($n hosts)" || fail "seed hosts key" "$n vs $nb"
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
