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

# Deprecated flags: OCR is disabled (IQ Cars–style). These flags are ignored.
if ocr_only_flag:
	print("DEPRECATED: --ocr-only is ignored. OCR is intentionally disabled for stability (IQ Cars–style).")
	ocr_only_flag = False
if strict_only:
	print("DEPRECATED: --strict-only is ignored. OCR/strict modes are disabled (IQ Cars–style).")
	strict_only = False

patterns = ("*.jpg","*.jpeg","*.png","*.webp","*.bmp","*.tif","*.tiff")

def process_one(path):
	if "_blurred" in os.path.basename(path).lower():
		return None
	# OCR is intentionally disabled for stability (IQ Cars–style). Single deterministic pass.
			out = car_analysis_service._blur_license_plates(path, strict=False, mode="auto")
			if out != path:
				print(out); return out
	print(f"NO_BLUR:{path}")
	return None

files = []
for p in patterns:
	files.extend(glob.glob(os.path.join(folder, '**', p), recursive=True))

# Totals for verification summary
total_images = 0
total_plates = 0
total_fallbacks = 0
misses = []

for path in files:
	try:
		total_images += 1
		process_one(path)
		# Read per-image stats from service
		stats = getattr(car_analysis_service, "_last_blur_stats", None)
		if isinstance(stats, dict):
			nb = int(stats.get('num_blurs', 0) or 0)
			fb = bool(stats.get('fallback', False))
			total_plates += nb
			if fb:
				total_fallbacks += 1
				if nb == 0:
					misses.append(os.path.basename(path))
	except Exception as e:
		print(f"ERROR:{path}:{e}")

print(f"SUMMARY: images={total_images} plates_detected={total_plates} fallbacks={total_fallbacks}")
if misses:
	print("MISSES (fallback used; no plate detection):")
	for m in misses:
		print(f"  - {m}")
