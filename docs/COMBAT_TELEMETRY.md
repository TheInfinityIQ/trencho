# Combat telemetry

The current build exports schema **0.2**. See [packet 005 changes](NEXT_PASS_005.md)
for closing, friction, deletion diagnostics and mirror-mode additions. Historical
validation evidence below describes the original v0.1 implementation.

Completed matches automatically write one JSON file to `user://combat_logs/`.
On Windows with the current project settings this is
`%APPDATA%/Godot/app_userdata/Trencho/combat_logs/`.
The debug result screen offers **Open combat log folder**, **Copy match summary**,
and **Save / retry combat log**. Saving again after success does not create another
file. An incomplete write stays a `.tmp`; only a successful write is renamed to
`.json`. An unsuccessful export is shown on the result screen and can be retried.
Restarting or quitting an unfinished match does not create a completed-match log.

No unit, card, modifier, economy, AI, or movement balance values were changed.

## Evidence collected

- Match identity, build, seed, actual map scene, simulation and real durations,
  final scores, winner and end reason.
- Actual starting unit definitions, modifier operations, and tuning values.
  Each package retains ordered cards, Command cost, resolved component stats and
  composition. Each spawned soldier also records its randomized interval and speed.
- Stable match-local soldier, squad, defensive-point and movement-order IDs.
- Timestamped attacks, applied damage, overkill, killer/victim provenance, deaths,
  scoring, orders, target/state transitions, point breaks and absorption, routs,
  breakthrough grants/refreshes, and AI deployments/assignments.
- Soldier counters aggregated by squad, component, and **team plus unit type**;
  an attacker-type/target-type matrix; card/modifier outcome associations.
- Command generated/spent, exact overflow, time at cap, opening and later player
  draws, committed card counts, and deployment package counts. AI has no draw pile,
  so its draw count is `null`.
- Movement-order history and low-frequency centroid/cohesion samples, stuck
  transitions, arrival or termination reasons. Defender population/area/capacity
  samples, point combat totals, rout casualties/damage/distance and recovery.
- AI doctrine, actual decision reason, chosen cards and available Command;
  subsequent establish/reinforce/advance assignments, and sampled doctrine counts.

## Definitions and limits

Use the JSON's `measurement_notes` alongside this document when analyzing it.

- Gameplay events use **simulation seconds**, advanced by the same physics delta
  as economy, combat and AI. Planning slowdown therefore changes wall time but
  does not inflate firing rates. Time totals are **soldier-seconds**, not squad
  wall-clock lifetime. `spawn_time`/`end_time` provide the latter.
- `damage_dealt` and `damage_received` count HP actually removed, excluding
  overkill. `damage_attempted` includes the actual rout/breakthrough multipliers.
  Current attacks are instantaneous guaranteed hits; attempted/completed attacks
  coincide and misses/projectile speed are not applicable. External damage has
  no invented attacker. Healing is reported separately.
- `time_actively_attacking` is time in an in-range firing engagement, including
  cooldown. It is not the sum of instantaneous shot durations. Time with no
  target in range includes advancing and idle defense. Closing time requires an
  actual selected target; it does not search for hypothetical enemies or infer
  why a unit is idle. State/target durations are measured at physics resolution.
- `initial_composition` is the resolved package, which can include queued members.
  `soldiers_deployed` counts soldiers actually spawned. `final_composition` counts
  members remaining on the battlefield; scored departures also count as survived.
  Unit-type cost is attributed as its Unit-card cost plus its proportional share
  of modifier cost, using resolved body counts. Cost associated with members still
  queued at match end remains visible in the package's full Command cost.
- Mixed component and unit-type totals partition soldier contributions. Modifier
  outcomes describe the whole modified package and are **not causal estimates**
  or additional damage to add to the unit totals.
- `actual_distance_travelled` in an order is sampled centroid distance, comparable
  to the requested route length. `soldier_distance_travelled` is the sum of exact
  member displacements. Cohesion and point/doctrine population averages are
  sampled approximations, not continuous integrals.
- A stuck order is one whose centroid moves less than the configured threshold
  per sample for the configured duration, excluding firing, retreat and arrived
  defense. This is a heuristic, not a claim that navigation failed. Arrival uses
  the game's route progress/defense-established state. An open-ended Advance has
  no waypoint arrival; it closes on departure, destruction, replacement or match
  end. Superseded paths are retained. Ordinary travel uses local steering;
  `repath_count` counts successfully installed per-soldier local recovery paths
  while that order remains active. Cancelled/failed recovery jobs do not increment
  it. Order replacement creates a new order ID. See [Pathing trials](PATHING_TRIALS.md).
- Breakthrough reports actual healing, unused budget, capped duration and refresh
  identity. Current gameplay has a damage multiplier and **no fire-rate bonus**;
  telemetry accurately reports zero for the latter. Future abilities should pass
  their source identifier and attacker through `Unit.apply_damage`.

## Controls and runtime cost

`BattleTuning` exposes `telemetry_enabled` (default true),
`telemetry_sample_interval` (default 1 simulation second),
`stuck_distance_threshold` (default 10 world units per sample), and
`stuck_time_threshold` (default 2 simulation seconds).

There is no per-frame disk I/O, transform stream, navigation search or gameplay
RNG call in the logger. Soldier counters update during existing physics work;
cohesion samples are sparse. Exact important events are retained in memory and
serialized once at completion. Consequently very long matches grow memory/log
size and may pause briefly at end-of-match export; this prototype does not yet
stream events to disk or support interrupted-match recovery.

`tools/profile_telemetry.gd` compares the deterministic 144-soldier/six-point CPU
workload with logging enabled or `-- --logging-off`. Run each in a fresh engine
process (reusing a physics world in-process contaminates the fixture). Compare
the printed gameplay snapshot hashes as well as timings. A measured development
run added about 1.3 ms per simulated step; this is a CPU fixture, not a player FPS
claim or a guarantee on other hardware.

## Validation and remaining packet scope

`tools/verify.ps1` includes `combat_telemetry_test.gd`. It checks actual definitions,
damage/overkill/kill reconciliation, stable identity, target-pair aggregation,
movement/stuck/arrival/replacement, mixed package costs, Command overflow, point
break/rout linkage, breakthrough refresh/heal budgets, JSON roundtrip, simulation
duration, monotonic events and idempotent export. The existing suite exercises
normal input, sustained combat, movement and 30/144 FPS simulation equivalence.

This implements the packet's minimum telemetry foundation plus the additional
combat, path, point, rout, breakthrough, economy and AI instrumentation above.
Some proposed analyses remain derivable from raw events rather than precomputed
fields: damage by casualty fraction, next-point-break while buffed, package
efficiency, and score per Command. Detailed ability/artillery instrumentation is
future scope because that gameplay does not exist yet. Point lifecycle/capacity
history and doctrine counts are sampled; short-lived intermediate states between
samples can be absent, while explicit break/absorption events are exact.

**Required next playtest:** record a completed human match and retain that exact
match's JSON. Spot-check visible deployments, final score, casualties, and Command
spend against the recording before using the data for balance decisions. Automated
checks and the sustained battle do not substitute for that manual video check.

### Verification evidence (2026-10-18)

Godot 4.7.2 stable: clean-import verification passed all 1,591 assertions,
startup, sustained battle, and matching 30/144 render-FPS snapshots. The sustained
battle ended after 163.533 simulation seconds with 125 packages, 1,020 spawned
soldiers, 798 deaths, and player/enemy score 100/0, matching the preceding build's
battle outcome. Its export held 17,289 events in 5.38 MiB.

`python tools/validate_combat_log.py MATCH.json` independently validated that
export's Command conservation, package spend, score events, nonnegative damage,
monotonic event times and soldier/squad/unit-type aggregation. No recorded human
match has yet been manually spot-checked.
