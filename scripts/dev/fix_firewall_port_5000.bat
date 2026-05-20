@echo off
echo Adding Windows Firewall rule for Flask Server Port 5000...
netsh advfirewall firewall add rule name="Flask Server Port 5000" dir=in action=allow protocol=TCP localport=5000
if %errorlevel% equ 0 (
    echo Firewall rule added successfully!
    echo Port 5000 is now accessible from network.
) else (
    echo Failed to add firewall rule. Please run as Administrator.
)
pause
