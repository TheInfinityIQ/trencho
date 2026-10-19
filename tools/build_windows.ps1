#requires -Version 7.0
[CmdletBinding()]
param([string]$GodotPath = $env:GODOT_BIN)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$requiredVersion = (Get-Content (Join-Path $projectRoot '.godot-version') -Raw).Trim()
$config = Get-Content (Join-Path $projectRoot 'project.godot') -Raw
$buildVersion = [regex]::Match($config, '(?m)^config/version="([^"]+)"').Groups[1].Value
if ($buildVersion -notmatch '^[0-9A-Za-z.-]+$') { throw 'Missing or unsafe application version.' }
if (-not $GodotPath) {
    $steamEditor = Join-Path ${env:ProgramFiles(x86)} 'Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'
    if (Test-Path -LiteralPath $steamEditor) { $GodotPath = $steamEditor }
    else { $GodotPath = (Get-Command godot -ErrorAction Stop).Source }
}
$buildRoot = Join-Path $projectRoot '.test-results/builds'
$buildFolder = Join-Path $buildRoot "Trencho-$buildVersion"
New-Item -ItemType Directory -Path $buildFolder -Force | Out-Null
function Invoke-Engine {
    param([string]$Name, [string[]]$EngineArguments, [string]$BinaryPath = $GodotPath)
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $BinaryPath
    $start.WorkingDirectory = $projectRoot
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in $EngineArguments) { $start.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    try {
        if (-not $process.Start()) { throw "Could not start $Name" }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(300000)) { $process.Kill($true); throw "$Name timed out" }
        $output = $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult()
        [IO.File]::WriteAllText((Join-Path $buildRoot "$Name.log"),$output)
        if ($process.ExitCode -ne 0 -or $output -match '(?m)^\s*(SCRIPT ERROR:|ERROR:|FATAL:|Parse Error:)') {
            throw "$Name failed. See $(Join-Path $buildRoot "$Name.log")"
        }
        return $output.Trim()
    } finally { $process.Dispose() }
}
$engineVersion = Invoke-Engine 'engine-version' @('--headless','--version')
if ($engineVersion -notmatch ('^'+[regex]::Escape($requiredVersion)+'\.stable\.')) { throw "Expected Godot $requiredVersion stable; got $engineVersion" }
$executable = Join-Path $buildFolder 'Trencho.exe'
$null = Invoke-Engine 'windows-export' @('--headless','--path',$projectRoot,'--export-release','Windows Desktop',$executable)
if (-not (Test-Path -LiteralPath $executable) -or -not (Test-Path -LiteralPath (Join-Path $buildFolder 'Trencho.pck'))) { throw 'Export did not produce the EXE and PCK.' }
$smokeOutput = Invoke-Engine -Name 'export-play-smoke' -BinaryPath $executable -EngineArguments @('--headless','--fixed-fps','60','--quit-after','1200','--','--build-smoke')
if ($smokeOutput -notmatch 'EXPORTED PLAY SMOKE: \d+ checks, PASSED') { throw 'Exported Play smoke exited without completing.' }
Write-Host ($smokeOutput -split "`r?`n" | Where-Object { $_ -match 'EXPORTED PLAY SMOKE:' })
$commit = (& git -C $projectRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Could not read source commit.' }
$tree = (& git -C $projectRoot rev-parse 'HEAD^{tree}').Trim()
$dirty = @(& git -C $projectRoot status --porcelain)
$artifactHashes = @{}
foreach ($name in @('Trencho.exe','Trencho.pck')) { $artifactHashes[$name] = (Get-FileHash -LiteralPath (Join-Path $buildFolder $name) -Algorithm SHA256).Hash.ToLowerInvariant() }
$manifest = [ordered]@{ version=$buildVersion; engine=$engineVersion; platform='Windows x86_64'; source_commit=$commit; source_tree=$tree; source_dirty=($dirty.Count -gt 0); uncommitted_files=$dirty; built_utc=[DateTime]::UtcNow.ToString('o'); artifacts_sha256=$artifactHashes }
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $buildFolder 'build-manifest.json') -Encoding utf8
@"
Trencho $buildVersion

Open Trencho.exe and choose Play. Keep Trencho.pck next to the executable.
Choose a Unit card (optional other Unit and/or Modifier cards), accept the
suggested blueprint, and draw an order from the squad knob. A terminal loop
creates a defense facing the enemy. An open route advances, unless its endpoint
lands on a friendly shield: then it reinforces. Approach from the left/right to
prefer that part of the front. The preview shows FRONTAGE or RESERVE.

Click a soldier to select its squad; Shift modifies selection. Shield selects
an established position. Mouse wheel zooms, WASD/arrows pan, Home shows overview,
F11 toggles fullscreen. Normal play needs no developer controls.

Combat logs are saved automatically when a battle finishes, under:
%APPDATA%\Godot\app_userdata\Trencho\combat_logs
Build/source identity is recorded in build-manifest.json.
"@ | Set-Content -LiteralPath (Join-Path $buildFolder 'READ-ME.txt') -Encoding utf8
$zipPath = Join-Path $buildRoot "Trencho-$buildVersion.zip"
Compress-Archive -Path (Join-Path $buildFolder '*') -DestinationPath $zipPath -Force
Write-Host "WINDOWS BUILD COMPLETE: $executable"
Write-Host "ZIP: $zipPath"
Write-Host "Source: $commit (dirty=$($dirty.Count -gt 0))"
