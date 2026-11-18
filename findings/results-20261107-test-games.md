# Test games 2026-11-07: Player B and Player C

Reports: `BK-report-PC-B-20261107-1604.zip` and `BK-report-PC-C-20261107-1805.zip`.
PC-A did not play (its newest zip is still `...-0155`). Times below are Player B's clock (PST); Player C's
log is 2 h ahead (CST). Earlier analysis: `compare-3PC-20261107.md`.

## Verdict

Three games, no desync. The third ran 82 minutes in the same setup as the 05-08 desync: host Player C running
four CPUs, with Player B as the remote human. It ended with "normal game ending (no sync errors)" on both PCs, with
0 mismatch lines and no SyncError files. `-sync_high` works: every game started at sync level 1 with
`SyncErrorChecking level to High`. The 05-08 game ran at level 0 / Low.

## Games

Map for all three: Crossing Meuse Points Up. Team 0: Player C (id-C, host) and Player B (id-B). Team 1: four
CPUs, Type 1 on PC-C and Type 3 on Player B, so the host ran them all.

| Start (PST) | Seed | Total CRC | Length | Result |
|---|---|---|---|---|
| 14:23 | 1794090239 | 7c0aed81 | 3 min | Player C's game quit at 14:26:59 (exit 0). Player B's PC took over the CPUs (`KillAllDropped ... migrate to station [2]`) and played on to a normal ending, 0 mismatches |
| 14:30 | 1794090615 | 8c833ed3 | 9 min | Normal ending on both, 0 mismatches |
| 14:40 | 1794091235 | deb2282d | **82 min** | Normal ending on both at 16:03:15, 0 mismatches. Replay `temp.rec` is 5,832,152 bytes on Player B and 5,832,150 on PC-C |

Both PCs wrote identical `datacrc` logs for all three games (timestamps aside).

## What changed since the 05-08 desync

- Both players now launch with `-mod Blitzkrieg -dev -nomovies -sync_high`, so checking runs at High.
- PC-C: WireGuard is gone (one network adapter now), and the user folder moved out of OneDrive
  (`C:\Users\<user>\Documents\...`). OneDrive still runs, but it no longer holds the game folder.
- Different map (Crossing Meuse Points Up instead of 8p Infantry OP), with 4 CPUs instead of 2.

One clean long game is encouraging, not proof. The April games on this pair were clean too. Several things changed
together, so this does not say which one mattered. The useful result is that High checking is now on, so the next
desync will be caught when it starts and leave a dump.

## Still open

1. **Player B's Cherbourg archive is still damaged.** `6p_RoadToCherbourg_rev2.sga` still hashes `6F906D6A`
   (dated 2026-02-13). The Steam verify either was not run or did not fix it. Run Steam > Blitzkrieg (681590) >
   Properties > Installed Files > Verify, then BK-collect again. If the hash still differs, check that drive
   (`chkdsk`, SMART). Do not pick that map until then.
2. Repeat the long game on the 05-08 map (8p Infantry OP) with CPUs, to test the case that failed before.
3. Bring PC-A into a three-player game. It has not played with this setup yet.
4. Workshop maps still differ: 58 identical, 13 different or missing (Player B 61, PC-C 64, DESKTOP 65). This
   only matters if one of those maps is picked.
5. Side note: PC-C's address check to Player B's LAN address 192.168.x.x timed out at game start. The game
   connected anyway (through the host route), so this is just a log line.
