#!/usr/bin/env bash
# health-loop.sh - keep every opencode slot's HTTP port answering.
# For each slot (home dir /home/cl-*), hit its loopback port; if the unit is
# "active" but the port is silent (wedged process), restart it. Never touches a
# unit that is already down/restarting: that is `Restart=always`'s own job, so
# this cannot fight the unit's backoff loop.
#
# Readiness mirrors smoke.sh: opencode returns 401 *without* auth, so a healthy
# slot is NOT a `curl -f` success. Any HTTP status (not 000/connection failure)
# means the loop is alive. Prints one PRUNED/OK line per slot.
#
# Usage (as root):  ./scripts/health-loop.sh
# Cron (every 5 min):
#   */5 * * * * /opt/opencode-anywhere/scripts/health-loop.sh >>/var/log/opencode-health.log 2>&1
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "ERROR: run with sudo" >&2; exit 1; }

# Never run twice: cron could overlap if a probe hangs. Same flock idiom as add-slot.sh.
exec 9>"/var/lock/opencode-health.lock"
flock -n 9 || { echo "health-loop: another run in progress; skipping" >&2; exit 0; }

found=0
for U in /home/cl-*; do
  [ -d "$U" ] || continue
  NAME="${U#/home/cl-}"
  found=1

  # Read the slot's loopback port the same way list-slots.sh does.
  PORT="$(systemctl show "opencode-web-$NAME" -p ExecStart --no-pager 2>/dev/null \
            | grep -oE 'port [0-9]+' | awk '{print $2}')" || true
  [ -n "$PORT" ] || { echo "PRUNED $NAME (no live unit/port)"; continue; }

  STATE="$(systemctl is-active "opencode-web-$NAME" 2>/dev/null || echo unknown)"
  # Unit is down/restarting: leave it to Restart=always, don't fight its backoff.
  [ "$STATE" != "active" ] && { echo "PRUNED $NAME (state=$STATE; Restart=always retries)"; continue; }

  CODE="$(curl -s --max-time 5 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/" || true)"
  if [ "$CODE" = "000" ]; then
    systemctl restart "opencode-web-$NAME"
    echo "PRUNED $NAME (active but :$PORT unresponsive -> restarted)"
  else
    echo "OK $NAME (:$PORT http=$CODE)"
  fi
done
[ "$found" -eq 1 ] && echo "health-loop: all slots checked at $(date -u +%FT%TZ)"