param([Parameter(Mandatory = $true)][string]$DustDemo)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
$previous=$env:CS2_REPLAY_DATA_ROOT
try {
    $env:CS2_REPLAY_DATA_ROOT=Join-Path $projectRoot ('artifacts/m8-acceptance-'+[guid]::NewGuid().ToString('N'))
    $arguments=@('--script',('"'+(Join-Path $projectRoot 'app/tests/milestone_8_tests.gd')+'"'),'--log-file',('"'+(Join-Path $projectRoot 'artifacts/m8-export.log')+'"'),'--','--project',('"'+$projectRoot+'"'),'--dust',('"'+$DustDemo+'"'))
    $run=Start-Process -FilePath (Join-Path $projectRoot 'dist/windows/CS2TacticalReplay.exe') -ArgumentList $arguments -PassThru -Wait -WindowStyle Normal
    exit $run.ExitCode
} finally {$env:CS2_REPLAY_DATA_ROOT=$previous}
