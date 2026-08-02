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
CODEX_CFG="$HOME/.codex"            # codex config + auth.json (per-slot)
CODEX_DATA="$HOME/.local/share/codex" # codex sessions/history
CODEX_XDG="$HOME/.config/codex"     # codex xdg config fallback
CLAUDE_CFG="$HOME/.claude"          # claude code state/auth
CLAUDE_JSON="$HOME/.claude.json"    # claude code main config+auth
CLAUDE_XDG="$HOME/.config/claude"   # claude settings.json template
CLAUDE_DATA="$HOME/.local/share/claude-code" # claude session .jsonl history
SHARED="$HOME/shared"            # per-slot shared folder (files that follow you)
PAIRS=(
  "$CFG         :.config/opencode"
  "$SKILLS      :.agents/skills"
  "$DATA        :.local/share/opencode"
  "$STATE       :.local/state/opencode"
  "$CODEX_CFG   :.codex"
  "$CODEX_DATA  :.local/share/codex"
  "$CODEX_XDG   :.config/codex"
  "$CLAUDE_CFG  :.claude"
  "$CLAUDE_JSON :.claude.json"
  "$CLAUDE_XDG  :.config/claude"
  "$CLAUDE_DATA :.local/share/claude-code"
  "$SHARED      :shared"
)

if [ "$CMD" = "info" ]; then
  echo "local  ->  slot '$SLOT' on $HOST (user $USER, sftp-only)"
  for pair in "${PAIRS[@]}"; do printf '  %-30s ->  ~%s\n' "${pair%%:*}" "${pair#*:}"; done
  if printf 'pwd\n' | sftp "${KEY_ARGS[@]}" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -b - "$DEST" >/dev/null 2>&1; then
    echo "OK - key auth to $DEST works"
  else
    echo "FAILED - ask the VM admin to add your ssh public key for user $USER" >&2
    exit 1
  fi
  exit 0
fi

if [ "$CMD" = "push" ]; then
  for pair in "${PAIRS[@]}"; do
    local_p="$(printf '%s' "${pair%%:*}" | tr -d ' ')"; remote_p="${pair#*:}"
    [ -e "$local_p" ] || { echo "skip: $local_p does not exist locally"; continue; }
    echo "push $local_p -> $DEST:$remote_p ..."
    if [ -d "$local_p" ]; then
      # Target dirs are pre-created by add-slot.sh (mkdir here would abort the
      # batch with "Failure" on an existing dir), so just upload into them.
      {
        printf 'cd %s\n' "$remote_p"
        printf 'lcd %s\n' "$local_p"
        printf 'put -r .\n'
      } | sftp "${KEY_ARGS[@]}" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -b - "$DEST" >/dev/null \
        || echo "  WARNING: push for $remote_p had issues"
    else
      # ponytail: a single FILE pair (e.g. ~/.claude.json) - scp it directly,
      # the remote target is a file path, not a dir.
      scp "${KEY_ARGS[@]}" -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$local_p" "$DEST:$remote_p" >/dev/null 2>&1 \
        || echo "  WARNING: push file $remote_p had issues"
    fi
  done
  echo "push done: slot '$SLOT' now mirrors this machine."
  echo "See it live from any device: https://$SLOT.<your-domain>  (URL shown by add-slot.sh)"
  exit 0
fi

# pull: back up local, then fetch each remote dir recursively via sftp batch
PULL_BACKUP="$HOME/opencode-connect-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$PULL_BACKUP"
for pair in "${PAIRS[@]}"; do
  local_p="$(printf '%s' "${pair%%:*}" | tr -d ' ')"; remote_p="${pair#*:}"
  [ -z "$remote_p" ] && continue
  [ -d "$local_p" ] && cp -a "$local_p" "$PULL_BACKUP/$(basename "$local_p")" 2>/dev/null || true
  # ponytail: some pairs are FILES (e.g. ~/.claude.json), so never mkdir a dir
  # over an existing file (that would crash under set -e on the same path).
  [ -e "$local_p" ] || mkdir -p "$local_p"
  echo "pull $DEST:$remote_p -> $local_p"
  if [ -d "$local_p" ]; then
    {
      printf 'cd %s\n' "$remote_p"
      printf 'lcd %s\n' "$local_p"
      printf 'get -r *\n'
    } | sftp "${KEY_ARGS[@]}" -o BatchMode=yes -b - "$DEST" >/dev/null || echo "  WARNING: sftp pull for $remote_p had issues (empty remote dir is fine)"
  else
    scp "${KEY_ARGS[@]}" -o BatchMode=yes "$DEST:$remote_p" "$local_p" >/dev/null 2>&1 \
      || echo "  WARNING: sftp pull file $remote_p had issues (remote missing is fine)"
  fi
done
echo "pull done; previous local state backed up under $PULL_BACKUP"