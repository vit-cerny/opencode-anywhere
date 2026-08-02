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

readonly SLOT_LOCK=/etc/opencode/slot-count.lock
mkdir -p /etc/opencode
# Atomic port allocation: flock so two concurrent add-slot runs cannot both
# read the same slot-count and collide on a port.
exec 9>"$SLOT_LOCK"
flock 9
N="$(cat /etc/opencode/slot-count 2>/dev/null || echo 0)"
PORT=$((41000 + N))
echo "$((N + 1))" > /etc/opencode/slot-count
flock -u 9
exec 9>&-

USER="cl-$SLOT"
HOME_DIR="/home/$USER"
DOMAIN="$SLOT.$BASE_DOMAIN"

# --- Linux user: system user, no login shell (sftp-only via sshd ForceCommand) ---
id -u "$USER" >/dev/null 2>&1 || useradd --system --create-home --home-dir "$HOME_DIR" --shell /usr/sbin/nologin "$USER"

# --- per-slot service env file (0600 root-only). Never silently overwrite an
# existing slot's password (a provision re-run must not clobber a user's
# credentials); OPENCODE_SLOT_RESET=1 explicitly rotates it. ---
if [ -f "/etc/opencode/$SLOT.env" ] && [ "${OPENCODE_SLOT_RESET:-0}" != "1" ]; then
  echo "note: keeping existing password for slot '$SLOT' (OPENCODE_SLOT_RESET=1 to rotate)"
else
  ( umask 077
    mkdir -p /etc/opencode
    printf 'OPENCODE_SERVER_PASSWORD="%s"\n' "$OPENCODE_SERVER_PASSWORD" > "/etc/opencode/$SLOT.env"
    printf 'OPENCODE_SERVER_USERNAME="%s"\n' "${OPENCODE_SERVER_USERNAME:-opencode}" >> "/etc/opencode/$SLOT.env"
    # Keep the pinned version from silently self-updating (drift defeats the pin).
    printf 'OPENCODE_DISABLE_AUTOUPDATE=1\n' >> "/etc/opencode/$SLOT.env"
    chmod 0600 "/etc/opencode/$SLOT.env"
  )
fi

# --- slot data dirs; config seeded from the shared template (user brings their own) ---
mkdir -p "$HOME_DIR/.config/opencode" "$HOME_DIR/.agents/skills" "$HOME_DIR/.local/share/opencode"
if [ -f /etc/opencode/templates/opencode.jsonc ] && [ ! -f "$HOME_DIR/.config/opencode/opencode.jsonc" ]; then
  sed "s|{{HOME}}|$HOME_DIR|g" /etc/opencode/templates/opencode.jsonc > "$HOME_DIR/.config/opencode/opencode.jsonc"
  sed "s|{{HOME}}|$HOME_DIR|g" /etc/opencode/templates/AGENTS.md > "$HOME_DIR/AGENTS.md"
fi
# --- SETTINGS_REPO: bake the user's OWN settings into the slot (real-time sync).
# First writer wins: apply a settings file only when the target is missing or is
# still the just-seeded template default (byte-identical). Never clobber a file
# a user already customized or pulled down via connect. Skills merge by name,
# no-clobber. A missing/unreachable repo warns and leaves the template defaults.
# Security: the value is an ATTACK SURFACE - accept only github URLs or plain
# local paths; reject anything that starts with '-' (option injection), contains
# spaces/shell metachars, or uses an exotic scheme (file:// etc).
# Also: git copies symlinks verbatim; a repo containing a link to /etc/... would
# let the slot read/write outside its home, so we delete symlinks after clone. ---
if [ -n "${SETTINGS_REPO:-}" ] && command -v git >/dev/null 2>&1; then
  case "$SETTINGS_REPO" in
    https://github.com/*|git@github.com:*|/*|~/*) ;;
    *) echo "WARNING: SETTINGS_REPO '$SETTINGS_REPO' rejected (allow: https://github.com/.., git@github.com:.., or an absolute path) - using template defaults" >&2; SETTINGS_REPO= ;;
  esac
  if [ -n "$SETTINGS_REPO" ] && git clone --depth 1 -- "$SETTINGS_REPO" "$HOME_DIR/.settings-src" >/dev/null 2>&1; then
    find "$HOME_DIR/.settings-src" -type l -delete   # no symlink escapes
    # opencode.jsonc -> .config/opencode (replaces a fresh template default; HTML home templated)
    if [ -f "$HOME_DIR/.settings-src/opencode.jsonc" ] \
       && { [ ! -f "$HOME_DIR/.config/opencode/opencode.jsonc" ] \
            || { [ -f /etc/opencode/templates/opencode.jsonc ] \
                 && cmp -s "$HOME_DIR/.config/opencode/opencode.jsonc" <(sed "s|{{HOME}}|$HOME_DIR|g" /etc/opencode/templates/opencode.jsonc); }; }; then
      sed "s|{{HOME}}|$HOME_DIR|g" "$HOME_DIR/.settings-src/opencode.jsonc" > "$HOME_DIR/.config/opencode/opencode.jsonc"
      echo "settings: opencode.jsonc <- SETTINGS_REPO"
    fi
    # AGENTS.md -> $HOME/AGENTS.md (same first-writer-wins rule)
    if [ -f "$HOME_DIR/.settings-src/AGENTS.md" ] \
       && { [ ! -f "$HOME_DIR/AGENTS.md" ] \
            || { [ -f /etc/opencode/templates/AGENTS.md ] \
                 && cmp -s "$HOME_DIR/AGENTS.md" <(sed "s|{{HOME}}|$HOME_DIR|g" /etc/opencode/templates/AGENTS.md); }; }; then
      sed "s|{{HOME}}|$HOME_DIR|g" "$HOME_DIR/.settings-src/AGENTS.md" > "$HOME_DIR/AGENTS.md"
      echo "settings: AGENTS.md <- SETTINGS_REPO"
    fi
    # skills/ -> ~/.agents/skills, per-name no-clobber
    if [ -d "$HOME_DIR/.settings-src/skills" ]; then
      mkdir -p "$HOME_DIR/.agents/skills"
      shopt -s nullglob
      for d in "$HOME_DIR/.settings-src/skills"/*/; do
        n="$(basename "$d")"
        [ -e "$HOME_DIR/.agents/skills/$n" ] || { cp -R "$d" "$HOME_DIR/.agents/skills/"; echo "settings: skill +$n"; }
      done
      chown -R "$USER:$USER" "$HOME_DIR/.agents"
      shopt -u nullglob
    fi
  else
    echo "WARNING: could not clone SETTINGS_REPO '$SETTINGS_REPO' - using template defaults" >&2
  fi
  rm -rf "$HOME_DIR/.settings-src"
fi
# --- codex slot seeding: ~/.codex (config + auth.json after the user logs in) ---
# 0700 on the dir: it holds the slot's codex auth (provider tokens) once used.
mkdir -p "$HOME_DIR/.codex"
if [ ! -f "$HOME_DIR/.codex/config.toml" ]; then
  cat > "$HOME_DIR/.codex/config.toml" <<EOF
# opencode-anywhere codex slot config. Log in once in this slot (ttyd web or
# 'connect push' after a local 'codex login') - the token lands in auth.json
# here (0600). Model + approval policy: uncomment and set your own defaults.
# model = "gpt-5.1-codex"
# approval_policy = "untrusted"
[approval_policy]
mode = "off"
EOF
fi
chmod 0700 "$HOME_DIR/.codex"
chown -R "$USER:$USER" "$HOME_DIR/.codex"

# --- claude code slot seeding: ~/.claude, ~/.claude.json ---
# ~/.claude + ~/.claude.json hold auth/state; settings.json is the user's
# settings template (0700 on the dirs: they can hold tokens).
mkdir -p "$HOME_DIR/.claude"
: > "$HOME_DIR/.claude.json"   # claude code expects this file to exist
if [ ! -f "$HOME_DIR/.claude/settings.json" ]; then
  cat > "$HOME_DIR/.claude/settings.json" <<'EOF'
{
  "env": {},
  "permissions": {}
}
EOF
fi
chmod 0700 "$HOME_DIR/.claude"
chmod 0600 "$HOME_DIR/.claude.json" "$HOME_DIR/.claude/settings.json"
chown -R "$USER:$USER" "$HOME_DIR/.claude" "$HOME_DIR/.claude.json"

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

# --- Caddy vhost: <slot>.<base> -> 127.0.0.1:<port> (auth enforced by opencode) ---
# Idempotent: drop any existing block for this domain first (stale/failed runs
# must not accumulate duplicate vhosts), then append a clean proxy-only block.
awk -v dom="$DOMAIN" '
  $0 == dom" {" { skip=1; next }
  skip && $0 == "}" { skip=0; next }
  skip { next }
  { print }
' /etc/caddy/Caddyfile > /etc/caddy/Caddyfile.new && mv /etc/caddy/Caddyfile.new /etc/caddy/Caddyfile
cat >> /etc/caddy/Caddyfile <<EOF
$DOMAIN {
    reverse_proxy 127.0.0.1:$PORT
}
EOF
caddy validate --config /etc/caddy/Caddyfile >/dev/null || { echo "ERROR: Caddyfile failed validation for slot $SLOT" >&2; exit 1; }
systemctl reload caddy 2>/dev/null || systemctl restart caddy

# --- sshd: this user is sftp-only (the connect client's data path) ---
mkdir -p /etc/ssh/sshd_config.d
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