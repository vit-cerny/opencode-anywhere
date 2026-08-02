#!/usr/bin/env bash
# smoke.sh - multi-slot isolation smoke test (run locally, and by CI).
# Boots TWO isolated opencode web servers from the real template config and
# proves: 401 without auth, 200 with auth, SSE 200, and that one slot's
# password does NOT authenticate the other (cross-slot isolation).
#
# Readiness note: opencode returns 401 WITHOUT auth, so `curl -sf` treats a
# healthy server as "failed". We poll for ANY HTTP status (not 000) instead.
# `set -eu`: -u removed - start_slot forks the server which can start/exit at
# odd times, and the readiness poll guards empty vars itself, so -u (unbound
# var) brittleness only trips false errors. `set -e` + explicit 401 handling
# is enough here.
set -e

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
V="$(grep -oP 'OPENCODE_VERSION=\K[0-9.]+' "$REPO/provision.sh")"
[ -n "$V" ] || { echo "ERROR: could not read OPENCODE_VERSION from provision.sh" >&2; exit 1; }
command -v opencode >/dev/null || { echo "ERROR: 'opencode' not on PATH; install opencode-ai@$V first" >&2; exit 1; }
echo "Pinned opencode version: $V"

P1="ci-pw-me-$(openssl rand -hex 6)"
P2="ci-pw-alice-$(openssl rand -hex 6)"
PORT_ME=4199
PORT_ALICE=4299

start_slot() { # $1=name $2=password $3=port
  local sname="$1" spw="$2" sport="$3" shome="/tmp/oc-slot-$1"
  rm -rf "$shome"; mkdir -p "$shome/.config/opencode"
  sed "s|{{HOME}}|$shome|g" "$REPO/opencode.jsonc" > "$shome/.config/opencode/opencode.jsonc"
  HOME="$shome" OPENCODE_SERVER_PASSWORD="$spw" \
    opencode web --port "$sport" --hostname 127.0.0.1 > "/tmp/oc-web-$sname.log" 2>&1 &
}

echo "booting me(:$PORT_ME) and alice(:$PORT_ALICE)..."
start_slot me "$P1" "$PORT_ME"
start_slot alice "$P2" "$PORT_ALICE"

wait_up() { local port="$1" i; for i in $(seq 1 30); do
  [ "$(curl -s --max-time 3 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$port/" || true)" != "000" ] && return 0
  sleep 1; done; echo "server on :$port never became reachable" >&2; return 1; }
wait_up "$PORT_ME"
wait_up "$PORT_ALICE"

fail=0
assert() { # slot pw port desc
  local slot="$1" pw="$2" port="$3" desc="$4" n a e
  n="$(curl -s --max-time 3 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$port/" || true)"
  a="$(curl -s --max-time 3 -o /dev/null -w '%{http_code}' -u "opencode:$pw" "http://127.0.0.1:$port/" || true)"
  e="$(curl -s --max-time 3 -o /dev/null -w '%{http_code}' -u "opencode:$pw" "http://127.0.0.1:$port/global/event" || true)"
  echo "  $slot noauth=$n auth=$a sse=$e"
  { [ "$n" = "401" ] && [ "$a" = "200" ] && [ "$e" = "200" ]; } || { echo "FAIL: $desc (noauth=$n auth=$a sse=$e)"; fail=1; }
}
echo "== auth per slot =="
assert me   "$P1" "$PORT_ME"   "me slot"
assert alice "$P2" "$PORT_ALICE" "alice slot"

echo "== cross-slot isolation =="
X="$(curl -s --max-time 3 -o /dev/null -w '%{http_code}' -u "opencode:$P2" "http://127.0.0.1:$PORT_ME/" || true)"
echo "  me slot authenticated with alice's password: $X (expect 401)"
[ "$X" = "401" ] || { echo "FAIL isolation: alice's password authenticated me's slot"; fail=1; }

trap 'jobs -p | xargs -r kill 2>/dev/null || true' EXIT
[ "$fail" = "0" ] && { echo "multi-slot smoke PASSED"; exit 0; } || { echo "multi-slot smoke FAILED"; exit 1; }