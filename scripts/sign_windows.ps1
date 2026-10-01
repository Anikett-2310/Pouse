<#
.SYNOPSIS
    Authenticode signing helper script for Pouse Windows release binaries and installers.

.DESCRIPTION
    Signs a target file (pc-client.exe or Pouse-Setup-v*.exe) using signtool.exe.
    Requires external signing credentials provided via environment variables.
    NO CREDENTIALS OR SECRETS ARE EMBEDDED IN THIS SCRIPT.

.PARAMETER FilePath
    Path to the executable or installer to sign.

.EXAMPLE
    # Signing via PFX file in CI/local environment:
    $env:POUSE_CERT_FILE = "C:\secrets\pouse-codesign.pfx"
    $env:POUSE_CERT_PASSWORD = "SecretPassword"
    .\scripts\sign_windows.ps1 -FilePath "pc-client\target\release\pc-client.exe"

.EXAMPLE
    # Signing via installed certificate thumbprint:
    $env:POUSE_CERT_THUMBPRINT = "ABCD1234EF567890..."
    .\scripts\sign_windows.ps1 -FilePath "pc-client\target\release\pc-client.exe"
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$FilePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Test-Path $FilePath)) {
    Write-Error "Target file not found: $FilePath"
    exit 1
}

$ResolvedPath = (Resolve-Path $FilePath).Path
Write-Host "Target file: $ResolvedPath"

# Locate signtool.exe
$Signtool = (Get-Command signtool.exe -ErrorAction SilentlyContinue)?.Source
if (-not $Signtool) {
    # Check common Windows SDK locations
    $SdkPaths = @(
        "${env:ProgramFiles(x86)}\Windows Kits\10\bin\*\x64\signtool.exe",
        "${env:ProgramFiles}\Windows Kits\10\bin\*\x64\signtool.exe"
    )
    $FoundSigntool = Get-Item $SdkPaths -ErrorAction SilentlyContinue | Select-Object -Last 1
    if ($FoundSigntool) {
        $Signtool = $FoundSigntool.FullName
    }
}

if (-not $Signtool) {
    Write-Error "signtool.exe not found. Please install the Windows 10/11 SDK or run from a Developer Command Prompt."
    exit 1
}

Write-Host "Using signtool: $Signtool"

$TimestampUrl = if ($env:POUSE_TIMESTAMP_SERVER) { $env:POUSE_TIMESTAMP_SERVER } else { "http://timestamp.digicert.com" }

if ($env:POUSE_CERT_FILE) {
    if (-not (Test-Path $env:POUSE_CERT_FILE)) {
        Write-Error "Certificate file specified in POUSE_CERT_FILE not found: $env:POUSE_CERT_FILE"
        exit 1
    }
    if (-not $env:POUSE_CERT_PASSWORD) {
        Write-Error "POUSE_CERT_FILE is set but POUSE_CERT_PASSWORD is empty."
        exit 1
    }

    Write-Host "Signing with PFX file: $env:POUSE_CERT_FILE"
    & $Signtool sign /fd sha256 /f $env:POUSE_CERT_FILE /p $env:POUSE_CERT_PASSWORD /tr $TimestampUrl /td sha256 "$ResolvedPath"
}
elseif ($env:POUSE_CERT_THUMBPRINT) {
    Write-Host "Signing with certificate thumbprint: $env:POUSE_CERT_THUMBPRINT"
    & $Signtool sign /fd sha256 /sha1 $env:POUSE_CERT_THUMBPRINT /tr $TimestampUrl /td sha256 "$ResolvedPath"
}
else {
    Write-Error @"
No signing credentials found in environment variables.
Please set either:
  `$env:POUSE_CERT_FILE and `$env:POUSE_CERT_PASSWORD (for PFX file)
  OR
  `$env:POUSE_CERT_THUMBPRINT (for Certificate Store / HSM)
Optional:
  `$env:POUSE_TIMESTAMP_SERVER (defaults to http://timestamp.digicert.com)
"@
    exit 1
}

# Verify signature
$Sig = Get-AuthenticodeSignature $ResolvedPath
Write-Host "Signature status: $($Sig.Status)"
if ($Sig.Status -ne "Valid") {
    Write-Error "Signature verification failed: $($Sig.StatusMessage)"
    exit 1
}

Write-Host "Successfully signed: $ResolvedPath"
