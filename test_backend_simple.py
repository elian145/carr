#!/usr/bin/env python3
"""
Simple test to verify backend is working
"""
import requests
import os
import cv2
import numpy as np

def test_backend_simple():
    """Simple test of the backend"""
    try:
        # Create a simple test image
        img = np.ones((200, 400, 3), dtype=np.uint8) * 255
        font = cv2.FONT_HERSHEY_SIMPLEX
        cv2.putText(img, 'LE75 CFG', (50, 100), font, 1, (0, 0, 0), 2)
        
        test_image_path = 'simple_test.jpg'
        cv2.imwrite(test_image_path, img)
        print(f"Created test image: {test_image_path}")
        
        # Test the backend
        url = 'http://localhost:5000/api/process-car-images-test'
        print(f"Testing: {url}")
        
        with open(test_image_path, 'rb') as f:
            files = {'images': f}
            response = requests.post(url, files=files)
        
        print(f"Status: {response.status_code}")
        print(f"Response: {response.text}")
        
        if response.status_code == 200:
            result = response.json()
            processed_paths = result.get('processed_images', [])
            print(f"Processed {len(processed_paths)} images")
            
            for processed_path in processed_paths:
                full_path = f"kk/static/{processed_path}"
                print(f"Checking: {full_path}")
                if os.path.exists(full_path):
                    print(f"SUCCESS: File exists")
                    # Test HTTP access
                    image_url = f"http://localhost:5000/static/{processed_path}"
                    img_response = requests.get(image_url)
                    print(f"HTTP access: {img_response.status_code}")
                    print(f"Image size: {len(img_response.content)} bytes")
                else:
                    print(f"FAILED: File missing")
        else:
            print("Backend error")
            
        # Clean up
        if os.path.exists(test_image_path):
            os.remove(test_image_path)
            
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    test_backend_simple()
