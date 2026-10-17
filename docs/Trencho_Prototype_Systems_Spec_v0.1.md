# Trencho Prototype Systems Specification
**Version:** 0.1  
**Purpose:** Developer handoff for the next playable mechanics prototype  
**Status:** Working specification — mechanics are intentionally provisional and should be revised after testing.

---

## 1. Prototype Goal

The next Trencho prototype should answer one main design question:

> **Does choosing what to deploy, where to deploy it, and whether to spend resources now or save for a stronger multi-card deployment create interesting tactical decisions?**

This build is **not** intended to prove the full campaign, progression, store, unlock, or content structure.

The prototype should focus on:

1. A resource economy.
2. A card hand.
3. Multi-card deployment packages.
4. Lane / deployment-zone selection.
5. Deployment-zone occupancy restrictions.
6. Autonomous unit movement and combat.
7. A simple enemy bot using the same battlefield rules.
8. Scoring / battle resolution sufficient to test the loop.
9. Debug information that makes system behavior inspectable.

---

# 2. Design Status Labels

Use these labels while implementing:

- **REQUIRED** — Needed for the next prototype.
- **PROVISIONAL** — Implement, but expose as tuning data because the value/rule is expected to change.
- **FUTURE** — Intentionally outside the next prototype.
- **OPEN** — Design decision has not yet been made.

Do not hard-code provisional tuning values where practical.

---

# 3. High-Level Battle Loop

## REQUIRED

The moment-to-moment loop should be:

1. Player receives / holds cards.
2. Player accumulates a battle resource.
3. Player observes the battlefield.
4. Player selects one Unit card.
5. Player may attach compatible modifier cards.
6. Player selects a legal deployment zone.
7. System validates:
   - card combination,
   - resource cost,
   - deployment-zone availability.
8. Resource cost is paid.
9. Cards resolve.
10. Units spawn.
11. Units move and fight autonomously.
12. Battlefield state changes.
13. Player adapts the next deployment to the new state.
14. Repeat until the battle ends.

### Core design principle

The player should primarily command **deployments**, not individual soldiers.

---

# 4. Battlefield / Lane System

## REQUIRED

The prototype battlefield currently uses three lanes:

- Left
- Middle
- Right

The player side advances toward the enemy side.

Each lane must have:

- a player deployment zone,
- an enemy deployment zone,
- a lane identifier,
- a way to query living units currently inside a deployment zone.

An **Even Spread** deployment option may also exist.

## Deployment Zone

A deployment zone is the physical area where a deployment may spawn.

A deployment zone has at minimum:

```text
zone_id
team_id
lane_id
is_occupied
occupying_units[]
spawn_points[]
```

### Occupancy Rule — REQUIRED

> A deployment zone cannot receive a normal unit deployment while any living unit, friendly or enemy, occupies that deployment zone.

This check happens at deployment validation time.

Example:

```text
Player attempts Rifle Squad -> Middle

Middle player deployment zone contains a friendly unit.

Result:
Deployment rejected.
No resource spent.
No cards consumed.
```

### Important behavior

A unit should cease blocking the deployment zone after it has physically left the zone.

Do **not** use a fixed timer to clear the zone if actual unit position can determine occupancy.

---

# 5. Deployment Lock / Breakthrough Behavior

## REQUIRED FOR TESTING

Enemy units are allowed to enter the player's deployment zone and vice versa.

If an enemy occupies a deployment zone:

- normal Unit deployments into that zone are blocked.

This creates a battlefield consequence for being pushed backward.

## OPEN

The final consequence of all three deployment zones being enemy-occupied has not been decided.

For the prototype, use one of these simple behaviors:

### Recommended prototype behavior

If all player deployment zones are blocked by enemy units for a configurable duration:

```text
player loses battle
```

Likewise for the enemy.

### PROVISIONAL

```text
all_zones_blocked_defeat_delay = 3–5 seconds
```

The exact value is tuning data.

---

# 6. Resource Economy

## REQUIRED

Replace the planned hand cooldown as the primary action limiter with a battle resource.

Working name:

```text
Command
```

The displayed name may later become Supply, Orders, Command Points, Logistics, etc.

## Resource State

Each side has:

```text
current_command
maximum_command
command_regeneration_rate
```

## Default Prototype Behavior

Command regenerates continuously.

Example provisional values:

```text
maximum_command = 10
command_regeneration_rate = 1 per second
starting_command = 3
```

These are **PROVISIONAL**.

## Spending

Each playable card has a Command cost.

For a multi-card deployment:

```text
total_cost = sum(cost of all cards in the deployment package)
```

The deployment is legal only when:

```text
current_command >= total_cost
```

When deployment succeeds:

```text
current_command -= total_cost
```

### Important rule

Resource should only be deducted **after all validation succeeds**.

If deployment is rejected because:

- the zone is occupied,
- the combination is illegal,
- there are insufficient resources,
- another validation fails,

then no resource is spent.

---

# 7. Card System

## REQUIRED

The player has a hand of cards.

The existing prototype uses a visible hand and deck/discard state. Preserve this concept.

A card should be data-driven.

Suggested base card data:

```text
card_id
display_name
card_type
tags[]
command_cost
description
art_reference
effect_data
```

---

# 8. Card Types

## REQUIRED FOR NEXT PROTOTYPE

Use at least these categories:

### 8.1 Unit Card

Creates battlefield units.

Example:

```text
Rifle Squad
Type: Unit
Tags: Infantry, Light
Base Units: 6
Cost: 3
```

A deployment package must normally contain exactly **one Unit card**.

---

### 8.2 Modifier Card

Changes the Unit card being deployed.

Modifiers can include:

- Commanders
- Support effects
- Tactical orders

For the prototype, these may all share one implementation category:

```text
Modifier
```

They can later be split into separate card types if useful.

Example:

```text
Commander Mojo
Type: Modifier
Tags: Commander, Infantry
Effect:
    +50% unit quantity
Compatibility:
    Unit card must have Infantry tag
```

---

### 8.3 Special Card

## FUTURE / OPTIONAL IN NEXT PROTOTYPE

A Special card affects the battlefield directly rather than modifying a normal deployment.

Examples:

- artillery,
- air strike,
- emergency reserves,
- temporary lane effect.

Special cards should eventually be capable of breaking normal rules when explicitly designed to do so.

Example:

```text
Emergency Reserves
Can deploy while the player's normal deployment zone is blocked.
```

Special cards are not required to validate the first multi-card deployment loop.

---

# 9. Multi-Card Deployment Packages

## REQUIRED

The player should be able to create a deployment package.

For the first implementation:

```text
1 Unit card
+
0 to 2 compatible Modifier cards
```

Maximum:

```text
3 cards per deployment package
```

This limit is **PROVISIONAL**, but recommended for the first test.

Do not implement five-card combinations yet.

## Valid Examples

```text
Rifle Squad
```

```text
Rifle Squad
+ Commander Mojo
```

```text
Rifle Squad
+ Commander Mojo
+ Forced March
```

## Invalid Examples

```text
Commander Mojo
```

Reason:
No Unit card.

```text
Rifle Squad
+ Assault Squad
```

Reason:
More than one Unit card.

```text
Rifle Squad
+ Modifier A
+ Modifier B
+ Modifier C
```

Reason:
Exceeds modifier limit.

---

# 10. Compatibility / Tag System

## REQUIRED

Cards must be able to restrict which other cards they modify.

Use tags rather than hard-coded card-to-card references where possible.

Example:

```text
Rifle Squad:
Tags = [Infantry, Light]
```

```text
Commander Mojo:
Required Target Tags = [Infantry]
```

Then:

```text
Commander Mojo + Rifle Squad = valid
Commander Mojo + Tank = invalid
```

This enables future combinations without requiring custom logic for every pair.

---

# 11. Modifier Resolution

## REQUIRED

The deployment system should generate a final deployment specification before spawning anything.

Example base Unit card:

```text
Rifle Squad

unit_type = Rifleman
quantity = 6
move_speed_multiplier = 1.0
damage_multiplier = 1.0
health_multiplier = 1.0
```

Commander Mojo:

```text
quantity_multiplier = 1.5
```

Final deployment:

```text
quantity = floor(6 * 1.5)
quantity = 9
```

## Resolution Order

Use a consistent order.

Recommended:

1. Load base Unit card values.
2. Apply additive modifiers.
3. Apply multiplicative modifiers.
4. Apply replacements / special overrides.
5. Clamp values if required.
6. Round discrete values such as unit count.
7. Generate final deployment.
8. Spawn.

Example:

```text
final_quantity =
floor(
    (base_quantity + additive_quantity)
    * quantity_multiplier
)
```

Keep the order centralized so card behavior remains predictable.

---

# 12. Commander Mojo — Prototype Specification

## PROVISIONAL TEST CARD

```text
Name:
Commander Mojo

Type:
Modifier

Tags:
Commander
Infantry

Compatibility:
Must be attached to a Unit card with the Infantry tag.

Effect:
Increase the number of units in the deployment by 50%.

Resolution:
final_quantity = floor(base_quantity * 1.5)

Cost:
PROVISIONAL
```

Example:

```text
Rifle Squad:
6 units

Rifle Squad + Commander Mojo:
9 units
```

This effect should be implemented through the normal modifier system, not as special-case logic inside Rifle Squad.

---

# 13. Player Deployment Flow

## REQUIRED

Recommended interaction:

### Step 1
Player selects a Unit card.

### Step 2
Compatible Modifier cards become selectable.

Illegal modifier combinations should be visibly disabled or rejected.

### Step 3
UI displays:

```text
Selected deployment
Total Command cost
Modified unit quantity
Relevant modified attributes
```

Example:

```text
RIFLE SQUAD
+ COMMANDER MOJO

Units: 6 -> 9
Cost: 3 -> 6
```

### Step 4
Player selects:

- Left,
- Middle,
- Right,
- Even Spread if supported.

### Step 5
System validates the deployment.

### Step 6
If valid:

- spend Command,
- consume / discard cards,
- spawn units,
- clear current card selection.

### Step 7
If invalid:

- show reason,
- spend nothing,
- do not discard cards.

---

# 14. Even Spread

## OPEN / PROVISIONAL

The existing prototype supports an Even Spread option.

If retained:

```text
deployment_quantity is distributed between all legal lanes
```

Example:

```text
9 units
-> 3 Left
-> 3 Middle
-> 3 Right
```

## Important unresolved rule

What happens if one or more zones are occupied?

Recommended prototype rule:

> Even Spread is legal only when every required deployment zone is currently open.

This prevents the system from silently changing the player's intended deployment.

Alternative behaviors may be tested later.

---

# 15. Deck / Hand / Discard System

## REQUIRED AT BASIC LEVEL

Maintain:

```text
draw_pile
hand
discard_pile
```

The current mechanics demo already represents deck/discard state.

## Recommended prototype rule

When a successful deployment occurs:

```text
all cards used in that deployment
-> discard pile
```

Then draw cards according to the current hand-size rule.

### PROVISIONAL

```text
maximum_hand_size = 5
```

## Deck Exhaustion

When draw pile is empty and cards must be drawn:

```text
shuffle discard pile
-> new draw pile
```

The exact randomization behavior should use the engine's reproducible RNG facilities where practical.

For debugging, expose the random seed when useful.

---

# 16. Unit Spawn System

## REQUIRED

The deployment system sends a finalized deployment specification to the spawn system.

Example:

```text
DeploymentRequest
{
    team,
    lane,
    unit_type,
    quantity,
    stat_modifiers,
    source_cards
}
```

The spawn system is responsible for:

1. finding valid spawn positions,
2. spawning the requested quantity,
3. assigning team,
4. assigning lane / destination,
5. applying finalized modifiers,
6. registering units with battlefield state.

The card system should not directly control unit movement or combat after spawning.

---

# 17. Unit Movement

## REQUIRED

Units autonomously move toward the opposing side.

Minimum state model:

```text
ADVANCING
ENGAGING
DEAD
```

Optional later states:

```text
RETREATING
SUPPRESSED
STUNNED
ABILITY
```

For the prototype:

```text
If no valid enemy target:
    advance

If enemy is in engagement range:
    stop
    engage

If target becomes invalid/dead:
    acquire another target
    otherwise resume advance
```

---

# 18. Combat

## REQUIRED AT MINIMUM

The purpose of prototype combat is to create battlefield pressure and changing lane states.

Minimum unit combat properties:

```text
health
damage
attack_range
attack_interval
move_speed
targeting_rules
```

Combat does not need production-quality animation or sophisticated tactical AI yet.

## Targeting

Start simple.

Recommended:

```text
target nearest valid enemy within attack range
```

Do not add complex target prioritization until the basic battle loop works.

---

# 19. Scoring / Victory

## REQUIRED

The prototype needs a clear battle-ending rule.

The current mechanics demo already shows team scoring.

The exact final scoring design is still **OPEN**.

## Recommended prototype implementation

A unit reaching the opponent's scoring boundary:

```text
awards points to its team
and is removed from active battle
```

Example:

```text
score += unit_score_value
```

The actual score values and victory threshold are **PROVISIONAL**.

Example:

```text
victory_score = 100
```

### Alternative / additional loss condition

All three deployment zones blocked for the configured duration may also trigger defeat.

These victory conditions should be configurable independently for testing.

---

# 20. Enemy Test Bot

## REQUIRED

Do **not** build advanced AI yet.

The enemy's purpose is to create repeatable battlefield pressure so the player-facing systems can be tested.

The bot should use:

- its own Command economy,
- the same deployment-zone occupancy rules,
- the same unit spawn system,
- the same combat rules.

The bot does **not** need a visible hand or full deck simulation initially.

---

# 21. Enemy Economy

Suggested provisional values:

```text
enemy_max_command = 10
enemy_starting_command = 3
enemy_command_regeneration = 1/sec
```

Use the same resource component as the player where practical.

---

# 22. Enemy Decision Cycle

## REQUIRED

Run a decision periodically.

Example:

```text
enemy_decision_interval = 1 second
```

Pseudo-code:

```text
Every decision interval:

    open_zones = get_open_enemy_deployment_zones()

    if open_zones is empty:
        do nothing
        return

    affordable_actions = get_affordable_enemy_actions()

    if affordable_actions is empty:
        wait
        return

    lane = choose_lane(open_zones)

    action = choose_deployment(affordable_actions)

    deploy(action, lane)
```

---

# 23. Enemy Lane Choice — Version 1

## REQUIRED

Use a simple heuristic.

Recommended:

```text
70%:
    choose legal lane with lowest player strength

30%:
    choose random legal lane
```

The exact weighting is **PROVISIONAL**.

## Lane Strength

For the first bot:

```text
lane_strength = number of living units belonging to that team in the lane
```

Do not build an advanced combat-power model yet.

Later this can become:

```text
sum(unit combat values)
```

---

# 24. Enemy Deployment Options

For the first version, the enemy may use a small fixed list instead of a real deck.

Example:

```text
Rifle Squad
Cost: 3
Quantity: 6
```

Later:

```text
Assault Squad
Large Wave
Commander combinations
Special cards
```

Do not implement enemy commanders until the basic economy/pressure loop works.

---

# 25. Shared Rules Between Player and Enemy

## IMPORTANT IMPLEMENTATION REQUIREMENT

Where practical, the player and enemy should use the same systems for:

- economy,
- deployment validation,
- deployment zones,
- unit spawning,
- unit stats,
- combat,
- scoring.

The difference should primarily be **who generates the deployment request**.

Conceptually:

```text
PLAYER INPUT ───────┐
                    │
                    v
             Deployment Request
                    |
                    v
             Validate Deployment
                    |
                    v
                Spawn Units
                    |
                    v
               Battlefield


ENEMY AI ───────────┘
```

Avoid building one set of game rules for the player and another for the enemy unless a design explicitly requires asymmetry.

---

# 26. Deployment Validation Service

## REQUIRED

Centralize deployment validation.

Suggested function:

```text
validate_deployment(
    team,
    selected_cards,
    target_zone
)
```

Return:

```text
is_valid
failure_reason
total_cost
resolved_deployment
```

Validation order:

1. Valid card package?
2. Exactly one Unit card?
3. Modifier limit respected?
4. Modifier compatibility valid?
5. Target zone belongs to team?
6. Target zone open?
7. Enough Command?
8. Spawn capacity available?
9. Other explicit restrictions?

No effects should resolve until validation succeeds.

---

# 27. Failure Reasons

## REQUIRED FOR DEBUG / UI

Use explicit failure identifiers.

Example:

```text
NO_UNIT_CARD
MULTIPLE_UNIT_CARDS
TOO_MANY_MODIFIERS
INCOMPATIBLE_MODIFIER
INSUFFICIENT_COMMAND
ZONE_OCCUPIED
INVALID_ZONE
NO_SPAWN_POSITION
```

This helps both UI messaging and debugging.

---

# 28. Debug / Developer UI

## REQUIRED

The prototype should make decisions inspectable.

Display or make accessible:

### Player

```text
Current Command
Max Command
Command Regen
Selected Cards
Total Deployment Cost
Resolved Unit Count
Selected Zone
Zone Occupancy
```

### Enemy

```text
Enemy Command
Next Decision Time
Open Zones
Lane Strength Values
Chosen Lane
Chosen Deployment
Reason / decision score
```

### Battlefield

```text
Living units by team
Living units by lane
Score
Deployment-zone occupants
```

Debug information may be ugly. It exists to make system behavior understandable.

---

# 29. Events / Signals

Recommended game-level events:

```text
command_changed
card_selected
card_deselected
deployment_requested
deployment_rejected
deployment_accepted
unit_spawned
unit_entered_zone
unit_exited_zone
unit_died
unit_reached_goal
score_changed
battle_ended
```

This keeps UI and game systems from becoming tightly coupled.

---

# 30. Suggested Data Ownership

A possible responsibility split:

## BattleManager

Owns:

```text
battle_state
scores
victory conditions
battle start/end
```

## EconomyComponent

Owns:

```text
current_command
maximum_command
regeneration
spending
```

Attach one to each team.

## CardManager

Owns:

```text
deck
hand
discard
selection
draw behavior
```

## DeploymentManager

Owns:

```text
package validation
zone validation
modifier resolution
deployment requests
```

## DeploymentZone

Owns:

```text
team
lane
occupants
spawn locations
occupancy state
```

## Unit

Owns:

```text
health
movement
combat state
target
team
lane
```

## EnemyController

Owns:

```text
decision timing
lane evaluation
action selection
```

EnemyController should request actions through the normal DeploymentManager.

---

# 31. Prototype Content Set

Do not build a large card pool yet.

Recommended minimum:

## Unit Cards

### Rifle Squad

```text
6 general infantry
```

### Assault Squad

```text
lower quantity
higher combat strength / movement
```

### Conscript Wave

```text
high quantity
lower individual combat strength
```

## Modifier Cards

### Commander Mojo

```text
+50% deployment quantity
Infantry only
```

### Forced March

Example:

```text
+movement speed
-different combat drawback
```

Exact numbers OPEN.

### Defensive Officer

Example:

```text
+survivability
-movement speed
```

Exact numbers OPEN.

## Optional Special

### Artillery

Direct battlefield effect useful for testing blocked lanes.

---

# 32. Prototype Tuning Variables

Expose these for rapid iteration:

```text
command_max
command_start
command_regeneration_rate

card_costs

unit_quantity
unit_health
unit_damage
unit_move_speed
unit_attack_range
unit_attack_interval

modifier_values

enemy_decision_interval
enemy_lane_choice_weights

victory_score
deployment_block_defeat_delay
```

Prefer editor-exposed data/resources over constants buried in code.

---

# 33. Systems Explicitly Out of Scope

## FUTURE

Do not block the mechanics prototype on:

- Campaign map.
- Multiple campaigns.
- Mission chains.
- Permanent card unlocks.
- Achievements.
- POW conversion.
- Armoury.
- Store refresh / item locking.
- Meta progression.
- Final art.
- Final animations.
- Final audio.
- Multiplayer.
- Online accounts.
- Backend services.
- Matchmaking.
- Advanced enemy AI.
- Final difficulty modes.
- Large card pool.
- Final balance.
- Analytics backend.

These may return after the battle loop proves worth expanding.

---

# 34. Acceptance Test — Prototype Milestone

The next prototype milestone is complete when all of the following work:

### Economy

- [ ] Player Command regenerates.
- [ ] Enemy Command regenerates.
- [ ] Cards/actions have costs.
- [ ] Illegal deployment does not consume Command.
- [ ] Successful deployment consumes the correct amount.

### Cards

- [ ] Player has a hand.
- [ ] One Unit card can be selected.
- [ ] Up to two compatible Modifier cards can be attached.
- [ ] Invalid combinations are rejected.
- [ ] Total deployment cost is shown.
- [ ] Modified output can be previewed.

### Commander Mojo

- [ ] Mojo only works with compatible Infantry Unit cards.
- [ ] Mojo increases deployment quantity by 50%.
- [ ] Quantity is resolved before spawning.

### Deployment Zones

- [ ] Left / Middle / Right zones exist for both sides.
- [ ] Occupancy is derived from living units inside the zone.
- [ ] Occupied zones reject normal deployments.
- [ ] Zones become available again when occupants leave or die.
- [ ] Enemy units can block player zones.
- [ ] Player units can block enemy zones.

### Units

- [ ] Units spawn at the selected legal zone.
- [ ] Units advance autonomously.
- [ ] Units acquire enemies.
- [ ] Units attack.
- [ ] Units die.
- [ ] Units resume advancing when no target remains.

### Enemy

- [ ] Enemy gains Command.
- [ ] Enemy periodically considers deployment.
- [ ] Enemy does nothing when no legal action exists.
- [ ] Enemy prefers weak lanes according to the current heuristic.
- [ ] Enemy sometimes chooses another lane due to controlled randomness.
- [ ] Enemy uses the normal deployment validation/spawn system.

### Battle

- [ ] Units can create score / progress toward a win condition.
- [ ] Score is visible.
- [ ] Battle can end.
- [ ] Battle can restart without restarting the development environment.

### Debugging

- [ ] Enemy decisions can be inspected.
- [ ] Zone occupancy can be inspected.
- [ ] Economy values can be inspected.
- [ ] Deployment rejection reason can be inspected.

---

# 35. First Playtest Question

Do **not** initially evaluate the build by asking:

> "Is the game fun?"

The first useful observation is:

> **Does the player repeatedly face meaningful choices between deploying immediately, saving Command for a stronger combination, and responding to lane pressure?**

Watch for situations such as:

```text
"I want to save for Mojo, but Right is collapsing."

"Middle is blocked, so I need to deploy somewhere else."

"I can afford a cheap squad now or wait for a stronger package."

"I concentrated too much on Left and now Middle is vulnerable."
```

If those decisions naturally occur, the economy, lane, and multi-card systems are beginning to interact successfully.

If the player simply saves for the same optimal combination every time, that is a design problem to investigate before expanding content.

---

# 36. Known Risks

## Dominant Combo

One Unit + Commander combination may become so efficient that other plays are irrelevant.

### Test

Compare cost-efficiency and battlefield usefulness across several situations.

---

## Passive Waiting

Replacing a cooldown with Command regeneration can still become a waiting game if the optimal action is always to save.

### Test

Create enough lane pressure that spending early sometimes has real value.

---

## Snowballing

Do not make kills the primary source of Command in the first prototype.

Otherwise:

```text
winning
-> more kills
-> more income
-> more deployments
-> winning harder
```

Passive income provides both sides a baseline ability to respond.

---

## Total Deployment Lock

If all zones are blocked, a player may have no legal recovery action.

For the prototype, treat sustained total deployment lock as a battle-ending state.

Later, Special cards may provide recovery tools.

---

## Even Spread Dominance

If Even Spread has little downside, individual lane selection may stop being meaningful.

### Test

Ensure concentrated and distributed deployments each have situations where they are preferable.

---

# 37. Open Design Questions

These should remain configurable or unresolved until testing provides evidence:

1. Final name of the battle resource.
2. Resource regeneration rate.
3. Resource cap.
4. Starting resources.
5. Individual card costs.
6. Final hand size.
7. Maximum modifier count.
8. Whether Commanders and Support cards become separate card types.
9. Whether the player draws continuously or only after deployments.
10. Whether Even Spread remains in the final game.
11. Even Spread behavior when one lane is blocked.
12. Exact scoring rule.
13. Exact battle victory threshold.
14. Whether full deployment lock causes immediate defeat or delayed defeat.
15. Whether Special cards can deploy into blocked zones.
16. Whether units are permanently lane-bound after spawning.
17. Whether units can retreat or change lanes.
18. Final enemy difficulty behavior.
19. Whether the enemy eventually uses an actual deck/hand.
20. Final unit/card balance.

---

# 38. Recommended Implementation Order

Implement in this order:

```text
1. Economy component
2. Deployment-zone occupancy
3. Central deployment validation
4. Card costs
5. Multi-card selection
6. Tag compatibility
7. Modifier resolution
8. Commander Mojo
9. Shared deployment request
10. Simple enemy economy
11. Simple enemy decision loop
12. Combat / scoring cleanup as needed
13. Debug UI
14. Playtest
```

Do not expand the card pool before the first playtest of this system.

---

# 39. Definition of Done for This Iteration

This iteration is done when:

> A player and a simple enemy bot operate under the same economy and deployment constraints, the player can create a legal multi-card deployment such as Rifle Squad + Commander Mojo, occupied zones prevent deployment, autonomous units produce changing lane pressure, and the battle reaches a clear resolution.

At that point, test the interaction before committing to additional campaign or content systems.
