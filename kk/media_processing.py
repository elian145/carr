from __future__ import annotations

import base64
import os
from io import BytesIO
from typing import Tuple

from flask import current_app

from .security import generate_secure_filename
from .time_utils import utcnow


def heic_to_jpeg(raw_bytes: bytes) -> Tuple[bytes, bool]:
    """Convert HEIC/HEIF bytes to JPEG. Returns (jpeg_bytes, True) on success."""
    try:
        import pillow_heif  # type: ignore  # noqa: F401
        from PIL import Image

        pillow_heif.register_heif_opener()
        im = Image.open(BytesIO(raw_bytes))
        if im.mode not in ("RGB", "L"):
            im = im.convert("RGB")
        out = BytesIO()
        im.save(out, format="JPEG", quality=92, optimize=True)
        return out.getvalue(), True
    except Exception:
        return raw_bytes, False


def blur_image_bytes(raw_bytes: bytes, ext: str, *, skip_blur: bool = False) -> bytes:
    """Run license-plate blur on in-memory image bytes; return blurred bytes (or original on failure)."""
    if skip_blur:
        return raw_bytes

    out_bytes = raw_bytes
    try:
        enabled = (os.getenv("PLATE_BLUR_ENABLED", "1").strip() != "0")
        if enabled:
            from .license_plate_blur import blur_license_plates, get_plate_detector

            detector = get_plate_detector()
            if detector.is_configured():
                expand = float(os.getenv("PLATE_BLUR_EXPAND", "0") or "0")
                out_bytes, _meta = blur_license_plates(
                    image_bytes=raw_bytes,
                    output_ext=ext,
                    detector=detector,
                    expand_ratio=expand,
                )
    except Exception:
        # Best-effort: never fail the upload on blur issues.
        out_bytes = raw_bytes
    return out_bytes


def process_and_store_image(file_storage, inline_base64: bool, *, skip_blur: bool = False):
    """
    Save one uploaded image into `kk/static/uploads/car_photos/` as an optimized JPEG.

    Returns: (relative_path_under_static, optional_inline_base64_preview)
    """
    filename = generate_secure_filename(file_storage.filename)
    timestamp = utcnow().strftime("%Y%m%d_%H%M%S_%f")

    temp_rel = f"temp/processed_{timestamp}_{filename}"
    temp_abs = os.path.join(current_app.config["UPLOAD_FOLDER"], temp_rel)
    os.makedirs(os.path.dirname(temp_abs), exist_ok=True)
    file_storage.save(temp_abs)

    try:
        b64 = None
        base_name = os.path.splitext(filename)[0]
        final_filename = f"processed_{timestamp}_{base_name}.jpg"
        final_rel = os.path.join("uploads", "car_photos", final_filename).replace("\\", "/")
        final_abs = os.path.join(current_app.root_path, "static", final_rel)
        os.makedirs(os.path.dirname(final_abs), exist_ok=True)

        with open(temp_abs, "rb") as fp:
            raw_bytes = fp.read()

        ext = (os.path.splitext(filename)[1] or ".jpg").lower()
        if ext in (".heic", ".heif"):
            raw_bytes, converted = heic_to_jpeg(raw_bytes)
            if converted:
                ext = ".jpg"

        out_bytes = blur_image_bytes(raw_bytes, ext, skip_blur=skip_blur)

        # Optionally keep original alongside the blurred output (off by default for privacy).
        if os.getenv("PLATE_BLUR_KEEP_ORIGINAL", "0").strip() == "1":
            try:
                original_name = f"original_{final_filename}"
                original_abs = os.path.join(current_app.root_path, "static", "uploads", "car_photos", original_name)
                with open(original_abs, "wb") as f:
                    f.write(raw_bytes)
            except Exception:
                pass

        # Downscale/compress (best-effort).
        try:
            from PIL import Image

            im = Image.open(BytesIO(out_bytes))
            if im.mode not in ("RGB", "L"):
                im = im.convert("RGB")
            max_dim = int(os.getenv("UPLOAD_IMAGE_MAX_DIM", "1200") or "1200")
            if max(im.size) > max_dim:
                im.thumbnail((max_dim, max_dim), Image.Resampling.LANCZOS)
            buf = BytesIO()
            quality = int(os.getenv("UPLOAD_IMAGE_JPEG_QUALITY", "80") or "80")
            im.save(buf, format="JPEG", quality=quality, optimize=True)
            out_bytes = buf.getvalue()
        except Exception:
            pass

        with open(final_abs, "wb") as out:
            out.write(out_bytes)

        if inline_base64:
            try:
                from PIL import Image

                im2 = Image.open(BytesIO(out_bytes))
                if im2.mode not in ("RGB", "L"):
                    im2 = im2.convert("RGB")
                prev_dim = int(os.getenv("INLINE_PREVIEW_MAX_DIM", "420") or "420")
                if max(im2.size) > prev_dim:
                    im2.thumbnail((prev_dim, prev_dim), Image.Resampling.LANCZOS)
                buf2 = BytesIO()
                prev_q = int(os.getenv("INLINE_PREVIEW_JPEG_QUALITY", "60") or "60")
                im2.save(buf2, format="JPEG", quality=prev_q, optimize=True)
                encoded = base64.b64encode(buf2.getvalue()).decode("utf-8")
                b64 = f"data:image/jpeg;base64,{encoded}"
            except Exception:
                b64 = None

        return final_rel, b64
    finally:
        try:
            if temp_abs and os.path.exists(temp_abs):
                os.remove(temp_abs)
        except Exception:
            pass

