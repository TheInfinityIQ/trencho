# Trencho — Deployment Flow & Reinforcement Pressure Update
**Version:** 0.1  
**Purpose:** Developer handoff for the next prototype iteration  
**Status:** Test-focused implementation spec

---

# 1. Goal of This Update

The latest playtest suggests the player is being overwhelmed primarily because **combat power takes too long to become active** and because **losing territory reduces the player's ability to reinforce effectively**.

This update should test that hypothesis without simultaneously rebalance-tuning the whole game.

The next build should therefore focus on:

1. Changing deployment rectangles from **destination formations** to **entry formations**.
2. Allowing player reinforcements to become useful immediately after entering the field.
3. Reducing the enemy's early execution advantage.
4. Making enemy proximity restrict deployment locally instead of effectively shutting down large areas.
5. Improving debug readability around `Incoming` units.

Do **not** significantly retune combat stats in the same iteration.

---

# 2. Current Combat Baseline to Preserve

Use the current prototype values for this test.

## Conscript Wave

```text
HP per Unit: 75
Range: 585
Ranged DPS per Soldier: 25
Quantity: 12
```

With Commander Mojo:

```text
12 -> 24 units
```

---

## Rifle Squad

```text
HP per Unit: 100
Range: 650
Ranged DPS per Soldier: 60
Quantity: 6
```

Enemy Rifle squads currently use the same Rifle combat profile.

With Commander Mojo:

```text
6 -> 12 units
```

---

## Assault Squad

```text
HP per Unit: 225
Ranged DPS per Soldier: 80
Quantity: 4
```

With Commander Mojo:

```text
4 -> 8 units
```

The Assault squad remains the short-range / fast / close-combat specialist.

---

## Commander Mojo

Current behavior:

```text
+100% units
Cost: 3 Command
```

Keep this unchanged for the next test.

---

# 3. Current Problem Being Tested

The current deployment system treats the rectangle as a **destination**.

The flow is effectively:

```text
player selects cards
-> draws deployment rectangle
-> confirms deployment
-> units spawn off-screen
-> units travel toward assigned positions
-> units only become fully useful after reaching those positions
```

This creates several problems.

---

# 4. Problem A — Destination March Creates a Bad Incentive

If units must travel to the requested rectangle before behaving normally, the player is strongly incentivized to place deployment rectangles as close to the bottom edge as possible.

This undermines the purpose of allowing the player to choose formation position.

The intended decision is:

> How should this group enter the battlefield?

The current behavior instead creates:

> How far am I willing to force this group to travel before it becomes useful?

This is especially punishing for short-range units such as Assault squads.

---

# 5. Problem B — Reinforcements Are Paid For but Not Yet Active

The player can have a large number of units in the `Incoming` state while still losing the battlefield.

This means Command and cards have already been spent, but much of that purchased combat power is not yet contributing.

This produces a logistics delay:

```text
Command spent
-> card committed
-> units ordered
-> long travel / formation process
-> eventual combat contribution
```

The enemy bot converts resources into battlefield pressure more directly.

---

# 6. Problem C — Losing Territory Reduces Reinforcement Capacity

Enemy pressure near the player's deployment area invalidates formation space.

This creates a positive feedback loop:

```text
lose battlefield position
-> lose legal reinforcement space
-> reinforcements become harder to place
-> less combat power reaches the field
-> lose more battlefield position
```

The goal is not to remove the spatial consequence.

The goal is to prevent it from becoming a near-binary lockout too early.

---

# 7. Core Change — Deployment Rectangle Becomes an Entry Formation

## REQUIRED

The deployment rectangle should no longer represent a destination that every soldier must physically reach before beginning normal advancement.

Instead:

> The rectangle defines the geometry of how the unit group enters the battlefield.

The rectangle controls:

- horizontal frontage,
- formation width,
- number of ranks,
- spacing,
- relative position between soldiers.

It should **not** create a distant movement objective that all units must reach first.

---

# 8. New Deployment Interpretation

## Old Meaning

```text
"Move these soldiers to this rectangle."
```

## New Meaning

```text
"Bring these soldiers onto the battlefield in this formation."
```

This keeps the player-facing formation mechanic while removing unnecessary movement latency.

---

# 9. Example Entry Formations

## Wide / Shallow

```text
X X X X X X X X
X X X X X X X X
```

Interpretation:

- broad frontage,
- fewer ranks,
- many units enter close together in time,
- good for covering width.

---

## Narrow / Deep

```text
X X X
X X X
X X X
X X X
```

Interpretation:

- narrow frontage,
- more ranks,
- units enter in greater depth,
- easier to fit through congested space,
- naturally creates a staggered reinforcement flow.

---

# 10. Vertical Rectangle Meaning

## RECOMMENDED

The vertical dimension of the drag rectangle should affect:

```text
rank count
or
reinforcement depth
```

rather than defining a target Y-position.

This means:

```text
shallow rectangle
-> fewer ranks
-> wider / more simultaneous entry

deep rectangle
-> more ranks
-> staggered / column-like entry
```

This preserves meaningful use of both rectangle dimensions.

---

# 11. Reinforcement Entry Behavior

## REQUIRED

After confirmation:

```text
1. Formation slots are calculated.
2. Units spawn off-screen / behind the battlefield edge.
3. Units enter while preserving the requested relative formation.
4. Units immediately begin advancing.
5. Units may engage enemies as soon as enemies enter valid weapon range.
```

There should be no required:

```text
travel to rectangle
-> arrive
-> then advance
```

stage.

---

# 12. Assault Squad Implication

This change is particularly important for Assault squads.

The Assault role is:

```text
high HP
high close-range DPS
short range
fast movement
small squad size
```

An Assault squad should be useful when enemies have penetrated into the player's command area.

The intended behavior is:

```text
deploy compact Assault formation
-> units enter
-> begin advancing immediately
-> enemy already close
-> Assault reaches firing range quickly
-> attempt to clear the breakthrough
```

Do not compensate for the current deployment delay by buffing Assault HP or DPS again before this movement change is tested.

---

# 13. Enemy First-Deployment Gate

## REQUIRED FOR THIS TEST

The enemy should not make its first deployment until the player has confirmed their first deployment.

Reason:

The enemy currently has almost no human decision latency.

The player must:

```text
inspect hand
choose cards
consider modifiers
draw formation
validate placement
confirm
```

The enemy currently:

```text
can afford action
-> deploy
```

This gives the enemy an early tempo advantage even if both sides have identical resource regeneration.

---

# 14. First-Deployment Rule

Recommended:

```text
battle starts
enemy economy may initialize normally
enemy deployment logic waits

player confirms first deployment

enemy AI deployment logic activates
```

After this point:

```text
enemy behaves normally
```

Do not continue handicapping the enemy later in the battle.

This is specifically intended to remove the player's startup UI/planning tax.

---

# 15. Enemy Exclusion — Change From Broad Denial to Local Slot Denial

## REQUIRED

Enemy presence should continue to reduce the player's usable deployment space.

However:

> Enemy proximity should invalidate **individual nearby formation slots**, not effectively deny large deployment areas unless enough enemies physically occupy them.

---

# 16. Desired Enemy Exclusion Behavior

Example:

```text
Enemy soldier near right side of deployment region

Nearby slots:
INVALID

Farther slots:
VALID
```

One enemy should not make an entire large rectangle unusable unless its exclusion area actually overlaps most or all required slots.

---

# 17. Enemy Exclusion Radius

## PROVISIONAL

Use the smallest exclusion radius that prevents obvious overlap / spawning directly on top of an enemy.

Do not use the radius as a major tactical suppression field yet.

The initial purpose is:

```text
no reinforcement appears physically inside an enemy unit
```

not:

```text
one enemy denies a huge section of the player's reinforcement zone
```

Expose this value for tuning.

Example:

```text
enemy_deployment_exclusion_radius
```

---

# 18. Local Slot Validation

When evaluating a deployment formation:

```text
for each formation slot:

    if slot is within enemy exclusion radius:
        invalid

    else if blocked by terrain:
        invalid

    else if reserved:
        invalid

    else:
        valid
```

The overall deployment is legal if enough valid slots exist for the unit count.

---

# 19. Preserve the Red Invalid Rectangle

## REQUIRED

If there are not enough legal positions:

```text
rectangle remains red
deployment cannot confirm
```

Do not automatically resize or move the rectangle.

The player must remain in control of formation placement.

---

# 20. Incoming-State Debug Readability

## REQUIRED

Improve the visibility of the `Incoming` state.

The developer and player should be able to distinguish:

```text
units purchased but not yet entered
units currently entering
units actively advancing
units currently fighting
```

---

# 21. Suggested Debug States

At minimum:

```text
QUEUED
ENTERING
ADVANCING
ENGAGING
CAPTURING
EXITING
DEAD
```

If `QUEUED` and `ENTERING` are internally different, expose them separately in debug mode.

---

# 22. Unit State Icon

For prototype/debug UI:

```text
QUEUED:
clock / queue icon

ENTERING:
down/up arrow or doorway icon

ADVANCING:
movement arrow

ENGAGING:
crosshair

CAPTURING:
flag
```

The exact icon artwork is flexible.

The important thing is being able to inspect the flow at a glance.

---

# 23. Incoming Counter

Keep the existing:

```text
Incoming: X
```

but consider adding debug detail such as:

```text
Queued: 8
Entering: 6
Active: 24
```

This can be debug-only.

It is useful for diagnosing whether battlefield weakness is caused by:

```text
bad stats
or
combat power waiting in logistics
```

---

# 24. Do Not Rebalance the Main Combat Values Yet

## REQUIRED TEST CONTROL

Keep the current combat numbers unchanged for this iteration.

Do not change:

```text
Conscript ranged DPS: 25
Rifle ranged DPS: 60
Assault ranged DPS: 80

Conscript HP: 75
Rifle HP: 100
Assault HP: 225

Conscript range: 585
Rifle range: 650
current Assault range

current squad quantities
current Command costs
```

The purpose is to isolate the deployment-flow change.

---

# 25. Do Not Change Commander Mojo Yet

Keep:

```text
+100% units
3 Command
```

Mojo currently produces:

```text
Assault:
4 -> 8

Rifle:
6 -> 12

Conscript:
12 -> 24
```

The logistics changes may substantially alter how powerful large Mojo deployments feel.

Do not balance Mojo before seeing the result.

---

# 26. Why Mojo Should Stay Fixed for This Test

Large Conscript + Mojo deployments currently amplify the reinforcement bottleneck.

A 24-unit wave is especially affected by:

```text
formation travel
entry delay
congestion
enemy exclusion
```

Changing deployment flow may make Mojo much stronger or simply make it function as intended.

Testing both changes together would make it difficult to know which caused the result.

---

# 27. Capture System

## NO CHANGE THIS ITERATION

Keep the current capture implementation.

The current overwhelming score differential appears to be downstream of battlefield control rather than primarily caused by capture timing.

Do not alter:

```text
capture threshold
capture speed
capture scoring
capture fade
```

until the reinforcement-pressure problem has been retested.

---

# 28. Player Unit Stat Efficiency — Diagnostic Note

Current theoretical squad values suggest the player is not obviously losing because their units have no combat power.

Approximate current values:

| Unit | Total HP | Total Ranged DPS | Command | DPS / Command |
|---|---:|---:|---:|---:|
| Conscript | 900 | 300 | 2 | 150 |
| Rifle | 600 | 360 | 3 | 120 |
| Assault | 900 | 320 | 4 | 80 |

These are simple model values.

They do not include:

- range,
- movement,
- overkill,
- target switching,
- formation delays,
- travel time,
- congestion,
- real combat uptime.

The fact that the player can still be overwhelmed despite these theoretical values is one reason to test logistics before further buffs.

---

# 29. Enemy AI — Do Not Make It Smarter Yet

Do not add:

```text
enemy Assault usage
enemy Conscript usage
enemy modifiers
enemy advanced counter-picking
enemy tactical formation logic
```

yet.

The current Rifle-only enemy is useful as a stable test pressure source.

First solve whether player combat power can enter the field effectively.

---

# 30. Expected Effects of This Update

If the hypothesis is correct:

### Player Reinforcements

Should become useful sooner.

### Assault Squad

Should become substantially better at clearing nearby breakthroughs without needing more raw stats.

### Formation Drawing

Should retain value because it controls frontage / ranks rather than creating travel distance.

### Enemy Breakthrough

Should still reduce available reinforcement space, but not instantly create a huge deployment lock.

### Incoming Count

Should decrease more quickly because units transition into active play earlier.

---

# 31. Acceptance Test — Entry Formation

A deployment succeeds when:

- [ ] Player can select cards.
- [ ] Player can draw a valid formation rectangle.
- [ ] Rectangle still controls formation shape.
- [ ] Units spawn from behind/off-screen.
- [ ] Units preserve the intended horizontal / rank arrangement during entry.
- [ ] Units do not travel toward a distant destination rectangle.
- [ ] Units begin advancing immediately after entry.
- [ ] Units can engage enemies encountered during entry / advance.
- [ ] Wide and narrow formations visibly produce different entry geometry.

---

# 32. Acceptance Test — Enemy Startup

- [ ] Enemy does not deploy before player's first confirmed deployment.
- [ ] Enemy may initialize resources normally.
- [ ] Player confirms first deployment.
- [ ] Enemy deployment logic activates.
- [ ] Enemy operates normally from that point onward.

---

# 33. Acceptance Test — Enemy Exclusion

- [ ] Enemies prevent spawning directly on top of themselves.
- [ ] Enemy exclusion applies to individual nearby slots.
- [ ] Distant slots inside the same formation may remain valid.
- [ ] One enemy does not deny a large region unless its actual exclusion radius covers it.
- [ ] Multiple enemies can genuinely consume most deployment space if physically present.
- [ ] Invalid deployment still turns red.
- [ ] Debug view makes excluded slots visible.

---

# 34. Acceptance Test — Incoming Debugging

- [ ] `Incoming` count remains visible.
- [ ] Developer can distinguish queued versus entering units.
- [ ] Developer can distinguish entering versus active units.
- [ ] Unit state icon updates correctly.
- [ ] It is easy to inspect how long purchased units remain outside active combat.

---

# 35. Primary Playtest Scenarios

## Scenario A — Large Mojo Conscript Wave

Deploy:

```text
Conscript Wave + Commander Mojo
24 units
```

Observe:

- how quickly combat power enters,
- whether formation shape remains understandable,
- whether large deployments still create meaningful congestion,
- whether the wave becomes too strong once travel-to-destination is removed.

---

## Scenario B — Assault Emergency Defense

Allow enemy Rifles to penetrate deeply.

Then deploy:

```text
Assault Squad
```

near the threatened area.

Expected:

- Assault enters quickly;
- Assault begins advancing/fighting immediately;
- short range is less punishing because the enemy is already nearby;
- Assault has a clear role as a local congestion breaker.

---

## Scenario C — Enemy Near Deployment Region

Allow one or two enemies near the command area.

Attempt several formation placements.

Expected:

- some slots become unavailable;
- nearby safe space remains usable;
- player can adapt rectangle shape / location;
- one enemy does not create an arbitrary full lock.

---

## Scenario D — Wide vs Narrow Entry

Deploy the same Unit card twice.

Test:

```text
very wide / shallow formation
```

and:

```text
narrow / deep formation
```

Observe whether these entry patterns create different tactical results.

---

# 36. Main Validation Question

The next build should primarily answer:

> **Was the player being overwhelmed because combat power was delayed by deployment logistics and shrinking reinforcement space rather than because player unit stats were too weak?**

---

# 37. Success Indicators

Evidence supporting the change would include:

- fewer large `Incoming` backlogs;
- Assault squads successfully reacting to nearby breakthroughs;
- player no longer feeling forced to draw every rectangle at the very bottom;
- player able to reinforce under pressure without the deployment system becoming irrelevant;
- formation width / depth still affecting battlefield entry;
- matches becoming less snowball-heavy without combat-stat buffs.

---

# 38. Failure Indicators

Reconsider the change if:

- formation drawing no longer creates meaningful choices;
- removing destination travel causes reinforcements to enter unrealistically fast;
- Mojo + Conscripts becomes overwhelmingly strong;
- enemy breakthroughs become trivial to recover from;
- Assault becomes dominant in all situations;
- unit overlap/pathfinding becomes significantly worse.

---

# 39. If the Player Is Still Overwhelmed

Do not immediately buff all player units.

Investigate in this order:

```text
1. Enemy deployment frequency
2. Enemy Command regeneration
3. Enemy starting Command
4. Player vs enemy deployment throughput
5. Targeting / engagement behavior
6. Range interactions
7. Only then additional combat-stat changes
```

Change one major variable at a time where practical.

---

# 40. Systems Explicitly Out of Scope

Do not block this iteration on:

```text
Bombing Run
Artillery
new Commander cards
new Unit cards
dynamic Mojo cost
advanced enemy AI
capture rebalance
campaign systems
store systems
meta progression
final visual polish
```

---

# 41. Definition of Done

This iteration is complete when:

> Player deployment rectangles define how a formation enters the battlefield rather than a position every soldier must reach; reinforcements become active immediately after entry; enemy deployment waits for the player's first committed deployment; enemy proximity removes nearby individual formation slots without broadly locking the command area; and `Incoming` units are easy to inspect through debug state feedback.

After implementation, rerun the same combat scenario before changing DPS, HP, Command costs, or Mojo.
