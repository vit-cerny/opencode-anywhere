# Bring your own: settings, sync, and keep-alive

Short, concrete how-to for **you**, the slot owner: reuse the settings you
already have, understand what's realtime vs on-demand, and keep the VM alive
forever with the loops already shipped. Assumes an **Oracle Cloud Always Free**
VM (no cloud lock-in — every step runs on any Ubuntu VPS with identical
scripts). The `me` slot below is your owner slot; swap in your real name.

---

## 1. Use the settings you already have (`SETTINGS_REPO`)

A **settings repo** is a *private* git repo whose contents get seeded into every
slot you point at it (`SETTINGS_REPO=` on `add-slot.sh` / `provision.sh`, or
`./scripts/seed-settings.sh <slot> <repo>` later). When you log into any slot,
that slot already carries **your** config, not the shared template.

### What each slot actually turns into your settings

| Your file (repo)            | Landed in the slot                                  | Seeded? |
| --------------------------- | --------------------------------------------------- | ------- |
| `opencode.jsonc`            | `~/.config/opencode/opencode.jsonc`                 | ✅ yes |
| `AGENTS.md`                 | `~/AGENTS.md`  (repo-relative; opencode scans the slot home)  | ✅ yes |
| `skills/<name>/…`           | `~/.agents/skills/<name>/…`   (merged by name, no-clobber) | ✅ yes |
| MCP servers + permissions   | the `"mcp"` block **inside your `opencode.jsonc`** (opencode's key is `mcp`, not `mcpServers`) | ✅ yes (via the jsonc) |
| plugin code                 | **NOT seeded** by the repo | ❌ see below |

Where things live **in opencode** (so you know what you're copying):

- **Config** is `~/.config/opencode/opencode.jsonc` — opencode's *custom config
  path* (not `~/.opencode`). This one file holds the `mcp` map (each MCP is
  `local`/`remote` with `command`/`url`), `permission` guardrails, and `agent`
  subagents. Not `mcpServers` — that key is Claude-Desktop style; opencode uses
  `mcp`.
- **Skills** are per-slot folders `~/.agents/skills/<name>/SKILL.md` (the source
  of `skills/` in your repo).
- **Plugins** live in `~/.config/opencode/plugin/<name>/{package.json,index.js,…}`.
  They are **not** auto-seeded by the settings repo (seed covers the 3 files
  above). Carry them via `connect push` (below) — the whole `.config/opencode`
  moves, `plugin/` included — or drop the folder into the slot by hand.
  MCP *config* on the other hand rides inside your jsonc, so it *is* seeded.

> `{{HOME}}` in the seeded config is substituted per-slot so absolute paths land
> in the right home. First-writer-wins: a seeded file only replaces the **fresh
> template default**, never a config you customized or pulled via `connect`.
>
> **Seeding is one-shot, not a watcher**: settings are copied at slot creation
> (or when you re-run `seed-settings.sh`). The slot never auto-pulls the repo —
> if you change `opencode-defaults`, re-run the seed to refresh the slot.

### Copy from your current machine → repo (one command set)

```bash
# on any PC that has the opencode you like:
mkdir -p settings && cd settings
git init -b main
cp ~/.config/opencode/opencode.jsonc opencode.jsonc
cp ~/.config/opencode/AGENTS.md AGENTS.md 2>/dev/null || true
cp -r ~/.agents/skills skills 2>/dev/null || true
# keep secrets OUT of a repo you may share:
printf '**/auth.json\n*.env\n.claude.json\n.codex/auth.json\nplugin/**/*.json\n' > .gitignore
git add -A && git commit -m "my opencode defaults"
gh repo create <your-name>/opencode-defaults --private --source . --push
```

Windows (PowerShell) equivalent of the copy, in one line:

```powershell
$d=Join-Path $env:USERPROFILE ".config\opencode"; New-Item -ItemType Directory -Force -Path settings | Out-Null
Copy-Item $d\opencode.jsonc settings\opencode.jsonc; Copy-Item $d\AGENTS.md settings\AGENTS.md -ErrorAction SilentlyContinue
Copy-Item "$env:USERPROFILE\.agents\skills" settings\skills -Recurse -ErrorAction SilentlyContinue
```

Then point your slot at it and log in from any device — same skills, MCPs,
agents, guardrails everywhere:

```bash
SETTINGS_REPO='https://github.com/<your-name>/opencode-defaults' \
  OPENCODE_SERVER_PASSWORD='a-strong-password' ./add-slot.sh <slot>
# or later, as root:  ./scripts/seed-settings.sh <slot> https://github.com/<you>/opencode-defaults
```

---

## 2. Realtime web vs on-demand `connect` — the honest difference

Two sync surfaces; do not expect "realtime" from the second.

| | **Web UI** (`https://<you>.<your-domain>`) | **`connect`** (`push`/`pull`) |
| --- | --- | --- |
| Mode | **Realtime**, server-side, live | On-demand, sftp, local-first |
| Where chats live | In the slot's server home `.local/share/opencode` — so every **browser** you log into that slot sees the **same** conversations | Your *local* opencode's home unless you push/pull |
| Projects/files | `~/shared/` on the slot — visible to **every connected browser** instantly | Move with `push`/`pull` (incl. `shared/`) |
| When to use | Day-to-day: phone/PC from anywhere, instant | First import into a slot, or mirror down to a **new machine** |
| Does a local desktop copy sync automatically? | **No.** | No — only when you run it |

**The honest catch you asked about:** conversations/files you edit in a **local
desktop opencode** (not through the web UI) are **not** synced anywhere on their
own. To bring them in, `push` (Windows: `pwsh -File connect\opencode-connect.ps1 …
push`). To re-open the slot's realtime state locally, `pull`. The web UI and
`connect` are *complementary*: web for live multi-device work, `connect` for
bulk moving state. Nothing does "realtime" for a desktop session automatically.

```bash
# import THIS machine into the slot:  ./connect/opencode-connect.sh <vm-ip> <slot> push
# clone the slot down (new PC):        ./connect/opencode-connect.sh <vm-ip> <slot> pull
```

---

## 3. Loop coding / keep-alive (already running, free)

The box is already a set of always-on loops; you paid nothing extra:

- **Each slot** is a systemd unit `opencode-web-<slot>` with `Restart=always`
  and `RestartSec=5`, `systemctl enable`d — a crash or reboot brings it back on
  its own.
- **`caddy`** ↔ Let's Encrypt auto-renews TLS every ~60 days; `systemctl reload
  caddy` picks up slot changes.
- **Backups** — documented cron (`0 */6 * * * sudo -u cl-me
  /usr/local/bin/backup.sh`) keeps a 0600 tarball of config + chats + `shared/`
  (last 7), optionally synced **encrypted** off-box via `BACKUP_RCLONE_REMOTE`.
- **Updates** — weekly one-liner keeps the box patched:
  `sudo apt update && sudo apt -y full-upgrade` (or
  `sudo unattended-upgrades` if you turned that on).
- **Oracle idle-reclaim guard** — documented `*/5` curl keepalive cron so the
  free instance is never "idle".

### Optional 5-minute health loop (new: `scripts/health-loop.sh`)

A slot that stays `active` but stops answering its port is the one case
`Restart=always` handles lazily. This tiny loop (no deps, idempotent) probes each
slot's HTTP port and restarts only a *wedged* unit, never fighting
`Restart=always`'s own backoff:

```bash
sudo install -m 0755 scripts/health-loop.sh /usr/local/bin/health-loop.sh
sudo crontab -e        # add:
*/5 * * * * /usr/local/bin/health-loop.sh >>/var/log/opencode-health.log 2>&1
```

Each line prints a `PRUNED` marker when it restarts / leaves a unit to recover,
`OK` otherwise. First run by hand to see the per-slot status table:

```bash
sudo bash scripts/health-loop.sh
# OK me (:$41000 http=401)      <-- 401 is *alive* (needs auth); 000 would mean dead
```

---

## 4. No cloud lock-in

These scripts are not tied to Oracle. They run on any **Ubuntu VPS** (or a
second Oracle box) with the identical steps: `setup.sh` → slots. Domain can be
DuckDNS, a real domain, or an IP. Nothing in this repo requires Oracle APIs;
recovery from any lost VM is the short drill: new VPS → `provision.sh` →
`restore.sh`, and your chats/config are back from the last backup. You own the
private settings repo and the backup tarballs — the host is just compute.