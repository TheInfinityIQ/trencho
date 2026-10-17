# Trencho — Unit Combat, Readability, and Capture-State Update
**Version:** 0.1  
**Purpose:** Developer handoff for the next prototype iteration  
**Status:** Prototype specification — values are intentionally test-oriented and should remain easy to tune

---

# 1. Goal of This Update

This iteration should improve three things at once:

1. Give Rifle, Assault, and Conscript units clearly different battlefield roles.
2. Improve unit readability through team color, unit-type icons, and state icons.
3. Add a capture-state sequence that preserves last-second defensive counterplay.

This update should also fix a current behavioral issue:

> Reinforcement units should not be unable to fight until they reach their assigned formation position.

The player's ordered position should remain the unit's movement objective, but units must be able to engage threats encountered while moving toward it.

---

# 2. Current Source Values

These are the current values from the three unit-card resources.

## Conscript Wave

```text
Command Cost: 2
Quantity: 12
Health: 60
Damage: 20
Melee Damage: 12
Melee Interval: 1.8
Move Speed: 260
Attack Interval: 3.5
Attack Range: 550
```

## Rifle Squad

```text
Command Cost: 3
Quantity: 6
Health: 100
Damage: 40
Move Speed: 300
Attack Interval: 3.0
Attack Range: 650
```

## Assault Squad

```text
Command Cost: 4
Quantity: 4
Health: 125
Damage: 55
Melee Damage: 35
Melee Interval: 1.1
Move Speed: 360
Attack Interval: 2.0
Attack Range: 500
```

The next values are not intended as final balance. They are deliberately differentiated so the intended roles are easy to observe during testing.

---

# 3. Proposed Unit Roles

## Rifle Squad

Role:

> General-purpose line infantry.

Rifles should be dependable at normal engagement distance and form the baseline against which the other infantry types are compared.

Desired characteristics:

- Medium unit count.
- Medium durability.
- Best standard ranged engagement distance.
- Moderate movement speed.
- Consistent firing cadence.
- Useful in most battlefield situations.
- Not the best specialized option at close range or mass deployment.

---

## Assault Squad

Role:

> Fast close-range wedge and congestion breaker.

Assault units should be especially useful when enemies penetrate deeply into the player's command/deployment area.

Desired characteristics:

- Low unit count.
- High individual close-range DPS.
- Short weapon range.
- High movement speed.
- Rapid firing cadence.
- Effective when spawned near an enemy breakthrough.
- Vulnerable while crossing open ground against longer-ranged units.

The intended player reaction should eventually be:

> "This is an Assault Squad situation."

when enemies have pushed too close or a dense position needs to be broken quickly.

---

## Conscript Wave

Role:

> Cheap mass, screening, attrition, and battlefield occupation.

Individual Conscripts should be clearly inferior soldiers.

Their advantage is quantity.

Desired characteristics:

- Very high unit count.
- Low cost.
- Low individual health.
- Low individual damage.
- Slow movement.
- Slow firing.
- Shorter range than Rifles.
- Strong at occupying space and absorbing targeting.
- Naturally creates its own congestion because of unit volume.
- Strong synergy with quantity-focused modifiers such as Commander Mojo.

The player should value Conscripts because they provide bodies, not because they are the most efficient source of raw damage.

---

# 4. Proposed Prototype Stats

Use the following as the next test baseline.

| Stat | Conscript Wave | Rifle Squad | Assault Squad |
|---|---:|---:|---:|
| Command Cost | 2 | 3 | 4 |
| Quantity | 12 | 6 | 4 |
| Health per Unit | 50 | 100 | 110 |
| Damage per Shot | 4 | 10 | 9 |
| Base Attack Interval | 1.10 sec | 0.75 sec | 0.32 sec |
| Attack Range | 500 | 650 | 400 |
| Move Speed | 250 | 300 | 420 |
| Approx. Squad Ranged DPS | 44 | 80 | 113 |
| Role | Mass / Attrition | Generalist | Close Assault |

These values are **PROVISIONAL**.

---

# 5. Why the Attack Cadence Is Changing

The current units use relatively large damage values with long intervals between attacks.

This makes the archetypes less visually distinct.

The proposed values keep roughly similar ranged-DPS relationships for Rifle and Assault units while changing how that damage is delivered.

Example:

Current Rifle:

```text
40 damage every 3.0 sec
≈ 13.3 DPS per soldier
```

Proposed Rifle:

```text
10 damage every 0.75 sec
≈ 13.3 DPS per soldier
```

The overall theoretical damage output is similar, but the proposed Rifle should feel like a soldier exchanging fire rather than waiting several seconds between large hits.

Current Assault:

```text
55 damage every 2.0 sec
≈ 27.5 DPS per soldier
```

Proposed Assault:

```text
9 damage every 0.32 sec
≈ 28.1 DPS per soldier
```

Again, the goal is to preserve approximately the same broad throughput while making the Assault role visibly rapid-fire.

Conscript damage is intentionally reduced more aggressively.

---

# 6. Small Per-Unit Variance

## REQUIRED FOR TESTING

Each soldier should receive minor stat variance once when spawned.

Do not reroll the variation every attack.

Recommended variation:

```text
Attack Interval: ±6%
Move Speed: ±3%
```

Example Rifle:

```text
Base Attack Interval:
0.75 sec

Spawned Range:
approximately 0.705–0.795 sec
```

Example movement:

```text
Base Move Speed:
300

Spawned Range:
approximately 291–309
```

This should make squads move and fire less mechanically in sync without creating large hidden power differences.

---

# 7. Stats That Should Not Vary Yet

Keep these fixed for the current prototype:

```text
Health
Damage
Attack Range
Command Cost
Unit Quantity
```

These values define the role of the card and need to remain predictable for balancing.

---

# 8. Reinforcement Combat Behavior

## REQUIRED

Units currently moving toward their assigned formation positions should be allowed to fight.

Do not use:

```text
spawn
-> reach assigned slot
-> combat enabled
```

Use:

```text
spawn
-> move toward assigned slot
-> enemy enters weapon range
-> stop and engage
-> enemy removed / leaves engagement condition
-> resume movement toward assigned position
-> reach position
-> transition into normal battlefield behavior
```

---

# 9. Recommended Unit State Flow

Suggested internal states:

```text
ENTERING
MOVING
ENGAGING
CAPTURING
EXITING
DEAD
```

Possible flow:

```text
ENTERING
    |
    v
MOVING
    |
    +---- enemy in valid range ----> ENGAGING
    |                                  |
    |                                  |
    <------ threat resolved ------------
    |
    v
CAPTURING
    |
    v
EXITING
```

Units may move between MOVING and ENGAGING repeatedly.

---

# 10. Combat While Moving Toward Formation Position

When a reinforcement is moving toward its assigned formation slot:

```text
if enemy enters valid attack range:
    stop movement
    enter ENGAGING
    attack normally
```

After the engagement ends:

```text
resume movement toward assigned formation position
```

Do not require the unit to reach the formation point before participating in combat.

This is necessary so the player is not always incentivized to place formations at the very bottom of the deployment area.

---

# 11. Firing While Moving

## PROTOTYPE RULE

Do not allow normal accurate firing while moving yet.

Use:

```text
move
-> stop
-> fire
-> resume movement
```

This should be easier to read and tune.

Moving-fire mechanics may be considered later for specific unit types if needed.

---

# 12. Assault Behavior

Do not give Assault units special targeting AI yet.

Use the normal targeting rules.

Their battlefield identity should emerge primarily from:

```text
short range
high movement speed
high attack frequency
small squad size
```

Recommended initial targeting:

```text
nearest valid enemy inside attack range
```

If these stats fail to create the intended wedge behavior, targeting rules may be revisited later.

---

# 13. Commander Mojo

Do not dynamically scale Commander Mojo's Command cost yet.

Current design intention:

```text
Commander Mojo
+50% deployment quantity
fixed Command cost
```

Examples:

```text
Assault Squad:
4 -> 6

Rifle Squad:
6 -> 9

Conscript Wave:
12 -> 18
```

This creates intentionally different value depending on the paired Unit card.

That is acceptable during the current prototype.

The first question is:

> Does Mojo become mandatory?

not:

> Does Mojo provide exactly equal value with every Unit card?

If Mojo becomes too dominant, test simple tuning before introducing dynamic cost scaling:

1. Increase Mojo's fixed Command cost.
2. Reduce the quantity bonus.
3. Add a maximum number of extra units.
4. Only consider dynamic scaling if simpler tuning fails.

---

# 14. Team Readability — Hat Color

## REQUIRED

Enemy unit hats/headgear should use a clearly red team color.

Player units should retain their own clearly different team presentation.

The purpose is immediate battlefield team recognition.

Do not rely only on hat color in the final game.

The unit-type icon system below should provide a second non-color channel.

---

# 15. Unit-Type Hat Icons

## REQUIRED

Every soldier should display a small unit-type icon on or immediately associated with the hat/headgear.

The icon identifies the soldier's archetype.

Suggested prototype icons:

```text
Rifle:
single chevron / diamond

Assault:
lightning bolt / double chevron

Conscript:
three dots / simple multi-mark
```

The exact art is flexible.

Important rules:

- Icons must be readable at gameplay camera distance.
- Avoid detailed weapon silhouettes.
- Use the same icon consistently on cards, hats, tooltips, and other UI where unit type is represented.
- Do not rely on color alone to distinguish the archetypes.

---

# 16. Unit State Icon

## REQUIRED

Add a small state icon adjacent to each unit's health bar.

The purpose is both player readability and prototype debugging.

Minimum player-facing state set:

| State | Suggested Icon | Meaning |
|---|---|---|
| Moving / Entering | Arrow | Unit is travelling |
| Engaging | Crosshair | Unit is actively attacking |
| Capturing | Flag | Unit is attempting to score |

Internally, ENTERING and MOVING may remain separate states even if they share the same visible icon.

---

# 17. State Icon Behavior

Recommended prototype behavior:

```text
ENTERING / MOVING
-> arrow icon

ENGAGING
-> crosshair icon

CAPTURING
-> flag icon
```

The icon should update immediately when the unit changes state.

For the prototype, keep state icons visible at all times.

Final production visibility rules can be decided later after effects and unit density increase.

---

# 18. Capture-State System

## RECOMMENDED

Add a dedicated capture region near the opponent's end of the battlefield.

Do not immediately score the unit at the moment it enters this region.

Instead:

```text
NORMAL BATTLEFIELD
        |
        | crosses capture threshold
        v
    CAPTURING
        |
        | still targetable
        |
        | moves toward score line
        v
    SCORE LINE
        |
        | score awarded
        v
      EXITING
```

This preserves a last opportunity for defenders to stop the breakthrough.

---

# 19. Capturing State

When a unit crosses the capture threshold:

```text
state = CAPTURING
```

Recommended behavior:

- Stop seeking new enemy targets.
- Continue toward the enemy score/exit boundary.
- Remain fully targetable.
- Remain fully damageable.
- Remain fully visible.
- Show the capture/flag state icon.
- Receive a modest movement speed bonus.

Proposed movement bonus:

```text
+20% to +25%
```

Start with:

```text
capture_speed_multiplier = 1.20
```

This value is **PROVISIONAL**.

---

# 20. Last-Second Counterplay

## IMPORTANT

A CAPTURING unit must not immediately become immune, untargetable, or visually faded.

If killed before crossing the scoring line:

```text
score = 0
```

This preserves:

> "Stop that unit before it gets through."

as a valid defensive moment.

---

# 21. Capture Targeting

While CAPTURING:

Recommended prototype rule:

```text
unit does not stop to acquire new targets
```

The unit is committed to the objective.

However:

```text
enemy units may still target and kill it
```

This makes reaching the capture state an offensive breakthrough without making the point automatic.

---

# 22. Score Line

Only when the unit crosses the actual scoring boundary:

```text
award score
state = EXITING
```

Scoring and visual removal should be separate events.

---

# 23. Exiting State

After score is awarded:

```text
state = EXITING
```

Then:

- unit may accelerate further;
- unit begins fading;
- unit leaves the active battlefield;
- unit is removed after the exit sequence.

Proposed fade duration:

```text
0.3–0.6 seconds
```

Example:

```text
0.45 sec
```

The fade occurs **after** the gameplay outcome is secured.

Do not fade a unit while defenders can still prevent the score.

---

# 24. Optional Capture Presentation

Future polish may include:

```text
flag icon pulse
subtle scoring sound
objective UI pulse
capture trail
```

These are not required for the next prototype.

---

# 25. Primary Matchup Tests

The next playtest should deliberately create these scenarios.

## Test A — Rifle vs Rifle at Range

Expected:

- stable firing-line behavior;
- clear cadence;
- neither side instantly evaporates;
- Rifle identity feels dependable.

Question:

> Does normal ranged combat feel readable and consistent?

---

## Test B — Assault Crossing Open Ground Into Rifles

Expected:

- Assault troops close distance quickly;
- Rifles begin dealing damage first because of range;
- Assault units are dangerous if enough survive to enter close range.

Question:

> Does Assault have meaningful vulnerability before reaching its effective range?

If Assault simply wins regardless of distance, it is too universally strong.

---

## Test C — Assault Used in the Friendly Command Area

Scenario:

Enemy units penetrate deeply into the player's deployment area.

Deploy Assault Squad nearby.

Expected:

- short travel distance minimizes Assault's range weakness;
- rapid fire becomes immediately useful;
- Assault clears close-range congestion better than Rifle or Conscript deployments.

Question:

> Does the battlefield situation naturally make Assault feel like the correct tool?

---

## Test D — Conscript Mass

Deploy Conscript Waves repeatedly.

Expected:

- large battlefield presence;
- weaker individual units;
- slower advance;
- lower individual lethality;
- significant spatial congestion;
- high compatibility with quantity modifiers.

Question:

> Are Conscripts valuable because of numbers rather than because they outperform Rifle squads economically in direct firepower?

---

## Test E — Capture Counterplay

Allow an attacker to enter CAPTURING state.

Attempt to kill it before the score line.

Expected:

- state clearly changes;
- attacker moves faster;
- defender can still attack;
- killing it before the line prevents score;
- crossing the line awards score immediately;
- fade begins only afterward.

Question:

> Does the capture sequence create tension without making the final part of the lane feel predetermined?

---

# 26. Debug Information

For prototype builds, make it possible to inspect:

```text
unit type
team
current state
base attack interval
spawned attack interval
base move speed
spawned move speed
attack range
current target
assigned formation slot
capturing status
```

This can be visible in debug overlays or inspector information.

It does not need production-quality presentation.

---

# 27. Implementation Acceptance Checklist

## Unit Stats

- [ ] Rifle stats changed to proposed prototype values.
- [ ] Assault stats changed to proposed prototype values.
- [ ] Conscript stats changed to proposed prototype values.
- [ ] Attack intervals use seconds consistently.
- [ ] Unit data remains externally tunable.

## Variance

- [ ] Attack interval varies by approximately ±6% per spawned soldier.
- [ ] Movement speed varies by approximately ±3% per spawned soldier.
- [ ] Variation is sampled once at spawn.
- [ ] Health does not randomly vary.
- [ ] Damage does not randomly vary.
- [ ] Range does not randomly vary.

## Reinforcement Behavior

- [ ] Reinforcements can engage before reaching their assigned slot.
- [ ] Units stop to fire.
- [ ] Units resume moving after the immediate engagement ends.
- [ ] Units still attempt to reach their ordered formation position.

## Readability

- [ ] Enemy hats are clearly red.
- [ ] Rifle unit-type icon exists.
- [ ] Assault unit-type icon exists.
- [ ] Conscript unit-type icon exists.
- [ ] Unit-type icon is visible at gameplay zoom.
- [ ] State icon appears near health bar.
- [ ] Moving state is visible.
- [ ] Engaging state is visible.
- [ ] Capturing state is visible.

## Capture

- [ ] Capture threshold exists.
- [ ] Crossing threshold sets CAPTURING state.
- [ ] Capturing units remain targetable.
- [ ] Capturing units remain damageable.
- [ ] Capturing units remain fully visible.
- [ ] Capturing units receive the configured movement bonus.
- [ ] Capturing units do not acquire new targets.
- [ ] Killing a Capturing unit before score line gives no score.
- [ ] Crossing score line awards score.
- [ ] Unit changes to EXITING after scoring.
- [ ] Fade only begins after score is awarded.

---

# 28. Systems Explicitly Not Required in This Update

Do not block this iteration on:

```text
dynamic Commander Mojo pricing
new Commander cards
Bombing Run
artillery
advanced enemy AI
formation-stat bonuses
new campaign systems
new meta progression
final UI art
final balance
```

The purpose is to test unit roles, readability, reinforcement combat behavior, and capture counterplay.

---

# 29. Decision Rules After Testing

## Rifle

Keep if:

> reliably useful without dominating specialized situations.

---

## Assault

Keep current role if:

- strong at close range;
- useful for clearing command-zone pressure;
- vulnerable while approaching ranged defenders;
- not obviously better than Rifle in every situation.

If too strong everywhere:

Change one major variable at a time.

Preferred tuning order:

```text
1. Range
2. Health
3. Damage / attack interval
4. Squad quantity
```

Do not nerf every stat simultaneously.

---

## Conscript

Keep current role if:

- individually weak;
- quantity is visibly valuable;
- useful as screens / mass;
- causes meaningful spatial pressure;
- does not outperform Rifles in both efficiency and general combat.

If too efficient, first reduce combat effectiveness rather than removing the quantity fantasy.

---

## Capturing

Keep if:

- crossing the capture threshold feels consequential;
- the state is visually obvious;
- defenders still feel they have a credible last-second response;
- capture does not routinely create long awkward chases.

If capture feels automatic too early:

```text
reduce capture threshold depth
reduce speed bonus
or increase distance between capture threshold and score line
```

If capture drags too long:

```text
increase capture speed modestly
or move threshold closer to score line
```

---

# 30. Definition of Done

This iteration is complete when:

> Rifle, Assault, and Conscript units are visibly and mechanically distinct; incoming units can fight before reaching their ordered formation position; team and unit type are readable through hats/icons; unit state can be inspected at a glance; and attackers entering the capture region visibly transition into a faster objective-focused state while remaining killable until they actually cross the scoring line.

After that, run the matchup tests before adding another major combat system.
