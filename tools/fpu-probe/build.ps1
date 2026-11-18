# Builds build\version.dll (the probe) and build\test\probe-test.exe with Visual Studio Build Tools.
# Usage:  powershell -ExecutionPolicy Bypass -File .\build.ps1 [-Test]
param([switch]$Test)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) { throw 'Visual Studio Build Tools not found (no vswhere.exe).' }
$vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vs) { throw 'No Visual Studio install with the C++ x86/x64 tools found.' }
$vcvars = Join-Path $vs 'VC\Auxiliary\Build\vcvars32.bat'
$env:PATH = "$(Split-Path $vswhere);$env:PATH"   # vcvars32.bat calls vswhere itself

New-Item -ItemType Directory -Force "$root\build\obj", "$root\build\test" | Out-Null
$cmd = "call `"$vcvars`" >nul" +
  " && rc /nologo /fo build\obj\probe.res src\probe.rc" +
  " && cl /nologo /O2 /MT /W4 /EHsc /LD /Fobuild\obj\ src\probe.cpp build\obj\probe.res" +
  " /link /DEF:src\version.def /OUT:build\version.dll /IMPLIB:build\obj\probe-imp.lib user32.lib" +
  " && cl /nologo /O2 /MT /W4 /EHsc /LD /Fobuild\obj\ /Febuild\test\SimEngine.dll test\SimEngine.cpp" +
  " /link /IMPLIB:build\obj\SimEngine.lib" +
  " && cl /nologo /O2 /MT /W4 /EHsc /Fobuild\obj\ /Febuild\test\probe-test.exe test\probe-test.cpp" +
  " build\obj\SimEngine.lib"
Push-Location $root
try {
  cmd /c $cmd
  if ($LASTEXITCODE -ne 0) { throw "Build failed (exit $LASTEXITCODE)." }
} finally { Pop-Location }
Copy-Item "$root\build\version.dll" "$root\build\test\version.dll" -Force
Write-Host "Built $root\build\version.dll"

if ($Test) {
  $logDir = "$root\build\test\logs"
  if (Test-Path $logDir) { Remove-Item -Recurse -Force $logDir }
  New-Item -ItemType Directory -Force $logDir | Out-Null
  $env:FPU_PROBE_FORCE = '1'; $env:FPU_PROBE_LOGDIR = $logDir
  $env:FPU_PROBE_NOBOX = '1'; $env:FPU_PROBE_INTERVAL = '1000'
  & "$root\build\test\probe-test.exe" $logDir
  $code = $LASTEXITCODE
  $env:FPU_PROBE_NOPIN = '1'; $env:FPU_PROBE_LOGDIR = "$logDir\nopin"
  New-Item -ItemType Directory -Force "$logDir\nopin" | Out-Null
  & "$root\build\test\probe-test.exe" "$logDir\nopin" nopin
  $codeNoPin = $LASTEXITCODE
  Remove-Item Env:FPU_PROBE_NOPIN
  Remove-Item Env:FPU_PROBE_FORCE, Env:FPU_PROBE_LOGDIR, Env:FPU_PROBE_NOBOX, Env:FPU_PROBE_INTERVAL
  $log = Get-ChildItem "$logDir\fpuprobe.*.txt" | Select-Object -First 1
  if (-not $log) { throw 'Test failed: no fpuprobe log written.' }
  $text = Get-Content $log.FullName -Raw
  $checks = [ordered]@{
    'x87 pc24 thread seen'   = $text -match 'pc24'
    'SSE ftz,daz thread seen' = $text -match 'ftz,daz'
    'mid-run change flagged' = $text -match 'CHANGED was cw='
    'alert fired'            = $text -match 'ALERT first mismatch line'
    'pin hook installed'     = $text -match 'PIN  on:'
    'pin fixed before tick'  = $text -match 'PIN  before tick 1: fixed cw=027F'
    'pin fixed after tick'   = $text -match 'PIN  after  tick 1: fixed cw=037F'
    'pin counters logged'    = $text -match 'PIN  ticks=5 fixed before=1 after=5'
    'slow tick logged'       = $text -match 'PIN  slow tick 5: started 1\d{3} ms after tick 4'
    'tick timing logged'     = $text -match 'PIN  ticks=5 fixed .*; last [\d.]+ s: \+\d+ ticks, tick ms avg=[\d.]+ max=[\d.]+, gap ms max=1\d{3}, slow=1'
    'nopin switch works'     = ($codeNoPin -eq 0) -and ((Get-Content "$logDir\nopin\fpuprobe.*.txt" -Raw) -match 'PIN  off')
  }
  $fail = 0
  foreach ($k in $checks.Keys) { if ($checks[$k]) { "PASS $k" } else { "FAIL $k"; $fail++ } }
  "Log: $($log.FullName)"
  if ($code -ne 0 -or $fail -gt 0) { throw "Test failed (exit $code, $fail checks failed)." }
}
