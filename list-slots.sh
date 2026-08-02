#!/usr/bin/env bash
# list-slots.sh - show every opencode slot on this VM with its URL and state.
# Usage (as root):  ./list-slots.sh
set -euo pipefail

BASE_DOMAIN="$(sed -n 's/^DOMAIN=//p' /etc/opencode/slots.conf 2>/dev/null || true)"
echo "slots on $(hostname) [base domain: ${BASE_DOMAIN:-<none>}]"
echo "---"
found=0
for U in /home/cl-*; do
  [ -d "$U" ] || continue
  NAME="${U#/home/cl-}"
  found=1
  ACTIVE="$(systemctl is-active "opencode-web-$NAME" 2>/dev/null || echo unknown)"
  PORT="$(systemctl show "opencode-web-$NAME" -p ExecStart --no-pager 2>/dev/null | grep -o 'port [0-9]*' | awk '{print $2}')"
  echo "$NAME   web: https://$NAME.$BASE_DOMAIN   state: $ACTIVE   port: ${PORT:-?}"
done
[ "$found" -eq 0 ] && echo "no slots yet - run add-slot.sh <name>"
echo "---"
[ -f /etc/opencode/slot-count ] && echo "total slots created: $(cat /etc/opencode/slot-count)"