param(
    [string]$EnvironmentFile = ".env.local"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$environmentPath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $EnvironmentFile))
$packagePath = Join-Path $repoRoot "dist\flight-lane.zip"

& (Join-Path $PSScriptRoot "build.ps1") -EnvironmentFile $EnvironmentFile

$rokuIp = ""
foreach ($line in Get-Content -LiteralPath $environmentPath) {
    if ($line -match '^ROKU_DEVICE_IP=(.*)$') {
        $rokuIp = $matches[1].Trim().Trim('"')
        break
    }
}
if ([string]::IsNullOrWhiteSpace($rokuIp)) {
    throw "ROKU_DEVICE_IP is missing from $EnvironmentFile."
}

$securePassword = Read-Host "Roku developer password" -AsSecureString
$passwordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
try {
    $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPointer)
    & curl.exe --fail-with-body --silent --show-error --digest --user "rokudev:$plainPassword" --form "mysubmit=Install" --form "archive=@$packagePath" --form "passwd=" "http://$rokuIp/plugin_install"
    if ($LASTEXITCODE -ne 0) {
        throw "Roku sideload failed. Review the Roku installer response printed above."
    }
}
finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPointer)
}

Write-Host "Flight Lane was installed on $rokuIp."
