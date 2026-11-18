# BK-compare.ps1 - consolidate BK-collect report zips and write a markdown comparison.
# Windows PowerShell 5.1. Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\BK-collect\BK-compare.ps1   (default -ReportDir: <repo>\reports)
param(
  [string]$ReportDir = (Join-Path (Split-Path (Split-Path $PSScriptRoot)) 'reports'),
  [string]$Out = ''
)
$ErrorActionPreference = 'Stop'
if (-not $Out) { $Out = Join-Path $ReportDir 'BK-compare-report.md' }
$utf8 = New-Object System.Text.UTF8Encoding($false)

$zips = @(Get-ChildItem -LiteralPath $ReportDir -Filter 'BK-report-*.zip' -File | Sort-Object Name)
if ($zips.Count -eq 0) { throw "No BK-report-*.zip in $ReportDir" }

# --- load every report ------------------------------------------------------
$players = @()
foreach ($z in $zips) {
  $dir = Join-Path $ReportDir ("extracted\" + [IO.Path]::GetFileNameWithoutExtension($z.Name))
  if (Test-Path $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }
  Expand-Archive -LiteralPath $z.FullName -DestinationPath $dir -Force
  $sumFile = Get-ChildItem -LiteralPath $dir -Filter summary.txt -Recurse | Select-Object -First 1
  $manFile = Get-ChildItem -LiteralPath $dir -Filter manifest.csv -Recurse | Select-Object -First 1
  if (-not $sumFile -or -not $manFile) { Write-Warning "$($z.Name): summary.txt or manifest.csv missing, skipped"; continue }
  $sum = [ordered]@{}; $findings = @(); $errs = @()
  foreach ($line in Get-Content -LiteralPath $sumFile.FullName) {
    if ($line -match '^\s*#' -or $line -notmatch '=') { continue }
    $k, $v = $line -split '=', 2
    if ($k -eq 'finding') { $findings += $v } elseif ($k -eq 'error') { $errs += $v } else { $sum[$k] = $v }
  }
  $label = if ($sum['computer']) { $sum['computer'] } else { $z.BaseName }
  if ($sum['player.name']) { $label += ' (' + $sum['player.name'] + ')' }
  $man = @{}
  foreach ($r in Import-Csv -LiteralPath $manFile.FullName) { $man[$r.Group + '|' + $r.RelativePath] = $r }
  $players += [pscustomobject]@{ Zip = $z.Name; Label = $label; Summary = $sum; Findings = $findings; Errors = $errs; Manifest = $man; Dir = $dir }
}
if ($players.Count -eq 0) { throw 'No usable reports.' }

$md = New-Object System.Collections.Generic.List[string]
$md.Add("# BK-compare report")
$md.Add("")
$md.Add("Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm') from $($players.Count) report(s) in ``$ReportDir``.")
$md.Add("")
$md.Add("| # | Player | Zip | Report created (UTC) |")
$md.Add("|---|---|---|---|")
$i = 0
foreach ($p in $players) { $i++; $md.Add("| $i | $($p.Label) | $($p.Zip) | $($p.Summary['report.createdUtc']) |") }

# --- 1. summary fields side by side -----------------------------------------
$keys = @(
  'game.exe.bytes','game.exe.sha256','game.WW2Mod.dll','game.SimEngine.dll','game.ModManager.dll',
  'steam.228200.buildid','steam.228200.LastUpdatedDate','steam.681590.buildid','steam.681590.LastUpdated',
  'mod.module.ModVersion','mod.loosefiles',
  'count.Blitzkrieg','mb.Blitzkrieg','count.Game.WW2','mb.Game.WW2','count.Game.Engine','mb.Game.Engine',
  'count.Maps.Subscriptions','mb.Maps.Subscriptions','count.Maps.Other','count.Maps.Workshop','missing.Maps.Other','missing.Maps.Workshop',
  'userdir.inOneDrive','userdir.isjunction','userdir.onlineOnlyFiles',
  'lastcrc.total','lastlog.name','lastlog.synclevel','lastlog.mismatchLines','logs.syncErrorFiles','lastlaunch.runoptions',
  'net.adaptersUp','onedrive.running','os','ram.gb','gpu.0','report.timezone','report.version','report.seconds')
$launchKeys = @($players | ForEach-Object { $_.Summary.Keys } | Where-Object { $_ -like 'steam.launchoptions.*' } | Sort-Object -Unique)
$keys = @($keys[0..8]) + $launchKeys + @($keys[9..($keys.Count-1)])

$md.Add(""); $md.Add("## 1. Key values per player"); $md.Add("")
$md.Add("Rows marked **DIFF** have more than one distinct value. Blank = key absent in that report.")
$md.Add("")
$hdr = "| Key | " + (($players | ForEach-Object { $_.Label }) -join ' | ') + " | Same? |"
$md.Add($hdr); $md.Add("|---|" + ("---|" * $players.Count) + "---|")
$diffKeys = 0
foreach ($k in $keys) {
  $absent = '(absent)'
  $vals = @($players | ForEach-Object { $v = $_.Summary[$k]; if ($null -eq $v) { $absent } else { "$v" } })
  $present = @($vals | Where-Object { $_ -ne $absent })
  if ($present.Count -eq 0) { continue }
  $distinct = @($present | Sort-Object -Unique)
  $same = if ($distinct.Count -gt 1) { $diffKeys++; '**DIFF**' } elseif ($present.Count -eq $players.Count) { 'yes' } else { 'partly (absent on some)' }
  $cells = $vals | ForEach-Object { if ($_ -eq $absent) { '' } else { ($_ -replace '\|', '\|') } }
  $md.Add("| $k | " + ($cells -join ' | ') + " | $same |")
}

# --- 2. manifest differences per group --------------------------------------
$md.Add(""); $md.Add("## 2. File differences"); $md.Add("")
$md.Add("Per group: files identical on every player, and every file that is missing somewhere or differs in SHA256 or size.")
$md.Add("Groups Game.WW2/Engine/DLC hash only sim-relevant archives unless BK-collect ran with -Full; other rows compare by size.")
$md.Add("")
$allKeys = @($players | ForEach-Object { $_.Manifest.Keys } | Sort-Object -Unique)
$groups = @($allKeys | ForEach-Object { ($_ -split '\|', 2)[0] } | Sort-Object -Unique)
$totalDiff = 0
foreach ($g in $groups) {
  $gk = @($allKeys | Where-Object { $_ -like "$g|*" })
  $rows = @(); $identical = 0
  foreach ($key in $gk) {
    $rel = ($key -split '\|', 2)[1]
    $entries = @($players | ForEach-Object { $_.Manifest[$key] })
    $missing = @(); $sigs = @()
    for ($n = 0; $n -lt $players.Count; $n++) {
      $e = $entries[$n]
      if ($null -eq $e) { $missing += $players[$n].Label; $sigs += $null; continue }
      $sigs += $(if ($e.SHA256) { 'sha:' + $e.SHA256 } else { 'size:' + $e.Bytes })
    }
    $present = @($sigs | Where-Object { $_ })
    $distinct = @($present | Sort-Object -Unique)
    $bySize = @($entries | Where-Object { $_ } | ForEach-Object { $_.Bytes } | Sort-Object -Unique)
    if ($missing.Count -eq 0 -and $distinct.Count -le 1 -and $bySize.Count -le 1) { $identical++; continue }
    $why = @()
    if ($missing.Count -gt 0) { $why += 'missing on: ' + ($missing -join ', ') }
    if ($bySize.Count -gt 1) { $why += 'size differs' }
    elseif ($distinct.Count -gt 1) { $why += 'hash differs' }
    $detail = @()
    for ($n = 0; $n -lt $players.Count; $n++) {
      $e = $entries[$n]
      if ($null -eq $e) { $detail += '-' ; continue }
      $h = if ($e.SHA256) { $e.SHA256.Substring(0, 8) } else { 'nohash' }
      $detail += "$($e.Bytes) B / $h / $($e.LastWriteUtc)"
    }
    $rows += "| $rel | $($why -join '; ') | " + ($detail -join ' | ') + " |"
  }
  $totalDiff += $rows.Count
  $md.Add("### $g  (identical: $identical, different or missing: $($rows.Count))"); $md.Add("")
  if ($rows.Count -gt 0) {
    $md.Add("| File | Problem | " + (($players | ForEach-Object { $_.Label }) -join ' | ') + " |")
    $md.Add("|---|---|" + ("---|" * $players.Count))
    $rows | Select-Object -First 200 | ForEach-Object { $md.Add($_) }
    if ($rows.Count -gt 200) { $md.Add("| ... | $($rows.Count - 200) more rows omitted | |") }
    $md.Add("")
  }
}

# --- 3. findings and errors per player --------------------------------------
$md.Add("## 3. Findings and errors reported by each collector run"); $md.Add("")
foreach ($p in $players) {
  $md.Add("### $($p.Label)"); $md.Add("")
  if ($p.Findings.Count -eq 0 -and $p.Errors.Count -eq 0) { $md.Add("none"); $md.Add(""); continue }
  foreach ($f in $p.Findings) { $md.Add("- finding: $f") }
  foreach ($e in $p.Errors) { $md.Add("- ERROR: $e") }
  $md.Add("")
}
$md.Add("## 4. Where the raw files are"); $md.Add("")
foreach ($p in $players) { $md.Add("- $($p.Label): ``$($p.Dir)`` (logs\log-summary.txt, logs\*.txt, config\, replay\)") }

[IO.File]::WriteAllText($Out, ($md -join "`r`n") + "`r`n", $utf8)
Write-Host "Players: $($players.Count)   keys with differences: $diffKeys   files different or missing: $totalDiff"
Write-Host "Report: $Out"
