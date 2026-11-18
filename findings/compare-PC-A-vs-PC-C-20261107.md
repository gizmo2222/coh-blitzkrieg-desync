# BK-collect comparison: PC-A (user-a) vs PC-C (user-c)

Reports: `BK-report-PC-A-20261107-0155.zip`, `BK-report-PC-C-20261107-1114.zip`.
Compared on 2026-11-07.

## Verdict

The game installs are identical. All 579 files under the game folder (GameRoot, Game.WW2, Game.Engine,
Game.CoH, DLC1-3, Blitzkrieg) have the same size and SHA-256 on both machines. Same CoH build 1647830,
same Blitzkrieg depot build 21630206, same RelicCOH.exe, WW2Mod.dll, SimEngine.dll, ModManager.dll
hashes, same .module files, same sysconfig.lua. The in-game data CRC agrees too:
Blueprints -1857718499, Attributes count 60352, Attributes CRC -874230631 on both.
Both replay maps (1496162131123372040, 1426789716279165026) are present on both machines with equal hashes.

File differences are therefore ruled out as the desync cause. What differs is environment and launch setup.

## Differences that matter for desync testing

| Item | PC-A | PC-C |
|---|---|---|
| Steam launch options (228200) | `-mod Blitzkrieg -dev -nomovies -sync_high` | none |
| Last launch RUN-OPTIONS | `-mod Blitzkrieg -dev -nomovies -sync_high` | `-mod Blitzkrieg -dev -nomovies` (no `-sync_high`) |
| User folder | junction to `D:\CoHUser`, not in OneDrive | inside `C:\Users\<user>\OneDrive\...` (OneDrive not running at report time) |
| Extra network adapter | Hyper-V/WSL vEthernet 192.168.x.x (game listed it as Host IP #0) | WireGuard tunnel 10.3.150.87, metric 3 |
| Newest game log | 2026-11-07 launches only, no match | 2026-05-08: 1302 mismatch lines, ended in disconnect |

## Logs

Shared games (same random seed in both logs):
- 2026-04-03, seed 1775257190: clean on both, normal game ending.
- 2026-02-17, seed 1771375188: DESKTOP shows 119 "Entity command 17 ... fuel_point_high / CPU to CPU"
  lines, PC-C shows 0, and BOTH ended with "normal game ending (no sync errors)". So those
  command-17 lines on resource points are noise, not a desync; the collector's mismatch count overstates them.
- PC-C's 2026-02-17 20:12 game (seed 1771380912) has 115 of the same noise lines and also ended normally.

Desync game 2026-05-08 20:10 (PC-C only; DESKTOP has no log from that date, so it was not in that
match or its logs were already rotated): map 8p Infantry OP (1426789716279165026), players Player C,
Player B and CPU-Normal. The first mismatch is at 20:47:20.90 (31 min in), real Squad commands 54/63/58/61,
mostly CPU squads mis-owned between CPU and Player C, then disconnect at 20:54:51. Launched without
`-sync_high`.

## Settings (configuration.lua)

Only cosmetic/audio differences: mastervolume, sfxvolume, speechvolume, mousescroll, playercolour, and
DESKTOP keeps prev* resolution keys. Graphics settings are equal. Nothing sim-relevant.

## Maps.Subscriptions

65 vs 64 workshop maps; 58 shared and identical. Only on DESKTOP: 1095916259112910977, 1285966981412945980,
1581400430036910843, 6223440159166169113, 7754945507448848656, 7789848404560972287, 903674828614008869.
Only on PC-C: 1240753242212663299, 1454859870179164195, 1461642035856408755, 3889949268647084068,
5011231364092002363, 7191714079050825848. Only matters if one of those maps is played.

## Actions for PC-C before the next test

1. Add `-sync_high` (and `-mod Blitzkrieg -dev -nomovies`) to Steam launch options for 228200.
2. Move the user folder out of OneDrive (checklist section "Do once before the playtests").
3. Disable the WireGuard adapter while playing.

For PC-A: disable the WSL/Hyper-V vEthernet adapter while playing; the game picked it as Host IP #0.
