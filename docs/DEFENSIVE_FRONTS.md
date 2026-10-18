# Defensive front prototype v0.1

Implemented against Godot 4.7.2 and the supplied Defensive Front System brief.

## Player behavior

A Defend order creates an oriented front from persistent squad formation blocks.
A terminal route supplies the last meaningful travel heading; an order without
one faces the enemy side. The AI supplies facing directly. Squads retain member
identity, formation files/ranks, relative shape, original blueprint width/depth,
card ordering, and original consolidation capacity. They never become a global
pool of defenders.

The existing traversable defensive spacing is retained: blueprint offsets are
uniformly expanded only when their closest spacing is below the defensive
clearance setting (320 pixels by default). Thus the chosen file/rank layout and
proportions persist, but a tightly drawn blueprint can occupy a larger defensive
footprint than its deployment preview. Original blueprint dimensions are stored
separately. This is a deliberate prototype accommodation for the current body
movement system, not a claim of exact pixel-for-pixel blueprint placement.

Whole-position orders center the combined depth around the selected anchor:
the first block establishes the front and subsequent blocks form depth. The
new front never packs survivors into a generic square. Each block keeps its
original casualty holes when it is relocated.

An open route ending inside an active friendly point reinforces that point.
The endpoint projects onto its lateral axis. A genuine opening that fits the
whole arriving block is preferred. Occupied central sectors gain reserve depth;
endpoints within about 0.6 defensive spacings of an exposed edge extend frontage.
Existing blocks keep their homes. A complete block must fit the battlefield,
No-Hold limits, terrain, and other positions. An invalid footprint rejects the
command without spending Command or queuing soldiers. The UI previews the
proposed soldier homes and labels frontage versus reserve depth. Failed plans
with available geometry appear red. Terminal Defend loops create new fronts;
they do not secretly become reinforcement orders.

The thick, segmented forward edge is primary. Casualty vacancies leave breaks;
reserves remain visible behind the line. Territory fill and boundary are subdued.
The old giant circular reinforcement overlay has been removed. Assigned slots
remain dim until their soldier physically approaches. Shields still select the
established squads of a logical point, including partially established squads.
Entirely inbound squads remain excluded.

## Reserves and attrition

The first vacant frontline slot starts a 3.0 simulation-second wave timer.
At 25% vacancy, remaining delay is capped at 1.0 second. When due, the service
assigns one established reserve per available vacancy, preferring lateral
locality before travel distance. Units physically follow their ordinary movement
and combat rules; an assignment does not teleport a soldier. Excess reserves
stay behind. No reserves means visible vacancies persist.

Rear ranks within a frontline block are reserves too. Reserve soldiers shoot
and receive damage normally, but do not independently pursue contacts away
from their assigned homes. A wholly missing frontline block can immediately
promote a compatible established reserve block behind it; the whole block moves
and retains squad identity. This is distinct from a casualty wave. A promoted
block must fit its destination legally. New orders and normal rout behavior
still take precedence.

Advance detaches exactly the ordered squad. Its vacated frontage remains an
opening; other squads do not globally redistribute. Whole-point relocation
uses the existing route/corridor and recovery systems.

## Stragglers

A 1–3-soldier squad can consolidate during a defensive lull only when fully
established, unselected, not retreating, and finished with any drawn route.
Receiving squads must be at the same point, eligible for a lull, contain the
incoming type in their original composition, and have real casualty vacancies
within original capacity. Matching composition is preferred, then local sector,
then distance. A receiver must have more surviving soldiers than the source;
this prevents mutual transfers and cycles between tiny squads. No synthetic
squads or new unit types are created.

A physical slot and a free receiving member index are reserved independently before movement, including after a reserve wave has moved the original slot occupant elsewhere. Frontline consolidation honors the reserve delay; it cannot bypass visible casualty gaps. The soldier
keeps its source identity until physically within 10 pixels of the receiving
home. Selection, combat, a new order, a missing receiver, a covered slot, or a
changed point cancels the internal transfer. Soldiers keep their existing
health, damage, speed, and modifiers. Empty source objects are pruned; telemetry
records `STRAGGLER_CONSOLIDATED` and ends the source as `consolidated`, not killed.
Unit telemetry retains original deployment provenance; the transfer event
records subsequent membership changes.

## Territory and AI

The existing point-level ownership, established/inbound distinction, pressure,
absorption, Rout, and Breakthrough model remain. Candidate distance now follows
the oriented envelope of block geometry, preferring rear space over equivalent
space ahead. A single global distance tie-break keeps the connected allocation
stream from starving on disconnected local minima. Casualty gaps do not yet
weaken individual sectors of territorial pressure. Friendly points remain
separate until the existing absorption logic merges them; absorption carries
physical blocks across into the receiving coordinate system. Friendly coarse ownership is renegotiated by this solver; it is not a veto on otherwise separated friendly physical formations. Opposing owned cells and physical formation overlap remain placement limits.

The AI keeps the existing economy, one-second decisions, shuffled packages,
70/30 lane policy, Line/Triangle anchors and thresholds, inbound commitments,
and excess Advance behavior. Its default blueprint aims for two ranks, with
additional ranks when a package cannot fit a flank or its neighboring positions at defensive spacing. Before purchasing for a doctrine commitment it checks the whole block at that anchor/sector; an impossible fit waits without spending.
Reinforcement first targets vacancies, then the sector with least reserve depth,
then alternates edge expansion. Both teams use the same front service and timers.

## Verification

`tools/verify.ps1 -Suite defensive_front` exercises both teams, shape and mixed
card persistence, facing, center/edge/gap reinforcement, unchanged settled homes,
read-only previews, invalid purchase atomicity, delayed/heavy-loss waves, reserve
accounting, depleted fronts, full-block replacement, detachment, physical
consolidation, capacity/type/selection restrictions, cancellation, and large AI
commitments. Live Line and Triangle scenarios use the real economy, entry queue, and movement to verify all anchor commitments establish and excess forces still Advance. The normal full verification runner includes this suite.

`tools/run_pathing_tests.ps1` continues to exercise normal physics, queued
purchases, obstructions, reinforcement, crossing routes, and whole-position
relocation. The edge case still follows a near-boundary route, but its final
formation is centered far enough inward to fit: fronts now reject a footprint
crossing the edge instead of silently clipping/repacking its soldiers.

Legacy heap/reference and forced overlapping-pressure fixtures explicitly build
legacy points so they continue to validate the unchanged solver and absorption
mechanics independently. New front command legality is tested separately.

No cover/damage bonus, balance-stat change, scoring change, new card, external
plugin, or arbitrary-maze pathfinder is introduced. Automated results establish
prototype behavior; balance and readability still need ordinary playtesting.


Observed validation on 2026-10-18 with Godot 4.7.2:

- 83 focused front assertions passed, including live Line/Triangle establishment
  and excess deployment, plus whole-body boundary checks.
- 39 seeded pathing trials passed with zero sampled body overlaps and zero
  invalid-motion samples. Both edge-route cases were rechecked after the final
  whole-body boundary guard and passed.
- The full regression runner passed, including 144-soldier replacement and
  relocation, combat/telemetry, independent territory allocation, capture,
  reinforcement entry, and matching 30/144 FPS simulation snapshots.
- Sustained battle passed: 51 deployments, 282 deaths, 100 scoring events,
  and 161 peak living units in the final full run.
- Existing local UI clarity suite: 37 assertions passed. Actual Godot-rendered
  battlefield captures were inspected for frontage gaps and reserve previews.

These are automated/editor-runtime checks, not an exported-build certification
or a claim that the prototype's balance has been proven.
