#!/usr/bin/env python3
"""
Test script to verify license plate blurring functionality
"""
import cv2
import numpy as np
import os
import sys

# Add the kk directory to the path
sys.path.append('kk')

def create_test_image():
    """Create a test image with text that looks like a license plate"""
    # Create a white background
    img = np.ones((200, 400, 3), dtype=np.uint8) * 255
    
    # Add some text that looks like a license plate
    font = cv2.FONT_HERSHEY_SIMPLEX
    cv2.putText(img, 'ABC123', (50, 100), font, 2, (0, 0, 0), 3)
    cv2.putText(img, 'XYZ789', (50, 150), font, 2, (0, 0, 0), 3)
    
    # Save the test image
    test_path = 'test_license_plate.jpg'
    cv2.imwrite(test_path, img)
    print(f"Created test image: {test_path}")
    return test_path

def test_blur_function():
    """Test the license plate blurring function"""
    try:
        from ai_service import car_analysis_service
        
        # Create test image
        test_path = create_test_image()
        
        print("Testing license plate blurring...")
        processed_path = car_analysis_service._blur_license_plates(test_path)
        
        print(f"Original image: {test_path}")
        print(f"Processed image: {processed_path}")
        print(f"Processed file exists: {os.path.exists(processed_path)}")
        
        if os.path.exists(processed_path):
            print("SUCCESS: License plate blurring test PASSED")
        else:
            print("FAILED: License plate blurring test FAILED")
            
        # Clean up
        if os.path.exists(test_path):
            os.remove(test_path)
        if os.path.exists(processed_path):
            os.remove(processed_path)
            
    except Exception as e:
        print(f"ERROR: Test failed with error: {e}")

if __name__ == "__main__":
    test_blur_function()
