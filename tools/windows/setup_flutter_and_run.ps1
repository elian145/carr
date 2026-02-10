Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
	New-Item -Path 'C:\src' -ItemType Directory -Force | Out-Null
} catch {}

$releasesUrl = 'https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json'
$meta = Invoke-RestMethod -Uri $releasesUrl
$stableHash = $meta.current_release.stable
$rel = $meta.releases | Where-Object { $_.hash -eq $stableHash } | Select-Object -First 1
if (-not $rel) { throw 'Could not resolve Flutter stable release info' }
$archive = $rel.archive
if (-not $archive) { throw 'No archive path in release info' }
$zipUrl = ($meta.base_url.TrimEnd('/') + '/' + $archive)
$zipPath = 'C:\src\flutter.zip'

Write-Host "Downloading Flutter (stable hash $stableHash) from $zipUrl ..."
Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath

if (Test-Path 'C:\src\flutter') {
	try { Remove-Item -Recurse -Force 'C:\src\flutter' } catch {}
}

Expand-Archive -Path $zipPath -DestinationPath 'C:\src' -Force
Remove-Item $zipPath -Force

$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
$env:Path = 'C:\src\flutter\bin;' + $env:Path

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
	Write-Host 'Git not found. Installing Git via winget...'
	winget install -e --id Git.Git --accept-package-agreements --accept-source-agreements
}

flutter --version

Set-Location 'C:\Users\VeeStore\Desktop\car_listing_app'
flutter pub get
flutter run --dart-define=API_BASE=http://10.0.2.2:5000


