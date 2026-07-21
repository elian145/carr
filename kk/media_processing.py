from __future__ import annotations

import base64
import logging
import os
from io import BytesIO
from typing import Tuple

from flask import current_app

from .config import get_app_env
from .security import generate_secure_filename
from .time_utils import utcnow

logger = logging.getLogger(__name__)


def _r2_configured() -> bool:
    """
    True if Cloudflare R2 (or another S3-compatible backend) is configured.

    We reuse the same config keys as the media blueprint:
    - R2_ACCOUNT_ID
    - R2_BUCKET_NAME
    - R2_ACCESS_KEY_ID
    - R2_SECRET_ACCESS_KEY
    """
    c = current_app.config
    return bool(
        c.get("R2_ACCOUNT_ID")
        and c.get("R2_BUCKET_NAME")
        and c.get("R2_ACCESS_KEY_ID")
        and c.get("R2_SECRET_ACCESS_KEY")
    )


def _r2_public_base() -> str:
    return (current_app.config.get("R2_PUBLIC_URL") or "").strip().rstrip("/")


def _allow_local_upload_fallback() -> bool:
    """
    Whether writing listing images to local disk is allowed.

    Dev/test: always. Production: only with persistent UPLOAD_FOLDER or
    ALLOW_EPHEMERAL_UPLOADS (emergency escape hatch).
    """
    env = get_app_env()
    if env in ("development", "testing", "test"):
        return True
    if (os.environ.get("ALLOW_EPHEMERAL_UPLOADS") or "").strip().lower() in (
        "1",
        "true",
        "yes",
        "on",
    ):
        return True
    from .config import _persistent_upload_folder_configured

    return _persistent_upload_folder_configured()


def persist_jpeg_bytes(out_bytes: bytes, *, object_filename: str) -> str:
    """
    Persist optimized JPEG bytes to R2 (preferred) or local UPLOAD_FOLDER.

    Returns a public HTTPS URL when R2_PUBLIC_URL is set, otherwise a relative
    ``uploads/car_photos/...`` path for local/static serving.
    """
    final_rel_local = os.path.join("uploads", "car_photos", object_filename).replace(
        "\\", "/"
    )

    if _r2_configured():
        public_base = _r2_public_base()
        if not public_base and not _allow_local_upload_fallback():
            raise RuntimeError(
                "R2 is configured but R2_PUBLIC_URL is missing; "
                "refusing to store non-public object keys in production."
            )
        try:
            client = _r2_client()
            bucket = current_app.config["R2_BUCKET_NAME"]
            key = f"car_photos/{object_filename}"
            client.put_object(
                Bucket=bucket,
                Key=key,
                Body=out_bytes,
                ContentType="image/jpeg",
            )
            if public_base:
                return f"{public_base}/{key}"
            return key
        except Exception:
            logger.exception("R2 image upload failed for %s", object_filename)
            if not _allow_local_upload_fallback():
                raise
            # Dev/test or persistent disk: fall through to local disk.

    if not _allow_local_upload_fallback():
        raise RuntimeError(
            "Local image persistence is not allowed in this environment. "
            "Configure R2 (with R2_PUBLIC_URL) or set UPLOAD_FOLDER to an "
            "absolute path on a persistent volume."
        )

    upload_root = (current_app.config.get("UPLOAD_FOLDER") or "").strip()
    if not upload_root:
        raise RuntimeError("UPLOAD_FOLDER is not configured")
    final_abs = os.path.join(upload_root, "car_photos", object_filename)
    os.makedirs(os.path.dirname(final_abs), exist_ok=True)
    with open(final_abs, "wb") as out:
        out.write(out_bytes)
    return final_rel_local


def _r2_client():
    """Return an S3-compatible client for Cloudflare R2."""
    import boto3
    from botocore.config import Config

    c = current_app.config
    account_id = c["R2_ACCOUNT_ID"]
    region = (os.environ.get("R2_REGION") or "auto").strip() or "auto"
    endpoint = f"https://{account_id}.r2.cloudflarestorage.com"
    return boto3.client(
        "s3",
        region_name=region,
        endpoint_url=endpoint,
        aws_access_key_id=c["R2_ACCESS_KEY_ID"],
        aws_secret_access_key=c["R2_SECRET_ACCESS_KEY"],
        config=Config(signature_version="s3v4"),
    )


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

        # Persist the optimized bytes: prefer Cloudflare R2 when configured,
        # otherwise fall back to local filesystem under /static/uploads.
        final_rel = persist_jpeg_bytes(out_bytes, object_filename=final_filename)

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

