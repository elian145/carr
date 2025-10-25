#!/usr/bin/env python3
"""
Test script to verify image upload and processing
"""
import requests
import os
import sys

def test_image_upload():
    """Test uploading an image to the test endpoint"""
    try:
        # Create a simple test image
        import cv2
        import numpy as np
        
        # Create a test image with license plate text
        img = np.ones((200, 400, 3), dtype=np.uint8) * 255
        font = cv2.FONT_HERSHEY_SIMPLEX
        cv2.putText(img, '24 A 8870', (50, 100), font, 1.5, (0, 0, 0), 2)
        
        # Save the test image
        test_path = 'test_upload.jpg'
        cv2.imwrite(test_path, img)
        print(f"Created test image: {test_path}")
        
        # Test the upload endpoint
        url = 'http://localhost:5000/api/process-car-images-test'
        
        with open(test_path, 'rb') as f:
            files = {'images': ('test.jpg', f, 'image/jpeg')}
            response = requests.post(url, files=files)
        
        print(f"Response Status: {response.status_code}")
        print(f"Response Content: {response.text}")
        
        if response.status_code == 200:
            print("SUCCESS: Image upload and processing worked!")
        else:
            print("FAILED: Image upload failed")
            
        # Clean up
        if os.path.exists(test_path):
            os.remove(test_path)
            
    except Exception as e:
        print(f"ERROR: Test failed with error: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    test_image_upload()
