# Trencho — Drag-to-Deploy Formation System Specification
**Version:** 0.1  
**Purpose:** Developer handoff for a prototype deployment system  
**Status:** Prototype specification — behavior and tuning values remain subject to playtesting

---

# 1. Goal

Replace the current rigid deployment-zone restriction with a more flexible system where the player:

1. Selects a deployment package.
2. Clicks and drags within a large friendly deployment area.
3. Draws a rectangular **deployment footprint**.
4. Uses that footprint to define where and how the selected units should enter the battlefield.
5. Receives immediate visual feedback about whether the requested formation is legal.
6. Confirms the deployment.
7. Units enter from off-screen and move into the requested formation.

The goal is to make congestion and battlefield pressure create **spatial consequences** rather than simply disabling the player's ability to deploy.

---

# 2. Core Design Principle

The player should not directly place individual soldiers.

Instead:

> The player defines the intended deployment area and formation shape.  
> The system determines legal unit positions within that footprint.

This keeps the player focused on command-level decisions rather than individual-unit micromanagement.

---

# 3. Deployment Area

## REQUIRED

Each team has a large deployment region near its side of the battlefield.

For the player:

```text
PLAYER DEPLOYMENT REGION
```

The player may only draw deployment footprints inside this region.

The deployment region should be significantly larger than the exact space needed to spawn one squad.

This gives the player meaningful spatial choice.

Possible choices include:

- Left side of the battlefield.
- Center.
- Right side.
- Wide formation.
- Narrow formation.
- Deep formation.
- Shallow formation.

---

# 4. Deployment Footprint

## REQUIRED

After selecting a valid deployment package, the player clicks and drags inside the deployment region.

The drag creates a rectangle.

This rectangle represents:

```text
desired deployment footprint
```

It determines:

- approximate entry position,
- formation width,
- formation depth,
- available formation capacity.

The rectangle does **not** directly mean:

```text
spawn units randomly anywhere in this box
```

Instead, the system generates valid formation slots inside it.

---

# 5. Rectangle Preview States

## REQUIRED

The deployment rectangle must provide clear real-time visual feedback.

### Valid

If the selected rectangle can support the deployment:

```text
rectangle = valid state
```

Recommended visual:

```text
green / normal deployment color
```

### Invalid

If the selected rectangle cannot support the deployment:

```text
rectangle = invalid state
```

Recommended visual:

```text
red
```

The player cannot confirm deployment while the rectangle is invalid.

---

# 6. Important UX Rule — Do Not Auto-Expand the Rectangle

## REQUIRED

If the player draws a rectangle that is too small:

> Do **not** automatically resize or expand it.

The rectangle should remain exactly where and how the player drew it.

It should instead turn red and communicate why the deployment is invalid.

Reason:

Automatic expansion could cause the deployment footprint to move into areas the player did not intentionally choose, making the system feel unpredictable or buggy.

The player should remain in control of the requested formation.

Example:

```text
Selected units:
12 Infantry

Required capacity:
12

Available capacity in selected rectangle:
8

Result:
INVALID
Rectangle turns RED
```

Possible UI message:

```text
Not enough room for this deployment.
```

Optional more detailed debug message:

```text
Required Slots: 12
Valid Slots: 8
```

---

# 7. Formation Slot Generation

## REQUIRED

The system should generate candidate unit positions inside the dragged rectangle.

Each unit requires minimum deployment spacing.

Example concept:

```text
unit_spacing_radius
```

or:

```text
unit_footprint_width
unit_footprint_depth
```

The exact implementation is up to the developer.

The important rule is:

> Every deployed unit must be assigned a legal formation slot.

---

# 8. Example Formation Shapes

A wide / shallow deployment:

```text
X X X X X X
X X X X X X
```

A narrow / deep deployment:

```text
X X X
X X X
X X X
X X X
```

Both contain 12 units.

The rectangle shape determines which arrangement is possible.

---

# 9. Minimum Formation Space

## REQUIRED

A deployment must require enough physical area for all units.

Conceptually:

```text
required_space =
unit_count
×
space_required_per_unit
```

Actual implementation may use slot generation instead of direct area arithmetic.

The player cannot compress units indefinitely by drawing smaller rectangles.

---

# 10. Friendly Unit Occupancy

## REQUIRED

Existing friendly units should **not automatically invalidate the entire deployment area**.

Instead, friendly units occupy physical space.

Their occupied space removes potential formation slots.

Example:

```text
Requested deployment:
12 units

Generated candidate slots:
15

Slots blocked by friendly units:
4

Remaining valid slots:
11

Result:
INVALID
```

Because only 11 valid slots remain for 12 units.

The deployment rectangle turns red.

---

# 11. Friendly Congestion

The system should treat friendly congestion as a spatial problem rather than a binary deployment restriction.

Desired behavior:

```text
friendly units nearby
-> fewer available deployment slots
-> player may need to:

   draw a larger rectangle
   move the rectangle
   deploy elsewhere
   wait for units to move forward
```

This keeps congestion meaningful without completely removing player agency.

---

# 12. Reinforcement Queue

## RECOMMENDED

If a deployment has enough valid formation slots at confirmation time, units do not need to appear instantly.

Instead:

1. Deployment is accepted.
2. Formation slots are reserved.
3. Units spawn off-screen.
4. Units enter the battlefield.
5. Each unit moves toward its assigned formation slot.
6. Once sufficiently integrated, normal unit behavior resumes.

This provides a natural reinforcement flow.

---

# 13. Off-Screen Spawn

## REQUIRED

Units should originate from behind / off-screen rather than appearing directly inside the selected rectangle.

Conceptually:

```text
OFF-SCREEN SPAWN
      |
      v
==================== battlefield edge

       [ selected formation footprint ]
```

The footprint defines the requested battlefield formation.

It does not need to be the literal spawn location.

---

# 14. Formation Reservation

## REQUIRED OR STRONGLY RECOMMENDED

When a deployment is confirmed, its formation slots should be temporarily reserved.

Purpose:

Prevent another deployment from claiming the same physical positions before the first reinforcement enters.

Suggested reservation state:

```text
FREE
RESERVED
OCCUPIED
BLOCKED
```

A slot becomes:

```text
RESERVED
```

when a deployment is confirmed.

It becomes:

```text
OCCUPIED
```

when the assigned unit reaches it.

It becomes:

```text
FREE
```

when reservation is cancelled, unit leaves, or unit dies depending on implementation.

---

# 15. Enemy Proximity

## REQUIRED FOR LATER TEST

Enemy units should reduce usable deployment space.

Do not use:

```text
one enemy enters deployment region
-> entire deployment system disabled
```

Instead, each enemy creates an exclusion area.

Conceptually:

```text
enemy_exclusion_radius
```

Formation slots inside that radius are invalid.

---

# 16. Enemy Exclusion Behavior

Example:

```text
Enemy unit is near the right side of the deployment area.

Left:
many valid slots

Center:
some valid slots

Right:
few or no valid slots
```

The player can still deploy where sufficient safe space remains.

This creates a gradual loss of deployment freedom rather than a binary lock.

---

# 17. Why Enemy Exclusion Matters

This allows enemy breakthrough to create a spatial consequence:

```text
enemy pushes toward player
-> available reinforcement space shrinks
-> deployment becomes harder
-> player must adapt
```

This is preferable to:

```text
enemy touches zone
-> player cannot deploy at all
```

because the severity scales with battlefield state.

---

# 18. Validity Calculation

## REQUIRED

The system should evaluate the deployment footprint before confirmation.

Conceptual flow:

```text
Player draws rectangle
        |
        v
Generate candidate formation slots
        |
        v
Remove invalid slots
        |
        +--> outside deployment region
        |
        +--> blocked by terrain
        |
        +--> blocked by friendly occupancy
        |
        +--> inside enemy exclusion area
        |
        +--> otherwise invalid
        |
        v
Count remaining valid slots
        |
        v
valid_slots >= required_units ?
        |
     YES / NO
```

If yes:

```text
rectangle = valid
```

If no:

```text
rectangle = red
deployment cannot be confirmed
```

---

# 19. Preview Information

## RECOMMENDED

While dragging, show enough information for the player to understand the result.

Example:

```text
Rifle Squad + Commander Mojo

Units:
9

Formation Capacity:
12

Status:
VALID
```

Invalid:

```text
Units:
9

Formation Capacity:
7

Status:
NOT ENOUGH SPACE
```

Do not expose excessive debug information in final UI unless useful.

---

# 20. Deployment Confirmation

## REQUIRED

A deployment may only confirm if:

```text
valid_slots >= required_unit_count
```

and all other deployment rules pass.

Possible additional checks:

```text
enough Command
valid card package
valid deployment region
valid modifier combination
```

Only after successful validation:

```text
spend resource
discard / consume cards
reserve slots
spawn reinforcements
```

---

# 21. Failed Deployment

## REQUIRED

If deployment is invalid:

```text
no Command spent
no cards discarded
no units spawned
```

The player remains free to:

```text
resize rectangle
move rectangle
cancel deployment
change selected cards
```

---

# 22. Formation Entry

## REQUIRED

Each spawned unit gets:

```text
assigned_formation_slot
```

Unit behavior:

```text
spawn off-screen
        |
        v
move toward assigned slot
        |
        v
reach deployment formation
        |
        v
transition into normal battlefield AI
```

---

# 23. Temporary Reinforcement State

## RECOMMENDED

Add a unit state such as:

```text
ENTERING_BATTLEFIELD
```

Example state flow:

```text
ENTERING_BATTLEFIELD
        |
        v
ADVANCING
        |
        v
ENGAGING
        |
        v
ADVANCING
```

This prevents standard combat movement logic from interfering with initial formation entry.

---

# 24. What Happens if the Assigned Slot Becomes Blocked?

## OPEN / PROTOTYPE RULE

A reserved slot may become obstructed before the unit arrives.

For the first prototype:

```text
find nearest valid unoccupied slot
```

within a small search radius.

If no replacement exists:

```text
unit waits / queues briefly
```

Avoid teleporting units.

Avoid forcing units to overlap.

---

# 25. Queue Behavior

## RECOMMENDED

If units cannot enter safely:

```text
remain off-screen
or
wait at the reinforcement edge
```

Then enter as space becomes available.

This turns crowding into:

```text
slower reinforcement flow
```

rather than:

```text
deployment impossible
```

provided the original deployment was valid when confirmed.

---

# 26. Important Distinction

There are two different concepts:

## Deployment Validity

Can this formation legally be ordered?

## Reinforcement Throughput

How quickly can those units physically enter?

These should not necessarily be the same thing.

A valid deployment may still take time to fully enter the battlefield.

---

# 27. Large Deployments

A large deployment naturally creates costs without requiring an artificial cooldown.

Example:

```text
4-unit squad
-> enters quickly

20-unit formation
-> takes longer to move onto the battlefield
```

This creates a possible soft balancing mechanism.

Large deployments:

```text
more immediate total power
but
greater spatial requirement
and
slower reinforcement throughput
```

Exact timing should remain tunable.

---

# 28. No Formation Stat Bonuses Yet

## OUT OF SCOPE FOR FIRST TEST

Do not yet add:

```text
wide formation = accuracy bonus
deep formation = defense bonus
dense formation = damage bonus
loose formation = explosion resistance
```

The first test should determine whether drawing formations is useful and understandable on its own.

Formation-based statistical mechanics can be considered later.

---

# 29. No Friendly Congestion Command Tax Yet

## OUT OF SCOPE FOR FIRST TEST

Do not combine this prototype with:

```text
friendly congestion -> additional Command cost
```

yet.

The spatial capacity / reinforcement-throughput system should be tested first.

Reason:

If several solutions are added simultaneously, it becomes difficult to know which rule improved the system.

---

# 30. Bombing Run Interaction

## FUTURE

A Bombing Run or similar Special card could later interact naturally with this system.

Example use:

```text
enemy units reduce available deployment space
        |
        v
player uses bombing run
        |
        v
enemy presence reduced
        |
        v
more formation slots become legal
```

This makes Bombing Run a tactical recovery tool rather than a mandatory workaround for a broken spawn system.

---

# 31. Suggested Data Structures

## DeploymentRegion

```text
team_id
bounds
formation_spacing
offscreen_spawn_area
```

## DeploymentFootprint

```text
rectangle
team_id
requested_unit_count
candidate_slots[]
valid_slots[]
invalid_slots[]
status
```

## FormationSlot

```text
position
state
reserved_by_deployment_id
blocking_unit
```

Possible state:

```text
FREE
RESERVED
OCCUPIED
BLOCKED
```

## DeploymentRequest

```text
team
source_cards
unit_type
unit_count
modifiers
requested_rectangle
resolved_slots[]
total_command_cost
```

---

# 32. Suggested Deployment Validation

Pseudo-code:

```text
function evaluate_deployment(rectangle, deployment):

    slots = generate_slots(rectangle)

    valid_slots = []

    for slot in slots:

        if not deployment_region.contains(slot):
            continue

        if terrain_blocks(slot):
            continue

        if friendly_unit_blocks(slot):
            continue

        if enemy_exclusion_blocks(slot):
            continue

        if slot_is_reserved(slot):
            continue

        valid_slots.append(slot)

    if valid_slots.size < deployment.unit_count:
        return INVALID

    return VALID
```

---

# 33. Confirmation Flow

Pseudo-code:

```text
function confirm_deployment():

    result = evaluate_deployment(
        current_rectangle,
        selected_deployment
    )

    if result == INVALID:
        reject
        keep rectangle red
        return

    if command < selected_deployment.total_cost:
        reject
        return

    spend_command()

    consume_cards()

    slots = choose_slots_for_units()

    reserve(slots)

    enqueue_reinforcements(slots)
```

---

# 34. Visual Feedback

## REQUIRED

The player should understand why a footprint is invalid.

At minimum:

```text
VALID
-> normal / green footprint

INVALID
-> red footprint
```

Possible invalid reasons:

```text
NOT_ENOUGH_SPACE
OUTSIDE_DEPLOYMENT_AREA
ENEMY_TOO_CLOSE
BLOCKED_BY_TERRAIN
INSUFFICIENT_COMMAND
```

The red rectangle must remain under the player's cursor and must not automatically move, resize, or expand.

---

# 35. Debug Visualization

## REQUIRED FOR DEVELOPMENT

Provide a debug mode capable of showing:

```text
deployment region bounds
candidate formation slots
valid slots
invalid slots
friendly occupancy
enemy exclusion radii
reserved slots
off-screen spawn points
assigned destination slot per unit
```

This system will be difficult to tune if the developer cannot see why a slot was rejected.

---

# 36. Edge Cases

The prototype should explicitly handle:

### Rectangle partly outside deployment region

```text
INVALID
```

Recommended:
entire requested footprint must remain inside the legal deployment region.

---

### Too-small rectangle

```text
INVALID
turn red
do not auto-expand
```

---

### Friendly units occupy some slots

Use remaining legal slots.

If insufficient:

```text
INVALID
```

---

### Enemy excludes some slots

Use remaining legal slots.

If insufficient:

```text
INVALID
```

---

### Another deployment reserved the area

Reserved slots are unavailable.

---

### Unit dies before reaching assigned formation slot

Release its slot reservation if appropriate.

---

### Unit cannot reach assigned formation slot

Attempt a nearby legal slot.

If none:

```text
wait / queue
```

Do not teleport.

---

### Player cancels before confirmation

Clear all preview state.

No cost.

---

# 37. Recommended Prototype Sequence

Implement in this order:

```text
1. Large player deployment region.
2. Click-and-drag rectangle.
3. Rectangle clamped / validated against region.
4. Formation slot generation.
5. Minimum unit spacing.
6. Valid / red invalid preview.
7. Friendly occupancy blocking individual slots.
8. Deployment confirmation.
9. Slot reservation.
10. Off-screen spawn.
11. Units move into assigned formation.
12. Reinforcement queue / congestion handling.
13. Enemy exclusion radius.
14. Debug visualization.
15. Playtest.
```

Do not add formation buffs, congestion resource penalties, or sophisticated Special-card interactions before testing this version.

---

# 38. First Acceptance Test

The system is ready for its first design test when:

- [ ] Player can select a squad.
- [ ] Player can click and drag a rectangle inside the deployment region.
- [ ] System generates formation slots.
- [ ] Rectangle turns red when the requested squad cannot fit.
- [ ] System does not resize the rectangle automatically.
- [ ] Existing friendly units remove available slots.
- [ ] Valid deployment can be confirmed.
- [ ] Invalid deployment cannot be confirmed.
- [ ] Units originate from off-screen.
- [ ] Units move toward reserved formation positions.
- [ ] Units do not initially overlap each other.
- [ ] Multiple deployments can create understandable congestion.
- [ ] Congestion delays / redirects reinforcement rather than producing arbitrary total lockout.
- [ ] Debug mode shows why deployments are valid or invalid.

---

# 39. First Playtest Questions

Do not initially judge the mechanic by asking only:

```text
"Is this fun?"
```

Observe:

### 1. Does the player understand why the rectangle turns red?

If not, improve visual feedback before changing the rule.

### 2. Does the player intentionally change formation width or depth?

If not, the rectangle may be adding interaction without meaningful choice.

### 3. Does friendly congestion create interesting spatial decisions?

Desired examples:

```text
"I can't fit this squad here, so I'll deploy wider."

"I've packed the center too tightly, so I'll reinforce the left."

"I need to wait for these troops to move forward before bringing in another large formation."
```

### 4. Does congestion feel like battlefield pressure or UI obstruction?

If it feels like the interface is fighting the player, revise the slot rules.

### 5. Do players repeatedly choose the smallest legal rectangle?

If yes, formation shape may not yet have meaningful consequences.

### 6. Does off-screen reinforcement entry make large deployments feel different from small ones?

If yes, reinforcement throughput may be a useful balancing dimension.

---

# 40. Primary Risk

The biggest risk is replacing:

```text
hard zone restriction
```

with:

```text
fiddly placement restriction
```

The deployment system should create strategic positioning choices without requiring pixel-perfect rectangle drawing.

The slot system should therefore tolerate reasonable player input while still preventing impossible overlap.

---

# 41. Design Intent Summary

The intended transformation is:

### Previous behavior

```text
Friendly or enemy unit occupies deployment zone
-> deployment prohibited
```

### Proposed behavior

```text
Player chooses deployment footprint
        |
        v
Existing battlefield occupancy removes available space
        |
        v
Player adapts formation position / shape
        |
        v
Valid reinforcements arrive physically from off-screen
```

The goal is for battlefield congestion to create:

> **spatial pressure and reinforcement delay**

rather than:

> **binary loss of player agency**

---

# 42. Definition of Done for This Iteration

This iteration is complete when:

> The player can draw a deployment footprint inside a large rear deployment region, receive immediate red feedback when the requested formation cannot legally fit, confirm valid formations, and watch those units enter from off-screen into reserved positions without initial overlap.

The next decision should be made only after testing whether that interaction is understandable and tactically useful.
