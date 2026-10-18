#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$GodotPath = $env:GODOT_BIN,
    [ValidateSet('ai_flow', 'mirror_mode', 'next_pass', 'defensive_combat', 'combat_telemetry', 'territory_performance', 'drawn_command_v02', 'retired_box', 'defense_scale', 'blueprint_drag', 'squad_command', 'squad_movement', 'reinforcement_flow', 'formation', 'combat_input', 'combat_readability_capture', 'camera', 'simulation_clock', 'battle_soak')]
    [string[]]$Suite = @('ai_flow', 'mirror_mode', 'next_pass', 'defensive_combat', 'combat_telemetry', 'territory_performance', 'drawn_command_v02', 'retired_box', 'defense_scale', 'blueprint_drag', 'squad_command', 'squad_movement', 'reinforcement_flow', 'formation', 'combat_input', 'combat_readability_capture', 'camera', 'simulation_clock', 'battle_soak'),
    [switch]$FreshImport,
    [ValidateRange(1, 600)][int]$TimeoutSeconds = 300
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$requiredVersion = (Get-Content -LiteralPath (Join-Path $projectRoot '.godot-version') -Raw).Trim()
if (-not $GodotPath) {
    if ($IsWindows) {
        $steamEditor = Join-Path ${env:ProgramFiles(x86)} 'Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'
        if (Test-Path -LiteralPath $steamEditor) { $GodotPath = $steamEditor }
    }
    if (-not $GodotPath) {
        $found = Get-Command godot -ErrorAction SilentlyContinue
        if ($found) { $GodotPath = $found.Source }
    }
}
if (-not $GodotPath) { throw 'Supply -GodotPath or set GODOT_BIN to a Godot editor executable.' }
$GodotPath = (Get-Command $GodotPath -ErrorAction Stop).Source
$runRoot = Join-Path $projectRoot ('.test-results/' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
$testRoot = $projectRoot

function Invoke-GodotCheck {
    param([string]$Name, [string[]]$EngineArguments, [string]$SuccessPattern = '')
    $logPath = Join-Path $runRoot ($Name + '.log')
    $start = [System.Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $GodotPath
    $start.WorkingDirectory = $testRoot
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in $EngineArguments) { $start.ArgumentList.Add($argument) }
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $start
    try {
        if (-not $process.Start()) { throw "Could not start $Name" }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
        if ($timedOut) { $process.Kill($true); $process.WaitForExit() }
        $output = $stdoutTask.GetAwaiter().GetResult() + $stderrTask.GetAwaiter().GetResult()
        [System.IO.File]::WriteAllText($logPath, $output)
        if ($timedOut) { throw "$Name exceeded ${TimeoutSeconds}s. See $logPath" }
        if ($process.ExitCode -ne 0 -or $output -match '(?m)^\s*(SCRIPT ERROR:|ERROR:|FATAL:|USER ERROR:|Parse Error:)') {
            Write-Host $output
            throw "$Name failed (exit $($process.ExitCode)). See $logPath"
        }
        if ($SuccessPattern -and $output -notmatch $SuccessPattern) {
            throw "$Name exited without its completion marker; it is not a pass. See $logPath"
        }
        Write-Host "$Name passed"
        return $output
    } finally { $process.Dispose() }
}

try {
    $versionOutput = Invoke-GodotCheck -Name 'version' -EngineArguments @('--headless', '--version')
    if ($versionOutput.Trim() -notmatch ('^' + [regex]::Escape($requiredVersion) + '\.stable\.')) {
        throw "Expected Godot $requiredVersion stable; received $($versionOutput.Trim()). Update .godot-version and CI together after compatibility checks."
    }
    Write-Host "Engine: $($versionOutput.Trim())"
    if ($FreshImport) {
        # Copy current Git-visible files, including edits, without the existing import cache.
        $paths = @(& git -C $projectRoot -c core.quotepath=false ls-files --cached --others --exclude-standard)
        if ($LASTEXITCODE -ne 0) { throw 'Could not enumerate project files for a fresh import.' }
        $testRoot = Join-Path $runRoot 'source'
        New-Item -ItemType Directory -Path $testRoot | Out-Null
        foreach ($relativePath in $paths) {
            $source = Join-Path $projectRoot $relativePath
            if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { continue }
            $destination = [System.IO.Path]::GetFullPath((Join-Path $testRoot $relativePath))
            if (-not $destination.StartsWith($testRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::Ordinal)) {
                throw "File outside fresh-import directory: $relativePath"
            }
            New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
            Copy-Item -LiteralPath $source -Destination $destination
        }
        Write-Host "Fresh import copy: $testRoot"
    }
    $null = Invoke-GodotCheck -Name 'import' -EngineArguments @('--headless', '--path', $testRoot, '--import')
    $markers = @{
        ai_flow = 'AI FLOW: \d+ assertions, PASSED'
        mirror_mode = 'MIRROR MODE: \d+ assertions, PASSED'
        next_pass = 'NEXT PASS: \d+ assertions, PASSED'
        defensive_combat = 'DEFENSIVE COMBAT: \d+ assertions, PASSED'
        combat_telemetry = 'COMBAT TELEMETRY: \d+ assertions, PASSED'
        territory_performance = 'TERRITORY PERFORMANCE: \d+ assertions, PASSED'
        drawn_command_v02 = 'DRAWN COMMAND V02: \d+ assertions, PASSED'
        retired_box = 'RETIRED BOX: \d+ assertions, PASSED'
        defense_scale = 'DEFENSE SCALE: \d+ assertions, PASSED'
        blueprint_drag = 'BLUEPRINT DRAG: \d+ assertions, PASSED'
        squad_movement = 'SQUAD MOVEMENT: \d+ assertions, PASSED'
        squad_command = 'SQUAD COMMANDS: \d+ assertions, PASSED'
        reinforcement_flow = 'REINFORCEMENT FLOW: \d+ assertions, PASSED'
        formation = 'FORMATION CHECKS PASSED: \d+ assertions'
        combat_input = 'COMBAT / INPUT CHECKS: \d+ assertions, PASSED'
        combat_readability_capture = 'COMBAT READABILITY CAPTURE: \d+ assertions, PASSED'
        camera = 'CAMERA CHECKS PASSED: \d+ assertions'
        simulation_clock = 'SIMULATION CLOCK: \d+ assertions, PASSED'
        battle_soak = 'BATTLE SOAK: deployments='
    }
    $clockSnapshots = @()
    foreach ($suiteName in $Suite) {
        $frameRates = if ($suiteName -eq 'simulation_clock') { @(30, 144) } else { @(60) }
        foreach ($frameRate in $frameRates) {
            $name = if ($suiteName -eq 'simulation_clock') { "$suiteName-$frameRate" } else { $suiteName }
            $output = Invoke-GodotCheck -Name $name -EngineArguments @('--headless', '--path', $testRoot, '--fixed-fps', "$frameRate", '--script', "tests/${suiteName}_test.gd", '--quit-after', '12000') -SuccessPattern $markers[$suiteName]
            Write-Host (($output -split '\r?\n' | Where-Object { $_ -match $markers[$suiteName] }) -join "`n")
            if ($suiteName -eq 'simulation_clock') {
                $snapshot = [regex]::Match($output, '(?m)^CLOCK SNAPSHOT: (.+)\r?$')
                if (-not $snapshot.Success) { throw 'Missing clock comparison snapshot.' }
                $clockSnapshots += $snapshot.Groups[1].Value.Trim()
            }
        }
    }
    if ($clockSnapshots.Count -eq 2 -and $clockSnapshots[0] -cne $clockSnapshots[1]) {
        throw 'Simulation results differ between 30 and 144 render FPS. Inspect the clock logs.'
    }
    if ($clockSnapshots.Count -eq 2) { Write-Host '30/144 FPS simulation snapshots match' }
    $null = Invoke-GodotCheck -Name 'startup-smoke' -EngineArguments @('--headless', '--path', $testRoot, '--fixed-fps', '60', '--quit-after', '120')
    Write-Host "VERIFICATION PASSED. Logs: $runRoot"
    exit 0
} catch {
    Write-Error -Message $_ -ErrorAction Continue
    Write-Host "VERIFICATION FAILED. Logs: $runRoot"
    exit 1
}
