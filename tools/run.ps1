param([switch]$Editor, [switch]$Test, [switch]$VisualTest, [string]$Replay, [switch]$RealTest, [switch]$MapTest, [switch]$CombatTest, [switch]$Milestone5, [switch]$Milestone6, [switch]$FullRound)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$localGodot = Join-Path $projectRoot '.tools/godot/Godot_v4.5.1-stable_win64_console.exe'
$enginePath = $localGodot
if (-not (Test-Path -LiteralPath $enginePath)) {
    $engineCommand = Get-Command godot, godot4 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $engineCommand) {
        throw 'Godot is missing. Put Godot 4.5.1 Standard in .tools/godot or add godot to PATH. See README.md.'
    }
    $enginePath = $engineCommand.Source
}
$appPath = Join-Path $projectRoot 'app'
$artifactPath = Join-Path $projectRoot 'artifacts'
New-Item -ItemType Directory -Path $artifactPath -Force | Out-Null
$engineArgs = @('--path', $appPath)
if ($Editor) { $engineArgs += '--editor' }
if ($Test -or $VisualTest -or $RealTest -or $MapTest -or $CombatTest -or $Milestone5 -or $Milestone6) {
    if (-not $VisualTest) { $engineArgs += '--headless' }
    $testScript = if ($Milestone6) { 'res://tests/milestone_6_tests.gd' } elseif ($Milestone5) { 'res://tests/milestone_5_tests.gd' } elseif ($CombatTest) { 'res://tests/milestone_4_tests.gd' } elseif ($MapTest) { 'res://tests/milestone_3_tests.gd' } elseif ($RealTest) { 'res://tests/real_replay_tests.gd' } else { 'res://tests/run_tests.gd' }
    $testLog = if ($Milestone6) { 'm6-tests.log' } elseif ($Milestone5) { 'milestone-5-tests.log' } elseif ($CombatTest) { 'milestone-4-tests.log' } elseif ($MapTest) { 'milestone-3-tests.log' } elseif ($RealTest) { 'real-tests.log' } else { 'tests.log' }
    $engineArgs += @('--script', $testScript, '--log-file', (Join-Path $artifactPath $testLog))
} else {
    $engineArgs += @('--log-file', (Join-Path $artifactPath 'viewer.log'))
}
$userArgs = @()
if ($Milestone6) { $env:CS2_REPLAY_DATA_ROOT = Join-Path $artifactPath ('m6-acceptance-' + [guid]::NewGuid().ToString('N')) }
if ($VisualTest) { $userArgs += '--visual' }
if ($FullRound) {
    if (-not (($CombatTest -or $Milestone5) -and $VisualTest)) { throw '-FullRound requires -CombatTest or -Milestone5, plus -VisualTest.' }
    $userArgs += '--full-round'
}
if ($Replay) {
    $resolvedReplay = (Resolve-Path -LiteralPath $Replay).Path
    $userArgs += @('--replay', $resolvedReplay)
}
if ($userArgs.Count -gt 0) { $engineArgs += '--'; $engineArgs += $userArgs }
& $enginePath @engineArgs
exit $LASTEXITCODE
