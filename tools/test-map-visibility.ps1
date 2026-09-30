param([string[]]$Maps = @('de_ancient','de_mirage','de_dust2','de_vertigo','de_inferno','de_nuke','de_train'))
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$tool = Join-Path $projectRoot 'parser/bin/cs2maptool.exe'
$cli = Join-Path $projectRoot 'parser/bin/map-tools/Source2Viewer-CLI.exe'
$gamePath = (& $tool discover | ConvertFrom-Json).path
if (-not $gamePath) { throw 'CS2 installation unavailable' }
$env:GOCACHE = Join-Path $projectRoot '.tools/go-cache'
foreach ($mapName in $Maps) {
    if ($mapName -notmatch '^de_[a-z0-9_]+$') { throw 'Invalid map name' }
    $folder = Join-Path $projectRoot "artifacts/m81/safety/$mapName"
    New-Item -ItemType Directory -Force $folder | Out-Null
    $source = & $tool probe-map $mapName $gamePath | ConvertFrom-Json
    if (-not $source.can_prepare -or -not $source.navigation_resource) { throw "Missing collision/navigation: $mapName" }
    if ($source.layout -ne 'map-vpk') {
        # resource names still come from the resolver; this audit requires a VPK.
        if ($source.layout -eq 'loose') { throw 'Use TACTICAL_SOURCE/NAV directly for loose assets' }
    }
    & $cli -i $source.source -f $source.physics_resource -o "$folder/collision.glb" -d --gltf_export_format glb > "$folder/extract.log" 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Collision extraction failed: $mapName" }
    & $cli -i $source.source -f $source.navigation_resource -o "$folder/source.nav" > "$folder/nav.log" 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Nav extraction failed: $mapName" }
    & $cli -i "$folder/source.nav" -o "$folder/navigation.glb" -d --gltf_export_format glb >> "$folder/nav.log" 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Nav conversion failed: $mapName" }
    $env:TACTICAL_SOURCE = "$folder/collision_physics.glb"
    $env:TACTICAL_NAV = "$folder/navigation.glb"
    $env:TACTICAL_TARGET = "$folder/map.glb"
    & go -C "$projectRoot/parser" test ./internal/tactical -run '^TestRealGeometry$' -count=1 -v > "$folder/test.log" 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Navigation support regression: $mapName; see $folder/test.log" }
    Write-Output "$mapName navigation safety PASS"
}
