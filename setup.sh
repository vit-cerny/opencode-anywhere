#!/usr/bin/env bash
# setup.sh - guided one-time setup for opencode-anywhere.
#
# ONE LINE on a fresh VM (no git needed first):
#   curl -fsSL https://raw.githubusercontent.com/vit-cerny/opencode-anywhere/main/setup.sh | sudo bash
#
# Or from an existing checkout:   sudo ./setup.sh
#
# Asks the same questions the console would (DuckDNS domain, owner password,
# optional settings repo), then runs provision.sh. Read-only discoverable:
# SETUP_* env vars skip the prompts.
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "run as root: sudo ./setup.sh (or the curl one-liner)" >&2; exit 1; }

# --- Self-bootstrap: working on a bare VM? clone ourselves first. ----------
if [ ! -f ./provision.sh ]; then
  echo "=> good to go: fetching opencode-anywhere (installs git)..."
  apt-get update -qq >/dev/null
  apt-get install -y -qq git >/dev/null
  [ -d /opt/opencode-anywhere/.git ] || \
    git clone --quiet https://github.com/vit-cerny/opencode-anywhere.git /opt/opencode-anywhere
  chmod +x /opt/opencode-anywhere/*.sh   # belt-and-braces: filesystems/git may drop exec bits
  cd /opt/opencode-anywhere
  exec bash ./setup.sh
fi

echo "opencode-anywhere guided setup"
echo "-------------------------------"
echo "This VM will become your always-on multi-user opencode server."
echo "Answers are used ONLY at run time - nothing is written to the repo."
echo

# 1. DuckDNS subdomain (mandatory)
DOMAIN="${SETUP_DOMAIN:-}"
while [ -z "$DOMAIN" ]; do
  read -r -p "Your DuckDNS subdomain (e.g. mybox.duckdns.org): " DOMAIN
  case "$DOMAIN" in
    '') ;;
    *[!a-zA-Z0-9.-]*) echo "  (letters/digits/dots only)"; DOMAIN= ;;
    *) ;;
  esac
done

# 2. Admin (owner slot) password (mandatory, min 12 chars, never echoed)
PW="${SETUP_PASSWORD:-}"
while [ "${#PW}" -lt 12 ]; do
  read -r -s -p "Owner-slot password (min 12 chars, hidden): " PW; echo
  [ "${#PW}" -lt 12 ] && echo "  (too short)" 
done

# 3. Own settings repo (optional) - your own opencode.jsonc/AGENTS.md/skills
REPO="${SETTINGS_REPO:-}"
if [ -z "$REPO" ] && [ "${SETUP_SKIP_REPO:-0}" != "1" ]; then
  read -r -p "Your settings repo (https://github.com/you/opencode-defaults, blank to skip): " REPO
fi

echo; echo "Summary:"
echo "  domain        : $DOMAIN"
echo "  settings repo : ${REPO:-<none - shared template>}"
echo "  new slots     : extra users use  OPENCODE_SERVER_PASSWORD='<their-pw>' ./add-slot.sh <name>"
# Non-interactive (CI/sandbox, SETUP_* set): skip straight to provisioning.
if [ "${SETUP_YES:-0}" = "1" ] || [ ! -t 0 ]; then
  echo "=> auto-proceeding (SETUP_YES=1 or non-interactive input)"
else
  read -r -p "Looks right? [Enter] to provision (Ctrl-C to abort) -> " _
fi

echo "=> provisioning (idempotent; ~2-5 min)..."
if [ -n "$REPO" ]; then
  OPENCODE_SERVER_PASSWORD="$PW" SETTINGS_REPO="$REPO" ./provision.sh "$DOMAIN"
else
  OPENCODE_SERVER_PASSWORD="$PW" ./provision.sh "$DOMAIN"
fi

echo
echo "DONE: https://me.$DOMAIN  (user: opencode, password: the one you entered)"