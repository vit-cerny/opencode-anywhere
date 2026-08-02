# GOTO — take your whole server anywhere, in one file

`goto.env` is the **one small file** that tells opencode-anywhere **where your
slot lives**. Put it on any new PC and one command pulls your whole opencode
world onto it. It is tiny, human-readable, and holds **no secrets**.

## Where does the file live?

- The **template** is `sync/goto.env.example` in this repo (keep it untouched;
  it is just the example you copy from).
- Your **real** file is `sync/goto.env` — you create it by copying the example.
  It is git-ignored on purpose (it is your own machine's pointer file).
- The adopter looks for it in `sync/goto.env`, then `goto.env` at the repo root.

## What goes in it?

Only three values matter. Everything else is optional and safe to leave blank.

| Field | What it is |
| --- | --- |
| `VM_IP` | the public IP (or hostname) of your opencode-anywhere VM |
| `SLOT` | your slot name on that VM, e.g. `me` |
| `DOMAIN` | your DuckDNS domain (only used to print your URL as a hint) |

Optional: `SETTINGS_REPO` — a git repo of extra settings/scripts you keep; leave
blank if you sync everything through the slot.

## The adopt command

On a brand-new machine, after cloning this repo and filling in `goto.env`:

```bash
bash sync/adopt.sh          # Linux / macOS  (pulls the slot down to this PC)
```

```powershell
pwsh -File sync/adopt-windows.ps1   # Windows
```

That runs your slot's **pull** — it downloads the slot's config, skills,
plugins, MCPs, projects and chats straight onto the machine. Re-run it any time
to refresh (it backs up the local copy first, so it's safe).

Want to go the other way (send this PC's state up)? `bash sync/adopt.sh push`.

## Security, in plain words

- `goto.env` only names your **server** and your **slot**. Nothing personal.
- Passwords, API keys, tokens, and SSH keys **never** go in it. `adopt` logs in
  with the same SSH key you already use for the connect client.
- Nothing here is ever committed to git, and the repo's security gate will fail
  the build if a secret ever sneaks in.