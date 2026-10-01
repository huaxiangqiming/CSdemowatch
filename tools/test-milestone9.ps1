param([string]$Demo, [switch]$Visual)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $Demo) { $Demo = Join-Path $projectRoot 'test_data/s2/s2.dem' }
if (-not (Test-Path -LiteralPath $Demo)) { throw 'Supply -Demo with a local CS2 demo; test demos are not distributed.' }
$godot = Join-Path $projectRoot '.tools/godot/Godot_v4.5.1-stable_win64_console.exe'
$parser = Join-Path $projectRoot 'parser/bin/cs2parser.exe'
$output = Join-Path $projectRoot 'artifacts/m9'
New-Item -ItemType Directory -Force $output | Out-Null
& go -C "$projectRoot/parser" test ./...
if ($LASTEXITCODE -ne 0) { throw 'Go tests failed' }
& go -C "$projectRoot/parser" build -o bin/cs2parser.exe ./cmd/cs2parser
if ($LASTEXITCODE -ne 0) { throw 'Parser build failed' }
foreach ($format in @('json','replay')) {
    & $parser $Demo "$output/ancient.$format" > "$output/parse-$format.log" 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Cannot create $format fixture" }
}
foreach ($script in @('milestone_9_tests','milestone_9_corruption_tests','milestone_9_prefetch_tests')) {
    $testOutput = & $godot --headless --path "$projectRoot/app" --script "res://tests/$script.gd" 2>&1
    $testExit = $LASTEXITCODE
    $testOutput | Tee-Object -FilePath "$output/$script.log" | Write-Output
    if ($testExit -ne 0 -or ($testOutput -match 'SCRIPT ERROR:|^ERROR:')) { throw "$script failed" }
}
foreach ($format in @('json','replay')) {
    & $godot --headless --path "$projectRoot/app" --script res://tests/milestone_9_benchmark.gd -- "$output/ancient.$format" "$output/benchmark-$format.json"
    if ($LASTEXITCODE -ne 0) { throw "$format benchmark failed" }
}
if ($Visual) {
    & $godot --path "$projectRoot/app" --script res://tests/milestone_9_scene_tests.gd
    if ($LASTEXITCODE -ne 0) { throw 'Scene acceptance failed' }
}
