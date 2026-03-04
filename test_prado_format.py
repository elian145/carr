#!/usr/bin/env python3
"""
Test Prado license plate format detection
"""
import sys
sys.path.append('kk')

from ai_service import car_analysis_service

# Test various formats that OCR might detect
test_cases = [
    "24-A 83878",
    "24A83878",
    "24 A 83878",
    "24-A83878",
    "24A 83878",
    "LE75 CFG",
    "LE75CFG",
]

print("Testing license plate detection patterns:")
print("=" * 50)

for text in test_cases:
    result = car_analysis_service._is_likely_license_plate(text)
    status = "✓ MATCH" if result else "✗ NO MATCH"
    print(f"{text:20} -> {status}")

