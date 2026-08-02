#!/usr/bin/env bash
# seed-settings.sh - clone a user's own settings repo into an existing slot,
# from outside (server-side helper). Same first-writer-wins rules as add-slot.sh.
#
# A settings repo is a private git repo that holds YOUR opencode:
#   opencode.jsonc  AGENTS.md  skills/
# It is cloned into a slot so your config follows you to every device in realtime.
#
# Usage (as root on the VM):
#   ./scripts/seed-settings.sh <slot> <SETTINGS_REPO-url-or-path>
#   e.g. ./scripts/seed-settings.sh alice https://github.com/you/your-settings
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "ERROR: run with sudo" >&2; exit 1; }

SLOT="${1:-}"
SETTINGS_REPO="${2:-}"
[ -n "$SLOT" ] || { echo "ERROR: usage: seed-settings.sh <slot> <settings-repo-url>" >&2; exit 1; }
[ -n "$SETTINGS_REPO" ] || { echo "ERROR: SETTINGS_REPO (git url or local path) required" >&2; exit 1; }

USER="cl-$SLOT"
HOME_DIR="/home/$USER"
id -u "$USER" >/dev/null 2>&1 || { echo "ERROR: no slot '$SLOT' (run add-slot.sh first)" >&2; exit 1; }

# Local path or git URL? Local paths (start with / or ~) clone straight; URLs need git.
if ! command -v git >/dev/null 2>&1; then
  echo "ERROR: 'git' not installed; install it to seed settings" >&2; exit 1
fi

if git clone --depth 1 "$SETTINGS_REPO" "$HOME_DIR/.settings-src" >/dev/null 2>&1; then
  # opencode.jsonc (first writer wins over a fresh template default)
  if [ -f "$HOME_DIR/.settings-src/opencode.jsonc" ] \
     && { [ ! -f "$HOME_DIR/.config/opencode/opencode.jsonc" ] \
          || { [ -f /etc/opencode/templates/opencode.jsonc ] \
               && cmp -s "$HOME_DIR/.config/opencode/opencode.jsonc" <(sed "s|{{HOME}}|$HOME_DIR|g" /etc/opencode/templates/opencode.jsonc); }; }; then
    mkdir -p "$HOME_DIR/.config/opencode"
    sed "s|{{HOME}}|$HOME_DIR|g" "$HOME_DIR/.settings-src/opencode.jsonc" > "$HOME_DIR/.config/opencode/opencode.jsonc"
    echo "settings: opencode.jsonc <- $SETTINGS_REPO"
  fi
  # AGENTS.md (first-writer-wins)
  if [ -f "$HOME_DIR/.settings-src/AGENTS.md" ] \
     && { [ ! -f "$HOME_DIR/AGENTS.md" ] \
          || { [ -f /etc/opencode/templates/AGENTS.md ] \
               && cmp -s "$HOME_DIR/AGENTS.md" <(sed "s|{{HOME}}|$HOME_DIR|g" /etc/opencode/templates/AGENTS.md); }; }; then
    sed "s|{{HOME}}|$HOME_DIR|g" "$HOME_DIR/.settings-src/AGENTS.md" > "$HOME_DIR/AGENTS.md"
    echo "settings: AGENTS.md <- $SETTINGS_REPO"
  fi
  # skills/ -> ~/.agents/skills, no-clobber per name
  if [ -d "$HOME_DIR/.settings-src/skills" ]; then
    mkdir -p "$HOME_DIR/.agents/skills"
    shopt -s nullglob
    for d in "$HOME_DIR/.settings-src/skills"/*/; do
      n="$(basename "$d")"
      [ -e "$HOME_DIR/.agents/skills/$n" ] || { cp -R "$d" "$HOME_DIR/.agents/skills/"; echo "settings: skill +$n"; }
    done
    chown -R "$USER:$USER" "$HOME_DIR/.agents" "$HOME_DIR/.config" "$HOME_DIR/AGENTS.md"
    shopt -u nullglob
  fi
  rm -rf "$HOME_DIR/.settings-src"
  echo "settings applied to slot $SLOT"
else
  echo "ERROR: could not clone SETTINGS_REPO '$SETTINGS_REPO'" >&2
  exit 1
fi