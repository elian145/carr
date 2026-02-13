from __future__ import annotations

import base64
import logging
import os
import re
from dataclasses import dataclass
from typing import Any, Dict, Iterable, List, Optional, Tuple

import requests

logger = logging.getLogger(__name__)

_API_KEY_RE = re.compile(r"(api_key=)([^&\s]+)", re.IGNORECASE)

def _env() -> str:
	return (os.environ.get("APP_ENV") or os.environ.get("FLASK_ENV") or "production").strip().lower()

def _public_error(msg: str) -> str:
	# In production, don't leak stack traces / dependency paths / internal details.
	return msg if _env() in ("development", "testing") else "internal_error"


def _redact_api_key(message: str) -> str:
	"""Redact api_key query parameter to avoid leaking secrets in logs/metadata."""
	if not message:
		return message
	try:
		return _API_KEY_RE.sub(r"\1REDACTED", message)
	except Exception:
		return "REDACTED"


@dataclass(frozen=True)
class PlateBox:
	"""Axis-aligned bounding box in pixel coordinates (x1,y1,x2,y2)."""

	x1: int
	y1: int
	x2: int
	y2: int
	confidence: Optional[float] = None

	def clamp(self, width: int, height: int) -> "PlateBox":
		x1 = max(0, min(self.x1, width))
		y1 = max(0, min(self.y1, height))
		x2 = max(0, min(self.x2, width))
		y2 = max(0, min(self.y2, height))
		# Ensure proper ordering
		if x2 < x1:
			x1, x2 = x2, x1
		if y2 < y1:
			y1, y2 = y2, y1
		return PlateBox(x1=x1, y1=y1, x2=x2, y2=y2, confidence=self.confidence)

	def expand(self, ratio: float) -> "PlateBox":
		w = max(0, self.x2 - self.x1)
		h = max(0, self.y2 - self.y1)
		pad_x = int(round(w * ratio))
		pad_y = int(round(h * ratio))
		return PlateBox(
			x1=self.x1 - pad_x,
			y1=self.y1 - pad_y,
			x2=self.x2 + pad_x,
			y2=self.y2 + pad_y,
			confidence=self.confidence,
		)


class RoboflowPlateDetector:
	"""
	Roboflow Hosted API client for plate bounding boxes.

	This implements the same payload shape as your curl example:
	- send raw base64 string in the POST body to:
	  https://serverless.roboflow.com/<project>/<version>?api_key=...
	"""

	def __init__(
		self,
		*,
		api_key: str,
		project: str = "plate-detector-i9vkk",
		version: str = "5",
		endpoint_base: str = "https://serverless.roboflow.com",
		timeout_s: int = 60,
		confidence: Optional[int] = None,
		overlap: Optional[int] = None,
	) -> None:
		self.api_key = (api_key or "").strip()
		self.project = (project or "").strip()
		self.version = str(version).strip()
		self.endpoint_base = (endpoint_base or "").strip().rstrip("/")
		self.timeout_s = int(timeout_s)
		self.confidence = confidence
		self.overlap = overlap
		self._session = requests.Session()

	def is_configured(self) -> bool:
		return bool(self.api_key and self.project and self.version and self.endpoint_base)

	def _url(self) -> str:
		return f"{self.endpoint_base}/{self.project}/{self.version}"

	def detect_with_meta(self, image_bytes: bytes) -> Tuple[List[PlateBox], Dict[str, Any]]:
		if not self.is_configured():
			return [], {"detect_status": "not_configured"}

		try:
			b64 = base64.b64encode(image_bytes).decode("ascii")
			params: Dict[str, Any] = {"api_key": self.api_key}
			# Roboflow supports confidence/overlap query params (commonly as 0-100).
			if self.confidence is not None:
				params["confidence"] = int(self.confidence)
			if self.overlap is not None:
				params["overlap"] = int(self.overlap)
			resp = self._session.post(
				self._url(),
				params=params,
				data=b64,
				headers={"Content-Type": "application/x-www-form-urlencoded"},
				timeout=(5, self.timeout_s),
			)
			resp.raise_for_status()
			payload: Dict[str, Any] = resp.json() if resp.content else {}
		except Exception as e:
			# Avoid leaking the API key, which can appear in exception messages/URLs.
			msg = _redact_api_key(str(e))
			logger.warning("Roboflow plate detection request failed: %s", msg)
			return [], {"detect_status": "detect_failed", "detect_error": msg}

		preds = payload.get("predictions") or []
		if not isinstance(preds, list):
			return [], {"detect_status": "bad_response", "detect_keys": list(payload.keys())}

		boxes: List[PlateBox] = []
		for p in preds:
			if not isinstance(p, dict):
				continue
			try:
				# Roboflow returns center-x/center-y with width/height (pixels)
				x = float(p.get("x"))
				y = float(p.get("y"))
				w = float(p.get("width"))
				h = float(p.get("height"))
				if w <= 0 or h <= 0:
					continue
				x1 = int(round(x - (w / 2.0)))
				y1 = int(round(y - (h / 2.0)))
				x2 = int(round(x + (w / 2.0)))
				y2 = int(round(y + (h / 2.0)))
				conf = p.get("confidence")
				conf_f = float(conf) if conf is not None else None
				boxes.append(PlateBox(x1=x1, y1=y1, x2=x2, y2=y2, confidence=conf_f))
			except Exception:
				continue

		return boxes, {"detect_status": "ok", "predictions": len(preds), "confidence": self.confidence, "overlap": self.overlap}

	def detect(self, image_bytes: bytes) -> List[PlateBox]:
		"""Backward-compatible wrapper."""
		boxes, _ = self.detect_with_meta(image_bytes)
		return boxes


def _normalize_image_bytes_for_inference(image_bytes: bytes, output_ext: str) -> Tuple[bytes, Dict[str, Any]]:
	"""
	Normalize EXIF orientation before inference.

	Roboflow web UI typically displays images with EXIF orientation applied; raw byte uploads may not.
	This function applies EXIF transpose (if Pillow is available) and re-encodes to the same format.
	"""
	try:
		from PIL import Image, ImageOps  # type: ignore
		from io import BytesIO
	except Exception as e:
		return image_bytes, {"normalize_status": "pillow_missing", "normalize_error": _public_error(str(e))}

	try:
		# Allow PIL to open HEIC (iPhone) if pillow-heif is installed.
		try:
			import pillow_heif  # type: ignore
			pillow_heif.register_heif_opener()
		except Exception:
			pass

		ext = (output_ext or "").strip().lower()
		if not ext.startswith("."):
			ext = f".{ext}" if ext else ".jpg"
		fmt = "JPEG"
		if ext == ".png":
			fmt = "PNG"
		elif ext == ".webp":
			fmt = "WEBP"
		elif ext in (".jpg", ".jpeg"):
			fmt = "JPEG"
		elif ext in (".heic", ".heif"):
			# HEIC decode only; we output JPEG for inference/saving.
			fmt = "JPEG"
			ext = ".jpg"

		im = Image.open(BytesIO(image_bytes))
		im2 = ImageOps.exif_transpose(im)

		# JPEG cannot store alpha
		if fmt == "JPEG" and im2.mode not in ("RGB", "L"):
			im2 = im2.convert("RGB")

		out = BytesIO()
		save_kwargs: Dict[str, Any] = {}
		if fmt == "JPEG":
			save_kwargs.update({"quality": 95, "optimize": True})
		elif fmt == "PNG":
			save_kwargs.update({"optimize": True})
		elif fmt == "WEBP":
			save_kwargs.update({"quality": 92, "method": 4})
		im2.save(out, format=fmt, **save_kwargs)
		return out.getvalue(), {"normalize_status": "normalized", "normalize_format": fmt}
	except Exception as e:
		# If anything goes wrong, fall back to original bytes
		return image_bytes, {"normalize_status": "normalize_failed", "normalize_error": _public_error(str(e))}


def _odd(n: int) -> int:
	return n if (n % 2 == 1) else (n + 1)


def _kernel_for_roi(w: int, h: int) -> int:
	# Kernel size scales with ROI but stays within reasonable bounds.
	min_dim = max(1, min(w, h))
	# ~60% of min dimension gives strong blur while preserving performance.
	k = int(round(min_dim * 0.6))
	k = max(k, 15)
	k = min(k, 151)
	return _odd(k)


def blur_license_plates(
	*,
	image_bytes: bytes,
	output_ext: str,
	detector: RoboflowPlateDetector,
	expand_ratio: float = 0.0,
) -> Tuple[bytes, Dict[str, Any]]:
	"""
	Blur detected plates and return new encoded image bytes.

	- If no plates are detected (or any error occurs), returns original bytes.
	- `expand_ratio` should be 0.10–0.15 to cover plate edges.
	"""

	# Import lazily so the app can still run even if opencv isn't installed yet.
	try:
		import cv2  # type: ignore
		import numpy as np  # type: ignore
	except Exception as e:
		return image_bytes, {"status": "opencv_missing", "error": _public_error(str(e))}

	try:
		# Normalize EXIF orientation *before* detection and decoding, so boxes match pixels.
		normalized_bytes, norm_meta = _normalize_image_bytes_for_inference(image_bytes, output_ext)

		arr = np.frombuffer(normalized_bytes, dtype=np.uint8)
		img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
		if img is None:
			return image_bytes, {**norm_meta, "status": "decode_failed"}
		height, width = img.shape[:2]

		# Roboflow needs the bytes; we use normalized bytes so orientation matches.
		boxes, det_meta = detector.detect_with_meta(normalized_bytes)
		if not boxes:
			# Distinguish "no plates" from request failures for debugging/observability.
			if det_meta.get("detect_status") in ("detect_failed", "bad_response"):
				return image_bytes, {**norm_meta, **det_meta, "status": "detect_failed"}
			return image_bytes, {**norm_meta, **det_meta, "status": "no_plates", "plates": 0}

		applied = 0
		ratio = float(expand_ratio)
		if ratio < 0:
			ratio = 0.0
		if ratio > 0.5:
			ratio = 0.5

		for b in boxes:
			# Expand then clamp to image bounds
			b2 = b.expand(ratio).clamp(width=width, height=height)
			w = b2.x2 - b2.x1
			h = b2.y2 - b2.y1
			if w < 6 or h < 6:
				continue
			roi = img[b2.y1 : b2.y2, b2.x1 : b2.x2]
			if roi.size == 0:
				continue
			k = _kernel_for_roi(w, h)
			blurred = cv2.GaussianBlur(roi, (k, k), 0)
			img[b2.y1 : b2.y2, b2.x1 : b2.x2] = blurred
			applied += 1

		if applied == 0:
			return image_bytes, {**norm_meta, **det_meta, "status": "no_valid_rois", "plates": len(boxes), "applied": 0}

		ext = (output_ext or "").strip().lower()
		if not ext.startswith("."):
			ext = f".{ext}" if ext else ".jpg"
		if ext not in (".jpg", ".jpeg", ".png", ".webp"):
			ext = ".jpg"

		encode_params: List[int] = []
		if ext in (".jpg", ".jpeg"):
			encode_params = [int(cv2.IMWRITE_JPEG_QUALITY), 92]
		elif ext == ".png":
			encode_params = [int(cv2.IMWRITE_PNG_COMPRESSION), 3]
		elif ext == ".webp":
			encode_params = [int(cv2.IMWRITE_WEBP_QUALITY), 90]

		ok, out = cv2.imencode(ext, img, encode_params)
		if not ok:
			return image_bytes, {**norm_meta, **det_meta, "status": "encode_failed", "plates": len(boxes), "applied": applied}

		return bytes(out.tobytes()), {**norm_meta, **det_meta, "status": "blurred", "plates": len(boxes), "applied": applied}
	except Exception as e:
		logger.warning("License-plate blurring failed: %s", e, exc_info=True)
		return image_bytes, {"status": "error", "error": _public_error(str(e))}


_DETECTOR_SINGLETON: Optional[RoboflowPlateDetector] = None


def get_plate_detector() -> RoboflowPlateDetector:
	"""
	Singleton detector configured from environment variables.

	Environment variables:
	- ROBOFLOW_API_KEY (required)
	- ROBOFLOW_MODEL (optional; format: "<project>/<version>", overrides ROBOFLOW_PROJECT/ROBOFLOW_VERSION)
	- ROBOFLOW_PROJECT (default: plate-detector-i9vkk)
	- ROBOFLOW_VERSION (default: 5)
	- ROBOFLOW_ENDPOINT_BASE (default: https://serverless.roboflow.com)
	- ROBOFLOW_TIMEOUT_S (default: 60)
	"""

	global _DETECTOR_SINGLETON
	if _DETECTOR_SINGLETON is not None:
		return _DETECTOR_SINGLETON

	api_key = os.getenv("ROBOFLOW_API_KEY", "").strip()

	# Convenience override: allow a single var to specify project+version.
	# Example: ROBOFLOW_MODEL="plate-detector-i9vkk/5"
	model = (os.getenv("ROBOFLOW_MODEL", "") or "").strip()
	project = os.getenv("ROBOFLOW_PROJECT", "plate-detector-i9vkk").strip()
	version = os.getenv("ROBOFLOW_VERSION", "5").strip()
	if model:
		try:
			p, v = model.split("/", 1)
			p = (p or "").strip()
			v = (v or "").strip()
			if p and v:
				project, version = p, v
		except Exception:
			# If malformed, ignore and fall back to ROBOFLOW_PROJECT/ROBOFLOW_VERSION.
			pass

	endpoint_base = os.getenv("ROBOFLOW_ENDPOINT_BASE", "https://serverless.roboflow.com").strip()
	timeout_s = int(os.getenv("ROBOFLOW_TIMEOUT_S", "60") or "60")

	def _to_percent(v: str) -> Optional[int]:
		s = (v or "").strip()
		if not s:
			return None
		try:
			f = float(s)
		except Exception:
			return None
		# Accept either 0-1.0 (fraction) or 0-100 (percent)
		if f <= 1.0:
			p = int(round(f * 100.0))
		else:
			p = int(round(f))
		# Clamp to Roboflow's typical 0-100 range
		if p < 0:
			p = 0
		if p > 100:
			p = 100
		return p

	# Default to lowest confidence (0) if not specified.
	confidence = _to_percent(os.getenv("ROBOFLOW_CONFIDENCE", "0"))
	overlap = _to_percent(os.getenv("ROBOFLOW_OVERLAP", ""))

	_DETECTOR_SINGLETON = RoboflowPlateDetector(
		api_key=api_key,
		project=project,
		version=version,
		endpoint_base=endpoint_base,
		timeout_s=timeout_s,
		confidence=confidence,
		overlap=overlap,
	)
	return _DETECTOR_SINGLETON

