$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$dataPath = Join-Path $projectRoot 'test_data'
$archivePath = Join-Path $dataPath 's2.7z'
$demoPath = Join-Path $dataPath 's2/s2.dem'
$archiveHash = 'AF8227B333CDD881DC9AD49D19D936DE04789069EF49B736CD3BF3E6BB37DD43'
$demoHash = '9051F4690A8A2F1A0D54026685E5F83F1A2AAB04574A1CB8735B7413712319A2'
$sourceUrl = 'https://gitlab.com/markus-wa/cs-demos-2/-/raw/df52577f7d01d9dd2172dee6fad48c6d9ced4b22/s2.7z'
New-Item -ItemType Directory -Force -Path $dataPath | Out-Null
if (-not (Test-Path -LiteralPath $archivePath)) {
    & curl.exe -L --fail --retry 2 --max-time 300 $sourceUrl -o $archivePath
    if ($LASTEXITCODE -ne 0) { throw 'Demo archive download failed.' }
}
if ((Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash -ne $archiveHash) {
    throw 'Demo archive checksum mismatch. Existing archive was not extracted.'
}
if (-not (Test-Path -LiteralPath $demoPath)) {
    & tar -xf $archivePath -C $dataPath s2/s2.dem
    if ($LASTEXITCODE -ne 0) { throw 'Demo extraction failed.' }
}
if ((Get-FileHash -LiteralPath $demoPath -Algorithm SHA256).Hash -ne $demoHash) {
    throw 'Demo checksum mismatch. Existing demo was not overwritten.'
}
Write-Output "Verified public CS2 demo: $demoPath"
