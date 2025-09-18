#!/usr/bin/env python3
"""
Test the api.py server with elian's data
"""

import requests
import json

def test_api_server():
    try:
        print("🔍 Testing api.py server...")
        
        # Test login
        login_r = requests.post('http://localhost:5000/api/auth/login', 
                              json={'username': 'elian', 'password': 'elian123'})
        print(f"Login status: {login_r.status_code}")
        
        if login_r.status_code == 200:
            token = login_r.json()['token']
            headers = {'Authorization': f'Bearer {token}'}
            
            # Test listings
            listings_r = requests.get('http://localhost:5000/api/my_listings', headers=headers)
            print(f"Listings status: {listings_r.status_code}")
            
            if listings_r.status_code == 200:
                listings = listings_r.json()
                print(f"Number of listings: {len(listings)}")
                
                print("\\n🚗 Elian's listings:")
                for car in listings:
                    print(f"  - {car['title']} - {car['brand']} {car['model']} ({car['year']}) - ${car['price']}")
            else:
                print(f"Listings error: {listings_r.text}")
                
            # Test favorites
            favorites_r = requests.get('http://localhost:5000/api/favorites', headers=headers)
            print(f"\\nFavorites status: {favorites_r.status_code}")
            
            if favorites_r.status_code == 200:
                favorites = favorites_r.json()
                print(f"Number of favorites: {len(favorites)}")
                
                print("\\n❤️  Elian's favorites:")
                for fav in favorites:
                    print(f"  - {fav['title']} - {fav['brand']} {fav['model']}")
            else:
                print(f"Favorites error: {favorites_r.text}")
        else:
            print(f"Login error: {login_r.text}")
            
    except Exception as e:
        print(f"❌ Error: {e}")

if __name__ == '__main__':
    test_api_server()
