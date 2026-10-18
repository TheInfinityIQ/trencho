#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$GodotPath = $env:GODOT_BIN,
    [int]$Seed = 16102026,
    [ValidateRange(1,20)][int]$Repetitions = 3,
    [ValidateSet('', 'open_advance', 'queued_direct', 'queued_route_loop', 'stationary_rank', 'whole_point_release', 'whole_point_relocate', 'reinforce', 'crossing_orders', 'mid_entry_reorder', 'edge_route', 'terrain_detour', 'mass_route', 'sealed_destination')]
    [string]$Case = ''
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
if (-not $GodotPath) {
    $steamEditor = Join-Path ${env:ProgramFiles(x86)} 'Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'
    if (Test-Path -LiteralPath $steamEditor) { $GodotPath = $steamEditor }
    else { $GodotPath = (Get-Command godot -ErrorAction Stop).Source }
}
$start = [System.Diagnostics.ProcessStartInfo]::new()
$start.FileName = $GodotPath
$start.WorkingDirectory = $projectRoot
$start.UseShellExecute = $false
$start.CreateNoWindow = $true
$start.RedirectStandardOutput = $true
$start.RedirectStandardError = $true
foreach ($argument in @('--headless', '--path', $projectRoot, '--fixed-fps', '60', '--script', 'tests/pathing_trials_test.gd', '--', "--seed=$Seed", "--repetitions=$Repetitions")) {
    $start.ArgumentList.Add($argument)
}
if ($Case) { $start.ArgumentList.Add("--case=$Case") }
$process = [System.Diagnostics.Process]::new()
$process.StartInfo = $start
try {
    if (-not $process.Start()) { throw 'Could not launch pathing trials.' }
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    $output = $stdout.GetAwaiter().GetResult()
    $errors = $stderr.GetAwaiter().GetResult()
    Write-Output $output
    if ($errors) { Write-Output $errors }
    if ($process.ExitCode -ne 0 -or $errors -match '(SCRIPT ERROR:|ERROR:|FATAL:)' -or $output -notmatch 'PATHING TRIALS: \d+ trials, PASSED') {
        throw "Pathing trials failed (exit $($process.ExitCode))."
    }
} finally { $process.Dispose() }
