from __future__ import annotations

import base64
import os
import tempfile
from uuid import uuid4

from PIL.Image import DecompressionBombError

from ..time_utils import utcnow
from .celery_app import celery_app


def _process_image_path(
    *,
    temp_abs: str | None,
    original_filename: str,
    inline_base64: bool,
    skip_blur: bool,
    owner_public_id: str | None = None,
    source_r2_key: str | None = None,
) -> dict:
    """
    Process an image already saved to disk at temp_abs, OR staged in R2
    under source_r2_key. Returns {rel_path, base64?}.

    ``source_r2_key``: OOM-fix follow-up -- when the enqueuing web process
    and this Celery worker run as *separate* Render services (production:
    ``carr`` vs ``carr-worker-fra``), a local path written by the web
    process is not visible here; Render never shares a local disk across
    services. In that case the enqueuer stages the original upload to a
    short-lived R2 object instead
    (``kk.media_processing.stage_upload_for_async_job``), and this downloads
    it to a fresh path on THIS worker's own disk before processing. The
    downloaded copy and the R2 staging object are both removed before this
    function returns or raises -- never left behind either way. When
    ``source_r2_key`` is not given, behavior is unchanged: ``temp_abs`` must
    already exist on this machine (same-process/dev/test case).
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

    downloaded_path: str | None = None
    try:
        source_path = temp_abs
        if source_r2_key:
            from flask import current_app

            from kk.r2_ops import r2_get_file

            upload_root = (
                (current_app.config.get("UPLOAD_FOLDER") or "").strip()
                or tempfile.gettempdir()
            )
            tmp_dir = os.path.join(upload_root, "temp")
            os.makedirs(tmp_dir, exist_ok=True)
            downloaded_path = os.path.join(
                tmp_dir, f"celery_r2_{timestamp}_{uuid4().hex}_{filename}"
            )
            r2_get_file(key=source_r2_key, dest_path=downloaded_path)
            source_path = downloaded_path

        if not source_path:
            raise RuntimeError(
                "_process_image_path: no source provided (temp_abs or source_r2_key)"
            )

        return _process_image_bytes_from_path(
            source_path=source_path,
            final_filename=final_filename,
            inline_base64=inline_base64,
            skip_blur=skip_blur,
            owner_public_id=owner_public_id,
        )
    finally:
        if downloaded_path:
            try:
                if os.path.isfile(downloaded_path):
                    os.remove(downloaded_path)
            except OSError:
                pass
        if source_r2_key:
            try:
                from kk.r2_ops import r2_delete_object

                r2_delete_object(key=source_r2_key)
            except Exception:
                pass


def _process_image_bytes_from_path(
    *,
    source_path: str,
    final_filename: str,
    inline_base64: bool,
    skip_blur: bool,
    owner_public_id: str | None = None,
) -> dict:
    """The actual decode/blur/downscale/encode/persist pipeline, factored
    out of ``_process_image_path`` so the R2-staging download/cleanup
    wrapper above stays simple. Behavior is byte-for-byte identical to the
    pre-existing inline implementation."""
    from kk.media_processing import (
        DecompressionBombRejected,
        blur_image_bytes,
        persist_jpeg_bytes,
    )

    with open(source_path, "rb") as fp:
        raw_bytes = fp.read()

    # Optional: blur plates (fallback to original on any failure, unless
    # M-08's PLATE_BLUR_REQUIRE_SUCCESS=1 is set -- in that case
    # blur_image_bytes() raises kk.media_processing.PlateBlurRequiredRejected
    # instead of returning unconfirmed bytes. It is a plain env var read
    # inside blur_image_bytes() itself, so this Celery worker process obeys
    # the exact same policy as the synchronous request path with no extra
    # wiring here; the raise propagates out of this function (and out of
    # the `process_car_image_file` task below) before persist_jpeg_bytes()
    # is ever reached, so a rejected image is never persisted via the async
    # path either -- mirroring the M-06 DecompressionBombRejected handling
    # immediately below.
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
        # Quality-audit benchmark: kept consistent with
        # media_processing.py::process_and_store_image() -- raised from 1200
        # to 2048 (matches Flutter's own image_picker cap, see that
        # function's comment for the measured PSNR/SSIM/file-size numbers).
        max_dim = int(os.getenv("UPLOAD_IMAGE_MAX_DIM", "2048") or "2048")
        if max(im.size) > max_dim:
            im.thumbnail((max_dim, max_dim), Image.Resampling.LANCZOS)

        buf = BytesIO()
        # Quality-audit fix: kept consistent with
        # media_processing.py::process_and_store_image(), which this
        # function duplicates -- same higher default quality + chroma
        # preservation, for the same reason (requirements D and F).
        quality = int(os.getenv("UPLOAD_IMAGE_JPEG_QUALITY", "92") or "92")
        im.save(
            buf,
            format="JPEG",
            quality=quality,
            optimize=True,
            exif=b"",
            subsampling=0,  # 4:4:4 -- preserve chroma/detail (requirement D)
        )
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
    temp_abs: str | None,
    original_filename: str,
    inline_base64: bool = False,
    skip_blur: bool = False,
    owner_public_id: str | None = None,
    source_r2_key: str | None = None,
):
    """
    Process a car image under the shared Celery Flask app context (P-06).

    ``owner_public_id`` is embedded in task meta/result so job polling can authorize
    even if the enqueue-time ownership registry is unavailable.

    ``source_r2_key``: see ``_process_image_path``'s docstring. When set,
    ``temp_abs`` is expected to be ``None`` (or otherwise not present on
    this machine) -- this task's own cleanup below only ever touches
    ``temp_abs``, so it is a harmless no-op in that case; the R2 staging
    object and the worker's own downloaded copy are cleaned up inside
    ``_process_image_path`` itself, success or failure.
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
            source_r2_key=source_r2_key,
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


@celery_app.task(name="kk.cleanup_stale_image_staging_objects")
def cleanup_stale_image_staging_objects():
    """Backstop sweep for abandoned R2 async-image-staging objects.

    ``kk.media_processing.stage_upload_for_async_job`` stages original
    upload bytes under ``car_photos/_staging/`` in R2 so a Celery worker on
    a separate Render service/disk can fetch them (see that function's
    docstring). The normal path always deletes the staging object itself,
    in ``_process_image_path``'s ``finally`` block, once the job finishes
    (success or failure). This task only catches the rare case a job is
    lost entirely (worker crash, broker outage, task never picked up) and
    its staging object would otherwise linger in R2 forever -- registered
    on the existing Celery Beat schedule (see ``kk/tasks/celery_app.py``),
    same pattern as ``clear_expired_featured_listings``.

    A generous 6-hour age threshold is used: real jobs normally complete
    within seconds to a couple of minutes, so anything still present after
    6 hours is safely assumed abandoned, not merely slow.
    """
    from flask import current_app

    from kk.media_processing import _ASYNC_STAGING_KEY_PREFIX, _r2_configured

    if not _r2_configured():
        return {"ok": True, "deleted": 0, "skipped": "r2_not_configured"}

    from kk.r2_ops import r2_cleanup_stale_staging

    deleted = r2_cleanup_stale_staging(
        prefix=_ASYNC_STAGING_KEY_PREFIX,
        older_than_seconds=6 * 3600,
    )
    if deleted:
        current_app.logger.info(
            "cleanup_stale_image_staging_objects: deleted %d stale staging object(s)",
            deleted,
        )
    return {"ok": True, "deleted": deleted}
