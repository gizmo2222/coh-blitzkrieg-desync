# Company of Heroes: Blitzkrieg desync toolkit

Tools and notes from chasing multiplayer desyncs ("sync errors") in the **Blitzkrieg** mod
(5.3.7, Steam app 681590) for **Company of Heroes Relaunch** (2.700.2, Steam app 228200) on Windows.
A group of four players saw long 4-human + 4-CPU games split after about 30 minutes, with the two Intel PCs
on one side and the two AMD PCs on the other, even though every file and data CRC matched.

The repo is set up so you can clone it, open **Claude Code** in the folder and say what you want to do. For example,
"help me collect everyone's data after tonight's game" or "compare the reports in `reports\`". `CLAUDE.md`
gives Claude the layout and the rules. Everything also works by hand. All commands are Windows PowerShell 5.1.

## What's here

| Path | What it is |
|---|---|
| [`CoH-Blitzkrieg-desync-checklist.md`](CoH-Blitzkrieg-desync-checklist.md) | Start here: where the game keeps things, what a desync looks like in the log, what to check after every game, the test plan |
| [`CoH-Blitzkrieg-determinism-audit.md`](CoH-Blitzkrieg-determinism-audit.md) | Audit of the mod's scripts for non-deterministic code, and why the FPU probe came next |
| [`CoH-Blitzkrieg-mod-review.md`](CoH-Blitzkrieg-mod-review.md) | Mod bugs and tunable settings, including a broken squad-AI plan and its fix |
| [`findings/`](findings/) | Write-ups of each test game and PC comparison (anonymized: Player A-D, PC-A-D) |
| [`fixes/Data/squadai/`](fixes/Data/squadai/) | The two repaired `.squadai` files (drop-in loose files, see the mod review) |
| [`tools/BK-collect/`](tools/BK-collect/README.md) | One script each player runs after a game, which zips up their logs, hashes, settings and replay; plus `BK-compare.ps1`, which puts every player's zip side by side |
| [`tools/fpu-probe/`](tools/fpu-probe/README.md) | A `version.dll` proxy that logs the x87/SSE floating-point settings of every game thread and pins the simulation thread's settings on every tick (C++, source and self-test) |
| `tools/sga.py`, `tools/extract_text.py` | Read Relic `.sga` archives and extract the mod's plain-text files into `extracted\` |

## Quick start

Clone it (needs [Git](https://git-scm.com/download/win)):

```powershell
git clone https://github.com/gizmo2222/coh-blitzkrieg-desync.git
```

Then open Claude Code in the `coh-blitzkrieg-desync` folder, or follow the steps below yourself.

**After a game, every player:** download `BK-collect.zip` from the
[Releases page](https://github.com/gizmo2222/coh-blitzkrieg-desync/releases), unzip it, double-click
`BK-collect.cmd`, and send back the zip it leaves on the Desktop. See [`tools/BK-collect/README.md`](tools/BK-collect/README.md),
including what the zip contains.

**One person compares them:** put every `BK-report-*.zip` into a `reports\` folder at the repo root (git ignores it), then:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\BK-collect\BK-compare.ps1
```

That writes `reports\BK-compare-report.md`. Any **DIFF** row is a setup difference to fix before the next test.

**Floating-point probe:** download `fpu-probe-2.2.zip` from Releases and follow
[`tools/fpu-probe/README.md`](tools/fpu-probe/README.md). Building it yourself needs Visual Studio Build Tools
(C++ x86) and a Windows SDK: `.\tools\fpu-probe\build.ps1 -Test`.

**Look at the mod's scripts** (needs Python 3):

```powershell
python -I tools/extract_text.py "C:\Program Files (x86)\Steam\steamapps\common\Company of Heroes Relaunch"
```

## Status (2026-11-17)

- Files, CRCs, launch options (`-sync_high`) and the user folder (moved out of OneDrive) are lined up on all PCs.
- fpu-probe 2.1 pinned the simulation thread's FPU settings on every tick. The game ran three clean long games in a row
  with it, the longest 2 h 41 min, and never had to correct a tick. That does not yet prove the pin fixed it: an unpinned
  control game is still needed (see [`findings/game-20261113-2200.md`](findings/game-20261113-2200.md)).
- fpu-probe 2.2 adds tick timing, to tell a stalled simulation apart from a slow unit.

## Privacy

Player reports contain PC names, Windows usernames, hardware, logs and replays. Keep them in `reports\`
(gitignored) and only commit anonymized write-ups to `findings\`.

Not affiliated with Relic, SEGA or the Blitzkrieg mod team. The mod's own files are not included.
