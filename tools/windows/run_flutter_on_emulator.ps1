Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
if (Test-Path 'C:\src\flutter\bin') {
    $env:Path = 'C:\src\flutter\bin;' + $env:Path
}

Set-Location $PSScriptRoot

Write-Host 'Detecting Android emulator device...'
$plain = flutter devices | Out-String
$match = [regex]::Match($plain, 'emulator-\d+')
if (-not $match.Success) {
	Write-Host $plain
	throw 'No Android emulator device found. Please ensure the emulator is running.'
}
$id = $match.Value
Write-Host \"Using device: $id\"

flutter pub get
# --flavor dev required: app has product flavors (dev/stage/prod); Flutter needs it to find the APK
flutter run -d $id --flavor dev --dart-define=API_BASE=http://10.0.2.2:5000 --dart-define=ALLOW_INSECURE_HTTP=true


