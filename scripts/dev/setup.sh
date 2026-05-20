#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."

echo "🚗 Car Listings App - Complete Setup"
echo "===================================="

# Check if Python is installed
if ! command -v python3 &> /dev/null; then
    echo "❌ Python 3 is not installed. Please install Python 3.8+ first."
    exit 1
fi

# Check if Flutter is installed
if ! command -v flutter &> /dev/null; then
    echo "❌ Flutter is not installed. Please install Flutter first."
    exit 1
fi

echo "✅ Python and Flutter are installed"

# Setup Backend
echo ""
echo "🔧 Setting up Backend..."
cd kk

# Create virtual environment
echo "Creating virtual environment..."
python3 -m venv venv

# Activate virtual environment
echo "Activating virtual environment..."
source venv/bin/activate

# Install Python dependencies
echo "Installing Python dependencies..."
pip install -r requirements.txt

# Run backend setup
echo "Running backend setup..."
python setup_backend.py

echo "✅ Backend setup completed!"

# Setup Frontend
echo ""
echo "📱 Setting up Frontend..."
cd ..

# Install Flutter dependencies
echo "Installing Flutter dependencies..."
flutter pub get

echo "✅ Frontend setup completed!"

echo ""
echo "🎉 Setup completed successfully!"
echo ""
echo "Next steps:"
echo "1. Update .env file in kk/ directory with your email and Firebase configuration"
echo "2. Start the backend: cd kk && source venv/bin/activate && python app_new.py"
echo "3. Start the Flutter app: flutter run"
echo ""
echo "Admin credentials:"
echo "  IMPORTANT: Do not use default credentials in production."
echo "  Provision an admin account securely (env/bootstrap), and rotate passwords."
echo ""
echo "Backend will be available at: http://localhost:5000"
echo "Admin dashboard: http://localhost:5000/api/admin/dashboard"
