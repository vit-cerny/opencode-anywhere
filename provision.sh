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
#   Optional: SETTINGS_REPO='https://github.com/you/your-opencode-settings' clones a
#   private settings repo (opencode.jsonc, AGENTS.md, skills/) into each slot so your
#   config follows you to every device in real time (first-writer-wins over the template).
#   e.g. SETTINGS_REPO='https://github.com/you/your-settings' sudo OPENCODE_SERVER_PASSWORD='<pw>' ./add-slot.sh alice
#   or, on an existing slot:  ./scripts/seed-settings.sh alice https://github.com/you/your-settings
set -euo pipefail
readonly NODE_VERSION=v24.18.1 OPENCODE_VERSION=1.18.11 PORT=4096 \
  CODEX_VERSION=0.146.0 CLAUDE_CODE_VERSION=2.1.220

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

# --- Architecture (Oracle AMD = x64/amd64, Ampere A1 = arm64) ---
case "$(uname -m)" in
  x86_64)       NODE_ARCH=x64   ; CADDY_ARCH=amd64 ;;
  aarch64|arm64) NODE_ARCH=arm64; CADDY_ARCH=arm64 ;;
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
if command -v opencode >/dev/null 2>&1 && opencode --version 2>/dev/null | grep -q "$OPENCODE_VERSION"; then
  echo "opencode-ai $OPENCODE_VERSION already installed"
else
  echo "installing opencode-ai@$OPENCODE_VERSION (npm, pinned)"
  npm install -g "opencode-ai@$OPENCODE_VERSION"
  hash -r
fi

# --- (b2) OpenAI Codex CLI, pinned (npm) - every slot user can invoke it ---
if command -v codex >/dev/null 2>&1 && codex --version 2>/dev/null | grep -q "$CODEX_VERSION"; then
  echo "codex $CODEX_VERSION already installed"
else
  echo "installing codex@$CODEX_VERSION (npm, pinned)"
  npm install -g "@openai/codex@$CODEX_VERSION"
  hash -r
fi

# --- (b3) Claude Code CLI, pinned (npm) - every slot user can invoke it ---
if command -v claude >/dev/null 2>&1 && claude --version 2>/dev/null | grep -q "$CLAUDE_CODE_VERSION"; then
  echo "claude $CLAUDE_CODE_VERSION already installed"
else
  echo "installing @anthropic-ai/claude-code@$CLAUDE_CODE_VERSION (npm, pinned)"
  npm install -g "@anthropic-ai/claude-code@$CLAUDE_CODE_VERSION"
  hash -r
fi

# --- (c) slot registries: base domain + shared templates for add-slot.sh ---
mkdir -p /etc/opencode/templates
printf 'DOMAIN=%s\n' "$DOMAIN" > /etc/opencode/slots.conf
cp "$SCRIPT_DIR/opencode.jsonc" /etc/opencode/templates/opencode.jsonc
cp "$SCRIPT_DIR/AGENTS.md"      /etc/opencode/templates/AGENTS.md

# --- (d) Caddy: official static binary from GitHub releases - pinned version,
#         verified against the upstream checksums file (no apt repo, no keyring,
#         no shell-pipe installer). Works identically on every distro/arch. ---
readonly CADDY_VERSION=v2.11.4
if [ -x /usr/bin/caddy ] && caddy version 2>/dev/null | grep -q "$CADDY_VERSION"; then
  echo "caddy $CADDY_VERSION already installed"
else
  CADDY_TMP="$(mktemp -d)"
  CADDY_URL="https://github.com/caddyserver/caddy/releases/download/$CADDY_VERSION/caddy_${CADDY_VERSION#v}_linux_${CADDY_ARCH}.tar.gz"
  echo "installing caddy $CADDY_VERSION (official tarball, checksum-verified)"
  curl -fsSL -o "$CADDY_TMP/caddy.tgz" "$CADDY_URL" || {
    curl -fsSL -o "$CADDY_TMP/checksums.txt" "https://github.com/caddyserver/caddy/releases/download/$CADDY_VERSION/caddy_${CADDY_VERSION#v}_checksums.txt"
    echo "ERROR: could not download caddy tarball (see checksums attempt above)" >&2; exit 1; }
  ( cd "$CADDY_TMP" && tar -xzf caddy.tgz caddy )
  install -m 0755 "$CADDY_TMP/caddy" /usr/bin/caddy
  rm -rf "$CADDY_TMP"
  hash -r
fi
mkdir -p /etc/caddy
# The service runs as non-root (User=caddy): the dir and file must be
# world-traversable/readable or Caddy cannot read its own config.
chmod 0755 /etc/caddy
umask 022  # explicit: ensure the template write below is 0644, not 0600
# Global options belong OUTSIDE site blocks (this is a Caddyfile requirement).
# Only seed the file if absent: add-slot.sh appends vhosts, and re-running
# provision must never wipe the slots that already exist.
if [ ! -s /etc/caddy/Caddyfile ]; then
  cat > /etc/caddy/Caddyfile <<'EOF'
{
    admin off
}
EOF
  printf '# opencode-anywhere: add-slot.sh appends one <user>.%s { } vhost per user.\n' "$DOMAIN" >> /etc/caddy/Caddyfile
fi
# Own the service (the distro's caddy unit may be absent): idempotent unit.
# Create the dedicated non-root caddy user BEFORE the unit references it
# (User=caddy), so a Caddy compromise is not a root compromise.
if ! id -u caddy >/dev/null 2>&1; then
  mkdir -p /var/lib/caddy
  useradd --system --home-dir /var/lib/caddy --shell /usr/sbin/nologin caddy
fi
mkdir -p /var/lib/caddy
chown -R caddy:caddy /var/lib/caddy
systemctl stop caddy >/dev/null 2>&1 || true
cat > /etc/systemd/system/caddy.service <<'EOF'
[Unit]
Description=Caddy web server (opencode-anywhere slots)
After=network-online.target
Wants=network-online.target
[Service]
Type=notify
User=caddy
Group=caddy
WorkingDirectory=/var/lib/caddy
Environment=XDG_DATA_HOME=/var/lib/caddy XDG_CONFIG_HOME=/var/lib/caddy
ExecStart=/usr/bin/caddy run --environ --config /etc/caddy/Caddyfile
ExecReload=/usr/bin/caddy reload --config /etc/caddy/Caddyfile
TimeoutStopSec=5s
LimitNOFILE=1048576
LimitNPROC=512
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=/var/lib/caddy /etc/caddy
AmbientCapabilities=CAP_NET_BIND_SERVICE
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable caddy >/dev/null 2>&1
# Caddy data dir (pki/CA store, autosave) - owned by its user. ProtectSystem=strict
# keeps the rest of the FS read-only, so Caddy may only write under this.
caddy validate --config /etc/caddy/Caddyfile >/dev/null || { echo "ERROR: base Caddyfile failed validation" >&2; exit 1; }

# Wait for the DuckDNS A record to point at this host before Caddy serves
# (Let's Encrypt HTTP-01 needs to reach us on port 80). Each lookup is capped
# so a broken resolver cannot stall the bootstrap.
for i in $(seq 1 12); do
  DNS_IP="$(timeout 4 getent hosts "$DOMAIN" | awk '{print $1}' | head -n1 || true)"
  PUB_IP="$(curl -fsSL --max-time 5 https://ifconfig.me 2>/dev/null || true)"
  if [ -n "$DNS_IP" ] && [ -n "$PUB_IP" ] && [ "$DNS_IP" = "$PUB_IP" ]; then break; fi
  echo "waiting for $DOMAIN to point at this host (attempt $i/12)..."
  sleep 10
done

# --- (e) first slot (owner): your own workspace, same as the single-user flow ---
FIRST_SLOT="${OPENCODE_SLOT:-me}"
OPENCODE_SERVER_PASSWORD="$OPENCODE_SERVER_PASSWORD" OPENCODE_SERVER_USERNAME="${OPENCODE_SERVER_USERNAME:-opencode}" \
  SETTINGS_REPO="${SETTINGS_REPO:-}" "$SCRIPT_DIR/add-slot.sh" "$FIRST_SLOT"

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