#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$GodotPath = $env:GODOT_BIN,
    [ValidateRange(0, 3600)][int]$SecondsBudget = 0,
    [int]$Seed = 16102026
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
foreach ($argument in @('--headless', '--path', $projectRoot, '--fixed-fps', '60', '--', '--mirror-batch', "--budget=$SecondsBudget", "--seed=$Seed")) {
    $start.ArgumentList.Add($argument)
}
$process = [System.Diagnostics.Process]::new()
$process.StartInfo = $start
try {
    if (-not $process.Start()) { throw 'Could not launch mirror tests.' }
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    $output = $stdout.GetAwaiter().GetResult()
    $errors = $stderr.GetAwaiter().GetResult()
    Write-Output $output
    if ($errors) { Write-Output $errors }
    if ($process.ExitCode -ne 0 -or $errors -match '(SCRIPT ERROR:|ERROR:|FATAL:)') {
        throw "Mirror test runner failed (exit $($process.ExitCode))."
    }
} finally { $process.Dispose() }
