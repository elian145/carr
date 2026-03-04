#!/usr/bin/env python3
"""
Simulate exactly what the Flutter app does
"""
import requests
import os
import cv2
import numpy as np

def simulate_flutter_app():
    """Simulate the Flutter app's image processing"""
    try:
        # Create a test image with UK license plate (like the Kia)
        img = np.ones((400, 600, 3), dtype=np.uint8) * 255
        font = cv2.FONT_HERSHEY_SIMPLEX
        cv2.putText(img, 'LE75 CFG', (200, 300), font, 1.5, (0, 0, 0), 3)
        cv2.putText(img, 'KIA', (250, 150), font, 1, (0, 0, 0), 2)
        
        test_image_path = 'flutter_simulation_test.jpg'
        cv2.imwrite(test_image_path, img)
        print(f"Created test image: {test_image_path}")
        
        # Step 1: Send image to backend (like Flutter app does)
        url = 'http://localhost:5000/api/process-car-images-test'
        print(f"Step 1: Sending image to backend: {url}")
        
        with open(test_image_path, 'rb') as f:
            files = {'images': f}
            response = requests.post(url, files=files)
        
        print(f"Backend response status: {response.status_code}")
        print(f"Backend response: {response.text}")
        
        if response.status_code == 200:
            result = response.json()
            processed_paths = result.get('processed_images', [])
            print(f"Step 2: Backend returned {len(processed_paths)} processed images")
            
            # Step 3: Download processed images (like Flutter app does)
            for i, processed_path in enumerate(processed_paths):
                image_url = f"http://localhost:5000/static/{processed_path}"
                print(f"Step 3: Downloading processed image from: {image_url}")
                
                img_response = requests.get(image_url)
                print(f"Download response status: {img_response.status_code}")
                print(f"Download response size: {len(img_response.content)} bytes")
                
                if img_response.status_code == 200:
                    # Save locally (like Flutter app does)
                    local_path = f"{test_image_path}_blurred.jpg"
                    with open(local_path, 'wb') as f:
                        f.write(img_response.content)
                    print(f"Step 4: Saved processed image to: {local_path}")
                    print(f"Local file exists: {os.path.exists(local_path)}")
                    print(f"Local file size: {os.path.getsize(local_path)} bytes")
                    
                    # Compare with original
                    original_size = os.path.getsize(test_image_path)
                    processed_size = os.path.getsize(local_path)
                    print(f"Original size: {original_size} bytes")
                    print(f"Processed size: {processed_size} bytes")
                    
                    if processed_size != original_size:
                        print("SUCCESS: Image was modified (likely blurred)")
                    else:
                        print("WARNING: Image size unchanged - may not have been blurred")
                else:
                    print(f"FAILED: Could not download processed image: {img_response.status_code}")
        else:
            print("FAILED: Backend processing failed")
            
        # Clean up
        if os.path.exists(test_image_path):
            os.remove(test_image_path)
        if os.path.exists(f"{test_image_path}_blurred.jpg"):
            os.remove(f"{test_image_path}_blurred.jpg")
            
    except Exception as e:
        print(f"ERROR: Test failed with error: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    simulate_flutter_app()
