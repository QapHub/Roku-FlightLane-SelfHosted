param(
    [string]$EnvironmentFile = ".env.local",
    [switch]$ScreenSaver
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$environmentPath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $EnvironmentFile))
$generatedPath = Join-Path $repoRoot "source\config.generated.brs"
$imageRoot = Join-Path $repoRoot "images"
$radarImagePath = Join-Path $imageRoot "radar-bg.png"
$mapBackdropPath = Join-Path $imageRoot "map-backdrop.jpg"
$staticAssetNames = @(
    "remote-dpad.png",
    "remote-ok.png",
    "remote-options.png",
    "remote-back.png",
    "flightlane-icon-v2_FHD.png",
    "flightlane-icon-v2_HD.png",
    "flightlane-icon-v2_SD.png",
    "splash-screen_FHD.jpg",
    "splash-screen_HD.jpg",
    "splash-screen_SD.jpg"
)
$stageFolder = if ($ScreenSaver) { "out\package-screensaver" } else { "out\package" }
$stageRoot = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $stageFolder))
$distRoot = [System.IO.Path]::GetFullPath((Join-Path $repoRoot "dist"))
$packageName = if ($ScreenSaver) { "flight-lane-screensaver.zip" } else { "flight-lane.zip" }
$packagePath = Join-Path $distRoot $packageName

if (-not (Test-Path -LiteralPath $environmentPath)) {
    throw "Missing $EnvironmentFile. Copy .env.example to .env.local and fill in the values."
}

function Read-DotEnv([string]$Path) {
    $values = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        $trimmed = $line.Trim()
        if ($trimmed.Length -eq 0 -or $trimmed.StartsWith("#")) {
            continue
        }
        $parts = $trimmed.Split("=", 2)
        if ($parts.Count -ne 2) {
            continue
        }
        $value = $parts[1].Trim()
        if ($value.Length -ge 2 -and $value.StartsWith('"') -and $value.EndsWith('"')) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        $values[$parts[0].Trim()] = $value
    }
    return $values
}

function Get-Value([hashtable]$Values, [string]$Name, [string]$Fallback = "") {
    if ($Values.ContainsKey($Name)) {
        return [string]$Values[$Name]
    }
    return $Fallback
}

function ConvertTo-BrightScriptString([string]$Value) {
    return $Value.Replace('"', '""')
}

function Read-Double([string]$Value, [double]$Fallback) {
    $parsed = 0.0
    $valid = [double]::TryParse(
        $Value,
        [Globalization.NumberStyles]::Float,
        [Globalization.CultureInfo]::InvariantCulture,
        [ref]$parsed
    )
    if ($valid) {
        return $parsed
    }
    return $Fallback
}

function New-RadarImage([string]$Path, [double]$OuterRadius) {
    Add-Type -AssemblyName System.Drawing
    $size = 840
    $bitmap = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.Clear([System.Drawing.Color]::Transparent)

        $minorPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(115, 125, 211, 252), 2)
        $majorPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(205, 56, 189, 248), 3)
        $crossPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(100, 186, 230, 253), 2)
        try {
            $center = $size / 2
            $graphics.DrawLine($crossPen, $center, $center - $OuterRadius, $center, $center + $OuterRadius)
            $graphics.DrawLine($crossPen, $center - $OuterRadius, $center, $center + $OuterRadius, $center)
            foreach ($fraction in @(0.25, 0.5, 0.75, 1.0)) {
                $radius = $OuterRadius * $fraction
                $pen = if ($fraction -eq 1.0) { $majorPen } else { $minorPen }
                $graphics.DrawEllipse($pen, $center - $radius, $center - $radius, $radius * 2, $radius * 2)
            }
        }
        finally {
            $minorPen.Dispose()
            $majorPen.Dispose()
            $crossPen.Dispose()
        }
        $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

function New-FallbackMap([string]$Path) {
    Add-Type -AssemblyName System.Drawing
    $bitmap = New-Object System.Drawing.Bitmap(840, 840)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.Clear([System.Drawing.Color]::FromArgb(8, 24, 39))
        $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Jpeg)
    }
    finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

$config = Read-DotEnv $environmentPath
$appName = ConvertTo-BrightScriptString (Get-Value $config "APP_NAME" "Flight Lane")
$latitude = 0.0
$longitude = 0.0
$radiusMiles = Read-Double (Get-Value $config "RADIUS_MILES" "4") 4.0
$refreshSeconds = Read-Double (Get-Value $config "REFRESH_SECONDS" "15") 15.0
$flightLaneApiUrl = ConvertTo-BrightScriptString ((Get-Value $config "FLIGHTLANE_API_URL").TrimEnd('/'))

$hasLocation = $false
if ($radiusMiles -lt 1 -or $radiusMiles -gt 10) {
    throw "RADIUS_MILES must be from 1 to 10."
}
if ($refreshSeconds -lt 5) { $refreshSeconds = 5.0 }
if ([string]::IsNullOrWhiteSpace($flightLaneApiUrl)) {
    throw "FLIGHTLANE_API_URL is required. Use the private-LAN address of this computer's local service."
}
try {
    $serviceUri = [Uri]$flightLaneApiUrl
}
catch {
    throw "FLIGHTLANE_API_URL must be a valid HTTP or HTTPS URL."
}
if ($serviceUri.Scheme -ne "http" -and $serviceUri.Scheme -ne "https") {
    throw "FLIGHTLANE_API_URL must use HTTP or HTTPS."
}
if ($serviceUri.Host -eq "localhost" -or $serviceUri.Host -eq "127.0.0.1") {
    throw "FLIGHTLANE_API_URL cannot use localhost because the Roku must reach this computer over your private network."
}

$satelliteMapEnabled = -not [string]::IsNullOrWhiteSpace($flightLaneApiUrl)
$radarPixelsPerMile = 390.0 / $radiusMiles
$mapZoom = 0
if ($satelliteMapEnabled) {
    $latitudeRadians = $latitude * [Math]::PI / 180.0
    for ($candidateZoom = 21; $candidateZoom -ge 0; $candidateZoom--) {
        $metersPerLogicalPixel = 156543.03392 * [Math]::Cos($latitudeRadians) / [Math]::Pow(2, $candidateZoom)
        $candidatePixelsPerMile = (1609.344 / $metersPerLogicalPixel) * (840.0 / 640.0)
        if (($candidatePixelsPerMile * $radiusMiles) -le 390.0) {
            $mapZoom = $candidateZoom
            $radarPixelsPerMile = $candidatePixelsPerMile
            break
        }
    }
}
$radarOuterRadius = $radarPixelsPerMile * $radiusMiles

$closeupRadiusFeet = 1000.0
$closeupViewportSize = 320.0
$closeupRadarRadiusPixels = 390.0 * ($closeupViewportSize / 840.0)
$closeupRadarPixelsPerFoot = $closeupRadarRadiusPixels / $closeupRadiusFeet
$closeupMaxZoom = 17

$culture = [Globalization.CultureInfo]::InvariantCulture
$latitudeLiteral = $latitude.ToString("0.######", $culture)
$longitudeLiteral = $longitude.ToString("0.######", $culture)
$radiusLiteral = $radiusMiles.ToString("0.###", $culture)
$refreshLiteral = $refreshSeconds.ToString("0.###", $culture)
$radarPixelsPerMileLiteral = $radarPixelsPerMile.ToString("0.######", $culture)
$mapZoomLiteral = $mapZoom.ToString($culture)
$closeupRadiusFeetLiteral = $closeupRadiusFeet.ToString("0", $culture)
$closeupViewportSizeLiteral = $closeupViewportSize.ToString("0", $culture)
$closeupRadarPixelsPerFootLiteral = $closeupRadarPixelsPerFoot.ToString("0.######", $culture)
$closeupMaxZoomLiteral = $closeupMaxZoom.ToString($culture)
$hasLocationLiteral = if ($hasLocation) { "true" } else { "false" }
$satelliteMapEnabledLiteral = if ($satelliteMapEnabled) { "true" } else { "false" }

$generated = @"
' Generated by scripts/build.ps1. Do not commit this file.
function GetAppConfig() as object
    return {
        appName: "$appName"
        hasLocation: $hasLocationLiteral
        homeLatitude: $latitudeLiteral
        homeLongitude: $longitudeLiteral
        radiusMiles: $radiusLiteral
        refreshSeconds: $refreshLiteral
        radarPixelsPerMile: $radarPixelsPerMileLiteral
        satelliteMapEnabled: $satelliteMapEnabledLiteral
        mapZoom: $mapZoomLiteral
        closeupRadiusFeet: $closeupRadiusFeetLiteral
        closeupViewportSize: $closeupViewportSizeLiteral
        closeupRadarPixelsPerFoot: $closeupRadarPixelsPerFootLiteral
        closeupMaxZoom: $closeupMaxZoomLiteral
        flightLaneApiUrl: "$flightLaneApiUrl"
    }
end function
"@

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($generatedPath, $generated, $utf8NoBom)

New-Item -ItemType Directory -Path $imageRoot -Force | Out-Null
New-FallbackMap $mapBackdropPath
New-RadarImage $radarImagePath 390.0

if (-not $stageRoot.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to clean a staging path outside the repository."
}
if (Test-Path -LiteralPath $stageRoot) {
    Remove-Item -LiteralPath $stageRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null

Copy-Item -LiteralPath (Join-Path $repoRoot "manifest") -Destination $stageRoot
Copy-Item -LiteralPath (Join-Path $repoRoot "source") -Destination $stageRoot -Recurse
Copy-Item -LiteralPath (Join-Path $repoRoot "components") -Destination $stageRoot -Recurse
$stageImages = Join-Path $stageRoot "images"
New-Item -ItemType Directory -Path $stageImages -Force | Out-Null
Copy-Item -LiteralPath $radarImagePath -Destination $stageImages
Copy-Item -LiteralPath $mapBackdropPath -Destination $stageImages
foreach ($staticAssetName in $staticAssetNames) {
    $staticAssetPath = Join-Path $imageRoot $staticAssetName
    if (-not (Test-Path -LiteralPath $staticAssetPath)) {
        throw "Missing packaged image asset: $staticAssetPath"
    }
    Copy-Item -LiteralPath $staticAssetPath -Destination $stageImages
}
if ($ScreenSaver) {
    Copy-Item -LiteralPath (Join-Path $repoRoot "screensaver\manifest") -Destination (Join-Path $stageRoot "manifest") -Force
    Copy-Item -LiteralPath (Join-Path $repoRoot "screensaver\source\main.brs") -Destination (Join-Path $stageRoot "source\main.brs") -Force
}

New-Item -ItemType Directory -Path $distRoot -Force | Out-Null
if (Test-Path -LiteralPath $packagePath) {
    Remove-Item -LiteralPath $packagePath -Force
}
& tar.exe -a -c -f $packagePath -C $stageRoot manifest source components images
if ($LASTEXITCODE -ne 0) {
    throw "Failed to create the Roku ZIP package."
}

Write-Host "Built $packagePath"
