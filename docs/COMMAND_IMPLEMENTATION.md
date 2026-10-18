# Squad Command & Planning v0.1 — implementation record

## Scope

Implemented the supplied 002_Trencho_Squad_Command_Planning_Gesture_System_v0.1 brief in the existing prototype. Baseline Git commit remains 4c9c191; implementation sits alongside the previously authorized maintenance, invalid-box fix, Assault cadence change and reservation investigation in the working tree. Those changes were preserved.

The live player path is now: select card package → click battlefield → resizable squad blueprint → single-knob line/loop gesture → validated initial intent → atomic card/Command commit → off-screen squad entry. Existing squads support click/Shift selection and re-commanding without another blueprint.

## Contracts and implementation

- Every deployment owns a persistent BattleSquad with ID, team, type, source cards, surviving members, persistent Advance/Defend intent and optional shared defense-order data.
- Shared defense orders retain separate squad identities and allocate contiguous chunks of centered grid positions. Selection uses all living members for its centroid.
- New player and enemy orders use DeploymentManager.request_squad. Existing battlefield occupancy and old deployment-area boundaries do not veto ordinary new deployments. Physical off-screen collisions still queue safely.
- Defense circles are expanded before bounds/No-Hold validation and before any resource commit. Positions account for body radius and terrain. Invalid commands preserve current orders, selection and resources.
- Advance retains disrupted positions and resumes forward combat/movement normally. Defend fights immediate threats during travel, then limits target acquisition/pursuit to its shared circle, prefers immediately shootable enemies, and returns to allocated homes.
- Casualties dirty a defense formation, but allocation is refreshed only once pressure has ended. Advance never runs reformation.
- A bounded local AStar grid attempts routes around blocked defensive movement. It follows a valid detour to completion instead of oscillating between symmetric routes. It skips the rounded start cell, which can otherwise point a clear soldier into a neighbor.
- Right-click/Escape uses one cancel stack. Gesture cancellation preserves squad orders and selection; setup cancellation preserves cards/resources; selection-only cancellation does not rewrite intent.
- Planning is one shared controller for blueprint and orders. It interpolates in unscaled real time, slows the fixed simulation through Engine.time_scale, and desaturates only the world. A separate higher layer keeps cards, selection and commands prominent. Scene exit/restart resets time scale.
- No-Hold hatching and text fade contextually during planning. Team shape markers remain readable without color. White selection rings are the prototype equivalent of an outline.
- Feedback uses clean arrows, pulsing circles/shields and selection rings; failures rise with accelerating movement and fade with an icon plus a short reason. Gesture metrics, squad state and planning state are visible in F3.

## Tunable defaults

| Setting | Default |
| --- | --- |
| Planning speed | 0.40x |
| Transition in/out | 0.25 seconds each |
| Desaturation | 0.85 |
| Brightness multiplier | 0.88 |
| Minimum/maximum defense radius | 140 / 1800 world pixels |
| Defensive spacing | 320 world pixels, bounded below by body diameter plus movement clearance |
| Enemy-side No-Hold depth | 900 world pixels |
| Simulation | 60 physics ticks/second |

The defensive spacing leaves traversal corridors between settled soldiers. A body-tight grid reproduced a stall in the new 24-soldier arrival test; centering the packing, leaving corridors and retaining local detours fixed that tested case. Full six-/24-unit arrivals and mixed-squad casualty reformation now run through normal spawning and physics rather than teleporting fixtures.

All existing card costs/stats, including the previously requested Assault 0.25-second base interval and 25.6 damage, remain intact. Added BattleTuning fields have defaults so existing resources load without a serialized migration. Squad/order state is runtime-only; no backend, persistent save system or dependency was added.

## Verification scope

The command suite covers recognition, loop stems, ambiguous rejection, ownership, click/Shift toggles, centroid, auto-expansion, shared defense, No-Hold/bounds, cancellation, partial/full casualties, planning transitions/reset, travel combat, leash targeting, return/reformation, blueprint resizing/cancellation, initial Advance/Defend, final resource revalidation and actual viewport mouse-event routing.

Movement scenarios require six and 24 soldiers to settle without teleportation, then require mixed Rifle/Assault squads to converge and reform after casualties while preserving IDs.

Rendered captures were executed and inspected on Windows with Steam Godot 4.7.2, both Compatibility/OpenGL and Forward+/Vulkan on an RTX 4070 Ti. The final blueprint uses an opaque dark background so controls remain legible over the battlefield. Captures are local under ignored .test-results/ and can be reproduced with tools/capture_command_preview.gd.

The verification runner includes both new suites. The sustained battle now uses intent-first deployment for both the automated test player and enemy.

## Limits and next check

This is a functional mechanics prototype, not final UI polish or a human playtest. Arbitrarily large terrain mazes are not covered by the bounded local navigation window. Gesture thresholds and planning values are provisional. Test gesture fatigue, recognition rejection frequency, large multi-squad congestion, No-Hold placement, selection clarity and whether Defend dominates Advance before adding tactical intents or refining artwork.

Legacy rectangle helpers/scenes remain for regression compatibility, but the actual viewport input test verifies that normal player input opens the blueprint instead of drawing a deployment rectangle. No public release, store export or GitHub Actions execution is claimed. Changes remain local until explicitly committed/pushed.

## Final executed results

Final complete uncached run on Steam Godot 4.7.2, Windows: .test-results/20261017-203820-159.

| Check | Result |
| --- | --- |
| Squad commands | 72 assertions passed |
| Squad movement / mixed-squad casualty reformation | 38 assertions passed |
| Reinforcement flow / reservation occupancy | 193 assertions passed |
| Historical formation geometry | 264 assertions passed |
| Combat/input | 29 assertions passed |
| Combat readability/capture | 150 assertions passed |
| Camera | 19 assertions passed |
| Simulation clock, 30 and 144 render FPS | 10 assertions each; identical snapshots |
| Total assertion checks | 785 passed |
| Sustained battle using intent-first deployment | 42 enemy / 53 player orders, 540 deaths, 105 scoring events, peak 136 units; player 100 / enemy 5; exit 0 |
| Fresh import and main-scene startup | Passed without logged errors |
| Rendered preview smoke | Compatibility/OpenGL and Forward+/Vulkan passed; images inspected |

The final runner and staged/unstaged diff checks passed; no test assertions were disabled to obtain a pass. Existing tests of superseded live rectangle behavior remain isolated compatibility checks, while actual viewport input and new intent-first deployments are covered explicitly. No commit or push was performed for this batch.

## Subsequent defense and blueprint revision

The AStar movement and slider-based blueprint described in the original implementation record have been replaced. See docs/DEFENSE_PERFORMANCE_AND_BLUEPRINT.md for the current local-steering implementation, direct corner/edge resizing, measured timing comparison and final 1,133-assertion verification.
