param()
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$previousDataRoot = $env:CS2_REPLAY_DATA_ROOT
try {
    $env:CS2_REPLAY_DATA_ROOT = Join-Path $projectRoot 'artifacts/m71-session'
    $baseline = Join-Path $projectRoot 'artifacts/m71-original-mirage'
    if (-not (Test-Path -LiteralPath (Join-Path $baseline 'cache.json'))) { throw 'Missing original M7 cache baseline; preserve it before preparing the hotfix.' }
    $stale = Join-Path $projectRoot 'artifacts/m71-stale-cache/de_mirage'
    New-Item -ItemType Directory -Force -Path $stale | Out-Null
    foreach ($file in @('map.glb','map.json','cache.json')) { Copy-Item -LiteralPath (Join-Path $baseline $file) -Destination $stale -Force }
    $arguments = @('--script', ('"' + (Join-Path $projectRoot 'app/tests/milestone_7_1_tests.gd') + '"'), '--log-file', ('"' + (Join-Path $projectRoot 'artifacts/m71-export.log') + '"'), '--', '--project', ('"' + $projectRoot + '"'), '--phase', 'after')
    $run = Start-Process -FilePath (Join-Path $projectRoot 'dist/windows/CS2TacticalReplay.exe') -ArgumentList $arguments -PassThru -Wait -WindowStyle Normal
    exit $run.ExitCode
} finally { $env:CS2_REPLAY_DATA_ROOT = $previousDataRoot }
