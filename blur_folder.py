import sys, os, glob
sys.path.append('.')
from kk.ai_service import car_analysis_service

# Usage:
#   python blur_folder.py "C:\path\to\images" [--aggressive]
# If no folder arg is passed, the default below is used.
folder = r"C:\Users\VeeStore\Desktop\New folder (4)"
aggressive = any(arg.lower() == '--aggressive' for arg in sys.argv[1:])
strict_only = any(arg.lower() == '--strict-only' for arg in sys.argv[1:])
ocr_only_flag = any(arg.lower() == '--ocr-only' for arg in sys.argv[1:])
if len(sys.argv) >= 2 and not sys.argv[1].startswith('-'):
	folder = sys.argv[1]

patterns = ("*.jpg","*.jpeg","*.png","*.webp","*.bmp","*.tif","*.tiff")

def process_one(path):
	if "_blurred" in os.path.basename(path).lower():
		return None
	if ocr_only_flag:
		out = car_analysis_service._blur_license_plates(path, strict=True, mode="ocr_only")
		if out != path:
			print(out); return out
	else:
		# Pass 1: YOLO + OCR with conservative clamps (default)
		out = car_analysis_service._blur_license_plates(path, strict=True, mode="auto")
		if out != path:
			print(out); return out
		# Pass 2: Relaxed geometry (helps with angled/far plates) unless strict-only
		if not strict_only:
			out = car_analysis_service._blur_license_plates(path, strict=False, mode="auto")
			if out != path:
				print(out); return out
		# Pass 3: OCR-only pipeline (handles generic/special plates, Arabic, etc.)
		out = car_analysis_service._blur_license_plates(path, strict=True if strict_only else False, mode="ocr_only")
		if out != path:
			print(out); return out
		# Optional aggressive re-try (slightly slower, higher recall)
		if aggressive and not strict_only:
			out = car_analysis_service._blur_license_plates(path, strict=False, mode="auto")
			if out != path:
				print(out); return out
	print(f"NO_BLUR:{path}")
	return None

files = []
for p in patterns:
	files.extend(glob.glob(os.path.join(folder, '**', p), recursive=True))

for path in files:
	try:
		process_one(path)
	except Exception as e:
		print(f"ERROR:{path}:{e}")
