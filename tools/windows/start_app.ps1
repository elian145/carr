# Start backend servers and Flutter app on Android emulator.
# Run from repo root. Uses release mode so the app launches without hanging after install.
#
# If listing images don't show: close any OLD server windows (kk/proxy) so the new
# backend (with static fallback for repo-root uploads) is the one in use.

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

# 1) Start backend (kk :5000, proxy :5003)
Write-Host 'Starting backend servers... (Close any old server windows so images load correctly.)'
& "$PSScriptRoot\start_servers.ps1"
Start-Sleep -Seconds 3

# 2) Find Android emulator
Write-Host 'Detecting Android emulator...'
$plain = flutter devices 2>&1 | Out-String
$match = [regex]::Match($plain, 'emulator-\d+')
if (-not $match.Success) {
    Write-Host $plain
    throw 'No Android emulator found. Start an emulator first (e.g. from Android Studio).'
}
$deviceId = $match.Value
Write-Host "Using device: $deviceId"

# 3) Run app in release mode (avoids hang after install; no hot reload)
# For debug + hot reload, run manually: flutter run -d $deviceId --flavor dev --dart-define=API_BASE=http://10.0.2.2:5000
Write-Host 'Building and launching app (release mode)...'
flutter run -d $deviceId --flavor dev --release --dart-define=API_BASE=http://10.0.2.2:5000
