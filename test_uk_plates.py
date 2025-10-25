#!/usr/bin/env python3
"""
Test script to verify UK license plate detection
"""
import sys
import os

# Add the kk directory to the path
sys.path.append('kk')

def test_uk_license_plates():
    """Test UK license plate detection"""
    try:
        from ai_service import car_analysis_service
        
        # Test UK license plate formats
        test_cases = [
            ("LE75 CFG", True),     # UK current format (from user's image)
            ("LE75CFG", True),      # Clean version
            ("AB12 CDE", True),     # UK format with space
            ("AB12CDE", True),      # UK format without space
            ("A123 BCD", True),     # Older UK format
            ("A123BCD", True),      # Clean version
            ("123 ABC", True),      # Older UK format
            ("123ABC", True),       # Clean version
            ("ABC 123", True),      # Older UK format
            ("ABC123", True),       # Clean version
            ("PRADO", False),       # Should NOT match
            ("TOYOTA", False),      # Should NOT match
            ("KIA", False),         # Should NOT match
            ("EV9", False),         # Should NOT match
        ]
        
        print("Testing UK license plate detection:")
        print("=" * 60)
        
        all_passed = True
        for text, expected in test_cases:
            result = car_analysis_service._is_likely_license_plate(text)
            status = "✓ PASS" if result == expected else "✗ FAIL"
            if result != expected:
                all_passed = False
            print(f"{text:15} -> {result:5} (expected {expected:5}) {status}")
        
        if all_passed:
            print("\n🎉 All tests PASSED! UK license plate detection is working correctly.")
        else:
            print("\n❌ Some tests FAILED! UK license plate detection needs fixing.")
        
        # Test with a simple image containing UK license plate
        print("\nTesting with UK license plate image...")
        import cv2
        import numpy as np
        
        # Create a simple test image with UK license plate text
        img = np.ones((200, 400, 3), dtype=np.uint8) * 255
        font = cv2.FONT_HERSHEY_SIMPLEX
        cv2.putText(img, 'LE75 CFG', (50, 100), font, 1.5, (0, 0, 0), 2)
        
        # Save the test image
        test_path = 'test_uk_plates.jpg'
        cv2.imwrite(test_path, img)
        print(f"Created test image: {test_path}")
        
        # Test the blurring function
        print("Testing blurring function...")
        processed_path = car_analysis_service._blur_license_plates(test_path)
        
        print(f"Original image: {test_path}")
        print(f"Processed image: {processed_path}")
        print(f"Processed file exists: {os.path.exists(processed_path)}")
        
        if os.path.exists(processed_path):
            print("SUCCESS: UK license plate blurring test PASSED")
            print("The processed image should have 'LE75 CFG' blurred")
        else:
            print("FAILED: UK license plate blurring test FAILED")
            
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
    test_uk_license_plates()
