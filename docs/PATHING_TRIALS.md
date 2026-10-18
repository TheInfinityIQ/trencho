# Gameplay 7 movement review and pathing trials

## Evidence and scope

Reviewed timestamped frames across `trencho_gameplay7.mp4` (127.6 seconds,
2556 x 1390, 30 fps), with denser samples around 35–65 and 89–119 seconds.
The repeated orders around 47–59 and 105–119 seconds motivated route-through-
formation and whole-point trials. Visible firing is not by itself a pathing
failure. The recording does not contain an authoritative input/state trace, so
these are reproducible related workloads, not a claimed exact replay.

The previous fix released vacated territory correctly, but mostly exercised
already-spawned troops receiving direct Defend orders. New no-enemy physics
probes reproduced additional route/loop and stationary-rank failures.

## Changes

- Include queued members when deriving route offsets. New purchases and orders
  issued during entry no longer funnel every unspawned member through one point.
- Retain 45-pixel passage for clear waypoints. Within three body clearances (including the steering probe), treat
  an occupied guide or a body-blocked approach as passed instead of requiring a
  soldier to enter another body or squeeze into an irrelevant waypoint pocket.
  This changes route progress only; every actual movement step still checks
  occupancy and terrain.
- Measure real forward displacement before recovering from a stall. A bounded
  1.5-second sidestep is considered after 0.75 seconds without adequate progress,
  for terrain, stationary defenders, or mutually stalled neighbors. Stable
  soldier IDs establish right of way so both neighbors do not reverse together.
  Keep the passing side until the approach clears the obstruction. Reset
  recovery when a new order arrives and keep defenders inside field bounds.
- Preserve normal strategic/tactical speeds, body sizes, damage, combat stopping,
  cohesion and territory restrictions. No teleportation, collision bypass,
  population caps or forced casualties are used to make arrival succeed.

## Recovery work budget

Angle-only recovery still left isolated soldiers looping in some seeded cases.
Persistent stalls can now request a local recovery path from one shared service.
It scans a bounded 49 x 49 grid at 40-pixel spacing, with cached terrain and current
body clearance, incrementally: at most 128 cells per physics tick, targeting 2 ms
of scan work. Only one job is built at a time; the queue is capped at 32 requests.
The native A* search runs after the scan and is bounded by that grid size. The
2 ms scan target is not a promise that every complete slice, including the native
search or OS scheduling, fits 2 ms; measured maxima are saved in each report.

Jobs keep weak unit references and an order generation. Replaced orders and dead
units cancel stale work. Every followed step still checks current occupancy and
terrain; a path blocked by changing traffic is discarded and can be requested
again. Tactical closing retains its cohesion restrictions. Successful installed
soldier paths are counted in the active order's `repath_count` combat telemetry.

Capturing troops also use collision-aware movement at the existing capture speed;
the old direct movement branch could overlap other troops after route completion.

## Running trials

Main menu → **Pathing trials** starts 13 scenarios across three seeds (39 trials)
in a background Godot process. Seeds vary placement and alternate teams. Choose
another range to repeat. **Open results** opens the saved JSON report folder.
Returning to the menu stops that page's worker; an incomplete run is not a pass.

From PowerShell:

```powershell
.\tools\run_pathing_tests.ps1 -Seed 16102026 -Repetitions 3
.\tools\run_pathing_tests.ps1 -Seed 16102026 -Repetitions 1 -Case mass_route
```

`tools/verify.ps1` includes two seeds (26 trials) by default. The command-line
runner exits unsuccessfully for failed trials, engine errors or a missing pass
marker. Exported-game menu workers use the same normal physics runner.

Scenarios: unobstructed Advance; queued direct defense; queued route plus loop;
stationary friendly rank; whole-point release along a curved route; whole-point
route/loop relocation; reinforcement into occupied territory; crossing orders;
reorder during entry; field-edge routing; terrain detour; 72-soldier mass route;
and a sealed destination that explicitly must remain blocked.

Each arrival phase requires the specified number of members, with individual
route completion remembered before any scoring exit. A missing, unspawned or
lost soldier cannot make a phase pass. Defensive arrival also requires the
assigned home, established status and Defending state. Motion/bounds are checked
each physics tick; body and terrain overlap are sampled every six ticks. Frozen
blockers must stay put. These are sampled checks, not a proof of all continuous
collision behavior.

Reports record seeds, sides, per-stage arrivals/deadlines, motion/overlap failures,
and the final eight one-second snapshots on failure, including unit IDs, squad
IDs, positions, current route targets, route indices, homes, recovery state and work-budget metrics. Repeat the named
case with the saved seed. Seeds reproduce fixtures; exact physics trajectories
are not promised to be bit-for-bit deterministic. Reports live in `user://pathing_tests/`.

## Limits

Combat is disabled in these trials to distinguish movement failures from firing
or tactical pursuit; existing combat and battle tests provide separate coverage.
Bounded local steering handles ordinary travel, with bounded local recovery for persistent stalls. Sealed destinations intentionally stay
unreached, and these trials do not establish general maze navigation. No exact
video-input replay or target-platform export is claimed.

## Validation: 18 October 2026

The exact staged source snapshot passed all default verification suites on
Godot 4.7.2.stable.steam.ed1daf0bf. This includes eight recovery lifecycle/budget
assertions, the existing 144-soldier defense regressions, command/combat/input
checks, matching 30/144 render-FPS simulation snapshots and startup smoke.

The default verification run's 26 pathing trials plus 13 trials for seed 16102028
all passed: 39/39 across seeds 16102026–16102028, including three explicitly
expected-blocked cases. Sampled body overlaps: 0; invalid motion samples:
0. Largest observed recovery slice across those runs: 1981 microseconds;
maximum scanned cells in one physics tick: 128. These are measurements from
this machine and workload, not platform-wide performance guarantees.

The sustained battle completed with 57 deployments, 370 deaths, 100 scoring
events and 164 peak living soldiers. The trial page was also rendered and its
live results inspected. Related UI/input checks passed with the user's existing
uncommitted UI work present; that work is excluded from this change.

A stationary-rank probe against the previous commit (732f15f) failed with 0/12
arrivals, confirming that the added trial catches an actual earlier failure.
No interactive gameplay replay of the exact video inputs or export is claimed.
