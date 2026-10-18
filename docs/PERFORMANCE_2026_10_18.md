# Battle performance investigation — 18 October 2026

Baseline: `0932e13`. The reported symptom was choppy gameplay. Profiling found periodic territory-allocation spikes, followed by unnecessary per-frame UI drawing and per-soldier material duplication. This change preserves game rules and tuning.

## Measured results

Same Windows machine, Godot `4.7.2.stable.steam.ed1daf0bf`, NVIDIA RTX 4070 Ti. Rendered comparisons used Vulkan/Forward+, 1280×900, six established Defensive Points and 144 static soldiers. AI and soldier movement were disabled in this rendered fixture to isolate territory/UI work. The game still ran its normal fixed-step rule updates. Each run warmed up for two wall-clock seconds, then sampled at least three seconds and 240 frames. The faster build collected more frames in that time. The window was started hidden; these are controlled fixture timings, not player-observed gameplay FPS.

| Measurement | Before | After |
| --- | ---: | ---: |
| Rendered frame mean | 35.214 ms | 3.285 ms |
| Rendered frame p95 | 129.066 ms | 4.475 ms |
| Rendered frame maximum | 134.144 ms | 5.643 ms |
| Rendered draw calls p95 | 2,608 | 1,767 |
| Command update p95, headless fixture | 113.512 ms | 1.605 ms |
| Forced territory solve mean, headless fixture | 241.060 ms | 6.717 ms |

Headless results use 180 manually driven command/soldier updates and 12 forced territory solves, with the same six-point/144-soldier fixture. Before and after runs were sequential. These are individual observed runs; timing varies with background work, hardware, renderer, map and population. A 60 FPS frame has about 16.7 ms total available. The controlled scenario now has substantially more headroom, but this does not establish a universal live-game frame-rate guarantee.

## Changes and trade-offs

- Cache legal cells sorted around a point's anchors. Reuse them until geometry or explicit terrain invalidation changes. Cache size is bounded at 32 entries.
- Merge those sorted streams with a small priority queue instead of allocating and globally sorting every point×battlefield-cell pair. Stop a point's stream once its area quota is full. The original ordering, pressure scores, connectivity, legal-cell rules and tie-breaks remain authoritative.
- Skip spatial reallocation when established counts, point identities/anchors/teams and relevant tuning are unchanged. Continue refreshing established/inbound counts and lifecycle metadata. Casualties and arrivals invalidate the input signature even if their square footprint budget happens to be unchanged. Explicit forced solves still execute.
- Merge territory fills into contiguous row strips and submit boundary segments together. Cache this world-space geometry, so zoom/pan still apply normally without rebuilding it.
- Rebuild a soldier's icon/health-bar geometry only when its visual inputs change. Health, state, team/type, zoom, debug visibility, defensive status, rout and buff visibility remain invalidation inputs. Transform updates still keep symbols upright while units turn and move.
- Use one shader resource and one material per team, preserving the existing color calculation instead of creating a material and shader for every soldier.

The additional memory is bounded caches and two shared team materials. Runtime terrain edits must continue calling `points.invalidate_terrain()`; that now clears terrain/candidate caches and the ownership signature together. No combat-stat, movement-speed, AI cadence, territory-budget or map-size change is used to obtain these results.

## Reproduce and verify

Use the pinned editor to run `tools/profile_battle.gd` headlessly, or `tools/profile_frame_pacing.gd` with the project's normal renderer. Both print completion markers and before/after metrics in milliseconds or microseconds. The frame-pacing fixture reports its actual sample count. Profiling tools do not certify gameplay balance or performance on every machine.

`tools/verify.ps1 -FreshImport` includes `territory_performance_test.gd`. It compares exact cell ownership with a frozen full-grid/global-sort reference across eight seeded scenes, including mixed teams, multiple anchors and varied counts. It also checks unchanged-work reuse, casualty/inbound/tuning/terrain invalidation, quota-bounded traversal, exact batched fill/hole coverage, boundary preservation, shared colors, and health/zoom/debug redraw invalidation. Existing movement, combat, selection, command, reinforcement, capture, camera and clock checks remain enabled.

The complete fresh-import run passed all suites, sustained battle (55 enemy/70 player deployments, 798 deaths, 100 goals, peak 139 units) and startup smoke. The final capacity-warning refresh correction was then checked with the 27-assertion performance suite, 337 drawn-command assertions, 72 squad-command assertions and startup smoke. The rendered captures were inspected for preserved territory outlines, selection, team colors and blueprint layout.

Next useful player check: repeat the battle that felt choppy, including deployment/gesture input and several established positions. Note whether any remaining spikes occur specifically on deployment, casualty bursts, selection/debug overlays, or large combat effects. Those cases would justify the next targeted profile; lowering gameplay complexity is not the first remedy.
