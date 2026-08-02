#!/usr/bin/env bash
# provision.sh - idempotent opencode-anywhere bootstrap for Ubuntu 22.04/24.04 (x64/arm64):
# Node LTS + pinned opencode-ai (npm) + Caddy HTTPS + UFW + per-user SLOT engine.
#
# Every user of the VM gets their own isolated "slot": own config/skills/chat
# dirs, own password, own subdomain + loopback port, own systemd unit. They use
# it via the web UI (realtime from any device) or the connect client (push/pull
# their local opencode state into the slot).
#
# Usage (as root):
#   sudo OPENCODE_SERVER_PASSWORD='a-strong-password' ./provision.sh yourdomain.duckdns.org
#   sudo OPENCODE_SERVER_PASSWORD='a-strong-password' ./add-slot.sh alice   (more users)
set -euo pipefail
readonly NODE_VERSION=v24.18.1 OPENCODE_VERSION=1.18.11 PORT=4096

# --- Fail fast: password from env, never from a file in this repo ---
if [ -z "${OPENCODE_SERVER_PASSWORD:-}" ] || [ "${#OPENCODE_SERVER_PASSWORD}" -lt 12 ]; then
  echo -e "ERROR: OPENCODE_SERVER_PASSWORD is required (min 12 chars).\n  Usage: sudo OPENCODE_SERVER_PASSWORD='a-strong-password' $0 yourdomain.duckdns.org" >&2
  exit 1
fi

# --- Fail fast: DuckDNS domain required (Caddy needs it for Let's Encrypt) ---
DOMAIN="${1:-}"
case "$DOMAIN" in
  ''|*[!a-zA-Z0-9.-]*) echo "ERROR: first argument must be your DuckDNS domain" >&2; exit 1 ;;
esac
[ "${DOMAIN%.*}" = "$DOMAIN" ] && { echo "ERROR: use a fully-qualified domain like yourname.duckdns.org" >&2; exit 1; }

# --- Must run as root, from the cloned repo (templates live next to this script) ---
[ "$(id -u)" -eq 0 ] || { echo "ERROR: run with sudo" >&2; exit 1; }
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$SCRIPT_DIR/opencode.jsonc" ] || { echo "ERROR: run from the cloned opencode-anywhere repo" >&2; exit 1; }

# --- Architecture (Oracle AMD = x64, Ampere A1 = arm64) ---
case "$(uname -m)" in
  x86_64)       NODE_ARCH=x64 ;;
  aarch64|arm64) NODE_ARCH=arm64 ;;
  *) echo "ERROR: unsupported architecture $(uname -m)" >&2; exit 1 ;;
esac

# --- Base packages (gpg for the Caddy key, xz for Node, ufw for the firewall, qrencode for QR) ---
apt-get update -qq && apt-get install -y -qq ca-certificates curl gnupg xz-utils tar ufw qrencode

# --- (a) Node.js LTS from the official nodejs.org tarball (both arches, no shell-pipe installer) ---
if [ -x /usr/local/bin/node ] && [ "$(/usr/local/bin/node -v 2>/dev/null || true)" = "$NODE_VERSION" ]; then
  echo "node $NODE_VERSION already installed"
else
  TMP="$(mktemp -d)"
  curl -fsSL -o "$TMP/node.tar.xz" "https://nodejs.org/dist/$NODE_VERSION/node-$NODE_VERSION-linux-$NODE_ARCH.tar.xz"
  tar -xJf "$TMP/node.tar.xz" -C "$TMP"
  cp -r "$TMP/node-$NODE_VERSION-linux-$NODE_ARCH"/* /usr/local/
  rm -rf "$TMP"
  hash -r
fi

# --- (b) opencode-ai, pinned (npm only; never a shell-pipe installer) ---
if command -v opencode >/dev/null 2>&1 && opencode --version 2>/dev/null | grep -q "v$OPENCODE_VERSION"; then
  echo "opencode-ai $OPENCODE_VERSION already installed"
else
  echo "installing opencode-ai@$OPENCODE_VERSION (npm, pinned)"
  npm install -g "opencode-ai@$OPENCODE_VERSION"
  hash -r
fi

# --- (c) slot registries: base domain + shared templates for add-slot.sh ---
mkdir -p /etc/opencode/templates
printf 'DOMAIN=%s\n' "$DOMAIN" > /etc/opencode/slots.conf
cp "$SCRIPT_DIR/opencode.jsonc" /etc/opencode/templates/opencode.jsonc
cp "$SCRIPT_DIR/AGENTS.md"      /etc/opencode/templates/AGENTS.md

# --- (d) Caddy: official apt repo, key pinned via gpg --dearmor (no shell-pipe installer) ---
if ! dpkg -s caddy >/dev/null 2>&1; then
  curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/gpg.key | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  # apt drops keyrings that are not 0644+ (NO_PUBKEY); enforce perms explicitly.
  chmod 0644 /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  printf 'deb [signed-by=/usr/share/keyrings/caddy-stable-archive-keyring.gpg] https://dl.cloudsmith.io/public/caddy/stable/deb/debian any-version main\n' > /etc/apt/sources.list.d/caddy-stable.list
  chmod 0644 /etc/apt/sources.list.d/caddy-stable.list
  apt-get update -qq && apt-get install -y -qq caddy
fi
mkdir -p /etc/caddy
# Base Caddyfile: comments only; add-slot.sh appends each user's vhost.
: > /etc/caddy/Caddyfile
printf '# opencode-anywhere: every slot adds its own <user>.%s { } vhost below.\n' "$DOMAIN" > /etc/caddy/Caddyfile
printf '# Regenerate/edit manually if you want extra server blocks.\n' >> /etc/caddy/Caddyfile

# Wait for the DuckDNS A record to point at this host before Caddy serves
# (Let's Encrypt HTTP-01 needs to reach us on port 80).
for i in $(seq 1 12); do
  DNS_IP="$(getent hosts "$DOMAIN" | awk '{print $1}' | head -n1 || true)"
  PUB_IP="$(curl -fsSL --max-time 5 https://ifconfig.me 2>/dev/null || true)"
  if [ -n "$DNS_IP" ] && [ -n "$PUB_IP" ] && [ "$DNS_IP" = "$PUB_IP" ]; then break; fi
  echo "waiting for $DOMAIN to point at this host (attempt $i/12)..."
  sleep 10
done

# --- (e) first slot (owner): your own workspace, same as the single-user flow ---
FIRST_SLOT="${OPENCODE_SLOT:-me}"
OPENCODE_SERVER_PASSWORD="$OPENCODE_SERVER_PASSWORD" OPENCODE_SERVER_USERNAME="${OPENCODE_SERVER_USERNAME:-opencode}" \
  "$SCRIPT_DIR/add-slot.sh" "$FIRST_SLOT"

# Install the bundled 14 community skills into the owner slot (best-effort).
install_skill() {
  local user="$1" entry="$2"   # user ; "owner/repo@skill-name"
  echo "  skill($user): $entry ..."
  if runuser -u "$user" -- env HOME="/home/$user" \
      PATH="/usr/local/bin:/usr/bin:/usr/sbin:/bin" \
      npx --yes skills add "$entry" -g -y --copy >/dev/null 2>&1; then
    echo "    ok"
  else
    echo "    WARNING: skipped '$entry' (npx skills add failed)" >&2
  fi
}
SKILL_USER="cl-$FIRST_SLOT"
install_skill "$SKILL_USER" "Niozerp/andrej-karpathy-skills-opencode@karpathy-guidelines"
install_skill "$SKILL_USER" "wshobson/agents@prompt-engineering-patterns"
install_skill "$SKILL_USER" "addyosmani/agent-skills@code-review-and-quality"
install_skill "$SKILL_USER" "addyosmani/web-quality-skills@performance"
install_skill "$SKILL_USER" "vercel-labs/agent-browser@agent-browser"
install_skill "$SKILL_USER" "openai/skills@screenshot"
install_skill "$SKILL_USER" "anthropics/skills@docx"
install_skill "$SKILL_USER" "anthropics/skills@pdf"
install_skill "$SKILL_USER" "anthropics/skills@pptx"
install_skill "$SKILL_USER" "anthropics/skills@xlsx"
install_skill "$SKILL_USER" "dietrichgebert/ponytail@ponytail"
install_skill "$SKILL_USER" "Graphify-Labs/graphify@graphify"
install_skill "$SKILL_USER" "github/awesome-copilot@ai-prompt-engineering-safety-review"
install_skill "$SKILL_USER" "maxmilian/loop-engineering@loop-engineering"

# --- (f) firewall: 22, 80, 443 only ---
for P in 22 80 443; do ufw allow "$P/tcp" >/dev/null; done
ufw --force enable >/dev/null

# --- (g) SSH hardening: key-only, no root login (slot users are sftp-only via add-slot.sh) ---
printf 'PasswordAuthentication no\nPermitRootLogin no\n' > /etc/ssh/sshd_config.d/99-opencode-cloud.conf
systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true

# --- (h) convenience helpers (server-side; connect client lives in connect/) ---
for S in qrcode backup restore list-slots; do install -m 0755 "$SCRIPT_DIR/$S.sh" "/usr/local/bin/$S.sh"; done

# --- done (never print passwords ---
echo; echo "============================================================"
echo " opencode-anywhere is live."
echo " YOUR slot:  https://$FIRST_SLOT.$DOMAIN   (sign in as '${OPENCODE_SERVER_USERNAME:-opencode}' + your OPENCODE_SERVER_PASSWORD)"
echo " QR:         qrcode.sh https://$FIRST_SLOT.$DOMAIN"
echo " more users: OPENCODE_SERVER_PASSWORD='<their-pw>' ./add-slot.sh <name>  -> https://<name>.$DOMAIN"
echo " connect:    a user's PC runs:  opencode-connect.sh <vm-ip> <name>   (in connect/)"
echo " backups:    backup.sh / restore.sh   logs: journalctl -u opencode-web-me -f"
echo "============================================================"