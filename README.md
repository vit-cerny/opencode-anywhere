# opencode-anywhere

**You (or anyone) plug your own opencode into a free always-on cloud VM and get
the same settings, skills, plugins, MCPs, projects and chats — in realtime —
from any PC or phone. Zero cost, permanent host, no PC left on.**

- **Realtime, any device** — the VM runs `opencode web` per *slot* (one isolated
  server per user). Any browser is a full client of the same server-side state:
  your phone and your PCs see the same chats/projects the moment they change.
- **Bring your own everything** — every user's slot starts minimal; the
  `connect` client pushes *your* `~/.config/opencode` (config, MCPs, plugins),
  `~/.agents/skills` (skills), `~/.local/share/opencode` (chats, projects,
  auth) and `~/.local/state/opencode` (frecency/kv) into your slot — or pulls
  them back down to any fresh machine.
- **Free forever** — runs on an Oracle Cloud **Always Free** VM (the only free
  *permanent* always-on cloud in 2026), or any ~\$5/mo VPS with identical steps.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Security gate](https://github.com/vit-cerny/opencode-anywhere/actions/workflows/security.yml/badge.svg)](https://github.com/vit-cerny/opencode-anywhere/actions/workflows/security.yml)

## From any machine in 3 commands (adopt)

Got a brand-new PC, laptop, or a friend's machine? Take your **whole server**
with you using one tiny pointer file. It stores only your VM's IP and your slot
name — no passwords, keys, or tokens.

1. **Grab the repo:**
   ```bash
   git clone https://github.com/vit-cerny/opencode-anywhere.git && cd opencode-anywhere
   ```
2. **Create `sync/goto.env` once** (copy the example, fill in `VM_IP` and `SLOT`):
   ```bash
   cp sync/goto.env.example sync/goto.env
   # then edit:  VM_IP=<your vm ip>   SLOT=me
   ```
3. **Adopt your whole server onto this machine:**
   ```bash
   bash sync/adopt.sh         # Linux/macOS   → pulls slot down to this PC
   pwsh -File sync/adopt-windows.ps1          # Windows
   ```

That's it — your config, skills, plugins, MCPs, projects and chats land here.
Re-run any time to refresh, or `bash sync/adopt.sh push` to send this PC's state
up instead. Full plain-English walkthrough: **[docs/GOTO.md](docs/GOTO.md)**.

## How it works

```
                    ┌──────────────────────────────  your VM (free/paid)  ──────────────────────────────┐
 [phone] ─┐         │   Caddy :443 (Let's Encrypt, rate-limited)                                          │
 [PC #1] ─┼─ HTTPS─▶│      │ user "me"     vhost: me.yourdomain.duckdns.org  ─▶ opencode web :41000         │
 [PC #2] ─┘         │      │ user "alice"  vhost: alice.yourdomain.duckdns.org ─▶ opencode web :41001      │
 [laptop]           │      │ user "bob"    ... add-slot.sh per user (isolated systemd unit + files)        │
                    │      └───────────────────────────────────────────────────────────────────────────────┘
 [any opencode install]                                                                                      ▲
   connect client (scp/sftp) ──push/pull──▶ per-user dirs: ~/.config/opencode, ~/.agents/skills, ~/.local/share/opencode
```

Every slot is a fully isolated opencode web: its own Linux user, own
subdomain+port, own password, own files. Slots never share state. The web UI is
**realtime** (server-authoritative state, browser clients). The `connect`
client is the **bring-your-own** bridge: import/export your existing opencode
world into a slot, or clone a slot down to a brand-new machine.

> Realtime, honestly: every device reads/writes the same server-side
> workspace, so state stays in sync instantly — but this is *your* session
> from anywhere, not a multi-user collaborative editor. Two devices can open
> the same project and see the same files; they are not designed to co-edit
> one message simultaneously. `connect push/pull` is for importing/exporting
> bulk state; the web is for day-to-day realtime work.

## Free-tier reality (read before deploying)

| Option | Free forever? | Reality | Verdict |
| --- | --- | --- | --- |
| **Oracle Cloud Always Free** | ✅ Yes | Real always-on VM: AMD micro (1 OCPU/1GB) or Ampere A1 (2 OCPU/12GB, arm64), 200GB disk. Caveats: signup friction (identity card), regional capacity, idle-reclaim policy | ✅ **Chosen** |
| Fly.io | ❌ No | No free tier for new accounts | ❌ |
| Render (free) | ⚠️ Technically | Sleeps after 15 min + ephemeral FS (chats vanish on deploy) | ❌ |
| Hetzner / Railway | ❌ No | Trial credits expire | ❌ |

Honest limits: no free cloud is a 100% SLA — Oracle may reclaim instances idle
for ~7 days (keepalive cron below mitigates) and suspends accounts with no
sign-in for 30 days. If hard uptime is required, a ~\$5/mo VPS works with the
identical scripts. Recovery after any termination is a ~20-minute drill:
new VM → `provision.sh` → `restore.sh`.

## Deploy (20 minutes, one-time)

> Full step-by-step: **[DEPLOY.md](DEPLOY.md)** · how files save/sync in realtime:
> **[docs/FILES.md](docs/FILES.md)**.

1. **Oracle**: sign up at [oracle.com/cloud/free](https://www.oracle.com/cloud/free/)
   (free account; card is for identity only). Console → *Create a VM instance* →
   **Ubuntu 22.04/24.04** → shape **VM.Standard.E2.1.Micro** (AMD) or
   **VM.Standard.A1.Flex** (Ampere) → paste your **SSH public key** → Create.
   Two steps people miss:
   - **Reserve the public IP** (Networking → IP management) — free, keeps your
     DuckDNS A record stable across reboots.
   - **Open VCN ingress TCP 22, 80, 443** (Networking → VCN → security list).
     Oracle's VCN is a *second* firewall; `ufw` alone is not enough.
2. **DuckDNS**: free subdomain at [duckdns.org](https://www.duckdns.org) → add an
   **A record** pointing at the VM's public IP.
3. **SSH in and run the one-line installer** (installs git, clones the repo,
   then asks 3 questions — domain, owner password, optional settings repo):

   ```bash
   ssh ubuntu@<vm-ip>
   curl -fsSL https://raw.githubusercontent.com/vit-cerny/opencode-anywhere/main/setup.sh | sudo bash
   ```

   This creates your first slot, **`me`**, at `https://me.yourname.duckdns.org`
   (sign in as `opencode` + that password), installs the 14 bundled community
   skills into it, and locks the firewall to 22/80/443. Caddy is installed from
   the official pinned binary tarball (checksum-verified), not an apt repo.
   Also installs the pinned global CLIs `codex` (@openai/codex) and `claude`
   (@anthropic-ai/claude-code) so every slot user can use them — sign in once
   inside your slot (web/ttyd or `connect push`) and your tokens stay in your
   slot's home, never in git.

4. **Add slots for other people** (each gets a separate password/live):

   ```bash
   # the one-liner installs the repo at /opt/opencode-anywhere:
   cd /opt/opencode-anywhere
   OPENCODE_SERVER_PASSWORD='a-strong-password-for-alice' sudo ./add-slot.sh alice
   # → https://alice.yourname.duckdns.org   (also prints its sftp user cl-alice)
   ```

   `list-slots.sh` shows every slot; `remove-slot.sh` kills one.

## Connect: plug any opencode install into a slot

On each user's own machine (desktop or laptop), with their slot name:

```bash
# Linux / macOS
git clone https://github.com/vit-cerny/opencode-anywhere.git
cd opencode-anywhere/connect
./opencode-connect.sh <vm-ip> alice info      # check key auth (see below)
./opencode-connect.sh <vm-ip> alice push     # import THIS machine into the slot
./opencode-connect.sh <vm-ip> alice pull     # mirror the slot back down (new PC)
```

```powershell
# Windows (PowerShell 7; Windows OpenSSH ships with the OS)
git clone https://github.com/vit-cerny/opencode-anywhere.git
cd opencode-anywhere\connect
pwsh -File opencode-connect.ps1 <vm-ip> alice push
```

First, the VM admin must register the user's public key for the sftp user:

```bash
# on the VM, for slot "alice":
sudo -u cl-alice bash -c 'mkdir -p ~/.ssh && echo "<alice public key>" >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys'
sudo -u cl-alice bash -c 'chown -R cl-alice:cl-alice ~/.ssh'
```

What moves: `~/.config/opencode` (config + MCPs + plugin configs + agents),
`~/.agents/skills` (your skill library), `~/.local/share/opencode` (chat
history, projects, `auth.json`), `~/.local/state/opencode`. Push overwrites the
slot's copy; pull backs your local state up first. Codex (`~/.codex`,
`~/.config/codex`, `~/.local/share/codex`) and Claude Code (`~/.claude`,
`~/.claude.json`, `~/.config/claude`, `~/.local/share/claude-code`) state moves
the same way — sign in once per slot (its token stays in the slot's home, never
in git).

## Your own settings in real time

Out of the box every slot starts from the repo's shared template. If you want
**your** opencode config — same `opencode.jsonc`, `AGENTS.md`, and `skills/`
library — to follow you to *every* device the moment you log into a slot, point
a slot at your own private settings repo with `SETTINGS_REPO`.

> Security note: your settings repo is **private on GitHub** — it may hold your
> real model provider choices and paths. It must never contain API keys,
> `auth.json`, or `*.env`. The server clones it *into the slot's home dir* only;
> nothing is pushed back into your repo, and session tokens stay in the slot.

**Make your settings repo** (one-time, on any PC):

```bash
# a PRIVATE repo holding exactly what opencode reads from your machine
git init settings && cd settings
cp ~/.config/opencode/opencode.jsonc opencode.jsonc   # your real config
cp ~/.config/opencode/AGENTS.md AGENTS.md             # your behavior rules
cp -r ~/.agents/skills skills                          # your skills, optional
printf '**/auth.json\n*.env\n.claude.json\n.codex/auth.json\n' > .gitignore
gh repo create <your-name>/opencode-defaults --private --source . --push
```

**Point a slot at it** (`SETTINGS_REPO` is a git URL or a local path on the VM):

```bash
SETTINGS_REPO='https://github.com/<your-name>/opencode-defaults' \
  OPENCODE_SERVER_PASSWORD='a-strong-password' ./add-slot.sh <slot>
```

or bake it into your *own* first slot during provisioning:

```bash
sudo OPENCODE_SERVER_PASSWORD='a-strong-password' \
  SETTINGS_REPO='https://github.com/<your-name>/opencode-defaults' \
  ./provision.sh <your-domain>.<ext>
```

or apply it to an **existing** slot later (as root):

```bash
./scripts/seed-settings.sh <slot> https://github.com/<your-name>/opencode-defaults
```

**Then roam across devices** — any phone/PC that can reach the VM logs into the
same web slot and sees that configuration: your skills, MCP servers, agents and
permission guardrails are the same everywhere, in realtime. Edit the repo on
device *A*, reseed the slot, log in from device *B* — same opencode.

**First-writer-wins** keeps the slot safe: a settings file is applied only if
the slot doesn't already have one, *or* it still holds the untouched template
default — it never clobbers a config you've since customized or pulled down via
`connect`. Skills are merged by name, no-overwrite.

## Day-to-day

- **Realtime from any device**: open `https://<you>.<yourdomain>` in any
  browser (or scan the QR: `qrcode.sh https://you.yourdomain` on the VM).
- **Bulk import/export**: `connect push`/`pull` per place.
- **Backups**: `sudo -u cl-me /usr/local/bin/backup.sh` creates
  `~/backups/opencode-<stamp>.tar.gz` (keeps 7); `restore.sh` rebuilds a slot
  anywhere. Set `BACKUP_RCLONE_REMOTE` for encrypted off-box copies.

Add a keepalive cron on the VM so the instance is never idle enough to reclaim:
```bash
sudo crontab -e   # add:
*/5 * * * * curl -fsS https://me.yourdomain.duckdns.org >/dev/null 2>&1
```

## Security checklist (per slot)

- [ ] Every slot has its own password (min 12 chars, enforced) and its own subdomain
- [ ] Slot users are `sftp-only` with `ForceCommand internal-sftp`, no passwords SSH
- [ ] opencode binds loopback only; only Caddy (TLS) is exposed
- [ ] Firewall = exactly 22/80/443; TLS only via Caddy (Let's Encrypt);
      per-slot brute-force protection = strong unique per-slot passwords
- [ ] `/etc/opencode/<slot>.env` is root-only 0600; repo has no secrets (CI gate enforced)
- [ ] `/etc/opencode/<slot>.env` is root-only 0600; repo has no secrets (CI gate enforced)
- [ ] `opencode-ai` + Node + `codex` + `claude-code` versions pinned; auto-update disabled server-side
- [ ] MCP guardrails on: `playwright_browser_run_code_unsafe=deny`, `evaluate=ask`
- [ ] Codex/Claude tokens live only in the slot's home (0700/0600), never in git
- [ ] Backups nightly + encrypted off-box sync

See [SECURITY.md](SECURITY.md) and the CI gate in `.github/workflows/security.yml`
(the gate + a two-slot auth isolation smoke test run on every push).

## Project layout

```
opencode-anywhere/
|-- provision.sh          # idempotent bootstrap: Node, pinned opencode, Caddy, UFW, first slot
|-- add-slot.sh           # admin: create one isolated per-user slot (web, unit, Caddy vhost)
|-- list-slots.sh         # admin: show slots + URLs
|-- remove-slot.sh        # admin: delete a slot
|-- opencode.jsonc        # slot template config ({{HOME}} templated, MCPs, agents, permissions)
|-- AGENTS.md             # global behavior rules (ponytail, graphify, swarms, loops)
|-- connect/
|   |-- opencode-connect.sh    # client: plug any local opencode into a slot (Linux/mac)
|   |-- opencode-connect.ps1   #                      ... (Windows)
|-- qrcode.sh / backup.sh / restore.sh   # server helpers
|-- scripts/check.ps1     # security gate (also in CI)
|-- scripts/smoke.sh      # multi-slot isolation smoke test (also in CI)
|-- scripts/seed-settings.sh  # reseed an existing slot from a private settings repo
|-- .github/workflows/security.yml  # gate + multi-slot smoke on every push
|-- SECURITY.md / LICENSE
```

## License

[MIT](LICENSE) — Copyright (c) 2026 opencode-anywhere contributors.