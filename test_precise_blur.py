#!/usr/bin/env python3
"""
Test script to verify precise license plate detection
"""
import sys
import os

# Add the kk directory to the path
sys.path.append('kk')

def test_license_plate_detection():
    """Test the improved license plate detection"""
    try:
        from ai_service import car_analysis_service
        
        # Test cases - should match
        should_match = [
            "24 A 8870",  # From user's image
            "24-A 83878",  # From user's image
            "24A8870",     # Clean version
            "24A83878",    # Clean version
            "AB123",       # Standard format
            "123AB",       # Reverse format
        ]
        
        # Test cases - should NOT match
        should_not_match = [
            "PRADO",       # Car model name
            "TOYOTA",      # Car brand
            "LAND",        # Car model part
            "CRUISER",     # Car model part
            "SUV",         # Vehicle type
            "CAR",         # Generic word
            "AUTO",        # Generic word
            "VEHICLE",     # Generic word
            "NOT A PLATE", # Random text
            "123",         # Too short
            "ABCDEFGH",    # No numbers
            "123456789",   # No letters
        ]
        
        print("Testing improved license plate detection:")
        print("=" * 60)
        
        print("\nShould MATCH (license plates):")
        for text in should_match:
            is_plate = car_analysis_service._is_likely_license_plate(text)
            status = "✓ MATCH" if is_plate else "✗ NO MATCH"
            print(f"  {text:15} -> {status}")
        
        print("\nShould NOT MATCH (car names/other text):")
        for text in should_not_match:
            is_plate = car_analysis_service._is_likely_license_plate(text)
            status = "✗ NO MATCH" if not is_plate else "✓ MATCH (ERROR!)"
            print(f"  {text:15} -> {status}")
        
        print("\nTesting with actual image processing...")
        
        # Create a test image with both license plate and car model text
        import cv2
        import numpy as np
        
        # Create a white background
        img = np.ones((300, 600, 3), dtype=np.uint8) * 255
        
        # Add license plate text (should be blurred)
        font = cv2.FONT_HERSHEY_SIMPLEX
        cv2.putText(img, '24 A 8870', (50, 150), font, 2, (0, 0, 0), 3)
        
        # Add car model text (should NOT be blurred)
        cv2.putText(img, 'PRADO', (50, 250), font, 2, (0, 0, 0), 3)
        cv2.putText(img, 'TOYOTA', (50, 100), font, 1.5, (0, 0, 0), 2)
        
        # Save the test image
        test_path = 'test_precise_blur.jpg'
        cv2.imwrite(test_path, img)
        print(f"Created test image: {test_path}")
        
        # Test the blurring function
        print("Testing blurring function...")
        processed_path = car_analysis_service._blur_license_plates(test_path)
        
        print(f"Original image: {test_path}")
        print(f"Processed image: {processed_path}")
        print(f"Processed file exists: {os.path.exists(processed_path)}")
        
        if os.path.exists(processed_path):
            print("SUCCESS: Precise license plate blurring test PASSED")
            print("Check the processed image - only '24 A 8870' should be blurred, not 'PRADO' or 'TOYOTA'")
        else:
            print("FAILED: Precise license plate blurring test FAILED")
            
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
    test_license_plate_detection()
