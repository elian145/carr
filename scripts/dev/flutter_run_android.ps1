# Run the Flutter app on Android with a compatible JDK.
# Flutter prefers Android Studio's bundled JBR, but Java 25 and broken
# Studio installs can break Gradle. This script uses Temurin 17.
param(
    [string]$Flavor = "dev",
    [string]$ApiBase = "https://carr-5hrm.onrender.com",
    [string]$Device = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$jdkRoot = Join-Path $env:LOCALAPPDATA ".jdks\temurin-17"

if (-not (Test-Path (Join-Path $jdkRoot "bin\java.exe"))) {
    Write-Error @"
JDK 17 not found at $jdkRoot

Install Temurin 17, then run:
  flutter config --jdk-dir="$jdkRoot"
"@
}

$env:JAVA_HOME = $jdkRoot
Set-Location $repoRoot

$args = @(
    "run",
    "--flavor", $Flavor,
    "--dart-define=API_BASE=$ApiBase"
)
if ($Device) {
    $args += @("-d", $Device)
}

Write-Host "Using JAVA_HOME=$env:JAVA_HOME"
& flutter @args
