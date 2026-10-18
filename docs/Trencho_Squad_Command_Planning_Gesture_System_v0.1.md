# Trencho — Squad Command & Command Planning System Specification
**Version:** 0.1  
**Purpose:** Developer handoff for the next mechanics prototype  
**Status:** Functional prototype specification  
**Primary goal:** Implement the agreed squad-command interaction model before UI/UX polish.

---

# 1. Prototype Objective

This iteration should replace the current deployment-restriction-heavy interaction with a command system centered on **player intent**.

The player should be able to:

1. Create a squad from cards.
2. Configure its initial formation.
3. Issue one of two commands:
   - **Advance**
   - **Defend**
4. Re-select existing squads later.
5. Re-issue Advance or Defend orders.
6. Multi-select squads.
7. Receive immediate success/failure feedback.
8. Use commands in a slowed, tactical "Command Planning Mode."

The design goal is:

> The player tells squads what they want them to do.  
> The simulation handles detailed soldier placement, movement, combat, and reformation.

This iteration should prioritize **functionality, clarity, and testability**, not final visual polish.

---

# 2. Systems Explicitly Replaced / Removed

## Remove current deployment-zone restriction model

Do not require the player to deploy only into predefined lane/deployment zones.

The old model where occupancy or enemy proximity could prevent ordinary deployment should no longer be the core interaction rule.

## Remove destination-first movement for normal Advance deployments

Advancing squads should not be required to:

```text
spawn
-> reach a player-drawn destination formation
-> then begin normal advance
```

Advance is now an intent, not a destination.

---

# 3. Core Squad Intents

Every active squad has one persistent tactical intent:

```text
ADVANCE
DEFEND
```

No additional tactical intents are required for this prototype.

Do not add:

```text
PATROL
RETREAT
FOLLOW
CHARGE
GUARD
HOLD_FIRE
```

unless later testing creates a specific need.

---

# 4. ADVANCE Intent

## Player-facing meaning

> Continue moving toward the enemy whenever not actively fighting.

## Behavior

A squad with `ADVANCE` intent:

```text
if valid enemy is engageable:
    engage enemy
else:
    advance toward enemy side
```

After combat ends:

```text
resume ADVANCE
```

## Formation behavior

Advancing squads do **not** automatically reform after casualties.

If the formation becomes irregular during combat:

```text
retain battlefield-disrupted positions
```

Do not constantly reposition survivors into a clean shape.

This is intentional.

Desired visual/gameplay principle:

> Advance accepts battlefield chaos.

---

# 5. DEFEND Intent

## Player-facing meaning

> Move to this area, establish a defensive position, fight enemies within the defended area, and return to position when threats disappear.

A Defend order includes:

```text
defense_center
defense_radius
```

The defense circle is the squad's permitted defensive area.

---

# 6. Defend State Flow

Recommended state flow:

```text
DEFEND order issued
        |
        v
MOVING_TO_DEFEND
        |
        +---- enemy encountered ----> ENGAGING
        |                                |
        |                                |
        <------ immediate threat ---------
        |
        v
DEFENDING
        |
        +---- valid enemy in defense area ---> ENGAGING_DEFENSIVELY
        |                                        |
        <------------ no valid threats ----------
        |
        v
RETURN_TO_DEFENSE_POSITIONS
        |
        v
DEFENDING
```

Exact internal state names may follow existing project conventions.

The important contract is behavior, not naming.

---

# 7. Defense Area / Squad Leash

The defense circle belongs to the **Defend order**.

All squads included in that order may engage enemies inside that same defense area.

## Targeting behavior

While defending, each soldier should:

1. Consider valid enemies inside the defense area.
2. Prefer enemies it can already shoot.
3. Among immediately shootable enemies, prefer the nearest or existing project-standard "first valid" target.
4. If no target is currently in weapon range, the soldier may reposition inside the defense area to engage.
5. Never chase a target beyond the defense boundary.
6. When no valid enemies remain, return to assigned defense positions.

Do not force the entire squad to focus-fire one target unless existing targeting rules already do so.

---

# 8. Defense Formation

When a Defend order is active, the game owns exact soldier placement inside the defense area.

The player defines:

```text
center
radius
```

The game determines a sensible internal defensive formation.

## Reformation rule

Reformation is only required while defending.

### ADVANCE

```text
casualties occur
-> no automatic cleanup/reformation
```

### DEFEND

```text
casualties occur
-> continue fighting
-> after pressure ends / while returning
-> recalculate surviving formation
-> survivors re-form around defend positions
```

Avoid constant shuffling during active combat.

Reformation should happen primarily during:

```text
RETURN_TO_DEFENSE_POSITIONS
```

---

# 9. Defense Circle Auto-Expansion

If the player draws a defense circle too small to contain all selected surviving units:

> Automatically expand the defense circle to the minimum usable radius.

This behavior is intentionally different from the old deployment rectangle rule.

The defense circle is an **area intent**, not exact player-authored geometry.

## Required behavior

```text
requested radius < minimum usable radius
-> expand radius
-> visibly show final radius
-> accept order if otherwise legal
```

Recommended temporary feedback:

```text
Defense area expanded to fit squad
```

This message may be debug-only initially.

Expose:

```text
minimum_defense_radius
maximum_defense_radius
```

as tunable values where practical.

---

# 10. Multiple Squads Defending One Area

For the first implementation:

> Multiple selected squads receiving one Defend order remain separate squads internally, but share one defense area/order.

Example:

```text
Rifle Squad
Assault Squad
Conscript Squad
        |
        v
one Defend order
        |
        v
one defense circle
```

Preserve individual squad ownership/data internally.

Where practical, keep squads spatially coherent inside the defense area rather than completely intermixing soldiers.

## Future alternative

A hidden temporary "super-squad" backend representation may later be tested if separate-squad handling proves awkward.

Do **not** implement the temporary super-squad now unless needed to solve a concrete implementation blocker.

---

# 11. Squad Selection

## Single selection

Clicking any soldier selects that soldier's entire squad.

Do not provide individual-soldier command selection.

## Selected state

Selected squad members should receive a:

```text
bright white outline
```

or equivalent clearly visible selection treatment.

The UI/UX specialist may refine final treatment later.

For this prototype, visibility matters more than polish.

## Toggle behavior

Clicking a squad that is already selected:

```text
deselect that squad
```

---

# 12. Multi-Selection

Use:

```text
Shift + Click
```

to add or remove squads from the current selection.

## Important accepted rule

Releasing Shift does **not** clear the current multi-selection.

Shift is only required to modify the selection.

Selection persists until:

- player toggles squads off;
- player clears selection;
- selected squads are destroyed;
- current interaction explicitly changes selection.

This supersedes the earlier idea of requiring Shift to remain held.

---

# 13. Selection Ownership

Multi-selecting squads does not permanently merge them.

Each squad retains:

```text
squad_id
unit_type
source deployment/cards if tracked
surviving soldiers
current intent
current formation/order data
```

A shared order may apply to multiple selected squads without destroying their identity.

---

# 14. Selection Centroid

When one or more squads are selected, calculate a group centroid.

Conceptually:

```text
selection_centroid =
average position of all currently selected living units
```

or an equivalent robust center calculation.

Use this as the spatial origin for:

- command knob;
- Defend movement arrow;
- command feedback;
- failure feedback;
- shared command visualization.

The exact centroid formula can be implementation-driven.

---

# 15. Command Input Model

There is one command input tool:

> **one draggable order knob**

Do not show separate Advance and Defend buttons/knobs for the prototype.

The player's gesture determines intent.

---

# 16. Gesture Types

The system recognizes two broad gesture classes:

```text
LINE-LIKE
LOOP-LIKE
```

## Line-like

Maps to:

```text
ADVANCE
```

## Loop-like

Maps to:

```text
DEFEND
```

The player does not need to draw a mathematically exact line or circle.

---

# 17. Gesture Recognition Philosophy

Gesture recognition must be:

- forgiving;
- fast;
- cancellable;
- broad-shape based;
- not scored for accuracy;
- not a performance/dexterity bonus system.

Do **not** grant combat bonuses for gesture precision.

The player is communicating intent, not playing a rhythm/accuracy test.

---

# 18. Suggested Gesture Classification

The exact recognizer implementation is up to engineering.

A simple prototype classifier is acceptable.

## Candidate Advance classification

A gesture is likely `ADVANCE` when:

- stroke is elongated;
- overall curvature is low/moderate;
- endpoint is meaningfully far from start;
- stroke does not return near its origin.

## Candidate Defend classification

A gesture is likely `DEFEND` when:

- stroke has meaningful curvature;
- endpoint returns near the start;
- path approximately encloses an area;
- loop geometry is coherent enough to infer a center/radius.

Do not add full handwriting recognition unless the simple classifier fails.

---

# 19. Gesture Ambiguity

If the gesture cannot be confidently classified:

```text
command fails
reason = UNRECOGNIZED_GESTURE
```

Do not guess.

Keep the squads selected.

Do not spend Command/resources.

Do not alter existing squad intent.

Allow immediate retry.

---

# 20. New Squad Creation / Blueprint Flow

New squads use a temporary blueprint/setup overlay before their initial command.

Recommended flow:

```text
select Unit card
        |
optionally select Modifier card(s)
        |
drag / confirm selected package
        |
open Blueprint Overlay
        |
configure initial squad formation
        |
complete formation setup
        |
return to battlefield command phase
        |
draw:
    line -> ADVANCE
    loop -> DEFEND
        |
command succeeds
        |
commit cards/resources
        |
deploy squad
```

UI/UX polish of this overlay is deferred.

---

# 21. Blueprint Overlay — Functional Requirements

The blueprint overlay only needs to function well enough for testing.

It should show:

- selected card package;
- final unit quantity;
- total Command cost;
- squad formation preview;
- resizable formation box;
- confirmation/cancel behavior.

It should not require final art direction.

---

# 22. Blueprint Overlay — Presentation Principle

Use a temporary overlay rather than permanently shrinking the battlefield.

During blueprint interaction:

- live battlefield remains visible behind the overlay;
- battlefield visually recedes;
- squad setup receives visual priority.

The UI/UX specialist will refine exact layout after mechanics testing.

---

# 23. Existing Squad Re-Command Flow

Existing squads do **not** need to reopen the full blueprint formation editor.

Recommended flow:

```text
click soldier
-> whole squad selected

Shift+click
-> additional squad(s) selected

begin command interaction
-> Command Planning Mode activates

draw:
    line -> ADVANCE
    loop -> DEFEND

command accepted/cancelled
-> return to normal gameplay
```

For Defend:

- loop determines defense center/radius;
- game automatically arranges units inside that defense area.

For Advance:

- existing squads simply switch to Advance intent.

No reformation is required before advancing.

---

# 24. Command Planning Mode

Issuing an order should temporarily enter a tactical slow-motion mode.

## Planning Mode purpose

Give the player enough time to:

- draw;
- read battlefield context;
- understand command previews;
- make deliberate orders;

without fully pausing the game.

---

# 25. Command Planning Mode — Time Scale

Provisional tuning:

```text
normal_game_speed = 1.00x
planning_game_speed = 0.40x
```

Suggested test range:

```text
0.35x–0.50x
```

Use smooth interpolation.

Suggested transition duration:

```text
0.20–0.35 sec
```

These values are **PROVISIONAL**.

---

# 26. Planning Mode Activation

Do not enter Planning Mode merely because squads are selected.

Selection should be cheap.

Planning Mode begins when the player starts a meaningful command/setup interaction.

Examples:

```text
blueprint setup starts
```

or:

```text
selected squad command gesture begins
```

---

# 27. Planning Mode Exit

Planning Mode ends when:

- command succeeds;
- player cancels;
- selected squads are destroyed;
- command interaction otherwise terminates.

Smoothly restore:

```text
planning speed -> normal speed
```

Do not snap instantly if interpolation is practical.

---

# 28. Planning Mode — Visual Treatment

During Planning Mode:

> Smoothly desaturate the battlefield toward a pseudo-grayscale tactical look.

Do not necessarily grayscale the entire UI.

Recommended separation:

## Battlefield

- reduced saturation;
- optionally slightly reduced brightness/contrast;
- continues moving at reduced speed.

## Command UI

Keep more visually prominent:

- selection outlines;
- gesture path;
- defense circle;
- movement arrow;
- cards;
- resource information;
- success/failure feedback;
- No-Hold Zone.

This should create:

> battlefield recedes / command layer comes forward.

Exact visual tuning is for later UI/UX refinement.

---

# 29. Team Readability During Desaturation

Enemy identification must remain readable when the battlefield is desaturated.

Do not rely only on red team color.

Retain or strengthen non-color cues such as:

- headgear icon;
- outline;
- silhouette treatment;
- team marker.

The UI/UX specialist may refine this after functional testing.

---

# 30. No-Hold Zone

Create an enemy-side restricted zone where Defend orders are not permitted.

Purpose:

Prevent degenerate behavior such as permanently defending directly on top of enemy reinforcement/spawn locations.

This is a:

```text
NO-HOLD ZONE
```

not a general no-entry zone.

---

# 31. No-Hold Zone Rules

Inside the No-Hold Zone:

## Allowed

- advancing;
- combat;
- passing through;
- capturing/scoring.

## Not allowed

- establishing a new Defend order whose defense circle overlaps the restricted zone.

Recommended prototype rule:

> The entire defense circle must remain outside the No-Hold Zone.

If it overlaps:

```text
command fails
reason = INVALID_DEFEND_AREA
```

Keep selection active for immediate retry.

---

# 32. No-Hold Zone Visibility

The No-Hold Zone should **not** be permanently visible.

Fade it in contextually when:

- creating a new squad command;
- moving existing selected squads;
- especially when a Defend gesture is being attempted.

At minimum, show it during active command planning.

Fade it out when:

- command succeeds;
- command cancels;
- Planning Mode ends.

---

# 33. No-Hold Zone Visual Language

Prototype with:

- tactical hatching;
- boundary line;
- shield-with-slash icon or equivalent;
- optional semantic color.

Do not rely only on red.

Final visual treatment is deferred to UI/UX iteration.

---

# 34. Visible Squad Intent Icons

Keep player-facing intent icons minimal.

## ADVANCE

```text
No persistent icon
```

No icon means:

> Default Advance intent.

## MOVING TO DEFEND

```text
Arrow + Shield
```

## DEFENDING

```text
Shield
```

Do not expose every internal AI state to the player.

---

# 35. Internal States vs Visible Intent

Internally, the implementation may track:

```text
ADVANCING
MOVING_TO_DEFEND
ENGAGING_WHILE_ADVANCING
ENGAGING_WHILE_MOVING_TO_DEFEND
DEFENDING
ENGAGING_WHILE_DEFENDING
RETURNING_TO_DEFENSE
CAPTURING
EXITING
DEAD
```

But visible player-facing communication should remain primarily:

```text
none
arrow + shield
shield
```

unless later testing shows another visible state is needed.

---

# 36. Defend Command Visualization

When a Defend order succeeds:

1. Resolve final defense radius.
2. Show defense circle.
3. Place a shield icon at the circle center.
4. Draw an arrow from selected-unit centroid to defense center.
5. Flash/pulse the defense circle once.
6. Selected squads transition to `MOVING_TO_DEFEND`.
7. Show Arrow + Shield state.
8. Fade order visualization to a less intrusive state.
9. Restore normal game speed/color.

When squads arrive:

```text
Arrow + Shield -> Shield
```

---

# 37. Defense Circle Persistence

Do not keep every defense circle permanently bright.

Recommended:

## On command success

Show strongly.

## After confirmation

Fade significantly.

## When squad is selected again

Show its defense circle clearly again.

This avoids battlefield clutter.

---

# 38. Advance Command Visualization

When an Advance order succeeds:

1. Rough line gesture resolves into a clean arrow.
2. Arrow flashes once.
3. Selected squad outline pulses briefly.
4. Existing Shield / Arrow+Shield intent icons clear.
5. Squads switch to `ADVANCE`.
6. Gesture graphic fades.
7. Restore normal game speed/color.

No persistent Advance icon is required.

---

# 39. Success Feedback Principle

Successful commands should have immediate visible acknowledgement.

Use:

```text
flash / pulse / snap-to-clean-command graphic
```

rather than text-heavy confirmation.

Examples:

- Advance arrow flashes.
- Defense circle/shield flashes.
- New unit deployment formation flashes on commit.

The player should know:

> The order was accepted.

---

# 40. Failure Feedback System

Failed commands should create a contextual feedback event.

The event originates near:

```text
selection centroid
```

or the failed order location where more appropriate.

The failure indicator should:

1. appear clearly;
2. move upward slowly at first;
3. then accelerate;
4. fade away;
5. avoid requiring a corner notification feed.

This motion gives the player time to recognize the failure before it disappears.

---

# 41. Failure Reasons

Use explicit internal failure reason identifiers.

At minimum:

```text
UNRECOGNIZED_GESTURE
INVALID_DEFEND_AREA
SQUAD_DESTROYED
NO_SELECTED_UNITS
POSITION_UNREACHABLE
COMMAND_CANCELLED
```

Add implementation-specific reasons only when necessary.

---

# 42. Failure Icon Vocabulary

Use iconography rather than letters where practical.

Prototype icons may be simple placeholders.

## UNRECOGNIZED_GESTURE

Semantic concept:

```text
bad drawing / invalid order
```

Future polish concept:

- floating piece of paper;
- pencil draws malformed shape;
- pencil lifts away;
- paper tears in half;
- pieces fade away.

Do not block prototype functionality on this animation.

---

## INVALID_DEFEND_AREA

Semantic concept:

```text
shield + prohibition
```

Possible future animation:

- shield appears;
- slash/stamp marks it invalid;
- icon floats/fades.

---

## SQUAD_DESTROYED

Semantic concept:

```text
destroyed squad / skull / broken unit marker
```

Use if all selected units disappear before command completion.

---

## POSITION_UNREACHABLE

Semantic concept:

```text
broken arrow / obstruction
```

Do not trigger this too aggressively.

Pathfinding should attempt reasonable alternatives first.

---

# 43. Casualties During Command Input

## Partial losses

If some selected soldiers die while the player is issuing an order:

```text
continue command with surviving selected units
```

Do not fail the entire order.

Update selection automatically.

## Entire squad destroyed

If one selected squad is fully destroyed but others survive:

```text
remove destroyed squad from selection
continue command with survivors
```

## All selected squads destroyed

If no selected units remain:

```text
fail/cancel command
reason = SQUAD_DESTROYED
clear selection
exit Planning Mode
```

---

# 44. Right-Click Behavior

Right-click means:

> Back out of the current UI operation.

It should **not** silently rewrite tactical intent.

Use a contextual cancel stack.

## During gesture

Right-click:

```text
cancel current gesture
keep previous squad orders
```

## During blueprint/setup

Right-click:

```text
cancel current setup step / back out
resources/cards remain unspent unless prior rules explicitly committed them
```

## Squads selected, no active command

Right-click:

```text
clear selection
```

Squads continue whatever existing intent they already had.

This is the canonical right-click rule.

---

# 45. Command Cancellation

Cancelled commands should not:

- spend Command;
- consume/discard cards;
- alter existing squad intent;
- clear selection unless the current cancel level is selection itself.

Prototype text feedback may be:

```text
Order cancelled
```

but heavy messaging is not required.

---

# 46. New Squad Commit Timing

For new deployments:

Do not spend resources or consume cards until the complete setup/order is valid.

Recommended:

```text
select cards
-> blueprint formation
-> gesture command
-> command validated
-> commit resources/cards
-> deploy
```

If player cancels before final command acceptance:

```text
no cost
no discard
```

---

# 47. New Squad Initial Intent

Every new squad must receive:

```text
ADVANCE
or
DEFEND
```

before final deployment commit.

Do not deploy into an undefined tactical intent.

---

# 48. Formation Meaning for New Squads

Blueprint formation defines the squad's **initial formation geometry**.

It does not permanently force that formation forever.

## ADVANCE

Initial formation may degrade naturally through battle.

No automatic reformation after casualties.

## DEFEND

Formation may be reorganized when establishing or returning to defense.

---

# 49. Existing Squad Defend Auto-Formation

Existing squads do not need a formation editor before a new Defend order.

When the player draws a defense circle:

1. calculate final legal defense area;
2. auto-expand if needed;
3. calculate internal positions for all selected survivors;
4. preserve squad grouping where practical;
5. issue move-to-defend order.

This is intentionally simulation-assisted.

---

# 50. Multi-Squad Defend Formation Allocation

When multiple squads share one defense area:

Preferred first implementation:

- allocate sub-regions/positions per squad;
- keep squads reasonably clustered;
- avoid unnecessary complete interleaving;
- allow squads to share the defense leash.

Exact formation packing algorithm may be simple for prototype.

Visual quality can be improved later.

---

# 51. Command Planning Mode and Blueprint Relationship

Blueprint setup is one use of Planning Mode.

Expected flow:

```text
normal battle
-> player begins squad setup
-> smoothly enter Planning Mode
-> blueprint overlay active
-> formation adjusted
-> battlefield command issued
-> deploy
-> smoothly return to normal battle
```

Do not build two unrelated slow-motion systems.

Use one shared Planning Mode controller.

---

# 52. Smooth Visual / Time Transitions

Expose or centralize tunable values:

```text
planning_time_scale
planning_transition_in_duration
planning_transition_out_duration
planning_desaturation_amount
planning_brightness_adjustment
```

Exact values are provisional.

Avoid hard-coding scattered transition values.

---

# 53. Debug Visibility

For development builds, expose enough state to diagnose behavior.

Suggested squad debug data:

```text
squad_id
unit_type
current_intent
internal_state
selected
defense_center
defense_radius
selected_group_id / shared_order_id if applicable
current_target
living_member_count
```

Gesture debug data:

```text
gesture_length
start_to_end_distance
closure_distance
curvature metric / classification metric
recognized_command
classification confidence / score if used
failure_reason
```

Planning Mode:

```text
current_game_speed
target_game_speed
planning_active
desaturation_amount
```

---

# 54. Gesture Debug Visualization

For prototype tuning, optionally show:

- raw gesture path;
- simplified path;
- start/end markers;
- inferred center;
- inferred radius;
- detected type;
- classification values.

Keep this debug-only.

It will be important for tuning "forgiving" recognition.

---

# 55. Implementation Architecture — Suggested Responsibilities

Use existing project architecture where possible.

Do not force these names if the repository uses another structure.

## Squad / SquadController

Owns:

- member units;
- squad identity;
- persistent intent;
- defense order data;
- selection state;
- squad-level order application.

## SelectionManager

Owns:

- clicked-unit to squad resolution;
- single select;
- Shift multi-select;
- toggle deselection;
- clear selection;
- selection centroid.

## CommandPlanningController

Owns:

- enter/exit Planning Mode;
- timescale transition;
- desaturation transition;
- command interaction lifecycle;
- cancel/back behavior.

## GestureRecognizer

Owns:

- gesture sampling;
- line-like vs loop-like classification;
- center/radius extraction for Defend;
- failure result.

## SquadCommandController / OrderService

Owns:

- apply Advance;
- validate/apply Defend;
- No-Hold validation;
- success/failure events.

## BlueprintController

Owns:

- new squad formation setup;
- selected card package display;
- initial formation dimensions;
- transition to initial order command.

## CommandFeedbackController

Owns:

- success flash;
- failure icon event;
- temporary arrow/circle;
- future polish animations.

---

# 56. Events / Signals

Suggested events:

```text
squad_selected
squad_deselected
selection_changed

planning_mode_started
planning_mode_ended

gesture_started
gesture_updated
gesture_cancelled
gesture_recognized
gesture_failed

advance_order_issued
defend_order_issued
command_failed

squad_started_moving_to_defend
squad_reached_defense
squad_returning_to_defense
squad_intent_changed

defense_area_changed
defense_area_expanded

blueprint_opened
blueprint_closed
deployment_committed
deployment_cancelled
```

Use project conventions.

---

# 57. Command Result Contract

Every command attempt should resolve to a clear result.

Conceptual result:

```text
CommandResult
{
    success: bool
    command_type
    affected_squad_ids[]
    failure_reason
    defense_center
    defense_radius
}
```

This separates gameplay result from presentation.

The UI can react to the result without gameplay code directly creating animations.

---

# 58. Acceptance Tests — Selection

- [ ] Clicking one soldier selects the whole squad.
- [ ] Selected squad receives a visible white outline.
- [ ] Clicking an already-selected squad deselects it.
- [ ] Shift+click adds a new squad.
- [ ] Shift+click an already-selected squad removes it.
- [ ] Releasing Shift does not clear multi-selection.
- [ ] Selection persists while issuing a command unless cancelled/destroyed.
- [ ] Right-click with no active command clears selection.
- [ ] Selection centroid updates as squads/members are added, removed, or killed.

---

# 59. Acceptance Tests — Advance

- [ ] Line-like gesture can be recognized.
- [ ] Successful line gesture issues Advance to every selected surviving squad.
- [ ] Existing Defend intent is cleared.
- [ ] Shield/Arrow+Shield icon clears.
- [ ] Advance squads engage enemies when appropriate.
- [ ] Advance squads resume forward movement after combat.
- [ ] Advance squads do not auto-reform after casualties.
- [ ] Success flash/arrow feedback occurs.
- [ ] Planning Mode exits smoothly.

---

# 60. Acceptance Tests — Defend

- [ ] Loop-like gesture can be recognized.
- [ ] Loop produces center/radius.
- [ ] Defense area appears.
- [ ] Shield appears at center.
- [ ] Arrow is drawn from selection centroid to defense center.
- [ ] Circle flashes on success.
- [ ] Circle auto-expands when too small.
- [ ] Multiple selected squads receive the same defense area.
- [ ] Squads retain internal identity.
- [ ] Arrow+Shield displays while moving to defend.
- [ ] Shield displays after reaching defense.
- [ ] Units only pursue/engage within defense area.
- [ ] Units return to defend positions after threats disappear.
- [ ] Survivors re-form only during defend behavior.
- [ ] Planning Mode exits smoothly.

---

# 61. Acceptance Tests — No-Hold Zone

- [ ] No-Hold Zone is hidden during normal battle.
- [ ] It appears during relevant command planning.
- [ ] Zone uses non-color visual differentiation.
- [ ] Advance may pass through the zone.
- [ ] Defend circle overlapping the zone fails.
- [ ] Failed Defend order does not deselect squads.
- [ ] Existing squad intent remains unchanged on failure.
- [ ] Failure feedback appears.
- [ ] Zone fades away when Planning Mode ends.

---

# 62. Acceptance Tests — Gesture Failure

- [ ] Ambiguous gesture is not guessed.
- [ ] `UNRECOGNIZED_GESTURE` result is produced.
- [ ] Existing orders remain unchanged.
- [ ] Selection remains active.
- [ ] No resources/cards are spent.
- [ ] Failure icon originates near selected squads / command origin.
- [ ] Player can retry immediately.
- [ ] Planning Mode can remain active for retry if that feels best in implementation.

---

# 63. Acceptance Tests — Casualties During Command

- [ ] Partial soldier losses do not cancel command.
- [ ] Selection automatically reflects survivors.
- [ ] One selected squad destroyed does not cancel remaining multi-squad command.
- [ ] If all selected units die, command ends.
- [ ] `SQUAD_DESTROYED` feedback is shown.
- [ ] Selection clears.
- [ ] Planning Mode exits safely.

---

# 64. Acceptance Tests — Right-Click

- [ ] Right-click during gesture cancels only the gesture.
- [ ] Existing squad orders remain intact.
- [ ] Right-click during blueprint backs out of setup.
- [ ] Resources/cards are not spent when setup is cancelled before commit.
- [ ] Right-click with selection only clears selection.
- [ ] Clearing selection does not alter squad tactical intent.

---

# 65. Acceptance Tests — Planning Mode

- [ ] Planning Mode does not activate on simple selection.
- [ ] It activates when blueprint/command input begins.
- [ ] Timescale smoothly transitions toward configured slow speed.
- [ ] Battlefield visually desaturates.
- [ ] Command UI remains readable/prominent.
- [ ] Enemy/team readability remains sufficient.
- [ ] Planning Mode exits on success.
- [ ] Planning Mode exits on cancel.
- [ ] Planning Mode exits if all selected units are destroyed.
- [ ] Timescale returns smoothly to normal.
- [ ] Visual saturation returns smoothly.

---

# 66. Acceptance Tests — Blueprint

- [ ] New squad card package can open blueprint.
- [ ] Final unit count is visible.
- [ ] Final total Command cost is visible.
- [ ] Formation preview exists.
- [ ] Formation box can be resized.
- [ ] Blueprint can be cancelled.
- [ ] Blueprint transitions into battlefield command input.
- [ ] Successful command commits cards/resources.
- [ ] Cancel before final command does not commit resources.
- [ ] UI can remain prototype-quality.

---

# 67. Playtest Questions

After implementation, test these questions before polishing the UI.

## Selection

- Is selecting and multi-selecting squads predictable?
- Does the white outline clearly identify selected squads?
- Does persistent multi-selection feel better than holding Shift?

## Gesture language

- Can the player reliably draw Advance and Defend without thinking about recognition rules?
- How often are valid intentions rejected?
- Are ambiguous gestures rare enough?
- Does retrying feel painless?

## Planning Mode

- Does slow motion give enough time?
- Does it preserve battlefield pressure?
- Does desaturation improve command readability?
- Does entering/exiting Planning Mode feel smooth rather than interruptive?

## Defend

- Does the defense leash feel understandable?
- Do units behave like they are protecting an area?
- Do they return/re-form naturally?
- Does circle auto-expansion feel helpful rather than surprising?

## Advance

- Does Advance feel like the default, low-friction order?
- Does lack of reformation make advancing units feel naturally battle-worn rather than broken?

## Multi-squad Defend

- Do separate squads sharing one defense circle behave coherently?
- Does it feel like one coordinated force or several squads fighting each other for space?
- If awkward, test temporary backend super-squad grouping next.

## Failure feedback

- Does the player immediately understand that an order failed?
- Can they tell roughly why without text?
- Does the feedback feel playful rather than punitive?

---

# 68. Primary Prototype Risks

## Gesture fatigue

A fun gesture once may become repetitive after many commands.

Do not solve this before testing.

Future expert shortcuts may be added later if needed.

---

## Gesture misclassification

If recognition rejects reasonable inputs, the whole system will feel unreliable.

Prefer permissive thresholds and immediate retry.

---

## Planning Mode overuse

If the game slows too often, combat may lose momentum.

Selection alone must not trigger slow motion.

---

## Defend dominance

If Defend provides too much control/safety, Advance may become irrelevant.

Watch actual battlefield use before adding penalties.

---

## Multi-squad packing

Several squads sharing one defense area may create collision/pathing problems.

Try separate squads first.

Only introduce hidden temporary super-squad behavior if needed.

---

## Visual clutter

Selection outlines, circles, arrows, icons, No-Hold hatching, cards, and health bars can become noisy.

Functional implementation comes first.

UI/UX cleanup is explicitly deferred until after mechanics testing.

---

# 69. Deferred UI/UX Polish

Do **not** block this implementation on final:

- blueprint layout;
- typography;
- final icon artwork;
- final command animations;
- paper/pencil failure animation;
- final desaturation shader/look;
- selection outline art;
- No-Hold pattern style;
- easing polish;
- audio cues;
- haptics;
- final information hierarchy.

The UI/UX specialist will refine these after the command system is tested.

For now use functional placeholders that clearly expose state.

---

# 70. Recommended Implementation Order

Implement in this order:

```text
1. Persistent Squad Intent data: ADVANCE / DEFEND
2. Squad selection by clicking any member
3. Shift multi-selection + toggle deselection
4. Selection centroid
5. Right-click contextual cancel/clear selection
6. Command Planning Mode controller
7. Smooth timescale transition
8. Battlefield desaturation transition
9. Basic gesture capture
10. Line/loop classification
11. Advance order
12. Defend center/radius extraction
13. Defense movement + leash targeting
14. Return/re-form behavior for defenders
15. Defense circle auto-expansion
16. Multi-squad shared defense area
17. No-Hold Zone validation
18. Success feedback events
19. Failure result/events
20. Prototype failure icons
21. Blueprint functional overlay
22. New squad initial-order flow
23. Automated acceptance checks
24. Playtest
25. UI/UX polish after mechanics are validated
```

---

# 71. Definition of Done

This iteration is complete when:

> The player can select one or multiple squads, issue a forgiving line gesture to make them Advance, issue a forgiving loop gesture to make them move to and defend a shared area, see clear success/failure feedback, cancel safely with right-click, and perform commands inside a smooth slow-motion/desaturated Command Planning Mode. New squads can be configured in a functional blueprint overlay and receive an initial Advance or Defend order before deployment. The enemy No-Hold Zone prevents defensive spawn camping without preventing ordinary advance/combat.

The system should then be playtested before substantial UI/UX polish or additional tactical commands are added.
