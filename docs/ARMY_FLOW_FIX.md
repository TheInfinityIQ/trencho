# Army flow correction

A completed mirror log contained 415 living soldiers in ADVANCING state. Default forward movement stopped on a blocked straight path without trying the bounded detours already used by ordered movement. AI defense assignments also waited until squads reached defense depth, leaving additional squads advancing unassigned during doctrine WAIT.

Default Advance now uses the same bounded local avoidance, respecting body clearance and preserving strategic speed. AI assigns defensive jobs to queued squads, reserves their population immediately, and pauses purchasing while current doctrine commitments establish. Failed assignments remain eligible for retry. Once goals are established, excess squads advance; casualties reopen deficits. No population cap, forced deaths, or combat stat changes were added.

Mirror status now reports separate live roles for each side, queued bodies separately, and established/target defense counts with inbound commitments. Whole squads can exceed a target. Counts describe the current state, not guarantees that all advancing bodies are making progress.

Regression: all three infantry types on both teams must pass a stationary friendly body without overlapping or moving it; queued defensive assignment, outer priority, reservations and WAIT purchasing are checked. Local steering is bounded, not global pathfinding; complex congestion remains a possible limitation.

Validation: full regression suite passed, including 31 new army-flow assertions and equal 30/144 FPS snapshots. The 180-second battle fixture reached a natural 0/100 result, with 349 deaths and peak 167 units. A separate 60-second wall-time mirror run sampled 128.3/125.9/141.1 simulated seconds and 175/203/152 living soldiers; no match finished within that budget. This is a short-run diagnostic, not proof that all longer matches avoid congestion or that the five-minute batch target is met.
