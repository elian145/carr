from __future__ import annotations

import base64
import hashlib
import logging
import os
import tempfile
from uuid import uuid4

from ..media_processing import (
    DecompressionBombRejected,
    ImageNormalizationFailed,
    PlateBlurRequiredRejected,
)
from ..time_utils import utcnow
from .celery_app import celery_app

logger = logging.getLogger(__name__)


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
        PlateBlurStatus,
        blur_image_bytes_with_status,
        normalize_to_canonical_jpeg,
        persist_jpeg_bytes,
    )

    with open(source_path, "rb") as fp:
        raw_bytes = fp.read()

    # TEMPORARY DEBUG TRACE (plate-blur real-device investigation -- safe to
    # delete once diagnosis is complete). Never logs bytes, only a digest.
    _trace_source_sha256 = hashlib.sha256(raw_bytes).hexdigest()

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
    out_bytes, _trace_blur_status = blur_image_bytes_with_status(
        raw_bytes, ".jpg", skip_blur=skip_blur
    )
    # TEMPORARY DEBUG: deterministic proof of whether the plate-blur
    # detector actually ran and produced a blurred result, independent of
    # what skip_blur was merely *requested* as.
    _trace_plate_blur_applied = _trace_blur_status == PlateBlurStatus.BLURRED_SUCCESS

    # Downscale/compress + canonicalize (2026 real-device fix: HEIC-
    # mislabeled-as-.jpg root cause). This now calls the SAME
    # `normalize_to_canonical_jpeg()` helper as
    # `kk/media_processing.py::process_and_store_image()`, instead of a
    # duplicated inline block that used to silently swallow ANY decode
    # failure (bare `except Exception: pass`) and fall through to
    # persisting the original, un-normalized ``out_bytes`` -- which is
    # exactly how raw HEIC bytes (produced by ``blur_image_bytes_with_status
    # ()``'s SKIPPED branch returning the untouched source when
    # ``skip_blur=True``) ended up persisted to R2 under a `.jpg`
    # filename/Content-Type on a real production listing.
    #
    # `DecompressionBombRejected` (M-06) and `ImageNormalizationFailed`
    # (2026 fix) are both hard failures that propagate out of this
    # function, out of `_process_image_path()`, and out of the Celery task
    # body (see `process_car_image_file`'s exception handling, which
    # transitions the media-readiness item to the terminal ``failed``
    # status for both -- never self-attaches unconfirmed bytes).
    out_bytes = normalize_to_canonical_jpeg(out_bytes)

    # TEMPORARY DEBUG TRACE: hash of the final bytes actually persisted
    # (post blur/resize/re-encode). A mismatch vs. _trace_source_sha256 is
    # EXPECTED and fine on its own (resize/re-encode always changes bytes)
    # -- the meaningful signal is _trace_plate_blur_applied above.
    _trace_processed_sha256 = hashlib.sha256(out_bytes).hexdigest()

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

    return {
        "rel_path": final_rel,
        "base64": b64,
        # TEMPORARY DEBUG TRACE fields (plate-blur real-device investigation
        # -- safe to remove once diagnosis is complete). Never contain
        # bytes, only digests/paths/booleans.
        "_trace_source_path": source_path,
        "_trace_source_sha256": _trace_source_sha256,
        "_trace_processed_sha256": _trace_processed_sha256,
        "_trace_plate_blur_applied": _trace_plate_blur_applied,
    }


@celery_app.task(bind=True, name="kk.process_car_image_file")
def process_car_image_file(
    self,
    temp_abs: str | None,
    original_filename: str,
    inline_base64: bool = False,
    skip_blur: bool = False,
    owner_public_id: str | None = None,
    source_r2_key: str | None = None,
    car_id: int | None = None,
    kind: str | None = None,
    client_media_id: str | None = None,
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

    Media-readiness (``car_id``/``kind``/``client_media_id``, all optional):
    when present, this task performs the FULL Phase B lifecycle for its
    manifest item itself -- no further Flutter call is required for
    correctness. On success it self-attaches the processed image (creating
    the ``CarImage`` row) and transitions the manifest item to
    ``"attached"``. On a PERMANENT rejection (``DecompressionBombRejected``/
    ``PlateBlurRequiredRejected``/``ImageNormalizationFailed`` -- all three
    deterministic given these exact bytes; retrying identical input cannot
    succeed) it transitions the item to ``"failed"``. Any OTHER exception
    (network/R2/broker/OOM/transient processing failure) is deliberately
    NOT treated as terminal -- it propagates, Celery's at-least-once
    redelivery may retry it, and the manifest item is correctly left at
    ``"processing"`` in the meantime (see kk/media_readiness.py's module
    docstring for the full rule).

    ``ImageNormalizationFailed`` (2026 real-device fix) is the hard-failure
    counterpart of the bug that let raw HEIC bytes self-attach as a
    `.jpg`-named ``CarImage`` on a real production listing: if the source
    bytes genuinely cannot be decoded/normalized into JPEG at all (not even
    after the module-level eager HEIC-opener registration -- e.g. still
    missing the ``pillow_heif`` dependency, or a truly corrupt upload),
    this task now fails the item instead of silently self-attaching
    unrenderable bytes.
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

        # TEMPORARY DEBUG TRACE (plate-blur real-device investigation --
        # safe to delete once diagnosis is complete). Never logs bytes,
        # only digests/paths/booleans; no signed URLs or credentials.
        try:
            logger.warning(
                "[BLUR TRACE SERVER] processing client_media_id=%s skip_blur=%s "
                "source_sha256=%s processed_sha256=%s source_key=%s processed_key=%s "
                "plate_blur_applied=%s",
                client_media_id,
                bool(skip_blur),
                res.get("_trace_source_sha256"),
                res.get("_trace_processed_sha256"),
                res.get("_trace_source_path"),
                res.get("rel_path"),
                res.get("_trace_plate_blur_applied"),
            )
        except Exception:
            pass

        if car_id and client_media_id:
            # Lazy imports: kk.routes.media imports THIS module at module
            # load time, so importing it back here at module scope would
            # be circular -- deferring to call time (well after both
            # modules have finished loading) breaks the cycle.
            from ..media_readiness import transition_media_item_terminal
            from ..routes.media import attach_processed_car_image

            transition_media_item_terminal(
                car_id=int(car_id),
                client_media_id=client_media_id,
                to_status="attached",
                attach_fn=lambda car: attach_processed_car_image(
                    car,
                    kind=kind or "listing",
                    rel_path=res["rel_path"],
                    source_media_id=client_media_id,
                    # TEMPORARY DEBUG TRACE args -- see attach_processed_car_image()
                    # docstring; safe to remove once diagnosis is complete.
                    _trace_skip_blur=bool(skip_blur),
                    _trace_processed_sha256=res.get("_trace_processed_sha256"),
                ),
            )
        return out
    except (
        DecompressionBombRejected,
        PlateBlurRequiredRejected,
        ImageNormalizationFailed,
    ):
        if car_id and client_media_id:
            try:
                from ..media_readiness import transition_media_item_terminal

                transition_media_item_terminal(
                    car_id=int(car_id),
                    client_media_id=client_media_id,
                    to_status="failed",
                )
            except Exception:
                logger.exception(
                    "process_car_image_file: terminal-fail transition failed "
                    "(car_id=%s client_media_id=%s)",
                    car_id,
                    client_media_id,
                )
        raise
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
