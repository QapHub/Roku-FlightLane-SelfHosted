param(
    [string]$EnvironmentFile = ".env.local"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$environmentPath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $EnvironmentFile))

function Read-DotEnv([string]$Path) {
    $values = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        $trimmed = $line.Trim()
        if ($trimmed.Length -eq 0 -or $trimmed.StartsWith("#")) { continue }
        $parts = $trimmed.Split("=", 2)
        if ($parts.Count -ne 2) { continue }
        $value = $parts[1].Trim().Trim('"').Trim("'")
        $values[$parts[0].Trim()] = $value
    }
    return $values
}

function Get-Value([hashtable]$Values, [string]$Name) {
    if ($Values.ContainsKey($Name)) { return [string]$Values[$Name] }
    return ""
}

if (-not (Test-Path -LiteralPath $environmentPath)) {
    throw "Missing $EnvironmentFile. Run npm run setup first."
}

$config = Read-DotEnv $environmentPath
$serviceUrl = (Get-Value $config "FLIGHTLANE_API_URL").TrimEnd("/")
$rokuIp = Get-Value $config "ROKU_DEVICE_IP"
$problems = New-Object System.Collections.Generic.List[string]

Write-Host "Flight Lane self-hosted diagnostics"
Write-Host ""

$nodeVersion = & node --version
if ($LASTEXITCODE -ne 0) {
    $problems.Add("Node.js 20 or newer is required.")
}
else {
    Write-Host "[OK] Node.js $nodeVersion"
}

if ([string]::IsNullOrWhiteSpace($serviceUrl)) {
    $problems.Add("FLIGHTLANE_API_URL is missing.")
}
elseif ($serviceUrl -match '192\.168\.1\.100') {
    $problems.Add("FLIGHTLANE_API_URL still contains the example computer address.")
}
else {
    try {
        $health = Invoke-RestMethod -Uri "$serviceUrl/health" -TimeoutSec 5
        if ($health.ok -eq $true) {
            Write-Host "[OK] Local service responded."
            Write-Host ("     Maps={0}, address lookup={1}, flight details={2}, photos={3}" -f
                $health.features.satelliteMaps,
                $health.features.addressLookup,
                $health.features.flightDetails,
                $health.features.aircraftPhotos)
        }
        else {
            $problems.Add("The local service health response was invalid.")
        }
    }
    catch {
        $problems.Add("The local service did not respond. Start it with npm run api.")
    }
}

if ([string]::IsNullOrWhiteSpace($rokuIp)) {
    $problems.Add("ROKU_DEVICE_IP is missing.")
}
elseif ($rokuIp -eq "192.168.1.50") {
    $problems.Add("ROKU_DEVICE_IP still contains the example Roku address.")
}
else {
    try {
        $rokuResponse = Invoke-WebRequest -Uri "http://$rokuIp" -UseBasicParsing -TimeoutSec 5
        Write-Host "[OK] Roku developer installer responded with HTTP $($rokuResponse.StatusCode)."
    }
    catch {
        if ($_.Exception.Response -ne $null) {
            Write-Host "[OK] Roku developer installer is reachable and requested authentication."
        }
        else {
            $problems.Add("The Roku developer installer was not reachable.")
        }
    }
}

Write-Host ""
if ($problems.Count -eq 0) {
    Write-Host "Diagnostics passed."
    exit 0
}

Write-Host "Fix these items:"
foreach ($problem in $problems) {
    Write-Host "  - $problem"
}
exit 1
