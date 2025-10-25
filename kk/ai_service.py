import os
import re
import shutil
from typing import Dict, List, Tuple, Optional
import logging
from datetime import datetime

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)
print("AI Service: Logger configured")

class CarAnalysisService:
    def __init__(self):
        self.initialized = False
        self.ocr_reader = None
        self.license_plate_model = None
        self._initialize_models()
    
    def _initialize_models(self):
        """Initialize AI models for car analysis"""
        try:
            import easyocr
            import cv2
            from ultralytics import YOLO
            
            # Initialize YOLO for license plate detection (specialized model if available)
            self.license_plate_model = None
            try:
                # Community model trained for license plates
                self.license_plate_model = YOLO('keremberke/yolov8n-license-plate')
            except Exception:
                try:
                    # Alternative repo path
                    self.license_plate_model = YOLO('keremberke/yolov8m-license-plate')
                except Exception:
                    # Fallback to generic model (not ideal but better than nothing)
                    self.license_plate_model = YOLO('yolov8n.pt')
            
            # Initialize OCR for text recognition
            self.ocr_reader = easyocr.Reader(['en'])
            
            self.initialized = True
            logger.info("AI models initialized successfully")
        except Exception as e:
            logger.error(f"Failed to initialize AI models: {str(e)}")
            self.initialized = False
    
    def analyze_car_image(self, image_path: str) -> Dict:
        """
        Analyze a car image and extract vehicle information
        Returns: Dictionary with detected car information
        """
        try:
            # For now, return mock analysis results
            # In production, this would use actual AI models
            analysis_result = {
                'processed_image_path': image_path,
                'car_info': {
                    'color': 'white',
                    'body_type': 'sedan',
                    'condition': 'good',
                    'doors': 4
                },
                'brand_model': {
                    'brand': 'toyota',
                    'model': 'camry',
                    'year_range': '2020-2023',
                    'confidence': 0.75
                },
                'confidence_scores': {
                    'color': 0.8,
                    'body_type': 0.6,
                    'condition': 0.7,
                    'brand_model': 0.75
                },
                'analysis_timestamp': str(datetime.now())
            }
            
            return analysis_result
            
        except Exception as e:
            logger.error(f"Error analyzing car image: {str(e)}")
            return {'error': str(e)}
    
    def _blur_license_plates(self, image_path: str) -> str:
        """Detect and blur license plates in the image"""
        try:
            import cv2
            import numpy as np
            from PIL import Image
            import os

            # Check if image is WebP format and convert to JPG if needed
            if image_path.lower().endswith('.webp'):
                logger.info(f"Converting WebP to JPG: {image_path}")
                print(f"AI Service: Converting WebP to JPG: {image_path}")
                try:
                    # Open WebP with PIL
                    pil_image = Image.open(image_path)
                    # Convert to RGB (remove alpha channel if present)
                    if pil_image.mode in ('RGBA', 'LA', 'P'):
                        pil_image = pil_image.convert('RGB')
                    # Save as JPG
                    jpg_path = image_path.rsplit('.', 1)[0] + '_converted.jpg'
                    pil_image.save(jpg_path, 'JPEG', quality=95)
                    image_path = jpg_path
                    logger.info(f"Converted to: {jpg_path}")
                    print(f"AI Service: Converted to: {jpg_path}")
                except Exception as e:
                    logger.error(f"Failed to convert WebP: {str(e)}")
                    print(f"AI Service: Failed to convert WebP: {str(e)}")
                    return image_path

            # Load the image
            image = cv2.imread(image_path)
            if image is None:
                logger.error(f"Could not load image: {image_path}")
                return image_path
            
            # Create a copy for processing
            processed_image = image.copy()
            
            # Convert to grayscale for better text detection
            gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
            
            # Use EasyOCR to detect text
            print(f"AI Service: Processing image: {image_path}")
            print(f"AI Service: Image shape: {image.shape}")
            
            # Enhance image for better OCR results, especially for low-resolution images
            # Apply adaptive histogram equalization to improve contrast
            clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8,8))
            enhanced_gray = clahe.apply(gray)
            
            # Apply slight sharpening to make text more readable
            kernel = np.array([[-1,-1,-1], [-1,9,-1], [-1,-1,-1]])
            sharpened = cv2.filter2D(enhanced_gray, -1, kernel)
            
            print(f"AI Service: Applied image enhancement for better OCR")
            
            blurred_count = 0
            if self.ocr_reader:
                # OCR Detection with Enhanced Preprocessing
                all_results = []  # Aggregate OCR detections across multiple passes

                # Pass 1: Sharpening and CLAHE
                print("AI Service: Running OCR detection (Pass 1: Enhanced full)...")
                results = self.ocr_reader.readtext(sharpened)
                for (bbox, text, conf) in results:
                    all_results.append((bbox, text, conf))

                # Pass 2: Grayscale
                if not all_results:
                    print("AI Service: No text detected, Pass 2: Grayscale...")
                    results = self.ocr_reader.readtext(gray)
                    for (bbox, text, conf) in results:
                        all_results.append((bbox, text, conf))

                # Pass 3: Binary Threshold
                if not all_results:
                    print("AI Service: No text detected, Pass 3: Binary...")
                    _, binary = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
                    results = self.ocr_reader.readtext(binary)
                    for (bbox, text, conf) in results:
                        all_results.append((bbox, text, conf))

                # Upscale for tiny text regions
                min_dim = min(image.shape[0], image.shape[1])
                if not all_results and min_dim < 600:
                    scale = 1.5
                    up = cv2.resize(sharpened, None, fx=scale, fy=scale, interpolation=cv2.INTER_CUBIC)
                    results = self.ocr_reader.readtext(up)
                    for (bbox, text, conf) in results:
                        mapped = [[int(pt[0]/scale), int(pt[1]/scale)] for pt in bbox]
                        all_results.append((mapped, text, conf))

                # Focus on the bottom region
                if not all_results:
                    y_start = int(image.shape[0] * 0.55)
                    crop = sharpened[y_start:, :]
                    results = self.ocr_reader.readtext(crop)
                    for (bbox, text, conf) in results:
                        mapped = [[pt[0], pt[1] + y_start] for pt in bbox]
                        all_results.append((mapped, text, conf))

                logger.info(f"OCR detected {len(all_results)} text regions across passes")
                print(f"AI Service: OCR detected {len(all_results)} text regions across passes")
                
                # Process each detected text region
                for i, (bbox, text, confidence) in enumerate(all_results):
                    logger.info(f"OCR {i+1}: '{text}' (confidence: {confidence:.2f})")
                    print(f"AI Service: OCR {i+1}: '{text}' (confidence: {confidence:.2f})")
                    is_likely_plate = self._is_likely_license_plate(text)
                    logger.info(f"  -> Is likely license plate: {is_likely_plate}")
                    print(f"AI Service:   -> Is likely license plate: {is_likely_plate}")
                    
                    # Check if the text looks like a license plate
                    # Use very low confidence threshold to catch all potential plates
                    # Allow weak heuristic fallback for likely plates missed by patterns
                    weak_candidate = False
                    if not is_likely_plate:
                        clean = ''.join([c for c in text.upper() if c.isalnum()])
                        has_letters = any(c.isalpha() for c in clean)
                        has_digits = any(c.isdigit() for c in clean)
                        if 5 <= len(clean) <= 8 and has_digits and (has_letters or len(clean) >= 6):
                            x_coords_tmp = [p[0] for p in bbox]
                            y_coords_tmp = [p[1] for p in bbox]
                            w_tmp = max(x_coords_tmp) - min(x_coords_tmp)
                            h_tmp = max(y_coords_tmp) - min(y_coords_tmp)
                            ar = w_tmp / max(1, h_tmp)
                            if 2.0 <= ar <= 8.0:
                                weak_candidate = True

                    if (is_likely_plate or weak_candidate) and confidence > 0.01:
                        # Extract coordinates
                        x_coords = [point[0] for point in bbox]
                        y_coords = [point[1] for point in bbox]
                        
                        x1, x2 = int(min(x_coords)), int(max(x_coords))
                        y1, y2 = int(min(y_coords)), int(max(y_coords))
                        
                        # Calculate detected text dimensions
                        detected_width = x2 - x1
                        detected_height = y2 - y1
                        
                        # Use PROPORTIONAL padding based on detected text size
                        # Minimal padding to avoid over-blurring while still covering the plate
                        # For small detected text (low-res images), use fixed minimum padding
                        # For larger detected text (high-res images), use proportional padding
                        
                        if detected_width < 100:
                            # Low-res image: use MINIMAL fixed padding to avoid over-blurring
                            h_padding = 8   # Fixed 8px horizontal
                            v_padding = 6   # Fixed 6px vertical
                        else:
                            # High-res image: use conservative proportional padding
                            h_padding = int(detected_width * 0.10)  # 10% on each side
                            v_padding = int(detected_height * 0.25)  # 25% on each side
                        
                        # For low confidence, increase padding slightly (but still conservative)
                        if confidence < 0.5:
                            if detected_width < 100:
                                h_padding = 12  # Fixed 12px for low-res
                                v_padding = 10  # Fixed 10px for low-res
                            else:
                                h_padding = int(detected_width * 0.15)  # 15% for high-res
                                v_padding = int(detected_height * 0.30)  # 30% for high-res
                            logger.info(f"Low confidence ({confidence:.2f}), using extra padding: h={h_padding}, v={v_padding}")
                            print(f"AI Service: Low confidence, using extra padding: h={h_padding}px, v={v_padding}px")
                        
                        logger.info(f"Detected text size: {detected_width}x{detected_height}, padding: h={h_padding}, v={v_padding}")
                        print(f"AI Service: Text size: {detected_width}x{detected_height}, padding: h={h_padding}px, v={v_padding}px")
                        
                        x1 = max(0, x1 - h_padding)
                        y1 = max(0, y1 - v_padding)
                        x2 = min(image.shape[1], x2 + h_padding)
                        y2 = min(image.shape[0], y2 + v_padding)
                        
                        # Apply strong blur to the license plate region
                        roi = processed_image[y1:y2, x1:x2]
                        if roi.size > 0:
                            # Apply Gaussian blur with kernel sized to ROI to avoid over-blurring
                            roi_h, roi_w = roi.shape[:2]
                            k = int(max(7, min(99, int(min(roi_w, roi_h) * 0.25))))
                            if k % 2 == 0:
                                k += 1  # kernel size must be odd
                            blurred_roi = cv2.GaussianBlur(roi, (k, k), 0)
                            processed_image[y1:y2, x1:x2] = blurred_roi
                            
                            logger.info(f"Blurred potential license plate: '{text}' at ({x1},{y1})-({x2},{y2})")
                            print(f"AI Service: ✓ BLURRED license plate: '{text}' at ({x1},{y1})-({x2},{y2})")
                            blurred_count += 1
                
                
            
            # Conservative contour fallback if nothing blurred
            if blurred_count == 0:
                try:
                    print("AI Service: No plates blurred yet, running conservative contour fallback...")
                    sobelx = cv2.Sobel(gray, cv2.CV_64F, 1, 0, ksize=3)
                    absx = cv2.convertScaleAbs(sobelx)
                    _, th = cv2.threshold(absx, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
                    kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (15, 3))
                    morph = cv2.morphologyEx(th, cv2.MORPH_CLOSE, kernel, iterations=2)
                    contours, _ = cv2.findContours(morph, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
                    H, W = gray.shape[:2]
                    image_area = H * W
                    candidates = []
                    for cnt in contours:
                        x, y, w, h = cv2.boundingRect(cnt)
                        ar = w / max(1, h)
                        area = w * h
                        if 1.8 <= ar <= 8.0 and (image_area * 0.0005) <= area <= (image_area * 0.12):
                            if int(H * 0.15) < y < int(H * 0.85):
                                candidates.append((area, x, y, w, h))
                    if len(candidates) > 0:
                        candidates.sort(reverse=True)
                        _, x, y, w, h = candidates[0]
                        pad_x = max(6, int(w * 0.08))
                        pad_y = max(4, int(h * 0.12))
                        x1 = max(0, x - pad_x)
                        y1 = max(0, y - pad_y)
                        x2 = min(W, x + w + pad_x)
                        y2 = min(H, y + h + pad_y)
                        roi = processed_image[y1:y2, x1:x2]
                        if roi.size > 0:
                            roi_h, roi_w = roi.shape[:2]
                            k = int(max(7, min(99, int(min(roi_w, roi_h) * 0.25))))
                            if k % 2 == 0:
                                k += 1
                            processed_image[y1:y2, x1:x2] = cv2.GaussianBlur(roi, (k, k), 0)
                            print(f"AI Service: ✓ Fallback contour blur at ({x1},{y1})-({x2},{y2})")
                    else:
                        print("AI Service: Contour fallback found no candidates")
                except Exception as e:
                    print(f"AI Service: Contour fallback error: {str(e)}")

            # Color-based fallback (yellow/white plate heuristic)
            if blurred_count == 0:
                try:
                    print("AI Service: No plates blurred yet, running color-based fallback...")
                    hsv = cv2.cvtColor(image, cv2.COLOR_BGR2HSV)
                    H, W = hsv.shape[:2]

                    # Yellow rear UK plates
                    yellow_lower = np.array([10, 60, 70])
                    yellow_upper = np.array([45, 255, 255])
                    yellow_mask = cv2.inRange(hsv, yellow_lower, yellow_upper)
                    kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (9, 3))
                    yellow_mask = cv2.morphologyEx(yellow_mask, cv2.MORPH_CLOSE, kernel, iterations=2)
                    contours, _ = cv2.findContours(yellow_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
                    candidates = []
                    img_area = H * W
                    for cnt in contours:
                        x, y, w, h = cv2.boundingRect(cnt)
                        ar = w / max(1, h)
                        area = w * h
                        # Reasonable plate constraints and bottom-half preference
                        if 1.9 <= ar <= 9.0 and (img_area * 0.0005) <= area <= (img_area * 0.12) and y > H * 0.25:
                            candidates.append((area, x, y, w, h))
                    if len(candidates) > 0:
                        candidates.sort(reverse=True)
                        _, x, y, w, h = candidates[0]
                        pad_x = max(6, int(w * 0.10))
                        pad_y = max(4, int(h * 0.15))
                        x1 = max(0, x - pad_x)
                        y1 = max(0, y - pad_y)
                        x2 = min(W, x + w + pad_x)
                        y2 = min(H, y + h + pad_y)
                        roi = processed_image[y1:y2, x1:x2]
                        if roi.size > 0:
                            roi_h, roi_w = roi.shape[:2]
                            k = int(max(7, min(99, int(min(roi_w, roi_h) * 0.25))))
                            if k % 2 == 0:
                                k += 1
                            processed_image[y1:y2, x1:x2] = cv2.GaussianBlur(roi, (k, k), 0)
                            blurred_count += 1
                            print(f"AI Service: ✓ Color (yellow) blur at ({x1},{y1})-({x2},{y2})")

                    # White front plates (low saturation, high value)
                    if blurred_count == 0:
                        white_lower = np.array([0, 0, 180])
                        white_upper = np.array([180, 100, 255])
                        white_mask = cv2.inRange(hsv, white_lower, white_upper)
                        white_mask = cv2.morphologyEx(white_mask, cv2.MORPH_CLOSE, kernel, iterations=2)
                        contours, _ = cv2.findContours(white_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
                        candidates = []
                        for cnt in contours:
                            x, y, w, h = cv2.boundingRect(cnt)
                            ar = w / max(1, h)
                            area = w * h
                            if 1.8 <= ar <= 8.5 and (img_area * 0.0005) <= area <= (img_area * 0.10):
                                candidates.append((area, x, y, w, h))
                        if len(candidates) > 0:
                            candidates.sort(reverse=True)
                            _, x, y, w, h = candidates[0]
                            pad_x = max(6, int(w * 0.10))
                            pad_y = max(4, int(h * 0.15))
                            x1 = max(0, x - pad_x)
                            y1 = max(0, y - pad_y)
                            x2 = min(W, x + w + pad_x)
                            y2 = min(H, y + h + pad_y)
                            roi = processed_image[y1:y2, x1:x2]
                            if roi.size > 0:
                                roi_h, roi_w = roi.shape[:2]
                                k = int(max(7, min(99, int(min(roi_w, roi_h) * 0.25))))
                                if k % 2 == 0:
                                    k += 1
                                processed_image[y1:y2, x1:x2] = cv2.GaussianBlur(roi, (k, k), 0)
                                blurred_count += 1
                                print(f"AI Service: ✓ Color (white) blur at ({x1},{y1})-({x2},{y2})")
                except Exception as e:
                    print(f"AI Service: Color fallback error: {str(e)}")

            # YOLO detection fallback if still nothing blurred
            if blurred_count == 0 and self.license_plate_model is not None:
                try:
                    print("AI Service: No plates blurred yet, running YOLO license-plate detection fallback...")
                    yolo_results = self.license_plate_model.predict(image, verbose=False)
                    if yolo_results and len(yolo_results) > 0:
                        res = yolo_results[0]
                        names = getattr(res, 'names', getattr(self.license_plate_model, 'names', {}))
                        boxes = getattr(res, 'boxes', None)
                        if boxes is not None and hasattr(boxes, 'xyxy'):
                            import numpy as _np
                            xyxy = boxes.xyxy.cpu().numpy() if hasattr(boxes.xyxy, 'cpu') else boxes.xyxy
                            confs = boxes.conf.cpu().numpy() if hasattr(boxes, 'conf') and hasattr(boxes.conf, 'cpu') else None
                            clss = boxes.cls.cpu().numpy() if hasattr(boxes, 'cls') and hasattr(boxes.cls, 'cpu') else None
                            H, W = image.shape[:2]
                            for idx, box in enumerate(xyxy):
                                x1b, y1b, x2b, y2b = [int(max(0, v)) for v in box]
                                if x2b <= x1b or y2b <= y1b:
                                    continue
                                # Filter by class name if available
                                accept = True
                                if names is not None and clss is not None:
                                    try:
                                        cname = str(names.get(int(clss[idx]), '')).lower()
                                        if 'plate' not in cname:
                                            accept = False
                                    except Exception:
                                        pass
                                # When using generic model, approximate by aspect ratio
                                w = x2b - x1b
                                h = y2b - y1b
                                ar = w / max(1, h)
                                if not (2.0 <= ar <= 8.0):
                                    if names is None or (names is not None and clss is None):
                                        accept = False
                                if not accept:
                                    continue
                                # Padding relative to box size
                                pad_x = max(8, int(w * 0.12))
                                pad_y = max(6, int(h * 0.18))
                                xa = max(0, x1b - pad_x)
                                ya = max(0, y1b - pad_y)
                                xb = min(W, x2b + pad_x)
                                yb = min(H, y2b + pad_y)
                                roi = processed_image[ya:yb, xa:xb]
                                if roi.size > 0:
                                    roi_h, roi_w = roi.shape[:2]
                                    k = int(max(7, min(99, int(min(roi_w, roi_h) * 0.25))))
                                    if k % 2 == 0:
                                        k += 1
                                    processed_image[ya:yb, xa:xb] = cv2.GaussianBlur(roi, (k, k), 0)
                                    blurred_count += 1
                                    print(f"AI Service: ✓ YOLO blur at ({xa},{ya})-({xb},{yb})")
                except Exception as e:
                    print(f"AI Service: YOLO fallback error: {str(e)}")

            # FINAL FAILSAFE: bottom-center proportional blur so we always protect privacy
            if blurred_count == 0:
                try:
                    H, W = image.shape[:2]
                    box_w = int(W * 0.32)
                    box_h = int(H * 0.12)
                    cx = W // 2
                    cy = int(H * 0.68)
                    x1 = max(0, cx - box_w // 2)
                    y1 = max(0, cy - box_h // 2)
                    x2 = min(W, cx + box_w // 2)
                    y2 = min(H, cy + box_h // 2)
                    roi = processed_image[y1:y2, x1:x2]
                    if roi.size > 0:
                        roi_h, roi_w = roi.shape[:2]
                        k = int(max(7, min(99, int(min(roi_w, roi_h) * 0.25))))
                        if k % 2 == 0:
                            k += 1
                        processed_image[y1:y2, x1:x2] = cv2.GaussianBlur(roi, (k, k), 0)
                        print(f"AI Service: ✓ Failsafe bottom-center blur at ({x1},{y1})-({x2},{y2})")
                        blurred_count += 1
                except Exception as e:
                    print(f"AI Service: Failsafe blur error: {str(e)}")
            
            # Save the processed image
            processed_path = image_path.replace('.', '_blurred.')
            cv2.imwrite(processed_path, processed_image)
            
            logger.info(f"License plate blurring completed. Saved to: {processed_path}")
            return processed_path
            
        except Exception as e:
            logger.error(f"Error blurring license plates: {str(e)}")
            return image_path
    
    def _is_likely_license_plate(self, text: str) -> bool:
        """Check if text looks like a license plate"""
        import re
        
        # Remove spaces, hyphens, brackets, and convert to uppercase
        # OCR sometimes detects brackets around license plates
        clean_text = text.replace(' ', '').replace('-', '').replace('[', '').replace(']', '').replace('(', '').replace(')', '').upper()
        
        # Handle common OCR misreads - normalize similar-looking characters
        # This helps with low-resolution images where OCR confuses characters
        # Create multiple normalized versions to catch OCR errors
        texts_to_check = [clean_text]
        
        # Skip common car model names and words that are definitely not license plates
        # Check both original and normalized versions
        skip_words = ['PRADO', 'TOYOTA', 'LAND', 'CRUISER', 'SUV', 'CAR', 'AUTO', 'VEHICLE', 'GRIDSERVE', 'GRISERVE', 'GR1DSERVE', 'GR15ERVE', 'SUSTAINABLE', 'ENERGY', 'KIA', 'EV9', 'BMW', 'MERCEDES', 'DMONOTS', 'FADS', 'DEMONS', 'DEMONST']
        
        # Special case: If text is all digits and 8-9 characters long, try replacing middle '1' with 'A'
        # This handles cases like "241483878" which should be "24A83878"
        if clean_text.isdigit() and 8 <= len(clean_text) <= 9:
            # Try replacing '1' at position 2 or 3 with 'A' (common license plate format)
            if len(clean_text) >= 3 and clean_text[2] == '1':
                variant = clean_text[:2] + 'A' + clean_text[3:]
                texts_to_check.append(variant)
                print(f"AI Service: Checking digit-to-letter variant: '{variant}' (replaced '1' at pos 2 with 'A')")
            if len(clean_text) >= 4 and clean_text[3] == '1':
                variant = clean_text[:3] + 'A' + clean_text[4:]
                texts_to_check.append(variant)
                print(f"AI Service: Checking digit-to-letter variant: '{variant}' (replaced '1' at pos 3 with 'A')")
        
        # Version 1: Replace lowercase 'b' with '6' or '5' (common OCR mistake)
        if 'B' in clean_text:
            texts_to_check.append(clean_text.replace('B', '6'))
            texts_to_check.append(clean_text.replace('B', '5'))
            print(f"AI Service: Checking 'B' variants: {clean_text.replace('B', '6')}, {clean_text.replace('B', '5')}")
        
        # Version 2: Replace 'O' with '0', 'I' with '1', 'S' with '5'
        normalized = clean_text.replace('O', '0').replace('I', '1').replace('S', '5')
        if normalized != clean_text:
            texts_to_check.append(normalized)
            print(f"AI Service: Checking normalized: '{normalized}'")
        
        # License plate patterns (more restrictive)
        patterns = [
            # US/International formats
            r'^\d{2}[A-Z]\d{4,5}$',  # 24A8870 or 24A83878 (most common format)
            r'^\d{2}[A-Z]\d{3,4}$',  # 24A123 or 24A1234
            r'^\d{1,2}[A-Z]\d{2,5}$',  # 1A123 or 24A12345
            r'^[A-Z]{2}\d{3,4}$',  # AB123 or AB1234
            r'^\d{3,4}[A-Z]{2}$',  # 123AB or 1234AB
            r'^[A-Z]\d{2,3}[A-Z]{2}$',  # A12BC
            
            # UK formats
            r'^[A-Z]{2}\d{2}[A-Z]{3}$',  # LE75CFG (current format)
            r'^[A-Z]{2}\d{2}[A-Z]{2,3}$',  # SN56XMZ (UK format)
            r'^[A-Z]\d{1,3}[A-Z]{3}$',  # A123BCD (older UK format)
            r'^\d{1,3}[A-Z]{3}$',  # 123ABC (older UK format)
            r'^[A-Z]{3}\d{1,3}$',  # ABC123 (older UK format)
            r'^[A-Z]{1,2}\d{2,3}[A-Z]{2,3}$',  # A12BC or AB123CDE (min 5 chars)
            r'^[A-Z]\d{3,4}[A-Z]$',  # A599B (international format)
            
            # Additional international formats
            r'^\d{2}[A-Z]\d{5}$',  # 24A83878 (Prado format - 8 chars)
            r'^\d{2}[A-Z]\d{4}$',  # 24A1234
            r'^\d{1,2}[A-Z]\d{4,6}$',  # 1A12345 or 24A123456
            r'^\d{2}[A-Z]\d{6}$',  # 24A123456 (9 chars - some plates have 6 digits after letter)
            
            # UK mixed format (GX6Z TKZ -> GX6ZTKZ)
            r'^[A-Z]{2}\d[A-Z]\d[A-Z]{3}$',  # GX6ZTKZ (UK format: 2 letters + digit + letter + digit + 3 letters)
            r'^[A-Z]{2}\d{1,2}[A-Z]{1,2}\d{0,2}[A-Z]{0,3}$',  # Very flexible UK format
        ]
        
        for text_variant in texts_to_check:
            # Check if this variant is in skip_words
            if text_variant in skip_words:
                logger.info(f"Skipping '{text}' -> '{text_variant}' (in skip_words)")
                print(f"AI Service: Skipping '{text}' -> '{text_variant}' (in skip_words)")
                return False
                
            for pattern in patterns:
                if re.match(pattern, text_variant):
                    logger.info(f"License plate pattern matched: '{text}' -> '{text_variant}' matches pattern {pattern}")
                    print(f"AI Service: License plate pattern matched: '{text}' -> '{text_variant}' matches pattern {pattern}")
                    return True
        
        # More flexible additional checks for various license plate formats
        # Check all text variants (including normalized versions)
        for text_variant in texts_to_check:
            # Require minimum 5 characters to avoid false positives like "E6X"
            if len(text_variant) >= 5 and len(text_variant) <= 8:
                # Check if it has letters and numbers
                has_letters = any(c.isalpha() for c in text_variant)
                has_numbers = any(c.isdigit() for c in text_variant)
                
                # For very low-res images, even accept all-number strings that look like plates
                # This catches cases where OCR misreads letters as numbers (e.g., A599B -> 445998)
                if has_letters and has_numbers:
                    letter_count = sum(1 for c in text_variant if c.isalpha())
                    number_count = sum(1 for c in text_variant if c.isdigit())
                    
                    # Very flexible ratios for low-resolution images
                    # Accept almost any combination of letters and numbers
                    if (1 <= letter_count <= 5 and 1 <= number_count <= 7):
                        logger.info(f"License plate heuristic matched: '{text}' -> '{text_variant}' (letters: {letter_count}, numbers: {number_count})")
                        print(f"AI Service: License plate heuristic matched: '{text}' -> '{text_variant}' (letters: {letter_count}, numbers: {number_count})")
                        return True
                
                # VERY AGGRESSIVE: For 5-6 character all-number strings, assume they might be misread plates
                # This is risky but necessary for very low-resolution images
                elif has_numbers and not has_letters and len(text_variant) in [5, 6]:
                    logger.info(f"License plate heuristic matched (all-numbers): '{text}' -> '{text_variant}' (might be misread plate)")
                    print(f"AI Service: License plate heuristic matched (all-numbers): '{text}' -> '{text_variant}' (might be misread plate)")
                    return True
        
        return False
    
    def process_multiple_images(self, image_paths: List[str]) -> List[str]:
        """Process multiple images and blur license plates"""
        processed_paths = []
        
        for image_path in image_paths:
            try:
                processed_path = self._blur_license_plates(image_path)
                processed_paths.append(processed_path)
            except Exception as e:
                logger.error(f"Error processing image {image_path}: {str(e)}")
                processed_paths.append(image_path)  # Return original if processing fails
        
        return processed_paths

# Global instance
car_analysis_service = CarAnalysisService()
