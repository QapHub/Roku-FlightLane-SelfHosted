Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$examplePath = Join-Path $repoRoot ".env.example"
$environmentPath = Join-Path $repoRoot ".env.local"

if (-not (Test-Path -LiteralPath $environmentPath)) {
    Copy-Item -LiteralPath $examplePath -Destination $environmentPath
    Write-Host "Created .env.local from the safe example."
}
else {
    Write-Host ".env.local already exists; it was not changed."
}

$addresses = @()
try {
    $addresses = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
        Where-Object {
            $_.IPAddress -notlike "127.*" -and
            $_.IPAddress -notlike "169.254.*" -and
            $_.AddressState -eq "Preferred"
        } |
        Select-Object -ExpandProperty IPAddress -Unique
}
catch {
    Write-Host "Automatic private-network address detection was unavailable."
}

if ($addresses.Count -gt 0) {
    Write-Host ""
    Write-Host "Possible computer address for FLIGHTLANE_API_URL:"
    foreach ($address in $addresses) {
        Write-Host "  http://${address}:8787"
    }
}

Write-Host ""
Write-Host "Next:"
Write-Host "  1. Edit .env.local and replace both example IP addresses."
Write-Host "  2. Add your Google API key(s) and optional FlightAware key."
Write-Host "  3. Run npm run api and leave that terminal open."
Write-Host "  4. In a second terminal, run npm run deploy."
