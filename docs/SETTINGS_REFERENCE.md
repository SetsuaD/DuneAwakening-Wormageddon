# Settings reference

Every dial Wormageddon exposes, grouped as in the GUI, plus extra keys you can
reach from the CLI. Each maps to a key in a UE5 ini section inside `UserGame.ini`.

> [!NOTE]
> **Every section, key, and default below was verified against the live, shipped
> `DefaultGame.ini`** (`/home/dune/server/DuneSandbox/Config/DefaultGame.ini`,
> game build of 2026-06-30) — not guessed. An unmoved GUI slider equals the
> game default shown here. **Range** is the slider's bounds (in game units after
> scaling); the CLI can set any value.

---

## Sandworm — "worm sign" & threat
Section: `[/Script/DuneSandbox.SandwormSettings]` · Group: `Sandworm`

| Key | Default | Range | Meaning |
|---|---:|---|---|
| `ThreatScale` | 1.0 | 0.0 – 5.0 | Master multiplier on **all** worm threat. The biggest dial: 2.0 = worms provoked twice as easily, 0.5 = calmer. |
| `DefaultMaxThreatScore` | 5000 | 1000 – 20000 | How much threat must build near a worm before it commits to an attack. Lower = strikes sooner. |
| `ThreatDecreaseCooldownInSeconds` | 5 | 0 – 30 | Seconds of quiet before accumulated threat starts to decay. |
| `WalkingThreatPerSec` | 15 | 0 – 100 | Threat generated each second while walking. |
| `RunningThreatPerSec` | 20 | 0 – 100 | Threat per second while running (between walking and sprinting). |
| `CrouchingThreatPerSec` | 15 | 0 – 100 | Threat per second while crouched / sneaking. |
| `SprintingThreatPerSec` | 20 | 0 – 100 | Threat per second while sprinting. |
| `HyperSprintingThreatPerSec` | 90 | 0 – 300 | Threat per second while hyper-sprinting. |
| `DashingThreatPerSec` | 90 | 0 – 300 | Threat per second while dashing — a sharp spike. |
| `SuspendingThreatPerSec` | 200 | 0 – 500 | Threat per second while suspensor-hovering — very loud to worms. |
| `ShieldingThreatPerSec` | 500 | 0 – 1000 | Threat per second with a Holtzman shield up on foot — a worm magnet. |
| `VehicleShieldingThreatPerSec` | 50 | 0 – 300 | Threat per second with a vehicle shield active. |
| `DrumsandThreatPerSec` | 200 | 0 – 500 | Threat per second on resonant drum sand; worms home in on the thumping. |
| `m_SyncTargetIntervalSeconds` | 1.0 | 0.1 – 5.0 | How often a worm re-locks its target. Lower = snappier reactions. |
| `m_MinDistanceBetweenSandworms` | 80000 | 20000 – 200000 | Minimum spacing between worms, in cm (80000 = 800 m). Lower = denser worm population. |

**Master toggle (CLI only — it's an enum, not a slider):** `m_EnableSandwormSystem`
(default `UseAllowList`). This is the top-level on/off/mode switch for the entire
sandworm subsystem. The observed value is `UseAllowList`; other enum values exist
but are unconfirmed, so the GUI doesn't expose it to avoid writing an unknown
value. Set it deliberately from the CLI, e.g.:
`Wormageddon.ps1 set Sandworm m_EnableSandwormSystem UseAllowList`.
Other confirmed-but-unmapped threat keys in this section you can set via the CLI:
`AirborneThreatDecreasingValuePerSec` (100), `WWoRThreatPerSec` (5),
`PlayerShootingRecoilThreatFactor` (1.0), `NPCShootingRecoilThreatFactor` (1.65).

## Giant Worm (Shai-Hulud)
Section: `[/Script/DuneSandbox.SandwormSettings]` · Group: `Sandworm`

| Key | Default | Range | Meaning |
|---|---:|---|---|
| `m_bGiantWormSystemEnabled` | On | On/Off | Master toggle for the scripted giant worm that erupts on busy spice fields. |
| `m_GiantWormMinimumPlayersOnSpiceField` | 4 | 1 – 10 | Harvesters on one spice field needed to trigger it. `1` = any single player can summon it. |
| `m_GiantWormMinimumSpiceAmountHarvested` | 50000 | 0 – 100000 | Total spice pulled from a field to call the giant worm. Lower = sooner. |
| `m_GiantWormSpawningCooldown` | 7200 | 0 – 14400 | Minimum seconds between giant-worm events (7200 = 2 h). |
| `m_GiantWormSpawningUpdateFrequency` | 60 | 5 – 300 | How often the game checks whether to erupt the worm once conditions are met (s). |

## Storms
Section: `[/Script/DuneSandbox.SandStormConfig]` (except where noted) · Group: `Storm`

| Key | Default | Range | Meaning |
|---|---:|---|---|
| `m_bCoriolisAutoSpawnEnabled` | On | On/Off | Whether the big map-wide Coriolis storms spawn automatically. |
| `m_bCoriolisDoesDamage` | Off | On/Off | Whether the Coriolis storm damages players/structures. |
| `m_CoriolisHeavyDamage` | 5000 | 0 – 10000 | Damage the Coriolis core deals per tick when damage is on (5000 = lethal). |
| `m_CoriolisLightDamage` | 5 | 0 – 200 | Damage the Coriolis outer band deals per tick. |
| `m_SmallSandStormDamageConfig` | 5 | 0 – 50 | Per-tick damage from a normal sandstorm. Writes the 4-target tuple (Player/Building/Placeable/Vehicle). |
| `m_LargeSandStormDamageConfig` | 7 | 0 – 50 | Per-tick damage from a large sandstorm (4-target tuple). |
| `m_SandStormDebrisSpeed` | 3000 | 0 – 8000 | Speed of flying sandstorm debris. |
| `m_bMitigateAllSandstormDamage` | Off | On/Off | On = all sandstorm damage ignored (storms become cosmetic). Section: `[/Script/DuneSandbox.BuildingSettings]` (Group `Building`). |

## Harvest & economy

| Key | Default | Range | Section / Group | Meaning |
|---|---:|---|---|---|
| `m_NodeValueToSpiceResourceRatio` | 10 | 1 – 50 | `SpiceHarvestingSystem` / `Harvest` | Spice gained per unit of node value — the spice harvest multiplier. |
| `m_FlourSandFieldsActivePercentage` | 1.0 | 0.0 – 1.0 | `FlourSandSubsystem` / `FlourSand` | Fraction of flour-sand fields active at once (1.0 = all). |
| `m_DefaultRepairCostMultiplier` | 0.5 | 0.0 – 3.0 | `BuildingSettings` / `Building` | Resource cost to repair structures (0.0 = free, 1.0 = full). |

## World & PvP

| Key | Default | Range | Section / Group | Meaning |
|---|---:|---|---|---|
| `m_DayLengthMinutes` | 30 | 5 – 120 | `TimeOfDaySettings` / `TimeOfDay` | Real minutes for one full in-game day/night cycle. |
| `m_DropAmountOnDefeat` | 0.4 | 0.0 – 1.0 | `DuneSandboxGameModeBase` / `GameMode` | Fraction of droppable inventory dropped on PvP defeat (0 = nothing, 1.0 = everything). |
| `m_bHydrationEnabled` | On | On/Off | `HydrationSubsystem` / `Hydration` | Master toggle for the dehydration mechanic. Off = players never dehydrate. |

Also confirmed in `DefaultGame.ini` and CLI-settable (Group `Building`):
`m_MaxNumLandclaimSegments` (6) — max land-claim flags a player may own.

---

## Editing a key the GUI doesn't list

Anything in `DefaultGame.ini` can be set from the CLI by passing a friendly
group (or a full section path) as `<Group>`:

```powershell
.\Wormageddon.ps1 get DefaultMaxThreatScore            # show default + current override
.\Wormageddon.ps1 set Sandworm m_EnableSandwormSystem UseAllowList
.\Wormageddon.ps1 set /Script/DuneSandbox.SomeOtherSettings SomeKey SomeValue
.\Wormageddon.ps1 restart
```

Use `get <Key>` first to confirm the game default and exact spelling against the
live server.
