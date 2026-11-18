<#
Installs fpu-probe (version.dll) from your Downloads folder into Company of Heroes Relaunch, then
watches the probe log while you play and shows the lines that matter. When the game closes (or you
press Ctrl+C) it prints a short report and puts it, with the probe log and the game's warnings
log, in one zip on your Desktop: fpuprobe-logs-<PC name>-<date>-<time>.zip (the time the game
started). Post that zip in the group chat.

Run it in Windows PowerShell:
  powershell -ExecutionPolicy Bypass -File "$HOME\Downloads\install-and-watch.ps1"

Options:
  -Source <path>    the version.dll to install (default: the newest fpu-probe version*.dll in Downloads)
  -GamePath <dir>   the game folder (default: found through Steam)
  -NoBox            turn the mid-game alert pop-up off (creates fpu-probe.nobox; the beeps stay)
  -Box              turn the pop-up back on (removes fpu-probe.nobox)
  -WatchOnly        do not install, only watch the log (works while the game is running)
  -StopAfter <s>    stop watching after this many seconds (default: when the game closes)
  -OutDir <dir>     where the zip goes (default: your Desktop)
  -Collect          forgot to run this during the game? No install, no watching: makes the report and
                    zip from the newest probe log (collect-logs.bat does this)
  -LogFile <file>   with -Collect: use this probe log instead of the newest one
#>
param(
  [string]$Source,
  [string]$GamePath,
  [switch]$NoBox,
  [switch]$Box,
  [switch]$WatchOnly,
  [int]$StopAfter = 0,
  [string]$OutDir,
  [switch]$Collect,
  [string]$LogFile
)
$ErrorActionPreference = 'Stop'
$t0 = Get-Date
if ($Collect) { $WatchOnly = $true; $NoBox = $false; $Box = $false }
$mute = $false

function Say([string]$text, [string]$color = 'Gray') { if (-not $mute) { Write-Host $text -ForegroundColor $color } }

function Find-Downloads {
  try {
    $p = (New-Object -ComObject Shell.Application).Namespace('shell:Downloads').Self.Path
    if ($p -and (Test-Path $p)) { return $p }
  } catch {}
  return "$HOME\Downloads"
}

function Find-Game {
  $roots = @()
  try { $roots += ((Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction Stop).SteamPath -replace '/', '\') } catch {}
  $roots += "${env:ProgramFiles(x86)}\Steam"
  foreach ($r in $roots) {
    $libs = @($r)
    $vdf = "$r\steamapps\libraryfolders.vdf"
    if (Test-Path $vdf) {
      $libs += Get-Content $vdf | Select-String '"path"' | ForEach-Object { ($_.Line -split '"')[3] -replace '\\\\', '\' }
    }
    foreach ($l in $libs) {
      $g = "$l\steamapps\common\Company of Heroes Relaunch"
      if (Test-Path "$g\RelicCOH.exe") { return $g }
    }
  }
  return $null
}

function Get-ProbeVersion([string]$path) {
  if (-not (Test-Path $path)) { return $null }
  $vi = (Get-Item $path).VersionInfo
  if ($vi.FileDescription -like 'fpu-probe*') { return $vi.FileVersion }
  return $null
}

function Get-GameProcess([string]$dir) {
  Get-Process RelicCOH -ErrorAction SilentlyContinue | Where-Object { -not $dir -or -not $_.Path -or $_.Path -like "$dir\*" }
}

function Short-Hash([string]$path) { (Get-FileHash $path -Algorithm SHA256).Hash.Substring(0, 12) }

# Copies a file the game may still have open.
function Copy-Shared([string]$from, [string]$to) {
  $in = [System.IO.File]::Open($from, 'Open', 'Read', 'ReadWrite')
  try { $out = [System.IO.File]::Create($to); try { $in.CopyTo($out) } finally { $out.Close() } } finally { $in.Close() }
}

# ---------------------------------------------------------------------------------------------
# Find the game
# ---------------------------------------------------------------------------------------------
if (-not $GamePath) { $GamePath = Find-Game }
if (-not $GamePath -or -not (Test-Path "$GamePath\RelicCOH.exe")) {
  Say 'Could not find Company of Heroes Relaunch. Run the script again with the folder, for example:' Red
  Say '  powershell -ExecutionPolicy Bypass -File "$HOME\Downloads\install-and-watch.ps1" -GamePath "D:\SteamLibrary\steamapps\common\Company of Heroes Relaunch"'
  exit 1
}
Say "Game folder: $GamePath"
$target = "$GamePath\version.dll"

# ---------------------------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------------------------
if (-not $WatchOnly) {
  if (-not $Source) {
    $dl = Find-Downloads
    $Source = Get-ChildItem "$dl\version*.dll" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending |
      Where-Object { Get-ProbeVersion $_.FullName } | Select-Object -First 1 -ExpandProperty FullName
    if (-not $Source) {
      Say "No fpu-probe version.dll found in $dl. Save it there and run the script again." Red
      exit 1
    }
  }
  $newVer = Get-ProbeVersion $Source
  if (-not $newVer) { Say "$Source is not an fpu-probe DLL." Red; exit 1 }
  Unblock-File $Source

  if (Get-GameProcess $GamePath) {
    Say 'Company of Heroes is running. Close it to continue (waiting)...' Yellow
    while (Get-GameProcess $GamePath) { Start-Sleep -Seconds 2 }
  }
  if ((Test-Path $target) -and -not (Get-ProbeVersion $target)) {
    $bak = "$target.backup-$(Get-Date -Format yyyyMMdd-HHmmss)"
    Move-Item $target $bak
    Say "There was another version.dll in the game folder (not fpu-probe). It was moved to $bak" Yellow
  }
  Copy-Item $Source $target -Force
  if ((Short-Hash $Source) -ne (Short-Hash $target)) { Say 'Copy failed: the installed file differs.' Red; exit 1 }
  Say "Installed fpu-probe $newVer from $Source" Green
}

$boxFlag = "$GamePath\fpu-probe.nobox"
if ($Box) { $NoBox = $false }  # -Box wins (the .bat always passes -NoBox)
if ($NoBox -and -not (Test-Path $boxFlag)) {
  [System.IO.File]::WriteAllText($boxFlag, '')
  Say 'Created fpu-probe.nobox: no pop-up from the next game start (the alert still beeps and is logged).' Green
}
if ($Box -and (Test-Path $boxFlag)) {
  Remove-Item $boxFlag
  Say 'Removed fpu-probe.nobox: the pop-up is back on from the next game start.' Green
}

if (-not $Collect -and -not (Test-Path $target)) { Say "No version.dll in $GamePath. Run the script without -WatchOnly first." Red; exit 1 }
$st = @{
  dllVer = Get-ProbeVersion $target; hash = $(if (Test-Path $target) { Short-Hash $target } else { 'none' })
  logVer = $null; cpu = $null; cmd = $null; pin = $null; first = $null; totals = $null
  slow = 0; slowMs = 0; slowLine = $null; gapMax = 0.0; tickMax = 0.0
  fixes = 0; summary = $null; alert = $null; changed = 0; exit = $null; crash = $false; log = $null
  shownSummary = $null; shownTotals = $null; shownTotalsAt = [datetime]::MinValue
}
Say "version.dll: fpu-probe $($st.dllVer), sha256 $($st.hash) (must be the same for all four players)"
if (Test-Path "$GamePath\fpu-probe.nopin") { Say 'fpu-probe.nopin is present: pinning is OFF (logging only).' Yellow }
if (Test-Path "$GamePath\fpu-probe.nobox") { Say 'fpu-probe.nobox is present: the alert only beeps.' }

# ---------------------------------------------------------------------------------------------
# Find the log
# ---------------------------------------------------------------------------------------------
$logs = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'My Games\Company of Heroes Relaunch\LogFiles'
function Stop-Due { $StopAfter -gt 0 -and ((Get-Date) - $t0).TotalSeconds -ge $StopAfter }

$game = Get-GameProcess $GamePath | Select-Object -First 1
$log = $null
if ($Collect) {
  $log = if ($LogFile) { Get-Item $LogFile } else {
    Get-ChildItem "$logs\fpuprobe.*.txt" -ErrorAction SilentlyContinue | Sort-Object CreationTime | Select-Object -Last 1 }
  if (-not $log) { Say "No probe log in $logs. Was fpu-probe installed when the game ran?" Red; exit 1 }
  Say "Collecting $($log.FullName) (game started $($log.CreationTime.ToString('yyyy-MM-dd HH:mm')))" Cyan
  if ($game -and $log.CreationTime -ge $game.StartTime.AddSeconds(-5)) {
    Say 'The game is still running, so this log is not finished. Close the game first for the full report.' Yellow
  }
} elseif ($game) {
  $log = Get-ChildItem "$logs\fpuprobe.*.txt" -ErrorAction SilentlyContinue |
    Where-Object { $_.CreationTime -ge $game.StartTime.AddSeconds(-5) } | Sort-Object CreationTime | Select-Object -Last 1
  if (-not $log) { Say 'The game is running but has no probe log, so the DLL is not loaded. Restart the game.' Red; exit 1 }
} else {
  $old = @{}
  Get-ChildItem "$logs\fpuprobe.*.txt" -ErrorAction SilentlyContinue | ForEach-Object { $old[$_.Name] = $true }
  Say ''
  Say 'Start the game from Steam now (same launch options as the other players). Waiting for its log...' Cyan
  while (-not $log) {
    if (Stop-Due) { Say 'Stopped: no log appeared.' Yellow; exit 1 }
    Start-Sleep -Seconds 1
    $log = Get-ChildItem "$logs\fpuprobe.*.txt" -ErrorAction SilentlyContinue |
      Where-Object { -not $old.ContainsKey($_.Name) } | Sort-Object CreationTime | Select-Object -Last 1
  }
}
$st.log = $log.FullName
if (-not $Collect) {
Say "Watching $($log.FullName)" Cyan
Say 'Start a match. Leave this window open; it stops when the game closes (or press Ctrl+C).' Cyan
Say ''
}

# ---------------------------------------------------------------------------------------------
# Watch
# ---------------------------------------------------------------------------------------------
function Handle-Line([string]$line) {
  if ($line -notmatch '^[\d:.]+\s+[+-][\d.]+\s+(.*)$') { return }
  $b = $Matches[1]
  if ($b -match '^fpu-probe (\S+) started') { $st.logVer = $Matches[1]; Say $line Green; return }
  if ($b -like 'INFO cpu:*') { $st.cpu = $b.Substring(10); Say $line; return }
  if ($b -like 'INFO command line:*') { $st.cmd = $b.Substring(19); Say $line; return }
  if ($b -like 'INFO windows:*') { Say $line; return }
  if ($b -like 'PIN  on:*') { $st.pin = $b; Say $line Green; return }
  if ($b -like 'PIN  off*' -or $b -like 'PIN  FAILED*' -or $b -like 'PIN  waiting*') { $st.pin = $b; Say $line Yellow; return }
  if ($b -like 'PIN  first tick*') {
    $st.first = $b.Substring(16)
    Say $line Cyan
    Say '      ^ compare this line with the other players' Cyan
    return
  }
  if ($b -match '^PIN  (before|after )') { $st.fixes++; Say $line Yellow; return }
  if ($b -like 'PIN  tick now on*') { Say $line Yellow; return }
  if ($b -match '^PIN  slow tick \d+: (started|took) (\d+) ms') {
    $st.slow++
    if ([int]$Matches[2] -gt $st.slowMs) { $st.slowMs = [int]$Matches[2]; $st.slowLine = $line }
    Say $line Yellow
    return
  }
  if ($b -like 'PIN  ticks=*') {
    $parts = $b.Substring(5) -split '; ', 2
    $st.totals = $parts[0]
    if ($parts.Count -gt 1 -and $parts[1] -match 'tick ms avg=[\d.]+ max=([\d.]+), gap ms max=([\d.]+)') {
      $t = [double]$Matches[1]; $g = [double]$Matches[2]
      if ($t -gt $st.tickMax) { $st.tickMax = $t }
      if ($g -gt $st.gapMax) { $st.gapMax = $g }
    }
    $fixPart = ($st.totals -replace ' sim tid=.*', '' -replace '^ticks=\d+ ', '')
    if ($fixPart -ne $st.shownTotals -or ((Get-Date) - $st.shownTotalsAt).TotalSeconds -ge 60) {
      $st.shownTotals = $fixPart; $st.shownTotalsAt = Get-Date
      Say $line $(if ($fixPart -eq 'fixed before=0 after=0') { 'Green' } else { 'Yellow' })
    }
    return
  }
  if ($b -match 'SUMMARY .* cw/mx: (.*)$') {
    $st.summary = $Matches[1]
    if ($st.summary -ne $st.shownSummary) { $st.shownSummary = $st.summary; Say $line }
    return
  }
  if ($b -like '*CHANGED was*') { $st.changed++; Say $line Yellow; return }
  if ($b -like 'ALERT first mismatch*') { $st.alert = $b.Substring(6); Say $line Red; return }
  if ($b -like 'ALERT*') { Say $line Red; return }
  if ($b -like 'MODULE+*' -or $b -like 'MODULE-*' -or $b -like 'WATCH*') { Say $line DarkGray; return }
  if ($b -like 'EXIT*') { $st.exit = $b; Say $line; return }
}

function Write-Report {
  $ok = { param($good, $text) if ($good) { "  [ok] $text" } else { "  [!!] $text" } }
  $r = @(
    "=== fpu-probe report: $env:COMPUTERNAME, $(Get-Date -Format 'yyyy-MM-dd HH:mm') ==="
    "probe:        $($st.dllVer) (sha256 $($st.hash))"
    "cpu:          $($st.cpu)"
    "command line: $($st.cmd)"
    "pin:          $($st.pin)"
    "first tick:   $(if ($st.first) { $st.first } else { 'none (no match was played?)' })"
    "pin totals:   $($st.totals)"
    "tick timing:  longest gap between ticks $($st.gapMax) ms, longest tick $($st.tickMax) ms, $($st.slow) slow-tick lines"
    "slowest:      $(if ($st.slowLine) { $st.slowLine } else { 'none (no gap of 1 s or more, no tick of 250 ms or more)' })"
    "last summary: $($st.summary)"
    "CHANGED:      $($st.changed) lines"
    "mismatch:     $(if ($st.alert) { $st.alert } else { 'none' })"
    "end:          $(if ($st.exit) { $st.exit } elseif ($st.crash) { 'game closed without an EXIT line (crash?)' } else { 'still running when the watch stopped' })"
    "log:          $($st.log)"
    'checks:'
    (& $ok ($st.dllVer -eq '2.2' -and $st.logVer -eq '2.2') "fpu-probe 2.2 installed and loaded (installed $($st.dllVer), log $($st.logVer))")
    (& $ok ($st.pin -like 'PIN  on:*') 'pinning on')
    (& $ok ([bool]$st.first) 'first sim tick seen')
    (& $ok ($st.totals -match '^ticks=(\d+)' -and [int]$Matches[1] -ge 100) 'pin ran on every tick (ticks= counts up during a match)')
    (& $ok ($st.fixes -eq 0 -and $st.totals -notmatch 'before=[1-9]|after=[1-9]') 'no PIN corrections (any correction: note it)')
    (& $ok (-not $st.alert) 'no lockstep mismatch line')
  )
  $text = ($r -join "`r`n") + "`r`n"
  Say ''
  foreach ($l in $r) { Say $l $(if ($l.Contains('[!!]')) { 'Yellow' } elseif ($l.Contains('[ok]')) { 'Green' } else { 'White' }) }
  # Zip the report, the probe log and the game's warnings log of this session into one file to post.
  # The report goes only into the zip; it is left on the Desktop only if zipping fails.
  $out = if ($OutDir) { $OutDir } else { [Environment]::GetFolderPath('Desktop') }
  $name = "fpuprobe-report-$env:COMPUTERNAME.txt"
  $oldReport = Join-Path $out $name
  if (Test-Path $oldReport) { Remove-Item $oldReport }  # left there by fpu-probe 2.1 and earlier
  $started = if ($st.log) { (Get-Item $st.log).CreationTime } else { $t0 }
  $zip = Join-Path $out "fpuprobe-logs-$env:COMPUTERNAME-$($started.ToString('yyyyMMdd-HHmm')).zip"
  $tmp = Join-Path $env:TEMP 'fpuprobe-send'
  try {
    if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
    New-Item -ItemType Directory -Force $tmp | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $tmp $name), $text)
    $files = @()
    if ($st.log) {
      $files += $st.log
      # The warnings log of the same game: written to after the probe log started, created closest to it.
      $born = (Get-Item $st.log).CreationTime
      $w = Get-ChildItem (Join-Path (Split-Path $st.log) 'warnings.*.txt') -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $born.AddMinutes(-1) } |
        Sort-Object { [math]::Abs(($_.CreationTime - $born).TotalSeconds) } | Select-Object -First 1
      if ($w) { $files += $w.FullName }
    }
    foreach ($f in $files) { Copy-Shared $f (Join-Path $tmp (Split-Path $f -Leaf)) }
    Compress-Archive -Path "$tmp\*" -DestinationPath $zip -Force
    Remove-Item -Recurse -Force $tmp
    Say ''
    Say "Post this one file in the group chat: $zip (the report is inside it)" Cyan
  } catch {
    [System.IO.File]::WriteAllText($oldReport, $text)
    Say "Could not zip the logs ($_). Post $oldReport and $($st.log) instead." Yellow
  }
}

if ($Collect) {
  # Read the finished log in one go, show only the report.
  $mute = $true
  try { Get-Content $log.FullName | ForEach-Object { Handle-Line $_ } } finally { $mute = $false }
  $live = $game -and $log.CreationTime -ge $game.StartTime.AddSeconds(-5)
  if (-not $st.exit -and -not $live) { $st.crash = $true }
  Write-Report
  exit 0
}

$fs = [System.IO.File]::Open($log.FullName, 'Open', 'Read', 'ReadWrite')
$rd = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8)
$pending = ''
$goneSince = $null
try {
  while ($true) {
    $chunk = $rd.ReadToEnd()
    if ($chunk) {
      $parts = ($pending + $chunk) -split "`r?`n"
      $pending = $parts[-1]
      for ($i = 0; $i -lt $parts.Count - 1; $i++) { Handle-Line $parts[$i] }
    }
    if ($st.exit -or (Stop-Due)) { break }
    if (Get-GameProcess $GamePath) { $goneSince = $null }
    elseif (-not $goneSince) { $goneSince = Get-Date }
    elseif (((Get-Date) - $goneSince).TotalSeconds -gt 5) { $st.crash = $true; break }
    Start-Sleep -Seconds 1
  }
} finally {
  $rd.Close()
  Write-Report
}
