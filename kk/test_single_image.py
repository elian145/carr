"""
Quick test script to check license plate detection on a single image
Usage: python test_single_image.py <path_to_image>
"""
import sys
import os
sys.path.insert(0, os.path.dirname(__file__))

from ai_service import CarAnalysisService

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python test_single_image.py <path_to_image>")
        sys.exit(1)
    
    image_path = sys.argv[1]
    
    if not os.path.exists(image_path):
        print(f"Error: Image not found: {image_path}")
        sys.exit(1)
    
    print(f"\n{'='*60}")
    print(f"Testing license plate detection on: {image_path}")
    print(f"{'='*60}\n")
    
    # Initialize service
    service = CarAnalysisService()
    
    # Process image
    result_path = service._blur_license_plates(image_path)
    
    print(f"\n{'='*60}")
    print(f"Processing complete!")
    print(f"Result saved to: {result_path}")
    print(f"{'='*60}\n")

