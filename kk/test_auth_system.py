#!/usr/bin/env python3
"""
Test script for the authentication system
This script tests all authentication endpoints and security features
"""

import requests
import json
import time
import sys
from datetime import datetime

# Configuration
BASE_URL = "http://localhost:5000"
TEST_USER = {
    "username": "testuser_auth",
    "phone_number": "+1234567890",
    "password": "TestPass123!",
    "first_name": "Test",
    "last_name": "User"
}

class AuthTester:
    def __init__(self, base_url):
        self.base_url = base_url
        self.session = requests.Session()
        self.access_token = None
        self.refresh_token = None
        self.user_id = None
        
    def log(self, message, status="INFO"):
        timestamp = datetime.now().strftime("%H:%M:%S")
        print(f"[{timestamp}] {status}: {message}")
    
    def test_endpoint(self, method, endpoint, data=None, headers=None, expected_status=200):
        """Test an API endpoint"""
        url = f"{self.base_url}{endpoint}"
        
        try:
            if method.upper() == "GET":
                response = self.session.get(url, headers=headers)
            elif method.upper() == "POST":
                response = self.session.post(url, json=data, headers=headers)
            elif method.upper() == "PUT":
                response = self.session.put(url, json=data, headers=headers)
            elif method.upper() == "DELETE":
                response = self.session.delete(url, headers=headers)
            else:
                raise ValueError(f"Unsupported method: {method}")
            
            if response.status_code == expected_status:
                self.log(f"✅ {method} {endpoint} - Status: {response.status_code}", "PASS")
                return response
            else:
                self.log(f"❌ {method} {endpoint} - Expected: {expected_status}, Got: {response.status_code}", "FAIL")
                self.log(f"Response: {response.text}", "ERROR")
                return response
                
        except Exception as e:
            self.log(f"❌ {method} {endpoint} - Exception: {str(e)}", "ERROR")
            return None
    
    def test_user_registration(self):
        """Test user registration"""
        self.log("Testing user registration...")
        
        # Test valid registration
        response = self.test_endpoint("POST", "/api/auth/register", TEST_USER, expected_status=201)
        if response and response.status_code == 201:
            data = response.json()
            self.user_id = data.get('user', {}).get('id')
            self.log(f"User registered with ID: {self.user_id}")
        
        # Test duplicate registration
        self.test_endpoint("POST", "/api/auth/register", TEST_USER, expected_status=400)
        
        # Test invalid data
        invalid_user = TEST_USER.copy()
        invalid_user['phone_number'] = "invalid-phone"
        self.test_endpoint("POST", "/api/auth/register", invalid_user, expected_status=400)
        
        # Test missing fields
        incomplete_user = {"username": "test"}
        self.test_endpoint("POST", "/api/auth/register", incomplete_user, expected_status=400)
    
    def test_user_login(self):
        """Test user login"""
        self.log("Testing user login...")
        
        # Test valid login
        login_data = {
            "username": TEST_USER["username"],
            "password": TEST_USER["password"]
        }
        response = self.test_endpoint("POST", "/api/auth/login", login_data, expected_status=200)
        
        if response and response.status_code == 200:
            data = response.json()
            self.access_token = data.get('access_token')
            self.refresh_token = data.get('refresh_token')
            self.log("Login successful, tokens received")
        
        # Test invalid credentials
        invalid_login = {
            "username": TEST_USER["username"],
            "password": "wrongpassword"
        }
        self.test_endpoint("POST", "/api/auth/login", invalid_login, expected_status=401)
        
        # Test missing credentials
        self.test_endpoint("POST", "/api/auth/login", {}, expected_status=400)
    
    def test_protected_endpoints(self):
        """Test protected endpoints"""
        if not self.access_token:
            self.log("No access token available, skipping protected endpoint tests", "WARN")
            return
        
        self.log("Testing protected endpoints...")
        headers = {"Authorization": f"Bearer {self.access_token}"}
        
        # Test get profile
        self.test_endpoint("GET", "/api/user/profile", headers=headers, expected_status=200)
        
        # Test get my listings
        self.test_endpoint("GET", "/api/user/my-listings", headers=headers, expected_status=200)
        
        # Test get favorites
        self.test_endpoint("GET", "/api/user/favorites", headers=headers, expected_status=200)
    
    def test_car_listing_operations(self):
        """Test car listing operations"""
        if not self.access_token:
            self.log("No access token available, skipping car listing tests", "WARN")
            return
        
        self.log("Testing car listing operations...")
        headers = {"Authorization": f"Bearer {self.access_token}"}
        
        # Test create car listing
        car_data = {
            "brand": "Toyota",
            "model": "Camry",
            "year": 2020,
            "mileage": 50000,
            "engine_type": "Gas",
            "transmission": "Automatic",
            "drive_type": "FWD",
            "condition": "Used",
            "body_type": "Sedan",
            "price": 25000,
            "location": "New York, NY",
            "description": "Well maintained car",
            "color": "Silver"
        }
        
        response = self.test_endpoint("POST", "/api/cars", car_data, headers=headers, expected_status=201)
        car_id = None
        if response and response.status_code == 201:
            data = response.json()
            car_id = data.get('car', {}).get('id')
            self.log(f"Car listing created with ID: {car_id}")
        
        # Test get all cars (public endpoint)
        self.test_endpoint("GET", "/api/cars", expected_status=200)
        
        # Test get specific car
        if car_id:
            self.test_endpoint("GET", f"/api/cars/{car_id}", expected_status=200)
            
            # Test update car (owner only)
            update_data = {"price": 24000}
            self.test_endpoint("PUT", f"/api/cars/{car_id}", update_data, headers=headers, expected_status=200)
            
            # Test delete car (owner only)
            self.test_endpoint("DELETE", f"/api/cars/{car_id}", headers=headers, expected_status=200)
    
    def test_token_operations(self):
        """Test token operations"""
        if not self.refresh_token:
            self.log("No refresh token available, skipping token tests", "WARN")
            return
        
        self.log("Testing token operations...")
        
        # Test token refresh
        headers = {"Authorization": f"Bearer {self.refresh_token}"}
        response = self.test_endpoint("POST", "/api/auth/refresh", headers=headers, expected_status=200)
        
        if response and response.status_code == 200:
            data = response.json()
            new_access_token = data.get('access_token')
            if new_access_token:
                self.access_token = new_access_token
                self.log("Token refresh successful")
        
        # Test logout (should blacklist token)
        if self.access_token:
            headers = {"Authorization": f"Bearer {self.access_token}"}
            self.test_endpoint("POST", "/api/auth/logout", headers=headers, expected_status=200)
            
            # Test that token is now blacklisted
            self.test_endpoint("GET", "/api/user/profile", headers=headers, expected_status=401)
    
    def test_rate_limiting(self):
        """Test rate limiting"""
        self.log("Testing rate limiting...")
        
        # Test registration rate limiting
        for i in range(6):  # Should fail on 6th attempt
            response = self.test_endpoint("POST", "/api/auth/register", TEST_USER, expected_status=400 if i >= 5 else 201)
            if i >= 5 and response and response.status_code == 429:
                self.log("Rate limiting working correctly")
                break
        
        # Test login rate limiting
        invalid_login = {"username": "nonexistent", "password": "wrong"}
        for i in range(12):  # Should fail on 11th attempt
            response = self.test_endpoint("POST", "/api/auth/login", invalid_login, expected_status=401)
            if i >= 10 and response and response.status_code == 429:
                self.log("Login rate limiting working correctly")
                break
    
    def test_security_headers(self):
        """Test security headers"""
        self.log("Testing security headers...")
        
        response = self.session.get(f"{self.base_url}/api/cars")
        if response:
            security_headers = [
                'X-Content-Type-Options',
                'X-Frame-Options',
                'X-XSS-Protection',
                'Strict-Transport-Security'
            ]
            
            for header in security_headers:
                if header in response.headers:
                    self.log(f"✅ Security header present: {header}", "PASS")
                else:
                    self.log(f"❌ Security header missing: {header}", "WARN")
    
    def run_all_tests(self):
        """Run all tests"""
        self.log("Starting authentication system tests...")
        self.log("=" * 50)
        
        try:
            self.test_user_registration()
            self.test_user_login()
            self.test_protected_endpoints()
            self.test_car_listing_operations()
            self.test_token_operations()
            self.test_rate_limiting()
            self.test_security_headers()
            
            self.log("=" * 50)
            self.log("All tests completed!", "SUCCESS")
            
        except KeyboardInterrupt:
            self.log("Tests interrupted by user", "WARN")
        except Exception as e:
            self.log(f"Test suite failed: {str(e)}", "ERROR")

def main():
    """Main test function"""
    print("🧪 Authentication System Test Suite")
    print("=" * 50)
    
    # Check if server is running
    try:
        response = requests.get(f"{BASE_URL}/api/cars", timeout=5)
        if response.status_code != 200:
            print(f"❌ Server not responding correctly. Status: {response.status_code}")
            sys.exit(1)
    except requests.exceptions.RequestException as e:
        print(f"❌ Cannot connect to server at {BASE_URL}")
        print("Make sure the Flask app is running: python app_new.py")
        sys.exit(1)
    
    # Run tests
    tester = AuthTester(BASE_URL)
    tester.run_all_tests()

if __name__ == '__main__':
    main()
