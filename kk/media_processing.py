from __future__ import annotations

import base64
import hashlib
import hmac
import logging
import os
import re
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

# 2026 real-device fix (5-images-become-1 investigation): register Pillow's
# HEIC/HEIF opener ONCE, here, at module import time -- unconditionally, in
# every process that imports this module (both the web process and the
# Celery worker, since kk/tasks/image_tasks.py imports from this module).
#
# ROOT CAUSE this fixes: `pillow_heif.register_heif_opener()` is a GLOBAL
# Pillow plugin registration, not scoped to one call. Before this fix, the
# ONLY code that ever called it was `kk/license_plate_blur.py`'s internal
# decode helpers -- which only run when plate-blur detection actually
# executes, i.e. only when `skip_blur=False`. A fresh worker process that
# received a HEIC-sourced photo (iPhone default camera format, uploaded
# with a `.jpg`/`.jpeg` filename/extension -- extension alone is NOT a
# reliable format signal) together with an explicit `skip_blur=True`
# request would therefore have NO HEIC decoder registered anywhere yet:
# `_process_image_bytes_from_path()`'s (and `process_and_store_image()`'s)
# downscale/re-encode step's `Image.open()` call would raise
# `PIL.UnidentifiedImageError`, which the old code silently swallowed
# (bare `except Exception: pass`), leaving the RAW, un-decoded HEIC bytes
# to be persisted straight to R2 under a `.jpg` filename and
# `Content-Type: image/jpeg`. Confirmed on a real production listing: 4 of
# 5 uploaded photos were raw HEIC (magic bytes `....ftypheic`) served with
# a `.jpg` URL, and Flutter's image decoder correctly refused to render
# them ("Could not decompress image"), while the 1 genuinely-JPEG photo
# rendered fine -- exactly matching the "only 1 of 5 visible" report.
#
# This eager, unconditional registration decouples HEIC decode capability
# from whether plate-blur detection happens to run first, closing that
# race/ordering hole entirely. `normalize_to_canonical_jpeg()` below is the
# second half of this fix: a hard failure (never a silent bytes-passthrough)
# if decode/re-encode still cannot produce valid JPEG output for any other
# reason.
try:
    import pillow_heif  # type: ignore

    pillow_heif.register_heif_opener()
except Exception:
    pass


class ImageNormalizationFailed(Exception):
    """2026 real-device fix: raised by :func:`normalize_to_canonical_jpeg`
    when the canonical decode -> EXIF-orientation -> RGB -> JPEG-re-encode
    step cannot produce genuine JPEG output bytes for the given source --
    including "Pillow does not recognize this format at all" (e.g. HEIC
    with no opener registered, a truly corrupt file, or an unsupported
    container).

    CORRECTNESS-CRITICAL CONTRACT: this must ALWAYS be a hard failure that
    propagates out of the caller (route handler / Celery task), never
    silently swallowed to fall back to the original, un-normalized bytes.
    Doing so previously let raw HEIC bytes be persisted to R2/local disk
    under a `.jpg` filename and `Content-Type: image/jpeg` -- a listing
    photo that no client could ever render, self-attached as if processing
    had fully succeeded. Callers must treat this exactly like
    :class:`DecompressionBombRejected`: reject/skip the individual file
    (route handlers) or transition the media-readiness item to the
    terminal ``failed`` status (the async Celery task) -- never persist or
    self-attach the unconfirmed bytes.
    """


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
    SKIPPED = "skipped"  # skip_blur honored -- ALWAYS, unconditionally, regardless of plate_blur_require_success_enabled() (see _run_plate_blur()'s docstring)
    NOT_CONFIGURED = "not_configured"  # PLATE_BLUR_ENABLED=0, or detector missing ROBOFLOW_API_KEY/project/version
    DETECTION_FAILED = "detection_failed"  # Roboflow request failed (network/API/timeout/quota/bad response)
    PROCESSING_FAILED = "processing_failed"  # image could not be decoded, or detected boxes were unusable
    ENCODING_FAILED = "encoding_failed"  # re-encoding the blurred image failed
    OTHER_FAILURE = "other_failure"  # any unexpected/ambiguous outcome -- fails closed, never treated as safe


# M-08: the ONLY statuses that may ever be persisted/returned when
# PLATE_BLUR_REQUIRE_SUCCESS=1 is enabled. Every other status --
# including any future/unknown status string this process doesn't
# recognize -- is rejected. See `_map_blur_meta_status()`.
#
# SKIPPED is included here (2026 real-device fix): `_run_plate_blur()` now
# ALWAYS honors an explicit `skip_blur=True` request unconditionally, even
# when `PLATE_BLUR_REQUIRE_SUCCESS=1` -- see its docstring. An explicit
# skip is the caller's own deliberate, confirmed choice (never an
# unconfirmed/ambiguous outcome), so it must not be rejected here; doing so
# would turn every legitimate "seller chose UNBLURRED" submission into a
# hard failure under M-08 enforcement, which is not what that flag is for.
_PLATE_BLUR_CONFIRMED_SAFE = frozenset(
    {PlateBlurStatus.BLURRED_SUCCESS, PlateBlurStatus.NO_PLATES, PlateBlurStatus.SKIPPED}
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


# ---------------------------------------------------------------------------
# Phase 1 of the server-side video transcode fallback: temporary SOURCE
# video staging (see kk/routes/media.py::sign_video_source_upload /
# finalize_video_source_upload, and kk/tasks/video_tasks.py's cleanup
# sweep). This is temporary storage for an oversized ORIGINAL video only --
# it is NOT final listing media, has no CarVideo row, and is completely
# separate from the unrelated 100MB final-listing-video cap
# (kk/routes/media.py::upload_car_videos ->
# validate_file_upload(max_size_mb=100)), which this feature never touches.
# Deliberately namespaced away from both real listing videos
# (``car_videos/<owner_segment><token>.<ext>``) and the image staging
# prefix above, so the periodic backstop sweep can target it precisely by
# prefix without ever matching a real listing video or an image staging
# object.
# ---------------------------------------------------------------------------
VIDEO_SOURCE_STAGING_KEY_PREFIX = "car_videos/_staging/"

# A client-chosen "stable draft media id" identifies one picked video across
# retries/app-restarts so the derived staging key is idempotent. This value
# is used directly as an R2 key path segment, so its charset/length must be
# tightly bounded -- it must never be able to contain "/", "..", or any
# other path-control sequence that could let a client influence which key
# it resolves to beyond its own owner-scoped directory.
_DRAFT_MEDIA_ID_RE = re.compile(r"^[A-Za-z0-9_-]{1,128}$")


def is_valid_draft_media_id(draft_media_id: str | None) -> bool:
    """True when ``draft_media_id`` is a safe, bounded path-segment value."""
    return bool(draft_media_id) and bool(_DRAFT_MEDIA_ID_RE.match(draft_media_id))


def video_source_staging_key(
    owner_public_id: str | None, draft_media_id: str | None
) -> str | None:
    """
    Deterministic, owner-scoped R2 key for one seller's staged SOURCE video.

    Idempotency: the SAME ``(owner_public_id, draft_media_id)`` pair always
    yields the SAME key -- a client retrying a sign-upload call (network
    failure, app restart, etc.) with the same draft media id reuses the
    exact same staging object instead of creating an unbounded number of
    orphan objects.

    Ownership isolation: a DIFFERENT owner using the same ``draft_media_id``
    string always yields a DIFFERENT key, because the owner-tag path
    segment (:func:`media_owner_tag`, an HMAC of the owner's public id
    keyed by ``SECRET_KEY``) differs. This holds even though
    ``draft_media_id`` itself is client-chosen and not secret -- ownership
    isolation comes entirely from the owner-tag segment, never from
    ``draft_media_id`` being unguessable.

    A fixed ``.src`` extension is used regardless of the real source
    container format. The actual content-type is instead (a) bound into
    the presigned PUT's signature at sign time, and (b) read back from R2
    object metadata and verified at finalize time (see
    ``finalize_video_source_upload()``). Deriving the key from a
    client-declared extension would let two calls with the same
    ``draft_media_id`` but a different claimed filename/content-type
    resolve to two different keys, breaking the idempotency guarantee this
    function exists to provide.

    Returns ``None`` if either input is missing/invalid -- callers must
    treat that as "cannot stage this upload" and never fall back to an
    unscoped or client-supplied key.
    """
    if not is_valid_draft_media_id(draft_media_id):
        return None
    owner_tag = media_owner_tag(owner_public_id)
    if not owner_tag:
        return None
    return f"{VIDEO_SOURCE_STAGING_KEY_PREFIX}{owner_tag}/{draft_media_id}.src"


# ---------------------------------------------------------------------------
# Phase 2 of the server-side video transcode fallback: PROCESSED (transcoded)
# video staging. IMPORTANT ARCHITECTURE RULE: a successful transcode is
# NEVER written directly to the permanent/final ``car_videos/`` namespace --
# at transcode time the car/listing this video will eventually belong to may
# not exist yet. Instead it is written here, to owner-scoped processed
# staging. A later Phase 3 "attach" endpoint (not implemented yet) will
# verify ownership/job result, promote/copy this object to permanent
# storage, create the actual ``CarVideo`` row, then delete this staging
# object. Deliberately namespaced under ``car_videos/`` (not a sibling of
# it) but with its own ``_processed_staging/`` segment, distinct from both
# real listing videos and ``car_videos/_staging/`` (Phase 1 SOURCE
# staging) -- so a periodic sweep can target exactly one of the three by
# prefix without ever matching either of the other two.
# ---------------------------------------------------------------------------
PROCESSED_VIDEO_STAGING_KEY_PREFIX = "car_videos/_processed_staging/"


def processed_video_staging_key(
    owner_public_id: str | None, draft_media_id: str | None
) -> str | None:
    """
    Deterministic, owner-scoped R2 key for one seller's PROCESSED
    (transcoded) staged video -- the Phase 2 counterpart of
    :func:`video_source_staging_key`, mirroring its exact ownership /
    idempotency principles:

    - Idempotency: the SAME ``(owner_public_id, draft_media_id)`` pair
      always yields the SAME key, so re-running (or retrying) the
      transcode task for the same draft video overwrites the same object
      rather than accumulating orphans.
    - Ownership isolation: a DIFFERENT owner using the same
      ``draft_media_id`` string always yields a DIFFERENT key, because the
      owner-tag path segment differs (same HMAC mechanism as
      :func:`media_owner_tag`).
    - ``draft_media_id`` is validated with the exact same
      :func:`is_valid_draft_media_id` helper used for source staging --
      same bounded charset, same path-injection protection.

    A fixed ``.mp4`` extension is used, matching the output contract every
    successful transcode must produce (MP4 container, H.264 video) -- see
    ``kk/video_transcoding.py``.

    Returns ``None`` if either input is missing/invalid.
    """
    if not is_valid_draft_media_id(draft_media_id):
        return None
    owner_tag = media_owner_tag(owner_public_id)
    if not owner_tag:
        return None
    return f"{PROCESSED_VIDEO_STAGING_KEY_PREFIX}{owner_tag}/{draft_media_id}.mp4"


# ---------------------------------------------------------------------------
# Phase 3A durability hardening: the PERMANENT destination key a promoted
# (transcoded) video is copied to (see
# kk/routes/media.py::attach_transcoded_video). Previously this was
# ``car_videos/{secrets.token_hex(16)}.mp4`` -- a fresh random key on every
# call. That created a crash window: if the R2 copy succeeded but the
# process died before the DB commit, the permanent object was orphaned
# (never referenced by any CarVideo row), and a retry would copy AGAIN to a
# brand new random key, leaving the first orphan behind forever (only ever
# reclaimed by nothing -- there is no sweep for the permanent namespace,
# unlike the two staging namespaces above).
#
# Making the destination key a DETERMINISTIC function of
# (owner_public_id, car_id, draft_media_id) instead fixes this: a retry for
# the exact same (owner, car, draft) always targets the exact SAME
# permanent key, so a server-side R2 CopyObject on retry simply
# overwrites/re-establishes the same destination instead of creating a new
# orphan -- see attach_transcoded_video()'s own crash-point-by-crash-point
# recovery docstring for how each ordering case (before/during/after copy,
# before/after the DB commit) is now safe.
# ---------------------------------------------------------------------------
_TRANSCODED_VIDEO_PERMANENT_KEY_VERSION = "v1"


def transcoded_video_permanent_key(
    owner_public_id: str | None, car_id: str | int | None, draft_media_id: str | None
) -> str | None:
    """
    Deterministic, opaque permanent R2 key for one successfully-promoted
    transcoded video -- the Phase 3A "final destination" counterpart of
    :func:`processed_video_staging_key`.

    Construction: ``HMAC-SHA256(SECRET_KEY, "transcoded-video:v1:<owner>:
    <car_id>:<draft_media_id>")``, truncated to the first 32 hex chars
    (128 bits -- ample collision resistance for this namespace's size),
    formatted as ``car_videos/<hex>.mp4``.

    Properties (all required by attach_transcoded_video()'s idempotent
    retry/crash-recovery contract):
      - Deterministic: the SAME ``(owner_public_id, car_id,
        draft_media_id)`` triple always yields the SAME key, on every call,
        forever (as long as ``SECRET_KEY`` does not change) -- a retry
        after ANY crash point targets the exact same permanent object
        instead of accumulating a new orphan.
      - Opaque: the output is a bare hex digest -- it never contains the
        raw ``owner_public_id``, ``car_id``, or ``draft_media_id`` as a
        readable substring (unlike, say, naively joining them with `-`),
        so a leaked/scraped permanent video URL cannot be used to infer any
        of those three values.
      - Isolated: changing ANY one of the three inputs changes the output
        key (standard HMAC input-avalanche property) -- a different owner,
        car, or draft_media_id never collides with another's permanent
        object.
      - Namespace-preserving: still lives directly under the existing
        ``car_videos/`` prefix used by the normal multipart
        ``upload_car_videos()`` endpoint (that endpoint's own random-token
        key scheme is UNCHANGED by this -- this function is used ONLY by
        the transcoded-video promotion/attach path).
      - The ``v1`` version segment lets this scheme be revised later (e.g.
        a v2 with different inputs) without ever colliding with a v1 key,
        should that become necessary.

    Returns ``None`` if any input is missing/invalid, or if ``SECRET_KEY``
    is not configured (mirrors :func:`media_owner_tag`'s same fail-closed
    contract) -- callers must treat that as "cannot derive a permanent key"
    and never fall back to a client-supplied or unscoped key.
    """
    if not is_valid_draft_media_id(draft_media_id):
        return None
    owner = (owner_public_id or "").strip()
    car = str(car_id if car_id is not None else "").strip()
    if not owner or not car:
        return None
    secret = (current_app.config.get("SECRET_KEY") or "").encode("utf-8")
    if not secret:
        return None
    payload = (
        f"transcoded-video:{_TRANSCODED_VIDEO_PERMANENT_KEY_VERSION}:"
        f"{owner}:{car}:{draft_media_id}"
    ).encode("utf-8")
    digest = hmac.new(secret, payload, hashlib.sha256).hexdigest()[:32]
    return f"car_videos/{digest}.mp4"


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


def normalize_to_canonical_jpeg(raw_bytes: bytes) -> bytes:
    """The ONE canonical image-normalization step every uploaded listing
    photo must go through before persistence -- deliberately independent of
    whether plate-blur ran (see the module-level HEIC-eager-registration
    comment above, and ``_run_plate_blur()``'s docstring: ``skip_blur``
    must only ever skip plate detection/blur, never decode/normalize/
    resize/encode).

    Decodes ``raw_bytes`` in WHATEVER format they actually are -- JPEG,
    PNG, WEBP, HEIC/HEIF, ... (content-based, via Pillow/``pillow_heif``'s
    globally-registered opener; never inferred from a filename extension,
    which is not a reliable format signal -- this is exactly how 4 raw HEIC
    files ended up served under a `.jpg` URL on a real production
    listing), applies EXIF orientation into the pixels, converts to RGB/L,
    resizes to ``UPLOAD_IMAGE_MAX_DIM``, and re-encodes as a genuine JPEG
    at ``UPLOAD_IMAGE_JPEG_QUALITY``. Also verifies the final bytes' magic
    header truly is JPEG (defense in depth) before returning.

    Raises :class:`DecompressionBombRejected` (M-06, propagated from
    Pillow's own decompression-bomb guard) or
    :class:`ImageNormalizationFailed` (any other decode/encode failure, or
    a final-bytes magic-header mismatch). NEVER silently returns the
    original, un-normalized bytes on failure -- a caller that catches and
    discards these exceptions would reintroduce the exact real-device bug
    (raw HEIC bytes persisted under a `.jpg` filename/Content-Type) this
    function exists to close off. Callers must let both exceptions
    propagate (reject/skip the file, or fail the Celery task) rather than
    falling back to unconfirmed bytes.
    """
    try:
        from PIL import Image, ImageOps

        im = Image.open(BytesIO(raw_bytes))
        im = ImageOps.exif_transpose(im)
        if im.mode not in ("RGB", "L"):
            im = im.convert("RGB")
        max_dim = int(os.getenv("UPLOAD_IMAGE_MAX_DIM", "2048") or "2048")
        if max(im.size) > max_dim:
            im.thumbnail((max_dim, max_dim), Image.Resampling.LANCZOS)
        quality = int(os.getenv("UPLOAD_IMAGE_JPEG_QUALITY", "92") or "92")
        save_kwargs = dict(
            format="JPEG",
            quality=quality,
            exif=b"",
            subsampling=0,  # 4:4:4 -- preserve chroma/detail
        )
        try:
            # ``optimize=True`` runs libjpeg-turbo's 2-pass Huffman-table
            # optimization. On very high-entropy/incompressible pixel data
            # (confirmed via a targeted repro: uniform random noise at
            # quality>=92, subsampling=0) this specific Pillow/libjpeg-turbo
            # build can raise ``OSError: broken data stream when writing
            # image file`` on Windows -- a real, deterministic libjpeg-turbo
            # encoder limitation, unrelated to the HEIC root-cause fix above.
            # It was previously invisible because the old inline code's bare
            # ``except Exception: pass`` silently swallowed it (leaving
            # un-normalized bytes persisted). Real camera photos are not
            # adversarially high-entropy like this, so this path is expected
            # to be rare, but a single retry WITHOUT ``optimize`` (same
            # quality/subsampling, still a full genuine re-encode -- never a
            # raw-bytes passthrough) keeps rare pathological inputs from
            # being needlessly rejected.
            buf = BytesIO()
            im.save(buf, optimize=True, **save_kwargs)
            out_bytes = buf.getvalue()
        except OSError:
            buf = BytesIO()
            im.save(buf, optimize=False, **save_kwargs)
            out_bytes = buf.getvalue()
    except DecompressionBombError as e:
        # M-06: never swallow -- the original, bomb-flagged bytes must
        # never be persisted as if normalization had succeeded.
        raise DecompressionBombRejected(
            "normalize_to_canonical_jpeg: image rejected by decompression-bomb guard"
        ) from e
    except Exception as e:
        raise ImageNormalizationFailed(
            "normalize_to_canonical_jpeg: could not decode/re-encode source "
            f"bytes as JPEG ({type(e).__name__})"
        ) from e

    # Belt-and-suspenders (Section 5 output-validation guard): even a
    # "successful" PIL save must genuinely be a JPEG. Guards against any
    # future change to this function accidentally producing something else
    # while a caller still persists it under a `.jpg` filename.
    if out_bytes[:3] != b"\xff\xd8\xff":
        raise ImageNormalizationFailed(
            "normalize_to_canonical_jpeg: final bytes are not valid JPEG "
            "(magic bytes mismatch)"
        )
    return out_bytes


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

    CORRECTNESS-CRITICAL CONTRACT (2026 real-device investigation):
    ``skip_requested=True`` MUST ALWAYS result in ``PlateBlurStatus.SKIPPED``
    -- detection must never even run, regardless of ``force_attempt``. This
    is an unconditional guarantee the sell-listing "Blur/Unblur choice"
    feature depends on: when a seller explicitly chooses UNBLURRED as their
    final, informed submission choice, the server sends
    ``skip_blur=true`` for that image, and the resulting listing photo must
    be provably byte-identical in outcome to "blur never attempted" -- never
    silently blurred anyway.

    ``force_attempt`` (M-08, ``PLATE_BLUR_REQUIRE_SUCCESS``) previously
    overrode ``skip_requested`` -- the original rationale was that an
    ordinary client-controlled ``skip_blur=1`` request parameter should not
    be able to bypass a server-enforced blur requirement. That rationale
    predates the current product contract, under which ``skip_blur`` is no
    longer an arbitrary/untrusted bypass flag but the seller's own
    deliberate final choice (see ``SellMediaIdentity.
    skipBlurForFinalSubmission`` on the Flutter side) -- forcing a blur the
    seller explicitly declined is itself the defect, confirmed on a real
    device: production logged ``skip_blur=True`` together with
    ``plate_blur_applied=True`` and a processed-image hash IDENTICAL to a
    separately-run ``skip_blur=False`` preview job for the same source,
    proving detection ran (and blurred) despite the explicit skip request.
    ``force_attempt`` now ONLY affects the ``skip_requested=False`` (blur
    genuinely wanted) path below -- it still makes THAT path fail closed
    (reject rather than silently persist an unconfirmed outcome) exactly as
    before; it can no longer force detection to run when the caller asked
    to skip it outright.
    """
    if skip_requested:
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


def blur_image_bytes_with_status(
    raw_bytes: bytes, ext: str, *, skip_blur: bool = False
) -> tuple[bytes, PlateBlurStatus]:
    """Same behavior as ``blur_image_bytes()``, but also returns the
    definitive ``PlateBlurStatus`` for the attempt (e.g. so a caller can log
    whether the blur was actually applied, vs. skipped/failed-open).

    TEMPORARY DEBUG plumbing (2026 plate-blur real-device trace): factored
    out of ``blur_image_bytes()`` so callers that need ``plate_blur_applied``
    for tracing can share this exact one-call code path instead of running
    detection twice. Pure refactor -- no behavior change vs. the previous
    inline body of ``blur_image_bytes()`` below.
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
    return outcome.out_bytes, outcome.status


def blur_image_bytes(raw_bytes: bytes, ext: str, *, skip_blur: bool = False) -> bytes:
    """Run license-plate blur on in-memory image bytes; return blurred bytes.

    ``skip_blur=True`` ALWAYS returns the original bytes unchanged and never
    raises, and detection is never even attempted -- unconditionally,
    regardless of ``plate_blur_require_success_enabled()`` (see
    ``_run_plate_blur()``'s docstring for the 2026 real-device fix that made
    this an absolute contract rather than a fail-open-mode-only behavior).

    When ``skip_blur=False`` and ``PLATE_BLUR_REQUIRE_SUCCESS`` is unset
    (the default), this preserves the original fail-open behavior
    byte-for-byte -- any detector/network/processing failure returns the
    original bytes unchanged and never raises. When
    ``PLATE_BLUR_REQUIRE_SUCCESS=1`` is set, this instead raises
    ``PlateBlurRequiredRejected`` for any outcome other than a confirmed
    ``BLURRED_SUCCESS`` or ``NO_PLATES`` (see ``PRODUCTION_AUDIT.md`` M-08
    for the original rationale).
    """
    out_bytes, _status = blur_image_bytes_with_status(raw_bytes, ext, skip_blur=skip_blur)
    return out_bytes


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

        # Downscale/compress + canonicalize (2026 real-device fix: this is
        # now the SAME `normalize_to_canonical_jpeg()` every listing photo
        # goes through regardless of `skip_blur` or source format -- see
        # that function's docstring, and `DecompressionBombRejected`/
        # `ImageNormalizationFailed` are both hard failures that propagate
        # out of this function; neither is ever swallowed here. This is the
        # ONE encode every listing photo (blurred or not) goes through, so
        # the two paths stay visibly equivalent (requirement F).
        #
        # L-03: EXIF orientation is normalized into the pixels before
        # stripping metadata; the final JPEG carries no source EXIF (GPS,
        # camera/device model, timestamps, or the orientation tag itself).
        out_bytes = normalize_to_canonical_jpeg(out_bytes)

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

