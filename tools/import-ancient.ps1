param(
    [Parameter(Mandatory = $true)][string]$CS2Path,
    [string]$Python = 'python'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$mapVpk = Join-Path $CS2Path 'game/csgo/maps/de_ancient.vpk'
if (-not (Test-Path -LiteralPath $mapVpk)) { throw "Ancient map not found: $mapVpk. Supply -CS2Path." }
$cliDirectory = Join-Path $projectRoot '.tools/vrf'
$cli = Join-Path $cliDirectory 'Source2Viewer-CLI.exe'
if (-not (Test-Path -LiteralPath $cli)) {
    New-Item -ItemType Directory -Force $cliDirectory | Out-Null
    $zip = Join-Path $cliDirectory 'cli.zip'
    Invoke-WebRequest 'https://github.com/ValveResourceFormat/ValveResourceFormat/releases/download/20.0/cli-windows-x64.zip' -OutFile $zip
    Expand-Archive -LiteralPath $zip -DestinationPath $cliDirectory -Force
}
$exportDirectory = Join-Path $projectRoot '.tools/ancient-export'
New-Item -ItemType Directory -Force $exportDirectory | Out-Null
$exportFile = Join-Path $exportDirectory 'collision.glb'
& $cli -i $mapVpk -f maps/de_ancient/world_physics.vmdl_c -o $exportFile -d --gltf_export_format glb
if ($LASTEXITCODE -ne 0) { throw 'Source2Viewer export failed.' }
$packages = Join-Path $projectRoot '.tools/pythonpkgs'
& $Python -m pip install --target $packages 'numpy>=1.26,<3'
if ($LASTEXITCODE -ne 0) { throw 'Python dependency install failed.' }
$outputFile = Join-Path $projectRoot 'app/maps/de_ancient/map.glb'
& $Python (Join-Path $PSScriptRoot 'build-tactical-map.py') (Join-Path $exportDirectory 'collision_physics.glb') $outputFile
if ($LASTEXITCODE -ne 0) { throw 'Tactical map conversion failed.' }
@{ source_vpk = $mapVpk; source_sha256 = (Get-FileHash -LiteralPath $mapVpk).Hash; viewer_version = '20.0'; generated = (Get-Date).ToString('o'); note = 'Local Valve asset. Do not redistribute or commit map.glb.' } | ConvertTo-Json | Set-Content (Join-Path $projectRoot 'app/maps/de_ancient/source.json')
Write-Host "Tactical map ready: $outputFile"
