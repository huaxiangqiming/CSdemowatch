param(
    [string]$Godot, [string]$ISCC, [switch]$SkipBuild,
    [switch]$RequireSignature, [switch]$AllowUnsignedPreview, [string]$CertificateThumbprint, [string]$SignTool,
    [ValidateSet('CurrentUser','LocalMachine')][string]$CertificateStore='CurrentUser',
    [string]$TimestampServer='http://timestamp.digicert.com'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $Godot) { $Godot = Join-Path $projectRoot '.tools/godot/Godot_v4.5.1-stable_win64_console.exe' }
if (-not $ISCC) { $ISCC = Join-Path $projectRoot '.tools/inno/compiler/ISCC.exe' }
if (-not (Test-Path -LiteralPath $ISCC)) { throw 'Install Inno Setup 7 and pass -ISCC with the compiler path.' }
$versionSource = Get-Content -LiteralPath (Join-Path $projectRoot 'app/scripts/application/AppInfo.gd') -Raw
$version = [regex]::Match($versionSource, 'const VERSION := "([0-9A-Za-z.-]+)"').Groups[1].Value
if (-not $version) { throw 'Missing application version.' }
if ($AllowUnsignedPreview -and ($RequireSignature -or $CertificateThumbprint)) { throw 'Unsigned preview and signing options cannot be combined.' }
$signing = -not $AllowUnsignedPreview
$artifactSuffix = if ($AllowUnsignedPreview) { '-unsigned-preview' } else { '' }
$signer = Join-Path $PSScriptRoot 'sign_windows_file.ps1'
$signOptions = @{ CertificateThumbprint=$CertificateThumbprint; SignTool=$SignTool; CertificateStore=$CertificateStore; TimestampServer=$TimestampServer }
if ($signing) { & $signer @signOptions -ValidateOnly }
# Validate all signing prerequisites before replacing any build or release artifact.
if (-not $SkipBuild) { & (Join-Path $PSScriptRoot 'build_windows.ps1') -Godot $Godot }
$packageRoot = Join-Path $projectRoot 'dist/windows'
$releaseDir = Join-Path $projectRoot $(if ($AllowUnsignedPreview) { 'dist/previews/' + $version } else { 'dist/releases' })
$licenses = Join-Path $packageRoot 'licenses'
New-Item -ItemType Directory -Force $releaseDir,$licenses | Out-Null
& $Godot --headless --path (Join-Path $projectRoot 'app') --script (Join-Path $PSScriptRoot 'export-engine-notices.gd') -- (Join-Path $licenses 'Godot-and-third-party.txt')
if ($LASTEXITCODE -ne 0) { throw 'Engine notice export failed.' }
$modules = & go -C (Join-Path $projectRoot 'parser') list -deps -f '{{if .Module}}{{.Module.Path}}|{{.Module.Dir}}{{end}}' ./cmd/cs2parser ./cmd/cs2maptool
if ($LASTEXITCODE -ne 0) { throw 'Go module listing failed.' }
foreach ($module in ($modules | Where-Object { $_ } | Sort-Object -Unique)) {
    $parts = $module -split '\|',2
    if ($parts[0] -eq 'csdemowatch/parser') { continue }
    if (-not $parts[1]) { throw "Module source unavailable: $($parts[0])" }
    $destination = Join-Path $licenses ($parts[0] -replace '[/\\]','_')
    New-Item -ItemType Directory -Force $destination | Out-Null
    $notices = Get-ChildItem -LiteralPath $parts[1] -File | Where-Object { $_.Name -match '^(LICENSE|COPYING|NOTICE|AUTHORS)' }
    if (-not $notices) { throw "Missing module license: $($parts[0])" }
    $notices | Copy-Item -Destination $destination -Force
}
$goRoot = & go env GOROOT
Copy-Item -LiteralPath (Join-Path $goRoot 'LICENSE') -Destination (Join-Path $licenses 'Go-LICENSE.txt') -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'docs/third-party-notices.txt') -Destination $packageRoot -Force
$mapNotices = Join-Path $licenses 'map-tools'
New-Item -ItemType Directory -Force $mapNotices | Out-Null
Copy-Item -LiteralPath (Join-Path $projectRoot 'docs/licenses/Source2Viewer-THIRD-PARTY.txt') -Destination $mapNotices -Force
if ($AllowUnsignedPreview) {
    'UNSIGNED LOCAL PREVIEW: publisher identity has not been verified. Do not describe this build as signed.' | Set-Content -LiteralPath (Join-Path $packageRoot 'SIGNING-STATUS.txt') -Encoding utf8
} else {
    'Timestamped signing is required for this package. Check Authenticode signatures to verify publisher identity.' | Set-Content -LiteralPath (Join-Path $packageRoot 'SIGNING-STATUS.txt') -Encoding utf8
}
# Copy only the validated application bundle; no demos, source assets or local caches.
$required = @('CS2TacticalReplay.exe','CS2TacticalReplay.pck','cs2parser.exe','cs2maptool.exe','README.txt','map-tools/Source2Viewer-CLI.exe','map-tools/libSkiaSharp.dll','map-tools/spirv-cross.dll','map-tools/LICENSE.txt','licenses/Godot-and-third-party.txt')
foreach ($name in $required) { if (-not (Test-Path -LiteralPath (Join-Path $packageRoot $name))) { throw "Missing runtime file: $name" } }
$unexpected = Get-ChildItem -LiteralPath $packageRoot -Recurse -File | Where-Object { $_.Extension -in @('.dem','.glb','.vpk','.replay','.log') }
if ($unexpected) { throw 'Unexpected user data in distribution folder.' }
$installerArgs = @("/DAppVersion=$version", "/DVersionInfo=$($version.Split('-')[0]).0", "/DPackageRoot=$packageRoot", "/DReleaseDir=$releaseDir", "/DArtifactSuffix=$artifactSuffix")
$signEnvNames = @('CS2_SIGN_CERT_THUMBPRINT','CS2_SIGN_TOOL','CS2_SIGN_CERT_STORE','CS2_SIGN_TIMESTAMP')
$savedSignEnv = @{}
foreach ($name in $signEnvNames) { $savedSignEnv[$name] = [Environment]::GetEnvironmentVariable($name,'Process') }
try {
    if ($signing) {
        foreach ($name in @('CS2TacticalReplay.exe','cs2parser.exe','cs2maptool.exe')) { & $signer @signOptions -FilePath (Join-Path $packageRoot $name) }
        $env:CS2_SIGN_CERT_THUMBPRINT=$CertificateThumbprint
        $env:CS2_SIGN_TOOL=$SignTool
        $env:CS2_SIGN_CERT_STORE=$CertificateStore
        $env:CS2_SIGN_TIMESTAMP=$TimestampServer
        $shell = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
        $command = '$q' + $shell + '$q -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $q' + $signer + '$q -FilePath $f'
        $installerArgs += @('/DSignedRelease=1',('/Scs2trusted=' + $command))
    }
    & $ISCC @installerArgs (Join-Path $projectRoot 'installer/windows.iss')
    if ($LASTEXITCODE -ne 0) { throw 'Installer compilation failed.' }
} finally {
    foreach ($name in $signEnvNames) { [Environment]::SetEnvironmentVariable($name,$savedSignEnv[$name],'Process') }
}
$setup = Join-Path $releaseDir "CS2TacticalReplay-$version-windows-x64-setup$artifactSuffix.exe"
if ($signing) {
    $signature = Get-AuthenticodeSignature -LiteralPath $setup
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Thumbprint -ne ($CertificateThumbprint -replace '\s','') -or -not $signature.TimeStamperCertificate) { throw 'Installer publisher or timestamp verification failed.' }
}
$zip = Join-Path $releaseDir "CS2TacticalReplay-$version-windows-x64-portable$artifactSuffix.zip"
Compress-Archive -Path (Join-Path $packageRoot '*') -DestinationPath $zip -Force
$setup = Join-Path $releaseDir "CS2TacticalReplay-$version-windows-x64-setup$artifactSuffix.exe"
$checksums = foreach ($file in @($setup,$zip)) { '{0}  {1}' -f (Get-FileHash -Algorithm SHA256 -LiteralPath $file).Hash.ToLowerInvariant(),(Split-Path -Leaf $file) }
$checksums | Set-Content -LiteralPath (Join-Path $releaseDir 'SHA256SUMS.txt') -Encoding ascii
Write-Output "Release artifacts: $releaseDir"
