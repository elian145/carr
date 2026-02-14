# Start backend and listings servers for the car app.
# Run from repo root. Flutter app expects API at http://<this-PC-IP>:5003
# Requires: .venv\Scripts\python.exe and backend\env.local (PORT=5003, LISTINGS_API_BASE=http://127.0.0.1:5000)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

# 1) Listings API (kk) on port 5000 — USE_LEGACY_CARS_DB=1 uses kk/instance/cars.db (all listings + images)
# Use cmd.exe so this works on Windows PowerShell 5.1 too (Start-Process has no -Environment there).
Start-Process -FilePath "cmd.exe" -ArgumentList "/c", "set APP_ENV=development&& set PORT=5000&& set USE_LEGACY_CARS_DB=1&& .\\.venv\\Scripts\\python.exe -m kk.app_new" -WindowStyle Normal
Start-Sleep -Seconds 5

# 2) Proxy on port 5003 (reads backend\env.local)
Start-Process -FilePath "cmd.exe" -ArgumentList "/c", "set PORT=5003&& set LISTINGS_API_BASE=http://127.0.0.1:5000&& .\\.venv\\Scripts\\python.exe backend\\server.py" -WindowStyle Normal

Write-Host "Servers starting: kk on :5000, proxy on :5003"
try {
  $lanIp = Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object {
      $_.IPAddress -ne "127.0.0.1" -and
      $_.IPAddress -notlike "169.254*" -and
      $_.IPAddress -match "^(10\\.|192\\.168\\.|172\\.(1[6-9]|2[0-9]|3[0-1])\\.)"
    } |
    Sort-Object -Property InterfaceMetric |
    Select-Object -First 1 -ExpandProperty IPAddress
} catch {
  $lanIp = $null
}
if (-not $lanIp) { $lanIp = "127.0.0.1" }
Write-Host "Flutter API_BASE (LAN): http://$($lanIp):5003"
Write-Host "Health: http://127.0.0.1:5003/health"
