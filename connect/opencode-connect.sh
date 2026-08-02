#!/usr/bin/env bash
# opencode-connect.sh - plug YOUR OWN local opencode into your cloud slot.
#
# Pushes/pulls your local opencode state (config, skills, MCPs, plugins,
# projects, chats, auth) between this machine and one slot on the
# opencode-anywhere VM, over sftp (slot users are sftp-only, key auth).
# Combined with the web UI (https://yourname.yourdomain.duckdns.org) every
# device sees the same settings and chats in realtime.
#
# Usage:
#   ./opencode-connect.sh <vm-ip> <slot-name> push|pull|info
#     push  - upload THIS machine's opencode state to the slot (overwrites slot)
#     pull  - download the slot's state to this machine (backs up local first)
#     info  - show the path mapping + test key auth
#   env: OPENCODE_CONNECT_KEY=/path/to/ssh-key   (optional)
set -euo pipefail

HOST="${1:-}"; SLOT="${2:-}"; CMD="${3:-}"
if [ -z "$HOST" ] || [ -z "$SLOT" ] || { [ "$CMD" != "push" ] && [ "$CMD" != "pull" ] && [ "$CMD" != "info" ]; }; then
  echo "usage: $0 <vm-ip> <slot-name> push|pull|info" >&2; exit 1
fi

USER="cl-$SLOT"
DEST="${USER}@${HOST}"
KEY_ARGS=()
[ -n "${OPENCODE_CONNECT_KEY_PATH:-}" ] && KEY_ARGS=(-i "$OPENCODE_CONNECT_KEY_PATH")
SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new)

CFG="$HOME/.config/opencode"        # config, MCPs, plugin config, agents
SKILLS="$HOME/.agents/skills"       # global skills (the skills CLI installs here)
DATA="$HOME/.local/share/opencode"  # chats, projects, auth.json - the state
STATE="$HOME/.local/state/opencode" # frecency / kv store (optional)
PAIRS=(
  "$CFG    :.config/opencode"
  "$SKILLS :.agents/skills"
  "$DATA   :.local/share/opencode"
  "$STATE  :.local/state/opencode"
)

if [ "$CMD" = "info" ]; then
  echo "local  ->  slot '$SLOT' on $HOST (user $USER, sftp-only)"
  for pair in "${PAIRS[@]}"; do printf '  %-30s ->  ~%s\n' "${pair%%:*}" "${pair#*:}"; done
  if ssh "${KEY_ARGS[@]}" "${SSH_OPTS[@]}" "$DEST" true 2>/dev/null; then
    echo "OK - key auth to $DEST works"
  else
    echo "FAILED - ask the VM admin to add your ssh public key for user $USER" >&2
    exit 1
  fi
  exit 0
fi

if [ "$CMD" = "push" ]; then
  for pair in "${PAIRS[@]}"; do
    local_p="${pair%%:*}"; remote_p="${pair#*:}"
    [ -d "$local_p" ] || { echo "skip: $local_p does not exist locally"; continue; }
    echo "push $local_p -> $DEST:$remote_p ..."
    ssh "${KEY_ARGS[@]}" "$DEST" "mkdir -p '$remote_p'"
    scp "${KEY_ARGS[@]}" -q -r "$local_p/." "$DEST:$remote_p/"
  done
  echo "push done: slot '$SLOT' now mirrors this machine."
  echo "See it live from any device: https://$SLOT.<your-domain>  (URL shown by add-slot.sh)"
  exit 0
fi

# pull: back up local, then fetch each remote dir recursively via sftp batch
PULL_BACKUP="$HOME/opencode-connect-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$PULL_BACKUP"
for pair in "${PAIRS[@]}"; do
  local_p="${pair%%:*}"; remote_p="${pair#*:}"
  [ -z "$remote_p" ] && continue
  [ -d "$local_p" ] && cp -a "$local_p" "$PULL_BACKUP/$(basename "$local_p")" 2>/dev/null || true
  mkdir -p "$local_p"
  echo "pull $DEST:$remote_p -> $local_p"
  {
    printf 'cd %s\n' "$remote_p"
    printf 'lcd %s\n' "$local_p"
    printf 'get -r *\n'
  } | sftp "${KEY_ARGS[@]}" -o BatchMode=yes -b - "$DEST" >/dev/null || echo "  WARNING: sftp pull for $remote_p had issues (empty remote dir is fine)"
done
echo "pull done; previous local state backed up under $PULL_BACKUP"