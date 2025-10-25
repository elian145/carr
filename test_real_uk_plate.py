#!/usr/bin/env python3
"""
Test with a real UK license plate format
"""
import sys
import os
import cv2
import numpy as np

# Add the kk directory to the path
sys.path.append('kk')

def test_real_uk_plate():
    """Test with a realistic UK license plate"""
    try:
        from ai_service import car_analysis_service
        
        # Create a realistic test image with UK license plate
        img = np.ones((400, 600, 3), dtype=np.uint8) * 255
        
        # Add a car-like background
        cv2.rectangle(img, (100, 200), (500, 350), (200, 200, 200), -1)  # Car body
        
        # Add UK license plate text (exactly like the user's image)
        font = cv2.FONT_HERSHEY_SIMPLEX
        cv2.putText(img, 'LE75 CFG', (200, 300), font, 1.5, (0, 0, 0), 3)
        
        # Add some other text that should NOT be blurred
        cv2.putText(img, 'KIA', (250, 150), font, 1, (0, 0, 0), 2)
        cv2.putText(img, 'EV9', (250, 180), font, 1, (0, 0, 0), 2)
        
        # Save the test image
        test_path = 'test_real_uk_plate.jpg'
        cv2.imwrite(test_path, img)
        print(f"Created test image: {test_path}")
        
        # Test OCR detection directly
        print("\nTesting OCR detection...")
        if car_analysis_service.ocr_reader:
            results = car_analysis_service.ocr_reader.readtext(img)
            print(f"OCR detected {len(results)} text regions:")
            
            for i, (bbox, text, confidence) in enumerate(results):
                print(f"  {i+1}. Text: '{text}' (confidence: {confidence:.2f})")
                is_plate = car_analysis_service._is_likely_license_plate(text)
                print(f"     -> Is license plate: {is_plate}")
        else:
            print("OCR reader not initialized!")
        
        # Test the full blurring function
        print("\nTesting full blurring function...")
        processed_path = car_analysis_service._blur_license_plates(test_path)
        
        print(f"Original image: {test_path}")
        print(f"Processed image: {processed_path}")
        print(f"Processed file exists: {os.path.exists(processed_path)}")
        
        if os.path.exists(processed_path):
            print("SUCCESS: Blurring test completed")
            print("Check the processed image to see what was blurred")
            
            # Check if the processed image is different (blurred)
            original_size = os.path.getsize(test_path)
            processed_size = os.path.getsize(processed_path)
            print(f"Original size: {original_size} bytes")
            print(f"Processed size: {processed_size} bytes")
            
            if processed_size != original_size:
                print("SUCCESS: Image was modified (likely blurred)")
            else:
                print("WARNING: Image size unchanged - may not have been blurred")
        else:
            print("FAILED: Blurring test failed")
            
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
    test_real_uk_plate()
