Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

try {
	New-Item -Path 'C:\src' -ItemType Directory -Force | Out-Null
} catch {}

# Ensure TLS 1.2+
try {
	[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
} catch {}

function Get-FlutterStableArchive {
	$releasesUrl = 'https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json'
	# Use -UseBasicParsing for compatibility
	$json = (Invoke-WebRequest -UseBasicParsing -Uri $releasesUrl).Content
	$meta = $json | ConvertFrom-Json
	$stableHash = $meta.current_release.stable
	$rel = $meta.releases | Where-Object { $_.hash -eq $stableHash } | Select-Object -First 1
	if (-not $rel) { throw 'Could not resolve Flutter stable release info (by hash)' }
	$baseUrl = $meta.base_url.TrimEnd('/')
	$archive = $rel.archive
	if (-not $archive) { throw 'No archive path in release info' }
	return @{ Url = ($baseUrl + '/' + $archive); Version = $rel.version; Hash = $stableHash }
}

$destZip = 'C:\src\flutter_stable.zip'
$flutter = Get-FlutterStableArchive
$zipUrl = $flutter.Url
Write-Host "Downloading Flutter $($flutter.Version) (hash $($flutter.Hash)) from $zipUrl ..."

function Download-WithBits {
	if (Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue) {
		Start-BitsTransfer -Source $zipUrl -Destination $destZip
		return $true
	}
	return $false
}

function Download-WithCurl {
	if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
		& curl.exe -L $zipUrl -o $destZip
		if ($LASTEXITCODE -ne 0) { throw "curl failed with exit code $LASTEXITCODE" }
		return
	}
	throw 'curl.exe not found'
}

if (Test-Path $destZip) { try { Remove-Item -Force $destZip } catch {} }

$usedBits = $false
try {
	$usedBits = Download-WithBits
	if (-not $usedBits) {
		Download-WithCurl
	}
} catch {
	# Fallback to curl if BITS failed
	Download-WithCurl
}

if (-not (Test-Path $destZip)) { throw "Download failed: $destZip not found" }

if (Test-Path 'C:\src\flutter') {
	try { Remove-Item -Recurse -Force 'C:\src\flutter' } catch {}
}

Expand-Archive -Path $destZip -DestinationPath 'C:\src' -Force
Remove-Item $destZip -Force

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


