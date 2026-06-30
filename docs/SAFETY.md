# Safety & operating notes

Wormageddon edits live server config and restarts shards. None of it is
destructive to player saves, but a careless restart will annoy players. Read
this once.

## What it changes (and what it doesn't)

- It only ever writes to **`UserGame.ini`** (the settings-override file) and
  **restarts a shard**. It does not touch the game database, player inventories,
  bases, or any other config file.
- **RESTORE DEFAULTS** removes *only the keys this tool manages* — your other
  `UserGame.ini` overrides (e.g. PvP, land-claim limits) are left untouched.

## Restarts drop players

- Applying a change restarts **one shard**, which **disconnects the players on
  that shard** for ~1 minute while it comes back.
- Do it in an **empty window** or warn players first.
- The CLI `restart` prompts for confirmation; pass `-Yes` to skip the prompt
  (the GUI's APPLY/RESTORE/SUMMON buttons confirm with a dialog).
- **Never** restart the survival shard with players mid-activity if you can help
  it.

## Backups

- Every `set` / `unset` / `preset` writes a **timestamped copy** of the current
  `UserGame.ini` to `.\backups\UserGame.<Shard>.<timestamp>.ini` *before* making
  any change. To roll back, copy an old backup's contents in via
  `set`/manual edit, or just use **RESTORE DEFAULTS** and re-apply what you want.
- `.\backups` is git-ignored.

## Worm warm-up (don't panic)

Sandworms repopulate **~10 minutes after any restart**. Seeing zero worms right
after applying a change is *normal*, not a bug. Use **Worms?** /
`Wormageddon.ps1 worms` to see spawn count vs uptime before judging a worm change.

## Secrets

- `dune-connection.json` holds your server IP, SSH user, key path, and
  (optionally) a password. It is **git-ignored** — only the placeholder
  `dune-connection.example.json` is committed. Never commit the real one.
- Prefer **SSH key auth** over a password. The tool keeps its own
  `dune_known_hosts` (git-ignored) and never modifies your global SSH config.

## Permissions on the server

The SSH user must be able to run `sudo k3s kubectl` non-interactively
(`sudo -n`). On a stock Dune Dedicated Server Manager box the `dune` user can.
If `sudo -n` prompts for a password, fix sudoers on the VM rather than storing a
password here.

## Good habits

- **Read current** (or `show`) before you change anything, so you know the
  starting point.
- Change one thing at a time when experimenting, and use the **Worms?** check
  after worm changes.
- Keep a known-good backup aside before a big tuning session.
