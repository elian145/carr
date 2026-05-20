#!/usr/bin/env python3
"""
Test the backend endpoint directly
"""
import requests
import os

def test_backend_endpoint():
    """Test the backend image processing endpoint directly"""
    try:
        # Test the backend endpoint
        url = 'http://localhost:5000/api/process-car-images-test'
        
        # Create a test image
        import cv2
        import numpy as np
        
        img = np.ones((400, 600, 3), dtype=np.uint8) * 255
        font = cv2.FONT_HERSHEY_SIMPLEX
        cv2.putText(img, 'LE75 CFG', (200, 300), font, 1.5, (0, 0, 0), 3)
        cv2.putText(img, 'KIA', (250, 150), font, 1, (0, 0, 0), 2)
        
        test_image_path = 'test_backend.jpg'
        cv2.imwrite(test_image_path, img)
        print(f"Created test image: {test_image_path}")
        
        # Test the endpoint
        with open(test_image_path, 'rb') as f:
            files = {'images': f}
            response = requests.post(url, files=files)
        
        print(f"Response status: {response.status_code}")
        print(f"Response body: {response.text}")
        
        if response.status_code == 200:
            result = response.json()
            print(f"Processed images: {result.get('processed_images', [])}")
            
            # Check if processed images exist
            for processed_path in result.get('processed_images', []):
                # Processed paths are relative to the static root (kk/static/...)
                full_path = f"kk/static/{processed_path}"
                print(f"Checking: {full_path}")
                if os.path.exists(full_path):
                    print(f"SUCCESS: Processed image exists: {full_path}")
                else:
                    print(f"FAILED: Processed image missing: {full_path}")
        else:
            print("Backend endpoint failed")
            
        # Clean up
        if os.path.exists(test_image_path):
            os.remove(test_image_path)
            
    except Exception as e:
        print(f"ERROR: Test failed with error: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    test_backend_endpoint()
