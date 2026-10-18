# Maintenance and entry-formation verification — 2026-10-17

## Scope and baseline

Base commit: `4c9c191881ec49275c119be8470731581f1f4f78` on `main`, initially clean. Results below cover that commit plus this maintenance working diff, not an unmodified release artifact.

The supplied `001_Trencho_AI_Software_Engineer_Project_Brief.md` requests the entry-formation/reinforcement-pressure iteration. That behavior was already implemented at the base commit. This pass preserves it, adds repeatable verification, and aligns economy, logistics and enemy decision updates with unit physics. No combat stats, Command costs, Mojo effects, resource schemas or save formats were changed.

## Delivered

- Battle simulation explicitly runs at 60 physics ticks/second. Camera and interface updates remain on the render clock.
- Tests that manually drive a battle now disable its automatic physics callback as well as its render callback; their existing gameplay assertions remain intact.
- `.godot-version` pins verification to 4.7.2 stable. `tools/verify.ps1` checks this version, imports assets, runs suites, compares 30/144 FPS snapshots and starts the main scene headlessly.
- Verification rejects nonzero exits, logged engine/script errors, missing completion markers and wall-clock timeouts. Fresh-import mode uses current Git-visible source without the existing import cache.
- GitHub Actions downloads the pinned official Windows editor, verifies the published SHA-512 checksum and invokes the same runner. The workflow has read-only repository permission and uploads logs; it does not deploy.
- Four tracked editor recovery files were removed from the index and preserved locally. Future `.tmp` files and `.test-results/` are ignored. A root README explains setup, verification and project structure.
- Legacy implementations remain for a later reference-aware cleanup; no broad rewrite was needed.

## Execution evidence

Environment: Windows, Steam Godot `4.7.2.stable.steam.ed1daf0bf`, PowerShell 7.

1. Before changing the clock, the new regression failed with exit 1: render callbacks regenerated Command and advanced logistics; fixed physics windows did not produce the expected logistics time. This establishes that the regression detects the prior clock coupling.
2. After the change, a complete uncached import and suite run passed:

| Suite | Assertions / observed result |
| --- | --- |
| Reinforcement flow | 143 passed |
| Formation | 266 passed |
| Combat/input | 18 passed |
| Combat readability/capture | 150 passed |
| Camera | 19 passed |
| Simulation clock | Initially 9 per run at 30 and 144 render FPS; matching snapshots |
| Sustained battle | 36 enemy and 46 player deployments, 417 deaths, 127 scoring events; peak 136 units; exit 0 |
| Main-scene startup | Headless startup, exit 0, no logged errors |

3. After explicitly recording the existing 60 Hz default in project settings and adding a corresponding assertion, a second uncached targeted run passed: 10 clock assertions at each render rate, identical snapshots, 143 reinforcement assertions and startup smoke. The other gameplay suites were unchanged after the complete run. The current combined coverage is 616 assertions across the five gameplay suites and two clock runs; no assertion count includes the soak or smoke checks.
4. Controlled failure injections were performed only in the disposable source copy. The runner rejected an exit-0 script with no completion marker, an exit-0 script emitting an error and a success marker, a process timeout during import, and an incorrect version pin. The modified disposable fixture and version file were restored afterward.
5. The workflow's official download URL responded successfully, and its checksum filename selector matched exactly one Windows archive entry in the published checksum file. GitHub-hosted execution remains unverified until the workflow is pushed and run.

Complete command: `pwsh -File tools/verify.ps1 -FreshImport`. Final targeted command from PowerShell: `./tools/verify.ps1 -FreshImport -Suite simulation_clock,reinforcement_flow`.

Local logs are retained in ignored `.test-results/`. The baseline failure log was captured outside the game repository in the current chat workspace.

## Brief acceptance coverage

- Exact rectangles, red rejection state, no automatic resizing/moving, atomic rejection without spending: formation and combat/input scenarios.
- Off-field entry, frontage and relative rank geometry, vertical-placement invariance, no destination travel, edge activation: formation, reinforcement and clock scenarios.
- Combat during entry and resumed advance: reinforcement and combat readability/capture scenarios.
- Enemy startup waits for an accepted player order; invalid/unaffordable orders and discards do not unlock it; restart resets it: reinforcement scenarios.
- Local slot exclusion and surviving distant slots, blocked-file waiting and reservation release: formation and reinforcement scenarios.
- Queued, entering, active, engaging and logistics delay inspection: reinforcement scenarios and inspected HUD/unit readout code. Capture, exit and scoring behavior: combat readability/capture scenarios.

Automated coverage does not establish visual readability, strategic formation value, perceived congestion or improved balance. Those remain player-observation checks.

## Next gameplay check

Repeat a comparable battle using wide/shallow and narrow/deep formations, an emergency Assault deployment and a 24-unit Mojo Conscript wave. Inspect F3 Incoming/Queued/Entering/Active counts and watch for entry overlap or prolonged waiting. Compare overwhelm and reinforcement delay before changing HP, DPS, card costs or Mojo again.

No store export, public release, gameplay playtest or GitHub Actions run is claimed by this record.

## Follow-up: clear rejected formation on release

The user's subsequent bug report supersedes the older brief's persistent editable rejection rectangle. Invalid geometry remains exact and red during drawing; a rejected confirmation now clears both drawing flags and preview nodes. Cards stay selected, Command and cards are preserved, and the rejection remains explained in the hand message. This prevents periodic preview updates from reviving the box after release.

The input regression reproduced the lingering preview before the fix (exit 1), then passed after it. It exercises release on the battlefield and over the HUD, a later preview refresh, preservation of selection/cards/Command, and a subsequent valid deployment. Formation assertions were updated to reflect this requested behavior change rather than the superseded persistent-box contract.

## Investigation: occupancy after reservation

Investigated the user's hypothesis that later occupancy cancels some already-paid reinforcements. On Steam Godot 4.7.2, the controlled scenarios did not reproduce lost queue entries. No production queue/spawn logic was changed.

Added 50 reinforcement assertions covering both teams:

- An enemy occupies a drawn formation slot after acceptance: all six purchased soldiers still spawn at their off-screen entry points.
- A friendly or enemy body occupies an entry point after acceptance: five clear files spawn, and the sixth soldier remains queued with its original reservation through three seconds of retries. Moving the blocker away releases that same soldier exactly once with no extra charge.
- Two separate drawn rectangles translate into the same entry files: movement eventually allows both complete six-soldier formations onto the field and releases all reservations.
- Terrain appears at an accepted entry point: only that file waits, and removing the terrain releases its queued soldier.
- A deep 24-soldier Mojo Conscript formation drains its queue and releases all reservations as soldiers advance, at the original combined cost.

The first deep-wave fixture only had 12 legal slots, so validation correctly rejected it. The fixture was corrected to provide 24 slots before testing queue completion. That initial failure was a test setup error, not observed loss of an accepted order.

A fresh-import run passed reinforcement (193), formation (264) and combat/input (29): 486 assertions total, plus startup smoke. Only these affected suites were rerun for this investigation. The tests remain in `tests/reinforcement_flow_test.gd`.

Important limitation: a real physical entry blockage has no timeout, rerouting or refund. It can keep a purchased soldier queued as long as it remains occupied. A soldier already spawned can also remain Entering behind congestion/terrain, or die before fully entering. These can look like missing reinforcements but are different from a dropped queue entry. Drawn reservation rings do not reserve actual off-screen entry points across different orders, so distinct rectangles may contend for the same entrance. The tests establish recovery for the scenarios above, not absence of every possible live battle stall.

For a recurrence, inspect F3 Queued versus Entering and cumulative Dead, then pan behind the home edge while debug is open. A positive Queued count indicates soldiers waiting to spawn; Entering indicates spawned soldiers not yet fully on the field. Record the blocker and formation shape before changing queue rules. No live reproduction of the user's particular case was observed here.
