param([string]$Godot)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $Godot) { $Godot = Join-Path $projectRoot '.tools/godot/Godot_v4.5.1-stable_win64_console.exe' }
$buildOutput = Join-Path $projectRoot 'dist/windows'
foreach ($requiredMapTool in @('Source2Viewer-CLI.exe','libSkiaSharp.dll','spirv-cross.dll','LICENSE.txt')) {
    if (-not (Test-Path -LiteralPath (Join-Path $projectRoot ('.tools/vrf/' + $requiredMapTool)))) { throw "Map preparation dependency missing: $requiredMapTool" }
}
New-Item -ItemType Directory -Force -Path $buildOutput | Out-Null
& go -C (Join-Path $projectRoot 'parser') build -trimpath -o bin/cs2parser.exe ./cmd/cs2parser
if ($LASTEXITCODE -ne 0) { throw 'Parser build failed.' }
& go -C (Join-Path $projectRoot 'parser') build -trimpath -o bin/cs2maptool.exe ./cmd/cs2maptool
if ($LASTEXITCODE -ne 0) { throw 'Map tool build failed.' }
& $Godot --headless --path (Join-Path $projectRoot 'app') --export-release 'Windows Desktop' (Join-Path $buildOutput 'CS2TacticalReplay.exe')
if ($LASTEXITCODE -ne 0) { throw 'Godot export failed. Install the 4.5.1 Windows templates into .tools/godot.' }
Copy-Item -LiteralPath (Join-Path $projectRoot 'parser/bin/cs2parser.exe') -Destination (Join-Path $buildOutput 'cs2parser.exe') -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'docs/windows-quick-start.txt') -Destination (Join-Path $buildOutput 'README.txt') -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'parser/bin/cs2maptool.exe') -Destination (Join-Path $buildOutput 'cs2maptool.exe') -Force
$mapToolsOutput = Join-Path $buildOutput 'map-tools'
New-Item -ItemType Directory -Force -Path $mapToolsOutput | Out-Null
foreach ($mapToolFile in @('Source2Viewer-CLI.exe','libSkiaSharp.dll','spirv-cross.dll','LICENSE.txt')) {
    Copy-Item -LiteralPath (Join-Path $projectRoot ('.tools/vrf/' + $mapToolFile)) -Destination $mapToolsOutput -Force
}
Write-Output "Built: $buildOutput"
