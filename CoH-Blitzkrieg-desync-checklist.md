# Company of Heroes / Blitzkrieg desync testing checklist

Written 2026-11-07 from an inspection of this PC. All commands are Windows PowerShell 5.1, one per block.

## Where things are

| Item | Path |
|---|---|
| Game (2.700.2, Steam app 228200), called `$game` below | `<Steam library>\steamapps\common\Company of Heroes Relaunch\` |
| Mod (Blitzkrieg 5.3.7, Steam app 681590) | same folder: `Blitzkrieg.module`, `Blitzkrieg\Archives\*.sga` |
| Launch options the launcher adds | `-mod Blitzkrieg -dev -nomovies` |
| User folder, called `$coh` below | `<Documents>\My Games\Company of Heroes Relaunch\` (Documents may be redirected into OneDrive) |
| Logs | `<user folder>\LogFiles\` |
| Last replay (overwritten every game) | `<user folder>\playback\temp.rec` |
| Workshop maps | `<user folder>\ww2\scenarios\subscriptions\` |
| Engine config | `RelicCOH.ini` in the game folder (console key `CONTROL+SHIFT+Grave`, `MaxTimeoutBeforeDisconnect = 30000`) |

## Collect everyone's data in one go (replaces sections 3 and 4 below)

`tools\BK-collect\` holds a collector every player runs once (double-click `BK-collect.cmd`,
1 to 2 minutes, 1 to 5 MB zip on the Desktop, sent through Discord) and `BK-compare.ps1`, which turns the
zips in `reports` into `BK-compare-report.md` with every file, size, hash and setting side by
side. See `tools\BK-collect\README.md`. Package it for the others with:

```powershell
Compress-Archive -Path ".\tools\BK-collect" -DestinationPath ".\BK-collect.zip" -Force
```

## What a desync looks like in the log

The `warnings.<date>.txt` for the game fills with lines like:

```
*** Squad command 45 sent from 1002 (Player C) but received by squad "sbps\races\axis\vehicles\halftrack_squad_kwk37" belonging to 1006 (CPU - Normal)
```

The first such line marks the moment the simulations diverged. Clean games have none and end with
`GameOverDialog - normal game ending (no sync errors)`.

Known desync game: `warnings.2026-02-13.15-51-46.txt` (4v4 with CPUs, first mismatch 16:33:46, host dropped 16:59:46).
Clean games for comparison: 2026-02-15, 2026-02-17, 2026-04-03.

## Before testing

Set a variable for the user folder and the game folder (change the Steam library path to yours) so the commands below stay short:

```powershell
$coh = "$([Environment]::GetFolderPath('MyDocuments'))\My Games\Company of Heroes Relaunch"
```

```powershell
$game = "C:\Program Files (x86)\Steam\steamapps\common\Company of Heroes Relaunch"
```

Back up the current replay so it is not lost:

```powershell
Copy-Item "$coh\playback\temp.rec" "$coh\playback\temp.before-testing.rec"
```

## After every game

### 1. Did it desync, and when?

```powershell
Get-ChildItem "$coh\LogFiles\warnings.*.txt" | Sort-Object LastWriteTime | Select-Object -Last 1 | ForEach-Object { "File: $($_.Name)"; $m = Select-String -Path $_.FullName -Pattern 'belonging to'; "Mismatch lines: $($m.Count)"; $m | Select-Object -First 3 | ForEach-Object { "$($_.LineNumber): $($_.Line.Trim())" }; Select-String -Path $_.FullName -Pattern 'GameOverDialog|PlayerDrop|disconnected' | ForEach-Object { $_.Line.Trim() } }
```

### 2. Save the replay and log from a desync game

```powershell
$stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm'; Copy-Item "$coh\playback\temp.rec" "$coh\playback\desync_$stamp.rec"; Get-ChildItem "$coh\LogFiles\warnings.*.txt" | Sort-Object LastWriteTime | Select-Object -Last 1 | Copy-Item -Destination "$coh\LogFiles\desync_$stamp.warnings.txt"
```

### 3. Your data checksums (send to teammates, ask for theirs)

Every player must show identical values. A difference means the mod or attribute data is not the same on both machines.

```powershell
Get-ChildItem "$coh\LogFiles\datacrc.*.txt" | Sort-Object LastWriteTime | Select-Object -Last 1 | ForEach-Object { "File: $($_.Name)"; Select-String -Path $_.FullName -Pattern 'Total CRC|Blueprints|Attributes \[|RandomStreamSeed' | ForEach-Object { $_.Line.Trim() } }
```

Reference values from this PC on 2026-04-03: Total CRC `be086e18`, Blueprints `-1857718499`, Blueprints Attributes Count `60352`, Attributes `-874230631`.

Mod DLL version line from the warnings log (should also match across players):

```powershell
Get-ChildItem "$coh\LogFiles\warnings.*.txt" | Sort-Object LastWriteTime | Select-Object -Last 1 | ForEach-Object { Select-String -Path $_.FullName -Pattern 'CRC & Version Info|MOD -- Mounting|GAME -- Company Of Heroes' | ForEach-Object { $_.Line.Trim() } }
```

Reference: `CRC & Version Info : 000002bc:6f6bb514:dc49d0cb blitzkrieg:700:ww2mod.dll 1`, mod 5.3.7, game 2.700.2.

### 4. Map file comparison

List the Workshop maps with size and date, then compare the row for the map you played against each teammate's:

```powershell
Get-ChildItem "$coh\ww2\scenarios\subscriptions" -File | Sort-Object LastWriteTime -Descending | Select-Object Name, Length, LastWriteTime | Format-Table -AutoSize
```

Mod archive sizes (should be identical on every machine):

```powershell
Get-ChildItem "$game\Blitzkrieg\Archives" -File | Select-Object Name, Length | Format-Table -AutoSize
```

## Test plan (one variable at a time)

Record for each game: date, map, players, CPU slots yes/no, result of command 1.

- [ ] **Game A: no CPU players.** Both logged desync chains involved CPU-owned squads, and the module uses `PlayerDropBehavior = aitakeover`. If games without CPUs never desync, AI is the cause.
- [ ] **Game B: virtual adapter disabled.** On 2026-02-13 the game bound to a virtual (WSL/Hyper-V) 192.168.x.x address, not the Ethernet adapter's address. Check the current adapters, then disable the vEthernet one for the session (run PowerShell as administrator):

```powershell
Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Select-Object Name, InterfaceDescription, ifIndex | Format-Table -AutoSize
```

```powershell
Disable-NetAdapter -Name "vEthernet (WSL (Hyper-V firewall))" -Confirm:$false
```

Re-enable afterwards:

```powershell
Enable-NetAdapter -Name "vEthernet (WSL (Hyper-V firewall))" -Confirm:$false
```

Confirm which address the game used in the log:

```powershell
Get-ChildItem "$coh\LogFiles\warnings.*.txt" | Sort-Object LastWriteTime | Select-Object -Last 1 | ForEach-Object { Select-String -Path $_.FullName -Pattern '192\.168\.|station' | Select-Object -First 8 | ForEach-Object { $_.Line.Trim() } }
```

- [ ] **Game C: OneDrive paused.** The whole user folder (config, cache, maps) lives under OneDrive. Pause syncing from the OneDrive tray icon before launching, and check nothing is marked online-only:

```powershell
Get-ChildItem "$coh" -Recurse -File | Where-Object { $_.Attributes -band 0x400000 } | Select-Object FullName
```

- [ ] **Game D: all players on identical CRCs and map files** (commands 3 and 4 compared beforehand).

### Added 2026-11-07 after comparing three PCs (`findings\compare-3PC-20261107.md`)

The collector proves the setups match. It cannot run these tests. Status as of 2026-11-07: game and mod files
match on all three PCs except Player B's `6p_RoadToCherbourg_rev2.sga` (fix with a Steam verify of Blitzkrieg). The
2026-05-08 desync (Player C host running both CPUs, Player B, 8p Infantry OP) started about 31 minutes in, with
identical data CRCs on both PCs.

The 2026-11-07 evening desync (4 humans + 4 CPU, Infantry OP, Player B host) split by CPU vendor: the two Intel PCs
(Player B, Player A) against the two AMD PCs (Player C, Player D), about 29 minutes in, with identical files and CRCs on
all four. Details and next tests: `findings\game-20261107-1840.md`.

- [x] **First: confirm `-sync_high` works.** Confirmed 2026-11-07: three games hosted by Player C started at sync level 1 with `SyncErrorChecking level to High` (`findings\results-20261107-test-games.md`). Before that it had not been checked in a game on this build. The host's level is
  sent to everyone, so the host's launch options are what count. After the first match, the host checks the newest
  log for `Starting game with synclevel` with a value other than 0 and for `SyncErrorChecking level to High`
  (command in "Open question for the Blitzkrieg team" below). If a desync happens at High, keep the `SyncError*` dump files with the replay.
- [ ] **Game A again, long.** Same players, same map, no CPU slots, played past 40 minutes. The 05-08 desync centred
  on the AIs, and it started at minute 31, so a short game proves nothing.
- [ ] **Game E: replay cross-check.** Every player plays back the same replay: now
  `reports\game-20261107-1840\desync-20261107.rec` (Player D's full recording of the 11-07 Intel/AMD split), saved into
  their own `playback\` folder. Watch to at least minute 32 (the split was at about minute 28-29), quit, then run
  command 1. Expected if the CPU is the cause: Intel PCs first flag CPU 1007's command on 1006's `officer_squad`,
  AMD PCs first flag CPU 1005's command on Player D's `engineer_infantry`, matching the live game. A different outcome
  on the screen at the same replay time points the same way. Steps for players: `findings\game-20261107-1840.md`.
- [ ] **Game F: stock hardware.** BK-collect records the CPU model only. Ask every player whether they run an overclock
  or memory profile (EXPO/XMP, PBO, Intel turbo tweaks), and play one long test with BIOS defaults and the overlays
  off (Discord, RivaTuner, AMD Adrenalin, GeForce Experience). A desync that only shows up after half an hour fits
  marginal hardware stability. This is a guess the files cannot confirm or rule out.
- [ ] **Game G: everyone capped to the same FPS.** Researched 2026-11-07. Evidence is two forum posts, nobody confirmed:
  a Blitzkrieg "Constant Desyncs" thread (Oct 2020, NVIDIA Max Frame Rate 45, "30 would help further") and a base-game
  "Random game desync" thread (Mar 2025, "both players cap to 60, no desyncing"). No Relic or BK statement, no mechanism.
  It fits the 11-07 finding that something local, not in the recording, leaked into the live sim. The 11-07 game ran at
  very unequal speeds (end-of-game `Max/Avg ... (fps=worst, avg)` line): Player D 49/56, Player B 20/43, Player C 25/40,
  Player A 7/16. Test: all four set the **same** cap (30, a level most PCs hold late game) in the GPU driver, not in game:
  NVIDIA Control Panel > Manage 3D settings > Program Settings > add `RelicCOH.exe` > Max Frame Rate = 30; AMD Adrenalin >
  Gaming > Company of Heroes (or Graphics) > Frame Rate Target Control = 30 (Radeon Chill min = max = 30 if FRTC is missing).
  Keep `-sync_high`; change nothing else. Same 4 humans + 4 CPU, Infantry OP, past 40 minutes, at
  least two games (one clean game proves little: the 82-minute game earlier that day was clean without a cap). Check after
  the game that the cap held (avg should read 30 or less on every PC):

```powershell
Get-ChildItem "$([Environment]::GetFolderPath('MyDocuments'))\My Games\Company of Heroes Relaunch\LogFiles\warnings.*.txt" | Sort-Object LastWriteTime | Select-Object -Last 1 | Select-String -Pattern 'Max/Avg:' | Select-Object -Last 1 | ForEach-Object { $_.Line.Trim() }
```

**After every test game**, desync or not: write down the date, map, host, CPU slots, length and result (command 1).
Everyone who played runs BK-collect the same day, before the next launch overwrites `temp.rec`, and sends the
zip. Then run `BK-compare.ps1` here. Player B re-runs BK-collect right after the Steam verify, to confirm that
`6p_RoadToCherbourg_rev2.sga` now hashes to `BCEDF703...`.

## Do once before the playtests: take the user folder out of OneDrive

The game asks Windows for the Documents folder, which is redirected to `<OneDrive>\Documents`, so everything it
writes (config, cache, logs, replays, 800 MB) is synced while you play.

**`-userdir` does not work.** Tested 2026-11-07: the game accepted `-userdir "D:\CoHUser"` on its command line
(`RUN-OPTIONS -sync_high -userdir D:\CoHUser` in the log) and still wrote everything to the OneDrive folder. Do not use it.
The copy in `D:\CoHUser` was never written to by the game and can be deleted.

**Junction (the fix).** Move the folder and leave a directory junction at the old path, so the game finds
it where it always looked while the bytes live outside OneDrive. OneDrive does not sync through junctions. Run with
the game and OneDrive closed:

```powershell
Move-Item "$coh" "D:\CoHUser"
```

```powershell
New-Item -ItemType Junction -Path "$coh" -Target "D:\CoHUser"
```

Undo: delete the junction (`Remove-Item` on the junction path removes only the link), then move the folder back.

Network adapter: there is no switch or ini key to pick the adapter; the engine enumerates all interfaces and warns.
Windows already prefers the real NIC (metric 25 vs 5000 for the WSL vEthernet), and the log lists the Ethernet address
first. Disabling the virtual adapters (Game B above) or `wsl --shutdown` before playing is the whole fix; patching
the exe is not worth it, and it is not a plausible desync cause (adapter trouble shows as drops, not sync errors).

## Launching the mod: skip the Blitzkrieg Launcher

Verified 2026-11-07. The launcher is only a window with three buttons; it does not update or check anything.
Button 1 runs `cmd /c Call Steam.exe -applaunch 228200 -mod Blitzkrieg -dev -nomovies`, which needs `Steam.exe` on
PATH. It is not (Steam is in `C:\Program Files (x86)\Steam`, PATH has no Steam entry), so cmd fails and the game never
starts: Steam's log shows every launcher run spawning that cmd with exit code 1 and no game process. The base game
launches fine from its own Steam entry (two runs to the menu that night).

Fix: launch **Company of Heroes** (app 228200) from Steam with Launch Options `-mod Blitzkrieg -dev -nomovies -sync_high`.
That is exactly what the launcher would have passed, plus the sync switch. Other players who still use the launcher
get the same mod arguments; only `-sync_high` must be added by everyone. Leave the Blitzkrieg entry's Launch Options empty.

Alternatives if someone insists on the launcher: button 2 (`steam://rungameid/228200// -mod Blitzkrieg -dev -nomovies`)
works but Steam pops an "allow launch with parameters" prompt each time; or put the Steam folder on PATH and restart Steam:

```powershell
[Environment]::SetEnvironmentVariable("Path", [Environment]::GetEnvironmentVariable("Path", "User") + ";C:\Program Files (x86)\Steam", "User")
```

## Open question for the Blitzkrieg team

The engine supports sync-error checking at None / Low / High (`SIM -- Setting SyncErrorChecking level to ...`) and writes `SyncError_<frame>` dump files when a check fails. Every game here ran at Low and no dump files exist.

**How to set High.** It is a command-line switch on `RelicCOH.exe`, not a menu option: `-sync_high` (the exe logs `GameApp::InitGlobal - SyncLevel set to N by default`, and the host sends its level to every player at game start: `SMT_StartGame_To_Everyone - Starting game with synclevel N`). The Blitzkrieg Launcher hardcodes `-mod Blitzkrieg -dev -nomovies` and starts the game through Steam (`-applaunch 228200 ...`), so Steam's own launch options are appended: in Steam, right-click **Company of Heroes** (the base game, app 228200, not the Blitzkrieg entry), Properties, General, Launch Options, enter `-mod Blitzkrieg -dev -nomovies -sync_high` and start **Company of Heroes** from Steam, not the
launcher (see "Launching the mod" above). Have every player do it; the host's setting is what counts, but identical settings keep the test clean. Verify in the newest log (expect a value other than 0):

```powershell
Get-ChildItem "$coh\LogFiles\warnings.*.txt" | Sort-Object LastWriteTime | Select-Object -Last 1 | Select-String -Pattern 'SyncLevel set to|sync level:|SyncErrorChecking'
```

After a desync at High, look for dump files and keep them with the replay:

```powershell
Get-ChildItem "$coh" -Recurse -Filter 'SyncError*' | Select-Object FullName, Length, LastWriteTime
```

Not yet verified in a game that the switch is accepted by this build; the log line above is the check.

Second question for them (added 2026-11-07): the module hands dropped players to the AI
(`PlayerDropBehavior = aitakeover`), and the 2026-05-08 desync centred on two CPU players run by the host, on 8p
Infantry OP, after 31 minutes. Are there known AI desyncs in 5.3.7 on 8-player maps or in long games, and is there
a fix or a safe setting?
