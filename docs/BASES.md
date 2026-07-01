# Bases — backup & restore player builds

Back up a player's base (buildings + placeables) to a portable `.json` file, and
(experimentally) restore one back into a player's inventory as a **Solido
Replicator** blueprint they can re-deploy in-world.

> "Solido Replicator" is the in-game device (internal `BuildingBlueprint_CopyDevice`)
> that saves a base layout as a re-deployable blueprint. Wormageddon works at the
> **game database** level, the same way the community web panels do — it reads and
> writes Postgres directly rather than driving the in-game device.

## Requirements

The base feature needs game-Postgres access. Add to `dune-connection.json`:

```json
"DbPassword": "<the game Postgres password>",
"DbUser": "postgres", "DbName": "dune", "DbPort": 15432, "DbPod": ""
```

`DbPod` auto-detects (`…-db-dbdepl-sts-0`) if left blank. Wormageddon runs `psql`
**inside** the DB pod via `kubectl exec` (SQL fed on stdin, so nothing is quoted
into a shell). Reads are safe; the one write path (restore) is heavily gated.

## Backup (export) — read-only, safe

```powershell
# list bases: building_id | owner | pieces | placeables
.\Wormageddon.ps1 bases

# back up one base to .\bases\base_<id>.<timestamp>.json
.\Wormageddon.ps1 base-export 123
.\Wormageddon.ps1 base-export 123 my-main-base.json
```

Or in the GUI: the **Bases** tab → *List bases* → select one → *Back up selected
base*. The file captures every building piece (`building_type` + position +
quaternion + health/flags) and every placeable (with its actor transform), so
it's a complete, human-readable snapshot you can archive, diff, or restore.

## Restore (import) — ⚠️ experimental, write to live game state

> [!WARNING]
> Restore **writes to the live game database** (it creates a Solido Replicator
> blueprint item in a player's inventory). A malformed blueprint can crash the
> game client. Treat it as experimental: **take a database backup first**
> (`.\Wormageddon.ps1` → the server's `battlegroup backup`), target an **offline**
> player, and **verify in-game** after the first use. Wormageddon defaults restore
> to a dry-run and requires explicit confirmation.

The restore path is being finished with those guard rails (offline-player check,
mandatory backup prompt, dry-run preview of the exact SQL, and a confirmation
step). Until you've verified it in-game once, keep using **export** for backups
and treat **import** as a supervised operation. See the project README/releases
for status.

## What's in the JSON

```jsonc
{
  "format": "wormageddon-base/1",
  "building_id": 123, "owner_entity_id": -3245519619502235758,
  "exported": "2026-07-01T01:19:11",
  "piece_count": 212, "placeable_count": 70,
  "pieces":     [ { "instance_id": 0, "building_type": "Choam_Shelter_Foundation_New",
                    "x": 151532.44, "y": 242336.72, "z": 1326.93,
                    "qx": 0, "qy": 0, "qz": 1, "qw": 6.12e-17, "flags": 1, "health": 5000 } ],
  "placeables": [ { "id": 544, "building_type": "WaterCistern_Placeable",
                    "x": 179059.33, "y": -97640.38, "z": 2203.57,
                    "qx": 0, "qy": 0, "qz": 0.707, "qw": 0.707, "hologram": false } ]
}
```
