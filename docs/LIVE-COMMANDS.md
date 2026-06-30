# Live server commands (broadcast & friends)

Wormageddon is a *settings* tuner — its one live, no-restart capability is
**`broadcast`** (warn players before a worm-restart). This doc explains how that
works and documents the whole live-command surface for power users, so you can
go further if you want.

> Credit: the RabbitMQ command protocol below was reverse-engineered and proven
> by the MIT-licensed [Dune Dedicated Server Manager](https://github.com/adainrivers/dune-dedicated-server-manager)
> (and [dune-admin](https://github.com/Icehunter/dune-admin)). Wormageddon's
> `broadcast` simply calls that project's daemon, so the heavy lifting stays in
> the tool that owns it.

## Two ways to send a live command

### 1. The daemon API (what `Wormageddon broadcast` uses) — recommended
If your server runs the `dune-server-service` daemon (it ships with the Dune
Dedicated Server Manager), it exposes a **loopback-only** HTTP API on the VM at
`http://127.0.0.1:29187`. Wormageddon SSHes to the VM and POSTs to it:

```
POST http://127.0.0.1:29187/api/admin/publish
Content-Type: application/json

{ "command": "ServiceBroadcast",
  "fields": { "BroadcastType": "Generic", "Title": "Server",
              "Body": "Restarting in 60s", "BroadcastDuration": 60 } }
```

The daemon handles the token, the RabbitMQ envelope, and the publish. It returns
HTTP 200 on success. Useful read-only endpoints: `GET /api/health`,
`GET /api/admin/cluster` (namespace + mq/db pod names), `GET /api/admin/commands`
(the full command catalogue), `GET /api/admin/players`.

This is loopback-only by design — it is only reachable *from the VM* (which is
why Wormageddon tunnels in over SSH). Don't expose :29187 publicly.

### 2. Direct `rabbitmqctl eval` (no daemon required)
If you don't run the daemon, the same publish can be done by `kubectl exec`-ing
`rabbitmqctl eval` inside the RabbitMQ pod. This is exactly what the daemon does
internally. The message body is:

```
base64( JSON{ "Version": 2,
              "AuthToken": "<token>",
              "MessageContent": "<the inner command JSON, stringified>" } )
```

published to exchange **`heartbeats`**, routing key **`notifications`**, with AMQP
properties `app_id="fls_backend"`, `user_id="fls"`. The `<token>` resolves as:
`DUNE_COMMAND_AUTH_TOKEN` env → `/home/dune/.dune/state/command-auth-token` file
→ the public builtin fallback `Nu6VmPWUMvdPMeB7qErr` (documented "Funcom-confirmed
harmless" in DDSM's source). The MQ pod is `…-mq-game-sts-0` in the
`funcom-seabass-*` namespace. This route is fiddlier (Erlang quoting) — feed the
Erlang script over stdin rather than inlining it. Wormageddon uses route #1 to
avoid all of this; #2 is documented here for completeness.

## The command catalogue

These are the `ServerCommand`s the platform accepts (proven by DDSM). **There is
no "spawn a sandworm" command** — creature spawning isn't exposed — so a literal
live worm summon isn't possible (use the giant-worm *settings* + a restart, i.e.
the GUI's **SUMMON SHAI-HULUD** button, for that).

| Command | Purpose | Key fields |
|---|---|---|
| `ServiceBroadcast` | Server-wide on-screen message / shutdown notice | `BroadcastType` (Generic\|ServerShutdown), `Title`, `Body`, `BroadcastDuration` |
| `AddItemToInventory` | Grant an item to a player | `PlayerId`, `ItemName`, `Quantity`, `Durability` |
| `KickPlayer` | Kick a player (or `*` for all) | `PlayerId` |
| `UpdateAllWaterFillables` | Refill a player's water | `PlayerId`, `WaterAmount` |
| `AwardXP` | Grant XP | `PlayerId`, `Experience` |
| `SkillsSetUnspentSkillPoints` / `SkillsSetModuleLevel` | Skill points / module level | `PlayerId`, `SkillPoints` / `Module`,`Level` |
| `TeleportTo` / `TeleportToExact` | Teleport a player | `PlayerId`, `X`,`Y`,`Z`,(`Yaw`…) |
| `SpawnVehicleAt` | Spawn a **vehicle** (not a creature) | `PlayerId`, `ClassName`, `X`,`Y`,`Z` |
| `CleanPlayerInventory` / `ResetProgression` | Destructive player wipes | `PlayerId` |
| (whisper) | Private chat to one player | recipient + text (separate endpoint) |

These are fire-and-forget (`publish_at_most_once`) — a 200/`publish=ok` means
"queued", not "applied". Wormageddon only wires `ServiceBroadcast`; the rest are
documented so you can extend it (or just use DDSM / dune-admin, which implement
them all with proper UIs).

## Using it from Wormageddon

```powershell
# preview exactly what would be sent (no network)
.\Wormageddon.ps1 broadcast "Worm settings changing in 1 min" "Heads up" -DryRun

# send it (asks for confirmation unless -Yes)
.\Wormageddon.ps1 broadcast "Worm settings changing in 1 min" "Heads up"

# warn players, then restart to apply your tuning
.\Wormageddon.ps1 restart -Shard Survival_1 -WarnSeconds 60
```

If broadcast reports a non-200, the daemon isn't running/reachable on the VM —
the settings side of Wormageddon doesn't need it.
