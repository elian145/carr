@echo off
echo 🚗 Car Listings App - Complete Setup
echo ====================================

REM Check if Python is installed
python --version >nul 2>&1
if errorlevel 1 (
    echo ❌ Python is not installed. Please install Python 3.8+ first.
    pause
    exit /b 1
)

REM Check if Flutter is installed
flutter --version >nul 2>&1
if errorlevel 1 (
    echo ❌ Flutter is not installed. Please install Flutter first.
    pause
    exit /b 1
)

echo ✅ Python and Flutter are installed

REM Setup Backend
echo.
echo 🔧 Setting up Backend...
cd kk

REM Create virtual environment
echo Creating virtual environment...
python -m venv venv

REM Activate virtual environment
echo Activating virtual environment...
call venv\Scripts\activate.bat

REM Install Python dependencies
echo Installing Python dependencies...
pip install -r requirements.txt

REM Run backend setup
echo Running backend setup...
python setup_backend.py

echo ✅ Backend setup completed!

REM Setup Frontend
echo.
echo 📱 Setting up Frontend...
cd ..

REM Install Flutter dependencies
echo Installing Flutter dependencies...
flutter pub get

echo ✅ Frontend setup completed!

echo.
echo 🎉 Setup completed successfully!
echo.
echo Next steps:
echo 1. Update .env file in kk/ directory with your email and Firebase configuration
echo 2. Start the backend: cd kk ^&^& venv\Scripts\activate.bat ^&^& python app_new.py
echo 3. Start the Flutter app: flutter run
echo.
echo Admin credentials:
echo   IMPORTANT: Do not use default credentials in production.
echo   Provision an admin account securely (env/bootstrap), and rotate passwords.
echo.
echo Backend will be available at: http://localhost:5000
echo Admin dashboard: http://localhost:5000/api/admin/dashboard

pause
