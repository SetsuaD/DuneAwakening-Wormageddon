# Contributing to Wormageddon

Thanks for helping! This is a small, focused tool — contributions that keep it
small and focused are the most welcome.

## Good first contributions

- **New presets.** Add a block to `presets.json` (see the format below). Themed
  bundles ("hardcore deep desert", "build-session calm", etc.) are great.
- **Settings-reference corrections.** If you've confirmed a real game default or
  the exact effect of a key, fix `docs/SETTINGS_REFERENCE.md` — especially any
  item marked *(inferred)*.
- **New sliders.** A key in `DefaultGame.ini` that players want to tune? Add a
  row to the `$SETTINGS` array in `Wormageddon-GUI.ps1` (the CLI can already set
  any key via a full `/Script/...` section).

## Adding a preset

Each preset is a name → `{ label, settings[] }`, where every setting is
`{ group, key, value }` in **game-write form** (exactly what lands in
`UserGame.ini`). `group` is a friendly name from `Wormageddon.ps1`'s `$SECMAP`
(e.g. `Sandworm`, `Storm`) or a full `/Script/...` section.

```json
"my_preset": {
  "label": "My preset - short description",
  "settings": [
    { "group": "Sandworm", "key": "ThreatScale", "value": "1.5" },
    { "group": "Sandworm", "key": "m_bGiantWormSystemEnabled", "value": "True" }
  ]
}
```

Keys starting with `_` (like `_comment`) are ignored by both the GUI and CLI.

## Adding a slider

Append to `$SETTINGS` in `Wormageddon-GUI.ps1`. Fields:

| Field | Meaning |
|---|---|
| `Tab` | Which tab page (`Sandworm`, `Giant Worm`, `Storms`, `Harvest & economy`, `World & PvP`) |
| `Group` | Friendly section name (must exist in `Wormageddon.ps1` `$SECMAP`) |
| `Key` | Exact ini key |
| `Type` | `num`, `bool`, or `stormdmg` (writes the 4-target damage tuple) |
| `Min`/`Max`/`Def` | TrackBar bounds + default, in **raw integer** slider units |
| `Scale` | Multiply raw value by this to get the real game value |
| `Desc` | Plain-English one-liner shown under the slider |

Set `Def` to the game's real default so an unmoved slider equals the default.

## Before you open a PR

Run the local checks (same as CI):

```bat
build.bat
```

This runs PSScriptAnalyzer (if installed), validates the JSON, and builds the GUI
headless via `Wormageddon-GUI.ps1 -SelfTest`. Please also keep code commented in
the existing style and **never commit `dune-connection.json`** or any real host,
key, or credential.

## Scope

Wormageddon intentionally does **not** grow into a general server manager (that's
[dune-admin](https://github.com/Icehunter/dune-admin) /
[DDSM](https://github.com/adainrivers/dune-dedicated-server-manager)). PRs that
keep it a small, sharp worm/threat tuner are far more likely to merge than ones
that add lifecycle, in-game admin, or a web server.
