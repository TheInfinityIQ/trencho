# Trencho mechanics prototype

The current build implements the economy/card/battle systems from `Trencho_Prototype_Systems_Spec_v0.1.md` and the entry-formation replacement in `Trencho_Deployment_Flow_Reinforcement_Pressure_Update_v0.1.md`. The latest update supersedes destination formations and binary deployment-zone lockout. Automatic deck reshuffling follows the latest player instruction.

## Playing

- The game opens maximized with a closer view of your side. UI scales with the window. Scroll or +/− zoom; middle-drag, WASD and arrow keys pan. Overview/Home shows the map; Deploy returns to your side; F11 toggles fullscreen.
- Select a Unit and up to two compatible Modifiers **in either order**. Clicking an already selected card removes that card; switching Units preserves compatible Modifiers. Incompatible combinations and excess Modifiers are rejected without changing the current selection.
- **Right-click anywhere** or Escape clears cards, any active drag, and the formation preview without spending anything.
- Click and drag in the large blue friendly deployment area to draw the requested footprint. Its exact width and depth determine candidate formation slots. Nothing auto-expands or snaps the rectangle.
- Ghosts show the requested units. Green means the complete order is legal; red means it is not. Space/Needed labels and a readable reason explain why. Friendly bodies, terrain colliders, enemy exclusion circles and existing reservations remove individual slots, rather than blocking the whole region.
- Release a green rectangle to confirm. The order is revalidated, Command is spent once, all selected cards are discarded, replacements are drawn, and the chosen positions are reserved. Pale blue rings show reservations for the incoming formation geometry; they are not movement destinations. The HUD shows queued plus entering soldiers as Incoming.
- A rejected rectangle stays red. Drag its corner handles to resize, drag its interior to move it, or draw a new rectangle elsewhere. Change cards or wait for Command, then click/release it or press Enter to retry. Rejection never spends Command, consumes cards, reserves slots or spawns troops.
- Reinforcements queue **behind the battlefield**. The requested X positions and relative rank depth translate behind the home edge. All clear soldiers across one rank spawn together; the next rank can release after 0.12 seconds. Vertical rectangle placement creates no extra travel. Soldiers advance straight forward and can stop to fight immediately, including during entry. They become active once their full body crosses the edge; there is no destination-arrival stage.
- An obstructed entry file waits without moving or resizing the requested geometry. Other clear files/ranks can enter. Actual body spacing prevents overlapping spawns and forward movement through another soldier. Entry or death frees reservations; terrain may still hold up a route until it clears.
- Dragging cards remains available for selection/discard, but dropping a card on the battlefield does not invent a formation. Draw a rectangle after choosing the cards.
- Click the discard pile with a selection, or drag the selection onto it, to exchange the selected cards. Refills draw up to the configured hand size; an exhausted draw pile automatically reshuffles the discard pile. Discarding costs no Command.
- F3/Debug shows candidate/free/blocked slots, friendly spacing, enemy exclusion, reserved slots, entry points, forward direction indicators and flow counts. While debug is open, pan behind either map edge to inspect off-screen entry. Restart/Play again starts a clean battle.

## Shared battle rules

Both sides start at 3 Command, cap at 10, and regenerate 1/second. Default five-card hands, one Unit plus up to two Modifiers. Costs and modified stats are shown before ordering. Modifier resolution remains centralized: additions, multipliers, overrides in package order, clamps, then discrete rounding. Separate copies of a modifier may stack within the modifier limit.

The enemy uses the same spatial validation, reservations, reinforcement queue, unit stats, combat and scoring rules. It waits for the player’s first accepted deployment, then its seeded decision cycle runs every second. Its economy regenerates normally during the startup wait; later player inactivity or troop losses do not close the gate. It prefers the weakest legal lane 70% of the time; otherwise it chooses randomly among legal lane footprints. Those lane footprints are bot presets, not player restrictions.

Victory defaults to 100 points, one per unit reaching the opposite scoring boundary. Scoring removes a unit exactly once. The old three-zone-touch defeat condition is replaced: the optional deployment-lock defeat rule is off by default and, if enabled, requires enemy exclusion across the **entire** deployment region for the configured delay. A few enemies cannot arbitrarily disable deployment.

| Card | Command | Output / effect |
| --- | ---: | --- |
| Rifle Squad | 3 | 6 infantry; 100 health, 45 damage / 0.75s (60 DPS), 650 range, 300 speed |
| Assault Squad | 4 | 4 infantry; 225 health, 25.6 damage / 0.32s (80 DPS), 400 range, 420 speed |
| Conscript Wave | 2 | 12 infantry; 75 health, 27.5 damage / 1.10s (25 DPS), 585 range, 250 speed |
| Commander Mojo | 3 | Infantry only; quantity ×2 (+100%) |
| Forced March | 2 | Infantry only; speed ×1.4, ranged/melee damage ×0.8 |
| Defensive Officer | 2 | Infantry only; health ×1.5, speed ×0.8 |

## Tuning in Godot

- `data/battle_tuning.tres`: economies, hand size, modifier limit, seed, minimum spacing and body radius, enemy exclusion radius, interval between ranks, off-screen entry margin, bot settings, and battle-ending rules.
- `data/cards/*.tres`: costs, quantities, tags, art, all combat stats, and modifier additions/multipliers/overrides.
- `scenes/cards/hand_of_cards.tscn`: starting deck IDs. Default: 3 Rifle Squads, 2 Assault Squads, 2 Conscript Waves, one of each Modifier.
- `main.tscn`: tuning resource, card catalog, starting zoom and camera speed.

Deployment regions span 90% of the map width and 26% of its depth on each side. Formations reserve positions immediately on acceptance. Reservations track QUEUED and ENTERING soldiers, and are freed when the soldier fully crosses its home edge or dies. The physical body still removes usable space until it is safely clear. No formation stat bonuses, congestion Command taxes or Special-card mechanics are included.

The six supplied temporary card illustrations are stored in `assets/cards/prototype/`. Units still use the original soldier visuals. Painted paths and trenches are decorative; real physics terrain colliders are excluded from formations. Enemy exclusion defaults to a local 144-pixel radius (unit diameter is 140). It removes nearby individual slots; a formation remains legal if enough other slots survive. Full pathfinding around complex obstacles remains outside this iteration.

## Validation

Import/open the project in Godot before running tests from a fresh checkout. Run with a Godot 4 executable from the project directory:

```
godot --headless --path . --fixed-fps 60 --script tests/reinforcement_flow_test.gd --quit-after 1200
godot --headless --path . --fixed-fps 60 --script tests/formation_test.gd --quit-after 600
godot --headless --path . --fixed-fps 60 --script tests/combat_input_test.gd --quit-after 600
godot --headless --path . --script tests/camera_test.gd --quit-after 180
godot --headless --path . --fixed-fps 60 --script tests/battle_soak_test.gd --quit-after 12000
```

The formation suite covers order-independent selection, right-click cancellation, exact drawing, resizing/moving, shape/capacity, spacing, friendly/terrain/enemy exclusions, atomic rejection, card consumption, reservations, physical off-screen entry, edge activation, freeing reservations, blocked files, congestion and narrow/deep ranks. The reinforcement-flow suite covers startup gating, vertical-translation invariance, both team entry geometries, local enemy denial, a 24-unit Mojo Conscript wave, emergency Assault entry combat and logistics counters. Combat/input tests cover the live input flow, combat targeting/cooldowns, scoring and restart. Camera tests verify zoom/pan and deployment coordinates. The soak test plays up to three simulated minutes and checks deployments, fighting and scoring. `tests/prototype_test.gd` and `tests/deployment_test.gd` are compatibility aliases for the current formation suite.

Balance and the designer's playtest questions still require human testing. Campaign/progression systems, final art, formation bonuses, congestion taxes, bombing runs and advanced pathfinding remain outside this iteration.


### Combat, symbols and capture
Incoming reinforcements stop to fight nearest threats and resume straight forward entry afterward. No soldier must reach the drawn rectangle. Each soldier rolls attack interval ±6% and speed ±3% once using a dedicated seeded random stream. Other stats remain fixed; existing melee values are unchanged.

Enemy hats are red and player hats blue. The shared type symbols are Rifle diamond, Assault lightning, and Conscript three dots. A flag beside health highlights capture and the scored exit. Ordinary movement, reinforcement entry and combat have no state icon during normal play. F3 enables their arrow/crosshair indicators, plus clock icons at queued entry origins. Unit-type symbols remain visible. Cards and the selected package show per-soldier ranged DPS (damage divided by the base attack interval), before spawn variance. Open F3 and hover a soldier to inspect base/spawned stats, team, state, target, entry origin, queue wait, time since spawn and total time to enter. The debug summary separates Queued, Entering, Active, Advancing, Engaging, Capturing, Exiting and cumulative Dead counts for both sides. Entering is a physical status and includes off-field soldiers who are already fighting. Oldest incoming age helps diagnose bottlenecks.

Gold lines mark capture thresholds, 600 world pixels before the scoring lines. Capturing soldiers stop acquiring targets, advance at 1.20× speed, and remain fully visible and vulnerable. Their center must cross the actual score line to award points. Scored units leave active combat and move/fade over 0.45 seconds, including the winning unit. Tune capture, variance and fade in BattleTuning.

Automated combat scenarios: `tests/combat_readability_capture_test.gd`. These verify role values, range advantage, rapid cadence, formation combat/resumption and defensive capture counterplay. Subjective balance and congestion still need live playtesting.
