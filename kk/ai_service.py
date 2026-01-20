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

# Pillow resampling compatibility (Pillow>=10 removed Image.ANTIALIAS)
try:
	from PIL import Image as _PIL_Image  # re-import to avoid shadow
	if not hasattr(_PIL_Image, 'ANTIALIAS'):
		_RES = getattr(_PIL_Image, 'Resampling', None)
		_PIL_Image.ANTIALIAS = getattr(_RES, 'LANCZOS', getattr(_PIL_Image, 'LANCZOS', getattr(_PIL_Image, 'BICUBIC', 1)))
except Exception:
	pass

class CarAnalysisService:
    def __init__(self):
        self.initialized = False
        self.ocr_reader = None
        self.license_plate_model = None
        self.model_is_generic = False
        # Cumulative stats for folder runs
        self._total_blur_stats = {'images': 0, 'plates': 0, 'fallbacks': 0}
        self._last_blur_stats = None
        self._initialize_models()
    
    def _post_blur_verify(self, processed_image, xa: int, ya: int, xb: int, yb: int) -> None:
        """
        Post-blur verification: re-run OCR on the blurred region and, if text that
        still looks like a license plate remains readable, strengthen obfuscation.
        This helps eliminate partial/insufficient blurs and ensures privacy.
        Controlled by:
          - PLATE_POST_VERIFY (default: true)
          - PLATE_VERIFY_CONF (default: 0.38)
          - PLATE_VERIFY_SOLID (default: true) - last resort solid box if needed
          - PLATE_VERIFY_PAD_RATIO (optional) - expand verify rect slightly (e.g., 0.06x,0.10y)
        """
        try:
            if not self._env_flag('PLATE_POST_VERIFY', True):
                return
            if self.ocr_reader is None:
                return
            import cv2
            import numpy as np
            import os as _os
            H, W = processed_image.shape[:2]
            xa = max(0, min(W - 1, xa)); xb = max(0, min(W, xb))
            ya = max(0, min(H - 1, ya)); yb = max(0, min(H, yb))
            if xb <= xa or yb <= ya:
                return
            # Optional small expansion to ensure borders are included
            try:
                pad_ratio = float(str(_os.getenv('PLATE_VERIFY_PAD_RATIO', '0.08')).strip())
            except Exception:
                pad_ratio = 0.08
            try:
                vpad_ratio = float(str(_os.getenv('PLATE_VERIFY_VPAD_RATIO', '0.12')).strip())
            except Exception:
                vpad_ratio = 0.12
            w_rect = xb - xa; h_rect = yb - ya
            pad_x = max(2, int(w_rect * pad_ratio))
            pad_y = max(2, int(h_rect * vpad_ratio))
            xa = max(0, xa - pad_x); xb = min(W, xb + pad_x)
            ya = max(0, ya - pad_y); yb = min(H, yb + pad_y)
            roi = processed_image[ya:yb, xa:xb]
            if roi.size == 0:
                return
            rgb = cv2.cvtColor(roi, cv2.COLOR_BGR2RGB)
            try:
                conf_th = float(str(os.getenv('PLATE_VERIFY_CONF', '0.25')))
            except Exception:
                conf_th = 0.25
            def looks_like_plate(_tx: str) -> bool:
                s = ''.join([c for c in str(_tx).upper() if c.isalnum()])
                return (3 <= len(s) <= 10) and any(ch.isalpha() for ch in s) and any(ch.isdigit() for ch in s)
            # Repeatable strengthening passes (configurable)
            _passes = 5
            try:
                _passes = int(os.getenv('PLATE_VERIFY_PASSES', '5'))
            except Exception:
                _passes = 5
            _passes = max(1, min(5, _passes))
            for _ in range(_passes):
                any_plate = False
                for (_bb, _tx, _cf) in self.ocr_reader.readtext(rgb):
                    cf = 0.0 if _cf is None else float(_cf)
                    if cf >= conf_th and looks_like_plate(_tx):
                        any_plate = True
                        break
                if not any_plate:
                    return
                # Strengthen blur: larger Gaussian, optional pixelation
                h, w = roi.shape[:2]
                k = int(max(31, min(231, int(min(h, w) * 0.60))))
                if k % 2 == 0: k += 1
                stronger = cv2.GaussianBlur(roi, (k, k), 0)
                try:
                    # Light pixelation overlay to destroy glyph structure
                    pw = max(8, w // 9); ph = max(6, h // 9)
                    tmp_small = cv2.resize(stronger, (pw, ph), interpolation=cv2.INTER_AREA)
                    stronger = cv2.resize(tmp_small, (w, h), interpolation=cv2.INTER_NEAREST)
                except Exception:
                    pass
                try:
                    stronger = self._apply_plate_obfuscation(roi, stronger)
                except Exception:
                    pass
                processed_image[ya:yb, xa:xb] = stronger
                roi = stronger
                rgb = cv2.cvtColor(roi, cv2.COLOR_BGR2RGB)
            # If still readable, apply solid fallback if enabled
            if self._env_flag('PLATE_VERIFY_SOLID', True):
                try:
                    med = np.median(roi.reshape(-1, roi.shape[2]), axis=0).astype(np.uint8)
                    processed_image[ya:yb, xa:xb] = np.full_like(roi, med)
                except Exception:
                    processed_image[ya:yb, xa:xb] = np.zeros_like(roi)
        except Exception:
            # Never fail the pipeline due to verification
            return

    def _post_blur_verify_mask(self, processed_image, xa: int, ya: int, xb: int, yb: int, mask_roi) -> None:
        """
        Post-blur verification constrained to a mask:
        - Runs OCR on the masked area only
        - If plate-like text still readable, strengthen blur ONLY inside mask
        - Repeat up to PLATE_VERIFY_PASSES (default 5)
        - Final fallback: solid block inside mask if still readable
        """
        try:
            if not self._env_flag('PLATE_POST_VERIFY', True):
                return
            if self.ocr_reader is None:
                return
            import cv2
            import numpy as np
            import os as _os
            H, W = processed_image.shape[:2]
            xa = max(0, min(W - 1, xa)); xb = max(0, min(W, xb))
            ya = max(0, min(H - 1, ya)); yb = max(0, min(H, yb))
            if xb <= xa or yb <= ya:
                return
            roi = processed_image[ya:yb, xa:xb]
            if roi.size == 0:
                return
            mask = (mask_roi.astype(np.uint8) > 0).astype(np.uint8)
            if mask.shape[:2] != roi.shape[:2]:
                try:
                    mask = cv2.resize(mask, (roi.shape[1], roi.shape[0]), interpolation=cv2.INTER_NEAREST)
                except Exception:
                    return
            # OCR conf threshold and passes
            try:
                conf_th = float(str(os.getenv('PLATE_VERIFY_CONF', '0.25')))
            except Exception:
                conf_th = 0.25
            passes = 5
            try:
                passes = int(os.getenv('PLATE_VERIFY_PASSES', '5'))
            except Exception:
                passes = 5
            passes = max(1, min(5, passes))
            # Helper: run OCR on masked area only
            def masked_ocr_readable(img_bgr) -> bool:
                masked = img_bgr.copy()
                inv = (mask == 0)
                masked[inv] = 0
                rgb = cv2.cvtColor(masked, cv2.COLOR_BGR2RGB)
                for (_bb, _tx, _cf) in self.ocr_reader.readtext(rgb):
                    cf = 0.0 if _cf is None else float(_cf)
                    s = ''.join([c for c in str(_tx).upper() if c.isalnum()])
                    if cf >= conf_th and (3 <= len(s) <= 10) and any(ch.isalpha() for ch in s) and any(ch.isdigit() for ch in s):
                        return True
                return False
            # Escalate blur only inside mask
            k_base = max(31, int(min(roi.shape[0], roi.shape[1]) * 0.50))
            if k_base % 2 == 0: k_base += 1
            for i in range(passes):
                if not masked_ocr_readable(roi):
                    return
                k = min(231, k_base + i * 20)
                if k % 2 == 0: k += 1
                stronger = cv2.GaussianBlur(roi, (k, k), 0)
                # Optional pixelation overlay
                try:
                    pw = max(8, roi.shape[1] // max(8, 10 - i))
                    ph = max(6, roi.shape[0] // max(8, 10 - i))
                    tmp_small = cv2.resize(stronger, (pw, ph), interpolation=cv2.INTER_AREA)
                    stronger = cv2.resize(tmp_small, (roi.shape[1], roi.shape[0]), interpolation=cv2.INTER_NEAREST)
                except Exception:
                    pass
                try:
                    stronger = self._apply_plate_obfuscation(roi, stronger)
                except Exception:
                    pass
                m3 = cv2.merge([mask * 255, mask * 255, mask * 255])
                roi = np.where(m3 == 255, stronger, roi)
                processed_image[ya:yb, xa:xb] = roi
            # Final fallback: solid block inside mask
            if self._env_flag('PLATE_VERIFY_SOLID', True) and masked_ocr_readable(roi):
                try:
                    med = np.median(roi.reshape(-1, roi.shape[2]), axis=0).astype(np.uint8)
                    solid = np.full_like(roi, med)
                except Exception:
                    solid = np.zeros_like(roi)
                m3 = cv2.merge([mask * 255, mask * 255, mask * 255])
                roi = np.where(m3 == 255, solid, roi)
                processed_image[ya:yb, xa:xb] = roi
        except Exception:
            return

    def _refine_plate_quad(self, roi) -> Optional[object]:
        """
        Try to locate the physical plate border inside a candidate ROI using edge/contour analysis
        and return a 4x2 float32 array of corner points (in ROI coordinates) representing a
        rotated rectangle tightly covering the plate. Returns None if not found.
        """
        try:
            import cv2
            import numpy as np
            h, w = roi.shape[:2]
            if h < 15 or w < 40:
                return None
            gray = cv2.cvtColor(roi, cv2.COLOR_BGR2GRAY)
            # Enhance contrast, suppress noise
            clahe = cv2.createSSRGBlike(256) if hasattr(cv2, 'createSSRGBlike') else None
            if hasattr(cv2, 'createCLAHE'):
                clahe = cv2.createCLAHE(clipLimit=2.0, tileSize=(8, 8))
            if clahe is not None:
                gray = clahe.apply(gray)
            blur = cv2.GaussianBlur(gray, (5, 5), 0)
            # Edge detection
            edges = cv2.Canny(blur, 50, 150)
            kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (5, 3))
            edges = cv2.morphologyEx(edges, cv2.MORPH_CLOSE, kernel, iterations=1)
            contours, _ = cv2.findContours(edges, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
            if not contours:
                return None
            best = None
            best_score = 0.0
            area_img = float(h * w)
            for cnt in contours:
                if len(cnt) < 4:
                    continue
                rect = cv2.minAreaRect(cnt)
                (cx, cy), (rw, rh), ang = rect
                if rw < 1 or rh < 1:
                    continue
                wlen, hlen = (rw, rh) if rw >= rh else (rh, rw)
                ar = (wlen / max(1e-3, hlen))
                # plate-like aspect ratio and reasonable area within ROI
                area_rect = rw * rh
                fill_ratio = area_rect / max(1.0, area_img)
                # Accept roughly 1.6–7.5 aspect and sufficient area coverage
                if 1.5 <= ar <= 7.5 and 0.05 <= fill_ratio <= 0.9:
                    # prefer larger area and aspect closer to mid-range (~3)
                    score = min(fill_ratio, 0.5) * 0.7 + (1.0 - abs(ar - 3.0) / 3.0) * 0.3
                    if score > best_score:
                        best = rect
                        best_score = score
            if best is None:
                return None
            box = cv2.boxPoints(best).astype(np.float32)
            # Slightly expand the rectangle to cover borders (3–6% of size)
            (cx, cy), (rw, rh), ang = best
            scale = 1.06
            M = cv2.getRotationMatrix2D((cx, cy), 0, 1.0)  # identity
            # Expand by scaling about center
            box_centered = box - np.array([[cx, cy]])
            box_scaled = box_centered * scale + np.array([[cx, cy]])
            # Clamp to ROI bounds
            box_scaled[:, 0] = np.clip(box_scaled[:, 0], 0, w - 1)
            box_scaled[:, 1] = np.clip(box_scaled[:, 1], 0, h - 1)
            return box_scaled
        except Exception:
            return None

    def _build_plate_surface_mask(self, roi) -> Optional["np.ndarray"]:
        """
        Generate a binary mask for the plate surface inside ROI using:
        - grayscale + CLAHE
        - adaptive thresholding (binary and inverted)
        - morphology to close gaps between glyphs and fill the plate area
        - largest plausible contour → minAreaRect polygon → slight dilation
        Returns mask (uint8, 0/1) in ROI size, or None if it fails.
        """
        try:
            import cv2
            import numpy as np
            h, w = roi.shape[:2]
            if h < 12 or w < 30:
                return None
            gray = cv2.cvtColor(roi, cv2.COLOR_BGR2GRAY)
            # Contrast enhance to fight glare/reflections
            clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
            gray = clahe.apply(gray)
            blur = cv2.GaussianBlur(gray, (5, 5), 0)
            # Two candidates: bright-plate and dark-plate scenarios
            th1 = cv2.adaptiveThreshold(blur, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
                                        cv2.THRESH_BINARY, 31, 5)
            th2 = cv2.adaptiveThreshold(blur, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
                                        cv2.THRESH_BINARY_INV, 31, 5)
            def refine(bin_img):
                k_close = cv2.getStructuringElement(cv2.MORPH_RECT, (7, 3))
                k_open  = cv2.getStructuringElement(cv2.MORPH_RECT, (3, 3))
                m = cv2.morphologyEx(bin_img, cv2.MORPH_CLOSE, k_close, iterations=2)
                m = cv2.morphologyEx(m, cv2.MORPH_OPEN,  k_open,  iterations=1)
                return m
            th1 = refine(th1)
            th2 = refine(th2)
            # Choose the candidate whose filled area is plausible (5%..80% of ROI)
            a1 = float(cv2.countNonZero(th1)) / float(h * w)
            a2 = float(cv2.countNonZero(th2)) / float(h * w)
            cand = th1 if (0.05 <= a1 <= 0.80 and (a1 >= a2 or not (0.05 <= a2 <= 0.80))) else th2
            if not (0.02 <= float(cv2.countNonZero(cand)) / float(h * w) <= 0.90):
                return None
            # Find largest contour and use its minAreaRect polygon as mask
            contours, _ = cv2.findContours(cand, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
            if not contours:
                return None
            best = max(contours, key=lambda c: cv2.contourArea(c))
            if cv2.contourArea(best) < (h * w * 0.01):
                return None
            rect = cv2.minAreaRect(best)
            box = cv2.boxPoints(rect).astype(np.int32)
            mask = np.zeros((h, w), dtype=np.uint8)
            cv2.fillPoly(mask, [box], 1)
            # Tiny dilation to fully cover borders/corners (2–3%)
            try:
                dw = max(1, int(w * 0.03)) | 1
                dh = max(1, int(h * 0.03)) | 1
                ker = cv2.getStructuringElement(cv2.MORPH_RECT, (dw, dh))
                mask = cv2.dilate(mask, ker, iterations=1)
            except Exception:
                pass
            return mask
        except Exception:
            return None

    def _homography_plate_mask(self, roi) -> Optional["np.ndarray"]:
        """
        Build a mask by rectifying a skewed/rotated plate to a canonical
        rectangle with perspective transform, thresholding there, then
        warping the mask back. This improves coverage on angled plates.
        """
        try:
            import cv2
            import numpy as np
            h, w = roi.shape[:2]
            if h < 12 or w < 30:
                return None
            gray = cv2.cvtColor(roi, cv2.COLOR_BGR2GRAY)
            gray = cv2.GaussianBlur(gray, (3, 3), 0)
            edges = cv2.Canny(gray, 50, 150)
            contours, _ = cv2.findContours(edges, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
            if not contours:
                return None
            cnt = max(contours, key=cv2.contourArea)
            if cv2.contourArea(cnt) < (h * w * 0.005):
                return None
            rect = cv2.minAreaRect(cnt)
            box = cv2.boxPoints(rect).astype(np.float32)
            s = box.sum(axis=1)
            diff = np.diff(box, axis=1).ravel()
            tl = box[np.argmin(s)]; br = box[np.argmax(s)]
            tr = box[np.argmin(diff)]; bl = box[np.argmax(diff)]
            src = np.array([tl, tr, br, bl], dtype=np.float32)
            Wt = int(max(60, np.linalg.norm(tr - tl)))
            Ht = int(max(20, Wt // 3))
            dst = np.array([[0, 0], [Wt - 1, 0], [Wt - 1, Ht - 1], [0, Ht - 1]], dtype=np.float32)
            M = cv2.getPerspectiveTransform(src, dst)
            Mi = cv2.getPerspectiveTransform(dst, src)
            rectified = cv2.warpPerspective(roi, M, (Wt, Ht), flags=cv2.INTER_LINEAR)
            g = cv2.cvtColor(rectified, cv2.COLOR_BGR2GRAY)
            clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
            g = clahe.apply(g)
            th = cv2.adaptiveThreshold(g, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY, 31, 5)
            k = cv2.getStructuringElement(cv2.MORPH_RECT, (7, 3))
            th = cv2.morphologyEx(th, cv2.MORPH_CLOSE, k, iterations=2)
            rect_mask = (th > 0).astype(np.uint8) * 255
            back = cv2.warpPerspective(rect_mask, Mi, (w, h), flags=cv2.INTER_NEAREST)
            back = (back > 0).astype(np.uint8)
            # tiny 2–3% dilation to seal edges
            dw = max(1, int(w * 0.03)) | 1
            dh = max(1, int(h * 0.03)) | 1
            ker = cv2.getStructuringElement(cv2.MORPH_RECT, (dw, dh))
            back = cv2.dilate(back, ker, iterations=1)
            return back
        except Exception:
            return None

    def _shrink_mask_polygon(self, mask01: "np.ndarray", scale_xy: float = 0.96) -> "np.ndarray":
        """
        Shrink a mask by fitting minAreaRect and scaling polygon around its center.
        Keeps mask tight to avoid over-blurring. scale_xy in (0,1].
        """
        try:
            import cv2
            import numpy as np
            h, w = mask01.shape[:2]
            if h < 2 or w < 2:
                return mask01
            cnts, _ = cv2.findContours((mask01 > 0).astype(np.uint8), cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
            if not cnts:
                return mask01
            cnt = max(cnts, key=cv2.contourArea)
            if cv2.contourArea(cnt) <= 0:
                return mask01
            rect = cv2.minAreaRect(cnt)
            box = cv2.boxPoints(rect).astype(np.float32)
            cx = box[:, 0].mean(); cy = box[:, 1].mean()
            centered = box - np.array([cx, cy], dtype=np.float32)
            scaled = centered * float(scale_xy) + np.array([cx, cy], dtype=np.float32)
            scaled[:, 0] = np.clip(scaled[:, 0], 0, w - 1)
            scaled[:, 1] = np.clip(scaled[:, 1], 0, h - 1)
            out = np.zeros((h, w), dtype=np.uint8)
            cv2.fillPoly(out, [scaled.astype(np.int32)], 1)
            return out
        except Exception:
            return mask01

    def _edge_rect_mask(self, roi) -> Optional["np.ndarray"]:
        """
        Edge-driven rectangle mask fallback: find largest contour and draw its minAreaRect.
        Adds a tiny 2–3% edge dilation. Returns uint8 0/1 mask or None.
        """
        try:
            import cv2
            import numpy as np
            h, w = roi.shape[:2]
            if h < 12 or w < 30:
                return None
            gray = cv2.cvtColor(roi, cv2.COLOR_BGR2GRAY)
            gray = cv2.GaussianBlur(gray, (3, 3), 0)
            edges = cv2.Canny(gray, 60, 180)
            cnts, _ = cv2.findContours(edges, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
            if not cnts:
                return None
            cnt = max(cnts, key=cv2.contourArea)
            if cv2.contourArea(cnt) < (h * w * 0.01):
                return None
            rect = cv2.minAreaRect(cnt)
            box = cv2.boxPoints(rect).astype(np.int32)
            m = np.zeros((h, w), dtype=np.uint8)
            cv2.fillPoly(m, [box], 1)
            dw = max(1, int(w * 0.03)) | 1
            dh = max(1, int(h * 0.03)) | 1
            ker = cv2.getStructuringElement(cv2.MORPH_RECT, (dw, dh))
            m = cv2.dilate(m, ker, iterations=1)
            return m
        except Exception:
            return None

    def _predict_seg_multiscale(self, image, base_conf: float, iou: float = 0.6):
        """
        Run the segmentation model at multiple input scales and return masks
        mapped back to the original image size.
        Returns list of (mask_HxW_uint8, (x1,y1,x2,y2), conf).
        """
        try:
            import cv2
            import numpy as np
            H, W = image.shape[:2]
            passes = [(image, 1280, 1.0)]
            min_dim = min(H, W)
            if min_dim < 900:
                up15 = cv2.resize(image, None, fx=1.5, fy=1.5, interpolation=cv2.INTER_CUBIC)
                passes.append((up15, 1280, 1.5))
            if min_dim < 600:
                up20 = cv2.resize(image, None, fx=2.0, fy=2.0, interpolation=cv2.INTER_CUBIC)
                passes.append((up20, 1536, 2.0))
            out = []
            for im, imgsz, scale in passes:
                try:
                    res = self.license_plate_seg_model.predict(im, conf=base_conf, iou=iou, imgsz=imgsz, verbose=False)
                    if not res:
                        continue
                    r0 = res[0]
                    boxes = getattr(r0, 'boxes', None)
                    masks = getattr(r0, 'masks', None)
                    if masks is None or not hasattr(masks, 'data') or boxes is None:
                        continue
                    mdata = masks.data
                    xyxy = boxes.xyxy
                    confs = boxes.conf if hasattr(boxes, 'conf') else None
                    mdata = mdata.cpu().numpy() if hasattr(mdata, 'cpu') else mdata
                    xyxy = xyxy.cpu().numpy() if hasattr(xyxy, 'cpu') else xyxy
                    confs = confs.cpu().numpy() if (confs is not None and hasattr(confs, 'cpu')) else confs
                    for i in range(min(len(mdata), len(xyxy))):
                        c = float(confs[i]) if confs is not None else base_conf
                        x1, y1, x2, y2 = [int(v / scale) for v in xyxy[i]]
                        x1 = max(0, x1); y1 = max(0, y1); x2 = min(W, x2); y2 = min(H, y2)
                        if x2 <= x1 or y2 <= y1:
                            continue
                        m = mdata[i].astype('uint8')
                        try:
                            # resize mask to original HxW
                            if m.shape[0] != int(H*scale) or m.shape[1] != int(W*scale):
                                m = cv2.resize(m, (im.shape[1], im.shape[0]), interpolation=cv2.INTER_NEAREST)
                            if scale != 1.0:
                                m = cv2.resize(m, (W, H), interpolation=cv2.INTER_NEAREST)
                            else:
                                m = cv2.resize(m, (W, H), interpolation=cv2.INTER_NEAREST)
                        except Exception:
                            m = cv2.resize(m, (W, H), interpolation=cv2.INTER_NEAREST)
                        out.append((m, (x1, y1, x2, y2), c))
                except Exception:
                    continue
            return out
        except Exception:
            return []
    
    @staticmethod
    def _env_flag(name: str, default: bool=False) -> bool:
        """Return True if env var is set to truthy value."""
        import os as _os
        v = str(_os.getenv(name, str(default))).strip().lower()
        return v in ('1','true','yes','y','on')
    
    def _apply_plate_obfuscation(self, original_roi, current_roi):
        """
        Apply an extra obfuscation pass controlled by environment variables:
          - PLATE_BLUR_STYLE: 'gauss', 'pixelate', 'gauss_pixelate' (default), or 'box'
          - PLATE_BLUR_STRENGTH: float multiplier >= 1.0 (default 1.0)
        This runs AFTER the baseline blur to let operators quickly harden obfuscation
        without changing code or retraining models.
        """
        try:
            import cv2
            import numpy as np
            import os as _os
            style = str(_os.getenv('PLATE_BLUR_STYLE', 'gauss_pixelate')).lower().strip()
            try:
                strength = float(_os.getenv('PLATE_BLUR_STRENGTH', '3.0'))
            except Exception:
                strength = 3.0
            strength = max(1.0, min(4.0, strength))  # clamp for safety
            roi = current_roi if current_roi is not None else original_roi
            if roi is None or roi.size == 0:
                return current_roi
            h, w = roi.shape[:2]
            out = roi
            # Solid box option (max privacy)
            if style in ('box', 'solid', 'black'):
                # Use median color to reduce harshness; fallback to black
                try:
                    med = np.median(original_roi.reshape(-1, original_roi.shape[2]), axis=0).astype(np.uint8)
                    out = np.full_like(original_roi, med)
                except Exception:
                    out = np.zeros_like(original_roi)
                return out
            # Gaussian component
            if style in ('gauss', 'gaussian', 'gauss_pixelate', 'auto'):
                kg = int(max(5, min(251, int(min(w, h) * 0.40 * strength))))
                if kg % 2 == 0:
                    kg += 1
                out = cv2.GaussianBlur(out, (kg, kg), 0)
            # Pixelation component
            if style in ('pixelate', 'gauss_pixelate', 'auto'):
                # Higher strength → coarser pixels
                denom = max(4.0, 10.0 / strength)
                pw = max(6, int(w / denom))
                ph = max(6, int(h / denom))
                small = cv2.resize(out, (pw, ph), interpolation=cv2.INTER_AREA)
                out = cv2.resize(small, (w, h), interpolation=cv2.INTER_NEAREST)
            return out
        except Exception:
            return current_roi
    
    def _build_output_suffix(self) -> str:
        """
        Build a result filename suffix based on environment overrides so different
        runs don't look identical on disk (e.g., _blurred_box_s35).
        - PLATE_OUTPUT_TAG: if set, appended after _blurred (e.g., _blurred_review)
        - Otherwise use PLATE_BLUR_STYLE and PLATE_BLUR_STRENGTH to form suffix.
        """
        try:
            import os as _os
            tag = str(_os.getenv('PLATE_OUTPUT_TAG', '') or '').strip()
            style = str(_os.getenv('PLATE_BLUR_STYLE', '') or '').strip().lower()
            strength = str(_os.getenv('PLATE_BLUR_STRENGTH', '') or '').strip()
            suffix = "_blurred"
            if tag:
                return f"{suffix}_{tag}"
            parts = [suffix]
            if style:
                parts.append(f"_{style}")
            if strength:
                try:
                    s = float(strength)
                    parts.append(f"_s{int(round(s*10))}")
                except Exception:
                    pass
            return "".join(parts)
        except Exception:
            return "_blurred"
    
    def _build_output_path(self, image_path: str) -> str:
        """
        Build the final absolute output path. If PLATE_OUTPUT_DIR is set,
        write all results into that folder; otherwise, write next to source.
        """
        try:
            import os as _os
            suffix = self._build_output_suffix()
            out_dir = str(_os.getenv('PLATE_OUTPUT_DIR', '') or '').strip()
            base_name, ext = _os.path.splitext(_os.path.basename(image_path))
            if out_dir:
                try:
                    _os.makedirs(out_dir, exist_ok=True)
                except Exception:
                    pass
                return _os.path.join(out_dir, f"{base_name}{suffix}{ext or '.jpg'}")
            root, ext2 = _os.path.splitext(image_path)
            return f"{root}{suffix}{ext2 or '.jpg'}"
        except Exception:
            # Fallback to original directory
            try:
                import os as _os
                root, ext = _os.path.splitext(image_path)
                return f"{root}{self._build_output_suffix()}{ext or '.jpg'}"
            except Exception:
                return image_path
    
    def _initialize_models(self):
        """Initialize AI models for car analysis"""
        try:
            import cv2
            from ultralytics import YOLO
            import os as _os
            # Reduce OpenCV thread contention on Windows for stability
            try:
                cv2.setNumThreads(1)
            except Exception:
                pass
            
            # Initialize YOLO for license plate detection (prefer local specialized high‑recall model)
            self.license_plate_model = None
            self.license_plate_seg_model = None
            self.model_is_generic = False
            try:
                _root = _os.path.abspath(_os.path.join(_os.path.dirname(__file__), '..'))
                # Prefer local license-plate models to avoid network pulls
                _local_lp_candidates = [
                    _os.path.join(_root, 'kk', 'weights', 'yolov8l-iraqi-license-plate.pt'),
                    _os.path.join(_root, 'kk', 'weights', 'yolov8l-license-plate.pt'),
                    _os.path.join(_root, 'weights', 'yolov8l-license-plate.pt'),
                    _os.path.join(_root, 'yolov8l-license-plate.pt'),
                    _os.path.join(_root, 'kk', 'weights', 'yolov8m-license-plate.pt'),
                    _os.path.join(_root, 'weights', 'yolov8m-license-plate.pt'),
                    _os.path.join(_root, 'yolov8m-license-plate.pt'),
                    _os.path.join(_root, 'kk', 'weights', 'yolov8n-license-plate.pt'),
                    _os.path.join(_root, 'weights', 'yolov8n-license-plate.pt'),
                    _os.path.join(_root, 'yolov8n-license-plate.pt'),
                ]
                for _p in _local_lp_candidates:
                    if _os.path.exists(_p):
                        self.license_plate_model = YOLO(_p)
                        self.model_is_generic = False
                        print(f"AI Service: Loaded local license-plate model: {_p}")
                        break

                # Try to load a segmentation model for license plates (preferred when available)
                _local_lp_seg_candidates = [
                    _os.path.join(_root, 'kk', 'weights', 'yolov8n-license-plate-seg.pt'),
                    _os.path.join(_root, 'weights', 'yolov8n-license-plate-seg.pt'),
                    _os.path.join(_root, 'yolov8n-license-plate-seg.pt'),
                ]
                for _p in _local_lp_seg_candidates:
                    if self.license_plate_seg_model is None and _os.path.exists(_p):
                        try:
                            self.license_plate_seg_model = YOLO(_p)
                            print(f"AI Service: Loaded local license-plate SEG model: {_p}")
                            break
                        except Exception:
                            pass

                # If no local specialized model, try remote specialized repos (prefer m/l over n)
                if self.license_plate_model is None:
                    try:
                        self.license_plate_model = YOLO('keremberke/yolov8m-license-plate')
                    except Exception:
                        try:
                            self.license_plate_model = YOLO('keremberke/yolov8l-license-plate')
                        except Exception:
                            try:
                                self.license_plate_model = YOLO('keremberke/yolov8n-license-plate')
                        except Exception:
                            pass

                if self.license_plate_seg_model is None:
                    try:
                        self.license_plate_seg_model = YOLO('keremberke/yolov8n-license-plate-seg')
                    except Exception:
                        try:
                            self.license_plate_seg_model = YOLO('keremberke/yolov8m-license-plate-seg')
                        except Exception:
                            pass

                # Final fallback: local or remote generic model
                if self.license_plate_model is None:
                    try:
                        _local_generic = _os.path.join(_root, 'yolov8n.pt')
                        if _os.path.exists(_local_generic):
                            self.license_plate_model = YOLO(_local_generic)
                            self.model_is_generic = True
                        else:
                            self.license_plate_model = YOLO('yolov8n.pt')
                            self.model_is_generic = True
                    except Exception:
                        self.license_plate_model = None
                        self.model_is_generic = False
            except Exception as _yolo_e:
                print(f"AI Service: YOLO specialized/generic init error: {_yolo_e}")
                # leave license_plate_model as-is (None) so OCR/fallbacks can proceed
            
            # OCR is intentionally disabled for stability (IQ Cars–style).
            # Do NOT initialize EasyOCR at startup. This avoids non-determinism and heavy deps.
                self.ocr_reader = None
            # print intentionally omitted: no "EasyOCR Reader initialized" should appear
            
            self.initialized = True
            logger.info("AI models initialized successfully")
            print(f"AI Service: YOLO model loaded -> generic={self.model_is_generic}, has_model={self.license_plate_model is not None}")
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
    
    def _blur_license_plates(self, image_path: str, strict: bool=False, mode: str='auto') -> str:
        """
        Detect and blur license plates in the image.
        
        IQ Cars–style lock-down:
        - OCR is intentionally disabled for stability and predictability on Iraqi plates.
        - YOLO-only detection is used, treating plates as visual objects (not text).
        - Deterministic rectangular blur with padding/dilation and size-scaled strength.
        """
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

            # Load image and normalize EXIF orientation BEFORE detection
            try:
                from PIL import ExifTags
                pil_img = Image.open(image_path)
                exif = getattr(pil_img, "_getexif", lambda: None)() or {}
                orientation_key = None
                for k, v in ExifTags.TAGS.items():
                    if v == 'Orientation':
                        orientation_key = k
                        break
                if orientation_key is not None and orientation_key in exif:
                    ori = exif.get(orientation_key, 1)
                    # Rotate to upright; PIL.rotate is counter-clockwise
                    if ori == 3:
                        pil_img = pil_img.rotate(180, expand=True)
                    elif ori == 6:
                        pil_img = pil_img.rotate(270, expand=True)  # 90 CW
                    elif ori == 8:
                        pil_img = pil_img.rotate(90, expand=True)   # 90 CCW
                # Ensure RGB then convert to OpenCV BGR
                pil_img = pil_img.convert('RGB')
                image = cv2.cvtColor(np.array(pil_img), cv2.COLOR_RGB2BGR)
            except Exception:
                # Fallback to OpenCV if EXIF handling fails
                image = cv2.imread(image_path)
                if image is None:
                    logger.error(f"Could not load image: {image_path}")
                    return image_path
            
            # Working copy
            processed_image = image.copy()
            H, W = image.shape[:2]
            image_area = H * W
            
            # IQ Cars–style deterministic YOLO-only pipeline (no OCR, no polygons)
            try:
                blurred_any = False
                fallback_used = False
                num_applied = 0
                det_boxes = []
                if self.license_plate_model is not None:
                    # Multi-scale YOLO-only detection for high recall (map boxes back to original coords)
                    scales = [1.0, 1.25, 1.5]
                    for s in scales:
                        import cv2 as _cv2
                        if s == 1.0:
                            img_s = image
                        else:
                            img_s = _cv2.resize(image, None, fx=s, fy=s, interpolation=_cv2.INTER_LINEAR)
                        res = self.license_plate_model.predict(img_s, conf=0.30, iou=0.5, imgsz=1280, verbose=False)
                        num = 0
                        if res:
                            r0 = res[0]
                            boxes = getattr(r0, 'boxes', None)
                            if boxes is not None and hasattr(boxes, 'xyxy'):
                                try:
                                    xyxy = boxes.xyxy.cpu().numpy() if hasattr(boxes.xyxy, 'cpu') else boxes.xyxy
                                    confs = boxes.conf.cpu().numpy() if hasattr(boxes, 'conf') and hasattr(boxes, 'cpu') else None
                                except Exception:
                                    xyxy, confs = None, None
                                if xyxy is not None:
                                    for i, b in enumerate(xyxy):
                                        c = float(confs[i]) if confs is not None and i < len(confs) else 1.0
                                        x1s, y1s, x2s, y2s = [float(v) for v in b]
                                        # Map back to original coordinates
                                        x1 = int(x1s / s); x2 = int(x2s / s)
                                        y1 = int(y1s / s); y2 = int(y2s / s)
                                        # Clamp
                                        x1 = max(0, min(W - 1, x1)); x2 = max(0, min(W, x2))
                                        y1 = max(0, min(H - 1, y1)); y2 = max(0, min(H, y2))
                                        if x2 <= x1 or y2 <= y1:
                                            continue
                                        det_boxes.append((c, x1, y1, x2, y2))
                                        num += 1
                        print(f"AI Service: YOLO detections @ scale={s:.2f}: {num}")
                # Filtering per spec:
                # - Keep boxes whose center lies in lower 50–100% of the image
                # - Keep only plate-like aspect ratios 1.5–7.0
                filtered = []
                for c, x1, y1, x2, y2 in det_boxes:
                    w_box = max(1, x2 - x1)
                    h_box = max(1, y2 - y1)
                    ar = w_box / float(h_box)
                    cy = (y1 + y2) * 0.5
                    if cy < (0.50 * H):  # ignore outside lower 50%
                        continue
                    if not (1.5 <= ar <= 7.0):  # broader aspect bound for Iraqi plates
                        continue
                    filtered.append((c, x1, y1, x2, y2))
                # Sort by confidence, keep top 2
                if filtered:
                    filtered.sort(key=lambda t: t[0], reverse=True)
                    filtered = filtered[:2]
                    for _, x1, y1, x2, y2 in filtered:
                        bw = max(1, x2 - x1)
                        bh = max(1, y2 - y1)
                        xa, ya, xb, yb = x1, y1, x2, y2
                        import cv2 as _cv2
                        roi = processed_image[ya:yb, xa:xb]
                        if roi.size == 0:
                            continue
                        # Find plate polygon via contours inside ROI
                        roi_gray = _cv2.cvtColor(roi, _cv2.COLOR_BGR2GRAY)
                        roi_gray = _cv2.bilateralFilter(roi_gray, 7, 55, 55)
                        edges = _cv2.Canny(roi_gray, 50, 150)
                        close_ker = _cv2.getStructuringElement(_cv2.MORPH_RECT, (5, 3))
                        edges = _cv2.morphologyEx(edges, _cv2.MORPH_CLOSE, close_ker, iterations=1)
                        contours, _ = _cv2.findContours(edges, _cv2.RETR_EXTERNAL, _cv2.CHAIN_APPROX_SIMPLE)
                        best_poly = None
                        best_score = -1.0
                        roi_h, roi_w = roi.shape[:2]
                        roi_area = max(1, roi_h * roi_w)
                        for cnt in contours:
                            if len(cnt) < 4:
                                continue
                            x, y, w, h = _cv2.boundingRect(cnt)
                            if w <= 0 or h <= 0:
                                continue
                            ar_local = w / float(max(1, h))
                            area = w * h
                            if area < 0.005 * roi_area:
                                continue
                            approx = _cv2.approxPolyDP(cnt, 0.02 * _cv2.arcLength(cnt, True), True)
                            poly = approx
                            # Prefer 4-point polygons; otherwise use convex hull
                            if len(approx) != 4:
                                poly = _cv2.convexHull(cnt)
                            # Score: plate-like AR, area coverage, rectangularity if 4-pt
                            rect_ratio = float(_cv2.contourArea(cnt)) / float(max(1, area))
                            size_score = min((area / roi_area) / 0.25, 1.0)  # prefer moderate coverage
                            ar_score = 1.0 - min(abs(ar_local - 3.0) / 3.0, 1.0)  # favor ~3:1
                            score = 0.4 * ar_score + 0.3 * size_score + 0.3 * rect_ratio
                            if score > best_score:
                                best_score = score
                                best_poly = poly
                        if best_poly is None or len(best_poly) < 3:
                            # If no polygon found, skip this detection (fallback will handle privacy)
                            continue
                        # Convert polygon points to image coordinates and apply 5–10% padding (scale from centroid)
                        pts = best_poly.reshape(-1, 2).astype(np.float32)
                        # Clamp to ROI bounds
                        pts[:, 0] = np.clip(pts[:, 0], 0, roi_w - 1)
                        pts[:, 1] = np.clip(pts[:, 1], 0, roi_h - 1)
                        # Expand polygon outward
                        pad_ratio = 0.07  # ~7% outward padding
                        cx = float(np.mean(pts[:, 0])); cy = float(np.mean(pts[:, 1]))
                        pts_pad = np.empty_like(pts)
                        pts_pad[:, 0] = cx + (pts[:, 0] - cx) * (1.0 + pad_ratio)
                        pts_pad[:, 1] = cy + (pts[:, 1] - cy) * (1.0 + pad_ratio)
                        pts_pad[:, 0] = np.clip(pts_pad[:, 0], 0, roi_w - 1)
                        pts_pad[:, 1] = np.clip(pts_pad[:, 1], 0, roi_h - 1)
                        # Build local mask from padded polygon
                        mask_local = np.zeros((roi_h, roi_w), dtype=np.uint8)
                        _cv2.fillPoly(mask_local, [pts_pad.astype(np.int32)], 255)
                        # Size-aware Gaussian kernel
                        poly_w = float(np.max(pts_pad[:, 0]) - np.min(pts_pad[:, 0]) + 1.0)
                        poly_h = float(np.max(pts_pad[:, 1]) - np.min(pts_pad[:, 1]) + 1.0)
                        k = int(max(15, min(211, int(min(poly_w, poly_h) * 0.60))))
                        if k % 2 == 0:
                            k += 1
                        roi_blurred = _cv2.GaussianBlur(roi, (k, k), 0)
                        mask3 = _cv2.merge([mask_local, mask_local, mask_local])
                        composited = np.where(mask3 == 255, roi_blurred, roi)
                        processed_image[ya:yb, xa:xb] = composited
                        # Log polygon (absolute coordinates)
                        abs_poly = [(int(xa + p[0]), int(ya + p[1])) for p in pts_pad]
                        print(f"AI Service: Blur applied -> box=({x1},{y1},{x2},{y2}) poly_pts={abs_poly} k={k}")
                        blurred_any = True
                        num_applied += 1
                # Privacy fallback: conservative bottom-center region if no plate found
                if not blurred_any:
                    import cv2 as _cv2
                    fw = int(W * 0.50)     # 50% width
                    fh = int(H * 0.22)     # 22% height
                    cx = W // 2
                    # Place region near bottom center
                    xa = max(0, cx - fw // 2)
                    xb = min(W, cx + fw // 2)
                    yb = H
                    ya = max(0, yb - fh)
                    if xb > xa and yb > ya:
                        k = int(max(13, min(197, int(min(xb - xa, yb - ya) * 0.55))))
                        if k % 2 == 0:
                            k += 1
                        roi = processed_image[ya:yb, xa:xb]
                        processed_image[ya:yb, xa:xb] = _cv2.GaussianBlur(roi, (k, k), 0)
                        blurred_any = True
                        print("AI Service: Fallback blur applied (bottom-center).")
                        fallback_used = True
                # Write output if any blur applied; return early to avoid OCR paths
                if blurred_any:
                    # Update per-image and cumulative stats
                    self._last_blur_stats = {
                        'image': image_path,
                        'num_blurs': int(num_applied),
                        'fallback': bool(fallback_used),
                    }
                    try:
                        self._total_blur_stats['images'] += 1
                        self._total_blur_stats['plates'] += int(num_applied)
                        if fallback_used:
                            self._total_blur_stats['fallbacks'] += 1
                    except Exception:
                        pass
                    out_path = self._build_output_path(image_path)
                    root, ext = os.path.splitext(out_path)
                    if not root.lower().endswith('_blurred'):
                        out_path = f"{root}_blurred{ext or '.jpg'}"
                    try:
                        os.makedirs(os.path.dirname(out_path), exist_ok=True)
                    except Exception:
                        pass
                    cv2.imwrite(out_path, processed_image)
                    return out_path
            except Exception as _stable_e:
                # Safety: never fall through to OCR-based legacy paths.
                # Apply bottom-center fallback and return to maintain privacy guarantees.
                print(f"AI Service: Stable YOLO-only pipeline error: {_stable_e}")
                try:
                    import cv2 as _cv2
                    fw = int(W * 0.50)
                    fh = int(H * 0.22)
                    cx = W // 2
                    xa = max(0, cx - fw // 2)
                    xb = min(W, cx + fw // 2)
                    yb = H
                    ya = max(0, yb - fh)
                    if xb > xa and yb > ya:
                        k = int(max(13, min(197, int(min(xb - xa, yb - ya) * 0.55))))
                        if k % 2 == 0:
                            k += 1
                        roi = processed_image[ya:yb, xa:xb]
                        processed_image[ya:yb, xa:xb] = _cv2.GaussianBlur(roi, (k, k), 0)
                        # Update stats for error-fallback case
                        self._last_blur_stats = {
                            'image': image_path,
                            'num_blurs': 0,
                            'fallback': True,
                        }
                        try:
                            self._total_blur_stats['images'] += 1
                            self._total_blur_stats['fallbacks'] += 1
                        except Exception:
                            pass
                        out_path = self._build_output_path(image_path)
                        root, ext = os.path.splitext(out_path)
                        if not root.lower().endswith('_blurred'):
                            out_path = f"{root}_blurred{ext or '.jpg'}"
                        try:
                            os.makedirs(os.path.dirname(out_path), exist_ok=True)
                        except Exception:
                            pass
                        cv2.imwrite(out_path, processed_image)
                        return out_path
                except Exception:
                    pass
                # As a last resort, return original path but never continue to OCR paths.
                return image_path
            
            # Safety assertion: this function must return from the YOLO-only path.
            # No downstream OCR-based blurring is allowed in lock-down mode.
            assert False, "OCR path disabled; _blur_license_plates must return earlier via YOLO-only pipeline"

            # Ensure a LICENSE-PLATE-ONLY detector (replace generic if needed)
            try:
                if self.license_plate_model is None:
                    pass
                elif getattr(self, 'model_is_generic', False):
                    from ultralytics import YOLO as _Y
                    try:
                        self.license_plate_model = _Y('keremberke/yolov8n-license-plate')
                        self.model_is_generic = False
                    except Exception:
                        try:
                            self.license_plate_model = _Y('keremberke/yolov8m-license-plate')
                            self.model_is_generic = False
                        except Exception:
                            # keep existing model if replacement fails
                            pass
            except Exception:
                pass

            # LETTERBOX-AWARE YOLO DETECTION ON UPRIGHT IMAGE (no manual resizing)
            blurred_count = 0
            # Preferred path: segmentation model (mask-based blur)
            if self.license_plate_seg_model is not None:
                try:
                    import os as _os2
                    # Adaptive conf by image size
                    try:
                        base_conf = float(_os2.getenv('PLATE_CONF_THRESHOLD', '0.30') or 0.30)
                    except Exception:
                        base_conf = 0.30
                    min_dim = min(H, W)
                    if min_dim < 500:
                        conf_th = max(0.18, base_conf - 0.12)
                    elif min_dim < 800:
                        conf_th = max(0.22, base_conf - 0.08)
                    else:
                        conf_th = base_conf
                    # Run multi-scale segmentation and blur inside masks
                    seg_dets = self._predict_seg_multiscale(image, base_conf=conf_th, iou=0.6)
                    for idx, (mask, (x1, y1, x2, y2), c) in enumerate(seg_dets):
                        if c < conf_th:
                            continue
                        # Restrict mask to bbox and seal edges
                        mclip = np.zeros_like(mask, dtype=np.uint8)
                        mclip[y1:y2, x1:x2] = mask[y1:y2, x1:x2]
                        if np.count_nonzero(mclip) == 0:
                            continue
                        try:
                            ker_w = max(1, int((x2 - x1) * 0.03)) | 1
                            ker_h = max(1, int((y2 - y1) * 0.06)) | 1
                            ker = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (ker_w, ker_h))
                            mclip = cv2.dilate(mclip.astype(np.uint8), ker, iterations=1)
                        except Exception:
                            pass
                        # Shrink oversized masks to avoid spill
                        try:
                            cov2 = float((mclip[y1:y2, x1:x2] > 0).sum()) / max(1, (x2 - x1) * (y2 - y1))
                            if cov2 > 0.65:
                                local = self._shrink_mask_polygon(mclip[y1:y2, x1:x2], 0.96)
                                mclip[y1:y2, x1:x2] = local
                        except Exception:
                            pass
                        if np.count_nonzero(mclip) == 0:
                            continue
                        # Blur only inside mask
                        bw = max(1, x2 - x1); bh = max(1, y2 - y1)
                        k = int(max(31, min(211, int(min(bw, bh) * 0.50))))
                        if k % 2 == 0:
                            k += 1
                        blurred = cv2.GaussianBlur(processed_image, (k, k), 0)
                        mask3 = cv2.merge([mclip * 255, mclip * 255, mclip * 255])
                        processed_image = np.where(mask3 == 255, blurred, processed_image)
                        # Debug save
                        try:
                            _dbg = os.getenv('PLATE_DEBUG_DIR', '').strip()
                            if _dbg:
                                os.makedirs(_dbg, exist_ok=True)
                                base = os.path.splitext(os.path.basename(image_path))[0]
                                dbg_mask = (mclip * 255).astype('uint8')
                                cv2.imwrite(os.path.join(_dbg, f"{base}_segmask_{idx}.png"), dbg_mask)
                        except Exception:
                            pass
                        try:
                            self._post_blur_verify_mask(processed_image, x1, y1, x2, y2, mclip[y1:y2, x1:x2])
                        except Exception:
                            pass
                        blurred_count += 1
                    if blurred_count > 0:
                        out_path = self._build_output_path(image_path)
                        root, ext = os.path.splitext(out_path)
                        if not root.lower().endswith('_blurred'):
                            out_path = f"{root}_blurred{ext or '.jpg'}"
                        try:
                            os.makedirs(os.path.dirname(out_path), exist_ok=True)
                        except Exception:
                            pass
                        cv2.imwrite(out_path, processed_image)
                        return out_path
                except Exception as _e_seg:
                    print(f"AI Service: Segmentation pipeline error: {_e_seg}")

            # Fallback path: detection model with ROI-generated mask or rectangle
            if self.license_plate_model is not None:
                try:
                    import os as _os2
                    # Adaptive conf by image size
                    try:
                        base_conf = float(_os2.getenv('PLATE_CONF_THRESHOLD', '0.30') or 0.30)
                    except Exception:
                        base_conf = 0.30
                    min_dim = min(H, W)
                    if min_dim < 500:
                        conf_th = max(0.18, base_conf - 0.12)
                    elif min_dim < 800:
                        conf_th = max(0.22, base_conf - 0.08)
                    else:
                        conf_th = base_conf
                    res = self.license_plate_model.predict(image, conf=conf_th, iou=0.6, imgsz=1280, verbose=False)
                    if res:
                        r0 = res[0]
                        boxes = getattr(r0, 'boxes', None)
                        if boxes is not None and hasattr(boxes, 'xyxy'):
                            # xyxy from Ultralytics are already scaled back to the original image coordinates,
                            # accounting for the internal letterbox (no manual scaling needed).
                            try:
                                xyxy = boxes.xyxy.cpu().numpy() if hasattr(boxes.xyxy, 'cpu') else boxes.xyxy
                                confs = boxes.conf.cpu().numpy() if hasattr(boxes, 'conf') and hasattr(boxes.conf, 'cpu') else None
                            except Exception:
                                xyxy, confs = None, None
                            dets = []
                            if xyxy is not None:
                                for i, b in enumerate(xyxy):
                                    c = float(confs[i]) if confs is not None and i < len(confs) else conf_th
                                    if c < conf_th:
                                        continue
                                    x1, y1, x2, y2 = [int(v) for v in b]
                                    # Clamp to image boundaries
                                    x1 = max(0, min(W - 1, x1)); x2 = max(0, min(W, x2))
                                    y1 = max(0, min(H - 1, y1)); y2 = max(0, min(H, y2))
                                    if x2 <= x1 or y2 <= y1:
                                        continue
                                    dets.append((c, x1, y1, x2, y2))
                            if dets:
                                dets.sort(key=lambda t: t[0], reverse=True)
                                dets = dets[:2]  # max 2 plates
                                for c, x1, y1, x2, y2 in dets:
                                    # No extra padding; use YOLO box directly and build mask within it
                                    xa, ya, xb, yb = x1, y1, x2, y2
                                    if xb <= xa or yb <= ya:
                                        continue
                                    roi = processed_image[ya:yb, xa:xb]
                                    if roi.size == 0:
                                        continue
                                    # Primary: build plate-surface mask; fallback to homography mask if weak
                                    mask01 = self._build_plate_surface_mask(roi)
                                    cov = (float((mask01 > 0).sum()) / (mask01.shape[0] * mask01.shape[1])) if (mask01 is not None and mask01.size) else 0.0
                                    if mask01 is None or cov < 0.35:
                                        mask01 = self._homography_plate_mask(roi)
                                    if mask01 is not None and np.count_nonzero(mask01) > 0:
                                        import cv2 as _cv2
                                        # Guard against oversized masks: shrink if coverage > 80%
                                        try:
                                            cov2 = float((mask01 > 0).sum()) / float(mask01.shape[0] * mask01.shape[1])
                                            if cov2 > 0.65:
                                                mask01 = self._shrink_mask_polygon(mask01, scale_xy=0.96)
                                        except Exception:
                                            pass
                                        k = int(max(31, min(211, int(min(roi.shape[0], roi.shape[1]) * 0.50))))
                                        if k % 2 == 0:
                                            k += 1
                                        blurred_roi = _cv2.GaussianBlur(roi, (k, k), 0)
                                        try:
                                            blurred_roi = self._apply_plate_obfuscation(roi, blurred_roi)
                                        except Exception:
                                            pass
                                        # Keep mask-only coverage; no bbox union per spec
                                        mask255 = (mask01.astype(np.uint8) * 255)
                                        mask3 = _cv2.merge([mask255, mask255, mask255])
                                        composited = np.where(mask3 == 255, blurred_roi, roi)
                                        processed_image[ya:yb, xa:xb] = composited
                                        # Debug save
                                        try:
                                            _dbg = os.getenv('PLATE_DEBUG_DIR', '').strip()
                                            if _dbg:
                                                os.makedirs(_dbg, exist_ok=True)
                                                base = os.path.splitext(os.path.basename(image_path))[0]
                                                cv2.imwrite(os.path.join(_dbg, f"{base}_roi_mask_{x1}_{y1}.png"), mask255)
                                        except Exception:
                                            pass
                                    else:
                                        # Fallback: try edge-rect mask before rectangle blur
                                        emask = self._edge_rect_mask(roi)
                                        if emask is not None and np.count_nonzero(emask) > 0:
                                            import cv2 as _cv2
                                            k = int(max(31, min(211, int(min(roi.shape[0], roi.shape[1]) * 0.50))))
                                            if k % 2 == 0:
                                                k += 1
                                            blurred_roi = _cv2.GaussianBlur(roi, (k, k), 0)
                                            m255 = (emask.astype(np.uint8) * 255)
                                            m3 = _cv2.merge([m255, m255, m255])
                                            comp = np.where(m3 == 255, blurred_roi, roi)
                                            processed_image[ya:yb, xa:xb] = comp
                                            try:
                                                self._post_blur_verify_mask(processed_image, xa, ya, xb, yb, emask)
                                            except Exception:
                                                pass
                                        else:
                                            # Last resort: contracted rectangle mask to avoid spillover
                                            k = int(max(31, min(211, int(min(roi.shape[0], roi.shape[1]) * 0.50))))
                                            if k % 2 == 0:
                                                k += 1
                                            import cv2 as _cv2
                                            rblur = _cv2.GaussianBlur(roi, (k, k), 0)
                                            # Build a contracted central mask (keeps corners/edges safe)
                                            shy = max(2, int(roi.shape[0] * 0.075))
                                            shx = max(2, int(roi.shape[1] * 0.075))
                                            cmask = np.zeros((roi.shape[0], roi.shape[1]), dtype=np.uint8)
                                            y1c, y2c = shy, max(shy + 1, roi.shape[0] - shy)
                                            x1c, x2c = shx, max(shx + 1, roi.shape[1] - shx)
                                            cmask[y1c:y2c, x1c:x2c] = 1
                                            m3 = _cv2.merge([cmask * 255, cmask * 255, cmask * 255])
                                            comp = np.where(m3 == 255, rblur, roi)
                                            processed_image[ya:yb, xa:xb] = comp
                                            try:
                                                self._post_blur_verify_mask(processed_image, xa, ya, xb, yb, cmask)
                                            except Exception:
                                                pass
                                    try:
                                        self._post_blur_verify_mask(processed_image, xa, ya, xb, yb, mask01 if mask01 is not None and np.count_nonzero(mask01)>0 else np.ones((roi.shape[0], roi.shape[1]), dtype=np.uint8))
                                    except Exception:
                                        pass
                                    blurred_count += 1
                    if blurred_count > 0:
                        # OCR residual sweep: blur any remaining plate-like text not caught by YOLO/seg
                        try:
                            if self.ocr_reader is not None:
                                rgb_full = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
                                candidates = []
                                for _scale in [1.0, 1.5, 2.0, 3.0]:
                                    src = rgb_full if _scale == 1.0 else cv2.resize(rgb_full, None, fx=_scale, fy=_scale, interpolation=cv2.INTER_CUBIC)
                                    _res = self.ocr_reader.readtext(src) or []
                                    for (bbox, text, conf) in _res:
                                        if _scale != 1.0:
                                            bbox = [[int(pt[0] / _scale), int(pt[1] / _scale)] for pt in bbox]
                                        candidates.append((bbox, text, conf))
                                for (bbox, text, conf) in candidates:
                                    try:
                                        clean = ''.join([c for c in str(text).upper() if c.isalnum()])
                                    except Exception:
                                        clean = ""
                                    if (conf or 0) < 0.25:
                                        continue
                                    if not self._is_likely_license_plate(clean):
                                        continue
                                    xs = [int(p[0]) for p in bbox]
                                    ys = [int(p[1]) for p in bbox]
                                    x1r, x2r = max(0, min(xs)), min(W, max(xs))
                                    y1r, y2r = max(0, min(ys)), min(H, max(ys))
                                    if x2r <= x1r or y2r <= y1r:
                                        continue
                                    xa, ya, xb, yb = x1r, y1r, x2r, y2r
                                    roi = processed_image[ya:yb, xa:xb]
                                    if roi.size == 0:
                                        continue
                                    mask01 = self._build_plate_surface_mask(roi)
                                    cov = (float((mask01 > 0).sum()) / (mask01.shape[0] * mask01.shape[1])) if (mask01 is not None and mask01.size) else 0.0
                                    if mask01 is None or cov < 0.35:
                                        mask01 = self._homography_plate_mask(roi)
                                    if mask01 is None or np.count_nonzero(mask01) == 0:
                                        # Rectangle blur fallback
                                        k = int(max(31, min(211, int(min(roi.shape[0], roi.shape[1]) * 0.50))))
                                        if k % 2 == 0: k += 1
                                        processed_image[ya:yb, xa:xb] = cv2.GaussianBlur(roi, (k, k), 0)
                                    else:
                                        import cv2 as _cv2
                                        # Tiny edge seal already done by builders; keep mask-only coverage
                                        k = int(max(31, min(211, int(min(roi.shape[0], roi.shape[1]) * 0.50))))
                                        if k % 2 == 0: k += 1
                                        blurred_roi = _cv2.GaussianBlur(roi, (k, k), 0)
                                        try:
                                            blurred_roi = self._apply_plate_obfuscation(roi, blurred_roi)
                                        except Exception:
                                            pass
                                        m255 = (mask01.astype(np.uint8) * 255)
                                        m3 = _cv2.merge([m255, m255, m255])
                                        comp = np.where(m3 == 255, blurred_roi, roi)
                                        processed_image[ya:yb, xa:xb] = comp
                                    try:
                                        self._post_blur_verify_mask(processed_image, xa, ya, xb, yb, mask01 if mask01 is not None and np.count_nonzero(mask01)>0 else np.ones((roi.shape[0], roi.shape[1]), dtype=np.uint8))
                                    except Exception:
                                        pass
                        except Exception:
                            pass
                        out_path = self._build_output_path(image_path)
                        root, ext = os.path.splitext(out_path)
                        if not root.lower().endswith('_blurred'):
                            out_path = f"{root}_blurred{ext or '.jpg'}"
                        try:
                            os.makedirs(os.path.dirname(out_path), exist_ok=True)
                        except Exception:
                            pass
                        cv2.imwrite(out_path, processed_image)
                        return out_path
                except Exception as _e_letterbox:
                    print(f"AI Service: Letterbox-aware YOLO pipeline error: {_e_letterbox}")
            
            # Helper: refine a coarse box to tighter plate-like rectangle within it
            def _refine_plate_box(xa: int, ya: int, xb: int, yb: int) -> Tuple[int, int, int, int]:
                try:
                    xa = max(0, min(W - 1, xa)); xb = max(0, min(W, xb))
                    ya = max(0, min(H - 1, ya)); yb = max(0, min(H, yb))
                    if xb <= xa or yb <= ya:
                        return xa, ya, xb, yb
                    roi = image[ya:yb, xa:xb]
                    if roi.size == 0:
                        return xa, ya, xb, yb
                    import cv2 as _cv2
                    roi_gray = _cv2.cvtColor(roi, _cv2.COLOR_BGR2GRAY)
                    roi_gray = _cv2.bilateralFilter(roi_gray, 5, 25, 25)
                    thr = _cv2.adaptiveThreshold(
                        roi_gray, 255,
                        _cv2.ADAPTIVE_THRESH_GAUSSIAN_C, _cv2.THRESH_BINARY_INV,
                        31, 7
                    )
                    kernel = _cv2.getStructuringElement(_cv2.MORPH_RECT, (7, 3))
                    thr = _cv2.morphologyEx(thr, _cv2.MORPH_CLOSE, kernel, iterations=1)
                    contours, _ = _cv2.findContours(thr, _cv2.RETR_EXTERNAL, _cv2.CHAIN_APPROX_SIMPLE)
                    rh, rw = thr.shape[:2]
                    r_area = max(1, rh * rw)
                    best = None
                    best_score = -1.0
                    for cnt in contours:
                        x, y, w, h = _cv2.boundingRect(cnt)
                        if w <= 0 or h <= 0:
                            continue
                        ar = w / max(1, h)
                        area = w * h
                        rect_ratio = (_cv2.contourArea(cnt) / float(area)) if area > 0 else 0.0
                        # Prefer plate-like rectangles near lower half with modest coverage (avoid grilles)
                        if 2.2 <= ar <= 6.0 and 0.05 <= (area / r_area) <= 0.40:
                            cx = (x + x + w) * 0.5 / max(1, rw)
                            cy = (y + y + h) * 0.5 / max(1, rh)
                            # Slight bias to lower part of ROI
                            y_bias = 1.0 - min(abs((cy - 0.65) / 0.65), 1.0)
                            center_score = 0.7 * (1.0 - min(abs(cx - 0.5) / 0.5, 1.0)) + 0.3 * y_bias
                            size_score = min((area / r_area) / 0.65, 1.0)
                            score = 0.4 * rect_ratio + 0.4 * size_score + 0.2 * center_score
                            if score > best_score:
                                best_score = score
                                best = (x, y, w, h)
                    if best is None:
                        return xa, ya, xb, yb
                    x, y, w, h = best
                    pad_x = max(2, int(w * 0.06))
                    pad_y = max(2, int(h * 0.15))
                    rx1 = max(0, xa + x - pad_x)
                    ry1 = max(0, ya + y - pad_y)
                    rx2 = min(W, xa + x + w + pad_x)
                    ry2 = min(H, ya + y + h + pad_y)
                    return rx1, ry1, rx2, ry2
                except Exception:
                    return xa, ya, xb, yb
            
            # Helper: OCR-driven refinement inside a YOLO box; returns tightened coords or original
            def _ocr_refine_box(xa: int, ya: int, xb: int, yb: int) -> Tuple[int, int, int, int]:
                try:
                    if self.ocr_reader is None:
                        return xa, ya, xb, yb
                    xa = max(0, min(W - 1, xa)); xb = max(0, min(W, xb))
                    ya = max(0, min(H - 1, ya)); yb = max(0, min(H, yb))
                    if xb <= xa or yb <= ya:
                        return xa, ya, xb, yb
                    import cv2 as _cv2
                    roi_rgb = _cv2.cvtColor(image[ya:yb, xa:xb], _cv2.COLOR_BGR2RGB)
                    ocr = self.ocr_reader.readtext(roi_rgb)
                    xs: List[int] = []
                    ys: List[int] = []
                    xe: List[int] = []
                    ye: List[int] = []
                    for (bb, tx, cf) in ocr:
                        if cf is None:
                            cf = 0.0
                        clean = ''.join([c for c in str(tx).upper() if c.isalnum()])
                        if len(clean) < 3 or len(clean) > 9:
                            continue
                        # Only accept if text matches license-plate patterns (avoid grilles/logos)
                        plate_like = self._is_likely_license_plate(clean) and cf >= 0.45
                        if plate_like:
                            bx = [p[0] for p in bb]; by = [p[1] for p in bb]
                            xs.append(min(bx)); ys.append(min(by))
                            xe.append(max(bx)); ye.append(max(by))
                    if not xs:
                        return xa, ya, xb, yb
                    rx1 = max(0, xa + min(xs))
                    ry1 = max(0, ya + min(ys))
                    rx2 = min(W, xa + max(xe))
                    ry2 = min(H, ya + max(ye))
                    # small padding
                    pad_x = max(2, int((rx2 - rx1) * 0.06))
                    pad_y = max(2, int((ry2 - ry1) * 0.14))
                    rx1 = max(0, rx1 - pad_x); ry1 = max(0, ry1 - pad_y)
                    rx2 = min(W, rx2 + pad_x); ry2 = min(H, ry2 + pad_y)
                    # Clamp refined ROI relative to the coarse ROI to prevent tall/wide masks
                    roi_w = max(1, xb - xa); roi_h = max(1, yb - ya)
                    max_h_rel = int(roi_h * 0.28)
                    if (ry2 - ry1) > max_h_rel:
                        c = (ry1 + ry2) // 2
                        ry1 = max(0, c - max_h_rel // 2); ry2 = min(H, ry1 + max_h_rel)
                    # Ensure aspect ratio not too small; prefer shrinking height
                    rw = max(1, rx2 - rx1); rh = max(1, ry2 - ry1)
                    min_ar = 2.0
                    if (rw / rh) < min_ar:
                        target_h = max(1, int(rw / min_ar))
                        c = (ry1 + ry2) // 2
                        ry1 = max(0, c - target_h // 2); ry2 = min(H, ry1 + target_h)
                    return rx1, ry1, rx2, ry2
                except Exception:
                    return xa, ya, xb, yb
            
            # Convert to grayscale and RGB for OCR/detection variants
            gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
            rgb  = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
            
            # Use EasyOCR to detect text
            print(f"AI Service: Processing image: {image_path} strict={strict} mode={mode}")
            print(f"AI Service: Image shape: {image.shape}")
            # Normalize mode flags
            mode_l = str(mode).lower()
            is_ocr_only = (mode_l in ['ocr_only', 'ocr-only', 'ocr_only_debug'])
            is_speed = (mode_l in ['speed', 'fast', 'quick'])
            is_debug = (mode_l.endswith('_debug'))
            try:
                print(f"AI Service: Mode evaluation -> is_ocr_only={is_ocr_only} is_speed={is_speed} is_debug={is_debug}")
            except Exception:
                pass
            
            # Enhance image for better OCR results, especially for low-resolution images
            # Apply adaptive histogram equalization to improve contrast
            clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8,8))
            enhanced_gray = clahe.apply(gray)
            
            # Apply slight sharpening to make text more readable
            kernel = np.array([[-1,-1,-1], [-1,9,-1], [-1,-1,-1]])
            sharpened = cv2.filter2D(enhanced_gray, -1, kernel)
            
            print(f"AI Service: Applied image enhancement for better OCR")
            
            blurred_count = 0

            # YOLO detection (multi-pass by default; reduced in speed mode)
            if (not is_ocr_only) and self.license_plate_model is not None:
                try:
                    print(f"AI Service: Running YOLO detection (speed={is_speed})...")
                    if is_speed:
                        # Single pass with higher resolution and stricter confidence for precision
                        passes = [
                            { 'img': image, 'conf': 0.40, 'imgsz': 1280, 'scale': 1.0 },
                        ]
                    else:
                        usharp = cv2.GaussianBlur(image, (0, 0), sigmaX=1.2)
                        usharp = cv2.addWeighted(image, 1.6, usharp, -0.6, 0)
                        passes = [
                            { 'img': image,  'conf': 0.45, 'imgsz': 1280, 'scale': 1.0 },
                            { 'img': image,  'conf': 0.40, 'imgsz': 1536, 'scale': 1.0 },
                            { 'img': usharp, 'conf': 0.40, 'imgsz': 1536, 'scale': 1.0 },
                        ]
                        # Add upscales only when not in speed mode
                        if min(H, W) < 700:
                            up2 = cv2.resize(image, None, fx=2.0, fy=2.0, interpolation=cv2.INTER_CUBIC)
                            passes.append({ 'img': up2, 'conf': 0.36, 'imgsz': 1280, 'scale': 2.0 })
                        if min(H, W) < 450:
                            up3 = cv2.resize(image, None, fx=3.0, fy=3.0, interpolation=cv2.INTER_CUBIC)
                            passes.append({ 'img': up3, 'conf': 0.34, 'imgsz': 1536, 'scale': 3.0 })
                        # Final recall-focused pass: lower conf but require OCR validation inside detections
                        passes.append({ 'img': image, 'conf': 0.25, 'imgsz': 1536, 'scale': 1.0, 'ocr_validate': True })

                    for p in passes:
                        rgb = cv2.cvtColor(p['img'], cv2.COLOR_BGR2RGB)
                        results = self.license_plate_model.predict(
                            rgb, conf=p['conf'], iou=0.5, imgsz=p['imgsz'], verbose=False
                        )
                        if not results:
                            continue
                        res = results[0]
                        names = getattr(res, 'names', getattr(self.license_plate_model, 'names', {}))
                        boxes = getattr(res, 'boxes', None)
                        if boxes is None or not hasattr(boxes, 'xyxy'):
                            continue
                        xyxy = boxes.xyxy.cpu().numpy() if hasattr(boxes.xyxy, 'cpu') else boxes.xyxy
                        try:
                            raw_count = 0 if xyxy is None else (xyxy.shape[0] if hasattr(xyxy, 'shape') else len(xyxy))
                        except Exception:
                            raw_count = 0
                        print(f"AI Service: YOLO pass imgsz={p['imgsz']} conf={p['conf']} scale={p.get('scale',1.0)} -> raw_boxes={raw_count}")
                        clss = boxes.cls.cpu().numpy() if hasattr(boxes, 'cls') and hasattr(boxes, 'cpu') else None
                        # Try to read per-box confidences when available
                        confs = None
                        try:
                            confs = boxes.conf.cpu().numpy() if hasattr(boxes, 'conf') and hasattr(boxes.conf, 'cpu') else None
                        except Exception:
                            confs = None
                        scale_back = 1.0 / float(p.get('scale', 1.0))
                        found_any = False
                        accepted_in_pass = 0
                        for idx, box in enumerate(xyxy):
                            x1b, y1b, x2b, y2b = [int(max(0, v * scale_back)) for v in box]
                            if x2b <= x1b or y2b <= y1b:
                                continue
                            accept = True
                            # Prefer model-provided class name if available
                            name_accept = False
                            if names is not None and clss is not None:
                                try:
                                    cname = str(names.get(int(clss[idx]), '')).lower()
                                    # consider common aliases for license plates across datasets
                                    if any(tok in cname for tok in ['plate', 'license', 'licence', 'lpr', 'plaka', 'matric', '牌']):
                                        name_accept = True
                                except Exception:
                                    pass
                            w_box = x2b - x1b
                            h_box = y2b - y1b
                            ar = w_box / max(1, h_box)
                            cy_box = 0.5 * (y1b + y2b)
                            # Size-aware thresholds; prefer plate-like geometry and reasonable area
                            min_w = max(int(W * 0.030), 24)
                            min_h = max(int(H * 0.014), 10)
                            area_box = w_box * h_box
                            # Unified geometry checks; allow wider variety but cut tiny/huge regions
                            ar_min, ar_max = 1.2, 6.0
                            area_min, area_max = (image_area * 0.0015), (image_area * 0.20)
                            cy_min, cy_max = (H * 0.08), (H * 0.98)
                            # In strict mode, keep geometry but don’t over-tighten; rely on OCR verification below
                            if strict:
                                pass
                            if not (ar_min <= ar <= ar_max and w_box >= min_w and h_box >= min_h and cy_min <= cy_box <= cy_max and area_min <= area_box <= area_max):
                                accept = False
                            # Confidence-aware OCR gate (and operator override):
                            # Require OCR when generic model OR low box confidence OR recall pass
                            # OR when PLATE_REQUIRE_OCR_INSIDE_YOLO is set (default: true).
                            if accept and self.ocr_reader is not None:
                                try:
                                    box_conf = float(confs[idx]) if (confs is not None and idx < len(confs)) else float(p.get('conf', 0.25))
                                    # Default to False so YOLO boxes are not dropped when OCR is unavailable;
                                    # operators can turn this on via env if desired.
                                    require_ocr_global = self._env_flag('PLATE_REQUIRE_OCR_INSIDE_YOLO', False)
                                    # Require OCR when using generic model OR very low box confidence OR recall pass OR global override
                                    require_ocr = bool(self.model_is_generic or box_conf < 0.25 or bool(p.get('ocr_validate', False)) or require_ocr_global)
                                    if require_ocr:
                                        roi_rgb = cv2.cvtColor(image[max(0, y1b):min(H, y2b), max(0, x1b):min(W, x2b)], cv2.COLOR_BGR2RGB)
                                        ocr_cands = self.ocr_reader.readtext(roi_rgb)
                                        plate_like = False
                                        for (_bb, _tx, _cf) in ocr_cands:
                                            clean = ''.join([c for c in str(_tx).upper() if c.isalnum()])
                                            if len(clean) >= 4 and len(clean) <= 9 and any(ch.isalpha() for ch in clean) and any(ch.isdigit() for ch in clean) and (_cf or 0) >= 0.40:
                                                plate_like = True
                                                break
                                        if not plate_like:
                                            accept = False
                                except Exception:
                                    pass
                            if not accept:
                                continue
                            # Robust padding to ensure full plate coverage (handles slight angle/offset)
                            # Allow operator override via PLATE_PAD_RATIO (e.g., 0.22 .. 0.45)
                            _default_pad = (0.30 if not strict else 0.25)
                            try:
                                _pad_env = os.getenv('PLATE_PAD_RATIO', '').strip()
                                pad_ratio = float(_pad_env) if _pad_env else _default_pad
                                pad_ratio = max(0.05, min(0.60, pad_ratio))
                            except Exception:
                                pad_ratio = _default_pad
                            pad_x = max(4, int(w_box * pad_ratio))
                            pad_y = max(4, int(h_box * pad_ratio))
                            xa = max(0, x1b - pad_x)
                            ya = max(0, y1b - pad_y)
                            xb = min(W, x2b + pad_x)
                            yb = min(H, y2b + pad_y)
                            # Clamp overly large boxes to avoid masking bumpers/grilles (tighter)
                            bw = max(1, xb - xa)
                            bh = max(1, yb - ya)
                            if bw > int(W * (0.42 if not strict else 0.36)):
                                cx = (xa + xb) // 2
                                half_w = int(W * (0.21 if not strict else 0.18))
                                xa = max(0, cx - half_w)
                                xb = min(W, cx + half_w)
                            if bh > int(H * (0.18 if not strict else 0.12)):
                                cy = (ya + yb) // 2
                                half_h = int(H * (0.09 if not strict else 0.06))
                                ya = max(0, cy - half_h)
                                yb = min(H, cy + half_h)
                            # Refine within the coarse box to find a tighter plate rectangle (skip OCR refine in speed mode)
                            if is_speed:
                                # keep coarse box for speed
                                pass
                            else:
                                xa2, ya2, xb2, yb2 = _ocr_refine_box(xa, ya, xb, yb)
                                if (xb2 - xa2) * (yb2 - ya2) < (xb - xa) * (yb - ya) * 0.9:
                                    xa, ya, xb, yb = xa2, ya2, xb2, yb2
                                else:
                                    xa, ya, xb, yb = _refine_plate_box(xa, ya, xb, yb)
                            try:
                                print(f"AI Service: FINAL ROI before blur: ({xa},{ya})-({xb},{yb}) size=({xb-xa}x{yb-ya}) img=({W}x{H})")
                            except Exception:
                                pass
                            roi = processed_image[ya:yb, xa:xb]
                            if roi.size > 0:
                                roi_h, roi_w = roi.shape[:2]
                                # Final safety clamp: prevent overly wide/tall blurs (slightly relaxed)
                                max_w = int(W * (0.22 if not strict else 0.18))
                                max_h = int(H * (0.12 if not strict else 0.10))
                                cur_w = xb - xa
                                cur_h = yb - ya
                                if cur_w > max_w:
                                    cx = (xa + xb) // 2
                                    half = max_w // 2
                                    xa = max(0, cx - half)
                                    xb = min(W, cx + half)
                                if (yb - ya) > max_h:
                                    cy = (ya + yb) // 2
                                    half = max_h // 2
                                    ya = max(0, cy - half)
                                    yb = min(H, cy + half)
                                # Recompute ROI after clamp
                                roi = processed_image[ya:yb, xa:xb]
                                roi_h, roi_w = roi.shape[:2]
                                # Compute blur kernel (strong for reliability)
                                try:
                                    _m_env = os.getenv('PLATE_BLUR_MULT', '').strip()
                                    mult_override = float(_m_env) if _m_env else None
                                except Exception:
                                    mult_override = None
                                mult = (0.32 if is_speed else (0.45 if strict else 0.40))
                                if isinstance(mult_override, float) and mult_override > 0:
                                    mult = mult_override
                                k = int(max(21, min(151, int(min(roi_w, roi_h) * mult))))
                                if k % 2 == 0:
                                    k += 1
                                # Try refined rotated rectangle mask inside ROI for exact coverage
                                quad = self._refine_plate_quad(roi)
                                if quad is not None:
                                    import cv2 as _cv2
                                    mask = np.zeros((roi_h, roi_w), dtype=np.uint8)
                                    _cv2.fillPoly(mask, [quad.astype(np.int32)], 255)
                                    # Light dilation to ensure corners/edges are fully covered
                                    try:
                                        _dw = max(1, int(roi_w * float(os.getenv('PLATE_MASK_DILATE_W_RATIO', '0.03'))))
                                        _dh = max(1, int(roi_h * float(os.getenv('PLATE_MASK_DILATE_H_RATIO', '0.05'))))
                                        ker = _cv2.getStructuringElement(_cv2.MORPH_RECT, ((_dw | 1), (_dh | 1)))
                                        mask = _cv2.dilate(mask, ker, iterations=1)
                                    except Exception:
                                        pass
                                    blurred_roi = _cv2.GaussianBlur(roi, (k, k), 0)
                                    # Extra operator-controlled obfuscation
                                    try:
                                        blurred_roi = self._apply_plate_obfuscation(roi, blurred_roi)
                                    except Exception:
                                        pass
                                    mask3 = _cv2.merge([mask, mask, mask])
                                    composited = np.where(mask3 == 255, blurred_roi, roi)
                                    processed_image[ya:yb, xa:xb] = composited
                                else:
                                    # Fallback: rectangular blur within refined ROI
                                    blurred_roi = cv2.GaussianBlur(roi, (k, k), 0)
                                    if not is_speed:
                                        try:
                                            px_w = max(8, roi_w // 8)
                                            px_h = max(6, roi_h // 8)
                                            small = cv2.resize(blurred_roi, (px_w, px_h), interpolation=cv2.INTER_AREA)
                                            blurred_roi = cv2.resize(small, (roi_w, roi_h), interpolation=cv2.INTER_NEAREST)
                                        except Exception:
                                            pass
                                    try:
                                        blurred_roi = self._apply_plate_obfuscation(roi, blurred_roi)
                                    except Exception:
                                        pass
                                    processed_image[ya:yb, xa:xb] = blurred_roi
                                # Post-blur verification to avoid partial/insufficient blur
                                try:
                                    self._post_blur_verify(processed_image, xa, ya, xb, yb)
                                except Exception:
                                    pass
                                blurred_count += 1
                                print(f"AI Service: YOLO blur at ({xa},{ya})-({xb},{yb}) [imgsz={p['imgsz']} conf={p['conf']} scale={p.get('scale',1.0)}]")
                                found_any = True
                                accepted_in_pass += 1
                        if blurred_count > 0:
                            break
                        print(f"AI Service: YOLO pass accepted={accepted_in_pass} (generic={self.model_is_generic})")
                        if not found_any:
                            print(f"AI Service: YOLO pass imgsz={p['imgsz']} conf={p['conf']} found 0 acceptable boxes (generic={self.model_is_generic})")
                except Exception as e:
                    print(f"AI Service: YOLO multi-pass error: {str(e)}")

            # YOLO union-rectangle fallback: when no blur happened, blur the union of all plausible YOLO plate boxes.
            if blurred_count == 0 and self.license_plate_model is not None:
                try:
                    rgb_union = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
                    # Slightly lenient confidence to capture far/angled plates
                    union_conf = 0.22
                    try:
                        union_conf = float(os.getenv('PLATE_UNION_CONF', '0.22'))
                    except Exception:
                        union_conf = 0.22
                    res_u = self.license_plate_model.predict(rgb_union, conf=union_conf, iou=0.6, imgsz=1280, verbose=False)
                    if res_u:
                        boxes = getattr(res_u[0], 'boxes', None)
                        if boxes is not None and hasattr(boxes, 'xyxy'):
                            xyxy = boxes.xyxy.cpu().numpy() if hasattr(boxes.xyxy, 'cpu') else boxes.xyxy
                            xs1, ys1, xs2, ys2 = [], [], [], []
                            for bx in (xyxy or []):
                                x1b, y1b, x2b, y2b = [int(v) for v in bx]
                                x1b = max(0, x1b); y1b = max(0, y1b); x2b = min(W, x2b); y2b = min(H, y2b)
                                w = x2b - x1b; h = y2b - y1b
                                if w <= 0 or h <= 0:
                                    continue
                                ar = w / max(1, h); area = w * h; ia = H * W; cy = 0.5 * (y1b + y2b)
                                if not (1.25 <= ar <= 8.8 and ia * 0.00006 <= area <= ia * 0.14 and H * 0.15 <= cy <= H * 0.96):
                                    continue
                                xs1.append(x1b); ys1.append(y1b); xs2.append(x2b); ys2.append(y2b)
                            if xs1 and ys1 and xs2 and ys2:
                                ux1, uy1, ux2, uy2 = min(xs1), min(ys1), max(xs2), max(ys2)
                                # No padding; keep tight union box
                                uroi = processed_image[uy1:uy2, ux1:ux2]
                                if uroi.size > 0:
                                    umask = self._build_plate_surface_mask(uroi)
                                    if umask is not None and np.count_nonzero(umask) > 0:
                                        k = int(max(31, min(211, int(min(uroi.shape[0], uroi.shape[1]) * 0.50)))) 
                                        if (k % 2) == 0: k += 1
                                        ublur = cv2.GaussianBlur(uroi, (k, k), 0)
                                        try:
                                            ublur = self._apply_plate_obfuscation(uroi, ublur)
                                        except Exception:
                                            pass
                                        m3 = cv2.merge([(umask*255).astype('uint8')]*3)
                                        comp = np.where(m3 == 255, ublur, uroi)
                                        processed_image[uy1:uy2, ux1:ux2] = comp
                                        try:
                                            self._post_blur_verify_mask(processed_image, ux1, uy1, ux2, uy2, umask)
                                        except Exception:
                                            pass
                                        blurred_count += 1
                                        print(f"AI Service: YOLO union mask fallback blur at ({ux1},{uy1})-({ux2},{uy2})")
                except Exception as _u_e:
                    print(f"AI Service: YOLO union fallback error: {_u_e}")

            # Tight OCR fallback (strict, plate-pattern only) if YOLO missed (skip in speed mode)
            if blurred_count == 0 and (not is_speed) and self.ocr_reader is not None:
                try:
                    print("AI Service: Running strict OCR fallback...")
                    ocr_results = self.ocr_reader.readtext(rgb)
                    best = None
                    best_w = -1
                    for (bbox, text, conf) in ocr_results:
                        try:
                            clean = ''.join([c for c in str(text).upper() if c.isalnum()])
                        except Exception:
                            clean = ""
                        if (conf or 0) < 0.40:
                            continue
                        if not self._is_likely_license_plate(clean):
                            continue
                        xs = [int(p[0]) for p in bbox]
                        ys = [int(p[1]) for p in bbox]
                        x1, x2 = max(0, min(xs)), min(W, max(xs))
                        y1, y2 = max(0, min(ys)), min(H, max(ys))
                        w = x2 - x1
                        h = y2 - y1
                        if w <= 0 or h <= 0:
                            continue
                        ar = w / max(1, h)
                        if not (1.6 <= ar <= 7.0):
                            continue
                        if w < max(int(W * 0.025), 16) or h < 10:
                            continue
                        if w > best_w:
                            best_w = w
                            best = (x1, y1, x2, y2)
                    if best is not None:
                        x1, y1, x2, y2 = best
                        pad_x = max(6, int((x2 - x1) * 0.12))
                        pad_y = max(6, int((y2 - y1) * 0.16))
                        xa = max(0, x1 - pad_x)
                        ya = max(0, y1 - pad_y)
                        xb = min(W, x2 + pad_x)
                        yb = min(H, y2 + pad_y)
                        roi = processed_image[ya:yb, xa:xb]
                        if roi.size > 0:
                            roi_h, roi_w = roi.shape[:2]
                            k = int(max(31, min(191, int(min(roi_w, roi_h) * (0.45 if strict else 0.35)))))
                            if k % 2 == 0:
                                k += 1
                            blurred_roi = cv2.GaussianBlur(roi, (k, k), 0)
                            try:
                                px_w = max(8, roi_w // 8)
                                px_h = max(6, roi_h // 8)
                                small = cv2.resize(blurred_roi, (px_w, px_h), interpolation=cv2.INTER_AREA)
                                blurred_roi = cv2.resize(small, (roi_w, roi_h), interpolation=cv2.INTER_NEAREST)
                            except Exception:
                                pass
                            try:
                                blurred_roi = self._apply_plate_obfuscation(roi, blurred_roi)
                            except Exception:
                                pass
                            processed_image[ya:yb, xa:xb] = blurred_roi
                            try:
                                self._post_blur_verify(processed_image, xa, ya, xb, yb)
                            except Exception:
                                pass
                            blurred_count += 1
                            print(f"AI Service: OCR strict fallback blur at ({xa},{ya})-({xb},{yb})")
                except Exception as e:
                    print(f"AI Service: OCR strict fallback error: {str(e)}")

            # Standalone OCR-based detection (enabled in OCR-only mode)
            if is_ocr_only and blurred_count == 0 and self.ocr_reader:
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

                # Pass 2b: RGB
                if not all_results:
                    print("AI Service: No text detected, Pass 2b: RGB...")
                    results = self.ocr_reader.readtext(rgb)
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
                if not all_results and min_dim < 1100:
                    for scale in [1.5, 2.0, 3.0, 4.0]:
                        print(f"AI Service: OCR upscale pass x{scale}...")
                        up_rgb = cv2.resize(rgb, None, fx=scale, fy=scale, interpolation=cv2.INTER_CUBIC)
                        results = self.ocr_reader.readtext(up_rgb)
                        for (bbox, text, conf) in results:
                            mapped = [[int(pt[0]/scale), int(pt[1]/scale)] for pt in bbox]
                            all_results.append((mapped, text, conf))
                        if all_results:
                            break

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
                    # Stricter acceptance: only clear plate-like text proceeds
                    weak_candidate = False
                    if not is_likely_plate:
                        clean = ''.join([c for c in text.upper() if c.isalnum()])
                        has_letters = any(c.isalpha() for c in clean)
                        has_digits = any(c.isdigit() for c in clean)
                        if has_letters and has_digits and 5 <= len(clean) <= 8:
                            x_coords_tmp = [p[0] for p in bbox]
                            y_coords_tmp = [p[1] for p in bbox]
                            w_tmp = max(x_coords_tmp) - min(x_coords_tmp)
                            h_tmp = max(y_coords_tmp) - min(y_coords_tmp)
                            ar = w_tmp / max(1, h_tmp)
                            if 2.1 <= ar <= 6.5:
                                weak_candidate = True

                    # Confidence-gated OCR usage (looser in OCR-only)
                    use_ocr = False
                    if is_ocr_only:
                        if is_likely_plate and confidence >= 0.35:
                            use_ocr = True
                        elif weak_candidate and confidence >= 0.60:
                            use_ocr = True
                    else:
                        if is_likely_plate and confidence >= 0.50:
                            use_ocr = True
                        elif weak_candidate and confidence >= 0.75:
                            use_ocr = True
                    if not use_ocr:
                        continue

                    # Extract coordinates
                    x_coords = [point[0] for point in bbox]
                    y_coords = [point[1] for point in bbox]

                    x1, x2 = int(min(x_coords)), int(max(x_coords))
                    y1, y2 = int(min(y_coords)), int(max(y_coords))

                    # Calculate detected text dimensions
                    detected_width = x2 - x1
                    detected_height = y2 - y1
                    if detected_width <= 0 or detected_height <= 0:
                        continue

                    # Additional geometric and positional filters to avoid non-plate text
                    H, W = image.shape[:2]
                    ar = detected_width / max(1, detected_height)
                    area = detected_width * detected_height
                    image_area = H * W
                    cy = 0.5 * (y1 + y2)
                    if not (1.5 <= ar <= 8.0):
                        continue
                    if not (image_area * 0.00006 <= area <= image_area * 0.09):
                        continue
                    if not (H * 0.25 <= cy <= H * 0.90):
                        continue

                    # Proportional padding, tightened to avoid over-blurring
                    if detected_width < 100:
                        h_padding = 6
                        v_padding = 5
                    else:
                        h_padding = int(detected_width * 0.08)
                        v_padding = int(detected_height * 0.18)

                    # For lower confidence, allow a bit more padding (still conservative)
                    if confidence < 0.6:
                        if detected_width < 100:
                            h_padding = max(h_padding, 8)
                            v_padding = max(v_padding, 7)
                        else:
                            h_padding = max(h_padding, int(detected_width * 0.10))
                            v_padding = max(v_padding, int(detected_height * 0.22))
                        logger.info(f"Low confidence ({confidence:.2f}), using extra padding: h={h_padding}, v={v_padding}")
                        print(f"AI Service: Low confidence, using extra padding: h={h_padding}px, v={v_padding}px")

                    logger.info(f"Detected text size: {detected_width}x{detected_height}, padding: h={h_padding}, v={v_padding}")
                    print(f"AI Service: Text size: {detected_width}x{detected_height}, padding: h={h_padding}px, v={v_padding}px")

                    x1 = max(0, x1 - h_padding)
                    y1 = max(0, y1 - v_padding)
                    x2 = min(image.shape[1], x2 + h_padding)
                    y2 = min(image.shape[0], y2 + v_padding)

                    # Merge vertically adjacent peers (stacked plates) and build combined polygon
                    bx1, by1, bx2, by2 = max(0, x1 + h_padding), max(0, y1 + v_padding), max(0, x2 - h_padding), max(0, y2 - v_padding)
                    union_x1, union_y1, union_x2, union_y2 = x1, y1, x2, y2
                    poly_pts = [[int(p[0]), int(p[1])] for p in bbox]
                    try:
                        base_w = max(1, bx2 - bx1)
                        base_h = max(1, by2 - by1)
                        cy_this = 0.5 * (by1 + by2)
                        for (bbox2, text2, conf2) in all_results:
                            xs2 = [p[0] for p in bbox2]; ys2 = [p[1] for p in bbox2]
                            x1b, y1b = int(min(xs2)), int(min(ys2))
                            x2b, y2b = int(max(xs2)), int(max(ys2))
                            if x2b <= x1b or y2b <= y1b:
                                continue
                            overlap = max(0, min(bx2, x2b) - max(bx1, x1b))
                            overlap_ratio = overlap / float(base_w)
                            cy_peer = 0.5 * (y1b + y2b)
                            vertical_gap = abs(cy_peer - cy_this)
                            if overlap_ratio >= 0.50 and vertical_gap <= 1.20 * max(base_h, (y2b - y1b)):
                                for p2 in bbox2:
                                    poly_pts.append([int(p2[0]), int(p2[1])])
                                union_x1 = max(0, min(union_x1, x1b - h_padding))
                                union_y1 = max(0, min(union_y1, y1b - v_padding))
                                union_x2 = min(image.shape[1], max(union_x2, x2b + h_padding))
                                union_y2 = min(image.shape[0], max(union_y2, y2b + v_padding))
                            else:
                                # Horizontal-merge on same line: strong vertical overlap and small horizontal gap
                                v_overlap = max(0, min(by2, y2b) - max(by1, y1b))
                                v_base = max(1, min(by2 - by1, y2b - y1b))
                                v_overlap_ratio = v_overlap / float(v_base)
                                gap = 0
                                if x1b > bx2:
                                    gap = x1b - bx2
                                elif bx1 > x2b:
                                    gap = bx1 - x2b
                                if v_overlap_ratio >= 0.55 and gap <= int(0.20 * max(base_w, (x2b - x1b))):
                                    for p2 in bbox2:
                                        poly_pts.append([int(p2[0]), int(p2[1])])
                                    union_x1 = max(0, min(union_x1, x1b - h_padding))
                                    union_y1 = max(0, min(union_y1, y1b - v_padding))
                                    union_x2 = min(image.shape[1], max(union_x2, x2b + h_padding))
                                    union_y2 = min(image.shape[0], max(union_y2, y2b + v_padding))
                    except Exception:
                        pass

                    # Apply strong blur to the license plate region using polygon mask
                    roi = processed_image[union_y1:union_y2, union_x1:union_x2]
                    if roi.size > 0:
                        # Reject windows: high saturation and medium-low value
                        try:
                            hsv_roi = cv2.cvtColor(roi, cv2.COLOR_BGR2HSV)
                            mean_h, mean_s, mean_v = [float(np.mean(hsv_roi[:,:,i])) for i in range(3)]
                            if mean_s > 80.0 and mean_v < 160.0:
                                continue
                        except Exception:
                            pass
                        # Color whitelist override: white/yellow plates for low-confidence
                        if not is_likely_plate and is_ocr_only and confidence >= 0.30:
                            try:
                                hsv_roi2 = cv2.cvtColor(roi, cv2.COLOR_BGR2HSV)
                                s_mean = float(np.mean(hsv_roi2[:,:,1]))
                                v_mean = float(np.mean(hsv_roi2[:,:,2]))
                                white_like = (s_mean < 60.0 and v_mean > 190.0)
                                yellow_lower = np.array([10, 60, 70]); yellow_upper = np.array([45, 255, 255])
                                ymask = cv2.inRange(hsv_roi2, yellow_lower, yellow_upper)
                                yfrac = float(np.count_nonzero(ymask)) / float(ymask.size)
                                yellow_like = (yfrac > 0.25)
                                if white_like or yellow_like:
                                    is_likely_plate = True
                            except Exception:
                                pass
                        # Apply Gaussian blur with kernel sized to ROI to avoid over-blurring
                        roi_h, roi_w = roi.shape[:2]
                        k = int(max(31, min(171, int(min(roi_w, roi_h) * 0.45))))
                        if k % 2 == 0:
                            k += 1  # kernel size must be odd
                        try:
                            # Build combined convex hull relative to ROI and dilate slightly
                            pts_rel = np.array([[int(p[0] - union_x1), int(p[1] - union_y1)] for p in poly_pts], dtype=np.int32).reshape((-1,1,2))
                            try:
                                hull = cv2.convexHull(pts_rel)
                            except Exception:
                                hull = pts_rel
                            mask = np.zeros(roi.shape[:2], dtype=np.uint8)
                            cv2.fillPoly(mask, [hull], 255)
                            # Close small gaps between text instances to avoid pinholes
                            try:
                                close_k = max(3, int(min(union_w, union_h) * 0.02))
                                close_kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (close_k | 1, close_k | 1))
                                mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, close_kernel, iterations=1)
                            except Exception:
                                pass
                            union_w = max(1, union_x2 - union_x1)
                            union_h = max(1, union_y2 - union_y1)
                            # Tunable dilation so blur stays tight but covers borders
                            try:
                                import os as _os
                                dw_ratio = float(str(_os.getenv('PLATE_MASK_DILATE_W_RATIO', '0.03')).strip())
                                dh_ratio = float(str(_os.getenv('PLATE_MASK_DILATE_H_RATIO', '0.06')).strip())
                            except Exception:
                                dw_ratio, dh_ratio = 0.03, 0.06
                            dilate_w = max(2, int(union_w * dw_ratio))
                            dilate_h = max(2, int(union_h * dh_ratio))
                            kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (dilate_w | 1, dilate_h | 1))
                            mask = cv2.dilate(mask, kernel, iterations=1)
                            blurred_roi = cv2.GaussianBlur(roi, (k, k), 0)
                            try:
                                blurred_roi = self._apply_plate_obfuscation(roi, blurred_roi)
                            except Exception:
                                pass
                            mask3 = cv2.merge([mask, mask, mask])
                            composited = np.where(mask3 == 255, blurred_roi, roi)
                            processed_image[union_y1:union_y2, union_x1:union_x2] = composited
                            # Optional rectangular fallback to guarantee full-plate coverage
                            try:
                                rect_fallback = self._env_flag('PLATE_RECT_FALLBACK', True) or self._env_flag('PLATE_RECT_ALWAYS', False)
                                if rect_fallback:
                                    try:
                                        padr = float(str(_os.getenv('PLATE_RECT_PAD_RATIO', '0.08')).strip())
                                    except Exception:
                                        padr = 0.08
                                    rx1 = max(0, union_x1 - int((union_x2 - union_x1) * padr))
                                    ry1 = max(0, union_y1 - int((union_y2 - union_y1) * padr))
                                    rx2 = min(W, union_x2 + int((union_x2 - union_x1) * padr))
                                    ry2 = min(H, union_y2 + int((union_y2 - union_y1) * padr))
                                    rect = processed_image[ry1:ry2, rx1:rx2]
                                    if rect.size > 0:
                                        krect = int(max(31, min(211, int(min(rect.shape[0], rect.shape[1]) * 0.50))))
                                        if krect % 2 == 0: krect += 1
                                        rect_blur = cv2.GaussianBlur(rect, (krect, krect), 0)
                                        try:
                                            rect_blur = self._apply_plate_obfuscation(rect, rect_blur)
                                        except Exception:
                                            pass
                                        processed_image[ry1:ry2, rx1:rx2] = rect_blur
                            except Exception:
                                pass
                            # Optional rotated-rectangle fallback to capture tilted plate corners
                            try:
                                if self._env_flag('PLATE_ROTATED_RECT_FALLBACK', True):
                                    import numpy as _np
                                    pts_arr = _np.array([[int(px - union_x1), int(py - union_y1)] for (px, py) in poly_pts], dtype=_np.int32)
                                    if pts_arr.shape[0] >= 3:
                                        rrect = cv2.minAreaRect(pts_arr)
                                        box = cv2.boxPoints(rrect).astype(_np.int32)
                                        rmask = _np.zeros(roi.shape[:2], dtype=_np.uint8)
                                        cv2.fillConvexPoly(rmask, box, 255)
                                        try:
                                            rratio = float(os.getenv('PLATE_ROT_DILATE_RATIO', '0.03'))
                                        except Exception:
                                            rratio = 0.03
                                        dr = max(2, int(min(union_w, union_h) * rratio))
                                        rker = cv2.getStructuringElement(cv2.MORPH_RECT, (dr | 1, dr | 1))
                                        rmask = cv2.dilate(rmask, rker, iterations=1)
                                        rk = int(max(31, min(211, int(min(roi_h, roi_w) * 0.50))))
                                        if rk % 2 == 0: rk += 1
                                        rblur = cv2.GaussianBlur(roi, (rk, rk), 0)
                                        try:
                                            rblur = self._apply_plate_obfuscation(roi, rblur)
                                        except Exception:
                                            pass
                                        rmask3 = _np.dstack([rmask, rmask, rmask])
                                        processed_image[union_y1:union_y2, union_x1:union_x2] = _np.where(rmask3 == 255, rblur, processed_image[union_y1:union_y2, union_x1:union_x2])
                            except Exception:
                                pass
                            try:
                                self._post_blur_verify(processed_image, union_x1, union_y1, union_x2, union_y2)
                            except Exception:
                                pass
                            if is_debug:
                                try:
                                    # Draw convex hull outline thicker
                                    hull_abs = np.array([[int(union_x1 + p[0][0]), int(union_y1 + p[0][1])] for p in (hull if 'hull' in locals() else pts_rel)], dtype=np.int32).reshape((-1,1,2))
                                    cv2.polylines(processed_image, [hull_abs], True, (255, 0, 255), 3)
                                except Exception:
                                    pass
                                try:
                                    cv2.rectangle(processed_image, (union_x1, union_y1), (union_x2, union_y2), (0, 255, 0), 1)
                                except Exception:
                                    pass
                        except Exception:
                            blurred_roi = cv2.GaussianBlur(roi, (k, k), 0)
                            processed_image[y1:y2, x1:x2] = blurred_roi

                        logger.info(f"Blurred potential license plate (OCR detect): '{text}' at ({x1},{y1})-({x2},{y2})")
                        print(f"AI Service: BLURRED (OCR detect) license plate: '{text}' at ({x1},{y1})-({x2},{y2})")
                        blurred_count += 1
                
                
            
            # YOLO-assisted proposals in OCR-only mode: propose boxes, require OCR inside
            if is_ocr_only and blurred_count == 0 and self.license_plate_model is not None and self.ocr_reader is not None:
                try:
                    print("AI Service: OCR-only → YOLO proposal stage...")
                    usharp = cv2.GaussianBlur(image, (0, 0), sigmaX=1.2)
                    usharp = cv2.addWeighted(image, 1.6, usharp, -0.6, 0)
                    passes = [
                        { 'img': image,  'conf': 0.26, 'imgsz': 960,  'scale': 1.0 },
                        { 'img': image,  'conf': 0.22, 'imgsz': 1280, 'scale': 1.0 },
                        { 'img': usharp, 'conf': 0.22, 'imgsz': 1280, 'scale': 1.0 },
                    ]
                    if min(H, W) < 700:
                        up2 = cv2.resize(image, None, fx=2.0, fy=2.0, interpolation=cv2.INTER_CUBIC)
                        passes.append({ 'img': up2, 'conf': 0.20, 'imgsz': 960,  'scale': 2.0 })
                    found_any = False
                    for p in passes:
                        rgbp = cv2.cvtColor(p['img'], cv2.COLOR_BGR2RGB)
                        results = self.license_plate_model.predict(rgbp, conf=p['conf'], iou=0.6, imgsz=p['imgsz'], verbose=False)
                        if not results:
                            continue
                        res = results[0]
                        boxes = getattr(res, 'boxes', None)
                        if boxes is None or not hasattr(boxes, 'xyxy'):
                            continue
                        xyxy = boxes.xyxy.cpu().numpy() if hasattr(boxes.xyxy, 'cpu') else boxes.xyxy
                        scale_back = 1.0 / float(p.get('scale', 1.0))
                        for idx, box in enumerate(xyxy):
                            x1b, y1b, x2b, y2b = [int(max(0, v * scale_back)) for v in box]
                            if x2b <= x1b or y2b <= y1b:
                                continue
                            # Geometry gate similar to OCR verification but looser as proposal
                            w_box = x2b - x1b; h_box = y2b - y1b
                            ar_box = w_box / max(1, h_box)
                            area_box = w_box * h_box
                            cy_box = 0.5 * (y1b + y2b)
                            if not (1.4 <= ar_box <= 8.5 and (image_area * 0.00008) <= area_box <= (image_area * 0.10) and (H * 0.18) <= cy_box <= (H * 0.95)):
                                continue
                            # OCR inside the YOLO box; build convex hull of OCR quads
                            xa, ya = max(0, x1b), max(0, y1b)
                            xb, yb = min(W, x2b), min(H, y2b)
                            roi_rgb = cv2.cvtColor(image[ya:yb, xa:xb], cv2.COLOR_BGR2RGB)
                            inner = self.ocr_reader.readtext(roi_rgb)
                            pts_abs = []
                            any_plate = False
                            boxes_meta = []
                            for (_bb, _tx, _cf) in inner:
                                if _cf is None: _cf = 0.0
                                # Apply same plate heuristics and lower conf in OCR-only
                                looks_plate = (_cf >= 0.30) and self._is_likely_license_plate(_tx)
                                if not looks_plate:
                                    # Allow weak if has letters+digits and plausible AR
                                    clean = ''.join([c for c in str(_tx).upper() if c.isalnum()])
                                    has_letters = any(c.isalpha() for c in clean)
                                    has_digits = any(c.isdigit() for c in clean)
                                    xs2 = [q[0] for q in _bb]; ys2 = [q[1] for q in _bb]
                                    w2 = (max(xs2) - min(xs2)); h2 = (max(ys2) - min(ys2))
                                    ar2 = (w2 / max(1, h2)) if h2 > 0 else 0
                                    if has_letters and has_digits and 1.4 <= ar2 <= 8.5 and len(clean) >= 5:
                                        looks_plate = True
                                if looks_plate:
                                    any_plate = True
                                boxes_meta.append((_bb, looks_plate))
                            # If at least one looks_plate box exists, also absorb horizontally aligned neighbors
                            if any_plate:
                                # First add all points of plate-like boxes
                                for (_bb, looks_plate) in boxes_meta:
                                    if not looks_plate: 
                                        continue
                                    for q in _bb:
                                        pts_abs.append([int(xa + q[0]), int(ya + q[1])])
                                # Then add horizontally adjacent neighbors sharing same line
                                # Build simple bbox list
                                simple = []
                                for (_bb, looks_plate) in boxes_meta:
                                    xs2 = [q[0] for q in _bb]; ys2 = [q[1] for q in _bb]
                                    simple.append((min(xs2), min(ys2), max(xs2), max(ys2), looks_plate, _bb))
                                for (x1i, y1i, x2i, y2i, lp, bb_i) in simple:
                                    if not lp:
                                        # Check adjacency with any plate-like box
                                        for (x1p, y1p, x2p, y2p, lp2, bb_p) in simple:
                                            if not lp2:
                                                continue
                                            v_overlap = max(0, min(y2i, y2p) - max(y1i, y1p))
                                            v_base = max(1, min(y2i - y1i, y2p - y1p))
                                            v_ratio = v_overlap / float(v_base)
                                            gap = 0
                                            if x1i > x2p:
                                                gap = x1i - x2p
                                            elif x1p > x2i:
                                                gap = x1p - x2i
                                            if v_ratio >= 0.55 and gap <= int(0.22 * max(x2p - x1p, x2i - x1i)):
                                                for q in bb_i:
                                                    pts_abs.append([int(xa + q[0]), int(ya + q[1])])
                                                break
                            if not any_plate or len(pts_abs) < 3:
                                # Last-resort for tiny proposals: try color-gated rectangle blur first
                                did_fallback = False
                                roi_small = (xb - xa) < 180 or (yb - ya) < 80 or min(H, W) < 360
                                if roi_small:
                                    try:
                                        roi_for_color = image[ya:yb, xa:xb]
                                        if roi_for_color.size > 0:
                                            hsvp = cv2.cvtColor(roi_for_color, cv2.COLOR_BGR2HSV)
                                            s_mean = float(np.mean(hsvp[:,:,1]))
                                            v_mean = float(np.mean(hsvp[:,:,2]))
                                            # Allow operator to disable this color-based fallback to avoid non-plate text
                                            _disable_color = self._env_flag('PLATE_DISABLE_COLOR_FALLBACK', True)
                                            white_like = (False if _disable_color else (s_mean < 95.0 and v_mean > 140.0))  # allow dim/gray white
                                            yellow_lower = np.array([10, 60, 70]); yellow_upper = np.array([45, 255, 255])
                                            ymask = cv2.inRange(hsvp, yellow_lower, yellow_upper)
                                            yfrac = float(np.count_nonzero(ymask)) / float(ymask.size)
                                            yellow_like = (False if _disable_color else (yfrac > 0.15))
                                            if white_like or yellow_like:
                                                # Shrink margins to avoid bumper spill and EU band on left
                                                shrink_x = int((xb - xa) * 0.08)
                                                shrink_y = int((yb - ya) * 0.15)
                                                xa2 = max(0, xa + shrink_x)
                                                ya2 = max(0, ya + shrink_y)
                                                xb2 = min(W, xb - shrink_x)
                                                yb2 = min(H, yb - shrink_y)
                                                # Extra left trim to de-emphasize blue EU band when present
                                                xa2 = min(xb2 - 1, xa2 + int((xb - xa) * 0.03))
                                                roi2 = processed_image[ya2:yb2, xa2:xb2]
                                                if roi2.size > 0:
                                                    k2 = int(max(17, min(151, int(min(roi2.shape[1], roi2.shape[0]) * 0.36))))
                                                    if k2 % 2 == 0: k2 += 1
                                                    br2 = cv2.GaussianBlur(roi2, (k2, k2), 0)
                                                    try:
                                                        br2 = self._apply_plate_obfuscation(roi2, br2)
                                                    except Exception:
                                                        pass
                                                    processed_image[ya2:yb2, xa2:xb2] = br2
                                                    try:
                                                        self._post_blur_verify(processed_image, xa2, ya2, xb2, yb2)
                                                    except Exception:
                                                        pass
                                                    blurred_count += 1
                                                    found_any = True
                                                    did_fallback = True
                                                    print(f"AI Service: YOLO proposal fallback rectangle blur (color) at ({xa2},{ya2})-({xb2},{yb2})")
                                                    if is_debug:
                                                        try:
                                                            cv2.rectangle(processed_image, (xa2, ya2), (xb2, yb2), (0, 255, 0), 1)
                                                        except Exception:
                                                            pass
                                    except Exception:
                                        pass
                                # If color gate didn’t pass, use geometry-only rectangle blur for plate-like boxes
                                # Disable this when strict is requested or in OCR-only mode to avoid non-plate blurs
                                geom_disabled = self._env_flag('PLATE_DISABLE_GEOM_FALLBACK', False)
                                if (not did_fallback) and (not strict) and (mode != 'ocr_only') and (not geom_disabled):
                                    try:
                                        w_box = xb - xa; h_box = yb - ya
                                        ar_box = w_box / max(1, h_box)
                                        area_box = w_box * h_box
                                        if 2.0 <= ar_box <= 6.8 and (image_area * 0.00008) <= area_box <= (image_area * 0.11):
                                            shrink_x = int((xb - xa) * 0.08)
                                            shrink_y = int((yb - ya) * 0.15)
                                            xa2 = max(0, xa + shrink_x)
                                            ya2 = max(0, ya + shrink_y)
                                            xb2 = min(W, xb - shrink_x)
                                            yb2 = min(H, yb - shrink_y)
                                            xa2 = min(xb2 - 1, xa2 + int((xb - xa) * 0.02))
                                            roi2 = processed_image[ya2:yb2, xa2:xb2]
                                            if roi2.size > 0:
                                                k2 = int(max(17, min(151, int(min(roi2.shape[1], roi2.shape[0]) * 0.36))))
                                                if k2 % 2 == 0: k2 += 1
                                                br2 = cv2.GaussianBlur(roi2, (k2, k2), 0)
                                                try:
                                                    br2 = self._apply_plate_obfuscation(roi2, br2)
                                                except Exception:
                                                    pass
                                                processed_image[ya2:yb2, xa2:xb2] = br2
                                                blurred_count += 1
                                                found_any = True
                                                print(f"AI Service: YOLO proposal fallback rectangle blur (geom) at ({xa2},{ya2})-({xb2},{yb2})")
                                                if is_debug:
                                                    try:
                                                        cv2.rectangle(processed_image, (xa2, ya2), (xb2, yb2), (0, 255, 0), 1)
                                                    except Exception:
                                                        pass
                                    except Exception:
                                        pass
                                continue
                            # Build convex hull mask within ROI
                            roi = processed_image[ya:yb, xa:xb]
                            if roi.size <= 0:
                                continue
                            try:
                                pts_rel = np.array([[int(px - xa), int(py - ya)] for (px, py) in pts_abs], dtype=np.int32).reshape((-1,1,2))
                                try:
                                    hull = cv2.convexHull(pts_rel)
                                except Exception:
                                    hull = pts_rel
                                mask = np.zeros(roi.shape[:2], dtype=np.uint8)
                                cv2.fillPoly(mask, [hull], 255)
                                # Dilation tuned for proposals
                                dilate_w = max(3, int((xb - xa) * 0.05))
                                dilate_h = max(3, int((yb - ya) * 0.12))
                                kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (dilate_w | 1, dilate_h | 1))
                                mask = cv2.dilate(mask, kernel, iterations=1)
                                k = int(max(31, min(171, int(min(roi.shape[1], roi.shape[0]) * 0.38))))
                                if k % 2 == 0: k += 1
                                blurred_roi = cv2.GaussianBlur(roi, (k, k), 0)
                                mask3 = cv2.merge([mask, mask, mask])
                                composited = np.where(mask3 == 255, blurred_roi, roi)
                                processed_image[ya:yb, xa:xb] = composited
                                blurred_count += 1
                                found_any = True
                                print(f"AI Service: YOLO proposal + OCR blur at ({xa},{ya})-({xb},{yb})")
                                if is_debug:
                                    try:
                                        hull_abs = np.array([[int(xa + p[0][0]), int(ya + p[0][1])] for p in (hull if 'hull' in locals() else pts_rel)], dtype=np.int32).reshape((-1,1,2))
                                        cv2.polylines(processed_image, [hull_abs], True, (255, 0, 255), 3)
                                        cv2.rectangle(processed_image, (xa, ya), (xb, yb), (0, 255, 0), 1)
                                    except Exception:
                                        pass
                            except Exception:
                                pass
                        if found_any:
                            break
                except Exception as e:
                    print(f"AI Service: YOLO proposal stage error: {str(e)}")

            # High-contrast rectangle fallback with convex hull (very conservative)
            # Disable when strict mode is requested
            if blurred_count == 0 and (not strict):
                try:
                    print("AI Service: Final high-contrast rectangle fallback...")
                    edges = cv2.Canny(gray, 80, 200)
                    kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (5, 3))
                    morph = cv2.morphologyEx(edges, cv2.MORPH_CLOSE, kernel, iterations=2)
                    contours, _ = cv2.findContours(morph, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
                    image_area = H * W
                    best = None
                    best_score = 0.0
                    for cnt in contours:
                        if cv2.contourArea(cnt) < 12:
                            continue
                        peri = cv2.arcLength(cnt, True)
                        approx = cv2.approxPolyDP(cnt, 0.03 * peri, True)
                        rect = cv2.minAreaRect(cnt)
                        (cx, cy), (rw, rh), ang = rect
                        w = max(rw, rh); h = min(rw, rh)
                        if h <= 0 or w <= 0:
                            continue
                        ar = w / max(1, h)
                        area = (w * h)
                        # Prefer bottom-half, plate-like AR and sensible area
                        if 1.8 <= ar <= 8.0 and (image_area * 0.00005) <= area <= (image_area * 0.10) and cy >= H * 0.18:
                            # check local contrast inside bbox as a score
                            box = cv2.boxPoints(rect).astype(int)
                            xs = [p[0] for p in box]; ys = [p[1] for p in box]
                            x1 = max(0, min(xs)); y1 = max(0, min(ys))
                            x2 = min(W, max(xs)); y2 = min(H, max(ys))
                            roi = gray[y1:y2, x1:x2]
                            if roi.size <= 0:
                                continue
                            contrast = float(np.std(roi))
                            score = contrast * (1.0 + 0.1 * ar)
                            if score > best_score:
                                best_score = score
                                best = (box, x1, y1, x2, y2)
                    if best is not None:
                        box, x1, y1, x2, y2 = best
                        xa, ya, xb, yb = x1, y1, x2, y2
                        # Shrink margins slightly
                        shrink_x = int((xb - xa) * 0.06)
                        shrink_y = int((yb - ya) * 0.12)
                        xa = max(0, xa + shrink_x)
                        ya = max(0, ya + shrink_y)
                        xb = min(W, xb - shrink_x)
                        yb = min(H, yb - shrink_y)
                        roi = processed_image[ya:yb, xa:xb]
                        if roi.size > 0:
                            # Build convex hull from the rotated rect points
                            pts_rel = np.array([[int(p[0] - xa), int(p[1] - ya)] for p in box], dtype=np.int32).reshape((-1,1,2))
                            try:
                                hull = cv2.convexHull(pts_rel)
                            except Exception:
                                hull = pts_rel
                            mask = np.zeros(roi.shape[:2], dtype=np.uint8)
                            cv2.fillPoly(mask, [hull], 255)
                            dilate_w = max(3, int((xb - xa) * 0.04))
                            dilate_h = max(3, int((yb - ya) * 0.10))
                            kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (dilate_w | 1, dilate_h | 1))
                            mask = cv2.dilate(mask, kernel, iterations=1)
                            k = int(max(31, min(171, int(min(roi.shape[1], roi.shape[0]) * 0.38))))
                            if k % 2 == 0: k += 1
                            blurred_roi = cv2.GaussianBlur(roi, (k, k), 0)
                            mask3 = cv2.merge([mask, mask, mask])
                            composited = np.where(mask3 == 255, blurred_roi, roi)
                            processed_image[ya:yb, xa:xb] = composited
                            blurred_count += 1
                            print(f"AI Service: High-contrast rectangle fallback blur at ({xa},{ya})-({xb},{yb})")
                            if is_debug:
                                try:
                                    hull_abs = np.array([[int(xa + p[0][0]), int(ya + p[0][1])] for p in (hull if 'hull' in locals() else pts_rel)], dtype=np.int32).reshape((-1,1,2))
                                    cv2.polylines(processed_image, [hull_abs], True, (255, 0, 255), 3)
                                    cv2.rectangle(processed_image, (xa, ya), (xb, yb), (0, 255, 0), 1)
                                except Exception:
                                    pass
                except Exception as e:
                    print(f"AI Service: High-contrast fallback error: {str(e)}")

            # Conservative contour fallback (disabled to avoid non-plate blur)
            if False and blurred_count == 0:
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
                            k = int(max(15, min(151, int(min(roi_w, roi_h) * 0.40))))
                            if k % 2 == 0:
                                k += 1
                            processed_image[y1:y2, x1:x2] = cv2.GaussianBlur(roi, (k, k), 0)
                            print(f"AI Service: Fallback contour blur at ({x1},{y1})-({x2},{y2})")
                    else:
                        print("AI Service: Contour fallback found no candidates")
                except Exception as e:
                    print(f"AI Service: Contour fallback error: {str(e)}")

            # Color/brightness fallback: tight rectangle when OCR/YOLO miss
            # Disable this path entirely to prevent non-plate blurs
            if False and blurred_count == 0 and (not is_ocr_only) and (not strict):
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
                        rect = cv2.minAreaRect(cnt)
                        (cx, cy), (rw, rh), ang = rect
                        w = max(rw, rh); h = min(rw, rh)
                        ar = w / max(1, h)
                        area = w * h
                        # Reasonable plate constraints and bottom-half preference; near-horizontal angle
                        if 1.9 <= ar <= 9.0 and (img_area * 0.001) <= area <= (img_area * 0.08) and cy > H * 0.25 and abs(float(ang)) <= 22.0:
                            candidates.append((area, rect))
                    if len(candidates) > 0:
                        candidates.sort(reverse=True)
                        _, rect = candidates[0]
                        # Shrink rectangle slightly to avoid overspill
                        (cx, cy), (rw, rh), ang = rect
                        rect = ((cx, cy), (rw * 0.88, rh * 0.82), ang)
                        box = cv2.boxPoints(rect).astype(int)
                        xs = [p[0] for p in box]; ys = [p[1] for p in box]
                        x1 = max(0, min(xs)); y1 = max(0, min(ys))
                        x2 = min(W, max(xs)); y2 = min(H, max(ys))
                        roi = processed_image[y1:y2, x1:x2]
                        if roi.size > 0:
                            k = int(max(15, min(111, int(min(roi.shape[1], roi.shape[0]) * 0.23))))
                            if k % 2 == 0: k += 1
                            local = box.copy()
                            local[:,0] -= x1; local[:,1] -= y1
                            mask = np.zeros(roi.shape[:2], dtype=np.uint8)
                            cv2.fillPoly(mask, [local], 255)
                            blurred_roi = cv2.GaussianBlur(roi, (k, k), 0)
                            mask3 = cv2.merge([mask, mask, mask])
                            composited = np.where(mask3 == 255, blurred_roi, roi)
                            processed_image[y1:y2, x1:x2] = composited
                            blurred_count += 1
                            print(f"AI Service: Color (yellow) polygon blur at ({x1},{y1})-({x2},{y2})")

                    # White front plates (low saturation, high value)
                    if blurred_count == 0:
                        white_lower = np.array([0, 0, 180])
                        white_upper = np.array([180, 100, 255])
                        white_mask = cv2.inRange(hsv, white_lower, white_upper)
                        white_mask = cv2.morphologyEx(white_mask, cv2.MORPH_CLOSE, kernel, iterations=2)
                        contours, _ = cv2.findContours(white_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
                        candidates = []
                        for cnt in contours:
                            rect = cv2.minAreaRect(cnt)
                            (cx, cy), (rw, rh), ang = rect
                            w = max(rw, rh); h = min(rw, rh)
                            ar = w / max(1, h)
                            area = w * h
                            if 1.8 <= ar <= 8.5 and (img_area * 0.001) <= area <= (img_area * 0.08) and cy > H * 0.18 and abs(float(ang)) <= 22.0:
                                candidates.append((area, rect))
                        if len(candidates) > 0:
                            candidates.sort(reverse=True)
                            _, rect = candidates[0]
                            (cx, cy), (rw, rh), ang = rect
                            rect = ((cx, cy), (rw * 0.88, rh * 0.82), ang)
                            box = cv2.boxPoints(rect).astype(int)
                            xs = [p[0] for p in box]; ys = [p[1] for p in box]
                            x1 = max(0, min(xs)); y1 = max(0, min(ys))
                            x2 = min(W, max(xs)); y2 = min(H, max(ys))
                            roi = processed_image[y1:y2, x1:x2]
                            if roi.size > 0:
                                k = int(max(15, min(111, int(min(roi.shape[1], roi.shape[0]) * 0.23))))
                                if k % 2 == 0: k += 1
                                local = box.copy()
                                local[:,0] -= x1; local[:,1] -= y1
                                mask = np.zeros(roi.shape[:2], dtype=np.uint8)
                                cv2.fillPoly(mask, [local], 255)
                                blurred_roi = cv2.GaussianBlur(roi, (k, k), 0)
                                mask3 = cv2.merge([mask, mask, mask])
                                composited = np.where(mask3 == 255, blurred_roi, roi)
                                processed_image[y1:y2, x1:x2] = composited
                                blurred_count += 1
                                print(f"AI Service: Color (white) polygon blur at ({x1},{y1})-({x2},{y2})")
                except Exception as e:
                    print(f"AI Service: Color fallback error: {str(e)}")

            # YOLO simple fallback (disabled; replaced by multi-pass above)
            if False and blurred_count == 0 and self.license_plate_model is not None:
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
                                    k = int(max(15, min(151, int(min(roi_w, roi_h) * 0.40))))
                                    if k % 2 == 0:
                                        k += 1
                                    processed_image[ya:yb, xa:xb] = cv2.GaussianBlur(roi, (k, k), 0)
                                    blurred_count += 1
                                    print(f"AI Service: YOLO blur at ({xa},{ya})-({xb},{yb})")
                except Exception as e:
                    print(f"AI Service: YOLO fallback error: {str(e)}")

            # Deterministic rectangle fallback if nothing blurred (disabled to avoid wrong-area blur)
            if False and blurred_count == 0:
                try:
                    gray2 = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
                    gray2 = cv2.bilateralFilter(gray2, 7, 75, 75)
                    edges = cv2.Canny(gray2, 40, 140)
                    kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (11, 3))
                    morph = cv2.morphologyEx(edges, cv2.MORPH_CLOSE, kernel, iterations=3)
                    contours, _ = cv2.findContours(morph, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

                    H, W = image.shape[:2]
                    image_area = H * W
                    best = None
                    best_score = -1.0

                    for cnt in contours:
                        x, y, w, h = cv2.boundingRect(cnt)
                        if w < 20 or h < 8:
                            continue
                        ar = w / max(1, h)
                        area = w * h
                        if not (1.6 <= ar <= 10.0):
                            continue
                        if not (image_area * 0.00015 <= area <= image_area * 0.15):
                            continue
                        cy = y + h * 0.5
                        # score: prefer AR~4, larger area, lower-half bias
                        ar_score = 1.0 - min(abs(ar - 4.0) / 4.0, 1.0)
                        area_score = min(area / (image_area * 0.05), 1.0)
                        y_score = 1.0 - abs((cy / H) - 0.7)
                        score = 0.5 * ar_score + 0.3 * area_score + 0.2 * y_score
                        if score > best_score:
                            best_score = score
                            best = (x, y, w, h)

                    if best is not None:
                        x, y, w, h = best
                        pad_x = max(6, int(w * 0.10))
                        pad_y = max(4, int(h * 0.18))
                        x1 = max(0, x - pad_x)
                        y1 = max(0, y - pad_y)
                        x2 = min(W, x + w + pad_x)
                        y2 = min(H, y + h + pad_y)

                        # Clamp ROI to a reasonable band to avoid over-blurring large areas
                        max_band_w = int(W * 0.60)
                        if (x2 - x1) > max_band_w:
                            cx = (x1 + x2) // 2
                            half = max_band_w // 2
                            x1 = max(0, cx - half)
                            x2 = min(W, cx + half)

                        max_band_h = int(H * 0.22)
                        band_h = min(y2 - y1, max_band_h)
                        desired_cy = int(H * 0.68)
                        y1 = max(0, desired_cy - band_h // 2)
                        y2 = min(H, y1 + band_h)
                        # Extra safeguard: require OCR confirmation before blurring deterministic band
                        ocr_ok = False
                        if self.ocr_reader is not None:
                            try:
                                roi_rgb = cv2.cvtColor(image[y1:y2, x1:x2], cv2.COLOR_BGR2RGB)
                                ocr_res = self.ocr_reader.readtext(roi_rgb)
                                for (_bb, _tx, _cf) in ocr_res:
                                    if (_cf or 0) >= 0.50 and self._is_likely_license_plate(_tx):
                                        ocr_ok = True
                                        break
                            except Exception:
                                ocr_ok = False
                        if ocr_ok:
                            # Optionally refine the band
                            x1, y1, x2, y2 = _refine_plate_box(x1, y1, x2, y2)
                            roi = processed_image[y1:y2, x1:x2]
                            if roi.size > 0:
                                k = int(max(31, min(171, int(min(roi.shape[1], roi.shape[0]) * 0.38))))
                                if k % 2 == 0:
                                    k += 1
                                processed_image[y1:y2, x1:x2] = cv2.GaussianBlur(roi, (k, k), 0)
                                print(f"AI Service: Deterministic fallback blur at ({x1},{y1})-({x2},{y2})")
                                blurred_count += 1
                except Exception as e:
                    print(f"AI Service: Deterministic fallback error: {str(e)}")

            # FINAL FAILSAFE (disabled to avoid non-plate blur)
            if False and blurred_count == 0:
                try:
                    H, W = image.shape[:2]
                    if min(H, W) < 260:
                        band_w = int(W * 0.70)
                        band_h = int(H * 0.25)
                        cy = int(H * 0.66)
                    else:
                        band_w = int(W * 0.62)
                        band_h = int(H * 0.20)
                        cy = int(H * 0.70)
                    cx = W // 2
                    x1 = max(0, cx - band_w // 2)
                    y1 = max(0, cy - band_h // 2)
                    x2 = min(W, cx + band_w // 2)
                    y2 = min(H, cy + band_h // 2)
                    roi = processed_image[y1:y2, x1:x2]
                    if roi.size > 0:
                        k = int(max(21, min(151, int(min(roi.shape[1], roi.shape[0]) * 0.45))))
                        if k % 2 == 0:
                            k += 1
                        processed_image[y1:y2, x1:x2] = cv2.GaussianBlur(roi, (k, k), 0)
                        print(f"AI Service: FINAL FAILSAFE blur at ({x1},{y1})-({x2},{y2})")
                        blurred_count += 1
                except Exception as e:
                    print(f"AI Service: Failsafe blur error: {str(e)}")
            
            # LIBERAL OCR FALLBACK (disabled to avoid non-plate blur)
            if False and blurred_count == 0 and self.ocr_reader is not None:
                try:
                    H, W = image.shape[:2]
                    # run a simple OCR pass on RGB
                    ocr_results = self.ocr_reader.readtext(rgb)
                    best = None
                    best_w = -1
                    for (bbox, text, conf) in ocr_results:
                        xs = [pt[0] for pt in bbox]
                        ys = [pt[1] for pt in bbox]
                        x1, x2 = int(min(xs)), int(max(xs))
                        y1, y2 = int(min(ys)), int(max(ys))
                        w = x2 - x1
                        h = y2 - y1
                        if w <= 0 or h <= 0:
                            continue
                        cy = 0.5 * (y1 + y2)
                        ar = w / max(1, h)
                        # liberal constraints: prefer plate-like boxes, bottom 80% of image
                        if 1.6 <= ar <= 10.0 and cy >= H * 0.20 and w >= max(24, int(W * 0.04)):
                            if w > best_w:
                                best_w = w
                                best = (x1, y1, x2, y2)
                    if best is not None:
                        x1, y1, x2, y2 = best
                        pad_x = max(8, int((x2 - x1) * 0.12))
                        pad_y = max(6, int((y2 - y1) * 0.20))
                        x1 = max(0, x1 - pad_x)
                        y1 = max(0, y1 - pad_y)
                        x2 = min(W, x2 + pad_x)
                        y2 = min(H, y2 + pad_y)
                        roi = processed_image[y1:y2, x1:x2]
                        if roi.size > 0:
                            k = int(max(15, min(151, int(min(roi.shape[1], roi.shape[0]) * 0.40))))
                            if k % 2 == 0:
                                k += 1
                            processed_image[y1:y2, x1:x2] = cv2.GaussianBlur(roi, (k, k), 0)
                            print(f"AI Service: Liberal OCR fallback blur at ({x1},{y1})-({x2},{y2})")
                            blurred_count += 1
                except Exception as e:
                    print(f"AI Service: Liberal OCR fallback error: {str(e)}")

            # POST-OCR VERIFICATION and OCR-ONLY mode
            try:
                if self.ocr_reader is not None:
                    # In OCR-only mode, read on original image; otherwise verify on processed image
                    rgb_ver = cv2.cvtColor(image if mode == 'ocr_only' else processed_image, cv2.COLOR_BGR2RGB)
                    ver_results = self.ocr_reader.readtext(rgb_ver)
                    post_blurs = 0
                    for (bbox, text, conf) in ver_results:
                        if conf is None:
                            conf = 0.0
                        # Lower confidence threshold for OCR-only
                        min_conf = 0.28 if mode == 'ocr_only' else 0.55
                        is_plate = (conf >= min_conf) and self._is_likely_license_plate(text)
                        # geometry sanity in verification stage
                        xs = [p[0] for p in bbox]; ys = [p[1] for p in bbox]
                        x1v, y1v = int(max(0, min(xs))), int(max(0, min(ys)))
                        x2v, y2v = int(min(W, max(xs))), int(min(H, max(ys)))
                        wv, hv = (x2v - x1v), (y2v - y1v)
                        if wv <= 0 or hv <= 0:
                            continue
                        arv = wv / max(1, hv)
                        areav = wv * hv
                        cyv = 0.5 * (y1v + y2v)
                        # Slightly relax AR; keep area conservative to avoid over-blur
                        ar_min_gate = 1.1 if mode == 'ocr_only' else 1.6
                        if not (ar_min_gate <= arv <= 7.0 and (image_area * 0.00006) <= areav <= (image_area * 0.09) and (H * 0.22) <= cyv <= (H * 0.92)):
                            is_plate = False
                        # Color-based whitelist for low-confidence OCR-only cases: white/yellow plate hues
                        if (not is_plate) and (mode == 'ocr_only') and (conf >= 0.28):
                            try:
                                roi_color = image[y1v:y2v, x1v:x2v]
                                if roi_color.size > 0:
                                    hsv_roi2 = cv2.cvtColor(roi_color, cv2.COLOR_BGR2HSV)
                                    # White-ish: low S, high V
                                    s_mean = float(np.mean(hsv_roi2[:,:,1]))
                                    v_mean = float(np.mean(hsv_roi2[:,:,2]))
                                    white_like = (s_mean < 60.0 and v_mean > 190.0)
                                    # Yellow-ish: use mask fraction
                                    yellow_lower = np.array([10, 60, 70])
                                    yellow_upper = np.array([45, 255, 255])
                                    ymask = cv2.inRange(hsv_roi2, yellow_lower, yellow_upper)
                                    yfrac = float(np.count_nonzero(ymask)) / float(ymask.size)
                                    yellow_like = (yfrac > 0.25)
                                    if (white_like or yellow_like) and (1.9 <= arv <= 7.0):
                                        is_plate = True
                            except Exception:
                                pass
                        if not is_plate:
                            continue
                        # Start with this box; then merge vertically stacked peers (two-line plates)
                        x1, y1 = x1v, y1v
                        x2, y2 = x2v, y2v
                        poly_pts = [[int(p[0]), int(p[1])] for p in bbox]
                        try:
                            cy_this = 0.5 * (y1v + y2v)
                            for (bbox2, text2, conf2) in ver_results:
                                if bbox2 is bbox:
                                    continue
                                xs2 = [p[0] for p in bbox2]; ys2 = [p[1] for p in bbox2]
                                x1b, y1b = int(min(xs2)), int(min(ys2))
                                x2b, y2b = int(max(xs2)), int(max(ys2))
                                if x2b <= x1b or y2b <= y1b:
                                    continue
                                overlap = max(0, min(x2v, x2b) - max(x1v, x1b))
                                base = max(1, min(x2v - x1v, x2b - x1b))
                                overlap_ratio = overlap / base
                                cy_peer = 0.5 * (y1b + y2b)
                                vertical_gap = abs(cy_peer - cy_this)
                                if overlap_ratio >= 0.50 and vertical_gap <= 1.20 * max((y2v - y1v), (y2b - y1b)):
                                    # Merge peer: extend polygon points and expand union box
                                    for p2 in bbox2:
                                        poly_pts.append([int(p2[0]), int(p2[1])])
                                    x1 = min(x1, x1b); y1 = min(y1, y1b)
                                    x2 = max(x2, x2b); y2 = max(y2, y2b)
                                else:
                                    # Also merge horizontally adjacent peers on same line (for split text like 'SL 593LM')
                                    # Require strong vertical overlap and small horizontal gap
                                    h_overlap = max(0, min(y2v, y2b) - max(y1v, y1b))
                                    v_base = max(1, min(y2v - y1v, y2b - y1b))
                                    v_overlap_ratio = h_overlap / v_base
                                    # Horizontal gap between boxes
                                    gap = 0
                                    if x1b > x2v:
                                        gap = x1b - x2v
                                    elif x1v > x2b:
                                        gap = x1v - x2b
                                    if v_overlap_ratio >= 0.55 and gap <= int(0.20 * max(x2v - x1v, x2b - x1b)):
                                        for p2 in bbox2:
                                            poly_pts.append([int(p2[0]), int(p2[1])])
                                        x1 = min(x1, x1b); y1 = min(y1, y1b)
                                        x2 = max(x2, x2b); y2 = max(y2, y2b)
                        except Exception:
                            pass
                        # Padding around OCR polygon; a bit wider in OCR-only to cover full plate
                        pad_x = max(6, int((x2 - x1) * (0.14 if mode != 'ocr_only' else 0.16)))
                        pad_y = max(5, int((y2 - y1) * (0.22 if mode != 'ocr_only' else 0.20)))
                        xa = max(0, x1 - pad_x); ya = max(0, y1 - pad_y)
                        xb = min(W, x2 + pad_x); yb = min(H, y2 + pad_y)
                        roi = processed_image[ya:yb, xa:xb]
                        # Window/glass rejection: skip regions with high saturation and medium-low value (common for tinted windows)
                        try:
                            hsv_roi = cv2.cvtColor(roi, cv2.COLOR_BGR2HSV)
                            mean_h, mean_s, mean_v = [float(np.mean(hsv_roi[:,:,i])) for i in range(3)]
                            if mean_s > 80.0 and mean_v < 160.0:
                                # Likely a window reflection, not a plate
                                continue
                        except Exception:
                            pass
                        if roi.size > 0:
                            # Safety clamp
                            max_w = int(W * (0.38 if mode == 'ocr_only' else 0.28))
                            max_h = int(H * (0.16 if mode == 'ocr_only' else 0.12))
                            if (xb - xa) > max_w:
                                cx = (xa + xb) // 2
                                half = max_w // 2
                                xa = max(0, cx - half); xb = min(W, cx + half)
                            if (yb - ya) > max_h:
                                cy = (ya + yb) // 2
                                half = max_h // 2
                                ya = max(0, cy - half); yb = min(H, cy + half)
                            roi = processed_image[ya:yb, xa:xb]
                            k = int(max(31, min(171, int(min(roi.shape[1], roi.shape[0]) * (0.36 if mode != 'ocr_only' else 0.40)))))
                            if k % 2 == 0: k += 1
                            # Polygon-masked blur using OCR quadrilateral to avoid bleeding onto grille/bumper
                            try:
                                # Use combined polygon points (merged peers if any) and fill convex hull to avoid self-intersection
                                pts = poly_pts if 'poly_pts' in locals() and poly_pts else [[int(p[0]), int(p[1])] for p in bbox]
                                pts_rel = np.array([[int(px - xa), int(py - ya)] for (px, py) in pts], dtype=np.int32).reshape((-1,1,2))
                                try:
                                    hull = cv2.convexHull(pts_rel)
                                except Exception:
                                    hull = pts_rel
                                mask = np.zeros(roi.shape[:2], dtype=np.uint8)
                                cv2.fillPoly(mask, [hull], 255)
                                # Dilate mask slightly to ensure plate edges are covered
                                dilate_w = max(3, int(max(1, (x2 - x1)) * 0.04))
                                dilate_h = max(3, int(max(1, (y2 - y1)) * 0.10))
                                kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (dilate_w | 1, dilate_h | 1))
                                mask = cv2.dilate(mask, kernel, iterations=1)
                                blurred_roi = cv2.GaussianBlur(roi, (k, k), 0)
                                mask3 = cv2.merge([mask, mask, mask])
                                composited = np.where(mask3 == 255, blurred_roi, roi)
                                processed_image[ya:yb, xa:xb] = composited
                                # Debug overlays
                                if is_debug:
                                    dbg_poly = np.array([[int(px), int(py)] for (px, py) in (pts if 'pts' in locals() else [[int(p[0]), int(p[1])] for p in bbox])], dtype=np.int32).reshape((-1,1,2))
                                    try:
                                        # Draw hull for clarity
                                        cv2.polylines(processed_image, [np.array([[int(px), int(py)] for (px, py) in (pts if 'pts' in locals() else [[int(p[0]), int(p[1])] for p in bbox])], dtype=np.int32).reshape((-1,1,2))], True, (255, 0, 255), 1)
                                        # Also draw convex hull outline thicker
                                        cv2.polylines(processed_image, [np.array([[int(xa + p[0][0]), int(ya + p[0][1])] for p in (hull if 'hull' in locals() else pts_rel)], dtype=np.int32).reshape((-1,1,2))], True, (255, 0, 255), 3)
                                    except Exception:
                                        pass
                                    try:
                                        cv2.rectangle(processed_image, (xa, ya), (xb, yb), (0, 255, 0), 1)
                                    except Exception:
                                        pass
                            except Exception:
                                processed_image[ya:yb, xa:xb] = cv2.GaussianBlur(roi, (k, k), 0)
                            post_blurs += 1
                            blurred_count += 1
                            print(f"AI Service: POST-OCR verification blur at ({xa},{ya})-({xb},{yb}) text='{text}' conf={conf:.2f}")
                    if post_blurs == 0:
                        print("AI Service: POST-OCR verification found no plate-like text")
            except Exception as e:
                print(f"AI Service: POST-OCR verification error: {str(e)}")

            # Debug marker: visually mark when debug mode is active
            try:
                if is_debug:
                    cv2.rectangle(processed_image, (3, 3), (15, 15), (255, 0, 255), -1)
                    cv2.putText(processed_image, 'OCR', (20, 18), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 0, 255), 1, cv2.LINE_AA)
                    print("AI Service: Debug marker applied to output image")
            except Exception:
                pass

            # Save the processed image
            print(f"AI Service: BLUR SUMMARY -> blurred_count={ blurred_count }")
            # If nothing was blurred, attempt a YOLO rectangle failsafe (optional), then OCR fallback
            if blurred_count == 0 and self.license_plate_model is not None and self._env_flag('PLATE_YOLO_RECT_FAILSAFE', True):
                try:
                    rgb_fs = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
                    fs_conf = 0.22
                    try:
                        fs_conf = float(os.getenv('PLATE_FAILSAFE_CONF', '0.22'))
                    except Exception:
                        fs_conf = 0.22
                    res_fs = self.license_plate_model.predict(rgb_fs, conf=fs_conf, iou=0.6, imgsz=1280, verbose=False)
                    if res_fs:
                        boxes = getattr(res_fs[0], 'boxes', None)
                        if boxes is not None and hasattr(boxes, 'xyxy'):
                            xyxy = boxes.xyxy.cpu().numpy() if hasattr(boxes.xyxy, 'cpu') else boxes.xyxy
                            for bx in (xyxy or []):
                                x1b, y1b, x2b, y2b = [int(v) for v in bx]
                                x1b = max(0, x1b); y1b = max(0, y1b); x2b = min(W, x2b); y2b = min(H, y2b)
                                w = x2b - x1b; h = y2b - y1b
                                if w <= 0 or h <= 0: 
                                    continue
                                ar = w / max(1, h); area = w * h; ia = H * W; cy = 0.5 * (y1b + y2b)
                                if not (1.4 <= ar <= 8.5 and ia * 0.00008 <= area <= ia * 0.12 and H * 0.18 <= cy <= H * 0.95):
                                    continue
                                try:
                                    padr = float(os.getenv('PLATE_RECT_PAD_RATIO', '0.08') or 0.08)
                                except Exception:
                                    padr = 0.08
                                rx1 = max(0, x1b - int(w * padr)); ry1 = max(0, y1b - int(h * padr))
                                rx2 = min(W, x2b + int(w * padr)); ry2 = min(H, y2b + int(h * padr))
                                roi = processed_image[ry1:ry2, rx1:rx2]
                                if roi.size == 0: 
                                    continue
                                k = int(max(31, min(211, int(min(roi.shape[0], roi.shape[1]) * 0.50)))) 
                                if (k % 2) == 0: k += 1
                                rblur = cv2.GaussianBlur(roi, (k, k), 0)
                                try:
                                    rblur = self._apply_plate_obfuscation(roi, rblur)
                                except Exception:
                                    pass
                                processed_image[ry1:ry2, rx1:rx2] = rblur
                                blurred_count += 1
                                print(f"AI Service: YOLO rectangle failsafe blur at ({rx1},{ry1})-({rx2},{ry2})")
                                break
                except Exception as _yfs_e:
                    print(f"AI Service: YOLO failsafe error: {_yfs_e}")

            # If still nothing was blurred, do not create a new file; try OCR rectangle fallback or return original
            if blurred_count == 0:
                # Moderate OCR-only fallback: try a single best OCR box with plate-like geometry/color
                try:
                    if self.ocr_reader is not None and mode in ('auto', 'ocr_only'):
                        rgb_src = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
                        cand = None
                        best_score = -1.0
                        for (bbox, text, conf) in self.ocr_reader.readtext(rgb_src):
                            if conf is None:
                                conf = 0.0
                            if not self._is_likely_license_plate(text):
                                continue
                            xs = [p[0] for p in bbox]; ys = [p[1] for p in bbox]
                            x1v, y1v = int(max(0, min(xs))), int(max(0, min(ys)))
                            x2v, y2v = int(min(W, max(xs))), int(min(H, max(ys)))
                            wv, hv = (x2v - x1v), (y2v - y1v)
                            if wv <= 0 or hv <= 0:
                                continue
                            arv = wv / max(1, hv)
                            areav = wv * hv
                            cyv = 0.5 * (y1v + y2v)
                            if not (1.4 <= arv <= 7.5 and (image_area * 0.00005) <= areav <= (image_area * 0.12) and (H * 0.18) <= cyv <= (H * 0.94)):
                                continue
                            # Color whitelist to avoid windows
                            try:
                                roi_color = image[y1v:y2v, x1v:x2v]
                                hsv_roi2 = cv2.cvtColor(roi_color, cv2.COLOR_BGR2HSV)
                                s_mean = float(np.mean(hsv_roi2[:,:,1]))
                                v_mean = float(np.mean(hsv_roi2[:,:,2]))
                                white_like = (s_mean < 70.0 and v_mean > 170.0)
                                yellow_lower = np.array([10, 60, 70])
                                yellow_upper = np.array([45, 255, 255])
                                ymask = cv2.inRange(hsv_roi2, yellow_lower, yellow_upper)
                                yfrac = float(np.count_nonzero(ymask)) / float(ymask.size)
                                yellow_like = (yfrac > 0.22)
                                if not (white_like or yellow_like):
                                    continue
                            except Exception:
                                pass
                            score = float(conf) + 0.1 * min(1.0, areav / float(image_area))
                            if score > best_score:
                                best_score = score
                                cand = (x1v, y1v, x2v, y2v)
                        if cand is not None:
                            x1, y1, x2, y2 = cand
                            pad_x = max(6, int((x2 - x1) * 0.16))
                            pad_y = max(5, int((y2 - y1) * 0.20))
                            xa = max(0, x1 - pad_x); ya = max(0, y1 - pad_y)
                            xb = min(W, x2 + pad_x); yb = min(H, y2 + pad_y)
                            # Clamp to avoid huge windows
                            max_w = int(W * 0.34)
                            max_h = int(H * 0.14)
                            if (xb - xa) > max_w:
                                cx = (xa + xb) // 2; half = max_w // 2
                                xa = max(0, cx - half); xb = min(W, cx + half)
                            if (yb - ya) > max_h:
                                cy = (ya + yb) // 2; half = max_h // 2
                                ya = max(0, cy - half); yb = min(H, cy + half)
                            roi = processed_image[ya:yb, xa:xb]
                            if roi.size > 0:
                                k = int(max(31, min(171, int(min(roi.shape[1], roi.shape[0]) * 0.40))))
                                if k % 2 == 0: k += 1
                                # Simple rectangular blur for fallback
                                processed_image[ya:yb, xa:xb] = cv2.GaussianBlur(roi, (k, k), 0)
                                root, ext = os.path.splitext(image_path)
                                processed_path = self._build_output_path(image_path)
                                cv2.imwrite(processed_path, processed_image)
                                logger.info(f"Fallback OCR blur applied. Saved to: {processed_path}")
                                return processed_path
                except Exception as _fb_e:
                    print(f"AI Service: Fallback OCR error: {_fb_e}")
                # PANIC MODE: Always obfuscate a bottom-center rectangle when enabled
                try:
                    if self._env_flag('PLATE_PANIC', False):
                        bw = max(40, int(W * 0.28))
                        bh = max(18, int(H * 0.11))
                        cx = W // 2
                        cy = int(H * 0.80)
                        xa = max(0, cx - bw // 2)
                        ya = max(0, cy - bh // 2)
                        xb = min(W, xa + bw)
                        yb = min(H, ya + bh)
                        roi = processed_image[ya:yb, xa:xb]
                        if roi.size > 0:
                            try:
                                roi2 = self._apply_plate_obfuscation(roi, roi)
                            except Exception:
                                roi2 = roi
                            processed_image[ya:yb, xa:xb] = roi2
                            processed_path = self._build_output_path(image_path)
                            cv2.imwrite(processed_path, processed_image)
                            logger.info(f"PANIC mode applied at ({xa},{ya})-({xb},{yb}). Saved to: {processed_path}")
                            return processed_path
                except Exception as _panic_e:
                    print(f"AI Service: PANIC mode error: {_panic_e}")
                logger.info("License plate blurring completed. No regions blurred; returning original image.")
                return image_path
            else:
                root, ext = os.path.splitext(image_path)
                processed_path = self._build_output_path(image_path)
                cv2.imwrite(processed_path, processed_image)
                logger.info(f"License plate blurring completed. Saved to: {processed_path}")
                return processed_path
            
        except Exception as e:
            logger.error(f"Error blurring license plates: {str(e)}")
            return image_path
    
    def _is_likely_license_plate(self, text: str) -> bool:
        """Check if text looks like a license plate"""
        import re
        # Map Eastern Arabic numerals to Western digits to improve Arabic plate handling
        arabic_digit_map = str.maketrans({
            '٠': '0','١': '1','٢': '2','٣': '3','٤': '4',
            '٥': '5','٦': '6','٧': '7','٨': '8','٩': '9'
        })
        
        # Remove spaces, hyphens, brackets, and convert to uppercase
        # OCR sometimes detects brackets around license plates
        clean_text = text.replace(' ', '').replace('-', '').replace('[', '').replace(']', '').replace('(', '').replace(')', '').upper()
        # Normalize Eastern Arabic numerals into Western digits
        clean_text = clean_text.translate(arabic_digit_map)
        
        # Handle common OCR misreads - normalize similar-looking characters
        # This helps with low-resolution images where OCR confuses characters
        # Create multiple normalized versions to catch OCR errors
        texts_to_check = [clean_text]
        
        # Skip common car model names and words that are definitely not license plates
        # Check both original and normalized versions
        skip_words = ['PRADO', 'TOYOTA', 'LAND', 'CRUISER', 'SUV', 'CAR', 'AUTO', 'VEHICLE', 'GRIDSERVE', 'GRISERVE', 'GR1DSERVE', 'GR15ERVE', 'SUSTAINABLE', 'ENERGY', 'KIA', 'EV9', 'BMW', 'MERCEDES', 'DMONOTS', 'FADS', 'DEMONS', 'DEMONST', 'GETTY', 'GETTYIMAGES', 'IMAGES', 'CREDIT', 'COOPER', 'LEXUS', 'DODGE', 'MINI']
        
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
            
            # Arabic/Iraqi plates often have a digits-only line (after translation)
            r'^\d{4,8}$',  # 4-8 digits (only if accompanied by plate geometry elsewhere)
            
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
            if len(text_variant) >= 5 and len(text_variant) <= 9:
                # Check if it has letters and numbers
                has_letters = any(c.isalpha() for c in text_variant)
                has_numbers = any(c.isdigit() for c in text_variant)

                # Only accept when BOTH letters and digits are present (avoid badges/words/numbers-only)
                if has_numbers and has_letters:
                    letter_count = sum(1 for c in text_variant if c.isalpha())
                    number_count = sum(1 for c in text_variant if c.isdigit())

                    # Reasonable bounds for low-resolution plates
                    if (1 <= letter_count <= 5 and 1 <= number_count <= 6):
                        logger.info(f"License plate heuristic matched: '{text}' -> '{text_variant}' (letters: {letter_count}, numbers: {number_count})")
                        print(f"AI Service: License plate heuristic matched: '{text}' -> '{text_variant}' (letters: {letter_count}, numbers: {number_count})")
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
