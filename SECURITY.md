# Security Policy

## Reporting a vulnerability

Open an issue on this repo, or a private GitHub advisory
(https://github.com/vit-cerny/opencode-anywhere/security/advisories) for
anything that could let one slot read another slot's data, an attacker reach
services other than the intended TLS endpoints, or credential/secret leakage.
Indicate severity (the guidance below is a good baseline). No bounty program.

## Trust model

- Each slot is an isolated Linux user with its own home dirs, own environment
  file (password), own systemd unit and own Caddy vhost. Slots share nothing.
- The web auth for each slot is opencode's own basic auth over TLS
  (`OPENCODE_SERVER_PASSWORD`, enforced by `OPENCODE_SERVER_PASSWORD` server
  internally: 401 without login). Caddy does not see passwords; it rate-limits
  (20 req/min/IP per vhost) against brute force.
- Slot users on SSH are sftp-only (`ForceCommand internal-sftp`,
  `PasswordAuthentication no`): their only inbound channel is file transfer for
  the `connect` client. They have no shell on the VM.
- The VM admin (ubuntu/root) is the trust root for all slots — same as any
  single-tenant host. Slots are isolated *from each other*, not from root.

## What this repo never does

- No secrets in the repository (enforced by the CI gate on every push —
  personal names, API-key patterns, `OPENCODE_SERVER_PASSWORD` literal values,
  private keys, OCI resource IDs are all scanned).
- No `curl | sh` / `iwr | iex` installers: Node tarball from nodejs.org,
  `opencode-ai` pinned via npm, Caddy from its signed apt repo (key pinned via
  `gpg --dearmor`).
- No password SSH on the VM (`PasswordAuthentication no`, `PermitRootLogin no`).
- opencode binds loopback only; only Caddy (TLS) is exposed.

## Running production-like

- Use strong unique passwords per slot (min 12 chars — enforced by the scripts).
- Keep `/etc/opencode/<slot>.env` 0600 root-owned (the scripts do; verify after
  any manual edits).
- `ufw` shows exactly 22/80/443; the Oracle VCN security list must also be 22/80/443.
- Backups contain `auth.json` (provider keys). Keep them on the box is fine
  (0600 home), off-box must be encrypted (e.g. rclone `crypt:` remote).
- Rate limiting is a mitigation, not a guarantee.

## Supply chain

- Pinned versions: Node `v24.18.1`, `opencode-ai@1.18.11`. The scripts are
  idempotent and skip already-correct installs so the pins stay effective.
- If a pinned dependency is compromised, bump the pin and push — the CI gate
  re-verifies the whole repo on the new commit.
- Skills and plugins are third-party agent code — they run with the agent's
  permissions. The bundled local skills list is fixed and vetted; users adding
  their own skills/plugins accept that trust model (same as any agent
  extension).

## Report handling

Fix first, disclose after, no drafts, no CVE spam. Reporters get a reply within
72h.