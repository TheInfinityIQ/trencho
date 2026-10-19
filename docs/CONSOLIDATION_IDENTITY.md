# Consolidation & identity pass — 0.5.2

Implemented against package 007 v0.1, the player's shield/approach clarification,
and Godot **4.7.2 stable** (`ed1daf0bf`). Baseline source: `28cd680`.
This is a stabilization build. Cards, economy, AI strategy, scoring, territory,
map size, reserve doctrine and reinforcement fit rules remain as implemented.

## Player interaction

- A terminal Defend loop creates a new point facing the enemy deployment side.
  Its tangent cannot rotate the front. No facing control was added.
- An open route reinforces only if its endpoint hits a friendly shield within
  **14 screen pixels**, converted through camera zoom. Visible inbound anchors
  count. Enemy anchors do not. Crossing a front or ending elsewhere in owned
  territory remains Advance.
- Shield = intent; recent approach = spatial preference. Walk back up to four
  defensive spacings along the gesture, including its starting knob. Project
  that sample onto the point's lateral axis. A centered sample (deadzone: the
  larger of 0.75 spacings or 15% of frontage width), or an approach shorter than
  half a spacing, defaults to center. Other samples prefer the left/right edge,
  clamped to existing usable frontage. These broad preferences feed the existing
  gap/edge/reserve planner; they do not add a placement exception or sector manager.
- Movement still uses the original waypoint route. Approach metadata does not
  redirect soldiers to the sampled preference point.
- Drawing previews Advance, new defense, Reinforce, invalid commands and proposed
  FRONTAGE/RESERVE placement. Reinforce also names LEFT/CENTER/RIGHT. Purchase,
  selected-squad and drawn previews use the same planner as accepted orders.
- Every legal affordable card package opens with a functional blueprint. Manual
  edits remain available and persist while the blueprint is open. Opening a new
  package recomputes its default instead of inheriting an undersized old shape.

## Findings and evidence

### Defender engagement: candidate not reproduced; exact video event unresolved

`consolidation_combat_test.gd` uses real Area2D overlap updates, established FRONT
and RESERVE soldiers, both teams and all three current unit types. It steps the
normal unit physics method at controlled cooldowns and tests distances 300, 600,
690, 740 and 900. Every detected ready target received a shot, health loss and
matching damage telemetry. The final combat suite passes **238 assertions**. Cooldown correctly explains the next non-firing step.

Observed type/range differences make apparent visual proximity insufficient:

| Unit | Configured ranged radius | Observed firing distances in fixture | No detection at |
| --- | ---: | --- | --- |
| Rifle | 650 | 300, 600, 690 | 740, 900 |
| Conscript | 585 | 300, 600 | 690, 740, 900 |
| Assault | 400 | 300 | 600, 690, 740, 900 |

Detection uses actual shape overlap, including enemy body extent, rather than a
strict center-to-center comparison with the ranged radius. No damage, range,
cooldown or targeting rules were changed. `engagement_snapshot()` and telemetry's
`inspect_engagement()` expose state, role, candidates, chosen target, distances,
range, masks, cooldown, fire-method entry, shot and reason on demand. They do not
add an ordinary-play target search.

Video 9 was sampled into contact sheets for visual context; this was not a
frame-by-frame input replay. Its precise apparently idle soldier cannot be
identified from a deterministic save/input trace. The tested sustained-idle
contradiction is falsified for these conditions; the specific recorded event
remains unresolved (classification E), with range/readability a supported
explanation in the reproduced out-of-detection cases. Do not describe the video
incident as a proven fixed targeting bug.

### Reserve waves: confirmed in live automatic combat

A normal enemy shot kills a frontline soldier in a 16-defender, eight-file point.
The vacancy starts the existing three-second timer. One reserve is assigned
3.0167 simulation seconds after the casualty and physically walks to the vacant
home; seven unused reserves remain behind. Assignment and arrival are separate
observations. Existing heavy-loss, depleted-front and consolidation regressions
also remain covered by the defensive-front suite. No reserve rule was changed.

New background events record vacancy changes, wave start, member assignment and
block classification/geometry. Point samples include timer, vacancies, available
reserves and physically arrived frontage. Gesture/result events record intent,
anchor classification, preferred sector and rejection. Ordinary completed
battles still save telemetry automatically; developer snapshots remain optional.
See [combat snapshots and live wave timeline](validation/consolidation_combat.json).

### Dense friendly crossing: performance defect confirmed and reduced

Fixture: 144 moving soldiers and 48 established same-team defenders, compared
with the same population and mover route with defenders positioned away from it.
Both cases run 1,200 automatic 60 Hz physics ticks, excluding 180 warmup ticks.
Rendered runs use Vulkan Forward+, 1280×800, VSync disabled and a 120 FPS cap;
normal simulation/telemetry/UI remain enabled. Hardware: i7-13700F, RTX 4070 Ti.

Repeated `living_members()` allocations/scans occurred for every defensive slot,
in physics and drawing. A bounded cache now stores weak member references and
checks alive state, squad identity and member index before reuse. It handles
casualty/transfer invalidation without retaining units or changing slot ownership.

| Isolated rendered run | Open mean / p95 / max (ms) | Crossing mean / p95 / max (ms) |
| --- | --- | --- |
| Before lookup fix | 48.17 / 136.50 / 190.13 | 95.17 / 146.80 / 171.41 |
| After lookup fix | 15.35 / 29.14 / 33.48 | 18.89 / 32.63 / 34.95 |
| Final repeat | 15.47 / 30.35 / 32.94 | 17.49 / 30.78 / 34.40 |

Final-repeat engine physics monitor means were 14.35 ms (open) and 14.75 ms
(crossing). It corroborates the reduced crossing differential.

The separately instrumented CPU probe reduced front bookkeeping from roughly
1.17 to 0.24 ms per crossing tick; unit simulation from 10.57 to 8.79 ms.
Those initial CPU timings are indicative: the first run overlapped other checks.
Nested timers must not be summed. The large rendered improvement is consistent
with reducing physics catch-up work and repeated drawing lookups; the exact split
between drawing and catch-up is an inference, not separately measured GPU time.

Residual crossing cost is identified: body congestion and bounded recovery.
Crossing/open maxima were 61/30 steering stalls; recovery requests 97/46; installed
paths 24/35; peak movers in the measured occupied corridor 38/91. These counts
remain unchanged by the cache. The 192-unit stress case can still exceed a 16.7 ms
frame budget. This is a measured hitch reduction, not a guaranteed 60 FPS claim
or proof that the original video workload was identical.

[Archived measurements](validation/consolidation_crossing.json) include physics,
body/terrain checks, recovery counts, population and percentiles with explicit
units/limitations. Initial CPU field-name corrections are documented there.
Reproduce using `tools/profile_friendly_crossing.gd`: `--cpu` for headless phase
measurements, or rendered `--uninstrumented` for ordinary gameplay timing. Do not
run timing comparisons concurrently with other games/tests. Profiling is opt-in.

## Validation and ordinary-play build

- Full `tools/verify.ps1 -FreshImport`: all suites passed, including 26 movement
  trials, 83 defensive-front assertions, sustained battle and matching 30/144 FPS
  simulation snapshots.
- Separate `tools/run_pathing_tests.ps1 -Repetitions 3`: **39 trials passed**,
  seeds 16102026–16102028, both teams covered, including whole-point relocation,
  queued squads, obstructions, dense routes, reinforcement and expected blockage.
- Consolidation command suite: **221 assertions**, including shield tolerance,
  owned-area Advance, enemy exclusion, all affordable legal package defaults,
  broad approach sectors and exact preview/commit home equality.
- Exported release: a developer-only `--build-smoke` worker uses the actual Play
  button and exported card/map resources, accepts the default blueprint, buys a
  squad, checks enemy-facing defense and saves completed-battle telemetry. The headless run passes nine checks; the rendered run passes 12, including
  screenshot saves. Menu/blueprint captures were inspected at 1280×800 and the
  overflowing help line was shortened. Normal startup does not run that worker. The build tool requires its completion marker.

`tools/build_windows.ps1` requires the pinned editor and matching Windows templates.
It creates `.test-results/builds/Trencho-0.5.2-consolidation/Trencho.exe` and its PCK,
README and build manifest; the ZIP sits beside that folder. The manifest records
source commit/tree, dirty state, engine and SHA-256 hashes. Final handoff is rebuilt
from the committed source. Launch the EXE and choose Play; no test harness, forced
AI doctrine or developer overlay is needed. The version appears on the menu.

Export warnings about pre-existing legacy scene UIDs fall back to their valid
text paths; the export and actual release Play smoke complete. Legacy assets were
preserved rather than removed during this pass.

## Deferred identity decisions

Manual editing and explicit front geometry remain on probation. Evaluate the
cleaned build before changing them. Keep the existing map, territory ownership,
Line/Triangle doctrines, Rout and Breakthrough.

Record for later design review: territory-generated fronts, card/squad cascades,
optional formation mastery, and autonomous assistance under asymmetric pressure.
Defensive positions should eventually react to that pressure with less micro
while preserving understandable consequences. No global rebalance, cover bonus,
new tactical AI, campaign/store system, card or map expansion was implemented.
