# Defend performance and direct blueprint resizing

## Observed causes and changes

The crowded baseline reproduced long simulation-update stalls. Each blocked soldier could create an AStar grid, test every cell against the full army and terrain, and repeat that search later. This was especially expensive as selected unit count increased.

Removed per-soldier grid/graph path search entirely. Defenders now try a fixed set of local headings, keep a passing-side preference, and use position assignment sorted by horizontal order to reduce crossing. Threat scans are shared per defense order. Movement collision checks use nearby-body buckets rather than scanning the whole army. Spawn, local transform changes, death and scene exit keep those buckets current; dead/freed enemies invalidate the shared threat cache.

The diagonal resize reproduction also failed before the fix: the preview auto-fit and re-centered itself after each width/depth edit, moving both the handle and its supposed anchor away from the pointer. Removed all blueprint slider controls. The box now uses one fixed preview scale, captures drag/release input, supports all corners and edge handles, anchors the opposite side, and clamps each axis independently. It consumes the final release position even outside the panel. No auto-fit or recenter occurs during the drag.

## Controlled timing measurements

Same Windows machine and Steam Godot 4.7.2. Each workload creates a crowded 24- or 72-unit formation, issues Defend and measures 180 fixed-step battle/unit updates. The baseline was measured before editing; the final version was measured in two fresh processes with the identical workload. Spawning/order allocation and rendering/UI are outside the timed loop, so these numbers measure simulation-update cost, not total frame time or FPS.

| Units | Baseline mean | Final means, two runs | Baseline p95 | Final p95, two runs |
| --- | ---: | ---: | ---: | ---: |
| 24 | 8.832 ms | 0.862 / 0.856 ms | 33.176 ms | 1.276 / 1.242 ms |
| 72 | 74.183 ms | 2.875 / 2.795 ms | 200.771 ms | 4.399 / 4.487 ms |

The 72-unit mean is approximately 26 times lower in this workload. Its worst sampled update fell from 998.267 ms to 5.302 / 5.230 ms. This is a bounded local comparison, not a universal performance guarantee.

Reproduce with the Godot editor executable: --headless --path . --fixed-fps 60 --script tools/profile_defense.gd. Local before/after logs are under ignored .test-results/.

## Regression coverage

- The pointer/anchor regression failed on the old resize implementation and passes after the fix.
- Blueprint drag coverage includes four corners, four diagonal movement samples, stable opposite anchors, edge-only axis changes, width clamping while depth remains responsive, release outside the panel, no slider controls and resource preservation.
- A six-squad, 72-soldier scenario requires all selected soldiers to arrive under ordinary physics/local steering while keeping squad identities and remaining within their defense circle.
- Collision bucket results are compared against an independent all-body reference, including near-cell boundaries. Tests require immediate occupancy updates after spawn, moving across cells and death.
- Shared targeting tests require newly spawned enemies to appear and dead/freed enemies to disappear.
- Existing six-/24-soldier movement, mixed-squad casualty reformation, leash targeting, command/cancellation, resource, reinforcement and combat tests remain enabled.

Local steering deliberately does not solve arbitrary enclosed terrain mazes. Real blockers can make soldiers wait. No collision bypass, teleportation or hidden super-squad is used to force arrival.

## Final verification (2026-10-17)

Steam Godot 4.7.2 fresh-import verification passed: 1,133 assertions across defense scale, blueprint drag, squad commands/movement, reinforcement, formation, combat/input/readability, camera and simulation-clock checks. The 30/144 FPS clock snapshots matched. The sustained battle completed with 95 orders, 540 deaths, 105 scoring events and a peak of 136 units. Main-scene startup passed without logged errors.

Forward+/Vulkan rendered preview capture passed; the slider-free blueprint image was inspected. Final logs: .test-results/20261017-205859-808. Changes remain local and uncommitted/unpushed.
