# Trencho mechanics prototype

Current interaction contract: [Drawn Commands v0.2](DRAWN_COMMAND_V02_IMPLEMENTATION.md). The sections below record the v0.1 baseline; the linked v0.2 document supersedes one-Unit, straight-line and fixed-circle assumptions. This supersedes the old player deployment-zone/exclusion and battlefield rectangle interaction. Formation, collision, economy and scoring still use shared systems for both teams.

## Playing

- Select one Unit and up to two compatible Modifiers, in either order. Click the battlefield to open a temporary **Squad Blueprint**. The clicked horizontal position sets entry frontage; its vertical position is not a movement destination.
- Resize the initial formation using its corner or edge handles only. The preview shows quantity, cost and capacity. An undersized formation cannot proceed.
- Choose **Use formation → draw an order**. Nothing is spent yet. Drag the single white order knob: a line means **Advance**, a loop means **Defend**. A short stem from the knob to the loop is supported. There is no gesture accuracy bonus.
- A valid initial command spends Command once, discards/refills the selected cards, creates a distinct squad with an intent, and queues off-screen reinforcements. Failed/cancelled setup or commands spend nothing.
- New squads are not limited to the old deployment rectangles. Enemy proximity or occupancy in the blueprint's world projection does not veto deployment. Real bodies/terrain at an off-screen entrance can delay individual soldiers safely; queued soldiers retry rather than disappear.
- **Advance** soldiers fight threats in range, then continue toward the enemy side. Survivors do not automatically re-form.
- **Defend** soldiers move to allocated positions and fight immediate threats en route. Once established, they target enemies inside the defense circle, prefer already shootable targets, and can reposition within their leash. They return to their positions when threats disappear.
- Defense circles expand to fit all commanded soldiers, up to the configured maximum. Packing leaves movement corridors so settled defenders do not cage later arrivals. Squads keep separate identities within a shared circle. Defensive reformation after casualties waits for pressure to end.
- Click any friendly soldier to select its whole squad. White rings mark selection. Click a selected squad to toggle it off; Shift+click adds/removes squads. Releasing Shift preserves selection. Selection alone never slows the game.
- Drag the selected squads' single knob to re-command them without reopening the blueprint. Advance clears their defense order; Defend assigns a new shared area.
- **Right-click / Escape** backs out one level: cancel an active gesture while preserving orders/selection; back out of blueprint/pending setup without spending; otherwise clear squad selection; otherwise clear card selection. Cancellation never silently changes tactical intent.
- Planning begins during blueprint setup or knob dragging. Speed smoothly transitions toward 0.40x and the battlefield desaturates. Cards/command overlays remain colored. Success/cancellation restores speed/color; exit/restart resets time scale.
- The enemy-side **No-Hold Zone** fades in during planning with hatching and a boundary. A Defend circle must lie entirely outside it and inside the battlefield. Advance, combat, capture and scoring remain permitted there.
- Shield = Defend; arrow + shield = moving to Defend. Advance has no persistent intent icon. Defense circles flash on acceptance, fade afterward, and become clear when their squad is selected again. Failures float upward with a contextual icon/reason.
- Partial casualties preserve an active command. Destroyed squads leave selection; losing all selected soldiers ends planning with SQUAD_DESTROYED.
- Scroll or +/− zoom; middle-drag, WASD/arrows pan. Overview/Home shows the map; Deploy returns to your side; F11 toggles fullscreen. Camera motion is locked while drawing an order/editing the blueprint so gesture coordinates remain stable.
- F3/Debug exposes squad IDs, intents, shared orders, selection, defense data, gesture metrics/failures, planning speed/blend and reinforcement counts. Pan behind the home edge to inspect Queued/Entering soldiers. Restart/Play again starts a fresh battle.

## Economy, cards and combat

Both sides start at 3 Command, cap at 10 and regenerate 1/second. Five-card hands; one Unit plus up to two Modifiers. Resolution remains additions, multipliers, overrides, clamps and discrete rounding. Separate modifier copies can stack within the limit. Discarding costs no Command; exhausted decks reshuffle the discard pile.

| Card | Command | Output / effect |
| --- | ---: | --- |
| Rifle Squad | 3 | 6 infantry; 100 health, 45 damage / 0.75s (60 base DPS), 650 range, 300 speed |
| Assault Squad | 4 | 4 infantry; 225 health, 25.6 damage / 0.25s (4 base shots/s, 102.4 base DPS), 400 range, 420 speed |
| Conscript Wave | 2 | 12 infantry; 75 health, 27.5 damage / 1.10s (25 base DPS), 585 range, 250 speed |
| Commander Mojo | 3 | Infantry only; quantity ×2 (+100%) |
| Forced March | 2 | Infantry only; speed ×1.4, ranged/melee damage ×0.8 |
| Defensive Officer | 2 | Infantry only; health ×1.5, speed ×0.8 |

Soldiers roll attack interval ±6% and speed ±3% once using a dedicated seeded stream. Melee profiles are unchanged. Team markers supplement colored headgear: enemy triangles and friendly rings remain distinguishable in grayscale. Type symbols remain Rifle diamond, Assault lightning and Conscript three dots.

Enemy deployment waits for the first accepted player deployment; its economy regenerates during the wait. It uses the same intent-first squad deployment, entry queue and combat rules. Lane footprints are bot frontage preferences, not player restrictions. Its one-second seeded cycle prefers the weakest frontage 70% of the time.

Advance soldiers commit to capture 600 pixels before the opposing score line, stop acquiring targets and move at 1.20x speed while remaining vulnerable. Crossing the line scores once; scored soldiers exit/fade over 0.45 seconds. Victory defaults to 100 points. The No-Hold Zone prevents defensive spawn camping.

## Architecture and tuning

- scripts/systems/squad.gd: persistent squad identity, members and intent.
- scripts/systems/squad_commands.gd: selection, centroids, shared orders, defensive packing/validation and casualty reformation.
- scripts/systems/gesture_recognizer.gd: bounded screen-space line/loop recognition.
- scripts/systems/command_planning.gd: one shared real-time transition controller and world-only desaturation layer.
- scripts/ui/squad_command_ui.gd: functional blueprint, knob/input lifecycle and contextual command feedback.
- scripts/unit.gd: movement/combat states and bounded local steering, nearby-body lookup and rare budgeted recovery paths; no NavigationAgent.
- BattleTuning / data/battle_tuning.tres: economy, spacing, defense radii/spacing, No-Hold depth, planning speed, transition durations, desaturation/brightness, capture and enemy settings.
- data/cards/: card costs/stats/modifiers. No new dependency or persistent save-format migration is introduced.

Physics runs at 60 ticks/second. Camera/UI use the render clock; planning transitions use unscaled elapsed time. The desaturation pass sits between the world and card/command layers.

Old rectangle-validation helpers and legacy scenes remain for compatibility/regression coverage; they are not the live player command path. The optional old deployment-lock defeat toggle remains off by default. Full navigation around arbitrarily large mazes and final UI polish are outside this prototype; ordinary travel uses bounded headings; persistent stalls can request the incremental local recovery service described in [Pathing trials](PATHING_TRIALS.md).

## Verification and playtesting

From the repository root: pwsh -File tools/verify.ps1 -FreshImport. See the root [README](../README.md) for version pinning, executable paths, completion/error checks and logs.

The runner includes command acceptance; actual six-/24-unit and mixed-squad defensive movement/reformation; reinforcement occupancy/retry; historical formation geometry; combat/input/capture; camera; frame-rate clock comparison; and sustained battle scenarios. From PowerShell, run the focused checks with ./tools/verify.ps1 -Suite squad_command,squad_movement.

Rendered previews can be reproduced with the editor executable using --path . --rendering-method gl_compatibility --script tools/capture_command_preview.gd. PNGs/logs are written under ignored .test-results/.

Automated checks and scripted rendered captures are not a human playtest. Gesture fatigue, false rejection rates, planning feel, selection readability, defensive strength and congestion still need gameplay observation before UI polish or additional tactical intents.

## Performance and direct box editing update

Defenders normally use a fixed set of local steering probes. A single shared recovery service incrementally builds bounded local grids for persistent stalls, capped at 128 cells per physics tick with a 2 ms scan target. Threat candidates are shared by each defense order; collision probes inspect nearby spatial buckets updated on spawn, position changes and removal. Slot assignment preserves horizontal ordering to reduce crossing.

Blueprint geometry is edited exclusively through the box's corners/edges. Its preview scale and opposite anchor remain fixed during a gesture, so diagonal motion tracks the pointer. Width/depth limits clamp independently; releasing outside the panel still ends the captured resize. No sliders or scrollbars remain.

See [measured results and regression coverage](DEFENSE_PERFORMANCE_AND_BLUEPRINT.md). This intentionally trades global maze-solving for predictable, bounded local movement cost.
