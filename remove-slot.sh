#!/usr/bin/env bash
# remove-slot.sh - delete one slot: systemd unit, Caddy vhost, env file, sshd
# Match block, and the user's home (their data) - after you have backed up.
# Usage (as root):  ./remove-slot.sh <user-name>
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "ERROR: run with sudo" >&2; exit 1; }
SLOT="${1:-}"
[ -n "$SLOT" ] || { echo "ERROR: usage: remove-slot.sh <user-name>" >&2; exit 1; }
case "$SLOT" in ''|*[!a-z0-9-]*) echo "ERROR: invalid slot name" >&2; exit 1 ;; esac

USER="cl-$SLOT"

systemctl disable --now "opencode-web-$SLOT" >/dev/null 2>&1 || true
rm -f "/etc/systemd/system/opencode-web-$SLOT.service"
rm -f "/etc/opencode/$SLOT.env"
systemctl daemon-reload

# --- strip the slot's Caddy vhost (its domain line { ... }) ---
if [ -f /etc/caddy/Caddyfile ]; then
  BASE_DOMAIN="$(sed -n 's/^DOMAIN=//p' /etc/opencode/slots.conf 2>/dev/null || true)"
  if [ -n "$BASE_DOMAIN" ]; then
    awk -v d="$SLOT.$BASE_DOMAIN" '
      $0 == d { skip=1; next }
      !skip { print }
      skip && /^ }/ { skip=0 }
    ' /etc/caddy/Caddyfile > /etc/caddy/Caddyfile.tmp && mv /etc/caddy/Caddyfile.tmp /etc/caddy/Caddyfile
    systemctl reload caddy 2>/dev/null || true
  fi
fi

# --- strip the slot's sshd Match block (down to the blank line) ---
if [ -f /etc/ssh/sshd_config.d/99-opencode-slots.conf ]; then
  awk -v u="$USER" '
    $1 == "Match" && $3 == u { skip=1; next }
    !skip { print }
    skip && /^$/ { skip=0 }
  ' /etc/ssh/sshd_config.d/99-opencode-slots.conf > /etc/ssh/sshd_config.d/99-opencode-slots.conf.tmp && mv /etc/ssh/sshd_config.d/99-opencode-slots.conf.tmp /etc/ssh/sshd_config.d/99-opencode-slots.conf
  systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
fi

# --- delete the user and their data home ---
if id -u "$USER" >/dev/null 2>&1; then userdel -r "$USER" 2>/dev/null || true; fi
echo "SLOT REMOVED: $SLOT (data home deleted)"