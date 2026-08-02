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

# Stop the service while overwriting live state (best-effort; service control needs root).
RESTART=0
if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet opencode-web 2>/dev/null; then
  if systemctl stop opencode-web 2>/dev/null; then RESTART=1; else
    echo "WARNING: could not stop opencode-web (run as root to stop/restart it)" >&2
  fi
fi

tar xzf "$FILE" -C "$HOME"
echo "restored: $FILE"

if [ "$RESTART" -eq 1 ]; then systemctl start opencode-web; fi
