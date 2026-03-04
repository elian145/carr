from __future__ import annotations

import base64
import os

from celery import shared_task

from ..time_utils import utcnow

def _process_image_path(
    *,
    temp_abs: str,
    original_filename: str,
    inline_base64: bool,
    skip_blur: bool,
) -> dict:
    """
    Process an image already saved to disk at temp_abs.
    Returns {rel_path, base64?}.
    """
    from flask import current_app

    from kk.security import generate_secure_filename

    filename = generate_secure_filename(original_filename or "upload.jpg")
    timestamp = utcnow().strftime("%Y%m%d_%H%M%S_%f")

    base_name = os.path.splitext(filename)[0]
    final_filename = f"processed_{timestamp}_{base_name}.jpg"
    final_rel = os.path.join("uploads", "car_photos", final_filename).replace("\\", "/")
    final_abs = os.path.join(current_app.root_path, "static", final_rel)
    os.makedirs(os.path.dirname(final_abs), exist_ok=True)

    with open(temp_abs, "rb") as fp:
        raw_bytes = fp.read()

    # Optional: blur plates (fallback to original on any failure).
    out_bytes = raw_bytes
    try:
        enabled = (os.getenv("PLATE_BLUR_ENABLED", "1").strip() != "0")
        if enabled and not skip_blur:
            from kk.license_plate_blur import blur_license_plates, get_plate_detector

            detector = get_plate_detector()
            if detector.is_configured():
                expand = float(os.getenv("PLATE_BLUR_EXPAND", "0") or "0")
                out_bytes, _meta = blur_license_plates(
                    image_bytes=raw_bytes,
                    output_ext=".jpg",
                    detector=detector,
                    expand_ratio=expand,
                )
    except Exception:
        out_bytes = raw_bytes

    # Downscale/compress
    try:
        from io import BytesIO

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

    b64 = None
    if inline_base64:
        try:
            from io import BytesIO

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

    return {"rel_path": final_rel, "base64": b64}


@shared_task(bind=True, name="kk.process_car_image_file")
def process_car_image_file(self, temp_abs: str, original_filename: str, inline_base64: bool = False, skip_blur: bool = False):
    """
    Celery task wrapper that creates a Flask app context to access config/root paths.
    """
    from kk.app_factory import create_app

    app, *_ = create_app()
    with app.app_context():
        try:
            res = _process_image_path(
                temp_abs=temp_abs,
                original_filename=original_filename,
                inline_base64=bool(inline_base64),
                skip_blur=bool(skip_blur),
            )
            return {"ok": True, **res}
        finally:
            try:
                if temp_abs and os.path.isfile(temp_abs):
                    os.remove(temp_abs)
            except Exception:
                pass

