# Loop status (opencode-anywhere) — updated by the agent each iteration

Do not delete me: the autonomous loop reads this file every cycle to reconstruct
state after context compaction. Keep entries short, factual, machine-checkable.

## Status: e2e VERIFIED locally; deploy still BLOCKED on user Oracle account — last updated 2026-08-02

### Done (verified)
- v1 fixes in `opencode-cloud` (upstream base): commit `b4cb08c` — umask-077
  leak scoping, skills CLI `owner/repo@skill` syntax, Caddy keyring perms.
- v2 repo `vit-cerny/opencode-anywhere` (public) pushed at `9d86734`; CI
  scheduled (gate ubuntu/windows + multi-slot smoke with cross-slot 401 assert).
- Sandbox e2e (WSL2 Ubuntu 24.04, domain `sandbox.localhost`), ALL PASSING:
  - provision.sh → slot `me` boots (`opencode-web-me.service` active,
    127.0.0.1:41004), Caddy v2.11.4 (official pinned binary tarball +
    upstream-checksum path; NOT apt) active on :80/:443 with internal TLS for
    both vhosts; `admin off` is now a GLOBAL Caddyfile option (was wrongly a
    site directive in the apt build).
  - auth matrix over HTTPS via Caddy: me 401→200; me+alice-pw→401;
    alice 401→200; alice+me-pw→401. Cross-slot isolation confirmed.
  - SSE `/global/event` authenticated → 200.
  - connect client `push` verified: client projects.json + opencode.jsonc
    (model entry) landed in `/home/cl-me/...`; `info` key-auth OK; `pull`
    round-trip into a scratch dir OK (backs up local first).
- Bundled-14 skills: only PromptScript-type (docx/pdf/pptx/xlsx) reject global
  install by design; markdown skills (ponytail) install fine. Best-effort step.
- Bugs found during e2e and FIXED in the working tree (uncommitted):
  1. Caddy arch mismatch (`NODE_ARCH=x64` vs Caddy asset `amd64`) → added
     `CADDY_ARCH` map (x86_64→amd64, arm64→arm64).
  2. Caddy systemd unit failed under `ProtectSystem=strict` (pki data dir)
     → dedicated `WorkingDirectory=/var/lib/caddy` (created by provision) +
     env XDG dirs + `ReadWritePaths=/var/lib/caddy /etc/caddy`.
  3. provision re-run wiped vhosts → Caddyfile only seeded if absent.
  4. `add-slot.sh`: vhost now proxy-only + idempotent (awk removes an existing
     `<user>.<domain>` block before appending, so stale `rate_limit` blocks
     never accumulate); `mkdir -p /etc/ssh/sshd_config.d` added.
  5. `connect/opencode-connect.sh`: sftp-native (no remote shell) — info uses
     sftp `pwd`, push uses sftp `mkdir`/`cd`/`lcd`/`put -r .`; trim padding
     whitespace in PAIRS matching; drop `mkdir` (target dirs pre-created).
  - `bash -n` clean on all *.sh; removed stale `rate_limit` (not in official
    caddy binary) from add-slot + check.ps1 + docs.

### Next (ordered)
1. Sync working tree → `git add` + commit the e2e fixes (message: provision
   hardened, connect sftp-native, e2e) — commit WITHOUT `.github/...` only if
   needed for workflow-scope; else single commit + push `main`.
2. Confirm GitHub Actions (gate + smoke) green on the pushed commit.
3. Update README/SECURITY wording already reflects: static Caddy binary +
   checksum; proxy-only vhosts; per-slot pw brute-force stance.
4. RE-DEPLOY BLOCKED: set up a free Oracle Cloud Always-Free VM + SSH keys +
   DuckDNS subdomain → run provision → add slots for real users. Cannot do
   without user's Oracle account/credentials; do NOT silently loop.

### Verifier rules (anti-Goodhart)
- Gate (`scripts/check.ps1`) is the only authority for "repo safe".
- Smoke/CI are the only authority for "serves + auths".
- Never delete/weaken tests to make them pass; fix the code instead.