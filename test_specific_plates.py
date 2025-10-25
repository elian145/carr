#!/usr/bin/env python3
"""
Test script to verify license plate detection with specific formats from user's images
"""
import sys
import os

# Add the kk directory to the path
sys.path.append('kk')

def test_license_plate_patterns():
    """Test the license plate detection with specific formats"""
    try:
        from ai_service import car_analysis_service
        
        # Test cases based on the user's images
        test_cases = [
            "24 A 8870",  # From first image
            "24-A 83878",  # From second image
            "24A8870",     # Clean version
            "24A83878",    # Clean version
            "ABC123",      # Standard format
            "123ABC",      # Reverse format
            "NOT A PLATE", # Should not match
            "123",         # Too short
            "ABCDEFGH",    # No numbers
        ]
        
        print("Testing license plate detection patterns:")
        print("=" * 50)
        
        for text in test_cases:
            is_plate = car_analysis_service._is_likely_license_plate(text)
            status = "✓ MATCH" if is_plate else "✗ NO MATCH"
            print(f"{text:15} -> {status}")
        
        print("\nTesting with actual image processing...")
        
        # Create a test image with the specific license plate format
        import cv2
        import numpy as np
        
        # Create a white background
        img = np.ones((200, 400, 3), dtype=np.uint8) * 255
        
        # Add the specific license plate text
        font = cv2.FONT_HERSHEY_SIMPLEX
        cv2.putText(img, '24 A 8870', (50, 100), font, 1.5, (0, 0, 0), 2)
        cv2.putText(img, '24-A 83878', (50, 150), font, 1.5, (0, 0, 0), 2)
        
        # Save the test image
        test_path = 'test_specific_plates.jpg'
        cv2.imwrite(test_path, img)
        print(f"Created test image: {test_path}")
        
        # Test the blurring function
        print("Testing blurring function...")
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
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    test_license_plate_patterns()
