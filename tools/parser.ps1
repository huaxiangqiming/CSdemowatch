param([switch]$Test, [string]$Demo, [string]$Output, [switch]$V1, [string]$DamageDemo)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$parserPath = Join-Path $projectRoot 'parser'
$demoPath = if ($Demo) { (Resolve-Path -LiteralPath $Demo).Path } else { $null }
if ($Test) {
    if ($DamageDemo) { $env:CS2_DAMAGE_DEMO = (Resolve-Path -LiteralPath $DamageDemo).Path }
    if ($demoPath) { $env:CS2_TEST_DEMO = $demoPath }
    & go -C $parserPath test -v ./...
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & go -C $parserPath vet ./...
    exit $LASTEXITCODE
}
& go -C $parserPath build -trimpath -o bin/cs2parser.exe ./cmd/cs2parser
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
if ($Demo) {
    if (-not $Output) { throw 'Specify -Output with -Demo.' }
    $parserArgs = @($demoPath, $Output)
    if ($V1) { $parserArgs = @('--v1') + $parserArgs }
    & (Join-Path $parserPath 'bin/cs2parser.exe') @parserArgs
    exit $LASTEXITCODE
}
