# Print SHA-256 for ANDROID_SHA256_CERT_FINGERPRINTS (delegates to Python script).
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
python scripts/print_android_app_link_sha.py
exit $LASTEXITCODE
