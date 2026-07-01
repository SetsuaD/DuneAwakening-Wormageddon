<#
  Wormageddon.ps1 - command-line backend for the Wormageddon settings tuner.
  ===========================================================================

  Wormageddon tunes the "worm sign" and threat level (and a handful of related
  survival/economy dials) of a self-hosted *Dune: Awakening* dedicated server -
  the Funcom `igw` self-hosting platform running on single-node k3s inside a
  Linux VM (the kind of server the Dune Dedicated Server Manager provisions).

  HOW IT WORKS (the whole trick in three lines):
    1. SSH to the Dune server VM.
    2. `kubectl exec` into the running shard pod and edit the PERSISTENT
       UserGame.ini overrides (UE5 config), backing up first.
    3. Restart that one shard so the server re-reads the file.

  There is no game API for these settings - they are UE5 *.ini overrides read at
  shard startup, which is why every change needs a shard restart to take effect.

  This script is the engine; Wormageddon-GUI.ps1 is a point-and-click front-end
  that simply shells out to these same actions.

  CONNECTION DETAILS ARE NEVER HARDCODED. They are read from
  dune-connection.json next to this file (create it from
  dune-connection.example.json, or via the GUI's "Connect to Server" dialog).

  USAGE
    powershell -ExecutionPolicy Bypass -File .\Wormageddon.ps1 <action> [args] [-Shard <Map>]

  ACTIONS
    status                                   shards + players (Funcom serverstats)
    shards                                   list the map/shard names the server runs
    worms   [-Shard S]                       sandworm spawn count + shard uptime (warm-up check)
    show    [-Shard S]                       print the shard's current UserGame.ini overrides
    get     <Key> [-Shard S]                 show the game default + current override for a setting
    set     <Group> <Key> <Value> [-Shard S] add/replace ONE override (merges; auto-backup)
    unset   <Group> <Key> [-Shard S]         remove ONE override (revert that key to default)
    preset  <Name> [-Shard S]                apply a named bundle from presets.json (auto-backup)
    backup  [-Shard S]                       save a timestamped copy of UserGame.ini to .\backups
    restart [-Shard S] [-WarnSeconds N] [-Yes] restart ONE shard (changes take effect);
                                             -WarnSeconds N broadcasts a countdown first
    broadcast "<msg>" ["<title>"] [-Yes]     send an in-game message to all players (needs daemon)
    players | commands                       list players / the commands the daemon accepts (read-only)
    start | stop | update [-Yes]             battlegroup lifecycle (disruptive - confirm)
    give <P> <Item> [n] | xp <P> <amt>       live in-game admin via the daemon (needs daemon)
    kick <P> | teleport <P> <X> <Y> <Z>        "
    spawn <P> <Class> <X> <Y> <Z>              "
    publish <Command> '<json-fields>'        send ANY daemon command (escape hatch)
    ssh     "<cmd>"                          run a raw shell command on the VM (advanced/debug)
    help

  BROADCAST is optional and needs the `dune-server-service` daemon on the VM
  (shipped with the Dune Dedicated Server Manager) on loopback :29187 - we POST
  to /api/admin/publish, which builds the RabbitMQ message. Without the daemon,
  broadcast is unavailable but everything else still works. See docs/LIVE-COMMANDS.md.

  GROUPS -> ini section (friendly name on the left, real UE section on the right):
    Sandworm, TimeOfDay, Building, GameMode, Pvp, Security, Storm, Harvest,
    FlourSand, Hydration   (or pass a full /Script/... section name directly)

  SAFETY
    * Every set/unset/preset writes a timestamped backup of UserGame.ini first.
    * A restart drops the players currently on THAT shard (~1 minute) - use an
      empty window or warn players.
    * Sandworms repopulate ~10 MINUTES after ANY restart, so "no worms right
      after a restart" is normal - use `worms` to check warm-up.
#>
[CmdletBinding()]
param(
  [Parameter(Position=0)][string]$Action = 'help',
  [Parameter(Position=1)][string]$A1,
  [Parameter(Position=2)][string]$A2,
  [Parameter(Position=3)][string]$A3,
  [Parameter(Position=4)][string]$A4,
  [Parameter(Position=5)][string]$A5,
  [string]$Shard = 'Survival_1',
  [int]$WarnSeconds = 0,
  [switch]$DryRun,
  [switch]$Yes
)
$ErrorActionPreference = 'Stop'

# Help is available with no server configured - print usage and stop before we
# ever look for a connection profile.
if ($Action.ToLower() -in @('help','-h','--help','/?','')) {
  Write-Host "Wormageddon - Dune: Awakening worm-sign / threat tuner (CLI)" -ForegroundColor Cyan
  Write-Host "Usage: powershell -ExecutionPolicy Bypass -File .\Wormageddon.ps1 <action> [args] [-Shard <Map>]"
  Write-Host ""
  Write-Host "Settings: status | shards | worms | show | get <Key> | set <Group> <Key> <Value> |"
  Write-Host "          unset <Group> <Key> | preset <Name> | backup | restart [-WarnSeconds N] [-Yes]"
  Write-Host "Server  : players | commands | start | stop | update"
  Write-Host "Admin   : broadcast ""<msg>"" | give <P> <Item> [n] | xp <P> <amt> | kick <P> |"
  Write-Host "          teleport <P> <X> <Y> <Z> | spawn <P> <Class> <X> <Y> <Z> | publish <Cmd> '<json>'"
  Write-Host "Other   : ssh ""<cmd>"" | help      (add -DryRun to preview; -Yes skips confirmations)"
  Write-Host "Groups : Sandworm TimeOfDay Building GameMode Pvp Security Storm Harvest FlourSand Hydration"
  Write-Host ""
  Write-Host "Connection comes from dune-connection.json (copy dune-connection.example.json)."
  Write-Host "The GUI (Wormageddon-GUI.ps1) is a friendlier front-end. Full docs: README.md."
  return
}

# --------------------------------------------------------------------------
# Connection profile (from dune-connection.json - NEVER hardcoded).
# Shape: { Host, User, KeyPath, Password, Namespace, Shards[] }
# Provide either KeyPath (recommended) or Password. Namespace may be blank;
# if so we auto-detect the Funcom battlegroup namespace on the VM.
# --------------------------------------------------------------------------
$CONN = Join-Path $PSScriptRoot 'dune-connection.json'
if (-not (Test-Path $CONN)) {
  throw "No server connection configured. Launch the GUI and use 'Connect to Server', or copy dune-connection.example.json to dune-connection.json and fill it in."
}
try { $conn = Get-Content $CONN -Raw | ConvertFrom-Json } catch { throw "dune-connection.json is not valid JSON: $($_.Exception.Message)" }
$VMHOST = "$($conn.Host)".Trim()
$VMUSER = if ("$($conn.User)".Trim()) { "$($conn.User)".Trim() } else { 'dune' }
$KEYP   = "$($conn.KeyPath)".Trim()
$PW     = "$($conn.Password)"
$JUMP   = "$($conn.JumpHost)".Trim()   # optional bastion for `ssh -J` (e.g. "owner@gateway"); needs key auth
if (-not $VMHOST) { throw "dune-connection.json has no 'Host'." }
if (-not $KEYP -and -not $PW) { throw "dune-connection.json needs either 'KeyPath' (an SSH private key) or 'Password'." }

# Paths on the VM. These are the stock Dune dedicated-server layout - the
# persistent per-battlegroup override file, and the read-only game defaults we
# compare against in `get`.
$UGDIR   = '/home/dune/server/DuneSandbox/Saved/UserSettings'
$UG      = "$UGDIR/UserGame.ini"
$GAMECFG = '/home/dune/server/DuneSandbox/Config/DefaultGame.ini'
$KH      = Join-Path $PSScriptRoot 'dune_known_hosts'   # per-tool known_hosts (auto-managed)
# Server management CLI on the VM + the dune-server-service daemon's loopback API.
$BGBIN   = if ("$($conn.BattlegroupBin)".Trim()) { "$($conn.BattlegroupBin)".Trim() } else { '/home/dune/.dune/bin/battlegroup' }
$DASH    = if ("$($conn.DashboardUrl)".Trim()) { "$($conn.DashboardUrl)".Trim() } else { 'http://127.0.0.1:29187' }
# Game Postgres (only needed for the base backup/restore feature). Password has
# no default - set DbPassword in dune-connection.json to enable `bases`/base-*.
$DBPASS  = "$($conn.DbPassword)"
$DBUSER  = if ("$($conn.DbUser)".Trim()) { "$($conn.DbUser)".Trim() } else { 'postgres' }
$DBNAME  = if ("$($conn.DbName)".Trim()) { "$($conn.DbName)".Trim() } else { 'dune' }
$DBPORT  = if ("$($conn.DbPort)") { [int]$conn.DbPort } else { 15432 }
$DBPOD   = "$($conn.DbPod)".Trim()

# Friendly group name -> real UE5 ini section. Pass any of these as <Group>,
# or a full "/Script/..." section string to reach a section not listed here.
$SECMAP = @{
  Sandworm='/Script/DuneSandbox.SandwormSettings';   TimeOfDay='/Script/DuneSandbox.TimeOfDaySettings'
  Building='/Script/DuneSandbox.BuildingSettings';   GameMode='/Script/DuneSandbox.DuneSandboxGameModeBase'
  Pvp='/Script/DuneSandbox.PvpPveSettings';          Security='/Script/DuneSandbox.SecurityZonesSubsystem'
  Storm='/Script/DuneSandbox.SandStormConfig';       Harvest='/Script/DuneSandbox.SpiceHarvestingSystem'
  FlourSand='/Script/DuneSandbox.FlourSandSubsystem'; Hydration='/Script/DuneSandbox.HydrationSubsystem'
}

# --------------------------------------------------------------------------
# Dssh - run one command on the VM over SSH.
# We base64-wrap the remote command so quoting/special characters survive the
# trip intact, then `base64 -d | sh` on the far side. Uses an SSH key when
# configured (BatchMode, no interactive prompts); otherwise falls back to
# PuTTY/plink for password auth.
# --------------------------------------------------------------------------
function Dssh([string]$cmd) {
  $b = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($cmd))
  $remote = "echo $b | base64 -d | sh"
  if ($KEYP) {
    $sshArgs = @('-i', $KEYP, '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=accept-new', '-o', "UserKnownHostsFile=$KH", '-o', 'ConnectTimeout=12')
    if ($JUMP) { $sshArgs += @('-J', $JUMP) }   # optional bastion / ProxyJump
    $sshArgs += @("$VMUSER@$VMHOST", $remote)
    & ssh @sshArgs 2>&1
  } else {
    $plink = (Get-Command plink.exe -ErrorAction SilentlyContinue).Source
    if (-not $plink -and (Test-Path 'C:\Program Files\PuTTY\plink.exe')) { $plink = 'C:\Program Files\PuTTY\plink.exe' }
    if (-not $plink) { return 'ERROR: password auth requires PuTTY/plink (https://www.putty.org). Install PuTTY or use an SSH key.' }
    'y' | & $plink -ssh -pw $PW "$VMUSER@$VMHOST" $remote 2>&1
  }
}

# --------------------------------------------------------------------------
# Namespace resolution. The Funcom platform puts each battlegroup in a
# "funcom-seabass-*" k8s namespace. Use the configured one, else auto-detect.
# --------------------------------------------------------------------------
$NS = "$($conn.Namespace)".Trim()
if (-not $NS -and $Action.ToLower() -ne 'help') {
  $n = Dssh "sudo -n k3s kubectl get ns -o name 2>/dev/null | grep funcom-seabass | head -1 | sed 's#namespace/##'"
  $NS = ("$n").Trim()
  if (-not $NS) { throw "Could not find a 'funcom-seabass' namespace on $VMHOST. Is this the Dune server VM and is k3s running?" }
}

# Normalise a shard/map name into the pod-name fragment k3s uses (lowercase,
# non-alphanumerics -> '-'), e.g. "Survival_1" -> "survival-1".
function MapKey([string]$shard) { ($shard.ToLower() -replace '[^a-z0-9]','-') }

# Find the running game-server pod for a shard (e.g. ...-sg-survival-1-pod...).
function Get-ShardPod([string]$shard) {
  $mk = MapKey $shard
  $p = Dssh "sudo -n k3s kubectl get pods -n $NS --field-selector=status.phase=Running -o name 2>/dev/null | grep -i 'sg-$mk-pod' | head -1 | sed 's#pod/##'"
  ("$p").Trim()
}

# Read the shard's UserGame.ini (as an array of lines; empty if none yet).
function Read-UserGame([string]$pod) {
  $t = Dssh "sudo -n k3s kubectl exec -n $NS $pod -- sh -c 'cat $UG 2>/dev/null'"
  if ($null -eq $t) { return @() }
  return @($t -split "`r?`n")
}

# Write the shard's UserGame.ini (base64 over the wire; creates the dir).
function Write-UserGame([string]$pod,[string[]]$lines) {
  $b = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($lines -join "`n")))
  Dssh "sudo -n k3s kubectl exec -n $NS $pod -- sh -c 'mkdir -p $UGDIR; echo $b | base64 -d > $UG'" | Out-Null
}

# Save a timestamped backup of the current UserGame.ini under .\backups.
function Backup-Shard([string]$shard,[string]$pod) {
  $dir = Join-Path $PSScriptRoot 'backups'; New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $f = Join-Path $dir ("UserGame.$shard." + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.ini')
  (Read-UserGame $pod) -join "`n" | Set-Content -LiteralPath $f -Encoding UTF8
  Write-Host "  backup -> $f" -ForegroundColor DarkGray
}

# Insert or replace one key inside one ini section, preserving every other
# line/override. Adds the section header if it does not exist yet.
function Merge-Setting([string[]]$lines,[string]$section,[string]$key,[string]$value) {
  $hdr = "[$section]"; $out = New-Object System.Collections.Generic.List[string]
  $inT=$false; $done=$false; $saw=$false
  foreach ($ln in $lines) {
    $t = $ln.Trim()
    if ($t -match '^\[.*\]$') {
      if ($inT -and -not $done) { $out.Add("$key=$value"); $done=$true }
      $inT = ($t -eq $hdr); if ($inT) { $saw=$true }
      $out.Add($ln); continue
    }
    if ($inT -and ($t -match ("^[+]?" + [regex]::Escape($key) + "\s*="))) {
      if (-not $done) { $out.Add("$key=$value"); $done=$true }
      continue
    }
    $out.Add($ln)
  }
  if ($inT -and -not $done) { $out.Add("$key=$value"); $done=$true }
  if (-not $saw) {
    if ($out.Count -gt 0 -and $out[$out.Count-1].Trim() -ne '') { $out.Add('') }
    $out.Add($hdr); $out.Add("$key=$value")
  }
  return ,$out.ToArray()
}

# Remove one key from one section; if that empties the section, drop the header
# (and a trailing blank line) too. Reverts that setting to the game default.
function Remove-Setting([string[]]$lines,[string]$section,[string]$key) {
  $hdr="[$section]"; $out=New-Object System.Collections.Generic.List[string]; $inT=$false; $kept=0; $hdrIdx=-1
  foreach ($ln in $lines) {
    $t=$ln.Trim()
    if ($t -match '^\[.*\]$') { $inT=($t -eq $hdr); if($inT){$hdrIdx=$out.Count;$kept=0}; $out.Add($ln); continue }
    if ($inT -and ($t -match ("^[+]?"+[regex]::Escape($key)+"\s*="))) { continue }
    if ($inT -and $t -ne '' -and $t -notmatch '^;') { $kept++ }
    $out.Add($ln)
  }
  if ($hdrIdx -ge 0 -and $kept -eq 0) {
    $out.RemoveAt($hdrIdx)
    if ($hdrIdx -gt 0 -and "$($out[$hdrIdx-1])".Trim() -eq '') { $out.RemoveAt($hdrIdx-1) }
  }
  return ,$out.ToArray()
}

# Resolve a friendly group name (or a raw /Script/... section) to a section.
function Resolve-Section([string]$group) {
  if ($SECMAP.ContainsKey($group)) { return $SECMAP[$group] }
  if ($group -match '^/Script/' -or $group -match '^/[A-Za-z]') { return $group }
  throw "Unknown group '$group'. Known: $($SECMAP.Keys -join ', '); or pass a full /Script/... section."
}

# --------------------------------------------------------------------------
# Live-command helpers (the "Server" + "Admin" side of the hub).
# These talk to the optional `dune-server-service` daemon's loopback HTTP API on
# the VM (:29187) - it builds the RabbitMQ envelope and injects commands into the
# running game with no restart. The daemon ships with the Dune Dedicated Server
# Manager; if it isn't running, these return a clear error and the settings side
# of the tool is unaffected. Read endpoints are safe anytime; write/commands
# affect live players, so callers confirm first.
# --------------------------------------------------------------------------
function Daemon-Get([string]$path) {
  # GET a read-only daemon endpoint (loopback, so reached over SSH). Raw text.
  return (Dssh "curl -s -m 8 $DASH$path")
}
function Daemon-Publish([string]$Command,[hashtable]$Fields,[switch]$Preview) {
  # POST a live command to /api/admin/publish. We base64 the JSON body onto the
  # VM (no quoting headaches) and curl --data @file. Returns $true on 200/202.
  $payload = @{ command=$Command; fields=$Fields } | ConvertTo-Json -Compress
  if ($Preview) {
    Write-Host "[dry-run] POST $DASH/api/admin/publish :" -ForegroundColor DarkGray
    Write-Host "  $payload"
    return $true
  }
  $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payload))
  $remote = "echo $b64 | base64 -d > /tmp/wm_cmd.json; " +
            "curl -s -m 12 -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' " +
            "--data @/tmp/wm_cmd.json $DASH/api/admin/publish; rm -f /tmp/wm_cmd.json"
  $code = ("$(Dssh $remote)").Trim()
  if ($code -eq '200' -or $code -eq '202') { Write-Host "OK - $Command (HTTP $code)." -ForegroundColor Green; return $true }
  Write-Host "$Command failed (HTTP '$code'). Is the dune-server-service daemon running on the VM ($DASH)?" -ForegroundColor Red
  return $false
}
function Send-Broadcast([string]$Title,[string]$Body,[int]$Duration=30,[switch]$Preview) {
  # The most common live command: an on-screen message to all players.
  return (Daemon-Publish 'ServiceBroadcast' @{ BroadcastType='Generic'; Title=$Title; Body=$Body; BroadcastDuration=$Duration } -Preview:$Preview)
}
function Battlegroup([string]$sub) {
  # Funcom battlegroup lifecycle CLI on the VM (list/status/start/stop/restart/update). Runs as the game user.
  return (Dssh "$BGBIN $sub")
}

# --------------------------------------------------------------------------
# Game-database access (base backup/restore only).
# Runs psql INSIDE the Postgres pod via kubectl exec. The SQL is base64'd and
# fed to psql on stdin (-f -), so there are NO shell/quoting hazards no matter
# what the SQL contains. Reads are safe; writes are gated behind confirmations.
# --------------------------------------------------------------------------
function Get-DbPod {
  if ($DBPOD) { return $DBPOD }
  $p = Dssh "sudo -n k3s kubectl get pods -n $NS -o name 2>/dev/null | grep -- '-db-dbdepl-sts' | head -1 | sed 's#pod/##'"
  return ("$p").Trim()
}
function Db([string]$sql) {
  if (-not $DBPASS) { throw "Base backup/restore needs 'DbPassword' in dune-connection.json (the game Postgres password)." }
  $pod = Get-DbPod
  if (-not $pod) { throw "Could not find the DB pod (…-db-dbdepl-sts-0) in namespace $NS." }
  $b = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($sql))
  $inner = "sh -c 'echo $b | base64 -d | env PGPASSWORD=$DBPASS psql -h 127.0.0.1 -p $DBPORT -U $DBUSER -d $DBNAME -At -F\"|\" -f -'"
  return (Dssh "sudo -n k3s kubectl exec -n $NS $pod -- $inner")
}
# Parse a building_instances.transform array "[0:6]={x,y,z,qx,qy,qz,qw}" -> 7 doubles.
function Parse-ArrTransform([string]$s) {
  if ($s -match '\{([^}]*)\}') { return @($matches[1] -split ',' | ForEach-Object { [double]$_ }) }
  return @(0,0,0,0,0,0,1)
}
# Parse an actors.transform composite ("(x,y,z)","(qx,qy,qz,qw)") -> 7 doubles [x,y,z,qx,qy,qz,qw].
function Parse-ActorTransform([string]$s) {
  $groups = [regex]::Matches($s, '\(([-0-9eE.,\s]+)\)')
  $pos=@(0,0,0); $quat=@(0,0,0,1)
  foreach ($g in $groups) {
    $nums = @($g.Groups[1].Value -split ',' | ForEach-Object { [double]($_.Trim()) })
    if ($nums.Count -eq 3) { $pos = $nums } elseif ($nums.Count -eq 4) { $quat = $nums }
  }
  return @($pos[0],$pos[1],$pos[2],$quat[0],$quat[1],$quat[2],$quat[3])
}

# --------------------------------------------------------------------------
# Action dispatch.
# --------------------------------------------------------------------------
switch ($Action.ToLower()) {

  'status' { Write-Host "Shards:" -ForegroundColor Cyan; Dssh "sudo -n k3s kubectl get serverstats -n $NS" }

  'getns'  { Write-Output $NS }   # used by the GUI to cache the detected namespace

  'shards' {
    # Pull the map/shard names from Funcom's serverstats (5th column).
    $out = Dssh "sudo -n k3s kubectl get serverstats -n $NS --no-headers 2>/dev/null | awk '{print `$5}'"
    (@($out) | ForEach-Object { "$_" -split "`r?`n" } | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -ne '<none>' } | Sort-Object -Unique) -join "`n"
  }

  'worms' {
    # Quick "are worms up yet?" probe: count sandworm spawn log lines + uptime.
    $pod = Get-ShardPod $Shard
    if (-not $pod) { Write-Output 'spawned=0 uptime_sec=0'; break }
    $n  = Dssh "sudo -n k3s kubectl logs -n $NS $pod --tail=30000 2>/dev/null | grep -c 'Spawned Sandworm with ID'"
    $st = Dssh "sudo -n k3s kubectl get pod -n $NS $pod -o jsonpath='{.status.startTime}'"
    $n=("$n").Trim(); $st=("$st").Trim()
    $up=0; try { $up=[int]((Get-Date).ToUniversalTime() - ([datetime]$st).ToUniversalTime()).TotalSeconds } catch {}
    Write-Output ("spawned={0} uptime_sec={1}" -f $n,$up)
  }

  'show'   { $pod=Get-ShardPod $Shard; Write-Host "UserGame.ini on $Shard ($pod):" -ForegroundColor Cyan; (Read-UserGame $pod) -join "`n" }

  'get' {
    if (-not $A1) { throw "usage: Wormageddon get <Key> [-Shard S]" }
    $pod = Get-ShardPod $Shard
    $def = Dssh "sudo -n k3s kubectl exec -n $NS $pod -- grep -nE '^[+]?$A1=' $GAMECFG"
    $ovr = @(Read-UserGame $pod | Where-Object { $_ -match ('^[+]?' + [regex]::Escape($A1) + '\s*=') })
    if (-not $def) { $def = '(not in DefaultGame.ini)' }
    if ($ovr.Count -eq 0) { $ovr = '(none -> uses default)' }
    Write-Host "Setting '$A1' on $Shard ($pod):" -ForegroundColor Cyan
    Write-Host ('  Game default : ' + ($def -join '; '))
    Write-Host ('  Override     : ' + ($ovr -join '; '))
  }

  'set' {
    if (-not $A1 -or -not $A2 -or [string]::IsNullOrEmpty($A3)) { throw "usage: Wormageddon set <Group> <Key> <Value> [-Shard S]" }
    $sec = Resolve-Section $A1; $pod = Get-ShardPod $Shard
    if (-not $pod) { throw "No running pod for shard '$Shard'." }
    Backup-Shard $Shard $pod
    Write-UserGame $pod (Merge-Setting (Read-UserGame $pod) $sec $A2 $A3)
    Write-Host "Set [$sec] $A2=$A3 on $Shard (existing overrides preserved)." -ForegroundColor Green
    Write-Host "Apply with:  .\Wormageddon.ps1 restart -Shard $Shard" -ForegroundColor Yellow
  }

  'unset' {
    if (-not $A1 -or -not $A2) { throw "usage: Wormageddon unset <Group> <Key> [-Shard S]" }
    $sec = Resolve-Section $A1; $pod = Get-ShardPod $Shard
    if (-not $pod) { throw "No running pod for shard '$Shard'." }
    Backup-Shard $Shard $pod
    Write-UserGame $pod (Remove-Setting (Read-UserGame $pod) $sec $A2)
    Write-Host "Removed [$sec] $A2 on $Shard (reverts after restart)." -ForegroundColor Green
  }

  'preset' {
    # Apply a named bundle of overrides from presets.json in one shot. Each
    # entry is { group, key, value } in game-write form; we merge them all into
    # the live UserGame.ini after a single backup, then prompt for a restart.
    if (-not $A1) { throw "usage: Wormageddon preset <Name> [-Shard S] [-Yes]" }
    $pf = Join-Path $PSScriptRoot 'presets.json'
    if (-not (Test-Path $pf)) { throw "presets.json not found next to this script." }
    $pj = Get-Content $pf -Raw | ConvertFrom-Json
    $preset = $pj.PSObject.Properties[$A1]
    if (-not $preset -or $A1 -like '_*') { throw "Unknown preset '$A1'. Available: $(($pj.PSObject.Properties.Name | Where-Object { $_ -notlike '_*' }) -join ', ')" }
    $entries = $preset.Value.settings
    $pod = Get-ShardPod $Shard
    if (-not $pod) { throw "No running pod for shard '$Shard'." }
    Backup-Shard $Shard $pod
    $lines = Read-UserGame $pod
    foreach ($e in $entries) { $lines = Merge-Setting $lines (Resolve-Section $e.group) $e.key "$($e.value)" }
    Write-UserGame $pod $lines
    Write-Host "Applied preset '$A1' ($($entries.Count) setting(s)) to ${Shard}: $($preset.Value.label)" -ForegroundColor Green
    Write-Host "Apply with:  .\Wormageddon.ps1 restart -Shard $Shard" -ForegroundColor Yellow
  }

  'backup' { $pod=Get-ShardPod $Shard; Backup-Shard $Shard $pod }

  'restart' {
    # Restart ONE shard by deleting its pod; the Funcom operator recreates it
    # (same name, fresh instance) which re-reads UserGame.ini. We poll until the
    # NEW instance (different uid) reports Ready, then remind about worm warm-up.
    $pod = Get-ShardPod $Shard
    if (-not $pod) { throw "No running pod for shard '$Shard'." }
    $ou = Dssh "sudo -n k3s kubectl get pod -n $NS $pod -o jsonpath='{.metadata.uid}'"; $oldUid = ("$ou").Trim()
    Write-Host "About to RESTART $Shard ($pod):" -ForegroundColor Yellow
    Dssh "sudo -n k3s kubectl get serverstats -n $NS 2>/dev/null | grep -i 'sg-$(MapKey $Shard)-pod'"
    if (-not $Yes) { if ((Read-Host "Players will be dropped. Type 'yes' to proceed") -ne 'yes') { Write-Host "Aborted."; break } }
    if ($WarnSeconds -gt 0) {
      Write-Host "Warning players with a $WarnSeconds s countdown..." -ForegroundColor Yellow
      [void](Send-Broadcast 'Server Restart' "Restarting in $WarnSeconds seconds to apply settings - please reach safety." $WarnSeconds)
      Start-Sleep -Seconds $WarnSeconds
    }
    Dssh "sudo -n k3s kubectl delete pod -n $NS $pod --wait=false" | Out-Null
    Write-Host "Deleted $pod; the operator recreates it (same name, new instance)..." -ForegroundColor Cyan
    $deadline=(Get-Date).AddSeconds(240); $ok=$false
    do {
      Start-Sleep -Seconds 8
      $cur = Get-ShardPod $Shard; $uid=''; $ready=''
      if ($cur) {
        $u = Dssh "sudo -n k3s kubectl get pod -n $NS $cur -o jsonpath='{.metadata.uid}'"; $uid = ("$u").Trim()
        $r = Dssh "sudo -n k3s kubectl get pod -n $NS $cur -o jsonpath='{.status.containerStatuses[0].ready}'"; $ready = ("$r").Trim()
      }
      $fresh = ($uid -and $uid -ne $oldUid)
      $ok = ($cur -and $fresh -and ($ready -eq 'true'))
      Write-Host ("  ... pod={0} newInstance={1} ready={2}" -f $(if($cur){$cur}else{'(pending)'}), $fresh, $ready)
    } while (-not $ok -and (Get-Date) -lt $deadline)
    if ($ok) {
      Write-Host "$Shard restarted and Ready (fresh instance)." -ForegroundColor Green
      Write-Host "NOTE: sandworms repopulate ~10 MINUTES after a restart - 'no worms right after a restart' is NORMAL." -ForegroundColor Yellow
    }
    else { Write-Host "Timed out waiting for Ready; check '.\Wormageddon.ps1 status'." -ForegroundColor Red }
  }

  'broadcast' {
    if (-not $A1) { throw 'usage: Wormageddon broadcast "<message>" ["<title>"] [-Yes] [-DryRun]' }
    $bTitle = if ($A2) { $A2 } else { 'Server' }
    if ($DryRun) { [void](Send-Broadcast $bTitle $A1 30 -Preview); break }
    if (-not $Yes) { if ((Read-Host "Send this in-game message to ALL online players? Type 'yes'") -ne 'yes') { Write-Host 'Aborted.'; break } }
    [void](Send-Broadcast $bTitle $A1 30)
  }

  # -------- Server tab: read + lifecycle --------
  'players'  { Write-Host "Players:" -ForegroundColor Cyan; Daemon-Get '/api/admin/players' }
  'commands' { Write-Host "Live commands the daemon accepts:" -ForegroundColor Cyan; Daemon-Get '/api/admin/commands' }
  'start' {
    if (-not $Yes) { if ((Read-Host "Start the battlegroup? Type 'yes'") -ne 'yes') { Write-Host 'Aborted.'; break } }
    Write-Host "Starting battlegroup..." -ForegroundColor Cyan; Battlegroup 'start'
  }
  'stop' {
    Write-Host "WARNING: stopping drops ALL players; the survival shard can hang on graceful stop." -ForegroundColor Yellow
    if (-not $Yes) { if ((Read-Host "Type 'stop' to confirm") -ne 'stop') { Write-Host 'Aborted.'; break } }
    Write-Host "Stopping battlegroup..." -ForegroundColor Cyan; Battlegroup 'stop'
  }
  'update' {
    if (-not $Yes) { if ((Read-Host "Update the server (can restart it)? Type 'yes'") -ne 'yes') { Write-Host 'Aborted.'; break } }
    Write-Host "Updating..." -ForegroundColor Cyan; Battlegroup 'update'
  }

  # -------- Admin tab: live in-game commands (via the daemon) --------
  'give' {
    if (-not $A1 -or -not $A2) { throw 'usage: Wormageddon give <PlayerId|*> <ItemName> [Quantity]' }
    $f = @{ PlayerId=$A1; ItemName=$A2; Quantity=$(if ($A3) { [int]$A3 } else { 1 }) }
    if ($DryRun) { [void](Daemon-Publish 'AddItemToInventory' $f -Preview); break }
    if (-not $Yes) { if ((Read-Host "Give $($f.Quantity) x $A2 to $A1? Type 'yes'") -ne 'yes') { Write-Host 'Aborted.'; break } }
    [void](Daemon-Publish 'AddItemToInventory' $f)
  }
  'kick' {
    if (-not $A1) { throw 'usage: Wormageddon kick <PlayerId|*>' }
    if (-not $Yes) { if ((Read-Host "Kick $A1? Type 'yes'") -ne 'yes') { Write-Host 'Aborted.'; break } }
    [void](Daemon-Publish 'KickPlayer' @{ PlayerId=$A1 })
  }
  'xp' {
    if (-not $A1 -or -not $A2) { throw 'usage: Wormageddon xp <PlayerId> <Amount>' }
    $f = @{ PlayerId=$A1; Experience=[int]$A2 }
    if ($DryRun) { [void](Daemon-Publish 'AwardXP' $f -Preview); break }
    if (-not $Yes) { if ((Read-Host "Award $A2 XP to $A1? Type 'yes'") -ne 'yes') { Write-Host 'Aborted.'; break } }
    [void](Daemon-Publish 'AwardXP' $f)
  }
  'teleport' {
    if (-not $A1 -or -not $A2 -or -not $A3 -or [string]::IsNullOrEmpty($A4)) { throw 'usage: Wormageddon teleport <PlayerId> <X> <Y> <Z>' }
    $f = @{ PlayerId=$A1; X=[double]$A2; Y=[double]$A3; Z=[double]$A4 }
    if ($DryRun) { [void](Daemon-Publish 'TeleportTo' $f -Preview); break }
    if (-not $Yes) { if ((Read-Host "Teleport $A1 to ($A2,$A3,$A4)? Type 'yes'") -ne 'yes') { Write-Host 'Aborted.'; break } }
    [void](Daemon-Publish 'TeleportTo' $f)
  }
  'spawn' {
    if (-not $A1 -or -not $A2 -or -not $A3 -or [string]::IsNullOrEmpty($A4) -or [string]::IsNullOrEmpty($A5)) { throw 'usage: Wormageddon spawn <PlayerId> <ClassName> <X> <Y> <Z>' }
    $f = @{ PlayerId=$A1; ClassName=$A2; X=[double]$A3; Y=[double]$A4; Z=[double]$A5 }
    if ($DryRun) { [void](Daemon-Publish 'SpawnVehicleAt' $f -Preview); break }
    if (-not $Yes) { if ((Read-Host "Spawn $A2 for $A1? Type 'yes'") -ne 'yes') { Write-Host 'Aborted.'; break } }
    [void](Daemon-Publish 'SpawnVehicleAt' $f)
  }
  'publish' {
    # Generic escape hatch: send ANY daemon command with JSON fields.
    #   Wormageddon publish KickPlayer "{\"PlayerId\":\"*\"}"
    if (-not $A1) { throw 'usage: Wormageddon publish <Command> ''<json-fields>'' [-DryRun] [-Yes]' }
    $fields = @{}
    if ($A2) { try { ($A2 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $fields[$_.Name] = $_.Value } } catch { throw "fields must be valid JSON: $($_.Exception.Message)" } }
    if ($DryRun) { [void](Daemon-Publish $A1 $fields -Preview); break }
    if (-not $Yes) { if ((Read-Host "Publish '$A1' to the live server? Type 'yes'") -ne 'yes') { Write-Host 'Aborted.'; break } }
    [void](Daemon-Publish $A1 $fields)
  }

  # -------- Bases tab: backup (export) & restore (import) buildings --------
  'bases' {
    Write-Host "Bases (building_id | owner_entity_id | pieces | placeables):" -ForegroundColor Cyan
    Db "SELECT bi.building_id, bi.owner_entity_id, count(*) AS pieces, (SELECT count(*) FROM dune.placeables p WHERE p.owner_entity_id=bi.owner_entity_id) AS placeables FROM dune.building_instances bi GROUP BY 1,2 ORDER BY pieces DESC"
  }

  'base-export' {
    # Read-only: dump a live base (building pieces + placeables) to a JSON file
    # you can archive, inspect, or later restore with base-import.
    if (-not $A1) { throw 'usage: Wormageddon base-export <building_id> [outfile.json]' }
    $bid = [long]$A1
    $owner = ("$(Db "SELECT owner_entity_id FROM dune.building_instances WHERE building_id=$bid LIMIT 1")").Trim()
    if (-not $owner) { throw "No base found with building_id=$bid (run 'bases')." }
    $pieces = @()
    foreach ($ln in ((Db "SELECT instance_id, building_type, transform, building_flags, health FROM dune.building_instances WHERE building_id=$bid ORDER BY instance_id") -split "`n")) {
      if (-not $ln.Trim()) { continue }
      $f = $ln -split '\|'; $t = Parse-ArrTransform $f[2]
      $pieces += [ordered]@{ instance_id=[int]$f[0]; building_type=$f[1]; x=$t[0]; y=$t[1]; z=$t[2]; qx=$t[3]; qy=$t[4]; qz=$t[5]; qw=$t[6]; flags=[int]$f[3]; health=[double]$f[4] }
    }
    $placeables = @()
    foreach ($ln in ((Db "SELECT p.id, p.building_type, coalesce(p.is_hologram,false), a.transform FROM dune.placeables p JOIN dune.actors a ON a.id=p.id WHERE p.owner_entity_id=$owner ORDER BY p.id") -split "`n")) {
      if (-not $ln.Trim()) { continue }
      $f = $ln -split '\|'; $t = Parse-ActorTransform $f[3]
      $placeables += [ordered]@{ id=[int]$f[0]; building_type=$f[1]; hologram=($f[2] -eq 't'); x=$t[0]; y=$t[1]; z=$t[2]; qx=$t[3]; qy=$t[4]; qz=$t[5]; qw=$t[6] }
    }
    $obj = [ordered]@{
      format='wormageddon-base/1'; building_id=$bid; owner_entity_id=[long]$owner
      exported=(Get-Date).ToString('s'); piece_count=$pieces.Count; placeable_count=$placeables.Count
      pieces=$pieces; placeables=$placeables
    }
    $out = if ($A2) { $A2 } else { Join-Path $PSScriptRoot ("bases\base_{0}.{1}.json" -f $bid,(Get-Date -Format 'yyyyMMdd-HHmmss')) }
    New-Item -ItemType Directory -Force -Path (Split-Path $out) | Out-Null
    ($obj | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $out -Encoding UTF8
    Write-Host "Exported base ${bid}: $($pieces.Count) pieces + $($placeables.Count) placeables -> $out" -ForegroundColor Green
  }

  'ssh'  { if (-not $A1) { throw 'usage: Wormageddon ssh "<command>"' }; Dssh $A1 }

  default {
    Write-Host "Wormageddon.ps1 actions:" -ForegroundColor Cyan
    Write-Host "  settings: status shards worms show get set unset preset backup restart"
    Write-Host "  server  : players commands start stop update"
    Write-Host "  admin   : broadcast give xp kick teleport spawn publish"
    Write-Host "  other   : ssh help"
    Write-Host "Connection comes from dune-connection.json. Full usage is in this file's header and the README."
  }
}
