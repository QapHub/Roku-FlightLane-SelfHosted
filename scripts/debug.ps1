param(
    [string]$EnvironmentFile = ".env.local",
    [int]$DurationSeconds = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$environmentPath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $EnvironmentFile))

if (-not (Test-Path -LiteralPath $environmentPath)) {
    throw "Missing $EnvironmentFile."
}

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

function Protect-DebugLine([string]$Line) {
    $protected = [regex]::Replace(
        $Line,
        '(?i)([?&](?:key|x-apikey|address|center|latitude|longitude)=)[^&\s]+',
        '$1[redacted]'
    )
    return [regex]::Replace(
        $protected,
        '(?i)(Authorization\s*[:=]\s*Bearer\s+)[A-Za-z0-9._-]+',
        '$1[redacted]'
    )
}

$client = New-Object System.Net.Sockets.TcpClient
try {
    $client.Connect($rokuIp, 8085)
    $reader = New-Object System.IO.StreamReader($client.GetStream())
    try {
        Write-Host "Connected to the Roku BrightScript console at ${rokuIp}:8085. Press Ctrl+C to stop."
        $deadline = $null
        if ($DurationSeconds -gt 0) {
            $deadline = [DateTime]::UtcNow.AddSeconds($DurationSeconds)
        }
        $discardFirstLine = $true

        while ($client.Connected -and ($null -eq $deadline -or [DateTime]::UtcNow -lt $deadline)) {
            if ($client.Available -gt 0) {
                $line = $reader.ReadLine()
                if ($null -eq $line) {
                    break
                }
                if ($discardFirstLine) {
                    $discardFirstLine = $false
                    continue
                }
                Write-Host (Protect-DebugLine $line)
            }
            else {
                Start-Sleep -Milliseconds 100
            }
        }
    }
    finally {
        $reader.Dispose()
    }
}
finally {
    $client.Dispose()
}
