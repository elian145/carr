#!/usr/bin/env python3
"""
Test if Flutter app can reach the backend
"""
import requests

def test_connectivity():
    """Test connectivity from Flutter app perspective"""
    try:
        # Test the exact URL that Flutter app would use
        url = 'http://10.0.2.2:5000/api/process-car-images-test'
        print(f"Testing Flutter connectivity to: {url}")
        
        # Test with a simple GET request first
        try:
            response = requests.get('http://10.0.2.2:5000/api/test-ai')
            print(f"Test AI endpoint: {response.status_code}")
            print(f"Response: {response.text}")
        except Exception as e:
            print(f"Test AI endpoint failed: {e}")
        
        # Test the process endpoint with a simple request
        try:
            # Create a minimal test image
            import cv2
            import numpy as np
            img = np.ones((100, 200, 3), dtype=np.uint8) * 255
            cv2.putText(img, 'TEST', (50, 50), cv2.FONT_HERSHEY_SIMPLEX, 1, (0, 0, 0), 2)
            cv2.imwrite('test_connectivity.jpg', img)
            
            with open('test_connectivity.jpg', 'rb') as f:
                files = {'images': f}
                response = requests.post(url, files=files)
            
            print(f"Process endpoint: {response.status_code}")
            print(f"Response: {response.text}")
            
            # Clean up
            import os
            if os.path.exists('test_connectivity.jpg'):
                os.remove('test_connectivity.jpg')
                
        except Exception as e:
            print(f"Process endpoint failed: {e}")
            
    except Exception as e:
        print(f"Connectivity test failed: {e}")

if __name__ == "__main__":
    test_connectivity()
