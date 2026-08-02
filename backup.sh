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

# Backup contents are SENSITIVE: the archive includes auth.json files (live
# provider API keys) AND opencode-*.env (slot passwords when run as root).
# Keep backups on the box is fine (0600 home + 0700 backup dir) - if you sync
# off-box, use an encrypted destination (e.g. `rclone` with a `crypt:` remote),
# never a plain object store.
# Optional off-box sync: BACKUP_RCLONE_REMOTE=rclone-crypt-remote:backups backup.sh
#
# Include the ENTIRE slot (config + state + skills + chat/auth dirs) so a fresh
# box can be rebuilt from the archive alone. Root mode additionally captures the
# system files that recreate users/passwords/vhosts: per-slot env, slots.conf,
# Caddyfile, sshd slot drop-in. Exit early (no write) if HOME is broken so we
# never ship a read-only/partial tarball.
if [ ! -d "$HOME/.config" ] && [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: \$HOME ($HOME) has no .config - nothing to back up" >&2; exit 1
fi
if [ "$(id -u)" -eq 0 ]; then
  # Root mode: whole slot(s) + the system files that recreate users/vhosts
  # (slots.conf, per-slot password envs, Caddyfile, sshd slot drop-in).
  # Subshell + cd / so the SHELL expands the cl-* globs (GNU tar globs
  # against the current dir, not against a -C dir).
  ( cd / && tar czf "$TARBALL" --ignore-failed-read \
      home/cl-*/.local/share/opencode home/cl-*/.local/state/opencode \
      home/cl-*/.config/opencode home/cl-*/.agents/skills \
      home/cl-*/.claude home/cl-*/.claude.json home/cl-*/.codex \
      home/cl-*/AGENTS.md home/cl-*/shared \
      etc/opencode/slots.conf etc/opencode/*.env \
      etc/caddy/Caddyfile etc/ssh/sshd_config.d/99-opencode-slots.conf )
else
  tar czf "$TARBALL" --ignore-failed-read \
    -C "$HOME" .config/opencode .local/share/opencode .local/state/opencode \
                 .agents/skills .claude .claude.json .codex AGENTS.md shared
fi
chmod 0600 "$TARBALL"

# Optional off-box sync (best-effort; the box itself keeps the last 7 regardless).
# The archive holds provider keys + slot passwords: only allow destinations we
# can prove are encrypted (an rclone remote of type `crypt`), never a plain
# object store. Local dirs (./x, /x) are fine - no transport.
if [ -n "${BACKUP_RCLONE_REMOTE:-}" ]; then
  case "$BACKUP_RCLONE_REMOTE" in
    /*|./*) ;;  # local path: no transport, fine
    *:*) REMOTE_NAME="${BACKUP_RCLONE_REMOTE%%:*}";;
    *) echo "ERROR: BACKUP_RCLONE_REMOTE must be rclone-remote:path or a local dir" >&2; exit 1 ;;
  esac
  if [ -n "${REMOTE_NAME:-}" ]; then
    if command -v rclone >/dev/null 2>&1; then
      TYPE="$(rclone config show "$REMOTE_NAME" 2>/dev/null | grep -oE '^\s*type\s*=\s*\S+' | head -1 | awk '{print $3}')"
      if [ "$TYPE" != "crypt" ]; then
        echo "ERROR: BACKUP_RCLONE_REMOTE remote '$REMOTE_NAME' has type '$TYPE', not 'crypt' - backups hold API keys + slot passwords; refusing" >&2
        exit 1
      fi
      rclone copy "$TARBALL" "$BACKUP_RCLONE_REMOTE" && echo "synced off-box: $BACKUP_RCLONE_REMOTE"
    else
      echo "WARNING: BACKUP_RCLONE_REMOTE set but rclone is not installed; skipping off-box sync" >&2
    fi
  fi
fi

# Retention: keep the newest 7 backups.
ls -1t "$BACKUP_DIR"/opencode-*.tar.gz 2>/dev/null | tail -n +8 | xargs -r rm -f

echo "backup written: $TARBALL"
echo "backups kept:   $(ls -1 "$BACKUP_DIR"/opencode-*.tar.gz 2>/dev/null | wc -l)"
