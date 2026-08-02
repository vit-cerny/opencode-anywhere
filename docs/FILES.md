# Files & realtime saving (opencode-anywhere)

How state, files and "realtime" actually work — what is live, what is
on-demand, and where work files live per slot.

## Realtime (live, instant)

- The **web UI** is server-authoritative. Every browser client reads/writes the
  same per-slot workspace on the VM, so one device's edits are visible to the
  others *the moment they change* (live via SSE/event streaming).
- Edits you make in the web UI **save to the slot immediately** — there is no
  "save" step and nothing to run on your machine.
- Caveat: this is *your session from anywhere*, not a multi-user collaborative
  editor — two devices see the same files/state; they are not designed to co-edit
  one message simultaneously.

## On-demand (`connect`)

- `connect/opencode-connect.sh` / `.ps1` moves **opencode state** onto or off a
  slot over sftp-only (bulk import/export):
  - `push` uploads this machine's state into the slot (overwrites slot).
  - `pull` downloads the slot's state to this machine (backs up local first).
- It transfers `~/.config/opencode`, `~/.agents/skills`,
  `~/.local/share/opencode`, `~/.local/state/opencode`, plus codex (`~/.codex`,
  `~/.config/codex`, `~/.local/share/codex`) and claude (`~/.claude`,
  `~/.claude.json`, `~/.config/claude`, `~/.local/share/claude-code`) state.
- Since the `shared/` work-files fix, it **also** syncs `~/shared` — the
  sftp transfer includes the per-slot shared folder, so `connect push|pull`
  moves your work files between devices too.

## Per-slot `shared/` (your work files)

- `add-slot.sh` creates a private **`~/shared/`** (`/home/cl-<name>/shared/`)
  per user, owned by that slot's user. Store work files there.
- It is included in **backups** (`backup.sh`).
- Each slot's files are isolated: a slot cannot read another user's home.

## Backups

- `backup.sh` archives a slot's opencode config + `shared/` + chat history into
  `~/backups/opencode-<stamp>.tar.gz` (0600, dir 0700), keeping the newest 7.
- `restore.sh` lists and extracts one over the live slot.
- Optional **encrypted** off-box sync: `BACKUP_RCLONE_REMOTE='<crypt>:backups'`
  (encrypted only — backups can hold provider tokens).
- Backup list per slot lives in `~/backups/`.