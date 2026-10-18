# Packet 005: mechanics, diagnostics, and mirror tests

This pass preserves all three base Unit cards, modifier values, Command rates,
the one-second minimum AI deployment cooldown, map width, doctrine population
targets, and uncapped Defensive Point population. The packet's single-match
findings are hypotheses and comparison baselines, not established balance rankings.

## Mechanics

Squads expose a living member's current firing contact. A short-range member
first checks its own weapon overlaps, then squad contact and the shared combat
neighborhood. Tactical closing assigns the target explicitly and uses that
soldier's modified native speed. Its preferred firing position and each steering
step must remain within the moving squad centroid's cohesion leash. The prior
interception exception no longer bypasses the leash. Strategic travel still uses
the slowest living member. Defenders retain their territory movement restrictions
and can return fire across the territory boundary.

The old code already contained a closing branch: zero closing telemetry alone
did not prove that no closing occurred. That branch failed to expose the target
to the logger. The revised behavior and diagnostics are tested together rather
than treating the packet's inferred explanation as a proven root cause.

Clicking a friendly shield/anchor selects its established living squads, excluding
entirely inbound squads. Aggregate selection emphasizes the area and anchor and
suppresses bright per-member selection rings. Clicking an individual soldier
returns to squad selection. A shared open route releases the selected squads;
route plus loop relocates them. An old point persists if it still has inbound
or remaining assigned soldiers.

Mass routes receive per-squad lateral lanes, ordered by current lateral position,
with bounded individual offsets retained. Lane waypoints stay within battlefield
bounds. Inbound defenders receive nearest available homes from their approach
sector. Settled homes are reserved before inbound slots, reducing center-first
crossings and unnecessary reshuffling during reinforcement. This is local steering
and distributed destinations, not a new global pathfinder or a guarantee that
all congestion is resolved.

## Telemetry schema 0.2

Existing counters remain available. Additions include:

- explicit tactical target acquisition, closing starts/completions/aborts, closing
  distance, and component forward/lateral position samples;
- `NO_RELEVANT_ENEMY`, `RELEVANT_ENEMY_OUT_OF_RANGE`,
  `RELEVANT_ENEMY_IN_RANGE_COOLDOWN`, `ATTACKING`, and
  `MOVING_TO_TACTICAL_POSITION` time counters;
- signed and positive route progress, backtracking distance, progress efficiency,
  moving friction events/time, and mean/median sampled efficiency on order end;
- point-break survivors, established/inbound populations, living assigned squad
  IDs/count, authoritative break cause, and explicit deletion reasons;
- mirror configuration, both doctrines, side-tagged AI decisions, and a forced
  surrender record when applicable.

`PATHING_FRICTION` is distinct from stationary stuck. Defaults are motion greater
than 10 world units per sample, progress efficiency below 0.35, sustained for two
simulation seconds, excluding firing, retreat, and arrived defense. These are
exposed diagnostic thresholds, not movement rules. Signed progress measures change
in distance to the current waypoint; completed waypoint changes are not counted as
an instantaneous jump. The positive-progress/distance ratio and signed sampled
efficiencies have different meanings; neither proves a navigation defect alone.

Observational duration/distance counters update per soldier and roll up to squad,
component, and unit type at export. Combat/economy event totals remain live. This
avoids repeating every per-step counter update in four dictionaries. Do not treat
intermediate in-memory squad duration counters as final aggregates.

`tools/validate_combat_log.py` accepts schemas 0.1 and 0.2. Existing 0.1 logs remain
readable. A completed human recording plus its exact JSON still needs a manual
spot-check before changing unit stats.

## Menu and mirror test matches

Startup now offers **Play** and **Mirror test match**. Play starts the normal
battle. The battle toolbar includes **Menu**.

Mirror mode launches these three independent matches in parallel:

1. Wall versus Wall (`LINE` internally): left/right positions prioritized, then center.
2. Wall versus Triangle.
3. Triangle versus Triangle: forward center prioritized, then the sides.

Both sides use the same controller code, equal economy, matching initial AI random
streams, mirrored anchors, and the same shuffled package-template policy. This
means equal decision rules, not forced identical moves after their battlefield
states diverge. The existing seeded soldier stat variance is preserved. Match
conditions and seeds are exported.

The AI has no player-style draw/discard deck. It now cycles through a shuffled bag
of Rifle, Conscript, Assault, Rifle+Conscript, Rifle+Assault, and Conscript+Assault
templates, occasionally adding one affordable compatible modifier. It saves for
the selected package instead of always spending the next three Command on Rifle.
This provides composition diversity; neither randomized templates nor stat
variance guarantees that a stalemate ends.

At 1,800 simulation seconds, the side with lower score surrenders; tied scores use
the seed to alternate the selected side without consuming gameplay RNG. Its queued
reinforcements are cancelled and its soldiers withdraw. Withdrawals are not kills
or score. The remaining side releases its defenses and uses normal Advance and
scoring. The forced result is labeled `timeout_surrender`, not a natural win.
A further 120-simulation-second safety limit is separately labeled if normal
scoring still fails after withdrawal. This keeps forced outcomes distinguishable
from balance evidence.

The progress screen can open the results folder or cancel back to the menu.
`user://mirror_tests/<batch>/batch_summary.json` references each completed match's
normal `user://combat_logs/` export. Results explicitly distinguish natural wins,
surrender results, failures, and incomplete budget-limited attempts.

## Speed and reproducibility

Workers use the actual `main.tscn` battle, actual Area2D weapon overlaps and
CharacterBody2D movement, and the normal 60 Hz physics loop. `--fixed-fps 60`
advances fixed simulation frames as fast as the CPU can execute them. There is no
enlarged combat timestep, approximated damage model, or skipped combat period.
Rendering, smoke creation, and presentation updates are disabled in workers.
Each match gets a fresh process/world to avoid contamination from previous worlds.

Spatial combat-neighborhood queries reuse the existing exact body grid and
pending reinforcement counts are maintained incrementally. Nearby candidates
retain spawn order. These optimizations are shared by normal and mirror play.
They do not introduce a cheaper alternate combat model.

From PowerShell:

```powershell
./tools/run_mirror_tests.ps1                       # the three requested matches
./tools/run_mirror_tests.ps1 -SecondsBudget 60     # as many complete games as fit
./tools/run_mirror_tests.ps1 -SecondsBudget 60 -Seed 42
```

Budget mode keeps up to three workers running, cycling the three pairings with
new seeds each round. At the wall-time deadline, unfinished workers are stopped
and recorded as incomplete; they are never counted as wins or completed games.
Returning to the menu cancels only workers created by that test screen.

A fixed-step parity probe is available through the worker's `--probe=SECONDS`
option and `--presentation=true`. Compare `snapshot_sha256` in otherwise identical
rendered and headless runs. This validates the sampled state on this engine/build;
it is not a claim of bitwise determinism across Godot versions, operating systems,
all hardware, or arbitrary human input. Wall-clock speed depends on army size and
CPU. Three worst-case 30-minute matches in under five real minutes is an aspiration,
not a guaranteed throughput target.

## Verification evidence — 2026-10-18

- Godot 4.7.2 stable, clean import: **1,731 assertions passed**, plus startup,
  matching 30/144 render-FPS simulation snapshots, and the 180-second sustained
  battle check (951 deaths, 74 score events). The sustained check was still active
  at its 180-second stop; it is not claimed as a completed match.
- The final contact parity fixture used real physics and exercised 5,020.5 applied
  damage, casualties, and 45.2333 soldier-seconds of tactical closing. Rendered and
  headless snapshots matched exactly (`ba9b085d5f57e0a86ff4229d70fcd07a5a89dcd79849dcf232ef96611401b063`).
  `tools/mirror_parity_probe.gd` reproduces this short synthetic contact scenario;
  use `--presentation=true` for the rendered variant and compare its output hash.
- Final isolated one-minute batch: **0 completed matches** in 60.052 real seconds.
  The three unfinished attempts reached approximately 102.45, 102.83 and 113.33
  simulation seconds. They were retained as incomplete, not forced results.
- A longer development batch completed all three pairings naturally, without the
  30-minute fallback, and all three exports passed independent log validation.
  That run took 823.701 real seconds under development/test load and preceded the
  final arrival-allocation correction; it is not a controlled performance result
  for the final build or evidence that the five-minute target is achieved.
- A separately labeled short-limit integration fixture exercised all three
  surrender/withdraw/normal-score/export paths. Its artificial one-second limit
  is test coverage, not a balance result.

The under-five-minute preference is **not met or guaranteed**. Preserve full
physics fidelity when interpreting these logs; reducing the number of physics
steps or substituting aggregate DPS would change the experiment. More CPU and
movement/physics optimization is needed for high-volume, minute-long batches.
