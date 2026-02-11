import sys
sys.path.append('.')
from ai_service import car_analysis_service

print('Model generic:', car_analysis_service.model_is_generic)
print('Has model:', car_analysis_service.license_plate_model is not None)
print('OCR initialized:', car_analysis_service.ocr_reader is not None)

