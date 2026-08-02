#!/usr/bin/env bash
# adopt.sh - bring YOUR WHOLE opencode server onto a brand-new machine.
#
# Reads sync/goto.env (you create it once - copy goto.env.example), finds your
# VM + slot, then pulls that slot's config, skills, plugins, MCPs, projects and
# chats down to THIS machine using the bundled opencode-connect client. After
# that this machine is a first-class member of your setup - push edits back up,
# or pull any time to refresh. Safe to re-run (pull backs up local state first).
#
# Security: goto.env holds NO passwords/tokens/keys. Authentication is your
# existing SSH key, exactly like connect. Nothing here ever touches git.
#
# Usage:
#   bash sync/adopt.sh          # pull the slot down to this machine (default)
#   bash sync/adopt.sh push     # send THIS machine's state up to the slot
#   bash sync/adopt.sh info     # show the path map + test key auth
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/.." && pwd)"

# --- 1. find the GOTO file (sync/goto.env first, then repo-root goto.env) ---
GOTO=""
for cand in "$DIR/goto.env" "$REPO/goto.env"; do
  if [ -f "$cand" ]; then GOTO="$cand"; break; fi
done
if [ -z "$GOTO" ]; then
  echo "No goto.env found yet. Create it once, then re-run:"
  echo "  cp $DIR/goto.env.example $DIR/goto.env"
  echo "  # edit VM_IP= and SLOT=  (see docs/GOTO.md)" >&2
  exit 1
fi

# --- 2. load only the plain values goto.env is allowed to hold ---
set -a
# shellcheck disable=SC1090
. "$GOTO"
set +a
VM_IP="${VM_IP:-}"; SLOT="${SLOT:-}"
if [ -z "$VM_IP" ]; then echo "goto.env is missing VM_IP=" >&2; exit 1; fi
if [ -z "$SLOT" ];  then echo "goto.env is missing SLOT="  >&2; exit 1; fi

# --- 3. which way are we going? (default: pull the server down onto this PC) ---
CMD="${1:-pull}"
case "$CMD" in
  push|pull|info) ;;
  *) echo "usage: $0 [push|pull|info]" >&2; exit 1 ;;
esac

echo "adopt: '$CMD' slot '$SLOT' on $VM_IP into this machine..."
# Reuse the bundled connect client (no new deps, it does the sftp/ssh work).
bash "$REPO/connect/opencode-connect.sh" "$VM_IP" "$SLOT" "$CMD"

echo
echo "done. This PC now shares the '$SLOT' slot. Next steps:"
echo "  - run opencode locally:  opencode"
if [ -n "${DOMAIN:-}" ]; then echo "  - or the live web UI:   https://$SLOT.$DOMAIN"; fi
echo "  - refresh later:         bash sync/adopt.sh pull"