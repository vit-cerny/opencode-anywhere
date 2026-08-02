#!/usr/bin/env bash
# backup.sh - nightly-style tar.gz of opencode state (chat history, projects, config, MCP state)
# into ~/backups/ with timestamped names, keeping the newest 7.
# Run as the opencode service user (or root, BACKUP_DIR overridable):
#   sudo -u opencode /usr/local/bin/backup.sh
set -euo pipefail

# The archive holds auth.json (live provider API keys): every file we touch
# here must stay private to the admin. umask 077 + 0700 dir + 0600 tarball.
umask 077
BACKUP_DIR="${BACKUP_DIR:-$HOME/backups}"
mkdir -p "$BACKUP_DIR"
chmod 0700 "$BACKUP_DIR"

STAMP="$(date +%Y%m%d-%H%M%S)"
TARBALL="$BACKUP_DIR/opencode-$STAMP.tar.gz"

# Backup contents are SENSITIVE: the archive includes ~/.local/share/opencode which
# holds auth.json (your AI provider API keys). Keep backups on the box is fine (0600
# home + 0700 backup dir), but if you sync off-box, use an encrypted destination
# (e.g. `rclone` with a `crypt:` remote) - never a plain object store.
# Optional off-box sync: BACKUP_RCLONE_REMOTE=rclone-crypt-remote:backups backup.sh
tar czf "$TARBALL" --ignore-failed-read -C "$HOME" .config/opencode .local/share/opencode
chmod 0600 "$TARBALL"

# Optional off-box sync (best-effort; the box itself keeps the last 7 regardless).
if [ -n "${BACKUP_RCLONE_REMOTE:-}" ]; then
  if command -v rclone >/dev/null 2>&1; then
    rclone copy "$TARBALL" "$BACKUP_RCLONE_REMOTE" && echo "synced off-box: $BACKUP_RCLONE_REMOTE"
  else
    echo "WARNING: BACKUP_RCLONE_REMOTE set but rclone is not installed; skipping off-box sync" >&2
  fi
fi

# Retention: keep the newest 7 backups.
ls -1t "$BACKUP_DIR"/opencode-*.tar.gz 2>/dev/null | tail -n +8 | xargs -r rm -f

echo "backup written: $TARBALL"
echo "backups kept:   $(ls -1 "$BACKUP_DIR"/opencode-*.tar.gz 2>/dev/null | wc -l)"
