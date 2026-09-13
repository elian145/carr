from __future__ import annotations

import base64
import os

from PIL.Image import DecompressionBombError

from ..time_utils import utcnow
from .celery_app import celery_app


def _process_image_path(
    *,
    temp_abs: str,
    original_filename: str,
    inline_base64: bool,
    skip_blur: bool,
    owner_public_id: str | None = None,
) -> dict:
    """
    Process an image already saved to disk at temp_abs.
    Returns {rel_path, base64?}.
    """
    from kk.media_processing import (
        DecompressionBombRejected,
        blur_image_bytes,
        persist_jpeg_bytes,
    )
    from kk.security import generate_secure_filename

    filename = generate_secure_filename(original_filename or "upload.jpg")
    timestamp = utcnow().strftime("%Y%m%d_%H%M%S_%f")

    base_name = os.path.splitext(filename)[0]
    final_filename = f"processed_{timestamp}_{base_name}.jpg"

    with open(temp_abs, "rb") as fp:
        raw_bytes = fp.read()

    # Optional: blur plates (fallback to original on any failure).
    out_bytes = blur_image_bytes(raw_bytes, ".jpg", skip_blur=skip_blur)

    # Downscale/compress
    #
    # L-03: normalize EXIF orientation into the pixels (ImageOps.exif_transpose)
    # *before* stripping metadata, then save with exif=b"" so no source EXIF --
    # GPS, camera/device model, timestamps, or the orientation tag itself -- is
    # ever written to the stored JPEG. exif_transpose() is a no-op when there is
    # no orientation tag (e.g. the plate-blur/OpenCV branch above already
    # produces EXIF-free bytes), so it is safe to always apply here regardless
    # of which branch of blur_image_bytes() produced ``out_bytes``. Kept
    # consistent with kk/media_processing.py::process_and_store_image(), which
    # this function duplicates.
    #
    # M-06 follow-up: this duplicate downscale step must reject a
    # decompression-bomb image the same way process_and_store_image() does --
    # PIL.Image.DecompressionBombError must never be swallowed here, because
    # doing so would leave ``out_bytes`` as the original, un-downscaled,
    # bomb-flagged bytes, which the unconditional persist_jpeg_bytes() call
    # right below would then persist to R2/local disk.
    try:
        from io import BytesIO

        from PIL import Image, ImageOps

        im = Image.open(BytesIO(out_bytes))
        im = ImageOps.exif_transpose(im)
        if im.mode not in ("RGB", "L"):
            im = im.convert("RGB")
        max_dim = int(os.getenv("UPLOAD_IMAGE_MAX_DIM", "1200") or "1200")
        if max(im.size) > max_dim:
            im.thumbnail((max_dim, max_dim), Image.Resampling.LANCZOS)

        buf = BytesIO()
        quality = int(os.getenv("UPLOAD_IMAGE_JPEG_QUALITY", "80") or "80")
        im.save(buf, format="JPEG", quality=quality, optimize=True, exif=b"")
        out_bytes = buf.getvalue()
    except DecompressionBombError as e:
        # M-06 follow-up: reuse the exact same rejection mechanism as
        # process_and_store_image() -- raise, do not fall through. This
        # propagates out of _process_image_path() (and out of the Celery
        # task body) before persist_jpeg_bytes() is ever reached; the
        # caller's `finally:` temp-file cleanup still runs regardless.
        raise DecompressionBombRejected(
            "_process_image_path: image rejected by decompression-bomb guard"
        ) from e
    except Exception:
        pass

    final_rel = persist_jpeg_bytes(
        out_bytes,
        object_filename=final_filename,
        owner_public_id=owner_public_id,
    )

    b64 = None
    if inline_base64:
        try:
            # L-03: same orientation-normalize-then-strip-EXIF guarantee as the
            # main save above (kept consistent with media_processing.py).
            from io import BytesIO

            from PIL import Image, ImageOps

            im2 = Image.open(BytesIO(out_bytes))
            im2 = ImageOps.exif_transpose(im2)
            if im2.mode not in ("RGB", "L"):
                im2 = im2.convert("RGB")
            prev_dim = int(os.getenv("INLINE_PREVIEW_MAX_DIM", "420") or "420")
            if max(im2.size) > prev_dim:
                im2.thumbnail((prev_dim, prev_dim), Image.Resampling.LANCZOS)
            buf2 = BytesIO()
            prev_q = int(os.getenv("INLINE_PREVIEW_JPEG_QUALITY", "60") or "60")
            im2.save(buf2, format="JPEG", quality=prev_q, optimize=True, exif=b"")
            encoded = base64.b64encode(buf2.getvalue()).decode("utf-8")
            b64 = f"data:image/jpeg;base64,{encoded}"
        except Exception:
            b64 = None

    return {"rel_path": final_rel, "base64": b64}


@celery_app.task(bind=True, name="kk.process_car_image_file")
def process_car_image_file(
    self,
    temp_abs: str,
    original_filename: str,
    inline_base64: bool = False,
    skip_blur: bool = False,
    owner_public_id: str | None = None,
):
    """
    Process a car image under the shared Celery Flask app context (P-06).

    ``owner_public_id`` is embedded in task meta/result so job polling can authorize
    even if the enqueue-time ownership registry is unavailable.
    """
    owner = (owner_public_id or "").strip() or None
    if owner:
        try:
            self.update_state(state="STARTED", meta={"owner_public_id": owner})
        except Exception:
            pass

    try:
        res = _process_image_path(
            temp_abs=temp_abs,
            original_filename=original_filename,
            inline_base64=bool(inline_base64),
            skip_blur=bool(skip_blur),
            owner_public_id=owner,
        )
        out = {"ok": True, **res}
        if owner:
            out["owner_public_id"] = owner
        return out
    finally:
        try:
            if temp_abs and os.path.isfile(temp_abs):
                os.remove(temp_abs)
        except Exception:
            pass
