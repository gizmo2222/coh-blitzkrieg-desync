# Blitzkrieg mod review: bugs and tunable settings

Reviewed 2026-11-07. Mod: Blitzkrieg 5.3.7 (Steam 681590) on Company of Heroes 2.700.2.
Scope: everything in the mod that is plain text (`.squadai`, `.ai`, `.scar`, `.lua`), read from
`BKData.sga` / `BKDataPatch.sga`. Binary attribute files (`.rgd`) need Corsix Mod Studio and were only
scanned for strings. Extracted copies live in `extracted\`.

Rule for every change below: the file must be identical on every player's machine. Squad AI, AI
personality and win-condition scripts all run inside the simulation, so a mismatch is a guaranteed desync.

## 1. Real bug, fixed: squad-AI plan that fails to load

**Symptom.** Every game since the current mod version logs, right after loading:

```
SQUADAI_ALERT: [string "Data:SquadAI/ASSAULT-INFANTRY-COMMANDOS-PLAN.squadai"]:80: '}' expected (to close '{' at line 29) near '<eof>'
SquadAI: Error loading(Data:SquadAI/ASSAULT-INFANTRY-COMMANDOS-PLAN.squadai), could not load file
```

**Cause.** In `BKDataPatch.sga`, `squadai/assault-infantry-commandos-plan.squadai` and
`squadai/assault-infantry-plan.squadai` both had a "phase4 - Final Attack" phase header pasted in
with no body and no closing brace, so the whole plan is rejected and squads using it get no assault
behaviour. `assault-infantry-plan` is referenced by 80 squad blueprints (riflemen, airborne,
engineers, tommies, sappers, grenadiers, stormtroopers, volksgrenadiers, panzergrenadiers, tank
crews and more). The patch's `.bak` of the file is the clean pre-patch version.

**Fix delivered.** `fixes\Data\squadai\` holds both files repaired. The Final Attack phase
is completed with the same body the mod uses in `assault-building-plan.squadai` (run up, throw the
faction's assault grenade, fall back), keeping each file's own grenade ability. Braces balance (15/15).
If you would rather make the smallest possible change, delete the four header lines
(`-- phase4 - Final Attack`, `{`, `type = DATA_PHASE,`, `name = "Final Attack",`) instead.

**Deploy (every player does the same, from the repo root; change `$game` to your install).** `Blitzkrieg.module` lists `Blitzkrieg\Data` as a loose data
folder ahead of the archives, so a loose file overrides the archived one. No repacking needed.

```powershell
$game = "C:\Program Files (x86)\Steam\steamapps\common\Company of Heroes Relaunch"
```

```powershell
Copy-Item -Path ".\fixes\Data" -Destination "$game\Blitzkrieg" -Recurse -Force
```

Package for the others (they unzip it into their `...\Company of Heroes Relaunch\Blitzkrieg\` folder):

```powershell
Compress-Archive -Path ".\fixes\Data" -DestinationPath ".\fixes\BK-squadai-fix.zip" -Force
```

**Verify** after one game: the SQUADAI_ALERT line for ASSAULT-INFANTRY-COMMANDOS-PLAN must be gone
from the newest log.

```powershell
Get-ChildItem "$([Environment]::GetFolderPath('MyDocuments'))\My Games\Company of Heroes Relaunch\LogFiles\designmessages.*.txt" | Sort-Object LastWriteTime | Select-Object -Last 1 | Select-String -Pattern 'SQUADAI_ALERT'
```

Not verified: whether the Blitzkrieg Launcher deletes or overwrites a loose `Data` folder on update.
Check after the next mod update. Alternative that survives any check: repack `BKDataPatch.sga` with
Corsix Mod Studio and hand out the archive.

**Open question.** The engine only reports the commandos file, never `assault-infantry-plan`, although
both are broken the same way. Either that plan is loaded from a different copy, or the error is
logged once per session for the first failure only. Fixing both is safe either way.

## 2. Settings you can tune (plain text, distributable)

### Win conditions (`scar/winconditions/`)

File names do not match what the titles say. Pick by title, not file name.

| File | Menu title | Popcap | Points |
|---|---|---|---|
| zvptickerwin_2500 | Victory Points 2500 | default | 2500 |
| zvptickerwin_4000 | Victory Points 750 with 250 Popcap | 250 | 750 |
| zvptickerwin-infonly_1000 | Victory Points 1000 Inf Only | 175 | 1000 |
| zvptickerwin-infonly_2500 | Annihilate with 200 Popcap (it is annihilate, not VP) | 200 | n/a |
| zvptickerwin-infonly_4000 | Victory Points 1250 with 250 Popcap | 250 | 1250 |
| zannihilate_200 | Annihilate with 150 Popcap | 150 | n/a |
| zannihilate_250 | Annihilate with 250 Popcap | 250 | n/a |
| zannihilate_inf | Annihilate with Infantry Only | 175 | n/a |
| zannihilate_fun | BK Fun Mode | 350 | n/a |
| zannihilate_pop | Annihilate without Popcap | 999 | n/a |

Popcap is `Player_SetPopCapOverride(..., N)` in each `.scar`; VP totals are `start_points` in the ticker
scripts. Change the number, keep the title in sync in `Locale\English\Blitzkrieg_SP.English.ucs`
(UTF-16; the titles are IDs 18011184 to 18011187, 18011265, 18015001 to 18015005, 18100028).

### AI behaviour (only matters when a player drops: `PlayerDropBehavior = aitakeover`)

`ai/personality.ai` in the patch already changed, among others: production wait 60 to 6 s, structure
wait 0 to 200, engineers with teammates 4 to 5, mine preference 10 to -5, ability avoidance 0.95
(correct, compared against a 0-1 random). `squadai/default-plan.squadai` and `assault-vehicle-plan`
were slowed from VERYFAST/FAST to MEDIUM and cover search widened (radius 6 to 12, angle 45 to 75).
If AI-controlled squads feel sluggish after a drop, those paces are the knobs.

## 3. Problems that need Corsix Mod Studio (binary `.rgd`)

- "Missing movingextinfo" every game for `flak38_squad_starting`, `88_flak_squad`,
  `bofors_aa_gun_squad` and `bofors_aa_gun_squad_starting`: the squad blueprint lacks a moving
  extension. Cosmetic in the log, but worth adding if these guns ever behave oddly when ordered to move.
- "Failed to find best target": appears in clean games too, not correlated with desyncs.

## 4. Harmless, leave alone

- `VILLERS-BOCAGE-REACTION.squadai` assert: vanilla base-game file (`WW2Data.sga`), single-player only.
- `levelingCurve.lua` not found and empty `medals\reward_*` PropertyBagGroups: vanilla engine noise.
- Multiple-network-adapter warning at startup: engine, not mod. Disabling unused adapters (VPN,
  virtual switches) before playing is still a cheap thing to try for the desyncs.

## 5. Hygiene (no gameplay effect)

- 51 `.bak` files inside `BKDataPatch.sga` (97 across both data archives); pure dead weight.
- `Blitzkrieg.module` references archives that do not exist (MOD1, DLC1, DLC2, SoundPatch, several
  locale packs); the engine skips them silently.

## 6. Relation to the desyncs

None of the above correlates with the out-of-sync games in the logs: the plan error and the RGD
warnings appear identically in clean and desynced games. The desync checklist in
`CoH-Blitzkrieg-desync-checklist.md` is still the path to the actual cause. Deploy the plan fix to
everyone before the playtests so the test runs on identical files.

Determinism audit of the scripts (2026-11-08): `CoH-Blitzkrieg-determinism-audit.md`. No cause found.
