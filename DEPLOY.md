# Deploy opencode-anywhere 24/7 on a free cloud VM

End to end: spin up an **Oracle Cloud Free** VM, run one script, and you have a
permanent always-on opencode web that every device can reach, plus per-user
slots, realtime file saving, and automated backups. This guide matches the
actual scripts in this repo (`provision.sh`, `add-slot.sh`, `backup.sh`,
`connect/*`) — see `docs/FILES.md` for how files save and sync.

> No personal data is pasted anywhere below. Swap the `<placeholders>` for your
> own values. **Never** put your real password in any file in this repo; it is
> set as an environment variable at deploy time only.

## 1. Oracle Cloud Free (the VM)

1. Sign up at <https://www.oracle.com/cloud/free/> (free account). A card is
   required for identity verification, but you are **only** charged if you
   upgrade to paid later. Choose a **Home Region** — it is permanent and cannot
   be changed, so pick the one physically nearest you.
2. Console → **Create a VM instance**:
   - Image: **Ubuntu 24.04** (or 22.04 — both supported).
   - Shape: pick the **Always Free** shape. Recommended `VM.Standard.A1.Flex`
     (Ampere ARM64, 2 OCPU / 12 GB, within the free quota). If you hit a
     *capacity / out-of-capacity* error (region peak), just retry later or pick
     the free AMD micro shape — both work with these scripts.
   - **SSH keys**: paste your **SSH public key** (you keep the private key).
   - Create the instance, then note its **public IP**.
3. **Reserve the public IP** (Networking → IP management → convert to
   *reserved/public*). This keeps your DuckDNS A record stable across reboots.
4. **Open ingress ports**: Networking → VCN → Security List → add ingress
   **TCP 22, 80, 443**. Oracle's VCN is a *second* firewall; the `ufw` inside
   the VM alone is not enough.

## 2. DNS (DuckDNS)

1. Create a free subdomain at **duckdns.org**: `<sub>.duckdns.org`.
2. Add an **A record** pointing at the VM's reserved **public IP**.
   DuckDNS IPs are ephemeral; reserving the IP above keeps the record stable, and
   if the IP ever changes, update the A record there (or you can use DuckDNS's
   update script — see note in §3 about restarts).

## 3. Provision on the VM

SSH in from your PC and run the **one-line installer** — it installs git,
clones itself, and asks the questions interactively:

```bash
ssh ubuntu@<vm-public-ip>
curl -fsSL https://raw.githubusercontent.com/vit-cerny/opencode-anywhere/main/setup.sh | sudo bash
```

(Prefer typing the answers instead of prompts? Same one-liner works with env
vars: prefix it with
`SETUP_DOMAIN='<sub>.duckdns.org' SETUP_PASSWORD='<pw-min-12>' SETTINGS_REPO='https://github.com/<YOUR-NAME>/opencode-defaults' `
or `SETUP_SKIP_REPO=1` to skip the settings repo.)

That single script, idempotently:
- installs pinned **Node**, **opencode-web**, **codex** and **claude** CLIs;
- installs **Caddy** (HTTPS/TLS via Let's Encrypt, auto-renewing) and **UFW**
  locked to exactly **22/80/443**;
- disables root SSH login and password auth (key-only);
- creates your first slot **`me`** → `https://me.<sub>.duckdns.org`
  (sign in as `opencode` + the password above);
- clones your **private** `SETTINGS_REPO` into that slot so your `opencode.jsonc`,
  `AGENTS.md` and `skills/` follow you to every device in realtime.

`SETTINGS_REPO` is optional — drop it to start from the shared template. It
must be a **private** GitHub repo (or a local path on the VM).

> **Realtime vs on-demand:** the web UI is the realtime surface — every browser
> client reads/writes the same server-side workspace, so state stays in sync
> instantly, and edits in the web UI save **live** to the slot. `connect` is a
> separate on-demand push/pull bridge (see §4). See `docs/FILES.md`.

## 4. Slots + connect from any device

Add a slot for each person. Each one gets their **own password**, own subdomain,
and isolated files:

```bash
cd /opt/opencode-anywhere   # where the one-liner installer put the repo
OPENCODE_SERVER_PASSWORD='<their-own-strong-pw>' ./add-slot.sh <name>
# → https://<name>.<sub>.duckdns.org   (login as "opencode" + that password)
```

On each user's own machine:

```bash
# Linux / macOS
git clone https://github.com/vit-cerny/opencode-anywhere.git
cd opencode-anywhere/connect
./opencode-connect.sh <vm-ip> <name> push    # import THIS machine into the slot
./opencode-connect.sh <vm-ip> <name> pull    # clone the slot down (new machine)
```

```powershell
# Windows (PowerShell)
git clone https://github.com/vit-cerny/opencode-anywhere.git
cd opencode-anywhere\connect
pwsh -File opencode-connect.ps1 <vm-ip> <name> push
```

`connect` moves opencode state (`~/.config/opencode`, `~/.agents/skills`,
`~/.local/share/opencode`, plus codex and claude state) over **sftp-only** slots.
The VM admin must first register that user's SSH public key:

```bash
# on the VM, for slot "<name>":
sudo -u cl-<name> bash -c 'mkdir -p ~/.ssh && echo "<their public key>" >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys'
sudo -u cl-<name> bash -c 'chown -R cl-<name>:cl-<name> ~/.ssh'
```

## 5. Files & shared saving

- Every slot has its own **`shared/`** folder (`/home/cl-<name>/shared/`) for the
  user's work files — private to that slot, created by `add-slot.sh` and backed
  up with `backup.sh`. Store work files here.
- Web UI edits save **live to the slot**. The `connect` client syncs opencode
  state **and** `~/shared/` on demand (push = import this machine into the slot,
  pull = clone the slot down), so `connect` is how work files travel between
  devices; you can also reach them from any browser via the slot URL or sftp.

## 6. Keep it alive forever

- Every slot and Caddy are **systemd units** with `Restart=always`, already
  `systemctl enable`d — they come back after reboots automatically.
- Re-provisioning is **idempotent**: run `provision.sh` again any time to pick
  up fixes / re-apply hardening — it never wipes existing slots or passwords.
- Keep the box patched (short, optional):

```bash
sudo apt install -y unattended-upgrades
```

- If the VM's public IP changes (you did not reserve it), update the DuckDNS A
  record before Caddy renews TLS.

## 7. Backups

```bash
# on the VM, per slot (owner slot "me"):
sudo -u cl-me /usr/local/bin/backup.sh      # → ~/backups/opencode-<stamp>.tar.gz
sudo -u cl-me /usr/local/bin/restore.sh     # pick one and restore
```

`backup.sh` archives the slot's opencode config + **`shared/`** + chat history
into a **0600** tarball inside **`~/backups/`** (0700), keeping the newest 7.
Add a cron to run it every 6h:

```bash
sudo crontab -e   # add:
0 */6 * * * sudo -u cl-me /usr/local/bin/backup.sh >/dev/null 2>&1
```

`BACKUP_RCLONE_REMOTE='<crypt-remote>:backups'` syncs the tarball off-box
**encrypted** (never a plain public object store — the archive can hold provider
tokens). `restore.sh` lists and extracts one over the live slot.

## 8. Security notes

- `ufw` allows only **22/80/443**; SSH is **key-only**, `PermitRootLogin no`.
- Slot users are **sftp-only** (`ForceCommand internal-sftp`), no shell;
  every slot has its own password (min 12 chars, enforced).
- opencode binds **127.0.0.1** only; TLS is handled by Caddy.
- Secrets **never** live in this public repo (the CI security gate enforces it).
- **Never** commit a real `OPENCODE_SERVER_PASSWORD`, `auth.json`, API keys, or
  private keys. Before pushing anything, scan:

```bash
git grep -nEi 'sk-proj|ghp_|AKI[A]|BEGIN .*PRIVATE KEY' HEAD -- ':!.git'
```

## 9. Sanity check after deploy

- `https://me.<sub>.duckdns.org` loads over HTTPS (padlock) and sign-in works.
- `list-slots.sh` shows every slot + URL.
- `journalctl -u opencode-web-me -f` shows the slot's logs.
- Recovery drill if the VM is ever reclaimed: new instance → clone →
  `provision.sh` → `restore.sh`.