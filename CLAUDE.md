# CLAUDE.md

Desync investigation toolkit for the Blitzkrieg mod on Company of Heroes Relaunch (Windows, Steam).
Read `README.md` first, then `CoH-Blitzkrieg-desync-checklist.md`, which is the working document.

## Doc map

| Question | File |
|---|---|
| Where the game keeps logs, replays and maps; what a desync looks like; the test plan | `CoH-Blitzkrieg-desync-checklist.md` |
| Which mod scripts can run non-deterministically | `CoH-Blitzkrieg-determinism-audit.md` |
| Mod bugs, tunable settings, the squad-AI fix | `CoH-Blitzkrieg-mod-review.md` |
| What happened in each test game so far | `findings/*.md` (newest: `game-20261113-2200.md`) |
| Collecting and comparing player reports | `tools/BK-collect/README.md` |
| The FPU probe: install, logs, pin, build | `tools/fpu-probe/README.md` (295 lines, read by section) |

## Rules

- Shell is **Windows PowerShell 5.1**. Commands you give the user: no `&&`/`||`, use `$env:VAR`, one command
  per `powershell` block. Write files as UTF-8 without BOM (`[IO.File]::WriteAllText`).
- Paths are per machine. Find the game with the Steam registry key (`HKCU:\Software\Valve\Steam` SteamPath, then
  `steamapps\libraryfolders.vdf`) and the user folder with `[Environment]::GetFolderPath('MyDocuments')` +
  `\My Games\Company of Heroes Relaunch`. Docs write them as `$game` / `$coh`.
- `reports\` (player zips, logs, replays) and `extracted\` (the mod's files) are gitignored. **Never commit them.**
  Player data has PC names, usernames and hardware. Write a finding into `findings\` with players named
  Player A-D and PCs PC-A-D, and no usernames, profile ids, IPs or personal paths.
- `extracted\` is recreated with `python -I tools/extract_text.py "<game folder>"` and is the mod team's content.
- A desync line is `... sent from X but received by ... belonging to Y` in `warnings.*.txt`. Lines between two
  CPU players, or to `(none)`, can be normal AI behaviour: compare the lines across PCs before calling it a split.
- Every change to game data must be identical on every player's PC, or it causes the desync it is meant to fix.

## Typical asks

- "Compare tonight's reports": run `tools\BK-collect\BK-compare.ps1`, read `reports\BK-compare-report.md`, list the DIFF
  rows that matter for sync, then write `findings\game-<yyyyMMdd-HHmm>.md` in the style of the existing ones.
- "Did it desync, and where": the newest `warnings.*.txt` per PC, the first `belonging to` line, and the
  `GameOverDialog` line; with fpu-probe logs, the `PIN` and `ticks=` lines.
- "Build the probe": `.\tools\fpu-probe\build.ps1 -Test` (needs VS Build Tools x86 + Windows SDK).
