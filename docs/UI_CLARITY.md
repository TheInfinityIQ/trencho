# Prototype UI clarity pass — 18 October 2026

This pass preserves card costs, combat profiles, planning speed, gesture rules,
and resource commitment. It changes presentation and read-only order prediction.

## Package and selection

- The summary shows total package cost, available Command, shortfall, quantity,
  and card composition. An unmodified mixed squad no longer compares the first
  Unit's cost against the cost of both Units.
- Selected Unit cards show FRONT/REAR priority. Hover the package summary for
  each component's modified quantity, HP, theoretical per-soldier DPS, and native
  speed. Mixed squads retain their existing slowest-living-member travel rule.
  Tooltip content stays stable during resource regeneration.
- Selected forces show squad count and living selected soldiers. Queued selected
  reinforcements are counted separately. Hover the contextual strip for selected
  point established/inbound populations. These populations are not the same as
  selected membership: an entirely inbound squad remains excluded from point
  selection, while a partially established selected squad can contain arrivals.
- Hover a friendly point anchor for a selection cue. The existing anchor hit
  target and soldier/point selection priority are preserved; no area lasso or
  empty-territory selection is introduced.

## Orders and recovery

- While drawing, the strip predicts Advance, establish defense, or reinforcement
  from the same route interpretation and package/defense validators used by
  acceptance. In particular, a terminal loop is not labeled reinforcement merely
  because it ends inside existing friendly territory.
- Live validation is sampled at most every 0.1 real seconds. Release always
  revalidates against current state. Defensive-front placement validates the entire arriving block; an invalid
  footprint rejects reinforcement without spending. Prediction never issues an order or spends Command.
- Rejection reasons include a recovery action and remain in the contextual strip
  after the short floating cue disappears. Beginning a retry, changing selection,
  resizing, or cancelling removes obsolete failure feedback. Shared bot/system
  order signals cannot overwrite the player's persistent recovery message.
- Esc/right-click still backs out one interaction level. If Controls help is
  open, it closes first without changing selection or orders.

## Blueprint and HUD

- Blueprint shows cost/available Command, front/rear composition, required versus
  available spaces, and forward direction. Unit shapes supplement component
  colors in the preview.
- An invalid formation keeps its player-drawn dimensions. The continue button is
  unavailable with a visible reason; Enter still executes the same authoritative
  validation. Insufficient Command can be inspected while regeneration proceeds.
  Continuing to the order stage spends nothing.
- Player Command, score, incoming count, and secondary enemy Command have distinct
  stable positions. Command at cap receives a quiet FULL label. Incoming has a
  queued/entering tooltip.
- Camera controls remain in a compact row. Controls opens an in-game reference;
  its rectangle blocks battlefield input. The hand and camera layout retain their
  existing reserved regions. Long summary/instruction text is bounded, with full
  details available on hover rather than painting beyond the viewport.

## Verification and limitations

`ui_clarity` is included in the default verification runner. It exercises mixed
costs and modifiers, stable tooltips, visible selection errors, invalid blueprint
recovery, no-spend cancellation, persistent command errors, aggregate membership,
reinforcement/loop prediction, preview non-mutation, Controls cancellation, and
layout bounds at 960×700, 1280×800 and 1920×1080 under project canvas scaling.

Run `./tools/verify.ps1 -FreshImport` from PowerShell for all regression checks.
For focused checks, use `./tools/verify.ps1 -Suite ui_clarity,blueprint_drag,combat_input`.

`tools/capture_ui_clarity.gd` produces scripted rendered states in
`.test-results/ui-clarity-*.png`. Run it with the editor executable using
`--path . --rendering-method gl_compatibility --script tools/capture_ui_clarity.gd`.
These are synthetic presentation fixtures, not human gameplay observations.

Verification on the final code, Godot `4.7.2.stable.steam.ed1daf0bf`:

- Full clean-import regression runner passed, including 37 new UI assertions,
  startup, equal 30/144-FPS simulation snapshots, and the sustained battle check.
- Logs: `.test-results/20261018-120130-578/`.
- Eight rendered fixture captures completed without engine errors. Package,
  valid/invalid blueprint, recovery, point selection, and Controls states were
  inspected, including point selection at all three window sizes above.
- `git diff --check` passed. This verification describes the original UI pass; later system changes require fresh checks.

Readability and tactical attention still need a human session on the current
build. Suggested tasks: explain a mixed package, make and recover from an invalid
formation, predict Advance/Defend/Reinforce before releasing, then select and
release a dense Defensive Point. Observe wrong orders, missed feedback, and
whether the strip draws excessive attention. This pass does not repair movement
congestion or establish improved balance, enjoyment, or accessibility compliance.

## Light follow-up review — 18 October 2026

The defensive-front redesign now determines facing from the order and validates
the full formation footprint. Blueprint guidance and placement-recovery wording
have been updated to match. No additional controls, layouts, or mechanics were
added during this follow-up.

Focused follow-up verification passed on Godot 4.7.2: UI clarity (37),
defensive fronts (83), blueprint dragging (24), combat/input (29), and camera
(19) assertions, plus startup. Logs: .test-results/20261018-181404-239/.
