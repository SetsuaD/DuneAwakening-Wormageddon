# Architecture

How Wormageddon actually changes a Dune: Awakening server setting.

## The two settings layers (and why we edit the file, not the API)

A Funcom `igw` Dune server exposes its gameplay configuration in **two** places,
and it's important to know which one is authoritative:

1. **The `serverGameplaySettings` JSON echo.** The battlegroup *director* pod
   periodically logs a RabbitMQ "ServerState" message containing a JSON blob
   (`sandwormEnabled`, `sandstormEnabled`, `miningOutputMultiplier`, …). This is
   a **read-only runtime echo** — handy to *observe* what the server currently
   believes, but it is not where you change things, and it does not contain the
   fine-grained worm dials at all.

2. **`UserGame.ini` (the authoritative, editable layer).** The real, tunable
   settings are **Unreal Engine 5 `*.ini` overrides** read by each shard at
   startup, living at:

   ```
   /home/dune/server/DuneSandbox/Saved/UserSettings/UserGame.ini
   ```

   with the stock game defaults in:

   ```
   /home/dune/server/DuneSandbox/Config/DefaultGame.ini
   ```

   The fine-grained worm-sign / threat dials — `ThreatScale`,
   `WalkingThreatPerSec`, the Shai-Hulud block, etc. — exist **only** here, in
   `[/Script/DuneSandbox.SandwormSettings]`.

There is **no live API** to set these. They are read once at shard boot. That is
why every change requires a shard restart, and why Wormageddon edits the file
directly rather than calling a service.

## The write path

```
set/unset/preset ─▶ SSH to VM ─▶ kubectl exec into shard pod ─▶ edit UserGame.ini ─▶ restart shard
```

Step by step (`Wormageddon.ps1`):

1. **Connect.** Read `dune-connection.json` for the host, SSH user, and key (or
   password). Every remote command is base64-wrapped and piped through
   `base64 -d | sh` on the far side so quoting and special characters survive
   the SSH hop intact (see `Dssh`).

2. **Resolve the namespace.** The Funcom platform puts each battlegroup in a
   `funcom-seabass-*` Kubernetes namespace. We use the one cached in your config,
   or auto-detect it:
   ```sh
   sudo -n k3s kubectl get ns -o name | grep funcom-seabass | head -1
   ```
   (`kubectl` is a k3s symlink and needs `sudo`.)

3. **Find the shard pod.** Shard `Survival_1` → pod-name fragment
   `sg-survival-1-pod`:
   ```sh
   sudo -n k3s kubectl get pods -n <ns> --field-selector=status.phase=Running -o name \
     | grep -i 'sg-survival-1-pod' | head -1
   ```

4. **Back up, then merge.** Read the current `UserGame.ini` out of the pod, write
   a timestamped copy to `.\backups`, then **merge** the new key into the right
   `[/Script/...]` section *preserving every other override* (`Merge-Setting`),
   and write it back via `kubectl exec ... > UserGame.ini`.

5. **Restart the shard.** We delete the pod; the Funcom operator immediately
   recreates it (same name, fresh instance), which re-reads `UserGame.ini` on
   boot. We poll until the **new** instance (different `metadata.uid`) reports
   `Ready`.

### Why deleting the pod is safe here

`UserSettings/` lives on a **persistent volume**, so the edited `UserGame.ini`
survives pod recreation and is read by the fresh instance. The delete is just the
supported way to bounce one shard; the platform's operator reconciles it back.

## Reading current values

`show` execs `cat UserGame.ini` inside the shard pod. `get <Key>` additionally
greps `DefaultGame.ini` so you can see the game default next to your override.
The GUI's **Read current** parses that output and positions every slider; keys
with no override fall back to their game default.

## The "worms?" warm-up probe

After any restart, sandworms take **~10 minutes** to repopulate. `worms` counts
`Spawned Sandworm with ID` lines in the shard log and compares against pod uptime
to tell you whether the desert is still warming up or genuinely quiet.

## Connection & secrets

All connection details come from `dune-connection.json` (git-ignored). Key-based
auth is strongly preferred; password auth falls back to PuTTY/plink. The tool
keeps its own `dune_known_hosts` next to the scripts (also git-ignored) so it
never touches your global SSH known_hosts.
