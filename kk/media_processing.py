from __future__ import annotations

import base64
import hashlib
import hmac
import logging
import os
import secrets
import tempfile
from dataclasses import dataclass
from enum import Enum
from io import BytesIO
from typing import Tuple
from uuid import uuid4

from flask import current_app
from PIL.Image import DecompressionBombError

from .config import get_app_env
from .security import generate_secure_filename
from .time_utils import utcnow

logger = logging.getLogger(__name__)


class DecompressionBombRejected(Exception):
    """Raised when Pillow's built-in decompression-bomb guard
    (``PIL.Image.DecompressionBombError``) rejects an image.

    M-06: callers (route handlers) must treat this as a hard rejection of the
    individual file -- the original, bomb-flagged bytes must never be
    persisted (R2/local disk) or returned to a caller as if they had been
    processed normally. The underlying PIL exception text is intentionally
    not attached to any API-facing message; callers should surface a
    generic, non-leaking rejection message instead.
    """


class PlateBlurStatus(str, Enum):
    """M-08: definitive outcome of one plate-blur attempt.

    This is the small internal "result object" the persistence layer
    (``process_and_store_image()`` / ``kk.tasks.image_tasks._process_image_path()``)
    uses to distinguish a confirmed-safe outcome from every kind of failure,
    instead of inferring success/failure purely from exceptions or from the
    presence/absence of a swallowed error.
    """

    BLURRED_SUCCESS = "blurred_success"  # plate(s) detected and blurred
    NO_PLATES = "no_plates"  # detection ran successfully; genuinely no plates found
    SKIPPED = "skipped"  # skip_blur honored (fail-open mode only; see plate_blur_require_success_enabled())
    NOT_CONFIGURED = "not_configured"  # PLATE_BLUR_ENABLED=0, or detector missing ROBOFLOW_API_KEY/project/version
    DETECTION_FAILED = "detection_failed"  # Roboflow request failed (network/API/timeout/quota/bad response)
    PROCESSING_FAILED = "processing_failed"  # image could not be decoded, or detected boxes were unusable
    ENCODING_FAILED = "encoding_failed"  # re-encoding the blurred image failed
    OTHER_FAILURE = "other_failure"  # any unexpected/ambiguous outcome -- fails closed, never treated as safe


# M-08: the ONLY statuses that may ever be persisted/returned when
# PLATE_BLUR_REQUIRE_SUCCESS=1 is enabled. Every other status --
# including any future/unknown status string this process doesn't
# recognize -- is rejected. See `_map_blur_meta_status()`.
_PLATE_BLUR_CONFIRMED_SAFE = frozenset(
    {PlateBlurStatus.BLURRED_SUCCESS, PlateBlurStatus.NO_PLATES}
)


@dataclass(frozen=True)
class PlateBlurOutcome:
    """Result of one `_run_plate_blur()` attempt."""

    status: PlateBlurStatus
    out_bytes: bytes
    detail: str = ""  # short, non-secret, internal status token -- server-log-only, never client-facing


class PlateBlurRequiredRejected(Exception):
    """M-08: raised when ``PLATE_BLUR_REQUIRE_SUCCESS`` is enabled and the
    plate-blur pipeline could not confirm ``BLURRED_SUCCESS`` or ``NO_PLATES``.

    Callers (route handlers) must treat this as a hard rejection of the
    individual file -- the original, unconfirmed bytes must never be
    persisted (R2/local disk) or returned to a caller as if nothing had gone
    wrong. ``status``/``detail`` are internal, non-secret tokens intended for
    server-side logging only; callers should surface a generic, non-leaking
    rejection message instead (mirroring the ``DecompressionBombRejected``
    convention above).
    """

    def __init__(self, status: PlateBlurStatus, detail: str = ""):
        self.status = status
        self.detail = detail
        super().__init__(
            f"plate blur required but not confirmed safe (status={status.value})"
        )


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


# OOM-fix follow-up (moving Sell photo prestage onto the Celery async
# image-processing pipeline): objects staged here are the *original*,
# not-yet-processed upload bytes, kept only long enough for
# ``kk.tasks.image_tasks.process_car_image_file`` to download and consume
# them. Deliberately namespaced away from real listing photos
# (``car_photos/<owner_tag>/...``) so they are never mistaken for one and so
# the periodic backstop sweep (``kk.tasks.image_tasks.
# cleanup_stale_image_staging_objects``) can target them precisely by prefix.
_ASYNC_STAGING_KEY_PREFIX = "car_photos/_staging/"


def stage_upload_for_async_job(
    file_storage, *, filename_hint: str, subdir: str = "temp"
) -> tuple[str | None, str | None]:
    """Save one uploaded file so the async Celery image-processing task
    (``kk.tasks.image_tasks.process_car_image_file``) can read it.

    Returns ``(temp_abs, source_r2_key)`` -- exactly one of the two is
    non-``None``.

    ``carr-worker-fra`` (the Celery worker) runs as a *separate* Render
    service from the web process handling this request. Render never shares
    a local disk across services or instances (see
    ``kk/docs/UPLOAD_PERSISTENCE.md`` and Render's own disk docs), so a path
    written to this process's own disk is not readable by that worker. When
    R2 is configured (the production default -- see
    ``kk/docs/UPLOAD_PERSISTENCE.md``), this uploads the file to a
    short-lived R2 staging key instead and returns that key as
    ``source_r2_key``, removing the local temp copy immediately since it is
    no longer needed once the bytes are durably staged in R2. When R2 is not
    configured (dev/test, or a single-process deployment with no separate
    worker service), this returns a local ``temp_abs`` path exactly as
    before -- unchanged behavior for that case, since same-machine execution
    makes a local path readable by whatever process runs the Celery task.

    The upload is always streamed via ``FileStorage.save()`` -- this
    function never reads the file fully into this process's memory, in
    either branch.
    """
    upload_root = (
        (current_app.config.get("UPLOAD_FOLDER") or "").strip()
        or tempfile.gettempdir()
    )
    tmp_dir = os.path.join(upload_root, subdir)
    os.makedirs(tmp_dir, exist_ok=True)
    ts = utcnow().strftime("%Y%m%d_%H%M%S_%f")
    temp_abs = os.path.join(tmp_dir, f"celery_{ts}_{uuid4().hex}_{filename_hint}")
    file_storage.save(temp_abs)

    if not _r2_configured():
        return temp_abs, None

    ext = os.path.splitext(filename_hint)[1].lower() or ".jpg"
    staging_key = f"{_ASYNC_STAGING_KEY_PREFIX}{secrets.token_hex(16)}{ext}"
    try:
        from .r2_ops import r2_put_file

        r2_put_file(
            key=staging_key,
            file_path=temp_abs,
            content_type="application/octet-stream",
        )
    finally:
        # The local copy is redundant once staged in R2 -- and would
        # otherwise never be cleaned up on this machine, since only the
        # worker (on a different machine) knows the job finished.
        try:
            os.remove(temp_abs)
        except OSError:
            pass
    return None, staging_key


def media_owner_tag(owner_public_id: str | None) -> str | None:
    """Key prefix that marks a stored object as belonging to one seller.

    Photos are stored before the listing row exists, so ``/images/attach`` has
    no CarImage row to check ownership against. The prefix is an HMAC of the
    seller's public id, so a scraper who sees someone else's photo URL cannot
    produce a URL that carries their own prefix.
    """
    owner = (owner_public_id or "").strip()
    if not owner:
        return None
    secret = (current_app.config.get("SECRET_KEY") or "").encode("utf-8")
    if not secret:
        return None
    digest = hmac.new(secret, f"media-owner:{owner}".encode("utf-8"), hashlib.sha256)
    return f"u{digest.hexdigest()[:16]}"


def media_key_owner_prefix_matches(key: str, owner_public_id: str | None) -> bool:
    """True when ``key`` carries the owner prefix for ``owner_public_id``."""
    expected = media_owner_tag(owner_public_id)
    if not expected:
        return False
    parts = (key or "").strip("/").split("/")
    if len(parts) < 3:
        return False
    return hmac.compare_digest(parts[1], expected)


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


def persist_jpeg_bytes(
    out_bytes: bytes,
    *,
    object_filename: str,
    owner_public_id: str | None = None,
) -> str:
    """
    Persist optimized JPEG bytes to R2 (preferred) or local UPLOAD_FOLDER.

    Returns a public HTTPS URL when R2_PUBLIC_URL is set, otherwise a relative
    ``uploads/car_photos/...`` path for local/static serving.

    ``owner_public_id`` adds an owner prefix to the R2 key so the seller can
    attach the object to a listing they create afterwards.
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
            from .r2_ops import r2_put_bytes

            owner_tag = media_owner_tag(owner_public_id)
            bucket_key = (
                f"car_photos/{owner_tag}/{object_filename}"
                if owner_tag
                else f"car_photos/{object_filename}"
            )
            r2_put_bytes(
                key=bucket_key,
                body=out_bytes,
                content_type="image/jpeg",
            )
            if public_base:
                return f"{public_base}/{bucket_key}"
            return bucket_key
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


def heic_to_jpeg(raw_bytes: bytes) -> Tuple[bytes, bool]:
    """Convert HEIC/HEIF bytes to JPEG. Returns (jpeg_bytes, True) on success.

    L-03: orientation is normalized into the pixels (``ImageOps.exif_transpose``)
    before saving, and the JPEG is saved with ``exif=b""`` so no source EXIF
    (GPS, camera/device model, timestamps, orientation tag) survives the
    HEIC->JPEG conversion.
    """
    try:
        import pillow_heif  # type: ignore  # noqa: F401
        from PIL import Image, ImageOps

        pillow_heif.register_heif_opener()
        im = Image.open(BytesIO(raw_bytes))
        im = ImageOps.exif_transpose(im)
        if im.mode not in ("RGB", "L"):
            im = im.convert("RGB")
        out = BytesIO()
        im.save(out, format="JPEG", quality=92, optimize=True, exif=b"")
        return out.getvalue(), True
    except DecompressionBombError as e:
        # M-06: Pillow's own decompression-bomb guard tripped -- do not
        # swallow this into the generic fallback below, which would silently
        # return the original, unprocessed, bomb-flagged bytes as if nothing
        # had gone wrong.
        raise DecompressionBombRejected(
            "heic_to_jpeg: image rejected by decompression-bomb guard"
        ) from e
    except Exception:
        return raw_bytes, False


def plate_blur_require_success_enabled() -> bool:
    """
    M-08: whether a listing photo must be confirmed ``BLURRED_SUCCESS`` or
    ``NO_PLATES`` before it may be persisted or returned; every other
    outcome (missing/unconfigured Roboflow key, Roboflow network/API/
    timeout/quota failure, decode/processing/encoding failure, or any
    unrecognized/ambiguous status) is a hard rejection instead of the
    original fail-open "return the unblurred bytes" behavior.

    Off (``0``) by default -- this preserves the pre-M-08 fail-open
    behavior byte-for-byte unless an operator explicitly opts in. This is a
    plain environment-variable read (checked at call time, like the sibling
    ``PLATE_BLUR_ENABLED``/``PLATE_BLUR_EXPAND``/``PLATE_BLUR_KEEP_ORIGINAL``
    flags in this module), intentionally NOT gated by ``get_app_env()``:
    unlike M-01's ``dev_debug_response_fields_enabled()`` (where the unsafe
    direction is "accidentally ON in production"), the unsafe direction here
    is the opposite -- accidentally OFF in production -- so tying this to
    APP_ENV would not add safety and would only make production silently
    diverge from the exact behavior exercised in dev/CI. Because it is a
    plain env var (not ``app.config``), a Celery worker/beat process reads
    the identical value from its own process environment, so async image
    processing (``kk/tasks/image_tasks.py``) automatically obeys the same
    policy as the synchronous request path with no separate wiring --
    operators must set it consistently across the web *and* worker services
    (see ``kk/env_example.txt``).
    """
    return (os.getenv("PLATE_BLUR_REQUIRE_SUCCESS", "0").strip().lower() in (
        "1",
        "true",
        "yes",
        "on",
    ))


# M-08: maps `blur_license_plates()`'s free-form `meta["status"]` string
# (kk/license_plate_blur.py) onto the small, definitive `PlateBlurStatus`
# enum the persistence layer gates on. Deliberately a data-only mapping --
# `license_plate_blur.py` itself is NOT modified, so its existing, already
# separately-tested detection/blur internals are untouched by M-08.
_BLUR_META_STATUS_MAP = {
    "blurred": PlateBlurStatus.BLURRED_SUCCESS,
    "no_plates": PlateBlurStatus.NO_PLATES,
    "not_configured": PlateBlurStatus.NOT_CONFIGURED,
    "detect_failed": PlateBlurStatus.DETECTION_FAILED,
    "bad_response": PlateBlurStatus.DETECTION_FAILED,
    "decode_failed": PlateBlurStatus.PROCESSING_FAILED,
    # M-08: boxes WERE detected (a plate may be present) but every candidate
    # ROI was too small to safely blur -- this is not a confirmed-safe "no
    # plates" result, so it must fail closed exactly like a processing error.
    "no_valid_rois": PlateBlurStatus.PROCESSING_FAILED,
    "opencv_missing": PlateBlurStatus.OTHER_FAILURE,
    "encode_failed": PlateBlurStatus.ENCODING_FAILED,
    "error": PlateBlurStatus.OTHER_FAILURE,
}


def _map_blur_meta_status(raw_status) -> PlateBlurStatus:
    # M-08 item 6: any status this process doesn't explicitly recognize as
    # confirmed-safe is ambiguous by definition -- fail closed, never persist.
    return _BLUR_META_STATUS_MAP.get(str(raw_status or ""), PlateBlurStatus.OTHER_FAILURE)


def _run_plate_blur(
    raw_bytes: bytes, ext: str, *, skip_requested: bool, force_attempt: bool
) -> PlateBlurOutcome:
    """
    Execute the plate-blur pipeline once and return a definitive
    ``PlateBlurOutcome`` -- the single choke point ``blur_image_bytes()``
    (and therefore every persistence path that calls it) uses to know
    whether the operation was BLURRED_SUCCESS / NO_PLATES / NOT_CONFIGURED /
    DETECTION_FAILED / PROCESSING_FAILED / ENCODING_FAILED / OTHER_FAILURE.

    ``force_attempt``: M-08 -- when the caller is enforcing
    ``PLATE_BLUR_REQUIRE_SUCCESS``, an ordinary client-controlled
    ``skip_blur=1`` request parameter must not be able to bypass the
    requirement, so detection still actually runs even if the caller asked
    to skip it. ``skip_requested`` is honored as an outright skip only when
    ``force_attempt`` is False (i.e. in the default fail-open mode), which
    preserves the exact original ``skip_blur`` product behavior for every
    deployment that has not explicitly opted into M-08 enforcement.
    """
    if skip_requested and not force_attempt:
        return PlateBlurOutcome(PlateBlurStatus.SKIPPED, raw_bytes, "skip_blur requested")

    enabled = (os.getenv("PLATE_BLUR_ENABLED", "1").strip() != "0")
    if not enabled:
        return PlateBlurOutcome(PlateBlurStatus.NOT_CONFIGURED, raw_bytes, "PLATE_BLUR_ENABLED=0")

    try:
        from .license_plate_blur import blur_license_plates, get_plate_detector

        detector = get_plate_detector()
        if not detector.is_configured():
            return PlateBlurOutcome(
                PlateBlurStatus.NOT_CONFIGURED,
                raw_bytes,
                "detector not configured (ROBOFLOW_API_KEY/project/version/endpoint)",
            )

        expand = float(os.getenv("PLATE_BLUR_EXPAND", "0") or "0")
        out_bytes, meta = blur_license_plates(
            image_bytes=raw_bytes,
            output_ext=ext,
            detector=detector,
            expand_ratio=expand,
        )
    except Exception as e:
        # M-08 item 6: anything that escapes blur_license_plates() itself
        # (it already has its own broad catch-all, so this should be rare)
        # is unknown/ambiguous -- fail closed, never conflate with a
        # confirmed "no plates" result. Log only the exception type, never
        # its message (which could echo request/network internals).
        logger.warning(
            "Plate blur pipeline raised unexpectedly (%s); treating as OTHER_FAILURE",
            type(e).__name__,
        )
        return PlateBlurOutcome(
            PlateBlurStatus.OTHER_FAILURE, raw_bytes, f"unexpected {type(e).__name__}"
        )

    status = _map_blur_meta_status(meta.get("status"))
    return PlateBlurOutcome(status, out_bytes, str(meta.get("status") or "unknown"))


def blur_image_bytes(raw_bytes: bytes, ext: str, *, skip_blur: bool = False) -> bytes:
    """Run license-plate blur on in-memory image bytes; return blurred bytes.

    M-08: when ``plate_blur_require_success_enabled()`` is False (the
    default), this preserves the original fail-open behavior byte-for-byte
    -- any detector/network/processing failure, or an explicit
    ``skip_blur=True``, returns the original bytes unchanged and never
    raises. When ``PLATE_BLUR_REQUIRE_SUCCESS=1`` is set, this instead
    raises ``PlateBlurRequiredRejected`` for any outcome other than a
    confirmed ``BLURRED_SUCCESS`` or ``NO_PLATES`` -- including
    ``skip_blur=True``, which is no longer honored as a way to bypass the
    requirement (see ``_run_plate_blur()``'s ``force_attempt`` docstring and
    ``PRODUCTION_AUDIT.md`` M-08 for the rationale).
    """
    require_success = plate_blur_require_success_enabled()
    outcome = _run_plate_blur(
        raw_bytes, ext, skip_requested=skip_blur, force_attempt=require_success
    )
    if require_success and outcome.status not in _PLATE_BLUR_CONFIRMED_SAFE:
        logger.warning(
            "M-08: rejecting upload -- plate blur not confirmed safe (status=%s, detail=%s)",
            outcome.status.value,
            outcome.detail,
        )
        raise PlateBlurRequiredRejected(outcome.status, outcome.detail)
    return outcome.out_bytes


def process_and_store_image(
    file_storage,
    inline_base64: bool,
    *,
    skip_blur: bool = False,
    owner_public_id: str | None = None,
):
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
        #
        # L-03: normalize EXIF orientation into the pixels (ImageOps.exif_transpose)
        # *before* stripping metadata, then save with exif=b"" so no source EXIF --
        # GPS, camera/device model, timestamps, or the orientation tag itself -- is
        # ever written to the stored JPEG. exif_transpose() is a no-op when there is
        # no orientation tag (e.g. the plate-blur/OpenCV branch above already
        # produces EXIF-free bytes), so it is safe to always apply here regardless
        # of which branch of blur_image_bytes() produced ``out_bytes``.
        try:
            from PIL import Image, ImageOps

            im = Image.open(BytesIO(out_bytes))
            im = ImageOps.exif_transpose(im)
            if im.mode not in ("RGB", "L"):
                im = im.convert("RGB")
            # Quality-audit benchmark (see the plate-blur image-quality report):
            # raised from 1200 to 2048 -- 2048 matches Flutter's own
            # image_picker maxWidth/maxHeight cap exactly, so most uploads
            # need NO further backend resize at all (avoiding a second,
            # non-integer-ratio lossy resize on top of Flutter's own
            # downscale, which the benchmark showed can locally increase
            # both file size and artifacting). Measured average PSNR/SSIM
            # vs. the true original improved from 26.6dB/0.587 (1200) to
            # 28.6dB/0.621 (2048) across the benchmark sample set, for a
            # ~2.4x average file-size cost (still capped -- large sources
            # are still downscaled if they exceed this).
            max_dim = int(os.getenv("UPLOAD_IMAGE_MAX_DIM", "2048") or "2048")
            if max(im.size) > max_dim:
                im.thumbnail((max_dim, max_dim), Image.Resampling.LANCZOS)
            buf = BytesIO()
            # Quality-audit fix: this is the ONE encode every listing photo
            # (blurred or not) goes through here, so raising the default
            # keeps the two paths visibly equivalent (requirement F) while
            # fixing the previous low default (80) that softened every
            # upload, not just plate-blurred ones (requirement D).
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
            # M-06: this is the last line of defense before persistence --
            # never fall through to persisting the original, unprocessed,
            # bomb-flagged ``out_bytes`` (which can happen either because
            # skip_blur was requested, or because blur_image_bytes() itself
            # already failed open and returned the original bytes). Reject
            # the whole file instead.
            raise DecompressionBombRejected(
                "process_and_store_image: image rejected by decompression-bomb guard"
            ) from e
        except Exception:
            pass

        # Persist the optimized bytes: prefer Cloudflare R2 when configured,
        # otherwise fall back to local filesystem under /static/uploads.
        final_rel = persist_jpeg_bytes(
            out_bytes,
            object_filename=final_filename,
            owner_public_id=owner_public_id,
        )

        if inline_base64:
            try:
                # L-03: same orientation-normalize-then-strip-EXIF guarantee as the
                # main save above. ``out_bytes`` here has already been through that
                # save (so it already carries no EXIF/orientation tag today), but
                # applying both explicitly keeps this call site self-contained and
                # correct even if the calling order above ever changes.
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

        return final_rel, b64
    finally:
        try:
            if temp_abs and os.path.exists(temp_abs):
                os.remove(temp_abs)
        except Exception:
            pass

