# BK-collect: one script per player, one zip back

Purpose: find out why Company of Heroes + Blitzkrieg desyncs by proving every player has the same game
files, mod files, maps and settings. Each player runs the collector once; it writes a small zip to their
Desktop; they send the zip over Discord; you consolidate the zips here and let Claude read the comparison.

## What each player does

1. Unzip the `BK-collect` folder anywhere (Desktop is fine). It holds `BK-collect.cmd`, `BK-collect.ps1`,
   `BK-compare.ps1`, this file.
2. Double-click **BK-collect.cmd**. A console window shows progress for about 1 to 2 minutes (the time is
   spent hashing the 2.5 GB mod folder and the sim-relevant base-game archives). No admin rights needed.
3. The zip appears on the Desktop as `BK-report-<ComputerName>-<date>.zip`, normally 1 to 5 MB.
   Attach it in Discord. If the script says it is over 10 MB, re-run with the replay left out and send
   the replay by other means:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\BK-collect.ps1 -NoReplay
```

If the game is not found automatically (unusual Steam library), the script asks for the folder, or pass it:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\BK-collect.ps1 -GamePath "D:\Games\Steam\steamapps\common\Company of Heroes Relaunch"
```

`-Full` additionally hashes every base-game archive (art, sound, movies; adds several minutes, only needed
if the normal run shows no difference and we still suspect the base install). `-LogDays N` changes how
many days of logs are copied (default 14; the newest three of each log type are always included).

## What the zip contains (tell players this before they send it)

| File | Content |
|---|---|
| `summary.txt` | key=value lines: OS, RAM, CPU, GPU, game exe size and SHA256, mod DLL versions, Steam build ids and update times for app 228200 (game) and 681590 (Blitzkrieg), Steam launch options, mod version from `Blitzkrieg.module`, loose files under `Blitzkrieg\Data`, user-folder location (OneDrive, junction, online-only placeholders), last launch options from the log, sync level and mismatch count of the newest game log, newest data CRC, network adapters, findings |
| `manifest.csv` | every file in `Blitzkrieg\` (all hashed), the game root, `WW2\`, `Engine\`, `DLC1-3\`, `CoH\` (hashed where sim-relevant, otherwise size and date), Workshop maps in `ww2\scenarios\subscriptions` (hashed) |
| `config\` | `RelicCOH.ini`, `Locale.ini`, `*.module`, Steam `appmanifest_*.acf`, user `configuration.lua`, `playercfg.lua`, `Local.ini` |
| `logs\` | `warnings.*`, `designmessages.*`, `datacrc.*` and other LogFiles newer than 14 days plus the newest 3 of each type (files over 25 MB skipped), `warnings.log`, any `SyncError*` dumps, and `log-summary.txt` with the lines that matter per game (sync level, host IP, mismatches, drops, CRC line) |
| `replay\` | newest replays (`playback\temp.rec` and up to 2 more), under 40 MB each; `-NoReplay` omits |

Privacy: the zip includes the computer name, the Windows user name, the Steam account id, local IP
addresses, the in-game player name and the paths above. No passwords, no Steam credentials, nothing
outside the game, its user folder and Steam's manifest files.

## Consolidating here

Drop every player's zip into `reports\` at the repo root (create it; git ignores it) (keep the original `BK-report-*.zip` names), then:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\BK-collect\BK-compare.ps1
```

It expands each zip to `reports\extracted\<zipname>\` and writes
`reports\BK-compare-report.md` with:

1. key values side by side, **DIFF** on any row where players disagree (exe hash, DLL versions, build ids,
   launch options, mod version, loose files, OneDrive, sync level, CRC, adapters);
2. per file group: how many files are identical, and a row for every file missing on someone or differing
   in hash or size, with size / first 8 hash characters / timestamp per player;
3. each player's findings and errors;
4. where the extracted raw files are, for digging into a specific player's logs.

Then open Claude Code in the repo root and ask it to read `reports\BK-compare-report.md` (and, if
needed, the `logs\log-summary.txt` of a specific player). Re-run the compare whenever a new zip arrives.

`-ReportDir` points at another folder; `-Out` names the markdown file.

## Sending the tool to players

```powershell
Compress-Archive -Path ".\tools\BK-collect" -DestinationPath ".\BK-collect.zip" -Force
```

Players need Windows PowerShell 5.1 (every Windows 10/11 has it). The `.cmd` wrapper bypasses the
execution policy for this one run only.

## How the collector decides what to hash

- All of `Blitzkrieg\` (mod archives, loose data, locale, module files): the mod is what the group
  distributes by hand, so every byte counts.
- Base game: `.sga` whose name contains Data, Attrib or Engine, plus every `.dll`, `.lua`, `.module`,
  `.ini`, `.txt`. Art, sound, speech and movie archives only by size and date unless `-Full`.
- Workshop maps: all hashed (a map that differs by one byte desyncs the game that uses it).

## Known limits

- `game.exe.version` reads "The build server will stamp this field" on this build; the exe hash and size
  are the real identity.
- The sync level only appears in a log when a match was played that session; a player who only reached
  the menu shows "(no sync level line ...)".
- Not yet run on another player's PC; the first foreign zip will tell whether game-folder detection and
  the user-folder detection hold up there. Discord's attachment limit for free accounts is assumed to be
  10 MB.
