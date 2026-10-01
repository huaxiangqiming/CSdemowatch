[CmdletBinding()]
param(
    [string]$FilePath,
    [string]$CertificateThumbprint = $env:CS2_SIGN_CERT_THUMBPRINT,
    [string]$SignTool = $env:CS2_SIGN_TOOL,
    [ValidateSet('CurrentUser','LocalMachine')][string]$CertificateStore = $(if ($env:CS2_SIGN_CERT_STORE) { $env:CS2_SIGN_CERT_STORE } else { 'CurrentUser' }),
    [string]$TimestampServer = $(if ($env:CS2_SIGN_TIMESTAMP) { $env:CS2_SIGN_TIMESTAMP } else { 'http://timestamp.digicert.com' }),
    [switch]$ValidateOnly
)
$ErrorActionPreference = 'Stop'
$CertificateThumbprint = $CertificateThumbprint -replace '\s',''
if ($CertificateThumbprint -notmatch '^[0-9a-fA-F]{40}$') { throw 'A specific code-signing certificate thumbprint is required. No self-signed certificate will be created.' }
if (-not $SignTool -or -not (Test-Path -LiteralPath $SignTool -PathType Leaf)) { throw 'Provide the Windows SDK signtool.exe path.' }
$timestampUri = $null
if (-not [Uri]::TryCreate($TimestampServer,[UriKind]::Absolute,[ref]$timestampUri) -or $timestampUri.Scheme -notin @('http','https')) { throw 'A valid RFC 3161 timestamp URL is required.' }
$certificate = Get-ChildItem -Path "Cert:\$CertificateStore\My" -CodeSigningCert | Where-Object { $_.Thumbprint -eq $CertificateThumbprint } | Select-Object -First 1
if (-not $certificate -or -not $certificate.HasPrivateKey) { throw 'Code-signing certificate with an accessible private key was not found. Connect/configure your approved certificate provider first.' }
$now = Get-Date
if ($certificate.NotBefore -gt $now -or $certificate.NotAfter -le $now) { throw 'Signing certificate is not currently valid.' }
if ($certificate.Subject -eq $certificate.Issuer) { throw 'Self-signed certificates cannot establish a public publisher identity.' }
$chain = [Security.Cryptography.X509Certificates.X509Chain]::new()
try {
    $chain.ChainPolicy.ApplicationPolicy.Add([Security.Cryptography.Oid]::new('1.3.6.1.5.5.7.3.3'))
    if (-not $chain.Build($certificate)) { throw 'Signing certificate chain is not trusted or could not be validated.' }
} finally { $chain.Dispose() }
if ($ValidateOnly) { Write-Output 'Signing prerequisites validated.'; return }
if (-not $FilePath -or -not (Test-Path -LiteralPath $FilePath -PathType Leaf)) { throw 'Signing target does not exist.' }
$resolvedFile = (Resolve-Path -LiteralPath $FilePath).Path
$arguments = @('sign','/s','My','/sha1',$CertificateThumbprint,'/fd','SHA256','/tr',$TimestampServer,'/td','SHA256','/d','CS2 Tactical Replay')
if ($CertificateStore -eq 'LocalMachine') { $arguments += '/sm' }
$arguments += $resolvedFile
& $SignTool @arguments
if ($LASTEXITCODE -ne 0) { throw "SignTool failed: $resolvedFile" }
& $SignTool verify /pa /all $resolvedFile
if ($LASTEXITCODE -ne 0) { throw "Signature verification failed: $resolvedFile" }
$signature = Get-AuthenticodeSignature -LiteralPath $resolvedFile
if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Thumbprint -ne $CertificateThumbprint -or -not $signature.TimeStamperCertificate) { throw 'Publisher identity or timestamp verification failed.' }
Write-Output "Verified timestamped signature: $resolvedFile"
