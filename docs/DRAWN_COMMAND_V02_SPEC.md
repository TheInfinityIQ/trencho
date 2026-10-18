# Trencho — Drawn Command, Defensive Area, Mixed Squad & Enemy AI Systems
**Developer Handoff — Consolidated Prototype Specification**
**Version:** 0.2
**Status:** Current agreed direction for implementation/testing
**Supersedes:** Earlier deployment-zone / fixed defense-circle assumptions where they conflict with this document
**Primary objective:** Implement the current battlefield command language and supporting squad/Defensive Area systems before a dedicated UI/UX polish pass.

---

# 0. Scope and Status Conventions

This specification separates decisions into four categories:

## LOCKED FOR PROTOTYPE
These are the current agreed requirements and should be implemented unless blocked by the existing architecture.

## PROVISIONAL TUNING
These are starting values or heuristics intended for testing.

## DEFERRED POLISH
These are intentionally not required for the functional prototype.

## FUTURE EXTENSION
Architecture should avoid blocking these ideas, but they should not delay the current implementation.

The current map width should remain unchanged for this pass.

---

# 1. Design Pillar

## Draw Orders on the Battlefield

The player's tactical intent should be expressed spatially on the battlefield wherever practical.

Prefer:

- drawn movement;
- drawn defense;
- spatial reinforcement;
- simulation-assisted execution;

over:

- persistent command panels;
- stance buttons;
- tactical toggles;
- individual-unit micromanagement.

The goal is for the player to feel as though they are issuing battlefield orders rather than operating a control console.

This does **not** prohibit conventional UI for:

- cards;
- menus;
- settings;
- references/tutorials;
- resource displays.

It specifically applies to tactical battlefield orders.

---

# 2. Core Command Grammar

The command system should use one continuous drawn stroke.

The player begins from the command knob / command origin and draws directly on the battlefield.

## LOCKED FOR PROTOTYPE

The gesture grammar is:

### Open stroke
```text
MOVE ALONG ROUTE
-> reach route endpoint
-> resume ADVANCE
```

### Closed loop
```text
DEFEND HERE
```

### Open route ending in a closed loop
```text
MOVE ALONG ROUTE
-> establish/join DEFENSIVE POINT at terminal loop
-> DEFEND
```

### Open route whose endpoint lands inside an existing friendly Defensive Area
```text
MOVE ALONG ROUTE
-> reinforce that Defensive Point
-> DEFEND
```

### Ambiguous attempted loop
```text
FAIL SAFELY
-> do not convert to Advance
-> preserve existing orders
-> keep selection for retry
```

No Shift modifier is required for drawing line-to-circle commands.

---

# 3. Curved Movement Routes

## LOCKED FOR PROTOTYPE

Open strokes may curve.

The player may draw:

- forward routes;
- backward routes;
- lateral routes;
- diagonal routes;
- broad curved routes.

The command system should not require straight lines.

Curved routes allow the player to avoid dangerous Defensive Areas or approach a reinforcement point from a safer direction.

## Route simplification

Do not preserve every mouse sample as a literal path.

Simplify the raw stroke into a small number of meaningful route segments / waypoints.

The implementation should:

- remove hand jitter;
- preserve broad intentional curves;
- avoid encouraging zig-zag micro;
- keep the route visually faithful to the player's broad movement intent.

### PROVISIONAL TUNING
A cap of roughly 2–4 meaningful route segments is a reasonable first test.

The exact simplification algorithm is implementation-dependent.

---

# 4. Full-Loop Requirement for Defend

Because curved open strokes are valid movement commands, Defend should require a clearly intentional loop.

## LOCKED FOR PROTOTYPE

A loop must be sufficiently closed to count as Defend.

Clockwise and counter-clockwise loops are equivalent.

The recognizer should not care which side the player enters the loop from.

The loop defines:

```text
Defensive Point center
```

It does **not** define the Defensive Area size.

The Defensive Area size is derived from assigned defenders.

---

# 5. Ambiguous Gestures

## LOCKED FOR PROTOTYPE

If a gesture strongly resembles an attempted loop but fails the closure criteria:

```text
result = AMBIGUOUS / UNRECOGNIZED
```

Do not silently interpret it as Advance.

This is important because an unintended Advance order can be substantially more harmful than a rejected input.

On ambiguous input:

- existing squad intent remains unchanged;
- selection remains active;
- no resources are spent;
- player may retry immediately;
- failure feedback should be shown.

---

# 6. Live Recognition Preview

## PROVISIONAL / STRONGLY RECOMMENDED

During drawing, provide a lightweight interpretation preview.

Examples:

### Open movement route
Show a faint projected route/arrow.

### Stroke starts forming a valid loop
Begin showing a faint defense preview.

### Loop becomes confidently recognized
Show a shield / Defensive Point preview.

### Route endpoint enters a friendly Defensive Area
Show reinforcement preview.

The player should ideally know what the game currently believes the gesture means before mouse release.

This can be prototype-quality.

---

# 7. Squad Selection

## LOCKED FOR PROTOTYPE

Clicking any soldier selects that soldier's entire squad.

Individual soldier command selection is not required.

Selected squads should receive a clearly visible bright white outline or equivalent placeholder selection treatment.

Clicking an already-selected squad toggles that squad off.

---

# 8. Multi-Selection

## LOCKED FOR PROTOTYPE

Use:

```text
Shift + Click
```

to add/remove squads from the current selection.

Releasing Shift does **not** clear the selection.

Shift is only required to modify the selection.

Multi-selection persists until:

- player explicitly deselects;
- player right-clicks with no active command interaction;
- squads are destroyed;
- another selection operation replaces the current selection.

---

# 9. Selection Centroid

## LOCKED FOR PROTOTYPE

Calculate a centroid / command origin for the currently selected living units.

Use it as the spatial origin for:

- command knob;
- movement visualization;
- Defend arrow;
- success feedback;
- failure feedback.

Exact centroid implementation may follow existing project architecture.

---

# 10. Right-Click Behavior

## LOCKED FOR PROTOTYPE

Right-click means:

> Back out of the current UI operation.

### During gesture input
Cancel the gesture only.

Do not change the squad's previous tactical order.

### During blueprint/setup
Back out/cancel the current setup step.

Do not spend cards/resources before final valid deployment commit.

### Selection only, no active command interaction
Clear selection.

Do not alter squad tactical intent.

Right-click is not a "stop squad" command.

---

# 11. Command Planning Mode

## LOCKED FOR PROTOTYPE

Entering a meaningful command/setup interaction activates Command Planning Mode.

Simple selection alone should not activate it.

Planning Mode should:

- smoothly slow simulation;
- smoothly desaturate battlefield visuals toward pseudo-grayscale;
- keep command UI/selection/gesture information prominent.

### PROVISIONAL TUNING

```text
normal time scale: 1.00x
planning time scale: ~0.40x
test range: 0.35x–0.50x
transition: ~0.20–0.35 sec
```

Use smooth interpolation rather than snapping.

---

# 12. Planning Mode Visual Hierarchy

## LOCKED PRINCIPLE

During Planning Mode:

### Battlefield
- reduced saturation;
- may slightly reduce contrast/brightness;
- continues moving at reduced speed.

### Command information
Remain prominent:
- selection outlines;
- route;
- loop;
- Defensive Area preview;
- reinforcement target feedback;
- cards/resources;
- No-Hold area;
- failure/success feedback.

Do not rely only on color for team identity.

---

# 13. ADVANCE Intent

Every squad has a persistent tactical intent.

Current intents:

```text
ADVANCE
DEFEND
```

## LOCKED FOR PROTOTYPE

ADVANCE means:

> Move according to current route/waypoint instruction; when not actively fighting and no temporary waypoint remains, continue advancing toward the enemy side.

While advancing:

- engage enemies according to normal combat rules;
- after combat ends, continue route / Advance;
- do not automatically reform after casualties.

Advance deliberately preserves battlefield disorder.

---

# 14. DEFEND Intent

DEFEND means:

> Move to / remain within a Defensive Point, engage enemies relevant to that Defensive Area, and reform when threats disappear.

Defenders:

- can reposition tactically inside the Defensive Area;
- should not chase beyond the Defensive Area;
- return to defensive positions when no valid threats remain;
- reform after combat/casualties.

Defensive reformation should happen primarily after pressure subsides rather than causing constant shuffling during combat.

---

# 15. Visible Squad Intent States

## LOCKED FOR PROTOTYPE

### Advance
No persistent icon.

### Moving to Defend
Arrow + Shield.

### Established Defend
Shield.

Do not expose every internal AI state to the player.

---

# 16. Defensive Point vs Defensive Area

## LOCKED TERMINOLOGY

Use two concepts:

### Defensive Point
The logical backend object.

It owns:
- ID;
- anchors;
- assigned squads;
- inbound squads;
- desired area/capacity;
- actual territory;
- pressure;
- lifecycle state.

### Defensive Area
The dynamic territory shape controlled by that Defensive Point.

Do not make a fixed mathematical radius the authoritative representation.

A new isolated Defensive Point may begin approximately circular, but constraints can deform it.

---

# 17. Defensive Point Lifecycle

## LOCKED FOR PROTOTYPE

A Defensive Point should only persist if at least one living squad is:

- currently assigned and established there; or
- explicitly inbound to reinforce/occupy it.

Recommended states:

### ACTIVE
At least one living established defender exists.

The point controls active territory.

### PENDING
No established defenders remain, but at least one living squad is inbound.

The destination remains valid.

It does not provide normal active defensive control until troops arrive.

### GONE
No established defenders and no living inbound squad.

Delete the Defensive Point.

---

# 18. Example: Defender Dies Before Reinforcement Arrives

Required behavior:

```text
Squad A defends Point X
Squad B is inbound to reinforce Point X

Squad A dies
-> Point X becomes PENDING
-> Point X remains as Squad B's destination

If Squad B arrives
-> Point X becomes ACTIVE

If Squad B dies or receives a different order before arrival
-> no defenders + no inbound
-> delete Point X
```

---

# 19. Inbound Reinforcements Do Not Increase Active Territory

## LOCKED FOR PROTOTYPE

Inbound soldiers should **not** contribute to the current active Defensive Area before they arrive.

The area should only expand after soldiers become established.

Otherwise territory would grow before the troops physically reach it.

During command drawing only, a faint projected future shape may be shown.

---

# 20. Reinforcement Projection

## LOCKED UX PRINCIPLE

Projected post-reinforcement area should appear only while the player is actively drawing/previewing the reinforcement order.

Do not keep projected future territory permanently visible.

Possible preview:

```text
solid shape = current active territory
faint ghost shape = expected territory after incoming squad arrives
```

The projected shape should already respect:

- map edge;
- No-Hold zone;
- neighboring Defensive Areas.

---

# 21. Defense Size Derived from Established Troops

## LOCKED FOR PROTOTYPE

The player does not draw the size of the Defensive Area.

The player draws the location / center.

Territory size is derived from established living defenders.

Conceptually:

```text
living established defenders
-> calculate compact formation footprint
-> determine required area
-> add defensive margin
-> obtain desired territory area
```

### PROVISIONAL TUNING

Start with a compact square/grid formation requirement plus approximately:

```text
+20% defensive margin
```

The exact margin is tunable.

The implementation should avoid a simple linear soldier-count-to-radius multiplier.

---

# 22. Desired Area vs Actual Area

Each Defensive Point should conceptually track:

### Desired Area
How much territory the established defenders would naturally support.

### Actual Area
How much legal territory the point currently owns after pressure and constraints.

### Pressure
How strongly the point contests nearby legal territory.

### Capacity
Whether the actual shape can physically accommodate the assigned established soldiers.

These concepts should drive the simulation rather than many special-case overlap rules.

---

# 23. Bubble-Like Territory Behavior

## LOCKED DIRECTION

Defensive Areas should behave like bubbles/membranes.

An isolated point tends toward an organic rounded shape.

When constrained, the area should expand into available legal space rather than simply shrinking equally in all directions.

Constraints include:

- map edge;
- enemy No-Hold / deployment restriction area;
- neighboring Defensive Areas.

The point should not gain unlimited area.

It should stop expanding after reaching its desired area budget.

---

# 24. Recommended Implementation: Territory / Influence Grid

## STRONGLY RECOMMENDED

Do not implement literal fluid simulation.

Use a deterministic low-resolution battlefield territory/influence grid or equivalent stable solver.

Each territory cell may be:

- unclaimed;
- claimed by Defensive Point A;
- claimed by Defensive Point B;
- hard-blocked.

Hard-blocked cells include:

- outside battlefield;
- enemy No-Hold/deployment zone where defense territory is not allowed.

Adjacent Defensive Points contest available cells using pressure.

A cell should never be owned by two Defensive Points simultaneously.

Visible boundaries can later be smoothed.

---

# 25. Defensive Areas Must Not Overlap

## LOCKED FOR PROTOTYPE

Two Defensive Areas should never visually/mechanically overlap.

They may:

- touch;
- press against each other;
- deform each other;
- transfer territory through pressure;
- absorb/defeat one another under the agreed conditions.

They should not occupy the same territory cells.

---

# 26. Contact Boundary Shape

## LOCKED DIRECTION

Free edges may be curved/organic.

When two Defensive Areas directly contact each other, the shared boundary should generally read as a comparatively straight contested front.

The contact line may shear/tilt, for example:

```text
AAAAAA / BBBB
AAAAA / BBBBB
AAAA / BBBBBB
```

Rather than always:

```text
AAAAA | BBBBB
AAAAA | BBBBB
AAAAA | BBBBB
```

### CURRENT IMPLEMENTATION PRIORITY

First pass may use point-level pressure and relatively straight shared boundaries.

### FUTURE EXTENSION

Local soldier density near a boundary may cause:

- bulging;
- shearing;
- angled fronts;
- local pressure differences.

Do not delay the first stable solver for local-density pressure.

---

# 27. Environmental Clipping / No-Hold Boundary

## LOCKED FOR PROTOTYPE

A Defensive Area may not grow into the enemy deployment / No-Hold zone.

If its desired area would cross the boundary:

- clamp that portion of the territory to the border;
- allow the Defensive Area to expand into other legal directions until it reaches its desired area, if space exists.

Do not simply shrink the whole territory symmetrically.

---

# 28. Friendly Defensive Area Competition

## LOCKED DIRECTION

Friendly Defensive Areas may press against one another.

They should not overlap.

If both can satisfy their desired areas, they remain separate.

If one becomes too compressed to support its assigned defenders, it may become unstable.

---

# 29. Friendly Point Absorption

## LOCKED FOR PROTOTYPE

If a friendly Defensive Point becomes unsustainable because a stronger neighboring friendly Defensive Point takes enough available territory:

```text
weaker point becomes unstable
-> weaker point pops / is absorbed
-> surviving soldiers assigned to weaker point join the stronger Defensive Point
-> weaker Defensive Point object is deleted
-> stronger Defensive Point recalculates desired area
```

This should emerge from pressure/capacity rather than a hard-coded "20 soldiers beats 1" rule.

---

# 30. Capacity States

## LOCKED CONCEPT

A Defensive Point should conceptually support:

### STABLE
Enough territory to fit defenders comfortably.

### COMPRESSED
Defenders still fit, but the point is below desired area / ideal spacing.

### CRITICAL
Not enough usable territory to fit defenders under the maximum allowed density.

When Critical:

1. attempt to acquire more legal territory through pressure;
2. friendly absorption may occur if appropriate;
3. if capacity still cannot be satisfied, the point may pop.

---

# 31. Reinforcement Warning for Critical Points

## LOCKED UX REQUIREMENT

If the player previews sending more troops into a Defensive Point that is already near capacity / instability:

- show a warning during preview;
- do not hard-reject the reinforcement.

The player should be allowed to take the risk.

DEFERRED polish may include:
- tense membrane animation;
- warning icon;
- distorted preview boundary.

Prototype feedback may be simple.

---

# 32. If a Friendly Defensive Point Cannot Fit Its Defenders

## LOCKED DIRECTION

If a point cannot acquire enough legal territory and cannot resolve the conflict through friendly absorption:

```text
Defensive Point pops
-> assigned squads stop Defending
-> those squads return to ADVANCE
```

This represents a defensive position becoming physically untenable.

Exact threshold is tunable.

---

# 33. Anchors

## LOCKED BACKEND REQUIREMENT

A Defensive Point may contain multiple spatial anchors.

Initial Defensive Point:
```text
anchors = [initial_center]
```

When one friendly Defensive Point absorbs another:

- retain the absorbed point's former center as an anchor in the surviving Defensive Point.

This preserves wide/ovoid territorial intent.

Do not recalculate the merged force into a perfect single circle.

---

# 34. Preserving Wide / Ovoid Defensive Areas

## LOCKED DIRECTION

After absorption, territory should remain biased toward the spatial distribution of its anchors.

Example:

```text
Point A + Point B
-> one logical Defensive Point
-> anchors [A_center, B_center]
-> elongated/ovoid territory
```

The shape may relax organically over time, but should not instantly collapse into a circular blob that destroys the player's horizontal coverage intent.

---

# 35. Friendly Reinforcement via Route Endpoint

## LOCKED FOR PROTOTYPE

If the final endpoint of an open movement route lands inside a friendly Defensive Area:

```text
that squad becomes inbound reinforcement to that Defensive Point
```

The route may pass through other friendly Defensive Areas without joining them.

Only the final endpoint captures the route into a reinforcement assignment.

This prevents accidental reinforcement.

---

# 36. Reinforcement Preview Focus Treatment

## LOCKED UX DIRECTION

When a route endpoint enters an existing friendly Defensive Area:

Do not rely only on increasing brightness.

Instead:

- slightly darken the surrounding local region;
- keep the target Defensive Area readable;
- show a faint projected post-reinforcement territory shape;
- show instability warning if relevant.

This should feel like visual focus, not another bright flashing element.

Final styling is deferred to UI/UX.

---

# 37. Enemy Defensive Areas as Tactical Obstacles

## LOCKED DIRECTION

An active enemy Defensive Area should matter to movement.

If an advancing route intersects an active enemy Defensive Area:

```text
squad engages the position
-> must break / defeat it before continuing the original route
```

A PENDING empty enemy point should not magically block movement.

The exact interception implementation may be simplified initially.

---

# 38. Opposing Defensive Area Pressure

## LOCKED DIRECTION, PHASED IMPLEMENTATION

When active opposing Defensive Areas contact each other:

- their shared boundary may compete based on defensive pressure;
- the front can visibly move back and forth;
- one side may compress the other.

Do not allow a large point to remotely defeat an enemy point merely because its desired mathematical radius would overlap.

Pressure should matter where active territories physically contact.

### RECOMMENDED PHASING
Implement same-side territory/absorption first.

Then enable opposing pressure once the friendly solver is stable.

---

# 39. Enemy Defensive Point Defeat by Pressure

## FUTURE/SECOND PHASE OF CURRENT SYSTEM

If an enemy Defensive Point is compressed below viability by opposing territorial pressure:

```text
point breaks
-> surviving defenders enter RETREATING
```

This is an alternative to killing every defender.

It should be visually readable before it becomes a major source of defeats.

---

# 40. Broken Defender Rout

## LOCKED FOR IMPLEMENTATION

When a Defensive Point is defeated/broken, surviving assigned defenders enter:

```text
RETREATING
```

Retreat behavior:

- destination = own deployment/reinforcement zone;
- movement speed = 1.5x normal Advance movement speed;
- never return fire;
- do not stop to engage enemies;
- cannot establish or reinforce a Defensive Point while retreating;
- cannot receive normal tactical commands during retreat;
- take increased incoming damage;
- upon reaching deployment zone:
  - clear RETREATING;
  - return to normal ADVANCE behavior.

### PROVISIONAL TUNING
Start with approximately:
```text
retreat damage taken multiplier = 1.25x
```

This must be tuned carefully because the retreating units are already unable to fire.

---

# 41. Rout Snowball Risk

## REQUIRED PLAYTEST WATCH

A broken position creates two simultaneous advantages:

1. winner gains Breakthrough;
2. loser routs and becomes easier to damage.

This may create runaway cascades.

Do not remove the system preemptively.

Expose tuning values and watch:

```text
Point A falls
-> routed defenders take losses
-> attackers get Breakthrough
-> Point B falls before recovery
-> Point C falls
```

If this is too common, tune one variable at a time.

Possible levers:
- Rout damage multiplier;
- Breakthrough magnitude;
- Breakthrough duration;
- duration conversion cap;
- refresh cap.

---

# 42. Breakthrough Reward

## LOCKED FOR PROTOTYPE

When a squad materially participates in defeating/breaking an enemy Defensive Point:

- surviving members of that squad receive a small heal;
- surviving members receive a temporary non-stacking combat buff;
- no movement speed bonus.

Possible buff components:
- damage;
- fire rate;
- or a moderate combination.

Do not use movement speed because it may make troops charge farther/faster than the player intended.

---

# 43. Breakthrough Eligibility

## LOCKED FOR FIRST TEST

Use squad-level eligibility.

If at least one member of a squad materially damaged defenders associated with the enemy Defensive Point during the relevant combat window:

```text
all living members of that squad receive Breakthrough
```

This is intentionally generous for the first prototype.

If too strong, tighten later.

---

# 44. Breakthrough Heal Overflow -> Duration

## LOCKED MECHANIC

Efficient attackers should not be penalized because they were already healthy.

Conceptually:

```text
heal_budget = H
actual_heal = min(H, missing_health)
unused_heal = H - actual_heal
```

Unused heal should increase the temporary buff duration.

### PROVISIONAL RULE

Convert unused-heal percentage into the same percentage of extra duration.

Example:

```text
0% heal wasted -> 1.0x base duration
50% heal wasted -> 1.5x base duration
100% heal wasted -> 2.0x base duration
```

Cap the duration extension.

### PROVISIONAL CAP
```text
maximum duration = 2.0x base duration
```

---

# 45. Breakthrough Stacking

## LOCKED FOR PROTOTYPE

Breakthrough should not stack in magnitude.

If a squad earns another Breakthrough while already buffed:

- apply the new healing normally;
- refresh/extend duration;
- respect the duration cap;
- do not multiply damage/fire-rate bonus magnitude.

---

# 46. No Automatic Pursuit Logic After Breakthrough

## LOCKED DIRECTION

Do not add special "chase routed enemies" AI for player-controlled troops.

After a position breaks, attackers continue according to their existing command/intent.

Advance and Defend remain the authoritative tactical behaviors.

---

# 47. Card Package Rules

## LOCKED FOR PROTOTYPE

A deployment package may contain a maximum of 3 cards.

It must contain at least 1 Unit card.

Allowed:

```text
1 Unit
1 Unit + 1 Modifier
1 Unit + 2 Modifiers
2 Units
2 Units + 1 Modifier
```

Not allowed:

```text
0 Units
3 Units
2 Units + 2 Modifiers
more than 3 total cards
```

Equivalent rule:

```text
max total cards = 3
max Unit cards = 2
max Modifier cards = 2
minimum Unit cards = 1
```

---

# 48. Why 3 Cards

## LOCKED DESIGN INTENT

The 3-card cap creates a deckbuilding tradeoff:

### Specialized package
```text
1 Unit + 2 Modifiers
```

### Mixed package
```text
2 Units + 1 Modifier
```

Do not increase to 4 cards unless playtesting shows the 3-card limit is unnecessarily restrictive.

---

# 49. Two Unit Cards Build One Squad

## LOCKED FOR PROTOTYPE

If two Unit cards are selected:

```text
they deploy as ONE mixed squad
```

They share:

- one squad ID;
- selection state;
- drawn route;
- intent;
- Defensive Point assignment;
- Breakthrough state;
- squad-level lifecycle.

They are not two squads travelling together.

---

# 50. Modifier Application

## LOCKED FIRST-PASS RULE

If a Modifier applies to both Unit cards, apply it to the whole package.

Example:

```text
Conscript + Assault + Commander Mojo
```

Modifier applies to both unit components if compatible.

The final blueprint/deployment preview should clearly display:

- quantity by unit type;
- total quantity;
- modifiers;
- total Command cost.

---

# 51. Modifier Resolution Order

## LOCKED ENGINEERING REQUIREMENT

Modifier selection order should not accidentally change results unless a future card explicitly makes ordering meaningful.

Use deterministic modifier resolution.

Unit-card order may have formation meaning.

Modifier-card order should not by default.

---

# 52. Mixed Formation — Proportional Interleaving

## LOCKED FOR PROTOTYPE

Mixed squads should blend unit types throughout the formation rather than create two isolated blocks.

Example:

```text
12 Conscripts
4 Assault
```

Approximate ratio:

```text
3 Conscripts : 1 Assault
```

Distribute unit types proportionally through available formation slots.

Use a deterministic proportional / weighted distribution algorithm.

Do not hard-code only specific pairings.

---

# 53. Unit Card Order = Front / Rear Priority

## LOCKED FOR PROTOTYPE

Unit selection order has tactical formation meaning.

### First Unit card
Front-priority.

### Second Unit card
Rear-priority.

Example:

```text
Assault -> Conscript
```

Try to place Assault members at the heads/front of files.

Example:

```text
Conscript -> Assault
```

Try to place Assault members toward the rear.

This meaning should survive formation resizing where practical.

---

# 54. Front-Priority Assignment

If there are fewer front-priority units than formation files:

- distribute them evenly across the frontmost available file positions;
- do not clump all of them on one side.

If there are more than enough to fill the front row, continue proportionally deeper.

Exact packing may be implementation-driven.

---

# 55. Blueprint Formation Assignment

Recommended order:

```text
1. generate formation slots
2. determine slot depth/front-to-back order
3. assign first Unit card with front priority
4. assign second Unit card with rear priority
5. preserve proportional interleaving laterally
```

The system should produce consistent results for identical card order + formation dimensions.

---

# 56. Strategic Squad Travel Speed

## LOCKED FOR PROTOTYPE

A mixed squad's route/travel speed is based on the slowest **living** member type currently in that squad.

Example:

```text
Rifle + Assault
-> travel at Rifle speed
```

If all Rifle members die:

```text
only Assault remain
-> squad may now travel at Assault speed
```

Recalculate when composition changes.

Smoothly interpolate speed changes if abrupt visual changes look bad.

---

# 57. Tactical Combat Reposition Speed

## LOCKED FOR PROTOTYPE

Individual soldiers retain their own native movement speed during local combat repositioning.

This is essential for mixed squads.

Example:

```text
Rifle + Assault squad
travels together at Rifle pace

combat begins:
Rifles stop at effective range
Assault uses native faster speed
Assault moves closer within local cohesion leash
```

Assault should not be artificially reduced to Rifle tactical speed while repositioning in combat.

---

# 58. Mixed-Squad Combat Cohesion Leash

## LOCKED DIRECTION

Individual soldiers may reposition according to their weapon range and native speed, but should remain within a reasonable local squad cohesion area.

Use a moving squad combat body/centroid rather than anchoring the leash to the original engagement point.

This prevents faster/shorter-range units from being permanently trapped or from sprinting arbitrarily far away.

---

# 59. Advance vs Defend Reformation for Mixed Squads

## LOCKED FOR PROTOTYPE

### Advance
After combat:
- squad regroups enough to continue route/travel;
- do not require pristine formation restoration;
- preserve battlefield disorder.

### Defend
After combat:
- survivors return to assigned defensive positions;
- recalculate/reform properly.

---

# 60. Front-Loaded Assault Risk

## REQUIRED PLAYTEST WATCH

`Assault -> Conscript` may cause Assault members to absorb disproportionate early casualties.

This may be an intended tactical tradeoff.

Do not immediately remove card-order formation meaning if this happens.

First consider:
- spacing;
- local combat positioning;
- engagement behavior;
- formation depth.

---

# 61. Future Defensive Specialist Compatibility

## FUTURE EXTENSION

Architecture should permit units whose combat role changes with intent.

Example machine-gun team:

### ADVANCE
- weapon packed;
- moves normally;
- cannot use full firing mode.

### MOVING_TO_DEFEND
- packed;
- moving.

### DEFENDING
- setup delay;
- weapon deployed;
- strong stationary fire capability.

### Leaving defense
- pack weapon;
- resume movement.

Do not implement this unit now unless separately requested.

Do not encode defense-area size rules that make such units difficult to add later.

---

# 62. New Squad Blueprint Flow

## LOCKED CURRENT FLOW

New deployment:

```text
select Unit card(s) + optional Modifier(s)
-> drag/confirm package
-> Blueprint overlay
-> configure initial formation
-> issue drawn battlefield order
-> validate
-> commit cards/resources
-> deploy
```

Do not spend cards/resources until the full deployment + command is valid.

---

# 63. Existing Squad Re-Command Flow

## LOCKED

Existing squads do not reopen the full formation blueprint.

Flow:

```text
select squad(s)
-> begin command gesture
-> Planning Mode
-> draw route / loop
-> validate
-> execute
```

Defend automatically manages exact defensive formation internally.

---

# 64. Success Feedback

## LOCKED PRINCIPLE

Accepted commands should have immediate visual acknowledgement.

Examples:

### Advance / movement
- rough route resolves/snaps into clean tactical path/arrow;
- brief pulse/flash;
- command executes.

### Defend
- loop resolves into Defensive Point marker / territory preview;
- shield appears;
- brief pulse/flash;
- command executes.

### Reinforce
- target Defensive Area receives focus treatment;
- projected future shape visible during preview;
- accepted order clearly acknowledges target.

Final art/VFX is deferred.

---

# 65. Failure Feedback

## LOCKED PRINCIPLE

Failed commands should create contextual iconographic feedback near the command origin / selected squads / failed target.

Animation direction:

- appear clearly;
- float upward slowly;
- accelerate;
- fade away.

Use icons over letters.

---

# 66. Failure Reasons

At minimum support:

```text
UNRECOGNIZED_GESTURE
AMBIGUOUS_GESTURE
INVALID_DEFEND_LOCATION
NO_SELECTED_UNITS
SQUAD_DESTROYED
POSITION_UNREACHABLE
COMMAND_CANCELLED
```

Presentation should be separated from gameplay logic.

---

# 67. Future Failure Animation: Invalid Drawing

## DEFERRED POLISH

For invalid gesture:

- piece of paper appears;
- floating pencil draws invalid shape;
- pencil lifts;
- paper rips in half;
- pieces fade away.

Do not block gameplay implementation on this animation.

---

# 68. Casualties During Command Input

## LOCKED FOR PROTOTYPE

If some selected soldiers die:

- continue with survivors.

If one selected squad dies but others survive:

- remove dead squad from selection;
- continue command with remaining squads.

If all selected units die:

- cancel/fail command;
- show `SQUAD_DESTROYED`;
- clear selection;
- exit Planning Mode safely.

---

# 69. Enemy AI: Shared Systems

## LOCKED ARCHITECTURE

Enemy AI should use the same underlying order APIs and gameplay systems as the player.

Player gesture interpretation eventually produces commands such as:

```text
issue_route_then_advance(...)
issue_defend(...)
reinforce_defensive_point(...)
```

AI should call those same command-level functions directly.

Do not create a separate AI-only movement/defense/combat model.

Shared systems must handle:

- Defensive Areas;
- pressure;
- absorption;
- Breakthrough;
- Rout;
- movement;
- combat;
- reinforcement.

---

# 70. Enemy AI Deployment Delay

## LOCKED FOR PROTOTYPE

Add a minimum:

```text
1.0 simulation-second delay
```

between completed AI squad/card-package deployments.

This is a delay between deployment packages, not between cards within a package.

The cooldown should use simulation time.

Therefore Planning Mode slowdown also slows AI deployment cadence relative to real-world time.

---

# 71. Enemy AI Card Package Legality

## LOCKED

AI obeys the same package rules:

```text
max 3 cards
1–2 Unit cards
0–2 Modifier cards
at least 1 Unit
```

AI package selection can remain simple.

Do not build sophisticated card-combo search yet.

---

# 72. Enemy AI Package Heuristic

## PROVISIONAL

A simple heuristic is sufficient:

```text
choose affordable Unit card
optionally add compatible second Unit
optionally add applicable Modifier
deploy package
wait deployment cooldown
```

The AI does not need optimal deckbuilding logic yet.

---

# 73. Enemy Defensive Doctrine Selection

## LOCKED FOR PROTOTYPE

At match start randomly choose one of two defensive doctrines:

```text
LINE
TRIANGLE
```

Use roughly 50/50 selection initially.

Provide a developer/debug override to force either doctrine.

---

# 74. Defensive Position Horizontal Anchors

Use battlefield-width percentages.

### Left
```text
25% from left edge
```

### Center
```text
50% width
```

### Right
```text
25% from right edge / 75% width
```

Exact defensive depth from the enemy deployment side should be a tunable value.

---

# 75. AI Establishment Trigger

## LOCKED DIRECTION

The AI should not instantly spawn directly into a completed Defensive Point.

The first relevant squads should:

```text
spawn
-> ADVANCE
-> reach configured defense trigger depth
-> if doctrine position requires defenders:
       establish/reinforce that point
   else:
       continue ADVANCE
```

This makes the AI visibly establish its battlefield positions.

---

# 76. LINE Doctrine

## LOCKED FOR PROTOTYPE

Three planned Defensive Points:

```text
Left:   25% width
Center: 50% width
Right:  75% width
```

Approximately the same battlefield depth.

### Priority
1. Establish/fill outside positions first.
2. Then establish/fill center.
3. When all minimums are met, additional squads Advance.

### Minimum established defender targets

```text
Left:   >= 10
Center: >= 10
Right:  >= 10
```

These are minimums, not exact caps.

If a squad puts the point above 10, that is acceptable.

---

# 77. LINE Reinforcement Behavior

If a point later drops below its target:

- newly available/uncommitted squads may reinforce it.

Do not continuously reroute every already-advancing squad because a point drops from 10 to 9.

Evaluate reinforcement need mainly when a new/uncommitted squad becomes available.

If both outer positions need reinforcement:
- choose lower defender count;
- random/alternating tie-break is acceptable.

---

# 78. TRIANGLE Doctrine

## LOCKED FOR PROTOTYPE

Use three points:

- left rear/side point;
- right rear/side point;
- forward center/apex point.

The center/apex is the doctrine's priority position.

### Minimum established defender targets

```text
Center/apex: >= 20
Left:        >= 10
Right:       >= 10
```

### Priority
The center is prioritized until it reaches 20.

Then fill side points.

Once all targets are satisfied:
- additional squads Advance.

---

# 79. TRIANGLE Center Priority

Example:

```text
Center = 14
Left   = 3
Right  = 10
```

Next reinforcement should still prioritize:

```text
Center
```

until Center reaches 20.

This is intentional.

---

# 80. AI Excess Forces

## LOCKED

When doctrine defensive minimums are currently satisfied:

```text
new additional squads -> ADVANCE
```

AI should not endlessly overfill all Defensive Points by default.

---

# 81. AI Understrength Recovery

If a defensive point later becomes understrength:

- newly available squads may reinforce according to doctrine priority.

Do not aggressively recall every active attacking squad.

This keeps AI behavior calmer and more readable.

---

# 82. AI Does Not Need Smart Flanking Yet

## DEFERRED

Initial AI does not need to reason deeply about:

- curving around player Defensive Areas;
- avoiding all enemy strongpoints;
- optimal territorial pressure;
- sophisticated multi-route attacks.

Let simple Advance interact with player Defensive Areas naturally.

This is useful for validating whether Defensive Areas function as fronts.

---

# 83. AI Consequences Are Shared

## LOCKED

Do not put special rout/breakthrough logic inside AI.

The shared gameplay systems should automatically handle:

- AI Defensive Point breaks;
- AI squad rout;
- AI deployment-zone recovery;
- player Defensive Point breaks;
- AI Breakthrough rewards.

Both sides obey the same underlying rules.

---

# 84. No-Hold / Enemy Deployment Zone

## LOCKED

The enemy deployment / No-Hold zone is not a generic movement restriction.

Allowed:
- Advance through it;
- combat in it;
- route through it.

Not allowed:
- Defensive Area territory may not claim cells inside it.

Growth should press against the border and redistribute into other legal directions when possible.

---

# 85. Map Width

## LOCKED FOR THIS PASS

Do **not** enlarge the map in this implementation pass.

Keep current battlefield dimensions.

Revisit wider battlefield testing only after the Defensive Area, routing, mixed-squad, and AI systems are stable enough to evaluate independently.

---

# 86. Blueprint / UI Polish Status

## DEFERRED

The functional Blueprint overlay may remain rough.

A dedicated UI/UX pass will later address:

- layout;
- hierarchy;
- iconography;
- visual balance;
- final command previews;
- final Defensive Area rendering;
- organic membrane appearance;
- tutorial/reference presentation.

Do not block the mechanics pass on final UI quality.

---

# 87. Tutorial / Reference Library

## FUTURE EXTENSION / UIUX PASS

The final game should eventually have:

- strong onboarding;
- a reference/Field Manual;
- short animated demonstrations / GIF-like command examples.

Likely reference entries:

```text
Advance
Move & Advance
Defend
Move & Defend
Reinforce Position
Withdraw from Position
Curved Route
Breakthrough
Rout
```

This is not required for the current functional implementation.

---

# 88. Defensive Area Visual Future

## DEFERRED POLISH

Eventually Defensive Areas should look like organic membranes/bubbles.

Desired visual ideas:

- soft organic free edges;
- straight/tensed shared contact fronts;
- sheared/angled contact fronts where pressure distribution differs;
- elastic pushing;
- ripple when pressure changes;
- visible absorption/pop;
- relaxation after pressure disappears.

Do not implement literal fluid simulation.

Mechanics should be stable first.

---

# 89. Recommended Backend Responsibilities

Names may follow project conventions.

## Squad / SquadController
Own:
- member units;
- mixed composition;
- current intent;
- route;
- selection;
- combat cohesion;
- current Defensive Point assignment;
- Breakthrough state;
- Retreat state.

## SelectionManager
Own:
- click-member -> squad;
- Shift multi-select;
- toggle deselect;
- selection centroid.

## GestureRecognizer
Own:
- path sampling;
- simplification;
- open/closed classification;
- ambiguity detection;
- loop center extraction;
- route endpoint.

## CommandPlanningController
Own:
- Planning Mode;
- timescale;
- desaturation;
- gesture lifecycle;
- cancel/back behavior.

## CommandService / SquadOrderService
Own:
- route then Advance;
- route then Defend;
- reinforce Defensive Point;
- validation.

## DefensivePointManager
Own:
- point IDs;
- anchors;
- assigned/inbound squads;
- lifecycle;
- desired area;
- actual area;
- capacity;
- pressure;
- absorption;
- deletion.

## TerritorySolver
Own:
- territory cells;
- constraints;
- point competition;
- No-Hold clipping;
- neighbor boundaries;
- future opposing pressure.

## CombatRewardService
Own:
- Breakthrough eligibility;
- heal;
- duration conversion;
- non-stacking refresh.

## EnemyAIController
Own:
- doctrine;
- package deployment cadence;
- reinforcement priorities;
- Advance/Defend decisions.

---

# 90. Suggested Core Data

Conceptual only:

```text
Squad
{
    squad_id
    members[]
    unit_components[]
    current_intent
    route_waypoints[]
    selected
    defensive_point_id?
    breakthrough_state?
    retreating
}
```

```text
DefensivePoint
{
    point_id
    owner_team
    anchors[]
    assigned_squad_ids[]
    inbound_squad_ids[]
    lifecycle_state
    desired_area
    actual_area
    pressure
    capacity_state
}
```

```text
CommandResult
{
    success
    command_type
    affected_squad_ids[]
    route[]
    defensive_point_id?
    failure_reason?
}
```

---

# 91. Important Debug Data

For each Squad:

```text
squad_id
composition by unit type
living members
slowest strategic speed
current intent
route
defensive_point_id
selected
retreating
breakthrough remaining duration
```

For each Defensive Point:

```text
point_id
owner
lifecycle
anchors
established defender count
inbound defender count
desired area
actual area
capacity state
pressure
neighbors
```

For gesture recognition:

```text
raw point count
simplified point count
path length
start/end distance
closure metric
loop detected
ambiguous
terminal defensive point target
```

For AI:

```text
doctrine
deployment cooldown
defensive targets
current defender counts
next reinforcement priority
```

---

# 92. Acceptance Tests — Gesture Grammar

- [ ] Open straight stroke creates Move -> Advance.
- [ ] Open curved stroke creates Move -> Advance.
- [ ] Closed loop creates Defend.
- [ ] Open route ending in closed loop creates Move -> Defend.
- [ ] Clockwise loop works.
- [ ] Counter-clockwise loop works.
- [ ] Loop entry direction does not matter.
- [ ] Partial/ambiguous attempted loop does not become Advance.
- [ ] Ambiguous gesture preserves previous orders.
- [ ] Route jitter is simplified.
- [ ] Broad intentional curve is preserved.

---

# 93. Acceptance Tests — Selection

- [ ] Clicking one soldier selects whole squad.
- [ ] Bright white placeholder outline appears.
- [ ] Clicking selected squad deselects it.
- [ ] Shift+click adds squad.
- [ ] Shift+click selected squad removes it.
- [ ] Releasing Shift does not clear multi-selection.
- [ ] Right-click clears selection only when no deeper interaction is active.

---

# 94. Acceptance Tests — Planning Mode

- [ ] Selection alone does not slow game.
- [ ] Starting command input activates Planning Mode.
- [ ] Time scale transitions smoothly.
- [ ] Desaturation transitions smoothly.
- [ ] Command information stays readable.
- [ ] Success exits Planning Mode.
- [ ] Cancel exits safely.
- [ ] All-selected-units-dead exits safely.

---

# 95. Acceptance Tests — Defensive Point Lifecycle

- [ ] Loop creates new Defensive Point.
- [ ] Point becomes ACTIVE when defenders establish.
- [ ] Point remains if defenders die but inbound squad exists.
- [ ] Such point becomes PENDING.
- [ ] PENDING point reactivates when inbound squad arrives.
- [ ] Point disappears if no established defenders and no inbound squads remain.
- [ ] Inbound troops do not increase active area before arrival.

---

# 96. Acceptance Tests — Territory

- [ ] Defensive Area size increases with established defender count.
- [ ] Defensive Area shrinks with casualties.
- [ ] Area does not enter No-Hold cells.
- [ ] Area does not leave map.
- [ ] Area expands into other legal directions when constrained.
- [ ] Area stops when desired area is satisfied.
- [ ] Two Defensive Areas never overlap.
- [ ] Shared contact edge is readable.
- [ ] Free boundary may remain rounded.
- [ ] Capacity states update correctly.

---

# 97. Acceptance Tests — Friendly Absorption

- [ ] Two adjacent friendly points can press against one another.
- [ ] Weak point may become Critical if it cannot retain enough area.
- [ ] Strong point may absorb unsustainable weak point.
- [ ] Weak point soldiers join strong point.
- [ ] Weak point backend object is deleted.
- [ ] Weak point center becomes anchor on surviving point.
- [ ] Surviving shape remains spatially elongated rather than snapping to a circle.
- [ ] Absorption can trigger further pressure recalculation.

---

# 98. Acceptance Tests — Reinforcement

- [ ] Route endpoint inside friendly Defensive Area targets that point.
- [ ] Passing through friendly area without ending there does not reinforce.
- [ ] Preview appears only during command drawing.
- [ ] Preview uses current + projected area distinction.
- [ ] Reinforcement target receives subtle focus treatment.
- [ ] Inbound squad is tracked by Defensive Point.
- [ ] Redirecting/killing final inbound squad removes empty Pending point.
- [ ] Reinforcement to near-Critical point produces warning.

---

# 99. Acceptance Tests — Rout

- [ ] Broken point causes surviving defenders to enter RETREATING.
- [ ] Retreat destination is own deployment zone.
- [ ] Retreat speed is 1.5x Advance speed.
- [ ] Retreating units never fire.
- [ ] Retreating units do not stop for combat.
- [ ] Retreating units take configured increased damage.
- [ ] Retreating units cannot Defend/reinforce.
- [ ] Reaching deployment zone returns them to ADVANCE.

---

# 100. Acceptance Tests — Breakthrough

- [ ] Participating squad receives Breakthrough.
- [ ] Whole living squad receives it if at least one member qualifies.
- [ ] Heal is applied up to missing health.
- [ ] Unused heal extends buff duration.
- [ ] Duration extension respects cap.
- [ ] Buff magnitude does not stack.
- [ ] Repeated Breakthrough refreshes/extends duration only.
- [ ] No movement speed bonus is applied.
- [ ] AI can earn Breakthrough under same rules.

---

# 101. Acceptance Tests — Card Packages

- [ ] 1 Unit legal.
- [ ] 1 Unit + 1 Modifier legal.
- [ ] 1 Unit + 2 Modifiers legal.
- [ ] 2 Units legal.
- [ ] 2 Units + 1 Modifier legal.
- [ ] 2 Units + 2 Modifiers illegal.
- [ ] 3 Units illegal.
- [ ] Modifier-only package illegal.
- [ ] Final quantity/cost shown before deployment.
- [ ] Resources/cards only commit after valid final deployment command.

---

# 102. Acceptance Tests — Mixed Squads

- [ ] Two Unit cards produce one squad.
- [ ] Mixed unit types are proportionally interleaved.
- [ ] First Unit card gets front priority.
- [ ] Second Unit card gets rear priority.
- [ ] Front-priority units distribute evenly across file heads.
- [ ] Formation is deterministic for same inputs.
- [ ] Slowest living member controls strategic travel speed.
- [ ] Speed updates when slowest type is eliminated.
- [ ] Individual soldiers retain native tactical reposition speed.
- [ ] Assault can close distance within cohesion leash.
- [ ] Advance does not fully reform after casualties.
- [ ] Defend does reform after combat.

---

# 103. Acceptance Tests — AI Deployment

- [ ] AI waits at least 1.0 simulation seconds between package deployments.
- [ ] Cooldown slows naturally during Planning Mode.
- [ ] AI obeys same package legality.
- [ ] AI uses same underlying squad command APIs.
- [ ] AI can deploy mixed squads if heuristic selects two Units.

---

# 104. Acceptance Tests — LINE Doctrine

- [ ] Doctrine can be forced in debug.
- [ ] Left position ~25% width.
- [ ] Center ~50%.
- [ ] Right ~75%.
- [ ] Outside positions prioritized before center.
- [ ] Left target >=10.
- [ ] Center target >=10.
- [ ] Right target >=10.
- [ ] Extra squads Advance when targets satisfied.
- [ ] Newly available squads reinforce later deficits.
- [ ] Existing attackers are not constantly recalled for minor deficits.

---

# 105. Acceptance Tests — TRIANGLE Doctrine

- [ ] Doctrine can be forced in debug.
- [ ] Forward center/apex exists.
- [ ] Side positions exist.
- [ ] Center target >=20.
- [ ] Side targets >=10 each.
- [ ] Center remains priority until >=20.
- [ ] After center target, side deficits are filled.
- [ ] Extra squads Advance when all targets satisfied.

---

# 106. Playtest Questions

## Gesture
- Do players think about tactics rather than recognition rules?
- Do curved paths feel useful rather than fussy?
- Are ambiguous attempted loops rejected reliably?
- Is loop closure forgiving enough?

## Defensive Areas
- Do territory changes visually communicate strength/loss?
- Does pressure feel understandable?
- Does absorption feel like a natural bubble interaction rather than arbitrary deletion?
- Are elongated anchor-based shapes useful?
- Do Critical warnings arrive early enough?

## Reinforcement
- Does ending a route inside a point feel intuitive?
- Does projected territory help decision-making?
- Does player understand that inbound troops do not count yet?

## Rout / Breakthrough
- Does breaking a point feel rewarding?
- Is rout too lethal?
- Does Breakthrough cause excessive cascading wins?
- Does health-to-duration conversion feel fair?

## Mixed Squads
- Does card order create useful formation differences?
- Does front-loaded Assault feel tactical or suicidal?
- Do fast close-range units use their native speed correctly in combat?
- Does slowest-member strategic speed feel natural?

## AI
- Do LINE and TRIANGLE create visibly different battles?
- Does AI reinforce enough without feeling obsessed with thresholds?
- Is 1-second deployment cadence readable and fair?
- Does simple AI provide useful pressure without hiding system behavior?

---

# 107. Known Balance Risks

## Breakthrough + Rout snowball
High priority to watch.

## Friendly bubble absorption
Could unexpectedly consolidate positions and alter spatial coverage.

## Large mixed squads
May create oversized territory/collision/pathing stress.

## Front-priority Assault
May create disproportionate losses.

## AI central fortress
TRIANGLE center at 20 may dominate current map depending on territory scaling.

## Modifier + two Units
Whole-package modifiers may create very large/high-value squads.

Do not pre-nerf these before observing them.

---

# 108. Deferred Systems

Do not block current implementation on:

- larger map;
- final Defensive Area membrane VFX;
- local soldier-density pressure;
- sophisticated AI flanking;
- machine-gun / defensive-specialist unit;
- permanent veterancy;
- advanced tutorial/reference library;
- final Blueprint UI;
- final failure animations;
- final audio cues.

---

# 109. Recommended Implementation Order

1. Finalize squad/card package data model for mixed squads.
2. Implement 3-card package legality.
3. Implement proportional mixed formation.
4. Implement first-card front priority / second-card rear priority.
5. Implement strategic slowest-living-member travel speed.
6. Implement native tactical reposition speed + cohesion leash.
7. Implement open curved route capture + simplification.
8. Implement full-loop Defend recognition.
9. Implement ambiguity-safe failure.
10. Implement route endpoint -> friendly Defensive Point reinforcement.
11. Convert fixed defense circle backend to Defensive Point + dynamic Defensive Area.
12. Add desired area from established defenders.
13. Add territory grid / legal-cell constraints.
14. Add No-Hold/map-edge clipping.
15. Add same-side Defensive Area contact and no-overlap.
16. Add capacity states.
17. Add friendly point absorption + anchor inheritance.
18. Add Pending point lifecycle and inbound tracking.
19. Add reinforcement projected-area preview.
20. Add rout state.
21. Add Breakthrough reward.
22. Add 1-second AI deployment cooldown.
23. Add LINE doctrine.
24. Add TRIANGLE doctrine.
25. Add AI reinforcement thresholds.
26. Validate all shared systems on both player and AI.
27. Playtest before advanced VFX/UIUX.
28. Only after stable: add opposing-area pressure/popping if not already included.

---

# 110. Definition of Done for This Prototype Pass

This pass is successful when:

> The player can build specialized or mixed squads from up to three cards, with Unit-card order affecting front/rear formation priority; mixed squads travel at the slowest living member's strategic speed while individual soldiers use native speed in combat; the player can draw open curved routes, closed Defend loops, and routes that reinforce existing Defensive Points; Defensive Points own dynamic non-overlapping bubble-like territory derived from established defenders; friendly points can pressure and absorb one another while preserving anchors; broken defenders rout to deployment at 1.5x speed without firing and with increased vulnerability; attackers earn a non-stacking Breakthrough reward; and the enemy AI uses the same systems with a 1-second deployment delay and randomly selected LINE or TRIANGLE defensive doctrine.

The current map size remains unchanged.

After this pass is mechanically stable, conduct a playtest before:
- enlarging the battlefield;
- polishing the Blueprint UI;
- implementing final bubble/membrane VFX;
- adding more sophisticated AI.
