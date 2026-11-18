# fpu-probe: floating-point settings logger and pin for Company of Heroes

A diagnostic and a candidate fix for the Blitzkrieg desyncs (see
`..\..\CoH-Blitzkrieg-determinism-audit.md`, option 3). Version 2.2 logs, as 1.0 did, and also
**pins** the floating-point settings of the simulation at the start of every tick (see Pinning
below). It does not patch the exe or any game file on disk.

**All four players must run the same version with the same pin setting.** If one player pins and
another does not, the game can desync because of that alone.

## What it is

`version.dll`, a 32-bit proxy DLL. `RelicCOH.exe` imports `VERSION.dll`, and Windows loads a copy
in the game folder before the one in `C:\Windows\SysWOW64`. The probe passes every call on to the
real system `version.dll`, so the game works as normal. Inside `RelicCOH.exe` it also starts one
background thread that:

- every 5 seconds reads the **x87 control word** (`cw`) and **MXCSR** (`mx`) of every game thread
  and writes them to the log, with the time, thread id, where the thread was (`at=`) and where it
  started (`start=`). If a thread's setting differs from its previous reading, the line ends in
  `CHANGED was ...`;
- logs every DLL that loads or unloads (`MODULE+` / `MODULE-`), so overlays and hooks (Steam,
  Discord, recording tools) show up with the time they arrived;
- watches the newest `warnings.*.txt` and, at the first `*** Squad command ... sent from` line
  (the first lockstep mismatch), takes an extra reading tagged `ALERT`, beeps three times and
  shows a message box.

Other programs in the game folder (launcher, WorldBuilder) get plain forwarding with no logging.

## Pinning (2.1)

`World::Simulate` in `SimEngine.dll` runs once per simulation tick. When the game starts, the
probe puts a jump at the start of that function, in memory only, so each tick goes through a small
stub. The stub:

- sets the x87 control word to `007F` (24-bit precision, round to nearest, exceptions masked) and
  MXCSR to `1F80` (round to nearest, no flush-to-zero) if they are anything else, runs the real
  tick, then checks and resets them again. These are the values the game's own code sets on its
  main and worker threads;
- counts each correction: `before` = the setting was wrong when a tick started, `after` = it was
  changed during the tick.

So whatever an overlay, driver or other DLL does to the simulation thread, every PC starts every
tick with the same settings. Worker threads are logged but not changed.

Before it writes the jump, the probe checks that the function starts with the five bytes it
expects (`51 53 56 8B F1`). If a game update changes them, it logs `PIN  FAILED` and only logs.

**2.0 did not pin each tick.** It wrapped `World::SimulatePre` / `SimulatePost` in the exe's import
table, but the exe calls those only once per game, so 2.0 logs show `ticks=1` for a whole match.
In a 2.1 log, `ticks=` grows by several per second during a match.

Log lines:

- `PIN  on: ...` once at start: the hook is in. `PIN  FAILED` or `PIN  off` means no pinning.
- `PIN  first tick on tid=... game had cw=... mx=...`: the first tick of the session and what the
  game had at that moment. Compare this line between the four players.
- `PIN  before tick N: fixed cw=... -> ...` or `PIN  after  tick N: ...`: a correction. The first
  20 of each kind are logged, then every 1000th.
- `PIN  ticks=... fixed before=... after=...`: running totals, after each SCAN while ticks advance.
  During a match `ticks=` must keep growing. If it stays at 1, the pin is not running each tick.
  Since 2.2 the line also has tick timing for the time since the previous one (see below).
- `PIN  slow tick N: started X ms after tick N-1` or `PIN  slow tick N: took X ms`: a stall (2.2).
  The first 50 are logged, then every 100th.

### Tick timing (2.2)

The same hook times every sim tick. The game runs 8 ticks a second, so ticks start about 125 ms apart.
Each `PIN  ticks=` line ends with, for the time since the previous `PIN  ticks=` line:

```
; last 5.1 s: +41 ticks, tick ms avg=12.3 max=40.1, gap ms max=180, slow=0
```

- `+41 ticks`: ticks run in that time. About 8 a second is normal.
- `tick ms avg / max`: how long `World::Simulate` took. A tick over 125 ms means this PC's sim
  cannot keep up; 250 ms or more gets a `slow tick ... took` line.
- `gap ms max`: the longest time from one tick's start to the next. A gap of 1 s or more gets a
  `slow tick ... started` line. All PCs show the same gap when the game waits for one PC (lockstep);
  only one PC showing it means that PC stalled.
- A game pause, and the time between two matches in one session, also show as one long gap.

A delay between a click and units acting with no long gap and +8 ticks a second is not a sim stall;
look at that unit (pathfinding, busy) instead. Timing needs the hook, so `fpu-probe.nopin` turns it off.

The main menu runs no ticks, so `ticks=0` there is normal. Ticks start when a match starts.

To turn pinning off and keep only the logging, create an empty flag file (all four players together):

```powershell
New-Item -ItemType File "$game\fpu-probe.nopin" | Out-Null
```

To turn it back on:

```powershell
Remove-Item "$game\fpu-probe.nopin"
```

The log goes next to the game's own logs:
`Documents\My Games\Company of Heroes Relaunch\LogFiles\fpuprobe.<date>.<time>.txt`

## Install the easy way: install-and-watch.bat

Download `fpu-probe-2.2.zip` from the repo's
[Releases page](https://github.com/gizmo2222/coh-blitzkrieg-desync/releases) and extract it anywhere (Downloads is fine). Its files are in an
`fpu-probe-2.2` folder; open it and double-click `install-and-watch.bat`. It runs `install-and-watch.ps1` from the same folder and installs the
`version.dll` that sits next to it. It also turns the mid-game alert pop-up off (it creates
`fpu-probe.nobox`; the alert still beeps and is logged). To get the pop-up back, run
`install-and-watch.bat -Box` from a command prompt in that folder. If Windows shows "Windows protected your PC", click
**More info**, then **Run anyway**. The window stays open at the end so you can read the report.
If you press Ctrl+C and Windows asks `Terminate batch job (Y/N)?`, answer `N`, so the window
stays open with the report. The report and zip are written either way.

Or, without the batch file: save `version.dll` and `install-and-watch.ps1` to your Downloads
folder. Then, in Windows PowerShell:

```powershell
Unblock-File "$HOME\Downloads\install-and-watch.ps1"
```

```powershell
powershell -ExecutionPolicy Bypass -File "$HOME\Downloads\install-and-watch.ps1"
```

The script:

1. finds the game through Steam, and the newest fpu-probe `version*.dll` in Downloads (so a
   browser copy named `version (1).dll` works too);
2. waits for you to close the game if it is running, moves any other `version.dll` aside as
   `version.dll.backup-<date>`, copies the probe in and checks the copy;
3. prints the version and a short sha256. **All four players must show the same hash**;
4. tells you to start the game, then shows the important log lines as they arrive: `PIN  on:`,
   the `PIN  first tick` line (marked "compare this line"), any correction, `CHANGED` and `ALERT`;
5. when the game closes (or you press Ctrl+C), prints a report with checks and zips it, with the
   probe log and the game's `warnings.*.txt` of that session, to your Desktop as
   `fpuprobe-logs-<PC name>-<yyyyMMdd-HHmm>.zip` (the date and time the game started). The report
   is only inside the zip; an old `fpuprobe-report-<PC name>.txt` from 2.1 is removed from the
   Desktop. Post that one zip in the group chat. (With the script you can skip "After the test
   game" below; the zip already holds those files.)

Leave the window open while you play. Options: `-WatchOnly` (no install, also attaches to a game
that is already running), `-Source <file>`, `-GamePath <folder>`, `-StopAfter <seconds>`,
`-NoBox` / `-Box` (pop-up off / on; the .bat always passes `-NoBox`, and `-Box` wins),
`-OutDir <folder>` (where the zip goes instead of the Desktop), `-Collect` and `-LogFile <file>`
(report and zip after the game; see "After the test game").
A `[!!]` in the report is not an error in itself; it marks the line to compare with the others.

## Install by hand (each of the four players)

1. Get `version.dll` from the group (built from this folder, see Build below) and put it in your
   Downloads folder.
2. Close Company of Heroes. Then, in Windows PowerShell, find your game folder and copy the file in.
   Steam can be in another library on your PC, so this asks Steam where the game is:

```powershell
$lib = Get-Content "${env:ProgramFiles(x86)}\Steam\steamapps\libraryfolders.vdf" | Select-String '"path"' | ForEach-Object { ($_ -split '"')[3] -replace '\\\\','\' } | Where-Object { Test-Path "$_\steamapps\common\Company of Heroes Relaunch\RelicCOH.exe" } | Select-Object -First 1; $game = "$lib\steamapps\common\Company of Heroes Relaunch"; $game
```

```powershell
Unblock-File "$HOME\Downloads\version.dll"; Copy-Item "$HOME\Downloads\version.dll" "$game\version.dll"; Get-Item "$game\version.dll" | Select-Object Name, Length, LastWriteTime
```

If the first command prints nothing, set the path yourself, for example
`$game = 'D:\SteamLibrary\steamapps\common\Company of Heroes Relaunch'`.

3. Start the game from Steam as usual (launch options `-mod Blitzkrieg ...`). Within a few seconds of
   the main menu, check that the log is filling in:

```powershell
$logs = "$([Environment]::GetFolderPath('MyDocuments'))\My Games\Company of Heroes Relaunch\LogFiles"; Get-ChildItem "$logs\fpuprobe.*.txt" | Sort-Object LastWriteTime | Select-Object -Last 1 | ForEach-Object { $_.Name; Get-Content $_.FullName | Select-String 'SUMMARY' | Select-Object -Last 1 }
```

You should see a line like `SCAN #12 SUMMARY threads=40 changed=0 cw/mx: 007F/1F80 x2, 027F/1F80 x38`.
Then check that pinning is on:

```powershell
Get-ChildItem "$logs\fpuprobe.*.txt" | Sort-Object LastWriteTime | Select-Object -Last 1 | ForEach-Object { Get-Content $_.FullName | Select-String 'PIN ' | Select-Object -First 3 }
```

The first line should start with `PIN  on:`. Once a match has started, a `PIN  first tick` line follows.

### The alert

When the first mismatch line appears you hear three beeps and a message box opens. If you play in
exclusive fullscreen the box may be behind the game or the game may minimize: press OK and Alt+Tab
back. The game itself is not affected. `install-and-watch.bat` turns the box off for you. By hand,
create an empty flag file to get only the beeps:

```powershell
New-Item -ItemType File "$game\fpu-probe.nobox" | Out-Null
```

and delete it to get the box back:

```powershell
Remove-Item "$game\fpu-probe.nobox"
```

## After the test game

Each player sends the newest `fpuprobe.*.txt` and the matching `warnings.*.txt`. If
install-and-watch was not running during the game, double-click `collect-logs.bat` (in the same
zip) after the game, before starting the game again. It installs nothing; it reads the newest probe log, prints the
same report and makes the same dated zip on the Desktop. For an older game:

```powershell
.\collect-logs.bat -LogFile "$([Environment]::GetFolderPath('MyDocuments'))\My Games\Company of Heroes Relaunch\LogFiles\fpuprobe.2026-11-13.22-00-08.txt"
```

The report's "installed" version is whatever is in the game folder now, so it can differ from the
log's if the probe was updated since. Without the script:

```powershell
$logs = "$([Environment]::GetFolderPath('MyDocuments'))\My Games\Company of Heroes Relaunch\LogFiles"; $out = "$HOME\Desktop\fpuprobe-logs-$env:COMPUTERNAME-$(Get-Date -Format yyyyMMdd-HHmm).zip"; $files = @(Get-ChildItem "$logs\fpuprobe.*.txt" | Sort-Object LastWriteTime | Select-Object -Last 1) + @(Get-ChildItem "$logs\warnings.*.txt" | Sort-Object LastWriteTime | Select-Object -Last 1); Compress-Archive -Path $files.FullName -DestinationPath $out -Force; $out
```

What to compare:

- Did the game desync? With pinning on, that is the main result.
- `PIN  first tick` line: the same `cw`/`mx` on all four PCs? A PC that differs is the suspect, and
  the pin corrected it.
- `PIN` correction lines: a PC with corrections had something changing the simulation thread's
  settings. Note the time and any `MODULE+` line just before it.
- `INFO cpu:` line: Intel vs AMD per PC. If games still desync with pinning on and no corrections,
  the cause is not the x87/SSE settings of the simulation thread (for example a CPU difference in
  a math library).
- `SUMMARY` lines: the set of `cw/mx` pairs should be the same on all four PCs and should not change
  during the game. Any `CHANGED` line is the main thing to look for: note the time, the thread
  (`tid`, `start=`) and any `MODULE+` line just before it.
- `pc24` vs `pc53` on the thread that runs the simulation (Direct3D 9 normally sets `pc24` on the
  render thread; that is expected if it is the same on every PC).
- `ftz` / `daz` in `mx`: should be absent or present on all PCs alike.

Baseline from the first run (Intel Xeon E5-2667 v4, 16 logical CPUs, NVIDIA, 2026-11-08, main menu):
at +5.5 s the main thread (`start=RelicCOH.exe+28E6DA`) goes from `027F` (pc53) to `007F` (pc24),
which is what Direct3D 9 does by default. There are also 15 worker threads (`start=MSVCR100.dll+5C59C`) at `007F`. All other
threads (driver, sound, network, Steam) stay at `027F`, and every `mx` is `1F80`. Steady state:
`cw/mx: 007F/1F80 x16, 027F/1F80 x55`. The 15 workers look like one per logical CPU minus one, so
a PC with a different core count will show a different `x16`. That alone is expected; a different
cw on the main thread or the workers is not.

Each scan writes one line per thread, so the log grows by about 130 KB a minute (about 8 MB per
hour of play).

## Uninstall

Close the game, then:

```powershell
Remove-Item "$game\version.dll", "$game\fpu-probe.nobox", "$game\fpu-probe.nopin" -ErrorAction SilentlyContinue; Test-Path "$game\version.dll"
```

`False` means it is gone. (Run the `$lib = ...` command from Install first if this is a new
PowerShell window.) Steam's "Verify integrity of game files" does **not** remove it, because the
file is not part of the game.

## Build

Needs Visual Studio Build Tools (2022 or later) with the C++ x86/x64 tools and a Windows SDK.

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\fpu-probe\build.ps1 -Test
```

This builds `build\version.dll` (static CRT, no extra runtime needed on the players' PCs) and
`build\test\probe-test.exe`, then runs a self-test (11 checks): forwarding, a 24-bit-precision
thread, an FTZ/DAZ thread, a mid-run change flagged `CHANGED`, the alert on a fake mismatch line,
and the pin on a stand-in `SimEngine.dll` whose virtual `World::Simulate` starts with the same
bytes as the game's (corrected before and after each of 5 ticks, `this` kept, and off with
`FPU_PROBE_NOPIN`).

| File | Purpose |
|---|---|
| `src\probe.cpp` | Forwarding stubs, thread scanner, module log, warnings watcher, pin hook |
| `src\version.def` | The 17 `version.dll` exports, same ordinals as Windows |
| `src\probe.rc` | File description so the DLL is recognisable in Explorer |
| `install-and-watch.ps1` | Installs the DLL from Downloads, watches the log, writes the compare report |
| `install-and-watch.bat` | Double-click launcher for the script; installs the `version.dll` next to it and turns the pop-up off |
| `collect-logs.bat` | Double-click after a game played without the script: report and dated zip from the newest log (`-Collect`) |
| `test\probe-test.cpp` | Self-test host |
| `test\SimEngine.cpp`, `.h` | Stand-in for the game's `SimEngine.dll`, for the pin test |

Test-only environment variables: `FPU_PROBE_FORCE=1` (log in any exe), `FPU_PROBE_LOGDIR`,
`FPU_PROBE_INTERVAL` (ms, default 5000), `FPU_PROBE_NOBOX=1`, `FPU_PROBE_NOPIN=1`.

## Known limits

- It samples every 5 seconds, so a setting that is changed and restored within one frame is only
  caught if a sample lands inside that window (then `at=` names the DLL that was running).
- The pin covers the thread that runs `World::Simulate`. If the simulation also does
  floating-point work on worker threads, those are only logged.
- Replays recorded without pinning may not play back the same with it (and the other way round)
  if the game ran its ticks with other settings before.
- Each reading suspends a thread for a few microseconds. Lockstep does not depend on timing, so this
  cannot cause a desync by itself.
