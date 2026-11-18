<#
.SYNOPSIS
  Collects what is needed to compare Company of Heroes + Blitzkrieg installs between players.
  Run it on each player's PC. It writes one zip (BK-report-<PC>-<date>.zip) on the Desktop;
  send that zip to the person consolidating. Nothing is changed on the machine.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\BK-collect.ps1
  powershell -NoProfile -ExecutionPolicy Bypass -File .\BK-collect.ps1 -NoReplay
  powershell -NoProfile -ExecutionPolicy Bypass -File .\BK-collect.ps1 -GamePath "D:\Steam\steamapps\common\Company of Heroes Relaunch"

.PARAMETER GamePath   Game folder (the one with RelicCOH.exe). Auto-detected via Steam when omitted.
.PARAMETER OutDir     Where the zip goes. Default: Desktop.
.PARAMETER NoReplay   Leave out the replay files (use when the zip is too big for Discord).
.PARAMETER Full       Also hash the art/sound/speech archives (slow, normally not needed).
.PARAMETER LogDays    Copy log files newer than this many days (default 14), plus the newest 3 of each kind.
#>
[CmdletBinding()]
param(
  [string]$GamePath,
  [string]$OutDir = [Environment]::GetFolderPath('Desktop'),
  [switch]$NoReplay,
  [switch]$Full,
  [int]$LogDays = 14
)

$ErrorActionPreference = 'Continue'
$sw = [Diagnostics.Stopwatch]::StartNew()
$utf8 = New-Object System.Text.UTF8Encoding($false)
$errors = New-Object System.Collections.Generic.List[string]
$findings = New-Object System.Collections.Generic.List[string]
$summary = [ordered]@{}
$manifest = New-Object System.Collections.Generic.List[string]
$manifest.Add('Group,RelativePath,Bytes,LastWriteUtc,SHA256')

function Say($m) { Write-Host ("[{0,4:n0}s] {1}" -f $sw.Elapsed.TotalSeconds, $m) }
function Note($k, $v) { $script:summary[$k] = [string]$v }
function Finding($m) { $script:findings.Add($m); Write-Host "  * $m" -ForegroundColor Cyan }
function Fail($m) { $script:errors.Add($m); Write-Host "  ! $m" -ForegroundColor Yellow }
function Csv($s) { '"' + ([string]$s -replace '"', '""') + '"' }
function MB($bytes) { [math]::Round([double]$bytes / 1MB, 1) }

function AddFile($group, $root, $file, $hash) {
  $rel = $file.FullName.Substring($root.Length).TrimStart('\')
  $h = ''
  if ($hash) {
    try { $h = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256 -ErrorAction Stop).Hash }
    catch { Fail "hash failed: $($file.FullName)" }
  }
  $script:manifest.Add(($group, (Csv $rel), $file.Length, $file.LastWriteTimeUtc.ToString('yyyy-MM-dd HH:mm:ss'), $h) -join ',')
}

# Adds every file under $path to the manifest; $hashIf decides per file whether to hash it.
function AddTree($group, $root, $path, [scriptblock]$hashIf) {
  if (-not (Test-Path -LiteralPath $path)) { Note "missing.$group" $path; Say "$group : not present ($path)"; return }
  $files = @(Get-ChildItem -LiteralPath $path -Recurse -File -Force -ErrorAction SilentlyContinue)
  $n = 0; $bytes = 0
  foreach ($f in $files) {
    $n++; $bytes += $f.Length
    if ($n % 20 -eq 0) { Write-Progress -Activity "Hashing $group" -Status "$n / $($files.Count)" -PercentComplete (100 * $n / $files.Count) }
    AddFile $group $root $f (& $hashIf $f)
  }
  Write-Progress -Activity "Hashing $group" -Completed
  Note "count.$group" $files.Count
  Note "mb.$group" (MB $bytes)
  Say "$group : $($files.Count) files, $(MB $bytes) MB"
}

function CopyTo($src, $dstDir) {
  if (Test-Path -LiteralPath $src) {
    New-Item -ItemType Directory -Force -Path $dstDir | Out-Null
    Copy-Item -LiteralPath $src -Destination $dstDir -Force -ErrorAction SilentlyContinue
  }
}

# ---------------------------------------------------------------- locate things
$steamPath = $null
try { $steamPath = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction Stop).SteamPath -replace '/', '\' } catch {}

function Find-Game {
  $c = New-Object System.Collections.Generic.List[string]
  if ($GamePath) { $c.Add($GamePath) }
  if ($PSScriptRoot) { $c.Add($PSScriptRoot) }
  try {
    $il = (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 228200' -ErrorAction Stop).InstallLocation
    if ($il) { $c.Add($il) }
  } catch {}
  if ($steamPath) {
    $c.Add("$steamPath\steamapps\common\Company of Heroes Relaunch")
    $vdf = "$steamPath\steamapps\libraryfolders.vdf"
    if (Test-Path -LiteralPath $vdf) {
      foreach ($m in [regex]::Matches((Get-Content -LiteralPath $vdf -Raw), '"path"\s+"([^"]+)"')) {
        $c.Add(($m.Groups[1].Value -replace '\\\\', '\') + '\steamapps\common\Company of Heroes Relaunch')
      }
    }
  }
  foreach ($p in $c) {
    if ($p -and (Test-Path -LiteralPath (Join-Path $p 'RelicCOH.exe'))) { return (Get-Item -LiteralPath $p).FullName }
  }
  return $null
}

$game = Find-Game
while (-not $game) {
  Write-Host 'Could not find the game folder (the one containing RelicCOH.exe).'
  $p = Read-Host 'Paste the full path of that folder, or press Enter to give up'
  if (-not $p) { Write-Host 'Stopped: no game folder.'; exit 1 }
  if (Test-Path -LiteralPath (Join-Path $p 'RelicCOH.exe')) { $game = (Get-Item -LiteralPath $p).FullName }
}
Say "Game folder: $game"
$steamapps = Split-Path (Split-Path $game)      # <library>\steamapps

$docs = [Environment]::GetFolderPath('MyDocuments')
$userDir = $null
foreach ($p in @("$docs\My Games\Company of Heroes Relaunch",
                 "$env:USERPROFILE\Documents\My Games\Company of Heroes Relaunch",
                 "$env:OneDrive\Documents\My Games\Company of Heroes Relaunch")) {
  if ($p -and (Test-Path -LiteralPath $p)) { $userDir = $p; break }
}
if ($userDir) { Say "User folder: $userDir" } else { Fail 'User folder (Documents\My Games\Company of Heroes Relaunch) not found' }

$stamp = Get-Date -Format 'yyyyMMdd-HHmm'
$label = "BK-report-$env:COMPUTERNAME-$stamp"
$work = Join-Path $env:TEMP $label
if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
New-Item -ItemType Directory -Force -Path "$work\config", "$work\logs" | Out-Null

# ---------------------------------------------------------------- machine
Say 'Machine info'
Note 'report.version' '1'
Note 'report.created' (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Note 'report.createdUtc' ((Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss'))
Note 'report.timezone' ([TimeZoneInfo]::Local.Id)
Note 'computer' $env:COMPUTERNAME
Note 'user' $env:USERNAME
try {
  $os = Get-CimInstance Win32_OperatingSystem
  $cs = Get-CimInstance Win32_ComputerSystem
  $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
  Note 'os' "$($os.Caption) $($os.Version)"
  Note 'ram.gb' ([math]::Round($cs.TotalPhysicalMemory / 1GB))
  Note 'cpu' $cpu.Name.Trim()
  $i = 0
  foreach ($g in @(Get-CimInstance Win32_VideoController)) { Note "gpu.$i" "$($g.Name) driver $($g.DriverVersion)"; $i++ }
} catch { Fail "machine info: $($_.Exception.Message)" }
Note 'powershell' $PSVersionTable.PSVersion.ToString()

# ---------------------------------------------------------------- game + steam
Say 'Game and Steam info'
Note 'game.path' $game
$exe = Get-Item -LiteralPath "$game\RelicCOH.exe"
Note 'game.exe.version' $exe.VersionInfo.FileVersion
Note 'game.exe.bytes' $exe.Length
Note 'game.exe.sha256' (Get-FileHash -LiteralPath $exe.FullName -Algorithm SHA256).Hash
foreach ($dll in 'WW2Mod.dll', 'SimEngine.dll', 'ModManager.dll') {
  if (Test-Path -LiteralPath "$game\$dll") {
    $d = Get-Item -LiteralPath "$game\$dll"
    Note "game.$dll" "$($d.VersionInfo.FileVersion) $($d.Length) $((Get-FileHash -LiteralPath $d.FullName -Algorithm SHA256).Hash)"
  }
}
foreach ($app in '228200', '681590') {
  $acf = "$steamapps\appmanifest_$app.acf"
  if (Test-Path -LiteralPath $acf) {
    $t = Get-Content -LiteralPath $acf -Raw
    foreach ($k in 'name', 'buildid', 'LastUpdated', 'StateFlags') {
      $m = [regex]::Match($t, '"' + $k + '"\s+"([^"]*)"')
      if ($m.Success) { Note "steam.$app.$k" $m.Groups[1].Value }
    }
    if ($app -eq '228200') {
      $lu = $summary['steam.228200.LastUpdated']
      if ($lu) { Note 'steam.228200.LastUpdatedDate' ([DateTimeOffset]::FromUnixTimeSeconds([long]$lu).LocalDateTime.ToString('yyyy-MM-dd HH:mm')) }
    }
    CopyTo $acf "$work\config"
  } else { Note "steam.$app.appmanifest" 'missing' }
}

# Launch options from every Steam account on this PC
$launchOpts = @()
if ($steamPath -and (Test-Path -LiteralPath "$steamPath\userdata")) {
  foreach ($lc in Get-ChildItem -LiteralPath "$steamPath\userdata" -Directory -ErrorAction SilentlyContinue) {
    $f = "$($lc.FullName)\config\localconfig.vdf"
    if (-not (Test-Path -LiteralPath $f)) { continue }
    $t = Get-Content -LiteralPath $f -Raw
    foreach ($app in '228200', '681590') {
      $blk = [regex]::Match($t, '"' + $app + '"\s*\{(?:[^{}]|\{(?:[^{}]|\{[^{}]*\})*\})*\}')
      $v = '(none)'
      if ($blk.Success) {
        $m = [regex]::Match($blk.Value, '"LaunchOptions"\s+"([^"]*)"')
        if ($m.Success) { $v = $m.Groups[1].Value -replace '\\"', '"' }
      }
      Note "steam.launchoptions.$app.account$($lc.Name)" $v
      if ($app -eq '228200') { $launchOpts += $v }
    }
  }
}
if (-not ($launchOpts | Where-Object { $_ -match '-sync_high' })) { Finding 'Steam Launch Options for Company of Heroes (228200) do not contain -sync_high' }
if (-not ($launchOpts | Where-Object { $_ -match '-mod\s+Blitzkrieg' })) { Finding 'Steam Launch Options for 228200 do not contain "-mod Blitzkrieg" (fine if this player starts the mod another way)' }

# Mod module text and version hints
$mod = "$game\Blitzkrieg.module"
if (Test-Path -LiteralPath $mod) {
  $t = Get-Content -LiteralPath $mod -Raw
  foreach ($k in 'Name', 'UIName', 'ModVersion', 'Version', 'Description') {
    $m = [regex]::Match($t, '(?im)^\s*' + $k + '\s*=\s*(.+?)\s*$')
    if ($m.Success) { Note "mod.module.$k" $m.Groups[1].Value }
  }
} else { Finding 'Blitzkrieg.module not found in the game folder: the mod is not installed here' }

foreach ($n in 'RelicCOH.ini', 'Locale.ini', 'sysconfig.lua', 'spDevices.lua', 'Release_Notes.txt', 'Blitzkrieg_installation.txt') { CopyTo "$game\$n" "$work\config" }
foreach ($m in Get-ChildItem -LiteralPath $game -Filter '*.module' -File) { CopyTo $m.FullName "$work\config\modules" }

# ---------------------------------------------------------------- file manifest
Say 'Hashing files (the mod folder and the maps take the longest)'
$simArchive = '(?i)(Data|Attrib|Engine)[^\\]*\.sga$'
$rootFiles = @(Get-ChildItem -LiteralPath $game -File)
foreach ($f in $rootFiles) { AddFile 'GameRoot' $game $f ($f.Extension -match '^\.(exe|dll|module|ini|lua)$') }
Note 'count.GameRoot' $rootFiles.Count
Say "GameRoot : $($rootFiles.Count) files"
foreach ($sub in 'WW2', 'Engine', 'DLC1', 'DLC2', 'DLC3', 'CoH') {
  AddTree "Game.$sub" $game "$game\$sub" { param($f) $Full -or ($f.FullName -match $simArchive) -or ($f.Extension -match '^\.(dll|lua|module|txt|ini)$') }
}
AddTree 'Blitzkrieg' $game "$game\Blitzkrieg" { $true }
$loose = @(Get-ChildItem -LiteralPath "$game\Blitzkrieg\Data" -Recurse -File -ErrorAction SilentlyContinue)
Note 'mod.loosefiles' $loose.Count
if ($loose.Count -gt 0) {
  Finding "$($loose.Count) loose override files under Blitzkrieg\Data (must be identical on every player)"
  $lb = ($loose | Measure-Object Length -Sum).Sum
  if ($lb -lt 20MB) { Copy-Item -LiteralPath "$game\Blitzkrieg\Data" -Destination "$work\loose-Blitzkrieg-Data" -Recurse -Force } else { Note 'mod.loosefiles.notcopied' "$(MB $lb) MB, too big to include" }
}
if (Test-Path -LiteralPath "$game\WW2\Data") { Finding "loose files present under WW2\Data in the base game ($((Get-ChildItem "$game\WW2\Data" -Recurse -File | Measure-Object).Count) files)" }

if ($userDir) {
  AddTree 'Maps.Subscriptions' $userDir "$userDir\ww2\scenarios\subscriptions" { $true }
  AddTree 'Maps.Other' $userDir "$userDir\ww2\scenarios\mp" { $true }
}
AddTree 'Maps.Workshop' $steamapps "$steamapps\workshop\content\228200" { $true }

# ---------------------------------------------------------------- user folder
if ($userDir) {
  Say 'User folder'
  Note 'userdir.path' $userDir
  try {
    $it = Get-Item -LiteralPath $userDir -Force
    $isLink = (($it.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
    Note 'userdir.isjunction' $isLink
    $target = $userDir
    if ($isLink -and $it.Target) { $target = [string]($it.Target | Select-Object -First 1); Note 'userdir.target' $target }
    $inOneDrive = ($target -match '(?i)onedrive') -or ($env:OneDrive -and $target.StartsWith($env:OneDrive, 'OrdinalIgnoreCase'))
    Note 'userdir.inOneDrive' $inOneDrive
    if ($inOneDrive) { Finding 'User folder is inside OneDrive (config, cache, maps and replays are synced while playing)' }
    $online = @(Get-ChildItem -LiteralPath $userDir -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object { ($_.Attributes -band 0x400000) -or ($_.Attributes -band 0x1000) })
    Note 'userdir.onlineOnlyFiles' $online.Count
    if ($online.Count -gt 0) { Finding "$($online.Count) files in the user folder are cloud placeholders (online-only), not actually on disk" }
  } catch { Fail "user folder attributes: $($_.Exception.Message)" }
  foreach ($n in 'configuration.lua', 'playercfg.lua', 'Local.ini', 'playername-UTF16.txt') { CopyTo "$userDir\$n" "$work\config\user" }
  try { Note 'player.name' ([IO.File]::ReadAllText("$userDir\playername-UTF16.txt", [Text.Encoding]::Unicode).Trim()) } catch {}
  $cache = @(Get-ChildItem -LiteralPath "$userDir\Cache" -Recurse -File -ErrorAction SilentlyContinue)
  Note 'userdir.cache' "$($cache.Count) files, $(MB (($cache | Measure-Object Length -Sum).Sum)) MB"

  # ---- logs
  Say 'Logs'
  $logDir = "$userDir\LogFiles"
  $picked = @{}
  if (Test-Path -LiteralPath $logDir) {
    $all = Get-ChildItem -LiteralPath $logDir -File
    $cut = (Get-Date).AddDays(-$LogDays)
    foreach ($f in $all) { if ($f.LastWriteTime -gt $cut) { $picked[$f.FullName] = $f } }
    foreach ($grp in ($all | Group-Object { ($_.Name -split '\.')[0] })) {
      foreach ($f in ($grp.Group | Sort-Object LastWriteTime -Descending | Select-Object -First 3)) { $picked[$f.FullName] = $f }
    }
  }
  CopyTo "$userDir\warnings.log" "$work\logs"
  $skipped = 0
  foreach ($f in $picked.Values) { if ($f.Length -gt 25MB) { $skipped++; Note "log.skipped.$($f.Name)" "$(MB $f.Length) MB" } else { CopyTo $f.FullName "$work\logs" } }
  Note 'logs.copied' ($picked.Count - $skipped)
  $syncDumps = @(Get-ChildItem -LiteralPath $userDir -Recurse -File -Filter 'SyncError*' -ErrorAction SilentlyContinue)
  Note 'logs.syncErrorFiles' $syncDumps.Count
  if ($syncDumps.Count -gt 0) {
    Finding "$($syncDumps.Count) SyncError dump files found"
    foreach ($f in ($syncDumps | Sort-Object LastWriteTime -Descending | Select-Object -First 10)) { if ($f.Length -lt 25MB) { CopyTo $f.FullName "$work\logs\syncerror" } }
  }

  # quick read of the newest warnings logs
  $lines = New-Object System.Collections.Generic.List[string]
  $hdr = "$userDir\warnings.log"
  if (Test-Path -LiteralPath $hdr) {
    $h = Get-Content -LiteralPath $hdr -TotalCount 6
    $lines.Add('== warnings.log header (last launch) ==')
    $h | ForEach-Object { $lines.Add($_) }
    $ro = ($h | Where-Object { $_ -like 'RUN-OPTIONS*' } | Select-Object -First 1)
    if ($ro) { Note 'lastlaunch.runoptions' ($ro -replace '^RUN-OPTIONS\s*', '').Trim() }
  }
  $recent = @()
  if (Test-Path -LiteralPath $logDir) { $recent = Get-ChildItem -LiteralPath $logDir -Filter 'warnings.*.txt' -File | Sort-Object LastWriteTime -Descending | Select-Object -First 6 }
  $k = 0
  foreach ($f in $recent) {
    $k++
    $t = Get-Content -LiteralPath $f.FullName
    $mm = @($t | Select-String -Pattern 'belonging to' -SimpleMatch)
    $lines.Add('')
    $lines.Add("== $($f.Name)  ($(MB $f.Length) MB, $($t.Count) lines, mismatch lines: $($mm.Count)) ==")
    if ($mm.Count -gt 0) { $lines.Add('first mismatch: ' + $mm[0].Line.Trim()) }
    $seen = @{}
    foreach ($l in ($t | Select-String -Pattern 'Host IP Address|SyncLevel set to|sync level:|SyncErrorChecking|synclevel|GameOverDialog|PlayerDrop|disconnected|CRC & Version Info|MOD -- Mounting|SQUADAI_ALERT|Scenario:|loading map|LoadScenario|GameApp::Quit|UNHANDLED|crash')) {
      $key = $l.Line.Trim() -replace '^\d\d:\d\d:\d\d\.\d\d\s+', ''
      if ($seen.ContainsKey($key)) { continue }
      $seen[$key] = 1
      if ($seen.Count -gt 30) { $lines.Add('(more lines omitted)'); break }
      $lines.Add($l.Line.Trim())
    }
    if ($k -eq 1) {
      Note 'lastlog.name' $f.Name
      Note 'lastlog.mismatchLines' $mm.Count
      $sl = ($t | Select-String -Pattern 'SyncLevel set to|sync level:|SyncErrorChecking|synclevel' | Select-Object -First 1)
      if ($sl) { Note 'lastlog.synclevel' $sl.Line.Trim() } else { Note 'lastlog.synclevel' '(no sync level line: no match was played in that session)' }
      if ($mm.Count -gt 0) { Finding "newest game log $($f.Name) has $($mm.Count) sync-mismatch lines (that game desynced)" }
    }
  }
  $crc = Get-ChildItem -LiteralPath $logDir -Filter 'datacrc.*.txt' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($crc) {
    $lines.Add(''); $lines.Add("== $($crc.Name) ==")
    foreach ($l in (Get-Content -LiteralPath $crc.FullName | Select-String -Pattern 'Total CRC|Blueprints|Attributes \[|RandomStreamSeed|Scenario|Mod')) { $lines.Add($l.Line.Trim()) }
    Note 'lastcrc.name' $crc.Name
    $tc = (Get-Content -LiteralPath $crc.FullName | Select-String -Pattern 'Total CRC' | Select-Object -First 1)
    if ($tc) { Note 'lastcrc.total' $tc.Line.Trim() }
  }
  [IO.File]::WriteAllLines("$work\logs\log-summary.txt", [string[]]$lines, $utf8)

  # ---- replays
  if (-not $NoReplay) {
    $recs = @(Get-ChildItem -LiteralPath "$userDir\playback" -Filter '*.rec' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 3)
    foreach ($r in $recs) { if ($r.Length -lt 40MB) { CopyTo $r.FullName "$work\replay" } }
    Note 'replays.copied' $recs.Count
  }
}

# ---------------------------------------------------------------- network
Say 'Network'
try {
  $ads = @(Get-NetAdapter -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' })
  $i = 0
  foreach ($a in $ads) {
    $ip = (Get-NetIPAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | ForEach-Object { $_.IPAddress }) -join ' '
    $met = (Get-NetIPInterface -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).InterfaceMetric
    Note "net.adapter.$i" "$($a.Name) | $($a.InterfaceDescription) | ip $ip | metric $met | $($a.LinkSpeed)"
    $i++
  }
  Note 'net.adaptersUp' $ads.Count
  if ($ads.Count -gt 1) { Finding "$($ads.Count) network adapters are up (virtual/VPN adapters can confuse the game; disable them before playing)" }
  $dr = @(Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object RouteMetric)
  $i = 0
  foreach ($r in $dr) { Note "net.defaultroute.$i" "via $($r.NextHop) ifIndex $($r.ifIndex) metric $($r.RouteMetric)"; $i++ }
} catch { Fail "network: $($_.Exception.Message)" }
try {
  $od = Get-Process OneDrive -ErrorAction SilentlyContinue
  Note 'onedrive.running' ([bool]$od)
} catch {}

# ---------------------------------------------------------------- write + zip
Say 'Writing report'
$out = New-Object System.Collections.Generic.List[string]
$out.Add('# BK-collect report (key=value; "finding=" and "error=" lines may repeat)')
foreach ($k in $summary.Keys) { $out.Add("$k=$($summary[$k])") }
foreach ($f in $findings) { $out.Add("finding=$f") }
foreach ($e in $errors) { $out.Add("error=$e") }
$out.Add("report.seconds=$([int]$sw.Elapsed.TotalSeconds)")
[IO.File]::WriteAllLines("$work\summary.txt", [string[]]$out, $utf8)
[IO.File]::WriteAllLines("$work\manifest.csv", [string[]]$manifest, $utf8)

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$zip = Join-Path $OutDir "$label.zip"
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
Compress-Archive -Path "$work\*" -DestinationPath $zip -CompressionLevel Optimal
Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue

$zsize = (Get-Item -LiteralPath $zip).Length
Write-Host ''
Write-Host "Done in $([int]$sw.Elapsed.TotalSeconds) s." -ForegroundColor Green
Write-Host "Report: $zip  ($(MB $zsize) MB)" -ForegroundColor Green
if ($findings.Count -gt 0) { Write-Host ''; Write-Host 'Things noticed on this PC:'; $findings | ForEach-Object { Write-Host "  * $_" } }
if ($errors.Count -gt 0) { Write-Host ''; Write-Host 'Problems while collecting (the report is still usable):'; $errors | ForEach-Object { Write-Host "  ! $_" } }
if ($zsize -gt 10MB) { Write-Host ''; Write-Host 'The zip is over 10 MB, which Discord may refuse. Re-run with -NoReplay to leave out the replay, and send the .rec file separately.' -ForegroundColor Yellow }
Write-Host ''
Write-Host 'Send the zip to the person collecting the reports.'
