#!/usr/bin/env python3
"""
Test license plate blurring directly
"""
import requests
import os
import cv2
import numpy as np

def test_license_plate_blurring():
    """Test license plate blurring with real examples"""
    try:
        # Create test images with both license plate formats
        test_cases = [
            ("LE75 CFG", "UK format"),
            ("24-A 83878", "International format"),
        ]
        
        for license_text, description in test_cases:
            print(f"\n=== Testing {description}: {license_text} ===")
            
            # Create test image
            img = np.ones((400, 600, 3), dtype=np.uint8) * 255
            font = cv2.FONT_HERSHEY_SIMPLEX
            
            # Add license plate text
            cv2.putText(img, license_text, (200, 300), font, 1.5, (0, 0, 0), 3)
            
            # Add some other text that should NOT be blurred
            cv2.putText(img, 'CAR BRAND', (250, 150), font, 1, (0, 0, 0), 2)
            
            test_image_path = f'test_{license_text.replace(" ", "_").replace("-", "_")}.jpg'
            cv2.imwrite(test_image_path, img)
            print(f"Created test image: {test_image_path}")
            
            # Test the backend endpoint
            url = 'http://192.168.1.9:5000/api/process-car-images-test'
            print(f"Testing endpoint: {url}")
            
            with open(test_image_path, 'rb') as f:
                files = {'images': f}
                response = requests.post(url, files=files)
            
            print(f"Response status: {response.status_code}")
            print(f"Response: {response.text}")
            
            if response.status_code == 200:
                result = response.json()
                processed_paths = result.get('processed_images', [])
                print(f"Processed {len(processed_paths)} images")
                
                for processed_path in processed_paths:
                    full_path = f"kk/static/{processed_path}"
                    print(f"Checking: {full_path}")
                    if os.path.exists(full_path):
                        print(f"SUCCESS: Processed image exists")
                        
                        # Compare file sizes
                        original_size = os.path.getsize(test_image_path)
                        processed_size = os.path.getsize(full_path)
                        print(f"Original size: {original_size} bytes")
                        print(f"Processed size: {processed_size} bytes")
                        
                        if processed_size != original_size:
                            print(f"SUCCESS: Image was modified (blurred)")
                        else:
                            print(f"WARNING: Image size unchanged - may not have been blurred")
                    else:
                        print(f"FAILED: Processed image missing")
            else:
                print("Backend processing failed")
            
            # Clean up
            if os.path.exists(test_image_path):
                os.remove(test_image_path)
                
    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    test_license_plate_blurring()
