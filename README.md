# Trencho

Single-player PC mechanics prototype combining card deployments with autonomous battlefield combat. The current goal is to validate the battle loop before expanding campaign or progression systems.

## Open and play

Use **Godot 4.7.2 stable**, standard edition (no .NET dependency). The verification version is recorded in `.godot-version`. Steam's `stable-4.7` branch can receive patch updates; update the version file only after running compatibility checks with the new patch.

The current interaction is a three-card package (one or two Units) → squad blueprint → a curved route, full Defend loop or route ending on a friendly Defensive Point shield from one order knob. See [v0.2 controls and systems](docs/DRAWN_COMMAND_V02_IMPLEMENTATION.md). Click soldiers to select whole squads; Shift modifies multi-selection.

Import `project.godot` in Godot and run `main.tscn`. See [prototype controls, rules and tuning](docs/PROTOTYPE.md).

## Verify

Install PowerShell 7 (`pwsh`). From the repository root:

```powershell
pwsh -File tools/verify.ps1 -FreshImport
```

On Windows the runner detects the usual Steam editor location. For another installation, pass the **editor executable** explicitly (not an export template), or set `GODOT_BIN`:

```powershell
pwsh -File tools/verify.ps1 -GodotPath '/path/to/godot' -FreshImport
./tools/verify.ps1 -Suite reinforcement_flow,simulation_clock
```

For selecting several suites from a shell other than PowerShell, invoke the script inside a PowerShell session so the suite list is passed as an array.

The runner checks the exact stable engine version, imports resources, runs the selected suites, and starts the main scene headlessly. Nonzero exits, engine/script errors, timeouts and missing suite completion markers fail verification. The simulation-clock suite runs at 30 and 144 render FPS and compares snapshots over equal physics ticks. Battle rules run at 60 physics ticks per second; camera and UI updates remain on the render clock.

`-FreshImport` verifies a copy of current Git-visible files without copying `.godot`; it includes uncommitted source edits. Logs and the temporary source copy are retained under ignored `.test-results/`. GitHub Actions runs the same command on a fresh Windows checkout. CI does not publish or release the game.

## Structure

- `scripts/systems/`: shared deployment, formation, economy and enemy rules.
- `scripts/unit.gd`: movement, targeting, combat, entry and capture states.
- `scripts/cards/` and `scripts/ui/`: hand input and battle feedback.
- `data/`: tunable card and battle resources.
- `tests/`: executable Godot regression scenarios.
- `docs/`: design history and current prototype instructions. Historical design documents may describe superseded behavior; inspect the implementation and `PROTOTYPE.md` together.

Legacy scenes/scripts remain until their references can be retired in a separate focused change. Engine recovery files (`*.tmp`), imported caches and local verification results are excluded from Git.

Automated checks verify covered behavior. Visual readability, congestion, balance and enjoyment still require a comparable gameplay test before changing combat stats or card costs.

## Consolidation build

The current version is **0.5.2-consolidation**. Defend faces the enemy automatically;
Reinforce requires ending on a friendly shield. The approach chooses a broad sector.
Every legal package starts with a usable blueprint; manual editing remains optional.
See [implementation and evidence](docs/CONSOLIDATION_IDENTITY.md).

With the matching Godot Windows export templates installed:

```powershell
./tools/build_windows.ps1
```

This creates an ordinary playable EXE/PCK and ZIP under
`.test-results/builds/Trencho-0.5.2-consolidation/`, plus a source/artifact manifest.
Open `Trencho.exe` and choose **Play**. Developer profiling and tests are optional.
