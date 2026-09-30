param()
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$previousDataRoot = $env:CS2_REPLAY_DATA_ROOT
try {
    $env:CS2_REPLAY_DATA_ROOT = Join-Path $projectRoot ('artifacts/m7-acceptance-' + [guid]::NewGuid().ToString('N'))
    $arguments = @('--script', ('"' + (Join-Path $projectRoot 'app/tests/milestone_7_tests.gd') + '"'), '--log-file', ('"' + (Join-Path $projectRoot 'artifacts/m7-export.log') + '"'), '--', '--project', ('"' + $projectRoot + '"'))
    # This is the visible application under visual acceptance, not a background helper.
    $run = Start-Process -FilePath (Join-Path $projectRoot 'dist/windows/CS2TacticalReplay.exe') -ArgumentList $arguments -PassThru -Wait -WindowStyle Normal
    exit $run.ExitCode
} finally {
    $env:CS2_REPLAY_DATA_ROOT = $previousDataRoot
}
