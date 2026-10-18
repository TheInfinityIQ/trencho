# Drawn command prototype v0.2

Implements the supplied consolidated handoff: mixed squads, route orders, Defensive Points with dynamic territory, reinforcement, friendly absorption, rout/Breakthrough and LINE/TRIANGLE enemy doctrines. Battlefield dimensions and existing card/combat profiles are preserved.

## Controls and rules

- Select up to three cards: one or two Units, zero to two compatible Modifiers. Two Units form one squad. Unit selection order gives front/rear priority; modifier order is immaterial.
- Click the battlefield or drag the selected package onto it to open the blueprint. Resize using its handles; the preview lists composition, total quantity and cost. Nothing is purchased yet.
- Confirm the formation, then drag the white knob. An open stroke follows a simplified route and resumes Advance. A complete terminal loop orders Defend; a stem/curved approach is retained. An open route ending inside a friendly active area reinforces that point. Passing through an area does not assign it.
- Clockwise/counter-clockwise loops work. Incomplete attempted loops fail safely, keep selection/setup and existing orders, spend nothing and restore normal simulation speed. Retry from the knob.
- Right-click/Escape backs out one interaction level. Selection alone never slows time. Planning retains the existing smooth slowdown and desaturation.
- Mixed squads travel at their slowest living member's speed. Native speed remains available for local combat repositioning within a moving squad leash. Route offsets retain formation/disorder rather than collapsing everyone into one waypoint.
- Active enemy territory intercepts travel and draws attackers into the defended position. Empty Pending points do not intercept.

## Defensive territory

The point dictionary in `squad_commands.orders` is the backend identity, not a circle. It records owner, anchors, squad IDs, established/inbound counts, lifecycle, desired/actual area, pressure, capacity, neighbors and recent damaging contributors. `defensive_points.gd` owns deterministic grid allocation. Radius remains a compatibility/debug bound, never the authoritative targeting boundary.

Only established living defenders purchase an area budget. The compact square footprint plus margin determines desired cells; connected, pressure-weighted allocation redistributes around map/No-Hold edges and stops at the budget. Each cell has one owner. A point with only inbound troops remains Pending with no active cells. No assigned or inbound survivors means deletion.

Territory is recomputed on a simulation-time interval. Reformation waits for local pressure to end. Home slots preserve corridors and rank order; active ownership clips home projections against other points. A Critical friendly point can be absorbed by a stronger contacting friendly point, transferring squads and retaining its anchors. Unresolvable environmental capacity failure returns squads to Advance. Opposing contact that makes a point Critical breaks it and routs survivors; pressure never uses a hypothetical bounding-circle overlap as a defeat trigger.

Reinforcement focus and ghost territory exist only during a live gesture. The projection respects legal cells and current neighboring ownership; insufficient projected capacity warns rather than vetoing the command.

## Rout and Breakthrough

Routed soldiers move home at 1.5× their squad's normal strategic Advance speed, never fire, take 1.25× damage and reject tactical commands. Once all surviving squad members reach the home deployment edge, the squad resumes Advance.

Damage contributions are recorded against the defender's point. On combat destruction or a contact-pressure break, each eligible surviving attacking squad receives a 10% maximum-health heal and an 8-second 1.15× damage buff. Unused healing proportion extends duration up to 16 seconds. Repeated awards heal normally and refresh duration within the cap; damage magnitude does not stack and speed never increases. Both sides use this service.

These are provisional starting values, exposed on BattleTuning along with grid size, area margin, update interval, cohesion and contribution window.

## Enemy

The existing first-player-deployment gate remains. Completed packages have a minimum one simulation-second cooldown. The simple affordable-package heuristic uses shared legality, atomic deployment, movement and order APIs.

At match initialization the seeded controller chooses LINE or TRIANGLE; BattleTuning can force either. New squads initially Advance and are considered for a defensive assignment only after reaching the configured depth. LINE fills outside positions at 25%/75% width to at least 10 each, then center to 10. TRIANGLE prioritizes its forward center to 20, then sides to 10 each. Inbound commitments reserve a deficit but do not inflate active territory. Excess squads Advance. Later deficits use newly available squads, not constant recalls of committed attackers.

## Old formation-box regression

The old hand handler still accepted unhandled battlefield presses while the command UI was waiting for a retry. A poor line followed by a press away from the knob could start the retired footprint drag. Live hand input no longer starts that path. Gesture begin/failure clears stale footprint state and preview nodes. Direct historical geometry helpers remain for regression coverage; they are not live player input.

`retired_box_test.gd` dispatches real mouse events after a poor line. It fails against the unchanged baseline at the retry-press assertion, and passes with the fix. It also checks no preview revival, no queue/resource change and safe planning exit.

## Verification and limits

Run `pwsh -File tools/verify.ps1 -FreshImport`. New suites cover gesture grammar, route movement, mixed composition, active/Pending lifecycle, unique legal cell ownership, capacity absorption, opposing break/rout, heal overflow, cooldown and doctrine thresholds. Existing 6/24/72-soldier movement, combat, capture, card-input, camera, frame-clock and sustained-battle checks remain enabled. Old direct geometry tests explicitly call the historical helper; new live-input tests ensure it cannot be activated by command retries.

The solver is coarse territory allocation, not fluid simulation. Boundary rendering is deliberately cell-based. Local steering is bounded; arbitrary maze navigation is not provided. If prototype terrain is changed at runtime, call `points.invalidate_terrain()` to invalidate its static terrain cache. Point-level pressure is implemented; local soldier-density fronts, final VFX and sophisticated AI flanking remain deferred.

Automated checks and scripted screenshots are not player playtests. Recognition comfort, strategic route value, visible territory communication, mixed Assault losses, capacity feedback and rout/Breakthrough cascades need observed sessions before balance changes or final UI work.
