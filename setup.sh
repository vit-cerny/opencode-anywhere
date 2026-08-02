#!/usr/bin/env bash
# setup.sh - guided bootstrap for opencode-anywhere (run ON the fresh VM after
# cloning the repo). Asks you the same questions the console would, then runs
# provision.sh. Read-only discoverable: SETUP_* env vars skip the prompts.
#
#   ssh ubuntu@<vm-ip>
#   git clone https://github.com/vit-cerny/opencode-anywhere.git && cd opencode-anywhere
#   ./setup.sh
set -euo pipefail

# Fail fast if not root-able (provision.sh needs sudo)
[ "$(id -u)" -eq 0 ] || { echo "run as root: sudo ./setup.sh" >&2; exit 1; }
[ -f ./provision.sh ] || { echo "ERROR: run from the cloned repo root (provision.sh not found)" >&2; exit 1; }

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