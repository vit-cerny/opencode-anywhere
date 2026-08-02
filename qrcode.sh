#!/usr/bin/env bash
# qrcode.sh - print a terminal ANSI QR code of the opencode-cloud HTTPS URL.
# Usage: qrcode.sh https://yourdomain.duckdns.org
# Requires: qrencode (installed by provision.sh; or 'apt install qrencode').
# The QR links the device to the URL; the login password is your OPENCODE_SERVER_PASSWORD.
set -euo pipefail

URL="${1:-}"
if [ -z "$URL" ]; then
  echo "usage: qrcode.sh https://yourdomain.duckdns.org" >&2
  exit 1
fi

if ! command -v qrencode >/dev/null 2>&1; then
  echo "ERROR: qrencode not found. Install it first: sudo apt install qrencode" >&2
  exit 1
fi

echo "Scan this QR with any phone camera:"
qrencode -t ANSIUTF8 -m 1 -o - "$URL"
echo
echo "URL: $URL"
echo "Then sign in with username 'opencode' (default) and your OPENCODE_SERVER_PASSWORD."
