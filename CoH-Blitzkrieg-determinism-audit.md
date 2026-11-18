# Blitzkrieg script determinism audit (option 2)

Done 2026-11-08. Question: can a mod script make one PC compute the game differently from the
others? Answer: no likely cause found in the scripts your games actually run. Next is option 3
(our own DLL), described at the end.

## What runs on every PC in your games
Every recorded game used Annihilate (`ZANNIHILATE.SCAR` or `ZANNIHILATE_250.SCAR`) on the
Workshop maps INFANTRYOP, CROSSING MEUSE POINTS UP and 6P_ACHELOUS RIVER. The scripts that run
in every PC's simulation are:

| Script | Where | Result |
|---|---|---|
| `scar/winconditions/zannihilate_250.scar` | `BKDataPatch.sga` | 19 lines; only sets pop cap 250. Clean |
| `scar/wcutil.scar` (annihilate check) | `BKDataPatch.sga` | Two `pairs()` loops, both membership tests, so order does not matter. Clean |
| `scar/scarutil.scar`, `luaconsts.scar` | `BKDataPatch.sga` | Flagged lines are UI, camera and game-over screens, or loops over constant tables. Clean |
| `squadai/*.squadai` | `BKDataPatch.sga` | Only engine actions; `ACTION_WAIT_RANDOM` is an engine call, not Lua `math.random`. Clean |
| `scenarios/mp/infantryop_id.scar` | Workshop `1426789716279165026.sga` | Empty stub |
| Base-game libraries (`Timer.scar`, `Player.scar`, ...) | `WW2Data.sga`, unmodified | 20 years of multiplayer use; not audited |

## Patterns searched (137 effective files, patch overrides base)
`math.random`, `os.time/clock/date`, real-time clocks, `io`/`dofile`/`require`: **0 hits**.
`Game_GetLocalPlayer`: only in the VP-ticker win conditions (UI text), which your games don't use.
`pairs()`, `next()`, `tostring()`: 1036 hits. Nearly all are in single-player missions or AI files.
Command-line checks: single-player missions and one game-over delay flag.

## Why the AI scripts don't matter
Each CPU player's AI runs on one PC and sends its decisions as normal commands, which every PC
executes. The logs confirm it: a PC never flags commands from its own local AI. So different AI
results on two PCs change what that AI orders, but every PC still runs the same orders.
The mismatch lines are a symptom of drift, not the cause. CPUs show up first only because they
issue the most commands.

## Files are identical
All 9 BK-collect reports show `mod.loosefiles=0`. Nobody deployed the squad-AI fix from
`CoH-Blitzkrieg-mod-review.md` section 1, so everyone runs the same archives. Keep it that way:
deploy that fix to all four players or to none.

Not covered: binary attribute data (`.rgd` in `BKAttrib*.sga`). It's data, not code, and the data
CRC matched on every PC.

## Next: option 3 (our own DLL), diagnostic first
1. A 32-bit proxy DLL next to `RelicCOH.exe` that logs the x87 control word and MXCSR on every
   game thread every few seconds, and pops up an alert on the first mismatch line.
2. One game with all four players running it. If the math settings differ between PCs or change
   mid-game, build the pinning fix. If they're identical, the remaining lead is the Intel/AMD
   x87 math-instruction difference (patching the exe).
Needs: a C++ compiler for 32-bit Windows (Visual Studio Build Tools or MinGW i686).

Step 1 is done: `tools\fpu-probe\` (proxy for `version.dll`; install, log collection and uninstall
are in its README). The first run on this PC: the main thread and 15 worker threads run at pc24 (`007F`),
the other threads at pc53 (`027F`), MXCSR is `1F80` everywhere, and nothing changed during 100 s.
Step 2 (the four-player game) is next.

The fix was built ahead of step 2 (fpu-probe 2.0, 2026-11-08). The probe now wraps the exe's
imports of `SimEngine.dll` `World::SimulatePre` / `SimulatePost`, in memory only, and sets
cw=`007F` and MXCSR=`1F80` at the start of every tick, logging each correction (`PIN` lines). The
self-test passes and the hook installs in the real game; the tick path has not yet run in a match.
The playtest (all four players on 2.0) decides it: no desync means the cause was the simulation
thread's FPU settings. A desync with no `PIN` corrections means it was not.
