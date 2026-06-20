# Run the same checks as CI locally (Flutter + static preflight + backend smoke).
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

Write-Host "== flutter analyze ==" -ForegroundColor Cyan
flutter analyze --no-fatal-infos
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "== flutter test ==" -ForegroundColor Cyan
flutter test --no-pub --coverage
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "== verify_publish_ready ==" -ForegroundColor Cyan
python scripts/verify_publish_ready.py
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "== backend factory smoke ==" -ForegroundColor Cyan
$env:APP_ENV = "testing"
python scripts/smoke_tests/test_backend_factory_smoke.py
exit $LASTEXITCODE
