Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$temporaryRoot = Join-Path $repoRoot "tmp\validation"

Push-Location $repoRoot
try {
    & npm test
    if ($LASTEXITCODE -ne 0) { throw "Node tests failed." }

    & (Join-Path $PSScriptRoot "build.ps1") -EnvironmentFile ".env.example"
    & (Join-Path $PSScriptRoot "build.ps1") -EnvironmentFile ".env.example" -ScreenSaver

    & npx bsc --project bsconfig.json
    if ($LASTEXITCODE -ne 0) { throw "BrightScript validation failed." }

    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
    & tar.exe -xf (Join-Path $repoRoot "dist\flight-lane.zip") -C $temporaryRoot
    if ($LASTEXITCODE -ne 0) { throw "Unable to inspect the built Roku package." }

    $packageTextFiles = Get-ChildItem -LiteralPath $temporaryRoot -Recurse -File |
        Where-Object { $_.Extension -in @(".brs", ".xml", "") }
    $packageText = ($packageTextFiles | ForEach-Object {
        Get-Content -LiteralPath $_.FullName -Raw
    }) -join "`n"

    $providerMarkers = @(
        "api.airplanes.live",
        "api.adsb.lol",
        "opendata.adsb.fi",
        "aeroapi.flightaware.com",
        "maps.googleapis.com",
        "api.planespotters.net",
        "x-apikey",
        "GOOGLE_MAPS_API_KEY",
        "FLIGHTAWARE_API_KEY"
    )
    foreach ($marker in $providerMarkers) {
        if ($packageText.IndexOf($marker, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            throw "The Roku package unexpectedly contains a server-only provider marker."
        }
    }

    $blockedPlatformName = "cloud" + "flare"
    $blockedPlatformTool = "wrang" + "ler"
    $repositoryFiles = Get-ChildItem -LiteralPath $repoRoot -Recurse -File |
        Where-Object {
            $_.FullName -notmatch '[\\/](node_modules|dist|out|tmp|\.git)[\\/]'
        }
    foreach ($file in $repositoryFiles) {
        if ($file.Extension -notin @(".brs", ".xml", ".json", ".md", ".ps1", ".mjs", ".txt", "")) {
            continue
        }
        $text = Get-Content -LiteralPath $file.FullName -Raw
        if (
            $text.IndexOf($blockedPlatformName, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $text.IndexOf($blockedPlatformTool, [StringComparison]::OrdinalIgnoreCase) -ge 0
        ) {
            throw "A hosted-platform reference was found in $($file.FullName)."
        }
    }

    Write-Host "Validation passed: tests, BrightScript, packages, and public-repository scans."
}
finally {
    Pop-Location
}
