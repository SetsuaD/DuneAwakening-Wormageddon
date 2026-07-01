#requires -version 5.1
<#
  Wormageddon-GUI.ps1 - point-and-click tuner for a Dune: Awakening dedicated server.
  ===================================================================================

  A small Windows Forms front-end over Wormageddon.ps1. It does NOT talk to the
  server itself - it shells out to Wormageddon.ps1, which SSHes to the Alpine/k3s
  VM, edits the persistent UserGame.ini overrides, and restarts shards.

  First launch prompts for the connection (server IP, SSH user, key or password)
  via "Connect to Server"; details are saved next to this file in
  dune-connection.json. No secrets are baked into the source.

  Tabs group the dials: Sandworm (worm sign / threat), Giant Worm (Shai-Hulud),
  Storms, Harvest & economy, World & PvP. "Read current" pulls live values into
  the sliders; "APPLY + RESTART" writes the changes and reboots that shard.
  The "Preset" row loads a curated bundle (Calm Dunes / Standard / WORMAGEDDON)
  into the sliders for you to review before applying.

  Run:  powershell -ExecutionPolicy Bypass -File .\Wormageddon-GUI.ps1
        (or double-click the "Wormageddon" desktop shortcut created by setup.bat)
#>
param([switch]$SelfTest)
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$DUNE     = Join-Path $PSScriptRoot 'Wormageddon.ps1'     # the CLI engine we drive
$CONNFILE = Join-Path $PSScriptRoot 'dune-connection.json'
$PRESETF  = Join-Path $PSScriptRoot 'presets.json'
if (-not (Test-Path $DUNE)) { [System.Windows.Forms.MessageBox]::Show("Wormageddon.ps1 not found next to this GUI ($DUNE).","Wormageddon"); return }

# --------------------------------------------------------------------------
# The slider catalogue. One row per tunable setting:
#   Tab    - which tab page it lives on
#   Group  - friendly group name Wormageddon.ps1 maps to a UE5 ini section
#   Key    - the exact ini key
#   Type   - num | bool | stormdmg (stormdmg writes the 4-target damage tuple)
#   Min/Max/Def - TrackBar bounds + default, in RAW integer slider units
#   Scale  - multiply raw slider value by this to get the real game value
#   Desc   - plain-English explanation shown under the slider
# Defaults (Def) mirror the game's own defaults so an unmoved slider == default.
# --------------------------------------------------------------------------
$SETTINGS = @(
  @{Tab='Sandworm'; Group='Sandworm'; Key='ThreatScale';                           Type='num';     Label='Threat scale (global worm aggression)'; Min=0;Max=50;Def=10;Scale=0.1;  Desc='Master multiplier on ALL worm threat. 1.0 normal, 2.0 = twice as easily provoked, 0.5 = calmer. The biggest dial.'}
  @{Tab='Sandworm'; Group='Sandworm'; Key='DefaultMaxThreatScore';                 Type='num';     Label='Threat to provoke';                      Min=1000;Max=20000;Def=5000;Scale=1; Desc='How much threat must build near a worm before it commits to attack. Lower = strikes sooner.'}
  @{Tab='Sandworm'; Group='Sandworm'; Key='ThreatDecreaseCooldownInSeconds';       Type='num';     Label='Threat cool-down (s)';                   Min=0;Max=30;Def=5;Scale=1;    Desc='Seconds you must stay quiet before built-up threat starts dropping.'}
  @{Tab='Sandworm'; Group='Sandworm'; Key='WalkingThreatPerSec';                   Type='num';     Label='Walking threat / sec';                   Min=0;Max=100;Def=15;Scale=1;  Desc='Threat generated each second while walking.'}
  @{Tab='Sandworm'; Group='Sandworm'; Key='SprintingThreatPerSec';                 Type='num';     Label='Sprinting threat / sec';                 Min=0;Max=100;Def=20;Scale=1;  Desc='Threat per second while sprinting.'}
  @{Tab='Sandworm'; Group='Sandworm'; Key='DashingThreatPerSec';                   Type='num';     Label='Dashing threat / sec';                   Min=0;Max=300;Def=90;Scale=1;  Desc='Threat per second while dashing - a sharp spike.'}
  @{Tab='Sandworm'; Group='Sandworm'; Key='ShieldingThreatPerSec';                 Type='num';     Label='Shield threat / sec (on foot)';          Min=0;Max=1000;Def=500;Scale=1;Desc='Threat per second while a Holtzman shield is up on foot - a worm magnet (500 default).'}
  @{Tab='Sandworm'; Group='Sandworm'; Key='DrumsandThreatPerSec';                  Type='num';     Label='Drum-sand threat / sec';                 Min=0;Max=500;Def=200;Scale=1; Desc='Threat per second on resonant drum sand. Worms home in on the thumping.'}
  @{Tab='Sandworm'; Group='Sandworm'; Key='RunningThreatPerSec';                   Type='num';     Label='Running threat / sec';                   Min=0;Max=100;Def=20;Scale=1;  Desc='Threat per second while running (between walking and sprinting).'}
  @{Tab='Sandworm'; Group='Sandworm'; Key='CrouchingThreatPerSec';                 Type='num';     Label='Crouching threat / sec';                 Min=0;Max=100;Def=15;Scale=1;  Desc='Threat per second while crouched / sneaking.'}
  @{Tab='Sandworm'; Group='Sandworm'; Key='SuspendingThreatPerSec';                Type='num';     Label='Suspensor-hover threat / sec';           Min=0;Max=500;Def=200;Scale=1; Desc='Threat per second while suspensor-hovering - very loud to worms (200 default).'}
  @{Tab='Sandworm'; Group='Sandworm'; Key='HyperSprintingThreatPerSec';            Type='num';     Label='Hyper-sprint threat / sec';              Min=0;Max=300;Def=90;Scale=1;  Desc='Threat per second while hyper-sprinting.'}
  @{Tab='Sandworm'; Group='Sandworm'; Key='VehicleShieldingThreatPerSec';          Type='num';     Label='Vehicle-shield threat / sec';            Min=0;Max=300;Def=50;Scale=1;  Desc='Threat per second with a vehicle shield active.'}
  @{Tab='Sandworm'; Group='Sandworm'; Key='m_SyncTargetIntervalSeconds';           Type='num';     Label='Re-target interval (s)';                 Min=1;Max=50;Def=10;Scale=0.1; Desc='How often the worm re-locks its target. Lower = snappier reactions.'}
  @{Tab='Sandworm'; Group='Sandworm'; Key='m_MinDistanceBetweenSandworms';         Type='num';     Label='Worm spacing (cm)';                      Min=20000;Max=200000;Def=80000;Scale=1;Desc='Minimum distance between worms (80000 = 800 m). Lower = denser worm population.'}
  @{Tab='Giant Worm'; Group='Sandworm'; Key='m_bGiantWormSystemEnabled';             Type='bool'; Label='Giant worm (Shai-Hulud) enabled';   Min=0;Max=1;Def=1;Scale=1;       Desc='Master toggle for the scripted giant worm that erupts on busy spice fields.'}
  @{Tab='Giant Worm'; Group='Sandworm'; Key='m_GiantWormMinimumPlayersOnSpiceField'; Type='num';  Label='Min players on spice field';          Min=1;Max=10;Def=4;Scale=1;      Desc='Players harvesting one spice field together needed to trigger it. 1 = any single harvester can summon it.'}
  @{Tab='Giant Worm'; Group='Sandworm'; Key='m_GiantWormMinimumSpiceAmountHarvested';Type='num';  Label='Spice harvested to trigger';          Min=0;Max=100000;Def=50000;Scale=1;Desc='Total spice that must be pulled from a field to call the giant worm. Lower = it comes sooner.'}
  @{Tab='Giant Worm'; Group='Sandworm'; Key='m_GiantWormSpawningCooldown';           Type='num';  Label='Cooldown between events (s)';          Min=0;Max=14400;Def=7200;Scale=1;Desc='Minimum seconds between giant-worm events (7200 = 2 h). 0 = back-to-back allowed.'}
  @{Tab='Giant Worm'; Group='Sandworm'; Key='m_GiantWormSpawningUpdateFrequency';    Type='num';  Label='Trigger check rate (s)';              Min=5;Max=300;Def=60;Scale=1;    Desc='How often the game checks whether to erupt the worm once conditions are met. Lower = appears faster.'}

  @{Tab='Storms';   Group='Storm';    Key='m_bCoriolisAutoSpawnEnabled';           Type='bool';    Label='Coriolis storm auto-spawn';              Min=0;Max=1;Def=1;Scale=1;     Desc='Whether the big map-wide Coriolis storms spawn automatically (default on).'}
  @{Tab='Storms';   Group='Storm';    Key='m_bCoriolisDoesDamage';                 Type='bool';    Label='Coriolis storm deals damage';            Min=0;Max=1;Def=0;Scale=1;     Desc='Whether the big Coriolis storm damages players/structures. Off by default.'}
  @{Tab='Storms';   Group='Storm';    Key='m_CoriolisHeavyDamage';                 Type='num';     Label='Coriolis core damage / tick';            Min=0;Max=10000;Def=5000;Scale=1;Desc='Damage the Coriolis core deals per tick when damage is on. 5000 = lethal.'}
  @{Tab='Storms';   Group='Storm';    Key='m_CoriolisLightDamage';                 Type='num';     Label='Coriolis edge damage / tick';            Min=0;Max=200;Def=5;Scale=1;   Desc='Damage the Coriolis outer band deals per tick.'}
  @{Tab='Storms';   Group='Storm';    Key='m_SmallSandStormDamageConfig';          Type='stormdmg';Label='Small sandstorm damage / tick';           Min=0;Max=50;Def=5;Scale=1;    Desc='Per-tick damage from a normal sandstorm to player/building/placeable/vehicle (sets all four).'}
  @{Tab='Storms';   Group='Storm';    Key='m_LargeSandStormDamageConfig';          Type='stormdmg';Label='Large sandstorm damage / tick';           Min=0;Max=50;Def=7;Scale=1;    Desc='Per-tick damage from a large sandstorm to all target types (sets all four).'}
  @{Tab='Storms';   Group='Storm';    Key='m_SandStormDebrisSpeed';                Type='num';     Label='Sandstorm debris speed';                 Min=0;Max=8000;Def=3000;Scale=1;Desc='Speed of flying sandstorm debris.'}
  @{Tab='Storms';   Group='Building'; Key='m_bMitigateAllSandstormDamage';         Type='bool';    Label='Ignore ALL sandstorm damage';            Min=0;Max=1;Def=0;Scale=1;     Desc='On = all sandstorm damage is ignored (storms become cosmetic).'}

  @{Tab='Harvest & economy'; Group='Harvest';   Key='m_NodeValueToSpiceResourceRatio'; Type='num'; Label='Spice harvest yield (x)';            Min=1;Max=50;Def=10;Scale=1;   Desc='Spice gained per unit of spice-node value - the spice HARVEST multiplier. Higher = more spice per harvest (default 10).'}
  @{Tab='Harvest & economy'; Group='FlourSand'; Key='m_FlourSandFieldsActivePercentage'; Type='num'; Label='Flour-sand fields active';         Min=0;Max=100;Def=100;Scale=0.01;Desc='Fraction of flour-sand fields active at once (1.00 = all). Affects water/flour-sand harvesting availability.'}
  @{Tab='Harvest & economy'; Group='Building';  Key='m_DefaultRepairCostMultiplier';   Type='num'; Label='Structure repair cost (x)';          Min=0;Max=30;Def=5;Scale=0.1;  Desc='Resource cost to repair structures. 0.0 = free, 1.0 = full (default 0.5).'}

  @{Tab='World & PvP'; Group='TimeOfDay'; Key='m_DayLengthMinutes';     Type='num';  Label='Day length (minutes)';        Min=5;Max=120;Def=30;Scale=1;  Desc='Real minutes for one full in-game day/night cycle.'}
  @{Tab='World & PvP'; Group='GameMode';  Key='m_DropAmountOnDefeat';   Type='num';  Label='Drop fraction on PvP defeat'; Min=0;Max=20;Def=8;Scale=0.05; Desc='Fraction of your droppable inventory dropped on PvP defeat. 0 = nothing, 1.0 = everything (default 0.4).'}
  @{Tab='World & PvP'; Group='Hydration'; Key='m_bHydrationEnabled';    Type='bool'; Label='Dehydration survival on';      Min=0;Max=1;Def=1;Scale=1;     Desc='Master toggle for the dehydration mechanic. Off = players never dehydrate.'}
)

# Format a raw slider value for DISPLAY (applies Scale; On/Off for bools).
function Disp-Val($s,$tbVal) {
  if ($s.Type -eq 'bool') { return $(if ([int]$tbVal -ge 1) {'On'} else {'Off'}) }
  $r = [double]$tbVal * [double]$s.Scale
  if ([double]$s.Scale -eq 1.0) { return [string][int][math]::Round($r) }
  if ([double]$s.Scale -ge 0.1) { return ('{0:0.0}' -f $r) }
  return ('{0:0.00}' -f $r)
}
# Convert a raw slider value into the value WRITTEN to the ini (True/False for
# bools; the 4-target tuple for stormdmg; the scaled number otherwise).
function Write-Val($s,$tbVal) {
  if ($s.Type -eq 'bool') { return $(if ([int]$tbVal -ge 1) {'True'} else {'False'}) }
  $d = Disp-Val $s $tbVal
  if ($s.Type -eq 'stormdmg') { return "(Player=$d,Building=$d,Placeable=$d,Vehicle=$d)" }
  return $d
}
# Convert a game-write value (from presets.json) BACK to a raw slider position.
function Raw-FromValue($s,$value) {
  if ($s.Type -eq 'bool') { return $(if ("$value" -match '^(True|1|On)$') {1} else {0}) }
  $num = $value
  if ($s.Type -eq 'stormdmg') { $m=[regex]::Match("$value",'Player=([0-9.]+)'); if($m.Success){$num=$m.Groups[1].Value} }
  $raw = [int][math]::Round([double]$num / [double]$s.Scale)
  if ($raw -lt $s.Min) { $raw = $s.Min }; if ($raw -gt $s.Max) { $raw = $s.Max }
  return $raw
}
# Run Wormageddon.ps1 synchronously and capture its output (for read/status).
function Invoke-Dune([string[]]$dargs) {
  try { (& powershell -NoProfile -ExecutionPolicy Bypass -File $DUNE @dargs 2>&1 | Out-String) } catch { "ERROR: $($_.Exception.Message)" }
}
# Launch a sequence of Wormageddon.ps1 calls in a visible console window so the
# user can watch a long-running apply+restart progress live.
function Run-Console([string[]]$lines,[string]$title) {
  $hdr  = @("`$Host.UI.RawUI.WindowTitle = '$title'", "Write-Host '== $title ==' -ForegroundColor Cyan", "Write-Host ''")
  $foot = @("Write-Host ''", "Write-Host 'DONE - close this window. Join the shard to see the effect.' -ForegroundColor Green")
  $tmp  = Join-Path $env:TEMP ('dune_run_' + [Guid]::NewGuid().ToString('N') + '.ps1')
  ($hdr + $lines + $foot) -join "`r`n" | Set-Content -LiteralPath $tmp -Encoding UTF8
  Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-NoExit','-File',('"'+$tmp+'"'))
}

# --------------------------------------------------------------------------
# "Connect to Server" dialog - collects host/user/key (or password) and writes
# dune-connection.json, then verifies by listing shards and caching the
# detected namespace + shard list. Nothing is stored anywhere but this PC.
# --------------------------------------------------------------------------
function Show-ConnectDialog {
  $ex=$null; if (Test-Path $CONNFILE) { try { $ex=Get-Content $CONNFILE -Raw | ConvertFrom-Json } catch {} }
  $d = New-Object System.Windows.Forms.Form
  $d.Text='Connect to Dune server'; $d.ClientSize=New-Object System.Drawing.Size(500,300); $d.StartPosition='CenterScreen'
  $d.FormBorderStyle='FixedDialog'; $d.MaximizeBox=$false; $d.MinimizeBox=$false; $d.Font=New-Object System.Drawing.Font('Segoe UI',9)
  function AddL($t,$y){ $l=New-Object System.Windows.Forms.Label; $l.Text=$t; $l.Location=New-Object System.Drawing.Point(16,$y); $l.AutoSize=$true; $d.Controls.Add($l) }
  AddL 'Server IP / hostname:' 18
  $tbHost=New-Object System.Windows.Forms.TextBox; $tbHost.Location='200,15'; $tbHost.Width=280; if($ex){$tbHost.Text="$($ex.Host)"}; $d.Controls.Add($tbHost)
  AddL 'SSH username:' 52
  $tbUser=New-Object System.Windows.Forms.TextBox; $tbUser.Location='200,49'; $tbUser.Width=280
  if ($ex -and "$($ex.User)".Trim()) { $tbUser.Text="$($ex.User)" } else { $tbUser.Text='dune' }
  $d.Controls.Add($tbUser)
  AddL 'SSH private key file:' 90
  $tbKey=New-Object System.Windows.Forms.TextBox; $tbKey.Location='200,87'; $tbKey.Width=198; if($ex){$tbKey.Text="$($ex.KeyPath)"}; $d.Controls.Add($tbKey)
  $btnBrowse=New-Object System.Windows.Forms.Button; $btnBrowse.Text='Browse...'; $btnBrowse.Location='404,86'; $btnBrowse.Width=80; $d.Controls.Add($btnBrowse)
  $btnBrowse.Add_Click({ $o=New-Object System.Windows.Forms.OpenFileDialog; $o.Title='Select SSH private key'; if($o.ShowDialog() -eq 'OK'){$tbKey.Text=$o.FileName} })
  AddL '...or SSH password:' 124
  $tbPw=New-Object System.Windows.Forms.TextBox; $tbPw.Location='200,121'; $tbPw.Width=280; $tbPw.UseSystemPasswordChar=$true; if($ex){$tbPw.Text="$($ex.Password)"}; $d.Controls.Add($tbPw)
  $note=New-Object System.Windows.Forms.Label; $note.Text='Tip: use the SSH key the Dune Dedicated Server Manager generated (look under its AppData folder for an "sshKey" file). Password auth requires PuTTY installed. Details are saved only on this PC in dune-connection.json.'; $note.Location='16,154'; $note.MaximumSize=New-Object System.Drawing.Size(468,0); $note.AutoSize=$true; $note.ForeColor=[System.Drawing.Color]::DimGray; $d.Controls.Add($note)
  $lblS=New-Object System.Windows.Forms.Label; $lblS.Location='16,212'; $lblS.MaximumSize=New-Object System.Drawing.Size(468,0); $lblS.AutoSize=$true; $lblS.ForeColor=[System.Drawing.Color]::FromArgb(40,90,150); $d.Controls.Add($lblS)
  $btnT=New-Object System.Windows.Forms.Button; $btnT.Text='Test && Save'; $btnT.Location='200,258'; $btnT.Width=130; $btnT.BackColor=[System.Drawing.Color]::FromArgb(40,120,60); $btnT.ForeColor=[System.Drawing.Color]::White; $d.Controls.Add($btnT)
  $btnX=New-Object System.Windows.Forms.Button; $btnX.Text='Cancel'; $btnX.Location='404,258'; $btnX.Width=80; $btnX.DialogResult='Cancel'; $d.Controls.Add($btnX); $d.CancelButton=$btnX
  $script:connOK=$false
  $btnT.Add_Click({
    $h=$tbHost.Text.Trim(); $u=$tbUser.Text.Trim(); $k=$tbKey.Text.Trim(); $p=$tbPw.Text
    if (-not $h) { $lblS.ForeColor=[System.Drawing.Color]::Firebrick; $lblS.Text='Enter the server IP/hostname.'; return }
    if (-not $k -and -not $p) { $lblS.ForeColor=[System.Drawing.Color]::Firebrick; $lblS.Text='Enter an SSH key file OR a password.'; return }
    if ($k -and -not (Test-Path $k)) { $lblS.ForeColor=[System.Drawing.Color]::Firebrick; $lblS.Text="Key file not found: $k"; return }
    $cfg=[ordered]@{ Host=$h; User=$u; KeyPath=$k; Password=$p; Namespace=''; Shards=@() }
    ($cfg | ConvertTo-Json) | Set-Content -LiteralPath $CONNFILE -Encoding UTF8
    $lblS.ForeColor=[System.Drawing.Color]::FromArgb(40,90,150); $lblS.Text='Testing connection... (a few seconds)'; $d.Refresh(); [System.Windows.Forms.Application]::DoEvents()
    $out = Invoke-Dune @('shards')
    $maps=@(($out -split "`r?`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -notmatch 'ERROR|Could not|not valid|Permission|denied|refused|timed out|timeout|No server|Unable|Warning|No route' })
    if ($maps.Count -gt 0) {
      $ns=(Invoke-Dune @('getns')).Trim()
      $cfg.Namespace=$ns; $cfg.Shards=$maps
      ($cfg | ConvertTo-Json) | Set-Content -LiteralPath $CONNFILE -Encoding UTF8
      $script:connOK=$true; $d.DialogResult='OK'; $d.Close()
    } else {
      $first=(($out -split "`r?`n") | Where-Object { $_.Trim() } | Select-Object -First 1)
      $lblS.ForeColor=[System.Drawing.Color]::Firebrick; $lblS.Text="Connection failed: $first"
    }
  })
  [void]$d.ShowDialog()
  return $script:connOK
}

# --------------------------------------------------------------------------
# Main window.
# --------------------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Wormageddon - Dune: Awakening Command Center'
$form.Size = New-Object System.Drawing.Size(760, 910)
$form.StartPosition = 'CenterScreen'; $form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$form.MinimumSize = New-Object System.Drawing.Size(720, 660)

# Row 1: shard picker + live-server actions.
$lblShard = New-Object System.Windows.Forms.Label; $lblShard.Text='Shard:'; $lblShard.Location='14,14'; $lblShard.AutoSize=$true
$cboShard = New-Object System.Windows.Forms.ComboBox; $cboShard.Location='60,11'; $cboShard.Width=140; $cboShard.DropDownStyle='DropDownList'; [void]$cboShard.Items.AddRange(@('Survival_1','Overmap')); $cboShard.SelectedIndex=0
$btnConnect=New-Object System.Windows.Forms.Button; $btnConnect.Text='Connect to Server'; $btnConnect.Location='210,9'; $btnConnect.Width=130
$btnRead  = New-Object System.Windows.Forms.Button; $btnRead.Text='Read current'; $btnRead.Location='348,9'; $btnRead.Width=105
$btnStatus= New-Object System.Windows.Forms.Button; $btnStatus.Text='Server status'; $btnStatus.Location='459,9'; $btnStatus.Width=100
$btnWorms = New-Object System.Windows.Forms.Button; $btnWorms.Text='Worms?'; $btnWorms.Location='565,9'; $btnWorms.Width=90
$form.Controls.AddRange(@($lblShard,$cboShard,$btnConnect,$btnRead,$btnStatus,$btnWorms))

# Row 2: curated presets - load a bundle into the sliders for review.
$lblPreset = New-Object System.Windows.Forms.Label; $lblPreset.Text='Preset:'; $lblPreset.Location='14,46'; $lblPreset.AutoSize=$true
$cboPreset = New-Object System.Windows.Forms.ComboBox; $cboPreset.Location='60,43'; $cboPreset.Width=300; $cboPreset.DropDownStyle='DropDownList'
$btnPreset = New-Object System.Windows.Forms.Button; $btnPreset.Text='Load preset into sliders'; $btnPreset.Location='368,42'; $btnPreset.Width=170
$lblPresetNote = New-Object System.Windows.Forms.Label; $lblPresetNote.Text='(then review and click APPLY + RESTART)'; $lblPresetNote.Location='548,46'; $lblPresetNote.AutoSize=$true; $lblPresetNote.ForeColor=[System.Drawing.Color]::DimGray
$form.Controls.AddRange(@($lblPreset,$cboPreset,$btnPreset,$lblPresetNote))

$txtHelp = New-Object System.Windows.Forms.TextBox
$txtHelp.Multiline=$true; $txtHelp.ReadOnly=$true; $txtHelp.ScrollBars='Vertical'; $txtHelp.Location='14,74'; $txtHelp.Size=New-Object System.Drawing.Size(720,96); $txtHelp.BackColor=[System.Drawing.Color]::FromArgb(245,245,240); $txtHelp.Anchor='Top, Left, Right'
$txtHelp.Text = @"
HOW TO USE  -  tune worm sign & threat in 4 steps:
 1. CONNECT - click "Connect to Server" (first run only): enter your server IP + SSH key. Saved locally on this PC.
 2. LOAD    - pick a shard, then "Read current" for live values, OR choose a Preset (Calm / Standard / WORMAGEDDON).
 3. TUNE    - drag the sliders across the tabs; each has a plain-English description (On/Off sliders are toggles).
 4. APPLY   - "APPLY + RESTART" writes your changes and reboots that shard.  "RESTORE DEFAULTS" reverts only this tool's settings.
 TABS      - the worm/settings tabs tune the game; the SERVER tab = status/players/lifecycle; the ADMIN tab = live in-game commands.
HEADS UP: these are SERVER settings - they take effect after the restart, so JOIN afterwards to see them. A restart drops the
players on that shard for ~1 min (warn them, or check "Worms?" first). Worms repopulate ~10 MIN after ANY restart - that's normal.
"@
$form.Controls.Add($txtHelp)

# Tab control with one AutoScroll panel per tab; sliders are added below.
$tc = New-Object System.Windows.Forms.TabControl; $tc.Location='14,176'; $tc.Size=New-Object System.Drawing.Size(720,498); $tc.Anchor='Top, Bottom, Left, Right'
$form.Controls.Add($tc)
$tabPanels = @{}
foreach ($tabName in @('Sandworm','Giant Worm','Storms','Harvest & economy','World & PvP')) {
  $tp = New-Object System.Windows.Forms.TabPage; $tp.Text=$tabName; $tp.BackColor=[System.Drawing.Color]::White
  $pn = New-Object System.Windows.Forms.Panel; $pn.Dock='Fill'; $pn.AutoScroll=$true
  $tp.Controls.Add($pn); [void]$tc.TabPages.Add($tp)
  $tabPanels[$tabName] = @{ Panel=$pn; Y=8 }
}

# Build one label + value + description + TrackBar per setting, stacking down
# its tab's panel. The TrackBar's Tag carries the setting + its value label so
# the ValueChanged handler can update the live readout.
foreach ($s in $SETTINGS) {
  $t = $tabPanels[$s.Tab]; $pn = $t.Panel; $y = $t.Y
  $name = New-Object System.Windows.Forms.Label; $name.Text=$s.Label; $name.Font=New-Object System.Drawing.Font('Segoe UI',9,[System.Drawing.FontStyle]::Bold)
  $name.Location=New-Object System.Drawing.Point(8,$y); $name.AutoSize=$true; $pn.Controls.Add($name)
  $val = New-Object System.Windows.Forms.Label; $val.Location=New-Object System.Drawing.Point(600,$y); $val.AutoSize=$true
  $val.Font=New-Object System.Drawing.Font('Consolas',10,[System.Drawing.FontStyle]::Bold); $val.Text=(Disp-Val $s $s.Def); $val.Anchor='Top, Right'; $pn.Controls.Add($val)
  $y += 20
  $desc = New-Object System.Windows.Forms.Label; $desc.Text=$s.Desc; $desc.ForeColor=[System.Drawing.Color]::DimGray
  $desc.Location=New-Object System.Drawing.Point(8,$y); $desc.MaximumSize=New-Object System.Drawing.Size(670,0); $desc.AutoSize=$true; $pn.Controls.Add($desc)
  $y += [math]::Max(18, $desc.PreferredHeight)
  $tb = New-Object System.Windows.Forms.TrackBar; $tb.Minimum=$s.Min; $tb.Maximum=$s.Max; $tb.Value=$s.Def
  $tb.TickStyle='None'; $tb.Location=New-Object System.Drawing.Point(6,$y); $tb.Size=New-Object System.Drawing.Size(670,40)
  $tb.LargeChange=[math]::Max(1,[int](($s.Max-$s.Min)/20)); $tb.Tag=@{S=$s; Val=$val}
  $tb.Add_ValueChanged({ $d=$this.Tag; $d.Val.Text = (Disp-Val $d.S $this.Value) })
  $tb.Anchor='Top, Left, Right'; $pn.Controls.Add($tb); $s.TB = $tb
  $t.Y = $y + 50
}

# ==========================================================================
# SERVER tab - live status + battlegroup lifecycle (drives Wormageddon.ps1).
# Controls build offline; data loads only on button click, so headless
# -SelfTest never touches the network.
# ==========================================================================
$tpServer = New-Object System.Windows.Forms.TabPage; $tpServer.Text='Server'; $tpServer.BackColor=[System.Drawing.Color]::White
$pnServer = New-Object System.Windows.Forms.Panel; $pnServer.Dock='Fill'
$btnSvStatus  = New-Object System.Windows.Forms.Button; $btnSvStatus.Text='Refresh status'; $btnSvStatus.Location='8,8'; $btnSvStatus.Width=110
$btnSvPlayers = New-Object System.Windows.Forms.Button; $btnSvPlayers.Text='Players'; $btnSvPlayers.Location='122,8'; $btnSvPlayers.Width=80
$btnSvWorms   = New-Object System.Windows.Forms.Button; $btnSvWorms.Text='Worms?'; $btnSvWorms.Location='206,8'; $btnSvWorms.Width=80
$lblLife = New-Object System.Windows.Forms.Label; $lblLife.Text='Lifecycle:'; $lblLife.Location='322,12'; $lblLife.AutoSize=$true
$btnSvRestart = New-Object System.Windows.Forms.Button; $btnSvRestart.Text='Restart (warn 60s)'; $btnSvRestart.Location='386,8'; $btnSvRestart.Width=126
$btnSvStart   = New-Object System.Windows.Forms.Button; $btnSvStart.Text='Start'; $btnSvStart.Location='516,8'; $btnSvStart.Width=58
$btnSvStop    = New-Object System.Windows.Forms.Button; $btnSvStop.Text='Stop'; $btnSvStop.Location='578,8'; $btnSvStop.Width=58
$btnSvUpdate  = New-Object System.Windows.Forms.Button; $btnSvUpdate.Text='Update'; $btnSvUpdate.Location='640,8'; $btnSvUpdate.Width=64
$txtServer = New-Object System.Windows.Forms.TextBox; $txtServer.Multiline=$true; $txtServer.ReadOnly=$true; $txtServer.ScrollBars='Both'; $txtServer.WordWrap=$false
$txtServer.Font=New-Object System.Drawing.Font('Consolas',9); $txtServer.Location='8,40'; $txtServer.Size=New-Object System.Drawing.Size(700,412); $txtServer.Anchor='Top, Bottom, Left, Right'
$txtServer.Text = 'Click "Refresh status" for battlegroup health + player counts, "Players" for the roster, or "Worms?" for the warm-up check.'
$pnServer.Controls.AddRange(@($btnSvStatus,$btnSvPlayers,$btnSvWorms,$lblLife,$btnSvRestart,$btnSvStart,$btnSvStop,$btnSvUpdate,$txtServer))
$tpServer.Controls.Add($pnServer); [void]$tc.TabPages.Add($tpServer)

$btnSvStatus.Add_Click({ $txtServer.Text='Querying...'; [System.Windows.Forms.Application]::DoEvents(); $txtServer.Text=(Invoke-Dune @('status')).TrimEnd() })
$btnSvPlayers.Add_Click({ $txtServer.Text='Querying...'; [System.Windows.Forms.Application]::DoEvents(); $txtServer.Text=(Invoke-Dune @('players')).TrimEnd() })
$btnSvWorms.Add_Click({ $sh=$cboShard.SelectedItem; $txtServer.Text=(Invoke-Dune @('worms','-Shard',$sh)).TrimEnd() })
$btnSvRestart.Add_Click({
  $sh=$cboShard.SelectedItem
  if ([System.Windows.Forms.MessageBox]::Show("Restart $sh now? Players get a 60-second in-game warning first, then the shard reboots (~1 min).",'Restart shard',[System.Windows.Forms.MessageBoxButtons]::YesNo) -ne 'Yes'){return}
  Run-Console @("& '$DUNE' restart -Shard $sh -WarnSeconds 60 -Yes") "Wormageddon RESTART -> $sh"; Log "Restart (60s warning) launched for $sh."
})
$btnSvStart.Add_Click({
  if ([System.Windows.Forms.MessageBox]::Show('Start the battlegroup?','Start',[System.Windows.Forms.MessageBoxButtons]::YesNo) -ne 'Yes'){return}
  Run-Console @("& '$DUNE' start -Yes") 'Wormageddon START'; Log 'Start launched.'
})
$btnSvStop.Add_Click({
  if ([System.Windows.Forms.MessageBox]::Show('STOP the battlegroup? This drops ALL players and the survival shard can hang on graceful stop.','Stop',[System.Windows.Forms.MessageBoxButtons]::YesNo,[System.Windows.Forms.MessageBoxIcon]::Warning) -ne 'Yes'){return}
  Run-Console @("& '$DUNE' stop -Yes") 'Wormageddon STOP'; Log 'Stop launched.'
})
$btnSvUpdate.Add_Click({
  if ([System.Windows.Forms.MessageBox]::Show('Update the server? It may restart to apply.','Update',[System.Windows.Forms.MessageBoxButtons]::YesNo) -ne 'Yes'){return}
  Run-Console @("& '$DUNE' update -Yes") 'Wormageddon UPDATE'; Log 'Update launched.'
})

# ==========================================================================
# ADMIN tab - live in-game commands via the daemon (drives `publish`). The
# command list mirrors the daemon catalogue; fields render per command; the
# player list loads on demand. Nothing here touches the network at build time.
# ==========================================================================
$ADMINCMDS = @(
  @{Id='ServiceBroadcast';      Label='Broadcast message';              Player=$false; Fixed=@{BroadcastType='Generic'}; Fields=@(@{K='Title';D='Server'},@{K='Body';D=''},@{K='BroadcastDuration';D='30'})}
  @{Id='AddItemToInventory';    Label='Give item';                      Player=$true;  Fixed=@{};                        Fields=@(@{K='ItemName';D=''},@{K='Quantity';D='1'})}
  @{Id='AwardXP';               Label='Award XP';                       Player=$true;  Fixed=@{};                        Fields=@(@{K='Experience';D='1000'})}
  @{Id='UpdateAllWaterFillables';Label='Refill water';                  Player=$true;  Fixed=@{};                        Fields=@(@{K='WaterAmount';D='1000000'})}
  @{Id='TeleportTo';            Label='Teleport (safe)';                Player=$true;  Fixed=@{};                        Fields=@(@{K='X';D='0'},@{K='Y';D='0'},@{K='Z';D='0'})}
  @{Id='SpawnVehicleAt';        Label='Spawn vehicle';                  Player=$true;  Fixed=@{};                        Fields=@(@{K='ClassName';D=''},@{K='X';D='0'},@{K='Y';D='0'},@{K='Z';D='0'})}
  @{Id='KickPlayer';            Label='Kick player';                    Player=$true;  Fixed=@{};                        Fields=@()}
  @{Id='CleanPlayerInventory';  Label='Clean inventory (DESTRUCTIVE)';  Player=$true;  Fixed=@{};                        Fields=@()}
  @{Id='ResetProgression';      Label='Reset progression (DESTRUCTIVE)';Player=$true;  Fixed=@{};                        Fields=@()}
)
$tpAdmin = New-Object System.Windows.Forms.TabPage; $tpAdmin.Text='Admin'; $tpAdmin.BackColor=[System.Drawing.Color]::White
$pnAdmin = New-Object System.Windows.Forms.Panel; $pnAdmin.Dock='Fill'
$lblPl = New-Object System.Windows.Forms.Label; $lblPl.Text='Player:'; $lblPl.Location='8,12'; $lblPl.AutoSize=$true
$cboPlayer = New-Object System.Windows.Forms.ComboBox; $cboPlayer.Location='56,9'; $cboPlayer.Width=246; $cboPlayer.DropDownStyle='DropDownList'
$btnPlRefresh = New-Object System.Windows.Forms.Button; $btnPlRefresh.Text='Refresh players'; $btnPlRefresh.Location='308,8'; $btnPlRefresh.Width=110
$lblCmd = New-Object System.Windows.Forms.Label; $lblCmd.Text='Command:'; $lblCmd.Location='8,44'; $lblCmd.AutoSize=$true
$cboCmd = New-Object System.Windows.Forms.ComboBox; $cboCmd.Location='72,41'; $cboCmd.Width=346; $cboCmd.DropDownStyle='DropDownList'
foreach ($c in $ADMINCMDS) { [void]$cboCmd.Items.Add($c.Label) }
$pnFields = New-Object System.Windows.Forms.Panel; $pnFields.Location='8,76'; $pnFields.Size=New-Object System.Drawing.Size(700,150); $pnFields.Anchor='Top, Left, Right'; $pnFields.AutoScroll=$true; $pnFields.BorderStyle='FixedSingle'
$btnAdPreview = New-Object System.Windows.Forms.Button; $btnAdPreview.Text='Preview (dry-run)'; $btnAdPreview.Location='8,234'; $btnAdPreview.Width=130
$btnAdSend = New-Object System.Windows.Forms.Button; $btnAdSend.Text='SEND'; $btnAdSend.Location='146,234'; $btnAdSend.Width=100; $btnAdSend.BackColor=[System.Drawing.Color]::FromArgb(150,60,60); $btnAdSend.ForeColor=[System.Drawing.Color]::White
$lblAdNote = New-Object System.Windows.Forms.Label; $lblAdNote.Text='Live commands need the dune-server-service daemon on the VM. Preview shows the exact payload without sending. SEND asks to confirm.'; $lblAdNote.Location='8,272'; $lblAdNote.MaximumSize=New-Object System.Drawing.Size(690,0); $lblAdNote.AutoSize=$true; $lblAdNote.ForeColor=[System.Drawing.Color]::DimGray
$pnAdmin.Controls.AddRange(@($lblPl,$cboPlayer,$btnPlRefresh,$lblCmd,$cboCmd,$pnFields,$btnAdPreview,$btnAdSend,$lblAdNote))
$tpAdmin.Controls.Add($pnAdmin); [void]$tc.TabPages.Add($tpAdmin)

$script:AdminBoxes=@{}
function Build-AdminFields {
  $pnFields.Controls.Clear(); $script:AdminBoxes=@{}
  $i=$cboCmd.SelectedIndex; if ($i -lt 0){return}
  $c=$ADMINCMDS[$i]; $y=6
  foreach ($fld in $c.Fields) {
    $l=New-Object System.Windows.Forms.Label; $l.Text=$fld.K; $l.Location=New-Object System.Drawing.Point(6,($y+3)); $l.Width=150
    $t=New-Object System.Windows.Forms.TextBox; $t.Text="$($fld.D)"; $t.Location=New-Object System.Drawing.Point(162,$y); $t.Width=500; $t.Anchor='Top, Left, Right'
    $pnFields.Controls.AddRange(@($l,$t)); $script:AdminBoxes[$fld.K]=$t; $y+=30
  }
  if (@($c.Fields).Count -eq 0) { $l=New-Object System.Windows.Forms.Label; $l.Text='(targets the selected player; no extra fields)'; $l.Location=New-Object System.Drawing.Point(6,6); $l.AutoSize=$true; $l.ForeColor=[System.Drawing.Color]::DimGray; $pnFields.Controls.Add($l) }
}
function Coerce-JsonVal($v) {
  if ($v -match '^-?\d+$') { return [int]$v }
  if ($v -match '^-?\d+\.\d+$') { return [double]$v }
  return $v
}
function Build-AdminPayload {
  $i=$cboCmd.SelectedIndex; if ($i -lt 0){ return $null }
  $c=$ADMINCMDS[$i]; $f=@{}
  foreach ($k in $c.Fixed.Keys) { $f[$k]=$c.Fixed[$k] }
  if ($c.Player) {
    $p=$cboPlayer.SelectedItem
    if (-not $p) { Log 'Pick a player first (click "Refresh players").'; return $null }
    $f['PlayerId']=$p.FlsId
  }
  foreach ($k in @($script:AdminBoxes.Keys)) { $val=$script:AdminBoxes[$k].Text; if ($val -ne '') { $f[$k]=Coerce-JsonVal $val } }
  return @{ Id=$c.Id; Json=($f | ConvertTo-Json -Compress); Label=$c.Label }
}
$cboCmd.Add_SelectedIndexChanged({ Build-AdminFields })
$btnPlRefresh.Add_Click({
  Log 'Loading players...'; $cboPlayer.Items.Clear()
  $out=Invoke-Dune @('players')
  try {
    foreach ($pl in ($out | ConvertFrom-Json)) {
      $item=New-Object PSObject -Property @{ FlsId=$pl.flsId; Disp=("{0}  [{1}]" -f $pl.name,$pl.online) }
      $item | Add-Member ScriptMethod ToString { $this.Disp } -Force
      [void]$cboPlayer.Items.Add($item)
    }
    if ($cboPlayer.Items.Count -gt 0){$cboPlayer.SelectedIndex=0}
    Log "Loaded $($cboPlayer.Items.Count) player(s)."
  } catch { Log "Could not read players (is the daemon up?): $(($out|Out-String).Trim())" }
})
$btnAdPreview.Add_Click({
  $p=Build-AdminPayload; if (-not $p){return}
  [void](Invoke-Dune @('publish',$p.Id,$p.Json,'-DryRun'))
  Log "PREVIEW $($p.Label): $($p.Json)"
})
$btnAdSend.Add_Click({
  $p=Build-AdminPayload; if (-not $p){return}
  if ([System.Windows.Forms.MessageBox]::Show("Send '$($p.Label)' to the LIVE server now?`n`n$($p.Json)",'Confirm live command',[System.Windows.Forms.MessageBoxButtons]::YesNo,[System.Windows.Forms.MessageBoxIcon]::Warning) -ne 'Yes'){return}
  $r=Invoke-Dune @('publish',$p.Id,$p.Json,'-Yes')
  Log "SEND $($p.Label): $(($r|Out-String).Trim())"
})
if ($cboCmd.Items.Count -gt 0){ $cboCmd.SelectedIndex=0 }

# ==========================================================================
# BASES tab - back up a live base to a JSON file (the "Solido Replicator"
# export). Read-only. Restore/import is CLI + experimental (see docs).
# ==========================================================================
$tpBases = New-Object System.Windows.Forms.TabPage; $tpBases.Text='Bases'; $tpBases.BackColor=[System.Drawing.Color]::White
$pnBases = New-Object System.Windows.Forms.Panel; $pnBases.Dock='Fill'
$btnBsList   = New-Object System.Windows.Forms.Button; $btnBsList.Text='List bases'; $btnBsList.Location='8,8'; $btnBsList.Width=100
$btnBsExport = New-Object System.Windows.Forms.Button; $btnBsExport.Text='Back up selected base -> file'; $btnBsExport.Location='114,8'; $btnBsExport.Width=190
$lstBases = New-Object System.Windows.Forms.ListBox; $lstBases.Location='8,42'; $lstBases.Size=New-Object System.Drawing.Size(700,368); $lstBases.Font=New-Object System.Drawing.Font('Consolas',9); $lstBases.Anchor='Top, Bottom, Left, Right'
$lblBsNote = New-Object System.Windows.Forms.Label; $lblBsNote.Text='Backs up a live base (buildings + placeables) to a .json in the "bases" folder. Needs DbPassword in dune-connection.json. Restore/import is planned (a guarded live write - see docs/BASES.md).'; $lblBsNote.Location='8,416'; $lblBsNote.MaximumSize=New-Object System.Drawing.Size(700,0); $lblBsNote.AutoSize=$true; $lblBsNote.ForeColor=[System.Drawing.Color]::DimGray; $lblBsNote.Anchor='Bottom, Left, Right'
$pnBases.Controls.AddRange(@($btnBsList,$btnBsExport,$lstBases,$lblBsNote))
$tpBases.Controls.Add($pnBases); [void]$tc.TabPages.Add($tpBases)

$btnBsList.Add_Click({
  Log 'Listing bases...'; $lstBases.Items.Clear()
  foreach ($ln in ((Invoke-Dune @('bases')) -split "`r?`n")) {
    if ($ln -match '^\s*(-?\d+)\|(-?\d+)\|(\d+)\|(\d+)') {
      $item = New-Object PSObject -Property @{ Bid=$Matches[1]; Disp=("base {0,-6}  {1,4} pieces  {2,3} placeables  (owner {3})" -f $Matches[1],$Matches[3],$Matches[4],$Matches[2]) }
      $item | Add-Member ScriptMethod ToString { $this.Disp } -Force
      [void]$lstBases.Items.Add($item)
    }
  }
  Log "Found $($lstBases.Items.Count) base(s). Select one and click 'Back up selected base'."
})
$btnBsExport.Add_Click({
  $sel=$lstBases.SelectedItem
  if (-not $sel) { Log 'Select a base in the list first (click "List bases").'; return }
  Log "Backing up base $($sel.Bid)..."
  $r = Invoke-Dune @('base-export',$sel.Bid)
  Log (($r | Out-String).Trim())
})

# Activity log strip at the bottom.
$log = New-Object System.Windows.Forms.TextBox
$log.Multiline=$true; $log.ReadOnly=$true; $log.ScrollBars='Vertical'; $log.Location='14,682'; $log.Size=New-Object System.Drawing.Size(720,96); $log.BackColor=[System.Drawing.Color]::Black; $log.ForeColor=[System.Drawing.Color]::Lime; $log.Font=New-Object System.Drawing.Font('Consolas',8); $log.Anchor='Bottom, Left, Right'
$form.Controls.Add($log)
function Log($m){ $log.AppendText(((Get-Date -Format 'HH:mm:ss')+'  '+$m+"`r`n")); $log.SelectionStart=$log.Text.Length; $log.ScrollToCaret(); [System.Windows.Forms.Application]::DoEvents() }

# Refresh the shard dropdown from the saved connection (or by asking the server).
function Update-Shards {
  $maps=@()
  if (Test-Path $CONNFILE) { try { $c=Get-Content $CONNFILE -Raw | ConvertFrom-Json; if ($c.Shards) { $maps=@($c.Shards) } } catch {} }
  if ($maps.Count -eq 0) {
    $out=Invoke-Dune @('shards')
    $maps=@(($out -split "`r?`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -notmatch 'ERROR|Could not|not valid|Permission|denied|refused|timeout|No server' })
  }
  if ($maps.Count -eq 0) { $maps=@('Survival_1','Overmap') }
  $cur=$cboShard.SelectedItem
  $cboShard.Items.Clear(); [void]$cboShard.Items.AddRange([object[]]$maps)
  if ($cur -and $cboShard.Items.Contains($cur)) { $cboShard.SelectedItem=$cur } else { $cboShard.SelectedIndex=0 }
}

# Populate the preset dropdown from presets.json (label text, name in Tag).
$script:Presets = $null
function Load-PresetList {
  $cboPreset.Items.Clear()
  if (-not (Test-Path $PRESETF)) { return }
  try { $script:Presets = Get-Content $PRESETF -Raw | ConvertFrom-Json } catch { Log "presets.json invalid: $($_.Exception.Message)"; return }
  foreach ($p in $script:Presets.PSObject.Properties) {
    if ($p.Name -like '_*') { continue }   # skip the _comment doc key
    $item = New-Object PSObject -Property @{ Name=$p.Name; Label=$p.Value.label }
    $item | Add-Member ScriptMethod ToString { $this.Label } -Force
    [void]$cboPreset.Items.Add($item)
  }
  if ($cboPreset.Items.Count -gt 0) { $cboPreset.SelectedIndex=0 }
}

# Bottom action row.
$btnApply = New-Object System.Windows.Forms.Button; $btnApply.Text='APPLY + RESTART'; $btnApply.Location='14,786'; $btnApply.Size=New-Object System.Drawing.Size(170,34); $btnApply.BackColor=[System.Drawing.Color]::FromArgb(40,120,60); $btnApply.ForeColor=[System.Drawing.Color]::White
$btnReset = New-Object System.Windows.Forms.Button; $btnReset.Text='RESTORE DEFAULTS'; $btnReset.Location='192,786'; $btnReset.Size=New-Object System.Drawing.Size(170,34)
$btnSummon = New-Object System.Windows.Forms.Button; $btnSummon.Text='SUMMON SHAI-HULUD'; $btnSummon.Location='370,786'; $btnSummon.Size=New-Object System.Drawing.Size(170,34); $btnSummon.BackColor=[System.Drawing.Color]::FromArgb(190,120,30); $btnSummon.ForeColor=[System.Drawing.Color]::White
$btnClose = New-Object System.Windows.Forms.Button; $btnClose.Text='Close'; $btnClose.Location='656,786'; $btnClose.Size=New-Object System.Drawing.Size(78,34)
$btnApply.Anchor='Bottom, Left'; $btnReset.Anchor='Bottom, Left'; $btnSummon.Anchor='Bottom, Left'; $btnClose.Anchor='Bottom, Right'
$form.Controls.AddRange(@($btnApply,$btnReset,$btnSummon,$btnClose))

# The bottom APPLY / RESTORE / SUMMON row only applies to the settings tabs;
# hide it on Server/Admin so those tabs read cleanly.
$SETTINGS_TABS = @('Sandworm','Giant Worm','Storms','Harvest & economy','World & PvP')
$tc.Add_SelectedIndexChanged({
  $isSettings = $SETTINGS_TABS -contains $tc.SelectedTab.Text
  $btnApply.Visible=$isSettings; $btnReset.Visible=$isSettings; $btnSummon.Visible=$isSettings
})

$btnConnect.Add_Click({ if (Show-ConnectDialog) { Log 'Connected.'; Update-Shards } else { Log 'Connect cancelled.' } })
$btnStatus.Add_Click({ Log 'Querying server status...'; Log (Invoke-Dune @('status')).Trim() })

# "Worms?" - interpret the spawn-count + uptime probe into plain English.
$btnWorms.Add_Click({
  $shard=$cboShard.SelectedItem; Log "Checking worms on $shard ..."
  $out = Invoke-Dune @('worms','-Shard',$shard)
  $sp=0; $up=0
  if ($out -match 'spawned=(\d+)') { $sp=[int]$Matches[1] }
  if ($out -match 'uptime_sec=(\d+)') { $up=[int]$Matches[1] }
  $um=[int]($up/60)
  if ($sp -gt 0) { Log "${shard}: up ${um}m - $sp sandworm spawn(s) this session - WORMS ARE UP." }
  elseif ($up -lt 600) { $left=[int][math]::Ceiling((600-$up)/60); Log "${shard}: up ${um}m - 0 worms yet - warming up (~$left min left of the ~10 min delay)." }
  else { Log "${shard}: up ${um}m - 0 worms in recent log; warm-up should be done, click again shortly." }
})

# "Read current" - pull the shard's live overrides and set each slider to match
# (unset keys fall back to the game default).
$btnRead.Add_Click({
  $shard=$cboShard.SelectedItem; $btnRead.Enabled=$false; $form.Cursor='WaitCursor'
  Log "Reading current overrides on $shard ..."
  $txt = Invoke-Dune @('show','-Shard',$shard)
  foreach ($s in $SETTINGS) {
    $tv = $s.Def; $k=[regex]::Escape($s.Key)
    if ($s.Type -eq 'bool') { $m=[regex]::Match($txt,'(?m)^\s*'+$k+'\s*=\s*(True|False)'); if($m.Success){ $tv=$(if($m.Groups[1].Value -eq 'True'){1}else{0}) } }
    elseif ($s.Type -eq 'stormdmg') { $m=[regex]::Match($txt,'(?m)^\s*'+$k+'\s*=\s*\(Player=([0-9.]+)'); if($m.Success){ $tv=[int][math]::Round([double]$m.Groups[1].Value/[double]$s.Scale) } }
    else { $m=[regex]::Match($txt,'(?m)^\s*'+$k+'\s*=\s*([0-9.]+)'); if($m.Success){ $tv=[int][math]::Round([double]$m.Groups[1].Value/[double]$s.Scale) } }
    if($tv -lt $s.Min){$tv=$s.Min}; if($tv -gt $s.Max){$tv=$s.Max}
    $s.TB.Value=$tv
  }
  Log 'Loaded. (settings not overridden show their game default)'; $btnRead.Enabled=$true; $form.Cursor='Default'
})

# "Load preset into sliders" - set sliders from the selected presets.json bundle
# WITHOUT applying, so the operator can review before committing.
$btnPreset.Add_Click({
  $sel=$cboPreset.SelectedItem
  if (-not $sel) { Log 'No preset selected (is presets.json present?).'; return }
  $pset = $script:Presets.PSObject.Properties[$sel.Name].Value
  $applied=0; $skipped=0
  foreach ($e in $pset.settings) {
    $s = $SETTINGS | Where-Object { $_.Key -eq $e.key } | Select-Object -First 1
    if (-not $s) { $skipped++; continue }
    $s.TB.Value = (Raw-FromValue $s $e.value); $applied++
  }
  Log "Loaded preset '$($sel.Label)' into $applied slider(s)$(if($skipped){" ($skipped not shown as sliders)"}). Review, then APPLY + RESTART."
})

# "APPLY + RESTART" - emit a `set` for every slider moved off default, then a
# `restart`, and run them in a visible console so the user watches progress.
$btnApply.Add_Click({
  $shard=$cboShard.SelectedItem
  $changed = @($SETTINGS | Where-Object { $_.TB.Value -ne $_.Def })
  $msg = if ($changed.Count) { "Apply $($changed.Count) change(s) across all tabs to $shard and RESTART it now? Players on $shard drop (~1 min). Progress opens in a console." } else { "No sliders changed from default. Restart $shard anyway?" }
  if ([System.Windows.Forms.MessageBox]::Show($msg,'Confirm apply',[System.Windows.Forms.MessageBoxButtons]::YesNo) -ne 'Yes') { return }
  $lines=@()
  foreach ($s in $changed) { $wv=Write-Val $s $s.TB.Value; $lines += "& '$DUNE' set $($s.Group) $($s.Key) '$wv' -Shard $shard" }
  $lines += "& '$DUNE' restart -Shard $shard -Yes"
  Run-Console $lines "Wormageddon APPLY -> $shard"
  Log "Apply launched for $shard ($($changed.Count) change(s)) in a console window - watch for the 'Ready' line."
})

# "RESTORE DEFAULTS" - unset every key this tool manages, then restart.
$btnReset.Add_Click({
  $shard=$cboShard.SelectedItem
  if ([System.Windows.Forms.MessageBox]::Show("Remove ALL settings this tool manages on $shard (revert to game defaults) and restart it? Your other config (e.g. PvP/landclaim) is NOT touched. Progress opens in a console.",'Restore defaults',[System.Windows.Forms.MessageBoxButtons]::YesNo) -ne 'Yes') { return }
  $lines=@()
  foreach ($s in $SETTINGS) { $s.TB.Value=$s.Def; $lines += "& '$DUNE' unset $($s.Group) $($s.Key) -Shard $shard" }
  $lines += "& '$DUNE' restart -Shard $shard -Yes"
  Run-Console $lines "Wormageddon RESTORE DEFAULTS -> $shard"
  Log "Restore launched for $shard in a console window; sliders reset to defaults."
})

# "SUMMON SHAI-HULUD" - the headline party trick: make the giant worm summonable
# on demand by a single spice harvester, then restart so it takes effect.
$btnSummon.Add_Click({
  $shard=$cboShard.SelectedItem
  if ([System.Windows.Forms.MessageBox]::Show("Set Shai-Hulud to SUMMON-ON-DEMAND on $shard and restart? Afterward, ANY single player harvesting spice on a field calls a giant worm within ~1 minute. Undo with RESTORE DEFAULTS. (Restart drops $shard's players for ~1 min.)",'Summon Shai-Hulud',[System.Windows.Forms.MessageBoxButtons]::YesNo) -ne 'Yes') { return }
  $easy = @{ 'm_bGiantWormSystemEnabled'=1; 'm_GiantWormMinimumPlayersOnSpiceField'=1; 'm_GiantWormMinimumSpiceAmountHarvested'=1000; 'm_GiantWormSpawningCooldown'=30; 'm_GiantWormSpawningUpdateFrequency'=10 }
  $lines=@()
  foreach ($s in $SETTINGS) {
    if ($easy.ContainsKey($s.Key)) {
      $tv=[int]$easy[$s.Key]; if ($tv -lt $s.Min){$tv=$s.Min}; if ($tv -gt $s.Max){$tv=$s.Max}
      $s.TB.Value=$tv
      $wv = Write-Val $s $tv
      $lines += "& '$DUNE' set $($s.Group) $($s.Key) '$wv' -Shard $shard"
    }
  }
  $lines += "& '$DUNE' restart -Shard $shard -Yes"
  Run-Console $lines "Wormageddon SUMMON Shai-Hulud -> $shard"
  Log "Shai-Hulud summon-mode launched for $shard. After it restarts, harvest spice on a field to call the giant worm (~1 min)."
})

$btnClose.Add_Click({ $form.Close() })

# On show: load presets, then either prompt to connect (first run) or load the
# saved connection's shard list.
$form.Add_Shown({
  Load-PresetList
  if (-not (Test-Path $CONNFILE)) {
    Log 'No server configured. Opening "Connect to Server"...'
    if (Show-ConnectDialog) { Log 'Connected.'; Update-Shards } else { Log 'Not connected - click "Connect to Server" when ready.' }
  } else { Update-Shards; Log 'Loaded saved connection. Click "Read current" to pull live values, or pick a Preset.' }
})

# Headless smoke test (used by build.bat / CI): build the form, report, exit.
if ($SelfTest) {
  Load-PresetList
  if ($cboCmd.Items.Count -gt 0){ $cboCmd.SelectedIndex=0; Build-AdminFields }
  Write-Host "SELFTEST OK: $($tc.TabPages.Count) tabs ($($SETTINGS.Count) settings + Server + Admin + Bases), $($cboPreset.Items.Count) preset(s), $($cboCmd.Items.Count) admin command(s)"
  $form.Dispose(); return
}
[void]$form.ShowDialog()
