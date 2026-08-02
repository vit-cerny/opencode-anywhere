# Click-through: 25 minutes to a live 24/7 slot

Hands-on walkthrough of the console screens — exact buttons and fields — for
the free Oracle Cloud flow used by `DEPLOY.md`. Oracle's UI labels shift
slowly; if a name moved, it'll be nearby — the flow is the same.

Time target: ~20-30 min once your account is approved (instant usually).

---

## Phase 0 — account (one time)

1. Browser → <https://signup.cloud.oracle.com> → **Start for free**.
2. Enter country, name, email; set password; **Create account**.
3. Verify email (click the link they email you).
4. **Add payment method** (a card; only kept for verification on Always Free) —
   enters **Card number / expiry / CVV**, then **Save & continue**.
5. Confirm phone: pick country, type your number, **Send verification code**,
   type the code, **Verify**.
6. **Create account**. You land on the Oracle Cloud **Dashboard**.
7. Set your **Home Region** now (top-right dropdown under your name) — it is
   *permanent*. Choose the region geographically closest (e.g. the one for
   your country). **Never change it later.**

## 2 — VM instance

8. From the dashboard, open the **hamburger menu (≡) → Compute → Instances**.
9. Click **Create instance** (blue button).
10. **Name**: `opencode` (or any).
11. **Placement**: leave as-is (Availability Domain auto).
12. **Image and shape**: click **Edit** → **Change image** → select **Ubuntu** →
    pick **Ubuntu 24.04** → **Select image**.
13. Under **Instance shape**: **Change shape** → **Specialty and legacy** tab →
    **Arm** → **VM.Standard.A1.Flex**; set **OCPU count: 2**, **Memory: 12 GB** →
    (if OCPU locked to 1 or greyed out, raise count on the slider) → **Select shape**.
    Note: in some regions A1 temporarily reports **Out of host capacity** — press
    **Retry** after refresh, or pick the free AMD `VM.Standard.E2.1.Micro` instead.
14. **SSH keys**: click **Paste public keys** and paste the **public** key you
    generated locally (`cat ~/.ssh/id_ed25519.pub` on your PC). You keep the
    private key. (If you have no key yet: on your PC `ssh-keygen -t ed25519`.)
15. Leave **Boot volume** defaults (Free-Tier eligible size).
16. Scroll down → **create**.

## 3 — Make the IP permanent

17. Wait ~1-2 min until **Running** (green dot) → note the **Public IP** shown.
18. Menu **(≡) → Networking → Reserved public IPs → Create / assign**:
    - Click **Create** (Pool: **Public**, name: `opencode-ip`).
    - After it's reserved, open the reserved IP row → **Assign** → select your VM
      instance → **Update**.

## 4 — Open ports 22/80/443 (the "second firewall")

19. Menu **(≡) → Networking → Virtual Cloud Networks** → click your VCN →
    **Security Lists** (left) → the default one → **Add Ingress Rules**.
20. For each port, click **+ Ingress Rules** with:
    - Source Type: IPv4 | Source CIDR: `0.0.0.0/0` | IP Protocol: TCP |
      Destination Port: **22** → **Add Ingress Rules**. Repeat for **80** and **443**.

## 5 — DNS (DuckDNS, free)

21. Browser new tab → <https://www.duckdns.org> → **Sign in** with Google/GitHub/
    X. After login:
    - **Domains** section: type a subdomain like `mybox` → **Add domain**.
    - Under your new `<mybox>.duckdns.org` row: **Edit** (or the pencil) →
      A record: paste your **reserved public IP** (→ "✓ OK").
    - Optional (keeps it updated if the IP ever changes): **Install the cron**
      per DuckDNS instructions; with a reserved IP it's unnecessary.

## 6 — Run the setup script (on your local machine: SSH into the VM)

22. On your PC terminal: `ssh ubuntu@<public-ip-address>` (the first connection
    asks to trust the new host → type `yes`).
23. Now do — in one go:

```bash
sudo apt update && sudo apt install -y git
git clone https://github.com/vit-cerny/opencode-anywhere.git
cd opencode-anywhere
sudo ./setup.sh
```

Answer the prompts: `<mybox>.duckdns.org`, a long owner password (12+), and
optionally your settings repo. The script runs the full `provision.sh`
(Nodes, opencode, codex, claude, Caddy, ufw — everything).

## Step 7 — verify

24. Visit `https://me.<mybox>.duckdns.org` — green padlock, login prompt.
    - Username: `opencode`
    - Password: what you entered in step 23.
25. Sanity: `./list-slots.sh` (shows me slot + URL); add a friend:
    `OPENCODE_SERVER_PASSWORD='<their-pw>' ./add-slot.sh alice`.

## Phase 8 — crash-proof (done once)

26. `sudo crontab -e` → add backup line (create ~/backups first):
    `0 * * * * root /usr/local/bin/backup.sh >/dev/null 2>&1` (hourly backup).

## If the IP changes later

- If you did NOT reserve it (step 3 was skipped), repeat step 21 (DuckDNS A
  record update) and (if needed) `systemctl reload caddy`.