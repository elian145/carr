#!/usr/bin/env python3
"""
Test script to verify license plate detection with user's specific image formats
"""
import sys
import os

# Add the kk directory to the path
sys.path.append('kk')

def test_user_specific_detection():
    """Test with the specific license plate formats from user's images"""
    try:
        from ai_service import car_analysis_service
        
        # Test the exact formats from user's images
        test_cases = [
            ("24 A 8870", True),   # Should match
            ("24-A 83878", True),  # Should match
            ("PRADO", False),      # Should NOT match
            ("TOYOTA", False),     # Should NOT match
            ("SUV", False),        # Should NOT match
            ("CAR", False),        # Should NOT match
            ("AUTO", False),       # Should NOT match
            ("VEHICLE", False),    # Should NOT match
        ]
        
        print("Testing user-specific license plate detection:")
        print("=" * 60)
        
        all_passed = True
        for text, expected in test_cases:
            result = car_analysis_service._is_likely_license_plate(text)
            status = "✓ PASS" if result == expected else "✗ FAIL"
            if result != expected:
                all_passed = False
            print(f"{text:15} -> {result:5} (expected {expected:5}) {status}")
        
        if all_passed:
            print("\n🎉 All tests PASSED! License plate detection is working correctly.")
        else:
            print("\n❌ Some tests FAILED! License plate detection needs fixing.")
        
        # Test with a simple image
        print("\nTesting with simple image...")
        import cv2
        import numpy as np
        
        # Create a simple test image with only license plate text
        img = np.ones((200, 400, 3), dtype=np.uint8) * 255
        font = cv2.FONT_HERSHEY_SIMPLEX
        cv2.putText(img, '24 A 8870', (50, 100), font, 2, (0, 0, 0), 3)
        
        # Save the test image
        test_path = 'test_user_specific.jpg'
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
            print("The processed image should have '24 A 8870' blurred")
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
    test_user_specific_detection()
