# Start backend and listings servers for the car app.
# Run from repo root. Flutter app expects API at http://<this-PC-IP>:5003
# Requires: .venv\Scripts\python.exe and backend\env.local (PORT=5003, LISTINGS_API_BASE=http://127.0.0.1:5000)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

# 1) Listings API (kk) on port 5000
Start-Process -FilePath ".\.venv\Scripts\python.exe" -ArgumentList "-m", "kk.app_new" -WindowStyle Normal
Start-Sleep -Seconds 5

# 2) Proxy on port 5003 (reads backend\env.local)
Start-Process -FilePath ".\.venv\Scripts\python.exe" -ArgumentList "backend\server.py" -WindowStyle Normal

Write-Host "Servers starting: kk on :5000, proxy on :5003"
Write-Host "Flutter API_BASE: http://192.168.1.7:5003 (or your PC IPv4 from ipconfig)"
Write-Host "Health: http://127.0.0.1:5003/health"
