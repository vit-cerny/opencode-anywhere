#!/usr/bin/env bash
# add-slot.sh - create one per-user isolated opencode slot on this VM.
#
# A slot = a dedicated opencode web for one user: own Linux user, own
# config/skills/chat dirs, own password, own subdomain + loopback port.
# Users "bring their own opencode" either via the web UI (realtime, any
# device) or via the connect client (push/pull their local opencode config,
# skills, MCPs, plugins, projects and chats into this slot).
#
# Usage (as root):  OPENCODE_SERVER_PASSWORD='a-strong-password' ./add-slot.sh myname
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "ERROR: run with sudo" >&2; exit 1; }

SLOT="${1:-}"
[ -n "$SLOT" ] || { echo "ERROR: usage: add-slot.sh <user-name> (lowercase letters, digits, dashes)" >&2; exit 1; }
case "$SLOT" in
  ''|*[!a-z0-9-]*) echo "ERROR: invalid slot name '$SLOT' (lowercase letters, digits, dashes only)" >&2; exit 1 ;;
esac
[ "$SLOT" != "root" ] && [ "$SLOT" != "ubuntu" ] || { echo "ERROR: '$SLOT' is reserved" >&2; exit 1; }

# Password from the environment only - never from a file in this repo.
if [ -z "${OPENCODE_SERVER_PASSWORD:-}" ] || [ "${#OPENCODE_SERVER_PASSWORD}" -lt 12 ]; then
  echo -e "ERROR: OPENCODE_SERVER_PASSWORD is required (min 12 chars).\n  Usage: OPENCODE_SERVER_PASSWORD='a-strong-password' ./add-slot.sh $SLOT" >&2
  exit 1
fi

# --- Base domain written by provision.sh ---
BASE_DOMAIN="$(sed -n 's/^DOMAIN=//p' /etc/opencode/slots.conf 2>/dev/null || true)"
[ -n "$BASE_DOMAIN" ] || { echo "ERROR: run provision.sh first (it writes /etc/opencode/slots.conf)" >&2; exit 1; }

mkdir -p /etc/opencode
N="$(cat /etc/opencode/slot-count 2>/dev/null || echo 0)"
PORT=$((41000 + N))
echo "$((N + 1))" > /etc/opencode/slot-count

USER="cl-$SLOT"
HOME_DIR="/home/$USER"
DOMAIN="$SLOT.$BASE_DOMAIN"

# --- Linux user: system user, no login shell (sftp-only via sshd ForceCommand) ---
id -u "$USER" >/dev/null 2>&1 || useradd --system --create-home --home-dir "$HOME_DIR" --shell /usr/sbin/nologin "$USER"

# --- per-slot service env file (0600 root-only) ---
( umask 077
  mkdir -p /etc/opencode
  printf 'OPENCODE_SERVER_PASSWORD="%s"\n' "$OPENCODE_SERVER_PASSWORD" > "/etc/opencode/$SLOT.env"
  printf 'OPENCODE_SERVER_USERNAME="%s"\n' "${OPENCODE_SERVER_USERNAME:-opencode}" >> "/etc/opencode/$SLOT.env"
  # Keep the pinned version from silently self-updating (drift defeats the pin).
  printf 'OPENCODE_DISABLE_AUTOUPDATE=1\n' >> "/etc/opencode/$SLOT.env"
  chmod 0600 "/etc/opencode/$SLOT.env"
)

# --- slot data dirs; config seeded from the shared template (user brings their own) ---
mkdir -p "$HOME_DIR/.config/opencode" "$HOME_DIR/.agents/skills" "$HOME_DIR/.local/share/opencode"
if [ -f /etc/opencode/templates/opencode.jsonc ] && [ ! -f "$HOME_DIR/.config/opencode/opencode.jsonc" ]; then
  sed "s|{{HOME}}|$HOME_DIR|g" /etc/opencode/templates/opencode.jsonc > "$HOME_DIR/.config/opencode/opencode.jsonc"
  sed "s|{{HOME}}|$HOME_DIR|g" /etc/opencode/templates/AGENTS.md > "$HOME_DIR/AGENTS.md"
fi
chown -R "$USER:$USER" "$HOME_DIR"

# --- per-slot systemd unit (template instance) ---
cat > "/etc/systemd/system/opencode-web-$SLOT.service" <<EOF
[Unit]
Description=opencode web slot for $SLOT
After=network-online.target
Wants=network-online.target
[Service]
Type=simple
User=$USER
Group=$USER
WorkingDirectory=$HOME_DIR
EnvironmentFile=/etc/opencode/$SLOT.env
ExecStart=/usr/local/bin/opencode web --port $PORT --hostname 127.0.0.1
Restart=always
RestartSec=5
NoNewPrivileges=true
PrivateTmp=yes
ProtectSystem=full
ReadWritePaths=$HOME_DIR/.config $HOME_DIR/.local $HOME_DIR/.agents
LimitNOFILE=65536
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable "opencode-web-$SLOT" >/dev/null 2>&1
systemctl restart "opencode-web-$SLOT" || echo "WARNING: slot $SLOT failed to start; see 'journalctl -u opencode-web-$SLOT -n 50'"

# --- Caddy vhost: <slot>.<base> -> 127.0.0.1:<port> (+ rate limit; auth handled by opencode) ---
cat >> /etc/caddy/Caddyfile <<EOF
$DOMAIN {
    admin off
    rate_limit {
        zone dynamic {
            key {remote_host}
            events 20
            window 1m
        }
    }
    reverse_proxy 127.0.0.1:$PORT
}
EOF
caddy validate --config /etc/caddy/Caddyfile >/dev/null || { echo "ERROR: Caddyfile failed validation for slot $SLOT" >&2; exit 1; }
systemctl reload caddy || systemctl restart caddy

# --- sshd: this user is sftp-only (the connect client's data path) ---
cat >> /etc/ssh/sshd_config.d/99-opencode-slots.conf <<EOF

Match User $USER
    PasswordAuthentication no
    ForceCommand internal-sftp
EOF
systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true

echo "SLOT READY: $SLOT"
echo "  web:      https://$DOMAIN   (sign in as '${OPENCODE_SERVER_USERNAME:-opencode}' + your slot password)"
echo "  connect:  ssh $SLOT@<vm-ip>  (sftp-only) - see connect/opencode-connect.*"
echo "  port:     $PORT (loopback only), user: $USER, home: $HOME_DIR"
echo "  manage:   ./remove-slot.sh $SLOT   list: ./list-slots.sh"