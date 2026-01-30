import io
import os
import logging
from flask import Flask, request, jsonify, send_file
from werkzeug.utils import secure_filename
from dotenv import load_dotenv
import requests
import tempfile

# Load environment variables; prefer .env, fallback to env.local
load_dotenv()
env_local_path = os.path.join(os.path.dirname(__file__), "env.local")
if os.path.exists(env_local_path):
	# Use override=True so env.local can repair empty/incorrect inherited env vars.
	# This makes behavior reproducible when the OS has stale/blank ROBOFLOW_*/LOGO_* vars.
	load_dotenv(env_local_path, override=True)

app = Flask(__name__)

# Logging configuration
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s [%(name)s] %(message)s")
logger = logging.getLogger("watermarkly-backend")

LISTINGS_API_BASE = (os.getenv("LISTINGS_API_BASE") or "").strip().rstrip("/")

EU_URL = "https://blur-api-eu1.watermarkly.com/blur/"
US_URL = "https://blur-api-us1.watermarkly.com/blur/"

_LOCAL_YOLO_MODEL = None
_LOCAL_YOLO_MODEL_PATH = None

def _get_local_yolo_model():
	"""
	Best-effort local Ultralytics YOLO model loader for license-plate detection.
	Only uses local .pt weights (no network downloads).
	Returns YOLO model or None.
	"""
	global _LOCAL_YOLO_MODEL, _LOCAL_YOLO_MODEL_PATH
	if _LOCAL_YOLO_MODEL is not None:
		return _LOCAL_YOLO_MODEL
	try:
		from ultralytics import YOLO  # type: ignore
	except Exception:
		return None
	try:
		repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
		candidates = [
			os.path.join(repo_root, "kk", "weights", "yolov8n-license-plate.pt"),
			os.path.join(repo_root, "kk", "weights", "yolov8m-license-plate.pt"),
			os.path.join(repo_root, "kk", "weights", "yolov8l-license-plate.pt"),
			os.path.join(repo_root, "weights", "yolov8n-license-plate.pt"),
			os.path.join(repo_root, "yolov8n-license-plate.pt"),
			# Generic local models as last resort (still local-only)
			os.path.join(repo_root, "kk", "yolov8n.pt"),
			os.path.join(repo_root, "yolov8n.pt"),
		]
		for p in candidates:
			if p and os.path.exists(p):
				_LOCAL_YOLO_MODEL = YOLO(p)
				_LOCAL_YOLO_MODEL_PATH = p
				logger.info(f"[local-yolo] loaded weights: {p}")
				return _LOCAL_YOLO_MODEL
	except Exception as e:
		logger.info(f"[local-yolo] init failed: {e}")
	return None

def _local_yolo_plate_mask(img_bgr):
	"""
	Build a union mask (uint8 HxW) from local YOLO detections.
	Returns None if unavailable or no detections.
	"""
	try:
		import numpy as _np
		import cv2 as _cv2
		model = _get_local_yolo_model()
		if model is None or img_bgr is None:
			return None
		H, W = img_bgr.shape[:2]
		conf = float(os.getenv("LOCAL_YOLO_CONFIDENCE") or "0.20")
		iou = float(os.getenv("LOCAL_YOLO_IOU") or "0.50")
		imgsz = int(float(os.getenv("LOCAL_YOLO_IMGSZ") or "1280"))
		res = model.predict(img_bgr, conf=conf, iou=iou, imgsz=imgsz, verbose=False)
		if not res:
			return None
		r0 = res[0]
		boxes = getattr(r0, "boxes", None)
		if boxes is None or not hasattr(boxes, "xyxy"):
			return None
		try:
			xyxy = boxes.xyxy.cpu().numpy() if hasattr(boxes.xyxy, "cpu") else boxes.xyxy
		except Exception:
			xyxy = boxes.xyxy
		if xyxy is None:
			return None
		mask = _np.zeros((H, W), _np.uint8)
		for b in xyxy:
			try:
				x1, y1, x2, y2 = [int(round(float(v))) for v in b[:4]]
				x1 = max(0, min(W - 1, x1))
				y1 = max(0, min(H - 1, y1))
				x2 = max(0, min(W, x2))
				y2 = max(0, min(H, y2))
				if x2 <= x1 or y2 <= y1:
					continue
				# Basic plate-like sanity: avoid absurdly large masks
				area_frac = float((x2 - x1) * (y2 - y1)) / float(max(1, H * W))
				if area_frac > float(os.getenv("LOCAL_YOLO_MAX_AREA_FRAC") or "0.35"):
					continue
				_cv2.rectangle(mask, (x1, y1), (x2, y2), 255, -1)
			except Exception:
				continue
		if not mask.any():
			return None
		try:
			ker = _cv2.getStructuringElement(_cv2.MORPH_ELLIPSE, (5, 5))
			mask = _cv2.morphologyEx(mask, _cv2.MORPH_CLOSE, ker, iterations=2)
			mask = _cv2.dilate(mask, ker, iterations=1)
		except Exception:
			pass
		return mask if mask.any() else None
	except Exception:
		return None

def _get_api_key() -> str:
	key = (os.getenv("WATERMARKLY_API_KEY") or "").strip()
	return key

@app.route("/health", methods=["GET"])
def health():
	return jsonify({"status": "ok"}), 200

def _call_watermarkly(img_bytes: bytes) -> requests.Response:
	headers = {"x-api-key": _get_api_key(), "Content-Type": "application/octet-stream"}
	def _try(url: str) -> requests.Response:
		# STRICT pass-through: forward the raw upload bytes exactly as received
		r = requests.post(url, headers=headers, data=img_bytes, timeout=90)
		if r.status_code == 429:
			import time as _t
			_t.sleep(0.25)
			r = requests.post(url, headers=headers, data=img_bytes, timeout=90)
		return r
	region = (os.getenv("WATERMARKLY_REGION") or "").strip().upper()
	order = [US_URL, EU_URL] if region == "US" else ([EU_URL, US_URL] if region == "EU" else [EU_URL, US_URL])
	for url in order:
		try:
			resp = _try(url)
			# Return on first 2xx with content; otherwise try next
			if resp is not None and resp.status_code == 200 and resp.content:
				return resp
		except Exception:
			continue
	# Last attempt US as hard fallback
	try:
		return _try(US_URL)
	except Exception:
		return _try(EU_URL)

# -------------------------------
# Logo stamping helper
# -------------------------------
def _load_logo():
	"""
	Load logo image (with alpha if present). Path via LOGO_PATH or default backend/logo.png.
	Returns (logo_bgra or None).
	"""
	import cv2 as _cv2
	_path = (os.getenv("LOGO_PATH") or "").strip()
	# Strip surrounding quotes if present
	if _path.startswith(("'", '"')) and _path.endswith(("'", '"')) and len(_path) >= 2:
		_path = _path[1:-1]
	if not _path:
		_path = os.path.join(os.path.dirname(__file__), "logo.png")
	try:
		if os.path.exists(_path):
			img = _cv2.imread(_path, _cv2.IMREAD_UNCHANGED)
			return img
	except Exception:
		return None
	return None

def _try_stamp_logo_using_rf_on_image(img_bgr):
	"""
	Run a single Roboflow detect on the provided image to build a union mask
	and stamp the logo onto the image. Returns possibly modified image.
	No blur is applied here; this is purely for logo overlay on WM results.
	"""
	try:
		model_slug = (os.getenv("ROBOFLOW_MODEL") or os.getenv("ROBOFLOW_MODEL_SLUG") or "").strip()
		if "/" in model_slug:
			parts = model_slug.split("/", 1)
			model_slug = parts[0].strip()
			if not os.getenv("ROBOFLOW_VERSION"):
				os.environ["ROBOFLOW_VERSION"] = (parts[1] or "1").strip()
		version = (os.getenv("ROBOFLOW_VERSION") or "1").strip()
		api_key = (os.getenv("ROBOFLOW_API_KEY") or "").strip()
		conf = (os.getenv("ROBOFLOW_CONFIDENCE") or "0.22").strip()
		overlap = (os.getenv("ROBOFLOW_OVERLAP") or "0.50").strip()
		include_mask = (os.getenv("ROBOFLOW_INCLUDE_MASK") or "true").strip().lower() in ("1", "true", "yes")
		if not api_key or not model_slug or not version:
			return img_bgr
		import numpy as _np
		import cv2 as _cv2
		H, W = img_bgr.shape[:2]
		ok, enc = _cv2.imencode(".jpg", img_bgr, [int(_cv2.IMWRITE_JPEG_QUALITY), 92])
		if not ok:
			return img_bgr
		params = f"?api_key={api_key}&confidence={conf}&overlap={overlap}&format=json"
		if include_mask:
			params += "&include_mask=true"
		url = f"https://detect.roboflow.com/{model_slug}/{version}{params}"
		rv = requests.post(url, files={"file": ("wm.jpg", enc.tobytes(), "image/jpeg")}, timeout=45)
		if rv.status_code != 200:
			return img_bgr
		jv = rv.json()
		mask = _np.zeros((H, W), _np.uint8)
		for p in (jv.get("predictions", []) or []):
			points = p.get("points") or []
			if isinstance(points, list) and len(points) >= 3:
				try:
					if isinstance(points[0], dict):
						pts = _np.array([[float(pt["x"]), float(pt["y"])] for pt in points], _np.int32)
					else:
						pts = _np.array([[float(pt[0]), float(pt[1])] for pt in points], _np.int32)
					_cv2.fillPoly(mask, [pts], 255)
					continue
				except Exception:
					pass
			# fallback rectangle
			try:
				x = float(p.get("x", 0)); y = float(p.get("y", 0))
				w = float(p.get("width", 0)); h = float(p.get("height", 0))
				x1 = max(0, int(x - w/2)); y1 = max(0, int(y - h/2))
				x2 = min(W, int(x + w/2)); y2 = min(H, int(y + h/2))
				if x2 > x1 and y2 > y1:
					_cv2.rectangle(mask, (x1, y1), (x2, y2), 255, -1)
			except Exception:
				continue
		if mask.any():
			try:
				ker = _cv2.getStructuringElement(_cv2.MORPH_ELLIPSE, (3, 3))
				mask = _cv2.erode(mask, ker, iterations=1)
			except Exception:
				pass
			try:
				img_bgr = _stamp_logo_on_mask(img_bgr, mask)
			except Exception:
				return img_bgr
		return img_bgr
	except Exception:
		return img_bgr

def _build_mask_from_rf(img_bgr, conf_override: str = None):
	"""
	Return a union mask (uint8 HxW) of detections from Roboflow for the given image.
	"""
	try:
		model_slug = (os.getenv("ROBOFLOW_MODEL") or os.getenv("ROBOFLOW_MODEL_SLUG") or "").strip()
		if "/" in model_slug:
			parts = model_slug.split("/", 1)
			model_slug = parts[0].strip()
			if not os.getenv("ROBOFLOW_VERSION"):
				os.environ["ROBOFLOW_VERSION"] = (parts[1] or "1").strip()
		version = (os.getenv("ROBOFLOW_VERSION") or "1").strip()
		api_key = (os.getenv("ROBOFLOW_API_KEY") or "").strip()
		conf = (conf_override or os.getenv("ROBOFLOW_CONFIDENCE") or "0.28").strip()
		overlap = (os.getenv("ROBOFLOW_OVERLAP") or "0.50").strip()
		include_mask = (os.getenv("ROBOFLOW_INCLUDE_MASK") or "true").strip().lower() in ("1", "true", "yes")
		if not api_key or not model_slug or not version:
			return None
		import numpy as _np
		import cv2 as _cv2
		H, W = img_bgr.shape[:2]
		ok, enc = _cv2.imencode(".jpg", img_bgr, [int(_cv2.IMWRITE_JPEG_QUALITY), 92])
		if not ok:
			return None
		params = f"?api_key={api_key}&confidence={conf}&overlap={overlap}&format=json"
		if include_mask:
			params += "&include_mask=true"
		url = f"https://detect.roboflow.com/{model_slug}/{version}{params}"
		rv = requests.post(url, files={"file": ("img.jpg", enc.tobytes(), "image/jpeg")}, timeout=60)
		if rv.status_code != 200:
			return None
		jv = rv.json()
		mask = _np.zeros((H, W), _np.uint8)
		for p in (jv.get("predictions", []) or []):
			points = p.get("points") or []
			if isinstance(points, list) and len(points) >= 3:
				try:
					if isinstance(points[0], dict):
						pts = _np.array([[float(pt["x"]), float(pt["y"])] for pt in points], _np.int32)
					else:
						pts = _np.array([[float(pt[0]), float(pt[1])] for pt in points], _np.int32)
					_cv2.fillPoly(mask, [pts], 255)
					continue
				except Exception:
					pass
			try:
				x = float(p.get("x", 0)); y = float(p.get("y", 0))
				w = float(p.get("width", 0)); h = float(p.get("height", 0))
				x1 = max(0, int(x - w/2)); y1 = max(0, int(y - h/2))
				x2 = min(W, int(x + w/2)); y2 = min(H, int(y + h/2))
				_cv2.rectangle(mask, (x1, y1), (x2, y2), 255, -1)
			except Exception:
				continue
		return mask if mask.any() else None
	except Exception:
		return None

def _estimate_blur_mask_from_diff(img_orig_bgr, img_wm_bgr):
	"""
	Estimate blurred region mask by comparing Watermarkly output with original image.
	Returns uint8 mask (H,W) or None.
	"""
	try:
		import numpy as _np
		import cv2 as _cv2
		if img_orig_bgr is None or img_wm_bgr is None:
			return None
		Ho, Wo = img_orig_bgr.shape[:2]
		Hw, Ww = img_wm_bgr.shape[:2]
		if Ho != Hw or Wo != Ww:
			img_wm_bgr = _cv2.resize(img_wm_bgr, (Wo, Ho), interpolation=_cv2.INTER_LINEAR)
		orig_g = _cv2.cvtColor(img_orig_bgr, _cv2.COLOR_BGR2GRAY)
		wm_g = _cv2.cvtColor(img_wm_bgr, _cv2.COLOR_BGR2GRAY)
		# High-frequency difference
		lap_o = _cv2.Laplacian(orig_g, _cv2.CV_32F)
		lap_w = _cv2.Laplacian(wm_g, _cv2.CV_32F)
		diff = _cv2.absdiff(_cv2.convertScaleAbs(lap_o), _cv2.convertScaleAbs(lap_w))
		# Areas with strong reduction in detail indicate blur; invert diff and threshold
		diff_norm = _cv2.normalize(diff, None, 0, 255, _cv2.NORM_MINMAX)
		inv = 255 - diff_norm
		blur = _cv2.GaussianBlur(inv, (9, 9), 0)
		_, th = _cv2.threshold(blur, 0, 255, _cv2.THRESH_BINARY + _cv2.THRESH_OTSU)
		# Morphological refine
		ker = _cv2.getStructuringElement(_cv2.MORPH_ELLIPSE, (7, 7))
		mask = _cv2.morphologyEx(th, _cv2.MORPH_CLOSE, ker, iterations=2)
		mask = _cv2.dilate(mask, ker, iterations=1)
		if int(mask.sum()) == 0:
			return None
		# Keep largest contiguous region (plate)
		contours, _ = _cv2.findContours(mask, _cv2.RETR_EXTERNAL, _cv2.CHAIN_APPROX_SIMPLE)
		if not contours:
			return None
		areas = [_cv2.contourArea(c) for c in contours]
		ci = int(_np.argmax(areas))
		# Basic sanity filtering: reject masks that are too large or not plate-like
		x, y, w, h = _cv2.boundingRect(contours[ci])
		area_frac = float(w * h) / float(max(1, Wo * Ho))
		# thresholds can be tuned via env; defaults chosen conservatively
		max_frac = float((os.getenv("DIFF_MASK_MAX_FRAC") or "0.25"))
		min_frac = float((os.getenv("DIFF_MASK_MIN_FRAC") or "0.0005"))
		ar = float(w) / float(max(1, h))
		if area_frac > max_frac or area_frac < min_frac or ar < 1.0 or ar > 8.0:
			return None
		mask2 = _np.zeros_like(mask)
		_cv2.drawContours(mask2, [contours[ci]], -1, 255, thickness=-1)
		return mask2
	except Exception:
		return None

def _stamp_logo_on_mask(bgr_image, plate_mask, bbox=None):
	"""
	Stamp a single centered logo onto the blurred plate region.
	- bgr_image: target image (BGR)
	- plate_mask: uint8 mask (H,W) where 255 = plate region
	- bbox: optional (x1,y1,x2,y2) to size the logo; if None computed from mask
	Respects:
	- LOGO_OPACITY (0..1, default 0.7)
	- LOGO_SCALE (fraction of bbox width, default 0.40)
	- LOGO_BG (1/0) draw dark badge under logo (default 1)
	- LOGO_BG_OPACITY (0..1, default 0.55)
	- LOGO_PAD (fractional padding around logo for badge, default 0.12)
	- LOGO_AUTO (1/0) auto-scale to fill plate region (default 1)
	- LOGO_FILL_W (0..1) fraction of plate width to fill (default 0.75)
	- LOGO_FILL_H (0..1) fraction of plate height cap (default 0.55)
	- LOGO_MIN_PX, LOGO_MAX_PX: hard pixel bounds for logo width (defaults 40..512)
	"""
	import numpy as _np
	import cv2 as _cv2
	logo = _load_logo()
	if logo is None:
		return bgr_image
	H, W = bgr_image.shape[:2]
	if plate_mask is None or plate_mask.size == 0:
		return bgr_image
	ys, xs = _np.where(plate_mask > 0)
	if xs.size == 0 or ys.size == 0:
		return bgr_image
	if bbox is None:
		x1, x2 = int(xs.min()), int(xs.max())
		y1, y2 = int(ys.min()), int(ys.max())
	else:
		x1, y1, x2, y2 = bbox
	x1 = max(0, x1); y1 = max(0, y1); x2 = min(W, x2); y2 = min(H, y2)
	bw = max(1, x2 - x1); bh = max(1, y2 - y1)
	# Dynamic sizing
	mode = (os.getenv("LOGO_MODE") or "").strip().lower()
	auto = (os.getenv("LOGO_AUTO") or "1").strip().lower() in ("1", "true", "yes")
	min_px = int(float(os.getenv("LOGO_MIN_PX", "40") or "40"))
	max_px = int(float(os.getenv("LOGO_MAX_PX", "512") or "512"))
	fill_w = float(os.getenv("LOGO_FILL_W", "0.75") or "0.75")
	fill_h = float(os.getenv("LOGO_FILL_H", "0.55") or "0.55")
	fill_w = max(0.2, min(0.98, fill_w))
	fill_h = max(0.2, min(0.98, fill_h))
	if mode == "exact":
		# Fit the logo entirely inside the blur bbox (no overflow)
		h0, w0 = logo.shape[0], logo.shape[1]
		scale_contain = min(bw / float(max(1, w0)), bh / float(max(1, h0)))
		target_w = int(round(w0 * scale_contain))
		target_h = int(round(h0 * scale_contain))
	elif mode == "stretch":
		# Stretch to exactly the bbox (may distort logo)
		target_w = max(1, bw)
		target_h = max(1, bh)
	elif mode == "cover":
		# Cover the bbox while preserving aspect ratio
		h0, w0 = logo.shape[0], logo.shape[1]
		scale_cover = max(bw / float(max(1, w0)), bh / float(max(1, h0)))
		target_w = int(round(w0 * scale_cover))
		target_h = int(round(h0 * scale_cover))
	else:
		# Legacy auto/scale behavior
		if auto:
			target_w = int(bw * fill_w)
			# target_h computed after aspect below; will be capped by fill_h later
		else:
			scale = float(os.getenv("LOGO_SCALE", "0.40") or "0.40")
			scale = max(0.1, min(0.9, scale))
			target_w = int(bw * scale)
	# keep aspect
	# keep aspect
	h0, w0 = logo.shape[0], logo.shape[1]
	if target_w <= 1 or w0 == 0:
		return bgr_image
	# When not set earlier (cover/stretch may have target_h), compute by aspect
	if 'target_h' not in locals():
		target_h = int(h0 * (target_w / float(w0)))
	# Cap by plate height if auto and not in cover/stretch
	if mode not in ("cover", "stretch") and auto and target_h > int(bh * fill_h):
		target_h = int(bh * fill_h)
		target_w = int(w0 * (target_h / float(max(1, h0))))
	# Clamp by absolute pixel bounds
	if target_w < min_px:
		scale_up = min_px / float(max(1, target_w))
		target_w = min_px
		target_h = int(target_h * scale_up)
	if target_w > max_px:
		scale_down = max_px / float(max(1, target_w))
		target_w = max_px
		target_h = int(target_h * scale_down)
	if target_h <= 0:
		target_h = 1
	logo_rs = _cv2.resize(logo, (target_w, target_h), interpolation=_cv2.INTER_AREA)
	# split channels and alpha
	ignore_alpha = (os.getenv("LOGO_IGNORE_ALPHA") or "1").strip().lower() in ("1", "true", "yes")
	if logo_rs.shape[2] == 4 and not ignore_alpha:
		l_bgr = logo_rs[:, :, :3]
		l_alpha = logo_rs[:, :, 3] / 255.0
		# Ensure minimum visibility if original alpha is too low
		min_a = float(os.getenv("LOGO_MIN_ALPHA", "0.85") or "0.85")
		min_a = max(0.0, min(1.0, min_a))
		l_alpha = _np.maximum(l_alpha, min_a)
	else:
		l_bgr = logo_rs[:, :, :3] if logo_rs.shape[2] >= 3 else logo_rs
		l_alpha = _np.ones((l_bgr.shape[0], l_bgr.shape[1]), dtype=_np.float32)
	opacity = float(os.getenv("LOGO_OPACITY", "0.70") or "0.70")
	opacity = max(0.0, min(1.0, opacity))
	l_alpha = (l_alpha * opacity).astype(_np.float32)
	# position inside bbox
	pos_env = (os.getenv("LOGO_POS") or "center").strip().lower()
	# For exact/cover/stretch we force center to ensure alignment with bbox, and remove margins
	pos = "center" if mode in ("exact", "cover", "stretch") else pos_env
	if mode in ("exact", "cover", "stretch"):
		margin_frac = 0.0
	else:
		margin_frac = float(os.getenv("LOGO_POS_MARGIN", "0.06") or "0.06")
	mx = int(bw * margin_frac); my = int(bh * margin_frac)
	if pos == "br":
		xs0 = max(x1 + mx, x2 - target_w - mx)
		ys0 = max(y1 + my, y2 - target_h - my)
	elif pos == "bl":
		xs0 = max(x1 + mx, x1 + mx)
		ys0 = max(y1 + my, y2 - target_h - my)
	elif pos == "tr":
		xs0 = max(x1 + mx, x2 - target_w - mx)
		ys0 = max(y1 + my, y1 + my)
	elif pos == "tl":
		xs0 = max(x1 + mx, x1 + mx)
		ys0 = max(y1 + my, y1 + my)
	else:
		# center
		cx = x1 + bw // 2
		cy = y1 + bh // 2
		xs0 = cx - target_w // 2
		ys0 = cy - target_h // 2
	xe0 = xs0 + target_w
	ye0 = ys0 + target_h
	# clamp to image
	if xs0 < 0:
		l_bgr = l_bgr[:, -xs0:, :]
		l_alpha = l_alpha[:, -xs0:]
		xs0 = 0
	if ys0 < 0:
		l_bgr = l_bgr[-ys0:, :, :]
		l_alpha = l_alpha[-ys0:, :]
		ys0 = 0
	if xe0 > W:
		cut = xe0 - W
		l_bgr = l_bgr[:, :l_bgr.shape[1] - cut, :]
		l_alpha = l_alpha[:, :l_alpha.shape[1] - cut]
		xe0 = W
	if ye0 > H:
		cut = ye0 - H
		l_bgr = l_bgr[:l_bgr.shape[0] - cut, :, :]
		l_alpha = l_alpha[:l_alpha.shape[0] - cut, :]
		ye0 = H
	if l_bgr.size == 0:
		return bgr_image
	# restrict to plate mask region
	pm_crop = plate_mask[ys0:ye0, xs0:xe0] / 255.0
	if pm_crop.size == 0:
		return bgr_image
	# Reject masks that would cover an unreasonable portion of the image (prevents full-image logo)
	try:
		import cv2 as _cv2
		pix = int((plate_mask > 0).sum())  # number of mask pixels
		area_frac = float(pix) / float(max(1, H * W))
		max_frac_env = os.getenv("LOGO_MAX_AREA_FRAC") or "0.22"
		max_frac = float(max_frac_env)
		if area_frac > max_frac:
			# Try to fall back to the largest reasonable contour
			cs, _ = _cv2.findContours(plate_mask, _cv2.RETR_EXTERNAL, _cv2.CHAIN_APPROX_SIMPLE)
			if cs:
				cs = sorted(cs, key=_cv2.contourArea, reverse=True)
				for c in cs:
					x, y, w, h = _cv2.boundingRect(c)
					if w <= 0 or h <= 0:
						continue
					ar_local = float(w) / float(h)
					sub_frac = float(w * h) / float(max(1, H * W))
					if 1.0 <= ar_local <= 8.0 and sub_frac <= max_frac:
						# Recompute ROI from this contour bbox
						x1, y1, x2, y2 = x, y, x + w, y + h
						bw, bh = max(1, w), max(1, h)
						# Recompute target size and crops below using this bbox
						# Recalculate pm_crop for the new bbox
						pm_crop = plate_mask[y1:y2, x1:x2] / 255.0
						break
				else:
					return bgr_image
			else:
				return bgr_image
	except Exception:
		pass
	# Expand mask locally only in legacy modes (not in exact/cover/stretch)
	if mode not in ("exact", "cover", "stretch"):
		try:
			import cv2 as _cv2
			mask_expand = float(os.getenv("LOGO_MASK_EXPAND", "0.25") or "0.25")
			mask_expand = max(0.0, min(1.0, mask_expand))
			ker_dim = int(max(3, round(max(target_w, target_h) * mask_expand)))
			if ker_dim % 2 == 0:
				ker_dim += 1
			ker_dim = min(ker_dim, 49)
			if ker_dim >= 3:
				ker = _cv2.getStructuringElement(_cv2.MORPH_ELLIPSE, (ker_dim, ker_dim))
				pm_crop = _cv2.dilate((pm_crop*255).astype(_np.uint8), ker, iterations=1) / 255.0
		except Exception:
			pass
	# Optional dark badge behind the logo for contrast (skip in exact/cover/stretch modes)
	if mode not in ("exact", "cover", "stretch"):
		try:
			if (os.getenv("LOGO_BG") or "1").strip().lower() in ("1", "true", "yes"):
				bg_opacity = float(os.getenv("LOGO_BG_OPACITY", "0.55") or "0.55")
				bg_opacity = max(0.0, min(1.0, bg_opacity))
				pad_frac = float(os.getenv("LOGO_PAD", "0.12") or "0.12")
				pad_px_x = int(max(2, pad_frac * (xe0 - xs0)))
				pad_px_y = int(max(2, pad_frac * (ye0 - ys0)))
				bx0 = max(0, xs0 - pad_px_x); by0 = max(0, ys0 - pad_px_y)
				bx1 = min(W, xe0 + pad_px_x); by1 = min(H, ye0 + pad_px_y)
				if bx1 > bx0 and by1 > by0:
					badge = _np.zeros((by1 - by0, bx1 - bx0, 3), dtype=_np.float32)
					# dark gray/black badge
					badge[:, :, :] = _np.array([16,16,16], dtype=_np.float32)  # BGR
					# use plate mask to confine badge
					pm_bg = (plate_mask[by0:by1, bx0:bx1] / 255.0).astype(_np.float32)
					roi_bg = bgr_image[by0:by1, bx0:bx1, :].astype(_np.float32)
					alpha_bg = (pm_bg * bg_opacity).astype(_np.float32)
					for c in range(3):
						roi_bg[:, :, c] = alpha_bg * badge[:, :, c] + (1.0 - alpha_bg) * roi_bg[:, :, c]
					bgr_image[by0:by1, bx0:bx1, :] = _np.clip(roi_bg, 0, 255).astype(_np.uint8)
		except Exception:
			pass
	# Stroke to ensure visibility
	try:
		if (os.getenv("LOGO_STROKE") or "1").strip().lower() in ("1","true","yes"):
			stroke_px = int(float(os.getenv("LOGO_STROKE_PX","3") or "3"))
			stroke_px = max(1, min(32, stroke_px))
			ker = _cv2.getStructuringElement(_cv2.MORPH_ELLIPSE, (2*stroke_px+1, 2*stroke_px+1))
			alpha_u8 = (l_alpha*255).astype(_np.uint8)
			border = _cv2.dilate(alpha_u8, ker, iterations=1) - alpha_u8
			border = (border/255.0).astype(_np.float32) * float(os.getenv("LOGO_STROKE_OPACITY","0.85") or "0.85")
			border = border * pm_crop
			col = tuple(int(x) for x in (os.getenv("LOGO_STROKE_COLOR","0,0,0") or "0,0,0").split(","))
			roi_bg = bgr_image[ys0:ye0, xs0:xe0, :].astype(_np.float32)
			for c,cc in enumerate(col[:3]):
				roi_bg[:,:,c] = border*cc + (1.0-border)*roi_bg[:,:,c]
			bgr_image[ys0:ye0, xs0:xe0, :] = _np.clip(roi_bg,0,255).astype(_np.uint8)
	except Exception:
		pass
	alpha = (l_alpha * pm_crop).astype(_np.float32)
	roi = bgr_image[ys0:ye0, xs0:xe0, :].astype(_np.float32)
	lb = l_bgr.astype(_np.float32)
	for c in range(3):
		roi[:, :, c] = alpha * lb[:, :, c] + (1.0 - alpha) * roi[:, :, c]
	bgr_image[ys0:ye0, xs0:xe0, :] = _np.clip(roi, 0, 255).astype(_np.uint8)
	return bgr_image

@app.route("/blur-license-plate", methods=["POST"])
def blur_single():
	# Deprecated: unify on /blur-license-plate-auto
	return jsonify({
		"error": "DeprecatedRoute",
		"message": "Use /blur-license-plate-auto. This route has been removed."
	}), 410

# -------------------------------
# Roboflow-backed local blur route
# -------------------------------
def _rf_cfg():
	model_slug = (os.getenv("ROBOFLOW_MODEL") or os.getenv("ROBOFLOW_MODEL_SLUG") or "").strip()
	# Accept either "slug" or "slug/version"
	if "/" in model_slug:
		parts = model_slug.split("/", 1)
		model_slug = parts[0].strip()
		if not os.getenv("ROBOFLOW_VERSION"):
			os.environ["ROBOFLOW_VERSION"] = (parts[1] or "1").strip()
	version = (os.getenv("ROBOFLOW_VERSION") or "1").strip()
	api_key = (os.getenv("ROBOFLOW_API_KEY") or "").strip()
	conf = (os.getenv("ROBOFLOW_CONFIDENCE") or "0.30").strip()
	overlap = (os.getenv("ROBOFLOW_OVERLAP") or "0.50").strip()
	include_mask = (os.getenv("ROBOFLOW_INCLUDE_MASK") or "false").strip().lower() in ("1", "true", "yes")
	return model_slug, version, api_key, conf, overlap, include_mask

@app.route("/blur-license-plate-local", methods=["POST"])
def blur_license_plate_local():
	# Deprecated: unify on /blur-license-plate-auto
	return jsonify({
		"error": "DeprecatedRoute",
		"message": "Use /blur-license-plate-auto. This route has been removed."
	}), 410

@app.route("/blur-license-plate-auto", methods=["POST"])
def blur_license_plate_auto():
	"""
	Try Watermarkly first. If it fails (non-200 or empty), fallback to Roboflow model-based blurring.
	"""
	# Desired behavior:
	# - Watermarkly first
	# - ONLY if plate still readable/sharp after WM -> YOLO override
	# - Stamp logo exactly on the blur mask (no extra/bottom-center stamping)
	strict_q = (request.args.get("strict") or "").strip().lower() in ("1", "true", "yes")
	env_force = (os.getenv("FORCE_YOLO_OVERRIDE") or "0").strip().lower() in ("1", "true", "yes")
	force_override = (env_force or strict_q)
	file = request.files.get("image") or request.files.get("file") or request.files.get("upload")
	if not file:
		return jsonify({"error": "No file provided. Use form field 'image'."}), 400
	filename = secure_filename(file.filename or "upload.jpg")
	img_bytes = file.read()
	# HEIC/HEIF support: convert to JPEG bytes before processing
	try:
		ext = os.path.splitext(filename)[1].lower()
		cth = (file.mimetype or "").lower()
		if ext in (".heic", ".heif") or "image/heic" in cth or "image/heif" in cth:
			from io import BytesIO as _BytesIO
			try:
				import pillow_heif as _pheif  # type: ignore
				_pheif.register_heif_opener()
			except Exception:
				pass
			from PIL import Image as _PILImage  # type: ignore
			_img = _PILImage.open(_BytesIO(img_bytes)).convert("RGB")
			_buf = _BytesIO()
			_img.save(_buf, format="JPEG", quality=95)
			img_bytes = _buf.getvalue()
			filename = (os.path.splitext(filename)[0] or "upload") + ".jpg"
	except Exception:
		pass
	if not img_bytes:
		return jsonify({"error": "Empty file upload"}), 400

	# 1) Attempt Watermarkly if key is configured
	key = _get_api_key()
	logger.info(f"[blur-auto] WM key present: {bool(key)}")
	if key:
		try:
			resp = _call_watermarkly(img_bytes)
			logger.info(f"[blur-auto] WM response: status={resp.status_code if resp else None}, has_content={bool(resp.content) if resp else False}")
			if resp is not None and resp.status_code == 200 and resp.content:
				# Strict verify after Watermarkly:
				# - Detect plates on the WM image at higher confidence
				# - For each detection, compute sharpness; only if any region is still sharp, override with YOLO
				try:
					model_slug = (os.getenv("ROBOFLOW_MODEL") or os.getenv("ROBOFLOW_MODEL_SLUG") or "").strip()
					if "/" in model_slug:
						parts = model_slug.split("/", 1)
						model_slug = parts[0].strip()
						if not os.getenv("ROBOFLOW_VERSION"):
							os.environ["ROBOFLOW_VERSION"] = (parts[1] or "1").strip()
					version = (os.getenv("ROBOFLOW_VERSION") or "1").strip()
					api_key = (os.getenv("ROBOFLOW_API_KEY") or "").strip()
					conf = (os.getenv("ROBOFLOW_CONFIDENCE") or "0.28").strip()
					overlap = (os.getenv("ROBOFLOW_OVERLAP") or "0.50").strip()
					include_mask = True if (os.getenv("ROBOFLOW_INCLUDE_MASK") or "true").strip().lower() in ("1", "true", "yes") else False
					logger.info(f"[blur-auto] RF config: api_key={bool(api_key)}, model_slug={model_slug}, version={version}, include_mask={include_mask}")
					if api_key and model_slug and version:
						import numpy as _np
						import cv2 as _cv2
						# Decode Watermarkly output and ORIGINAL input
						img_arr = _np.frombuffer(resp.content, dtype=_np.uint8)
						img_wm = _cv2.imdecode(img_arr, _cv2.IMREAD_COLOR)
						img_orig = _cv2.imdecode(_np.frombuffer(img_bytes, dtype=_np.uint8), _cv2.IMREAD_COLOR)
						if img_wm is not None and img_orig is not None:
							H, W = img_wm.shape[:2]
							# Step A: strict verify on WM image with multi-scale and OCR+sharpness gate
							try:
								verify_conf = float(os.getenv("ROBOFLOW_VERIFY_CONFIDENCE") or "0.18")
							except Exception:
								verify_conf = 0.18
							verify_params_base = f"?api_key={api_key}&confidence={verify_conf:.2f}&overlap={overlap}&format=json"
							if include_mask:
								verify_params_base += "&include_mask=true"
							url_verify_base = f"https://detect.roboflow.com/{model_slug}/{version}"
							gray_wm = _cv2.cvtColor(img_wm, _cv2.COLOR_BGR2GRAY)
							# union mask from verify detections for logo stamping
							mask_logo = _np.zeros((H, W), _np.uint8)
							def _roi_sharp(gray, x1, y1, x2, y2):
								roi = gray[max(0,y1):min(H,y2), max(0,x1):min(W,x2)]
								if roi.size == 0: return 0.0
								return float(_cv2.Laplacian(roi, _cv2.CV_64F).var())
							# optional OCR reader
							_ezr = None
							try:
								from easyocr import Reader as _EZReader
								_ezr = _EZReader(['en','ar','fa'], gpu=False)
							except Exception:
								_ezr = None
							def _roi_has_text(x1,y1,x2,y2):
								if _ezr is None: return False
								roi = img_wm[max(0,y1):min(H,y2), max(0,x1):min(W,x2)]
								if roi.size == 0: return False
								hits = _ezr.readtext(roi)
								for (_bb, _tx, _cf) in hits:
									_cf = 0.0 if _cf is None else float(_cf)
									txt = ''.join([c for c in str(_tx) if c.isalnum()])
									# More permissive: any alphanumeric ≥3 with conf ≥0.25 triggers override
									if _cf >= 0.25 and len(txt) >= 3:
										return True
								return False
							leftover = False
							for s in [1.0, 1.25, 1.5, 1.75, 2.0]:
								try:
									img_vs = img_wm if s == 1.0 else _cv2.resize(img_wm, None, fx=s, fy=s, interpolation=_cv2.INTER_LINEAR)
									okv, encv = _cv2.imencode(".jpg", img_vs, [int(_cv2.IMWRITE_JPEG_QUALITY), 92])
									if not okv: continue
									rv = requests.post(url_verify_base + verify_params_base, files={"file": ("wm.jpg", encv.tobytes(), "image/jpeg")}, timeout=45)
									if rv.status_code != 200: continue
									jv = rv.json()
									for p in jv.get("predictions", []) or []:
										pts = p.get("points") or []
										if isinstance(pts, list) and len(pts) >= 3:
											try:
												if isinstance(pts[0], dict):
													xs = [float(t["x"])/s for t in pts]; ys = [float(t["y"])/s for t in pts]
												else:
													xs = [float(t[0])/s for t in pts]; ys = [float(t[1])/s for t in pts]
												x1, x2 = int(max(0, min(xs))), int(min(W, max(xs)))
												y1, y2 = int(max(0, min(ys))), int(min(H, max(ys)))
												# add to union mask for logo placement
												try:
													if include_mask:
														if isinstance(pts[0], dict):
															pts_s = _np.array([[float(t["x"])/s, float(t["y"])/s] for t in pts], _np.int32)
														else:
															pts_s = _np.array([[float(t[0])/s, float(t[1])/s] for t in pts], _np.int32)
														_cv2.fillPoly(mask_logo, [pts_s], 255)
													else:
														_cv2.rectangle(mask_logo, (x1, y1), (x2, y2), 255, -1)
												except Exception:
													pass
											except Exception:
												leftover = True; break
										else:
											try:
												x = float(p.get("x", 0))/s; y = float(p.get("y", 0))/s
												w = float(p.get("width", 0))/s; h = float(p.get("height", 0))/s
												x1 = int(max(0, x - w/2)); y1 = int(max(0, y - h/2))
												x2 = int(min(W, x + w/2)); y2 = int(min(H, y + h/2))
												# add to union mask for logo placement
												try:
													_cv2.rectangle(mask_logo, (x1, y1), (x2, y2), 255, -1)
												except Exception:
													pass
											except Exception:
												leftover = True; break
										# gate: OCR or sharpness (lower sharpness threshold)
										if _roi_sharp(gray_wm, x1, y1, x2, y2) > 5.0 or _roi_has_text(x1,y1,x2,y2):
											leftover = True; break
									if leftover: break
								except Exception:
									continue
							# If verification produced no mask at all, treat as leftover -> require override
							if not mask_logo.any():
								leftover = True
							# If no leftover sharp regions -> accept Watermarkly unless strict override requested
							if not leftover and not force_override:
								ct = (resp.headers.get("Content-Type") or "image/jpeg").split(";", 1)[0].strip()
								try:
									# stamp logo using union of verify detections
									stamped = False
									if mask_logo.any():
										try:
											ker = _cv2.getStructuringElement(_cv2.MORPH_ELLIPSE, (3, 3))
											mask_logo = _cv2.erode(mask_logo, ker, iterations=1)
										except Exception:
											pass
										img_out2 = _stamp_logo_on_mask(img_wm, mask_logo)
										stamped = True
									if stamped:
										ext = ".png" if "png" in ct else ".jpg"
										enc_mime = "image/png" if ext == ".png" else "image/jpeg"
										ok_out2, enc_out2 = _cv2.imencode(ext, img_out2, [int(_cv2.IMWRITE_JPEG_QUALITY), 92] if ext == ".jpg" else [])
										if ok_out2:
											rsp_ok2 = send_file(io.BytesIO(enc_out2.tobytes()), mimetype=enc_mime, as_attachment=False, download_name=f"blurred_{filename}")
											rsp_ok2.headers["X-Blur-Path"] = "wm"
											rsp_ok2.headers["X-WM-Region"] = (os.getenv("WATERMARKLY_REGION") or "auto").upper()
											rsp_ok2.headers["X-Logo-Stamped"] = "1"
											return rsp_ok2
								except Exception:
									pass
								# Final fallback: estimate blurred region by diff(ORIG vs WM) and stamp exactly on that region
								try:
									m_diff = _estimate_blur_mask_from_diff(img_orig, img_wm)
									if m_diff is not None and m_diff.any():
										img_out2 = _stamp_logo_on_mask(img_wm, m_diff)
										ok_out2, enc_out2 = _cv2.imencode(".jpg", img_out2, [int(_cv2.IMWRITE_JPEG_QUALITY), 92])
										if ok_out2:
											rsp_ok2 = send_file(io.BytesIO(enc_out2.tobytes()), mimetype="image/jpeg", as_attachment=False, download_name=f"blurred_{filename}")
											rsp_ok2.headers["X-Blur-Path"] = "wm"
											rsp_ok2.headers["X-WM-Region"] = (os.getenv("WATERMARKLY_REGION") or "auto").upper()
											rsp_ok2.headers["X-Logo-Stamped"] = "1"
											return rsp_ok2
								except Exception:
									pass
								# If stamping failed entirely, treat as leftover so YOLO override kicks in
								leftover = True
							# Step B: detect on ORIGINAL (pre-WM) to create union mask; lower conf to catch weak plates
							try:
								_conf_f = max(0.18, float(conf))
							except Exception:
								_conf_f = 0.28
							base_params = f"?api_key={api_key}&confidence={_conf_f:.2f}&overlap={overlap}&format=json"
							if include_mask:
								base_params += "&include_mask=true"
							url_base = f"https://detect.roboflow.com/{model_slug}/{version}"
							# Multi-scale TTA: union masks from 1.0, 1.25, 1.5, 1.75, 2.0
							scales = [1.0, 1.25, 1.5, 1.75, 2.0]
							m2 = _np.zeros((H, W), _np.uint8)
							for s in scales:
								try:
									if s == 1.0:
										img_s = img_orig
									else:
										img_s = _cv2.resize(img_orig, None, fx=s, fy=s, interpolation=_cv2.INTER_LINEAR)
									ok2, enc2 = _cv2.imencode(".jpg", img_s, [int(_cv2.IMWRITE_JPEG_QUALITY), 92])
									if not ok2:
										continue
									url = url_base + base_params
									rv = requests.post(url, files={"file": ("orig.jpg", enc2.tobytes(), "image/jpeg")}, timeout=60)
									if rv.status_code != 200:
										continue
									jv = rv.json()
									for p in jv.get("predictions", []) or []:
										points = p.get("points") or []
										if isinstance(points, list) and len(points) >= 3:
											try:
												if isinstance(points[0], dict):
													pts_s = _np.array([[float(pt["x"])/s, float(pt["y"])/s] for pt in points], _np.int32)
												else:
													pts_s = _np.array([[float(pt[0])/s, float(pt[1])/s] for pt in points], _np.int32)
												_cv2.fillPoly(m2, [pts_s], 255)
												continue
											except Exception:
												pass
										try:
											x = float(p.get("x", 0))/s; y = float(p.get("y", 0))/s
											w = float(p.get("width", 0))/s; h = float(p.get("height", 0))/s
											x1 = max(0, int(x - w/2)); y1 = max(0, int(y - h/2))
											x2 = min(W, int(x + w/2)); y2 = min(H, int(y + h/2))
											_cv2.rectangle(m2, (x1, y1), (x2, y2), 255, -1)
										except Exception:
											continue
								except Exception:
									continue
							if m2.any():
								try:
									ker5 = _cv2.getStructuringElement(_cv2.MORPH_ELLIPSE, (5, 5))
									# Seal gaps then expand slightly to ensure coverage
									m2 = _cv2.morphologyEx(m2, _cv2.MORPH_CLOSE, ker5, iterations=2)
									m2 = _cv2.dilate(m2, ker5, iterations=1)
								except Exception:
									pass
								k = max(31, int(min(H, W) * 0.07)) | 1
								blurred = _cv2.GaussianBlur(img_wm, (k, k), 0)
								out = _np.where(_cv2.merge([m2]*3) == 255, blurred, img_wm)
								# Stamp logo on overlayed mask
								try:
									out = _stamp_logo_on_mask(out, m2)
								except Exception:
									pass
								ok3, enc3 = _cv2.imencode(".jpg", out, [int(_cv2.IMWRITE_JPEG_QUALITY), 92])
								if ok3:
									rsp2 = send_file(io.BytesIO(enc3.tobytes()), mimetype="image/jpeg", as_attachment=False, download_name=f"blurred_{filename}")
									rsp2.headers["X-Blur-Path"] = "wm+override"
									rsp2.headers["X-WM-Region"] = (os.getenv("WATERMARKLY_REGION") or "auto").upper()
									rsp2.headers["X-Logo-Stamped"] = "1"
									rsp2.headers["X-Override-Source"] = "roboflow"
									return rsp2
							# If Roboflow produced no detections, fallback to local YOLO weights (Ultralytics)
							try:
								m_local = _local_yolo_plate_mask(img_orig)
								if m_local is not None and m_local.any():
									# Ensure mask matches WM image size if needed
									if m_local.shape[0] != H or m_local.shape[1] != W:
										m_local = _cv2.resize(m_local, (W, H), interpolation=_cv2.INTER_NEAREST)
									try:
										ker5 = _cv2.getStructuringElement(_cv2.MORPH_ELLIPSE, (5, 5))
										m_local = _cv2.morphologyEx(m_local, _cv2.MORPH_CLOSE, ker5, iterations=2)
										m_local = _cv2.dilate(m_local, ker5, iterations=1)
									except Exception:
										pass
									k = max(31, int(min(H, W) * 0.07)) | 1
									blurred = _cv2.GaussianBlur(img_wm, (k, k), 0)
									out = _np.where(_cv2.merge([m_local]*3) == 255, blurred, img_wm)
									try:
										out = _stamp_logo_on_mask(out, m_local)
									except Exception:
										pass
									ok3, enc3 = _cv2.imencode(".jpg", out, [int(_cv2.IMWRITE_JPEG_QUALITY), 92])
									if ok3:
										rsp2 = send_file(io.BytesIO(enc3.tobytes()), mimetype="image/jpeg", as_attachment=False, download_name=f"blurred_{filename}")
										rsp2.headers["X-Blur-Path"] = "wm+override"
										rsp2.headers["X-WM-Region"] = (os.getenv("WATERMARKLY_REGION") or "auto").upper()
										rsp2.headers["X-Logo-Stamped"] = "1"
										rsp2.headers["X-Override-Source"] = "local-yolo"
										return rsp2
							except Exception:
								pass
				except Exception:
					# If verify fails, still try to stamp logo on WM result
					try:
						import numpy as _np
						import cv2 as _cv2
						img_arr = _np.frombuffer(resp.content, dtype=_np.uint8)
						img_wm = _cv2.imdecode(img_arr, _cv2.IMREAD_COLOR)
						img_orig = _cv2.imdecode(_np.frombuffer(img_bytes, dtype=_np.uint8), _cv2.IMREAD_COLOR)
						if img_wm is not None:
							out_try = _try_stamp_logo_using_rf_on_image(img_wm)
							stamped = not _np.array_equal(out_try, img_wm)
							# If Roboflow stamping finds nothing, try local YOLO/diff-mask override before returning WM.
							if not stamped and (os.getenv("LOCAL_YOLO_FALLBACK") or "1").strip().lower() in ("1", "true", "yes"):
								try:
									Ht, Wt = img_wm.shape[:2]
									# Prefer local YOLO mask on original
									if img_orig is not None:
										m_local = _local_yolo_plate_mask(img_orig)
									else:
										m_local = None
									if m_local is not None and m_local.any():
										if m_local.shape[0] != Ht or m_local.shape[1] != Wt:
											m_local = _cv2.resize(m_local, (Wt, Ht), interpolation=_cv2.INTER_NEAREST)
										k = max(31, int(min(Ht, Wt) * 0.07)) | 1
										blurred = _cv2.GaussianBlur(img_wm, (k, k), 0)
										out2 = _np.where(_cv2.merge([m_local]*3) == 255, blurred, img_wm)
										try:
											out2 = _stamp_logo_on_mask(out2, m_local)
										except Exception:
											pass
										ok2, enc2 = _cv2.imencode(".jpg", out2, [int(_cv2.IMWRITE_JPEG_QUALITY), 92])
										if ok2:
											rsp2 = send_file(io.BytesIO(enc2.tobytes()), mimetype="image/jpeg", as_attachment=False, download_name=f"blurred_{filename}")
											rsp2.headers["X-Blur-Path"] = "wm+override"
											rsp2.headers["X-WM-Region"] = (os.getenv("WATERMARKLY_REGION") or "auto").upper()
											rsp2.headers["X-Logo-Stamped"] = "1"
											rsp2.headers["X-Override-Source"] = "local-yolo"
											return rsp2
									# Final fallback: diff mask
									if img_orig is not None:
										m_diff = _estimate_blur_mask_from_diff(img_orig, img_wm)
									else:
										m_diff = None
									if m_diff is not None and m_diff.any():
										if m_diff.shape[0] != Ht or m_diff.shape[1] != Wt:
											m_diff = _cv2.resize(m_diff, (Wt, Ht), interpolation=_cv2.INTER_NEAREST)
										k = max(31, int(min(Ht, Wt) * 0.07)) | 1
										blurred = _cv2.GaussianBlur(img_wm, (k, k), 0)
										out2 = _np.where(_cv2.merge([m_diff]*3) == 255, blurred, img_wm)
										try:
											out2 = _stamp_logo_on_mask(out2, m_diff)
										except Exception:
											pass
										ok2, enc2 = _cv2.imencode(".jpg", out2, [int(_cv2.IMWRITE_JPEG_QUALITY), 92])
										if ok2:
											rsp2 = send_file(io.BytesIO(enc2.tobytes()), mimetype="image/jpeg", as_attachment=False, download_name=f"blurred_{filename}")
											rsp2.headers["X-Blur-Path"] = "wm+override"
											rsp2.headers["X-WM-Region"] = (os.getenv("WATERMARKLY_REGION") or "auto").upper()
											rsp2.headers["X-Logo-Stamped"] = "1"
											rsp2.headers["X-Override-Source"] = "diff-mask"
											return rsp2
								except Exception:
									pass
							okx, encx = _cv2.imencode(".jpg", out_try, [int(_cv2.IMWRITE_JPEG_QUALITY), 92])
							if okx:
								rsp_ok = send_file(io.BytesIO(encx.tobytes()), mimetype="image/jpeg", as_attachment=False, download_name=f"blurred_{filename}")
								rsp_ok.headers["X-Blur-Path"] = "wm"
								rsp_ok.headers["X-WM-Region"] = (os.getenv("WATERMARKLY_REGION") or "auto").upper()
								rsp_ok.headers["X-Logo-Stamped"] = "1" if stamped else "0"
								return rsp_ok
					except Exception:
						pass
				ct = (resp.headers.get("Content-Type") or "image/jpeg").split(";", 1)[0].strip()
				# Last-chance: if Roboflow gave no detections (common failure mode),
				# try local YOLO weights, then diff-mask, before returning raw WM output.
				_attempted_last_chance = False
				try:
					if (os.getenv("LOCAL_YOLO_FALLBACK") or "1").strip().lower() in ("1", "true", "yes"):
						_attempted_last_chance = True
						import numpy as _np
						import cv2 as _cv2
						img_wm2 = _cv2.imdecode(_np.frombuffer(resp.content, dtype=_np.uint8), _cv2.IMREAD_COLOR)
						img_orig2 = _cv2.imdecode(_np.frombuffer(img_bytes, dtype=_np.uint8), _cv2.IMREAD_COLOR)
						if img_wm2 is not None and img_orig2 is not None:
							H2, W2 = img_wm2.shape[:2]
							# 1) Local YOLO mask on original
							m_local2 = _local_yolo_plate_mask(img_orig2)
							if m_local2 is not None and m_local2.any():
								if m_local2.shape[0] != H2 or m_local2.shape[1] != W2:
									m_local2 = _cv2.resize(m_local2, (W2, H2), interpolation=_cv2.INTER_NEAREST)
								k = max(31, int(min(H2, W2) * 0.07)) | 1
								blurred2 = _cv2.GaussianBlur(img_wm2, (k, k), 0)
								out2 = _np.where(_cv2.merge([m_local2]*3) == 255, blurred2, img_wm2)
								try:
									out2 = _stamp_logo_on_mask(out2, m_local2)
								except Exception:
									pass
								ok2, enc2 = _cv2.imencode(".jpg", out2, [int(_cv2.IMWRITE_JPEG_QUALITY), 92])
								if ok2:
									rsp2 = send_file(io.BytesIO(enc2.tobytes()), mimetype="image/jpeg", as_attachment=False, download_name=f"blurred_{filename}")
									rsp2.headers["X-Blur-Path"] = "wm+override"
									rsp2.headers["X-WM-Region"] = (os.getenv("WATERMARKLY_REGION") or "auto").upper()
									rsp2.headers["X-Logo-Stamped"] = "1"
									rsp2.headers["X-Override-Source"] = "local-yolo"
									return rsp2
							# 2) Diff-based mask as final safety net
							try:
								m_diff2 = _estimate_blur_mask_from_diff(img_orig2, img_wm2)
							except Exception:
								m_diff2 = None
							if m_diff2 is not None and m_diff2.any():
								if m_diff2.shape[0] != H2 or m_diff2.shape[1] != W2:
									m_diff2 = _cv2.resize(m_diff2, (W2, H2), interpolation=_cv2.INTER_NEAREST)
								k = max(31, int(min(H2, W2) * 0.07)) | 1
								blurred2 = _cv2.GaussianBlur(img_wm2, (k, k), 0)
								out2 = _np.where(_cv2.merge([m_diff2]*3) == 255, blurred2, img_wm2)
								try:
									out2 = _stamp_logo_on_mask(out2, m_diff2)
								except Exception:
									pass
								ok2, enc2 = _cv2.imencode(".jpg", out2, [int(_cv2.IMWRITE_JPEG_QUALITY), 92])
								if ok2:
									rsp2 = send_file(io.BytesIO(enc2.tobytes()), mimetype="image/jpeg", as_attachment=False, download_name=f"blurred_{filename}")
									rsp2.headers["X-Blur-Path"] = "wm+override"
									rsp2.headers["X-WM-Region"] = (os.getenv("WATERMARKLY_REGION") or "auto").upper()
									rsp2.headers["X-Logo-Stamped"] = "1"
									rsp2.headers["X-Override-Source"] = "diff-mask"
									return rsp2
				except Exception:
					pass
				rsp_ok = send_file(io.BytesIO(resp.content), mimetype=ct, as_attachment=False, download_name=f"blurred_{filename}")
				rsp_ok.headers["X-Blur-Path"] = "wm"
				rsp_ok.headers["X-WM-Region"] = (os.getenv("WATERMARKLY_REGION") or "auto").upper()
				rsp_ok.headers["X-Logo-Stamped"] = "0"
				if _attempted_last_chance:
					rsp_ok.headers["X-Override-Attempted"] = "1"
				return rsp_ok
		except Exception:
			pass  # fall through to Roboflow

	# 2) Fallback: use Roboflow detection/segmentation and blur locally
	try:
		model_slug = (os.getenv("ROBOFLOW_MODEL") or os.getenv("ROBOFLOW_MODEL_SLUG") or "").strip()
		if "/" in model_slug:
			parts = model_slug.split("/", 1)
			model_slug = parts[0].strip()
			if not os.getenv("ROBOFLOW_VERSION"):
				os.environ["ROBOFLOW_VERSION"] = (parts[1] or "1").strip()
		version = (os.getenv("ROBOFLOW_VERSION") or "1").strip()
		api_key = (os.getenv("ROBOFLOW_API_KEY") or "").strip()
		conf = (os.getenv("ROBOFLOW_CONFIDENCE") or "0.28").strip()
		overlap = (os.getenv("ROBOFLOW_OVERLAP") or "0.50").strip()
		include_mask = (os.getenv("ROBOFLOW_INCLUDE_MASK") or "true").strip().lower() in ("1", "true", "yes")
		if not api_key or not model_slug or not version:
			return jsonify({"error": "Roboflow not configured for fallback"}), 500

		# Save to temp for upload to Roboflow
		with tempfile.NamedTemporaryFile(suffix=".jpg", delete=False) as tmp:
			tmp.write(img_bytes)
			tmp_path = tmp.name

		params = f"?api_key={api_key}&confidence={conf}&overlap={overlap}&format=json"
		if include_mask:
			params += "&include_mask=true"
		url = f"https://detect.roboflow.com/{model_slug}/{version}{params}"
		with open(tmp_path, "rb") as fh:
			r = requests.post(url, files={"file": fh}, timeout=60)
		if r.status_code != 200:
			return jsonify({"error": "RoboflowError", "status": r.status_code, "body": r.text[:400]}), 502
		j = r.json()

		# Build blur from predictions
		import numpy as _np
		import cv2 as _cv2
		img_arr = _np.frombuffer(img_bytes, dtype=_np.uint8)
		img = _cv2.imdecode(img_arr, _cv2.IMREAD_COLOR)
		if img is None:
			return jsonify({"error": "DecodeFailed"}), 400
		H, W = img.shape[:2]
		mask = _np.zeros((H, W), _np.uint8)
		for p in j.get("predictions", []) or []:
			points = p.get("points") or []
			if isinstance(points, list) and len(points) >= 3:
				# points may be list[dict{x,y}] or list[[x,y]]
				try:
					if isinstance(points[0], dict):
						pts = _np.array([[float(pt["x"]), float(pt["y"])] for pt in points], _np.int32)
					else:
						pts = _np.array([[float(pt[0]), float(pt[1])] for pt in points], _np.int32)
					_cv2.fillPoly(mask, [pts], 255)
					continue
				except Exception:
					pass
			# fallback rectangle
			try:
				x = float(p.get("x", 0)); y = float(p.get("y", 0))
				w = float(p.get("width", 0)); h = float(p.get("height", 0))
				x1, y1 = max(0, int(x - w / 2)), max(0, int(y - h / 2))
				x2, y2 = min(W, int(x + w / 2)), min(H, int(y + h / 2))
				# slight shrink to avoid spill
				m = int(0.04 * min(max(1, x2 - x1), max(1, y2 - y1)))
				x1 = max(0, x1 + m); y1 = max(0, y1 + m); x2 = min(W, x2 - m); y2 = min(H, y2 - m)
				if x2 > x1 and y2 > y1:
					_cv2.rectangle(mask, (x1, y1), (x2, y2), 255, thickness=-1)
			except Exception:
				continue

		if mask.any():
			try:
				ker = _cv2.getStructuringElement(_cv2.MORPH_ELLIPSE, (3, 3))
				mask = _cv2.erode(mask, ker, iterations=1)
			except Exception:
				pass
			k = max(31, int(min(H, W) * 0.07)) | 1
			blurred = _cv2.GaussianBlur(img, (k, k), 0)
			out = _np.where(_cv2.merge([mask]*3) == 255, blurred, img)
			# Stamp logo on mask
			try:
				out = _stamp_logo_on_mask(out, mask)
			except Exception:
				pass
		else:
			out = img
		ok, enc = _cv2.imencode(".jpg", out, [int(_cv2.IMWRITE_JPEG_QUALITY), 92])
		if not ok:
			return jsonify({"error": "EncodeFailed"}), 500
		rsp_fb = send_file(io.BytesIO(enc.tobytes()), mimetype="image/jpeg", as_attachment=False, download_name=f"blurred_{filename}")
		rsp_fb.headers["X-Blur-Path"] = "fallback"
		rsp_fb.headers["X-WM-Region"] = (os.getenv("WATERMARKLY_REGION") or "auto").upper()
		rsp_fb.headers["X-Logo-Stamped"] = "1" if mask.any() else "0"
		return rsp_fb
	except Exception as e:
		return jsonify({"error": "AutoRouteError", "message": str(e)}), 500

# API alias so clients calling /api/blur-license-plate-auto hit the same handler
@app.route("/api/blur-license-plate-auto", methods=["POST"])
def blur_license_plate_auto_alias():
	return blur_license_plate_auto()

# Transparent proxy for all other API requests so the app can use one API_BASE
@app.route("/api/<path:subpath>", methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"])
def proxy_api(subpath: str):
	# Do NOT proxy the local blur endpoint here (it is handled above)
	if subpath == "blur-license-plate-auto":
		return blur_license_plate_auto_alias()
	if not LISTINGS_API_BASE:
		return jsonify({"error": "ProxyNotConfigured", "message": "Set LISTINGS_API_BASE to your listings API base (no /api)."}), 500
	try:
		import requests as _rq
		target = f"{LISTINGS_API_BASE}/api/{subpath}"
		params = request.args.to_dict(flat=False)
		# Build headers but avoid hop-by-hop/host and DO NOT forward content-type for multipart; requests will set it with boundary
		hdrs = {
			k: v
			for k, v in request.headers.items()
			if k.lower() not in ("host", "content-length", "transfer-encoding", "content-type")
		}
		method = request.method.upper()
		# Handle multipart forms
		files = None
		data = None
		json_body = None
		if request.files:
			logger.info(f"[proxy] incoming multipart fields: {list(request.files.keys())} to {target}")
			# Compatibility: some clients send images[]/files[]; also backend expects 'image' or 'images'
			files = []
			for key in request.files.keys():
				for storage in request.files.getlist(key):
					try:
						# Read file content to ensure forwarding is not empty
						content = storage.read()
						import io as _io
						buf = _io.BytesIO(content if isinstance(content, (bytes, bytearray)) else storage.stream.read())
					except Exception:
						try:
							import io as _io
							buf = _io.BytesIO(storage.stream.read())
						except Exception:
							buf = None
					fn = storage.filename or "upload.jpg"
					mt = storage.mimetype or "application/octet-stream"
					if buf is not None:
						# Attach with canonical 'images' key and original key
						files.append(("images", (fn, buf, mt)))
						buf2 = _io.BytesIO(buf.getvalue())
						files.append((key, (fn, buf2, mt)))
			data = request.form.to_dict(flat=False)
		else:
			ctype = request.headers.get("Content-Type", "")
			if "application/json" in ctype:
				json_body = request.get_json(silent=True)
			else:
				data = request.get_data()
		logger.info(f"[proxy] forwarding file parts: {0 if files is None else len(files)} to {target}")
		# Longer timeout for multipart uploads; standard for others
		_has_multipart = (files is not None) or ("multipart/form-data" in (request.headers.get("Content-Type") or ""))
		_timeout_s = 600 if (method == "POST" and _has_multipart) else 60
		resp = _rq.request(method, target, params=params, headers=hdrs, data=data, json=json_body, files=files, timeout=_timeout_s, stream=False)
		from flask import Response as _FlaskResp
		exclude = {"Content-Encoding", "Transfer-Encoding", "Connection"}
		resp_headers = [(k, v) for k, v in resp.headers.items() if k not in exclude]
		return _FlaskResp(resp.content, status=resp.status_code, headers=resp_headers)
	except Exception as e:
		logger.exception("Proxy error")
		return jsonify({"error": "ProxyError", "message": str(e)}), 502

@app.route("/static/uploads/<path:subpath>", methods=["GET", "HEAD"])
def static_uploads_local(subpath: str):
	"""
	Serve images directly from local filesystem if present to avoid 404s due to
	mismatched static roots. Falls back to proxying to the listings server.
	Checks both repo_root/static/uploads and kk/static/uploads.
	"""
	try:
		repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
		candidates = [
			os.path.join(repo_root, "static", "uploads", subpath),
			os.path.join(repo_root, "kk", "static", "uploads", subpath),
		]
		for p in candidates:
			if os.path.isfile(p):
				# Best-effort content type based on extension; let client sniff otherwise
				return send_file(p, as_attachment=False, download_name=os.path.basename(p))
	except Exception:
		pass
	# Fallback to proxy to listings server static
	return proxy_uploads(subpath)

@app.route("/static/images/<path:subpath>", methods=["GET", "HEAD"])
def static_images_local(subpath: str):
	"""
	Serve brand and other images from local repo paths before proxying.
	Looks under static/images and kk/static/images.
	"""
	try:
		repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
		candidates = [
			os.path.join(repo_root, "static", "images", subpath),
			os.path.join(repo_root, "kk", "static", "images", subpath),
		]
		for p in candidates:
			if os.path.isfile(p):
				return send_file(p, as_attachment=False, download_name=os.path.basename(p))
	except Exception:
		pass
	# Fallback to proxy to listings server static/images
	if not LISTINGS_API_BASE:
		return jsonify({"error": "ProxyNotConfigured", "message": "Set LISTINGS_API_BASE to your listings API base (no /api)."}), 500
	try:
		import requests as _rq
		target = f"{LISTINGS_API_BASE}/static/images/{subpath}"
		params = request.args.to_dict(flat=False)
		resp = _rq.request(request.method, target, params=params, headers={k: v for k, v in request.headers.items() if k.lower() != "host"}, timeout=60, stream=False)
		from flask import Response as _FlaskResp
		exclude = {"Content-Encoding", "Transfer-Encoding", "Connection"}
		resp_headers = [(k, v) for k, v in resp.headers.items() if k not in exclude]
		return _FlaskResp(resp.content, status=resp.status_code, headers=resp_headers)
	except Exception as e:
		logger.exception("Static images proxy error")
		return jsonify({"error": "ProxyError", "message": str(e)}), 502

@app.route("/static/<path:subpath>", methods=["GET", "HEAD"])
def proxy_static(subpath: str):
	if not LISTINGS_API_BASE:
		return jsonify({"error": "ProxyNotConfigured", "message": "Set LISTINGS_API_BASE to your listings API base (no /api)."}), 500
	try:
		import requests as _rq
		target = f"{LISTINGS_API_BASE}/static/{subpath}"
		params = request.args.to_dict(flat=False)
		resp = _rq.request(request.method, target, params=params, headers={k: v for k, v in request.headers.items() if k.lower() != "host"}, timeout=60, stream=False)
		from flask import Response as _FlaskResp
		exclude = {"Content-Encoding", "Transfer-Encoding", "Connection"}
		resp_headers = [(k, v) for k, v in resp.headers.items() if k not in exclude]
		return _FlaskResp(resp.content, status=resp.status_code, headers=resp_headers)
	except Exception as e:
		logger.exception("Static proxy error")
		return jsonify({"error": "ProxyError", "message": str(e)}), 502

@app.route("/uploads/<path:subpath>", methods=["GET", "HEAD"])
def proxy_uploads(subpath: str):
	# Convenience: map /uploads/* -> listings /static/uploads/*
	if not LISTINGS_API_BASE:
		return jsonify({"error": "ProxyNotConfigured", "message": "Set LISTINGS_API_BASE to your listings API base (no /api)."}), 500
	try:
		import requests as _rq
		target = f"{LISTINGS_API_BASE}/static/uploads/{subpath}"
		params = request.args.to_dict(flat=False)
		resp = _rq.request(request.method, target, params=params, headers={k: v for k, v in request.headers.items() if k.lower() != "host"}, timeout=60, stream=False)
		from flask import Response as _FlaskResp
		exclude = {"Content-Encoding", "Transfer-Encoding", "Connection"}
		resp_headers = [(k, v) for k, v in resp.headers.items() if k not in exclude]
		return _FlaskResp(resp.content, status=resp.status_code, headers=resp_headers)
	except Exception as e:
		logger.exception("Uploads proxy error")
		return jsonify({"error": "ProxyError", "message": str(e)}), 502

@app.route("/car_photos/<path:subpath>", methods=["GET", "HEAD"])
def proxy_car_photos(subpath: str):
	# Convenience: map /car_photos/* -> listings /static/uploads/car_photos/*
	if not LISTINGS_API_BASE:
		return jsonify({"error": "ProxyNotConfigured", "message": "Set LISTINGS_API_BASE to your listings API base (no /api)."}), 500
	try:
		import requests as _rq
		target = f"{LISTINGS_API_BASE}/static/uploads/car_photos/{subpath}"
		params = request.args.to_dict(flat=False)
		resp = _rq.request(request.method, target, params=params, headers={k: v for k, v in request.headers.items() if k.lower() != "host"}, timeout=60, stream=False)
		from flask import Response as _FlaskResp
		exclude = {"Content-Encoding", "Transfer-Encoding", "Connection"}
		resp_headers = [(k, v) for k, v in resp.headers.items() if k not in exclude]
		return _FlaskResp(resp.content, status=resp.status_code, headers=resp_headers)
	except Exception as e:
		logger.exception("Car photos proxy error")
		return jsonify({"error": "ProxyError", "message": str(e)}), 502

# No-op analytics endpoint to avoid 500s blocking UI if upstream lacks it
@app.route("/api/analytics/track/view", methods=["POST"])
def analytics_track_view_noop():
	try:
		payload = request.get_json(silent=True) or {}
		logger.info(f"[analytics] view: {payload}")
	except Exception:
		pass
	return jsonify({"ok": True}), 200

def create_app():
	return app

if __name__ == "__main__":
	port = int(os.getenv("PORT", "5000"))
	app.run(host="0.0.0.0", port=port, debug=False)