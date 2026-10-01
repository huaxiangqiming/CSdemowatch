param([string]$Setup, [string]$OutputDirectory, [switch]$RequireSignature, [switch]$NavigationChecks)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$output = if ($OutputDirectory) { [IO.Path]::GetFullPath($OutputDirectory) } else { Join-Path $projectRoot 'artifacts/installer-check' }
if (-not $output.StartsWith([IO.Path]::GetFullPath((Join-Path $projectRoot 'artifacts')) + [IO.Path]::DirectorySeparatorChar)) { throw 'Test output must stay within project artifacts.' }
$target = [IO.Path]::GetFullPath((Join-Path $output 'Install Test 应用'))
if (-not $target.StartsWith([IO.Path]::GetFullPath($output) + [IO.Path]::DirectorySeparatorChar)) { throw 'Invalid test installation target.' }
if (-not $Setup) { throw 'Pass -Setup with the exact installer to test.' }
$registration = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{90737B99-1704-428F-9D37-5CC0F7B13869}_is1'
if (Test-Path $registration) {
    $existing = (Get-ItemProperty $registration).InstallLocation
    if ($existing.TrimEnd('\') -ne $target.TrimEnd('\')) { throw 'An existing user installation is registered; use a clean test account.' }
}
New-Item -ItemType Directory -Force $output | Out-Null
$checks = @()
if ($RequireSignature) {
    $setupSignature = Get-AuthenticodeSignature -LiteralPath $Setup
    if ($setupSignature.Status -ne 'Valid' -or -not $setupSignature.TimeStamperCertificate) { throw 'Installer is not validly signed and timestamped.' }
}
for ($pass = 1; $pass -le 2; $pass++) {
    $setupArgs = @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-','/NOICONS','/TASKS=',('/DIR="'+$target+'"'),('/LOG="'+(Join-Path $output "setup-$pass.log")+'"'))
    $process = Start-Process -FilePath $Setup -ArgumentList $setupArgs -WindowStyle Hidden -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw "Installation pass $pass failed: $($process.ExitCode)" }
    $checks += "Installation pass $pass completed"
}
foreach ($name in @('CS2TacticalReplay.exe','CS2TacticalReplay.pck','cs2parser.exe','cs2maptool.exe','map-tools/Source2Viewer-CLI.exe','map-tools/libSkiaSharp.dll','map-tools/spirv-cross.dll','licenses/Godot-and-third-party.txt')) {
    $installed = Join-Path $target $name
    $source = Join-Path (Join-Path $projectRoot 'dist/windows') $name
    if ((Get-FileHash -LiteralPath $installed).Hash -ne (Get-FileHash -LiteralPath $source).Hash) { throw "Installed file differs: $name" }
    $checks += "Installed file verified: $name"
}
if ($RequireSignature) {
    foreach ($name in @('CS2TacticalReplay.exe','cs2parser.exe','cs2maptool.exe','unins000.exe')) {
        $signature = Get-AuthenticodeSignature -LiteralPath (Join-Path $target $name)
        if ($signature.Status -ne 'Valid' -or -not $signature.TimeStamperCertificate -or $signature.SignerCertificate.Thumbprint -ne $setupSignature.SignerCertificate.Thumbprint) { throw "Installed signature mismatch: $name" }
        $checks += "Verified signed installed component: $name"
    }
}
$env:M9_PROJECT = $projectRoot
$env:CS2_MAP_CACHE_ROOT = Join-Path $projectRoot 'artifacts/m81/maps'
$env:CS2_REPLAY_DATA_ROOT = Join-Path $output ('user-data-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $env:CS2_REPLAY_DATA_ROOT | Out-Null
$stdout = Join-Path $output 'installed-app.log'
$stderr = Join-Path $output 'installed-app-errors.log'
$testScript = Join-Path $projectRoot 'app/tests/milestone_9_export_tests.gd'
$process = Start-Process -FilePath (Join-Path $target 'CS2TacticalReplay.exe') -ArgumentList '--script',('"'+$testScript+'"') -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
if ($process.ExitCode -ne 0 -or ((Get-Content $stderr) -match 'SCRIPT ERROR:|^ERROR:')) { throw 'Installed application acceptance failed.' }
$report = Get-Content (Join-Path $env:CS2_REPLAY_DATA_ROOT 'report.json') -Raw | ConvertFrom-Json
if ($report.checks -ne 11 -or $report.failures.Count -ne 0) { throw 'Installed acceptance report is incomplete.' }
$checks += '11 real-demo application checks passed from installed EXE'
if ($NavigationChecks) {
    $navigationScript = Join-Path $projectRoot 'app/tests/playback_navigation_tests.gd'
    $navigationLog = Join-Path $output 'navigation-installed.log'
    $navigationErrors = Join-Path $output 'navigation-installed-errors.log'
    $process = Start-Process -FilePath (Join-Path $target 'CS2TacticalReplay.exe') -ArgumentList '--script',('"'+$navigationScript+'"') -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $navigationLog -RedirectStandardError $navigationErrors
    if ($process.ExitCode -ne 0 -or ((Get-Content $navigationErrors) -match 'SCRIPT ERROR:|^ERROR:')) { throw 'Installed playback navigation checks failed.' }
    $navigationReport = Get-Content (Join-Path $projectRoot 'artifacts/m92/navigation-installed-report.json') -Raw | ConvertFrom-Json
    if ($navigationReport.checks -lt 50 -or $navigationReport.failures.Count -ne 0) { throw 'Installed navigation report is incomplete.' }
    $checks += "Installed round/15-second navigation checks: $($navigationReport.checks) passed"
}
$sentinel = Join-Path $env:CS2_REPLAY_DATA_ROOT 'keep-user-data.txt'
'User data must survive uninstall.' | Set-Content -LiteralPath $sentinel
$process = Start-Process -FilePath (Join-Path $target 'unins000.exe') -ArgumentList '/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART' -WindowStyle Hidden -Wait -PassThru
if ($process.ExitCode -ne 0) { throw 'Uninstall failed.' }
if (Test-Path -LiteralPath (Join-Path $target 'CS2TacticalReplay.exe')) { throw 'Application remains after uninstall.' }
if (Test-Path $registration) { throw 'Uninstall registration remains.' }
if (-not (Test-Path -LiteralPath $sentinel)) { throw 'Uninstall removed user data.' }
$checks += 'Uninstall removes application and registration while preserving separate user data'
@{ checks=$checks; count=$checks.Count; app_checks=$report.checks; failures=@() } | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $output 'report.json')
Write-Output "Installer checks: $($checks.Count); installed application checks: $($report.checks); failures: 0"
