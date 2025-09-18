#!/usr/bin/env python3
"""
Verify elian's listings are restored
"""

import requests
import json

def verify_elian_listings():
    try:
        # Login
        print("🔐 Logging in as elian...")
        login_r = requests.post('http://localhost:5000/api/auth/login', 
                              json={'username': 'elian', 'password': 'elian123'})
        
        if login_r.status_code != 200:
            print(f"❌ Login failed: {login_r.status_code}")
            return
            
        token = login_r.json()['token']
        headers = {'Authorization': f'Bearer {token}', 'Content-Type': 'application/json'}
        
        # Get listings
        print("📋 Getting elian's listings...")
        listings_r = requests.get('http://localhost:5000/api/my_listings', headers=headers)
        
        if listings_r.status_code != 200:
            print(f"❌ Failed to get listings: {listings_r.status_code}")
            return
            
        listings = listings_r.json()
        print(f"✅ Total listings: {len(listings)}")
        
        # Find Toyota cars (original listings)
        toyota_cars = [car for car in listings if 'toyota' in car['brand'].lower()]
        print(f"\\n🚗 Your original Toyota listings ({len(toyota_cars)}):")
        for car in toyota_cars:
            print(f"  ID: {car['id']}, {car['title']} - {car['brand']} {car['model']} ({car['year']}) - ${car['price']}")
        
        # Show all cars
        print(f"\\n📊 All {len(listings)} listings:")
        for car in listings[:10]:  # Show first 10
            print(f"  ID: {car['id']}, {car['title']} - {car['brand']} {car['model']} ({car['year']}) - ${car['price']}")
        
        if len(listings) > 10:
            print(f"  ... and {len(listings) - 10} more")
            
    except Exception as e:
        print(f"❌ Error: {e}")

if __name__ == '__main__':
    verify_elian_listings()
