# Wormageddon vs the other Dune: Awakening admin tools

An honest, detailed comparison so you can pick the right tool. Short version:
**Wormageddon is the smallest of the three on purpose.** If you want a full
control plane, use dune-admin. If you want to manage the server's lifecycle and
do in-game admin, use the Dune Dedicated Server Manager. Wormageddon is for one
job: tuning worm-sign / threat (and a few related dials) with zero setup.

## At a glance

| | **Wormageddon** | **Dune Dedicated Server Manager** (adainrivers) | **Icehunter/dune-admin** |
|---|---|---|---|
| Type | PowerShell GUI + CLI | Tauri desktop app (Rust + web) | Go web panel (embedded React SPA) |
| Install | Copy 2 files, run | Desktop installer (Win/Linux/macOS) | `curl \| bash` → systemd service |
| Topologies | k3s-over-SSH | k3s-over-SSH (Funcom `igw`) | AMP, kubectl, docker, local (4 providers) |
| **Edit worm/threat gameplay settings** | ✅ its whole purpose | ❌ no settings editor | ✅ Server Settings tab |
| Curated worm/threat presets | ✅ (+ SUMMON SHAI-HULUD) | ❌ | ❌ (generic schema editor) |
| Server lifecycle (start/stop/restart/update) | restart-to-apply only | ✅ full + scheduled | ✅ |
| In-game admin (give item, spawn, XP, teleport) | ❌ | ✅ (RabbitMQ) | ✅ (RabbitMQ + huge DB suite) |
| Database tools (raw SQL, repair, backups) | ❌ | player lookup, welcome ledger | ✅ extensive |
| Multi-user / auth | ❌ (your desktop) | ❌ (your desktop) | ✅ local + Discord, RBAC, audit |
| Scheduling (restarts/backups) | ❌ | ✅ (bundled daemon) | ✅ |
| License | MIT | MIT | MIT |

## The three tools, in detail

### Wormageddon (this project)
A two-file PowerShell tool. SSHes to the Dune VM, edits `UserGame.ini` via
`kubectl exec`, restarts the shard. Exposes ~28 curated sliders across Sandworm /
Giant Worm / Storms / Harvest / World&PvP tabs, three presets, and a one-click
giant-worm summon. No service, no database, no auth, no agent — and nothing to
secure beyond your own SSH key. **Strength:** zero-friction worm/threat tuning
for a solo Windows operator. **Limits:** Windows-only, single-purpose, no live
in-game admin, no lifecycle/scheduling.

### Dune Dedicated Server Manager (adainrivers)
A cross-platform Tauri desktop app that **manages an already-provisioned**
server. It does battlegroup lifecycle (start/stop/restart/update), component
diagnostics and logs, secure SSH tunnels to the Director / File Browser /
PostgreSQL / PgHero, and a bundled `dune-server-service` daemon for scheduled
daily restarts (with in-game warnings), automated backups, and update apply.
Its admin console does **in-game actions over RabbitMQ** — item grants, vehicle
spawns, skill/journey/XP, player lookup, plus per-player "welcome package"
automation. **It deliberately has no gameplay-settings editor** — that's the
exact gap Wormageddon fills. (This is also the app that typically *provisions*
the kind of server Wormageddon then tunes.)

### Icehunter/dune-admin
The heavyweight: a self-hosted Go binary (with an embedded React 19 / HeroUI SPA)
that runs as a service and is reached in a browser. Highlights:

- **Four provider back-ends:** CubeCoders **AMP**, **kubectl** (k3s over SSH),
  **docker**, and **local** bare-metal — selected per server, multi-server aware.
- **Server Settings tab:** reads `DefaultGame.ini` and writes `UserGame.ini`
  overrides through a schema (categories include `SandwormSettings` and
  `SpiceHarvestingSystem`) plus a raw-section editor — i.e. it *can* edit the
  same worm settings Wormageddon does, just inside a much larger generic UI.
- **Deep player/world tooling:** inventory, skills, currency, XP, faction,
  teleport, whisper, bases, blueprints, guilds, Landsraad, an interactive
  Leaflet map, and stats dashboards.
- **Live commands over RabbitMQ** (base64 envelope published via
  `rabbitmqctl eval`) with **offline DB fallbacks** for many ops, a **raw-SQL
  console** (read-only-gated at the handler), and **AMP-only `pg_dump`/`pg_restore`
  backups**.
- **Economy:** market viewer + an embedded market bot, a full **battlepass**
  engine, welcome kits / give-packs, deferred grants.
- **Discord:** OAuth login, status embeds, multi-guild mapping, an events engine.
- **Auth/security:** local bcrypt + Discord OAuth, signed `HttpOnly` sessions,
  a ~28-capability RBAC model with a read-only floor and guest mode, an
  append-only audit log, login rate-limiting, CSP/HSTS headers, and CI security
  gates (gosec + CodeQL SAST, govulncheck SCA).

**Strength:** it does basically everything, for any topology, with multi-user
access control. **Cost:** you stand up and secure a web service, and the worm
dials are one small tab in a very large app.

## Which should you use?

- **Just want scary (or chill) worms tonight, on Windows, with no setup?** →
  **Wormageddon.**
- **Want to run/restart/update the server and do GM stuff (give items, spawn,
  schedule restarts)?** → **Dune Dedicated Server Manager.**
- **Want one web app for everything, multiple admins, Discord login, full audit,
  any hosting topology?** → **Icehunter/dune-admin.**

They compose fine: many operators provision with DDSM, run day-to-day admin in
DDSM or dune-admin, and keep Wormageddon around as the quick worm/threat knob.
