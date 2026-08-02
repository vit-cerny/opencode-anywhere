#!/usr/bin/env bash
# restore.sh - list local backups and extract one over the live opencode state.
# Usage: restore.sh            (interactive: pick a backup from ~/backups/)
#        restore.sh <file>    (restore a specific backup directly)
# Stops the opencode-web service first when running with enough privileges, then restarts it.
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-$HOME/backups}"
BACKUPS=("$BACKUP_DIR"/opencode-*.tar.gz)

if ! compgen -G "$BACKUP_DIR/opencode-*.tar.gz" >/dev/null 2>&1; then
  echo "ERROR: no backups found in $BACKUP_DIR (run backup.sh first)" >&2
  exit 1
fi

if [ $# -ge 1 ]; then
  FILE="$1"
else
  echo "Available backups:"
  i=1
  for b in "${BACKUPS[@]}"; do printf '  %d) %s\n' "$i" "$b"; i=$((i + 1)); done
  read -r -p "Enter the number to restore: " N
  FILE="${BACKUPS[$((N - 1))]}"
fi

[ -f "$FILE" ] || { echo "ERROR: backup not found: $FILE" >&2; exit 1; }

# Stop the slot's own unit(s) while overwriting live state (best-effort; root
# needed). Real units are named opencode-web-<slot> - stop every one whose
# service User matches $USER (the never-existent literal "opencode-web" unit
# would silently do nothing, then extract over a LIVE sqlite store).
RESTART=()
if command -v systemctl >/dev/null 2>&1; then
  for UNIT in $(systemctl list-unit-files --type=service --no-legend 2>/dev/null | awk '/^opencode-web-/ {print $1}' | sed 's/\.service$//'); do
    if systemctl show "$UNIT" -p User --no-pager 2>/dev/null | grep -q "User=$USER$"; then
      if systemctl stop "$UNIT" 2>/dev/null; then RESTART+=("$UNIT"); else
        echo "WARNING: could not stop $UNIT (run as root to stop/restart it)" >&2
      fi
    fi
  done
fi

tar xzf "$FILE" -C "$HOME"
echo "restored: $FILE"

for UNIT in "${RESTART[@]}"; do systemctl start "$UNIT"; done
