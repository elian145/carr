from __future__ import annotations

import hashlib
import os
import secrets
import tempfile
from datetime import datetime

from flask import Blueprint, current_app, jsonify, request
from flask_jwt_extended import jwt_required
from werkzeug.utils import safe_join

from ..auth import get_current_user, log_user_action, phone_verification_required_response
from ..job_ownership import (
    get_idempotent_job_task_id,
    get_registered_job_owner,
    is_valid_task_id,
    register_idempotent_job_task_id,
    register_job_owner,
)
from ..media_processing import (
    DecompressionBombRejected,
    ImageNormalizationFailed,
    PlateBlurRequiredRejected,
    is_valid_draft_media_id,
    media_key_owner_prefix_matches,
    media_owner_tag,
    process_and_store_image,
    processed_video_staging_key,
    stage_upload_for_async_job,
    transcoded_video_permanent_key,
    video_source_staging_key,
)
from ..media_readiness import mark_item_phase_a_accepted, mark_normal_video_attached_locked
from ..models import Car, CarImage, CarVideo, db
from ..security import generate_secure_filename, validate_file_upload, rate_limit
from ..tasks.image_tasks import process_car_image_file
from .. import video_transcoding as vt
from ..tasks.video_tasks import (
    VIDEO_JOB_AUTH_TTL_SECONDS,
    VIDEO_TRANSCODE_TASK_EXPIRES_SECONDS,
    celery_state_to_video_job_state,
    transcode_car_video_source,
    video_job_dedupe_key,
)
from ..time_utils import utcnow

bp = Blueprint("media", __name__)


def _r2_configured() -> bool:
    """True if R2 is configured (account + bucket + credentials)."""
    c = current_app.config
    return bool(
        c.get("R2_ACCOUNT_ID")
        and c.get("R2_BUCKET_NAME")
        and c.get("R2_ACCESS_KEY_ID")
        and c.get("R2_SECRET_ACCESS_KEY")
    )


def _r2_public_base() -> str:
    return (current_app.config.get("R2_PUBLIC_URL") or "").strip().rstrip("/")


def _r2_ready_for_public_object_urls() -> bool:
    """Upload objects to R2 and expose them via R2_PUBLIC_URL (custom domain or r2.dev)."""
    return _r2_configured() and bool(_r2_public_base())


def _presigned_upload_enabled() -> bool:
    """H-03: gate for the direct-to-R2 presigned-PUT upload flow.

    ``r2_sign_upload()`` hands an authenticated client a presigned PUT URL
    and never sees the uploaded bytes itself — unlike every other upload
    path in this file (``/api/cars/<id>/images``, ``/api/cars/<id>/videos``,
    ``/api/process-car-images``), it cannot run the magic-byte check in
    ``kk/security.py::sniff_bytes`` because the server never receives the
    file body.

    As of the H-03 follow-up audit, ``signR2ImageUpload()`` in the Flutter
    client (``lib/services/api/api_listings.dart``) has **no caller** — the
    shipped app always uploads listing media via the validated multipart
    endpoints above. This flow is therefore disabled by default in every
    environment (including production) until either (a) a caller is added
    *and* attach-time content validation is implemented for it, or (b) it is
    removed outright. Re-enable only via the explicit env var below, and
    only after re-reviewing this decision.
    """
    return (os.environ.get("R2_PRESIGNED_UPLOAD_ENABLED") or "").strip().lower() in (
        "1",
        "true",
        "yes",
        "on",
    )


def _video_content_type_for_ext(ext: str) -> str:
    ext = (ext or "").lower()
    if not ext.startswith("."):
        ext = "." + ext
    return {
        ".mp4": "video/mp4",
        ".mov": "video/quicktime",
        ".webm": "video/webm",
        ".mkv": "video/x-matroska",
        ".avi": "video/x-msvideo",
    }.get(ext, "application/octet-stream")


_ALLOWED_IMAGE_CONTENT_TYPES = frozenset(
    {
        "image/jpeg",
        "image/jpg",
        "image/png",
        "image/gif",
        "image/webp",
        "image/heic",
        "image/heif",
    }
)
_ALLOWED_VIDEO_CONTENT_TYPES = frozenset(
    {
        "video/mp4",
        "video/quicktime",
        "video/webm",
        "video/x-matroska",
        "video/x-msvideo",
    }
)
_R2_IMAGE_MAX_BYTES = 25 * 1024 * 1024
_R2_VIDEO_MAX_BYTES = 200 * 1024 * 1024

# Phase 1 of the server-side video transcode fallback (audit: "SECURE
# DIRECT-TO-R2 SOURCE-VIDEO STAGING"). This is a SEPARATE, temporary
# SOURCE-upload cap -- deliberately NOT the same constant as
# _R2_VIDEO_MAX_BYTES above (the disabled-by-default *final*-media presign
# cap) and completely unrelated to the 100MB final-listing-video cap
# enforced by upload_car_videos() (validate_file_upload(max_size_mb=100)).
# A staged source object is never a listing video by itself -- it must
# still go through a (not-yet-implemented) transcode step, which is the
# only thing that will ever produce a <=100MB final video. 500 MiB gives
# headroom for a real high-bitrate 4K/Dolby-Vision clip within the Sell
# picker's existing 5-minute duration cap (see
# lib/features/sell/sell_step4_logic.dart's `pickMultiVideo(maxDuration:
# Duration(minutes: 5))`) without being unbounded.
_R2_VIDEO_SOURCE_STAGING_MAX_BYTES = 500 * 1024 * 1024

# Short-lived: long enough for a mobile upload of a large file to
# complete, short enough to bound a leaked-URL exposure window. Matches
# the "~15 minutes" target from the audit.
_VIDEO_SOURCE_STAGING_URL_EXPIRES_SECONDS = 900

_ALLOWED_VIDEO_SOURCE_EXTENSIONS = frozenset({".mp4", ".mov", ".avi", ".mkv", ".webm"})


def _video_source_staging_enabled() -> bool:
    """
    Gate for the two Phase-1 video-source-staging endpoints below.

    Mirrors ``_presigned_upload_enabled()``'s precedent immediately above
    (H-03 audit): a direct-to-R2 write path whose bytes this process never
    sees is new attack surface, and this feature is intentionally
    incomplete as of Phase 1 -- there is no transcode consumer yet and no
    Sell-flow client caller yet (see the audit report). Default OFF until
    the end-to-end feature (transcode + client fallback) actually exists,
    so shipping this backend groundwork alone can never silently expose a
    live, unused upload path in production.
    """
    return (os.environ.get("VIDEO_SOURCE_STAGING_ENABLED") or "").strip().lower() in (
        "1",
        "true",
        "yes",
        "on",
    )
MAX_DAMAGE_PHOTOS = 10
# M-06: cumulative-per-car cap on listing (non-damage) photos, mirroring the
# existing Flutter client cap (`_kSellMaxPhotos` in
# lib/features/sell/sell_step4_logic.dart) and the existing MAX_DAMAGE_PHOTOS
# precedent. Enforced server-side so it cannot be bypassed by a modified
# client or a direct API call.
MAX_LISTING_PHOTOS = 20

# Phase 3A (server-side video transcode fallback -- promotion/attach):
# cumulative-per-car cap on listing videos, mirroring the existing Flutter
# client cap (`_kSellMaxVideos = 3` in lib/features/sell/sell_step4_logic.dart).
#
# NOTE (audit finding): the older, pre-existing multipart
# `upload_car_videos()` endpoint below does NOT currently enforce any
# server-side video-count cap at all (unlike the photo caps above) -- that
# is a separate, pre-existing gap, out of scope for this Phase 3A change,
# which only implements the new transcoded-video promotion/attach
# endpoint. This constant/check is enforced by `attach_transcoded_video()`
# only, so a modified client (or a direct API call) cannot use THAT path
# to exceed the same cap the shipped Sell UI already assumes.
MAX_LISTING_VIDEOS = 3


def _normalize_signed_content_type(raw: str, *, asset: str, default_ct: str) -> str | None:
    ct = (raw or default_ct).strip().lower().split(";")[0].strip()
    allowed = (
        _ALLOWED_VIDEO_CONTENT_TYPES if asset == "video" else _ALLOWED_IMAGE_CONTENT_TYPES
    )
    if ct not in allowed:
        return None
    if ct == "image/jpg":
        return "image/jpeg"
    return ct


def _allowed_attach_media_url(url: str) -> bool:
    """Only allow HTTPS objects under our R2 public base + known key prefixes."""
    u = (url or "").strip()
    if not u.lower().startswith("https://"):
        return False
    public_base = _r2_public_base()
    if not public_base:
        return False
    prefix = public_base.rstrip("/") + "/"
    if not u.startswith(prefix):
        return False
    key = u[len(prefix) :]
    return key.startswith("car_photos/") or key.startswith("car_videos/")


def _http_url_owned_by_user(url: str, user_id: int) -> bool:
    """True if this exact URL is already attached to one of this user's own cars.

    The R2 bucket is public-read, so `car_photos/<key>.jpg` URLs are guessable
    from any listing a scraper can see. Attach must only let a seller re-attach
    media they already own (e.g. keeping existing photos when editing a
    listing), not hot-link someone else's photo onto their own listing.
    """
    return (
        db.session.query(CarImage.id)
        .join(Car, Car.id == CarImage.car_id)
        .filter(Car.seller_id == user_id, CarImage.image_url == url)
        .first()
        is not None
    )


def _http_url_staged_by_user(url: str, owner_public_id: str | None) -> bool:
    """True if this URL is an object this seller uploaded but hasn't attached yet.

    Sellers stage listing photos before the car row exists (so the photos land
    with the listing instead of trailing behind it), which means there is no
    CarImage row to prove ownership. The object key carries an HMAC of the
    seller's public id instead.
    """
    public_base = _r2_public_base()
    if not public_base:
        return False
    prefix = public_base.rstrip("/") + "/"
    if not (url or "").startswith(prefix):
        return False
    return media_key_owner_prefix_matches(url[len(prefix) :], owner_public_id)


def _upload_video_file_to_r2(file_storage) -> str:
    """
    Stream a validated multipart video upload to R2, return public HTTPS
    URL for DB storage. Caller must ensure stream is at position 0 or call
    seek(0) after validation.

    P-02: videos are allowed up to 100MB (see ``upload_car_videos``'s
    ``validate_file_upload(..., max_size_mb=100)`` call). The previous
    implementation read the *entire* file into a single ``bytes`` object in
    this process (``file_storage.read()``) before handing it to
    ``r2_put_bytes()``, which then wrote those same bytes back out to a
    second temp file just to satisfy the R2 subprocess's ``body_path``
    contract -- i.e. the full video was buffered in this request-handling
    process's memory (on top of a redundant disk copy) for every upload.
    This now streams straight to a temp file via ``FileStorage.save()``
    (Werkzeug copies in small fixed-size chunks -- no full-file memory
    buffer here) and hands that existing path directly to
    ``r2_put_file()``, so this process never holds more than one chunk of
    the video in memory at a time. The temp file is always removed
    afterward, success or failure.
    """
    public_base = _r2_public_base()
    if not public_base:
        raise RuntimeError("R2_PUBLIC_URL is not set")

    raw_name = (file_storage.filename or "video.mp4").strip()
    ext = os.path.splitext(raw_name)[1].lower() or ".mp4"
    if ext not in (".mp4", ".mov", ".avi", ".mkv", ".webm"):
        ext = ".mp4"
    key = f"car_videos/{secrets.token_hex(16)}{ext}"

    try:
        file_storage.seek(0)
    except Exception:
        pass

    upload_root = (current_app.config.get("UPLOAD_FOLDER") or "").strip() or tempfile.gettempdir()
    tmp_dir = os.path.join(upload_root, "temp")
    os.makedirs(tmp_dir, exist_ok=True)
    tmp_path = os.path.join(tmp_dir, f"r2video_{secrets.token_hex(16)}{ext}")
    try:
        file_storage.save(tmp_path)
        if not os.path.isfile(tmp_path) or os.path.getsize(tmp_path) <= 0:
            raise RuntimeError("Empty file body")

        from ..r2_ops import r2_put_file

        ct = _video_content_type_for_ext(ext)
        r2_put_file(key=key, file_path=tmp_path, content_type=ct, timeout=180)
        return f"{public_base}/{key}"
    finally:
        try:
            if os.path.isfile(tmp_path):
                os.remove(tmp_path)
        except OSError:
            pass


def _get_car_by_any_id(car_id: str):
    car = Car.query.filter_by(public_id=car_id).first()
    if not car and str(car_id).isdigit():
        try:
            car = Car.query.filter_by(id=int(car_id)).first()
        except Exception:
            car = None
    return car


def _normalize_car_image_kind(raw) -> str:
    """Return 'damage' or 'listing' for stored CarImage.kind."""
    s = (str(raw or "")).strip().lower()
    return "damage" if s == "damage" else "listing"


def _count_images_of_kind(car: Car, kind: str) -> int:
    want = _normalize_car_image_kind(kind)
    try:
        return sum(
            1
            for img in car.images
            if _normalize_car_image_kind(getattr(img, "kind", None)) == want
        )
    except Exception:
        return 0


def _count_listing_images(car: Car) -> int:
    return _count_images_of_kind(car, "listing")


def _damage_photo_limit_error(existing: int, incoming: int):
    if existing + incoming <= MAX_DAMAGE_PHOTOS:
        return None
    return (
        jsonify(
            {
                "message": (
                    f"You can add up to {MAX_DAMAGE_PHOTOS} damage photos per listing."
                )
            }
        ),
        400,
    )


def _listing_photo_limit_error(existing: int, incoming: int):
    """M-06: reject the whole request (all-or-nothing) once a cumulative
    per-car cap of ``MAX_LISTING_PHOTOS`` listing photos would be exceeded.

    Mirrors ``_damage_photo_limit_error`` exactly (same all-or-nothing
    semantics, same response shape) so a request that would push a car over
    the cap is rejected outright rather than partially accepted -- matching
    the API's existing established convention for the damage-photo cap.
    """
    if existing + incoming <= MAX_LISTING_PHOTOS:
        return None
    return (
        jsonify(
            {
                "message": (
                    f"You can add up to {MAX_LISTING_PHOTOS} photos per listing."
                )
            }
        ),
        400,
    )


def _video_limit_error(existing: int, incoming: int):
    """Phase 3A: mirrors ``_damage_photo_limit_error``/``_listing_photo_limit_error``
    exactly (same all-or-nothing shape/response), for ``MAX_LISTING_VIDEOS``.
    Only used by ``attach_transcoded_video()`` -- see ``MAX_LISTING_VIDEOS``'s
    own comment for why the older multipart video-upload endpoint is
    unaffected."""
    if existing + incoming <= MAX_LISTING_VIDEOS:
        return None
    return (
        jsonify(
            {
                "message": (
                    f"You can add up to {MAX_LISTING_VIDEOS} videos per listing."
                )
            }
        ),
        400,
    )


def _pick_primary_listing_url(car: Car):
    """Prefer primary among listing photos; never use damage-only rows as hero."""
    try:
        for img in car.images:
            if (
                getattr(img, "is_primary", False)
                and _normalize_car_image_kind(getattr(img, "kind", None)) == "listing"
            ):
                return img.image_url
        for img in car.images:
            if _normalize_car_image_kind(getattr(img, "kind", None)) == "listing":
                return img.image_url
        return None
    except Exception:
        return None


def _normalize_image_match_key(url: str) -> str:
    """Normalize stored or client image refs for fuzzy equality checks."""
    from urllib.parse import urlparse

    s = (url or "").strip().replace("\\", "/")
    if not s:
        return ""
    if "?" in s:
        s = s.split("?", 1)[0]
    lower = s.lower()
    if lower.startswith("http://") or lower.startswith("https://"):
        s = urlparse(s).path.lstrip("/")
    if s.startswith("/"):
        s = s[1:]
    if s.startswith("static/"):
        s = s[len("static/") :]
    return s.lower()


def _find_listing_image_by_ref(car: Car, image_ref: str):
    """Return a listing CarImage row matching a client path or URL."""
    key = _normalize_image_match_key(image_ref)
    if not key:
        return None
    basename = os.path.basename(key)
    for img in car.images:
        if _normalize_car_image_kind(getattr(img, "kind", None)) != "listing":
            continue
        stored = _normalize_image_match_key(getattr(img, "image_url", "") or "")
        if not stored:
            continue
        if stored == key or stored.endswith("/" + key) or key.endswith("/" + stored):
            return img
        if basename and os.path.basename(stored) == basename:
            return img
    return None


def _set_primary_listing_image(car: Car, image_ref: str):
    """Mark one listing photo as primary; clear primary on other listing photos."""
    target = _find_listing_image_by_ref(car, image_ref)
    if not target:
        return None
    for img in car.images:
        if _normalize_car_image_kind(getattr(img, "kind", None)) != "listing":
            continue
        img.is_primary = img.id == target.id
    return target.image_url


@bp.route("/api/cars/<car_id>/images/primary", methods=["PUT"])
@jwt_required()
def set_car_primary_image(car_id: str):
    """Set which listing photo is the cover / primary image."""
    try:
        current_user = get_current_user()
        verify_err = phone_verification_required_response(current_user)
        if verify_err:
            return verify_err

        car = _get_car_by_any_id(car_id)
        if not car:
            return jsonify({"message": "Car not found"}), 404

        if car.seller_id != current_user.id and not current_user.is_admin:
            return jsonify({"message": "Not authorized to update images for this listing"}), 403

        data = request.get_json(silent=True) or {}
        image_ref = (
            data.get("image_url")
            or data.get("path")
            or data.get("url")
            or ""
        )
        image_ref = str(image_ref).strip()
        if not image_ref:
            return jsonify({"message": "image_url is required"}), 400

        primary_url = _set_primary_listing_image(car, image_ref)
        if not primary_url:
            return jsonify({"message": "Image not found on this listing"}), 404

        db.session.commit()
        log_user_action(current_user, "set_primary_image", "car", car.public_id)

        return jsonify({"message": "Primary image updated", "image_url": primary_url}), 200
    except Exception:
        db.session.rollback()
        return jsonify({"message": "Failed to set primary image"}), 500


@bp.route("/api/cars/<car_id>/images/layout", methods=["PUT"])
@jwt_required()
def update_car_image_layout(car_id: str):
    """Persist ordering and non-destructive vertical crop metadata."""
    try:
        current_user = get_current_user()
        car = _get_car_by_any_id(car_id)
        if not car:
            return jsonify({"message": "Car not found"}), 404
        if car.seller_id != current_user.id and not current_user.is_admin:
            return jsonify({"message": "Not authorized to update images for this listing"}), 403

        data = request.get_json(silent=True) or {}
        rows = data.get("images")
        if not isinstance(rows, list):
            return jsonify({"message": "images must be a list"}), 400

        by_id = {img.id: img for img in car.images}
        updated = []
        requested_primary = None
        for index, raw in enumerate(rows):
            if not isinstance(raw, dict):
                return jsonify({"message": "Each image layout must be an object"}), 400
            try:
                image_id = int(raw.get("id"))
            except (TypeError, ValueError):
                return jsonify({"message": "Each image layout requires a valid id"}), 400
            image = by_id.get(image_id)
            if image is None:
                return jsonify({"message": f"Image {image_id} is not on this listing"}), 400

            focus = raw.get("focus_y")
            if focus is None or focus == "":
                image.focus_y = None
            else:
                try:
                    focus = float(focus)
                except (TypeError, ValueError):
                    return jsonify({"message": "focus_y must be between 0 and 1"}), 400
                if not 0.0 <= focus <= 1.0:
                    return jsonify({"message": "focus_y must be between 0 and 1"}), 400
                image.focus_y = focus

            for field in ("image_width", "image_height"):
                value = raw.get(field)
                if value is not None:
                    try:
                        value = int(value)
                    except (TypeError, ValueError):
                        return jsonify({"message": f"{field} must be a positive integer"}), 400
                    if value <= 0:
                        return jsonify({"message": f"{field} must be a positive integer"}), 400
                    setattr(image, field, value)

            image.order = int(raw.get("order", index))
            if raw.get("is_primary") is True and _normalize_car_image_kind(image.kind) == "listing":
                requested_primary = image.id
            updated.append(image)

        if requested_primary is not None:
            for image in car.images:
                if _normalize_car_image_kind(image.kind) == "listing":
                    image.is_primary = image.id == requested_primary

        db.session.commit()
        return jsonify({"images": [image.to_dict() for image in updated]}), 200
    except Exception:
        db.session.rollback()
        return jsonify({"message": "Failed to update image layout"}), 500


def _storage_key_from_url(url: str) -> str | None:
    """Extract an R2 object key from a stored ``image_url``/``video_url``.

    Returns ``None`` when ``url`` is not an R2-hosted object this process
    knows how to map back to a key (e.g. a local ``uploads/...`` path, or an
    unrelated/foreign HTTPS URL) -- callers must treat that as "nothing to
    delete from R2", not an error.
    """
    u = (url or "").strip()
    if not u:
        return None
    public_base = _r2_public_base()
    if public_base:
        prefix = public_base.rstrip("/") + "/"
        if u.startswith(prefix):
            return u[len(prefix):] or None
        if u.lower().startswith("http://") or u.lower().startswith("https://"):
            # Foreign/unexpected host -- never attempt to delete it.
            return None
    # R2 configured without a public URL: `persist_jpeg_bytes()` /
    # `_upload_video_file_to_r2()` can store the bare bucket key itself
    # (see media_processing.persist_jpeg_bytes docstring).
    if u.startswith("car_photos/") or u.startswith("car_videos/"):
        return u
    return None


def _delete_media_storage_object(url: str) -> None:
    """Best-effort delete of the underlying storage object for ``url``.

    Never raises: an already-missing object, an unrecognized URL shape, or a
    storage-backend failure must never block the DB row deletion the caller
    already committed -- this mirrors the fail-safe posture every upload
    path in this file already takes toward storage errors (log and degrade,
    never leave the request half-done).
    """
    u = (url or "").strip()
    if not u:
        return
    key = _storage_key_from_url(u)
    if key and _r2_configured():
        try:
            from ..r2_ops import r2_delete_object

            r2_delete_object(key=key)
        except Exception as e:
            current_app.logger.warning(
                "Failed to delete R2 media object (best-effort, key length=%d): %s",
                len(key),
                e,
            )
        return

    # Local-disk path: uploads/car_photos/<file> or uploads/car_videos/<file>.
    rel = u.lstrip("/")
    if rel.startswith("static/"):
        rel = rel[len("static/"):]
    if not rel.startswith("uploads/"):
        return
    subpath = os.path.relpath(rel, "uploads").replace("\\", "/")

    # Mirror misc.static_files()'s resolution order: prefer the configured
    # UPLOAD_FOLDER (may live outside kk/static on persistent storage), then
    # fall back to the kk/static/uploads mirror used by older uploads.
    candidate_roots = []
    configured_root = (current_app.config.get("UPLOAD_FOLDER") or "").strip()
    if configured_root:
        candidate_roots.append(os.path.abspath(configured_root))
    candidate_roots.append(
        os.path.abspath(os.path.join(current_app.root_path, "static", "uploads"))
    )

    for upload_root in candidate_roots:
        try:
            abs_path = safe_join(upload_root, subpath)
            if not abs_path:
                continue
            abs_path = os.path.abspath(abs_path)
            if not abs_path.startswith(upload_root + os.sep):
                continue
            if os.path.isfile(abs_path):
                os.remove(abs_path)
                return
        except OSError as e:
            current_app.logger.warning(
                "Failed to delete local media file (best-effort): %s", e
            )


@bp.route("/api/cars/<car_id>/images/<int:image_id>", methods=["DELETE"])
@jwt_required()
def delete_car_image(car_id: str, image_id: int):
    """Delete one photo from a listing: removes the DB row and (best-effort)
    the underlying storage object.

    - Owner (or admin) only -- 403 otherwise (no IDOR: the image must also
      belong to *this* car, not just to the caller, or a guessed image id on
      someone else's car would 404 rather than leaking existence).
    - Refuses to delete the last remaining "listing" (non-damage) photo so a
      listing never ends up with zero cover-eligible photos -- this is the
      server-side backstop for the same "at least one photo" invariant the
      sell wizard already enforces client-side before it will submit.
    - If the deleted photo was the primary/cover image, promotes the next
      remaining listing photo (lowest ``order``, then ``id``) to primary so
      the listing's cover never silently disappears.
    """
    try:
        current_user = get_current_user()
        verify_err = phone_verification_required_response(current_user)
        if verify_err:
            return verify_err

        car = _get_car_by_any_id(car_id)
        if not car:
            return jsonify({"message": "Car not found"}), 404
        if car.seller_id != current_user.id and not current_user.is_admin:
            return jsonify({"message": "Not authorized to modify images for this listing"}), 403

        image = CarImage.query.filter_by(id=image_id, car_id=car.id).first()
        if not image:
            return jsonify({"message": "Image not found on this listing"}), 404

        kind = _normalize_car_image_kind(image.kind)
        if kind == "listing":
            remaining_listing = (
                CarImage.query.filter(
                    CarImage.car_id == car.id,
                    CarImage.id != image.id,
                    CarImage.kind != "damage",
                ).count()
            )
            if remaining_listing == 0:
                return (
                    jsonify(
                        {
                            "message": (
                                "At least one photo is required. Add a new "
                                "photo before removing the last one."
                            )
                        }
                    ),
                    400,
                )

        was_primary = bool(image.is_primary) and kind == "listing"
        image_url = image.image_url

        db.session.delete(image)

        if was_primary:
            next_image = (
                CarImage.query.filter(
                    CarImage.car_id == car.id,
                    CarImage.id != image.id,
                    CarImage.kind != "damage",
                )
                .order_by(CarImage.order.asc(), CarImage.id.asc())
                .first()
            )
            if next_image:
                next_image.is_primary = True

        db.session.commit()

        _delete_media_storage_object(image_url)

        log_user_action(current_user, "delete_image", "car", car.public_id)

        try:
            primary = _pick_primary_listing_url(car)
        except Exception:
            primary = None

        return (
            jsonify({"message": "Image deleted", "image_url": primary or ""}),
            200,
        )
    except Exception:
        db.session.rollback()
        return jsonify({"message": "Failed to delete image"}), 500


@bp.route("/api/cars/<car_id>/videos/<int:video_id>", methods=["DELETE"])
@jwt_required()
def delete_car_video(car_id: str, video_id: int):
    """Delete one video from a listing: removes the DB row and (best-effort)
    the underlying storage object. Owner (or admin) only; no minimum-count
    invariant -- videos are optional listing media, unlike photos."""
    try:
        current_user = get_current_user()
        verify_err = phone_verification_required_response(current_user)
        if verify_err:
            return verify_err

        car = _get_car_by_any_id(car_id)
        if not car:
            return jsonify({"message": "Car not found"}), 404
        if car.seller_id != current_user.id and not current_user.is_admin:
            return jsonify({"message": "Not authorized to modify videos for this listing"}), 403

        video = CarVideo.query.filter_by(id=video_id, car_id=car.id).first()
        if not video:
            return jsonify({"message": "Video not found on this listing"}), 404

        video_url = video.video_url
        db.session.delete(video)
        db.session.commit()

        _delete_media_storage_object(video_url)

        log_user_action(current_user, "delete_video", "car", car.public_id)
        return jsonify({"message": "Video deleted"}), 200
    except Exception:
        db.session.rollback()
        return jsonify({"message": "Failed to delete video"}), 500


@bp.route("/api/media/r2/sign-upload", methods=["POST"])
@jwt_required()
@rate_limit(max_requests=60, window_minutes=60, per_ip=False)
def r2_sign_upload():
    """
    Return a presigned PUT URL for uploading one file to R2 (image or video).
    Body: { "filename": "photo.jpg", "content_type": "image/jpeg", "asset": "image" | "video" } (optional).
    Response: { "upload_url": "<presigned PUT URL>", "key": "<object key>", "public_url": "<optional public URL>" }.
    """
    try:
        current_user = get_current_user()
        verify_err = phone_verification_required_response(current_user)
        if verify_err:
            return verify_err
    except Exception:
        return jsonify({"message": "Unauthorized"}), 401

    # H-03: disabled by default everywhere (see _presigned_upload_enabled
    # docstring) — this path bypasses the magic-byte content validation that
    # every other upload endpoint performs, and currently has no caller in
    # the shipped app. 404 (not 503) so the endpoint's existence isn't
    # distinguishable from "not configured" vs. "deliberately unavailable".
    if not _presigned_upload_enabled():
        return jsonify({"message": "Not found"}), 404

    if not _r2_configured():
        return jsonify({"message": "R2 storage is not configured"}), 503

    try:
        data = request.get_json(silent=True) or {}
        asset = (data.get("asset") or "image").strip().lower()
        raw_name = (data.get("filename") or data.get("name") or "").strip()
        if not raw_name or "/" in raw_name or "\\" in raw_name:
            raw_name = "image.jpg" if asset != "video" else "clip.mp4"
        ext = os.path.splitext(raw_name)[1].lower()

        # Owner prefix lets the seller attach this object to a listing they
        # create later, before any CarImage row exists to prove ownership.
        owner_tag = media_owner_tag(current_user.public_id)
        owner_segment = f"{owner_tag}/" if owner_tag else ""
        if asset == "video":
            if ext not in {".mp4", ".mov", ".avi", ".mkv", ".webm"}:
                ext = ".mp4"
            key = f"car_videos/{owner_segment}{secrets.token_hex(8)}{ext}"
            default_ct = _video_content_type_for_ext(ext)
            max_bytes = _R2_VIDEO_MAX_BYTES
        else:
            if ext not in {".jpg", ".jpeg", ".png", ".gif", ".webp", ".heic", ".heif"}:
                ext = ".jpg"
            key = f"car_photos/{owner_segment}{secrets.token_hex(8)}{ext}"
            default_ct = "image/jpeg"
            max_bytes = _R2_IMAGE_MAX_BYTES

        content_type = _normalize_signed_content_type(
            data.get("content_type") or "",
            asset=asset,
            default_ct=default_ct,
        )
        if not content_type:
            return jsonify({"message": "Unsupported content_type for this asset"}), 400

        # Required, not optional: ContentLength is only bound into the presigned
        # signature when we pass it to boto3. Skipping it here would let anyone
        # with a valid JWT PUT an object of any size to this key.
        raw_len = data.get("content_length")
        if raw_len is None:
            raw_len = data.get("size")
        if raw_len is None:
            return jsonify({"message": "content_length is required"}), 400
        try:
            claimed = int(raw_len)
        except (TypeError, ValueError):
            return jsonify({"message": "Invalid content_length"}), 400
        if claimed < 1 or claimed > max_bytes:
            return jsonify(
                {
                    "message": f"content_length must be between 1 and {max_bytes} bytes",
                }
            ), 400

        from ..r2_ops import r2_presign_put

        presigned_url = r2_presign_put(
            key=key,
            content_type=content_type,
            expires_in=900,
            content_length=claimed,
        )

        out = {"upload_url": presigned_url, "key": key}
        public_base = (current_app.config.get("R2_PUBLIC_URL") or "").strip()
        if public_base:
            out["public_url"] = f"{public_base.rstrip('/')}/{key}"
        return jsonify(out), 200
    except Exception as e:
        current_app.logger.warning("R2 sign-upload failed: %s", e)
        return jsonify({"message": "Failed to generate upload URL"}), 500


@bp.route("/api/media/r2/sign-video-source-upload", methods=["POST"])
@jwt_required()
@rate_limit(max_requests=30, window_minutes=60, per_ip=False)
def sign_video_source_upload():
    """
    Phase 1 of the server-side video transcode fallback: issue a short-lived
    presigned PUT URL so an authenticated seller can upload an OVERSIZED
    SOURCE video directly to temporary R2 staging, without proxying the
    bytes through this Flask process.

    This is temporary SOURCE storage only -- NOT final listing media. The
    final-listing-video cap (100MB, enforced by ``upload_car_videos()`` via
    ``validate_file_upload(max_size_mb=100)``) is completely separate and is
    NOT touched by this endpoint. A staged source object never becomes a
    listing video by itself -- this endpoint never creates a ``CarVideo``
    row, and a staged key is never visible on any listing. A later (not yet
    implemented) transcode step is what will actually consume a staged
    object and produce a real, <=100MB listing video.

    SECURITY NOTE (content validation limitation): this endpoint cannot run
    the magic-byte/codec content validation that every multipart upload
    endpoint in this file performs (``validate_file_upload`` ->
    ``sniff_bytes``), because the video bytes are PUT directly to R2 and
    this process never sees them. It only validates the CLIENT'S DECLARED
    ``content_type``/``content_length`` here (cryptographically bound into
    the presigned URL, so R2 itself rejects a PUT whose real
    Content-Type/Content-Length don't match), plus -- at finalize time --
    the object's ACTUAL size and stored content-type metadata. Neither this
    endpoint nor finalize can prove the staged bytes are a structurally
    valid, decodable video; that authoritative check only happens later, in
    the not-yet-built transcode step's ffprobe validation, before any
    decode is attempted. Callers must never treat "staged" as "verified
    playable video".

    Body: {
        "draft_media_id": "<stable per-video id chosen by the client>",
        "filename": "clip.mov",            (optional; used only to infer a default content-type)
        "content_type": "video/quicktime",
        "content_length": 123456789
    }
    Response: {
        "upload_url": "<presigned PUT URL>",
        "staging_key": "<deterministic, owner-scoped R2 key>",
        "expires_in": 900,
        "max_bytes": 524288000
    }
    """
    try:
        current_user = get_current_user()
        verify_err = phone_verification_required_response(current_user)
        if verify_err:
            return verify_err
    except Exception:
        return jsonify({"message": "Unauthorized"}), 401

    if not _video_source_staging_enabled():
        return jsonify({"message": "Not found"}), 404

    if not _r2_configured():
        return jsonify({"message": "R2 storage is not configured"}), 503

    try:
        data = request.get_json(silent=True) or {}

        draft_media_id = str(data.get("draft_media_id") or "").strip()
        if not is_valid_draft_media_id(draft_media_id):
            return jsonify({"message": "Invalid or missing draft_media_id"}), 400

        raw_name = (data.get("filename") or "").strip()
        ext = os.path.splitext(raw_name)[1].lower()
        if ext not in _ALLOWED_VIDEO_SOURCE_EXTENSIONS:
            # Only used to pick a sensible default Content-Type below -- the
            # staging key itself never varies by extension (see
            # video_source_staging_key()'s docstring for why).
            ext = ".mp4"

        content_type = _normalize_signed_content_type(
            data.get("content_type") or "",
            asset="video",
            default_ct=_video_content_type_for_ext(ext),
        )
        if not content_type:
            return jsonify({"message": "Unsupported content_type for a video upload"}), 400

        # Required, not optional -- see the identical comment on
        # r2_sign_upload() above: ContentLength is only bound into the
        # presigned signature when passed to boto3 here.
        raw_len = data.get("content_length")
        if raw_len is None:
            raw_len = data.get("size")
        if raw_len is None:
            return jsonify({"message": "content_length is required"}), 400
        try:
            claimed = int(raw_len)
        except (TypeError, ValueError):
            return jsonify({"message": "Invalid content_length"}), 400
        if claimed < 1 or claimed > _R2_VIDEO_SOURCE_STAGING_MAX_BYTES:
            return jsonify(
                {
                    "message": (
                        "content_length must be between 1 and "
                        f"{_R2_VIDEO_SOURCE_STAGING_MAX_BYTES} bytes"
                    )
                }
            ), 400

        key = video_source_staging_key(current_user.public_id, draft_media_id)
        if not key:
            return jsonify({"message": "Unable to derive a staging key"}), 400

        from ..r2_ops import r2_presign_put

        presigned_url = r2_presign_put(
            key=key,
            content_type=content_type,
            expires_in=_VIDEO_SOURCE_STAGING_URL_EXPIRES_SECONDS,
            content_length=claimed,
        )

        return jsonify(
            {
                "upload_url": presigned_url,
                "staging_key": key,
                "expires_in": _VIDEO_SOURCE_STAGING_URL_EXPIRES_SECONDS,
                "max_bytes": _R2_VIDEO_SOURCE_STAGING_MAX_BYTES,
            }
        ), 200
    except Exception as e:
        current_app.logger.warning("sign_video_source_upload failed: %s", e)
        return jsonify({"message": "Failed to generate upload URL"}), 500


@bp.route("/api/media/r2/finalize-video-source-upload", methods=["POST"])
@jwt_required()
@rate_limit(max_requests=30, window_minutes=60, per_ip=False)
def finalize_video_source_upload():
    """
    Phase 1 of the server-side video transcode fallback: verify that a
    seller's direct-to-R2 source-video upload actually completed, before
    anything downstream is allowed to treat it as staged.

    Never trusts the client: the expected key is always RECONSTRUCTED
    server-side from the authenticated caller's identity + ``draft_media_id``
    (see ``video_source_staging_key()``). If the client also supplies
    ``staging_key``, it must exactly equal the reconstructed key or the
    request is rejected -- this is what stops one seller from finalizing
    (and later having transcoded) a foreign/arbitrary key.

    Does NOT and CANNOT prove the object is a valid, decodable video -- see
    ``sign_video_source_upload()``'s docstring for the same
    content-validation limitation; only ``content_type`` metadata is
    checked here, not the actual bytes. The authoritative check happens in
    the transcode task's own ffprobe validation
    (``kk/video_transcoding.py::validate_source_media``).

    Phase 2: once the existing HEAD/ownership/size checks above succeed,
    this ALSO enqueues the server-side transcode task
    (``kk.tasks.video_tasks.transcode_car_video_source``) and registers its
    ownership (``register_job_owner``), returning the task id + a small
    job-state string.

    Idempotent enqueue (CRITICAL): repeated finalize calls for the same
    (owner, draft_media_id) must NOT enqueue a new task every time. This is
    NOT solved with an in-memory Python dict -- it reuses the smallest
    existing durable mechanism already in this codebase for exactly this
    shape of problem: the same Redis-backed store
    (``kk/job_ownership.py``'s ``_redis_client()``) that
    ``register_job_owner`` already uses for job-ownership, extended with a
    small, generic dedupe-key -> task-id mapping
    (``get_idempotent_job_task_id`` / ``register_idempotent_job_task_id``).
    This survives a web-process restart and is shared across every web
    instance, unlike an in-memory dict. No new DB model/migration was
    needed for this.

    Body: { "draft_media_id": "...", "staging_key": "..." (optional) }
    Response (200): {
        "status": "staged", "staging_key": "...", "size": <int>,
        "task_id": "...", "job_state": "queued"|"processing"|"succeeded"|"failed"
    }

    Safely idempotent: the source-verification portion only reads R2
    state; the enqueue portion returns the SAME ``task_id`` (and its
    current live state) on every repeated call for the same
    (owner, draft_media_id) instead of creating a new job.
    """
    try:
        current_user = get_current_user()
        verify_err = phone_verification_required_response(current_user)
        if verify_err:
            return verify_err
    except Exception:
        return jsonify({"message": "Unauthorized"}), 401

    if not _video_source_staging_enabled():
        return jsonify({"message": "Not found"}), 404

    if not _r2_configured():
        return jsonify({"message": "R2 storage is not configured"}), 503

    try:
        data = request.get_json(silent=True) or {}

        draft_media_id = str(data.get("draft_media_id") or "").strip()
        if not is_valid_draft_media_id(draft_media_id):
            return jsonify({"message": "Invalid or missing draft_media_id"}), 400

        # Media-readiness (optional, back-compat): binds this transcode job
        # to a manifest row registered at create_car() time (see
        # kk/media_readiness.py) so the task can self-attach on completion
        # and so submitFast()'s Phase-A signal can advance for this item.
        # Callers that omit car_id (older app builds, or any car-less use
        # of this endpoint) get EXACTLY the pre-existing behavior -- no
        # manifest lookup, no self-attach wiring.
        car_id_raw = str(data.get("car_id") or "").strip()
        car = None
        if car_id_raw:
            car = _get_car_by_any_id(car_id_raw)
            if not car:
                return jsonify({"message": "Car not found"}), 404
            if car.seller_id != current_user.id and not current_user.is_admin:
                return (
                    jsonify({"message": "Not authorized to upload video for this listing"}),
                    403,
                )

        expected_key = video_source_staging_key(current_user.public_id, draft_media_id)
        if not expected_key:
            return jsonify({"message": "Unable to derive a staging key"}), 400

        claimed_key = str(data.get("staging_key") or "").strip()
        if claimed_key and claimed_key != expected_key:
            # Never trust a client-supplied key that doesn't match the
            # server-reconstructed, owner-scoped key -- this is exactly
            # what stops one seller from finalizing another seller's (or
            # any other arbitrary/foreign) staged object.
            return (
                jsonify({"message": "staging_key does not match this draft_media_id"}),
                403,
            )

        from ..r2_ops import r2_head_object

        meta = r2_head_object(key=expected_key)
        if not meta or not meta.get("exists"):
            return (
                jsonify({"message": "Staged video not found. Has the upload finished?"}),
                404,
            )

        size = int(meta.get("size") or 0)
        if size <= 0:
            return jsonify({"message": "Staged object is empty"}), 400
        if size > _R2_VIDEO_SOURCE_STAGING_MAX_BYTES:
            return (
                jsonify(
                    {
                        "message": (
                            "Staged object exceeds the "
                            f"{_R2_VIDEO_SOURCE_STAGING_MAX_BYTES}-byte source cap"
                        )
                    }
                ),
                400,
            )

        stored_ct = (meta.get("content_type") or "").strip().lower().split(";")[0].strip()
        if stored_ct and stored_ct not in _ALLOWED_VIDEO_CONTENT_TYPES:
            return (
                jsonify({"message": "Staged object content-type is not an allowed video type"}),
                400,
            )

        # Phase 2: enqueue the transcode task, idempotently, now that the
        # staged source object is confirmed to exist/be in-bounds.
        dedupe_key = video_job_dedupe_key(current_user.public_id, draft_media_id)
        task_id = get_idempotent_job_task_id(dedupe_key)
        if not task_id:
            async_result = transcode_car_video_source.apply_async(
                kwargs={
                    "source_staging_key": expected_key,
                    "owner_public_id": current_user.public_id,
                    "draft_media_id": draft_media_id,
                    "car_id": (car.id if car is not None else None),
                },
                expires=VIDEO_TRANSCODE_TASK_EXPIRES_SECONDS,
            )
            task_id = async_result.id
            # Phase 3A durability hardening: explicit, video-specific TTL --
            # see kk/tasks/video_tasks.py::VIDEO_JOB_AUTH_TTL_SECONDS's
            # docstring for why this must be >= the processed-staging TTL
            # attach_transcoded_video() depends on, and why this does NOT
            # change either helper's own default ttl_s (used unchanged by
            # unrelated callers, e.g. the async image job registration
            # below).
            register_job_owner(task_id, current_user.public_id, ttl_s=VIDEO_JOB_AUTH_TTL_SECONDS)
            register_idempotent_job_task_id(
                dedupe_key, task_id, ttl_s=VIDEO_JOB_AUTH_TTL_SECONDS
            )

        # Media-readiness: the enqueue-durability boundary (see
        # kk/media_readiness.py) is `apply_async()` returning without
        # raising, above -- ONLY once that has happened (fresh enqueue OR
        # an already-registered task_id reused via the dedupe map, either
        # way proving the task was accepted) do we advance this manifest
        # item past "awaiting_upload". Idempotent/no-op if already advanced.
        if car is not None:
            try:
                mark_item_phase_a_accepted(
                    car_id=car.id,
                    client_media_id=draft_media_id,
                    job_task_id=task_id,
                )
            except Exception:
                current_app.logger.exception(
                    "finalize_video_source_upload: mark_item_phase_a_accepted failed"
                )

        try:
            job_state = celery_state_to_video_job_state(
                transcode_car_video_source.AsyncResult(task_id).state
            )
        except Exception:
            job_state = "queued"

        return jsonify(
            {
                "status": "staged",
                "staging_key": expected_key,
                "size": size,
                "task_id": task_id,
                "job_state": job_state,
            }
        ), 200
    except Exception as e:
        current_app.logger.warning("finalize_video_source_upload failed: %s", e)
        return jsonify({"message": "Failed to finalize staged upload"}), 500


def attach_one_transcoded_video(car: Car, *, owner_public_id: str, draft_media_id: str) -> CarVideo:
    """
    Server-side (Celery-task-driven) idempotent CarVideo attach -- the
    trusted-input, no-HTTP-round-trip counterpart of
    ``attach_transcoded_video()`` below, used by the media-readiness
    self-attach path (``kk/tasks/video_tasks.py``). Called ONLY after
    ``_transcode_video_source_impl`` has ALREADY successfully produced and
    uploaded the processed object to R2 under
    ``processed_video_staging_key(owner_public_id, draft_media_id)`` in
    THIS SAME task execution (or a prior, at-least-once-redelivered
    execution of the identical task) -- there is no client ``task_id``/job-
    state to (re-)validate here, unlike the HTTP endpoint, because this
    function IS the producer confirming its own completed work.

    Idempotent (mirrors ``attach_transcoded_video()``'s exact crash-matrix
    -- see that function's docstring for the full point-by-point reasoning,
    which applies unchanged here):
      - Checked-then-insert on ``(car_id, source_draft_media_id)``.
      - Deterministic destination key -- a retry (this task redelivered,
        or a genuinely duplicate at-least-once task) always targets the
        SAME permanent object.
      - Destination-HEAD-first skips a redundant copy when a previous
        (possibly duplicate) execution already completed it.
      - The DB unique constraint on ``(car_id, source_draft_media_id)`` is
        the final protection against two truly concurrent callers.

    Raises on any unrecoverable step (missing/oversized/wrong-type
    processed object, failed copy, failed verification) -- the caller
    (``transition_media_item_terminal``) rolls back and re-raises, which
    is deliberately treated as a TRANSIENT failure by the calling task
    (see kk/tasks/video_tasks.py): Celery's at-least-once redelivery, or a
    future run of this same task, gets another chance.

    MUST be called only from inside
    ``kk.media_readiness.transition_media_item_terminal``'s per-car
    ``SELECT ... FOR UPDATE`` lock -- it only ``flush()``es, it never
    commits. Staging-object cleanup after a successful attach is left to
    the existing ``cleanup_stale_processed_video_staging_objects`` sweep
    rather than duplicated here.
    """
    existing = CarVideo.query.filter_by(
        car_id=car.id, source_draft_media_id=draft_media_id
    ).first()
    if existing:
        return existing

    expected_key = processed_video_staging_key(owner_public_id, draft_media_id)
    if not expected_key:
        raise RuntimeError(
            "attach_one_transcoded_video: unable to derive the processed staging key"
        )

    from ..r2_ops import r2_head_object

    meta = r2_head_object(key=expected_key)
    if not meta or not meta.get("exists"):
        raise RuntimeError("attach_one_transcoded_video: processed object not found")

    size = int(meta.get("size") or 0)
    if size <= 0:
        raise RuntimeError("attach_one_transcoded_video: processed object is empty")
    if size >= vt.FINAL_MAX_BYTES:
        raise RuntimeError(
            "attach_one_transcoded_video: processed object exceeds the final size limit"
        )

    existing_count = CarVideo.query.filter_by(car_id=car.id).count()

    permanent_key = transcoded_video_permanent_key(
        owner_public_id, car.public_id, draft_media_id
    )
    if not permanent_key:
        raise RuntimeError(
            "attach_one_transcoded_video: unable to derive the permanent video key"
        )

    from ..r2_ops import r2_copy_object

    dest_meta = r2_head_object(key=permanent_key)
    dest_already_correct = bool(
        dest_meta and dest_meta.get("exists") and int(dest_meta.get("size") or 0) == size
    )
    if not dest_already_correct:
        r2_copy_object(
            source_key=expected_key, dest_key=permanent_key, content_type="video/mp4"
        )
        dest_meta = r2_head_object(key=permanent_key)
        if (
            not dest_meta
            or not dest_meta.get("exists")
            or int(dest_meta.get("size") or 0) != size
        ):
            raise RuntimeError(
                "attach_one_transcoded_video: destination verification failed after copy"
            )

    public_base = _r2_public_base()
    video_url = f"{public_base}/{permanent_key}" if public_base else permanent_key

    car_video = CarVideo(
        car_id=car.id,
        video_url=video_url,
        order=existing_count,
        source_draft_media_id=draft_media_id,
    )
    db.session.add(car_video)
    try:
        db.session.flush()
    except Exception:
        db.session.rollback()
        existing_after_race = CarVideo.query.filter_by(
            car_id=car.id, source_draft_media_id=draft_media_id
        ).first()
        if existing_after_race:
            return existing_after_race
        raise
    return car_video


@bp.route("/api/media/r2/attach-transcoded-video", methods=["POST"])
@jwt_required()
@rate_limit(max_requests=30, window_minutes=60, per_ip=False)
def attach_transcoded_video():
    """
    Phase 3A of the server-side video transcode fallback: promote a
    successful ``kk.transcode_car_video_source`` result
    (PROCESSED-video-staging object) to permanent listing-video storage and
    create the actual ``CarVideo`` row -- the final step this feature has
    been missing since Phase 2.

    Body: { "car_id": "...", "draft_media_id": "...", "task_id": "..." }
    Response (200/201): {
        "message": "...", "video": <CarVideo.to_dict()>, "videos": [<same>]
    }

    NEVER trusts a client-supplied R2 key, owner tag, file size, or
    content-type -- every one of those is either reconstructed
    server-side from the authenticated caller's identity + the request's
    ``draft_media_id``, or read back from R2 object metadata (HEAD), never
    from anything the client claims.

    Identity / task<->draft binding (no new DB/Redis schema needed): this
    reuses the EXACT existing Redis-backed idempotent-enqueue map
    (``kk/job_ownership.py``'s ``get_idempotent_job_task_id`` --
    ``video_job_dedupe_key(owner_public_id, draft_media_id)`` -> task_id).
    That mapping is populated ONLY by ``finalize_video_source_upload()``,
    ONLY when it enqueues ``kk.transcode_car_video_source`` for that EXACT
    ``(owner_public_id, draft_media_id)`` pair -- so reconstructing the
    dedupe key from THIS authenticated caller's own public_id (never a
    client-supplied owner tag) + the request's ``draft_media_id``, and
    requiring it to resolve to EXACTLY the client-supplied ``task_id``,
    proves all of: (a) ``task_id`` belongs to this caller, (b) ``task_id``
    corresponds to this specific ``draft_media_id``, and (c) ``task_id`` is
    specifically a ``kk.transcode_car_video_source`` task (nothing else
    could ever have populated that mapping). ``get_registered_job_owner``
    is also checked explicitly as defense-in-depth. The task's own
    structured SUCCESS result (which already includes ``owner_public_id``/
    ``draft_media_id`` -- see ``_transcode_video_source_impl``'s return
    value) is cross-checked ONLY as an extra safety net when present, never
    as the primary/sole proof of identity (a stronger, stored ownership
    record is always available and preferred -- see above).

    Processed-object validation (deliberately HEAD-only, no re-download/
    re-probe): the worker's own ``validate_output_media()`` (real ffprobe
    contract check -- h264/<=1920 long edge/<=30fps/yuv420p/aac-if-audio/
    <100MiB) ALREADY ran, successfully, on this exact file, BEFORE the
    worker ever uploaded it to processed staging (the upload call in
    ``_transcode_video_source_impl`` is unconditionally AFTER that
    validation passes -- there is no code path that uploads first and
    validates after). Re-downloading the (up to ~100MiB) object here and
    re-running ffprobe on it would duplicate that already-expensive check
    for no additional confidence beyond "did the object get corrupted
    after upload", which a HEAD's real, R2-reported size + content-type
    already reasonably covers -- and would add an ffmpeg/ffprobe runtime
    dependency to the WEB process that only the worker currently needs.
    This endpoint therefore only HEADs the object (exists, size in
    (0, FINAL_MAX_BYTES), content-type is ``video/mp4`` when reported --
    the transcode task always uploads with that exact content-type).

    Idempotency (CRITICAL): a repeated call for the same
    (owner, car_id, draft_media_id) must NEVER create a second ``CarVideo``
    row. This is checked FIRST, before any task/job validation -- a
    retry (timeout, app restart, lost response, duplicate tap, resume)
    with ANY task_id (even a stale/expired one) for a draft that was
    already successfully attached to this car short-circuits straight to
    returning the existing row. A DB-level unique constraint on
    ``(car_id, source_draft_media_id)`` (see the migration adding that
    column) additionally protects against two concurrent requests racing
    a plain "check then insert" -- the second commit's ``IntegrityError``
    is caught and re-resolved to the same existing-row response rather
    than erroring.

    Ordering / failure recovery (Phase 3A durability hardening -- the
    permanent key is now DETERMINISTIC, see
    ``transcoded_video_permanent_key()``, which is what makes every one of
    these crash points below safely retryable without ever accumulating an
    orphaned permanent object):

      A. Crash BEFORE the R2 copy call: nothing has happened yet -- a
         retry starts clean, from the top.
      B. Crash DURING the R2 copy (or the copy call raises): no DB row is
         created; the processed staging object is left untouched; the
         (still-in-progress or now-failed) destination write is simply
         retried from the top on the next call, targeting the SAME
         deterministic key.
      C. Crash AFTER a successful copy but BEFORE this endpoint's own
         destination-HEAD verification: a retry's destination-HEAD (now
         run FIRST, before deciding whether to copy at all -- see below)
         finds the destination already present with the correct size, so
         it skips the redundant copy entirely and proceeds straight to the
         DB insert.
      D. Crash AFTER the destination HEAD verification but BEFORE the DB
         commit: identical recovery to (C) -- the retry's own destination
         check finds the SAME deterministic key already correctly
         populated, skips re-copying, and creates the DB row. No second
         destination key is ever generated.
      E. Crash AFTER the DB commit but BEFORE the staging delete: the
         video IS already durably attached. A retry's idempotency
         short-circuit (``CarVideo`` row keyed by
         ``(car_id, source_draft_media_id)``, checked FIRST -- see above)
         finds that row immediately and returns it, regardless of whether
         the processed staging object still exists.
      F. Crash/lost-response AFTER the staging delete (or any retry that
         simply never saw the first response): same as (E) -- the
         idempotency short-circuit returns the existing row. This is the
         normal "delayed resume" case (see
         ``VIDEO_JOB_AUTH_TTL_SECONDS``'s docstring for how long the
         job/dedupe/result records this depends on stay valid).

      This endpoint therefore NEVER deletes a permanent destination object
      merely because a later step (DB commit, staging delete) failed --
      with a deterministic key, an already-correct destination is always
      safe and useful for the next retry to build on, never something to
      undo. The DB-level unique constraint on
      ``(car_id, source_draft_media_id)`` remains the final protection
      against two genuinely CONCURRENT requests both reaching the insert
      at once (see the idempotency section above) -- this ordering only
      protects against SEQUENTIAL crash-then-retry, not a true race.
    """
    try:
        current_user = get_current_user()
        verify_err = phone_verification_required_response(current_user)
        if verify_err:
            return verify_err
    except Exception:
        return jsonify({"message": "Unauthorized"}), 401

    if not _video_source_staging_enabled():
        return jsonify({"message": "Not found"}), 404

    if not _r2_configured():
        return jsonify({"message": "R2 storage is not configured"}), 503

    try:
        data = request.get_json(silent=True) or {}

        car_id_raw = str(data.get("car_id") or "").strip()
        draft_media_id = str(data.get("draft_media_id") or "").strip()
        task_id = str(data.get("task_id") or "").strip()

        if not car_id_raw:
            return jsonify({"message": "car_id is required"}), 400
        if not is_valid_draft_media_id(draft_media_id):
            return jsonify({"message": "Invalid or missing draft_media_id"}), 400
        if not is_valid_task_id(task_id):
            return jsonify({"message": "Invalid or missing task_id"}), 400

        car = _get_car_by_any_id(car_id_raw)
        if not car:
            return jsonify({"message": "Car not found"}), 404
        if car.seller_id != current_user.id and not current_user.is_admin:
            return (
                jsonify({"message": "Not authorized to attach video for this listing"}),
                403,
            )

        def _idempotent_response(existing_video: CarVideo, *, status: int):
            return (
                jsonify(
                    {
                        "message": "Video already attached",
                        "video": existing_video.to_dict(),
                        "videos": [existing_video.to_dict()],
                    }
                ),
                status,
            )

        # Idempotency short-circuit -- see docstring. Must run before ANY
        # task/job validation so a retry never depends on the supplied
        # task_id still being valid/resolvable.
        existing = CarVideo.query.filter_by(
            car_id=car.id, source_draft_media_id=draft_media_id
        ).first()
        if existing:
            return _idempotent_response(existing, status=200)

        # --- Not yet attached: validate the job before promoting anything ---

        # Defense-in-depth (see docstring -- the dedupe-key check below is
        # the primary/authoritative binding).
        registered_owner = get_registered_job_owner(task_id)
        if not registered_owner or registered_owner != current_user.public_id:
            return jsonify({"message": "task_id does not belong to this account"}), 403

        # Authoritative task_id <-> (owner, draft_media_id) binding -- see
        # docstring for why this single check also proves the task is
        # specifically kk.transcode_car_video_source.
        dedupe_key = video_job_dedupe_key(current_user.public_id, draft_media_id)
        bound_task_id = get_idempotent_job_task_id(dedupe_key)
        if not bound_task_id or bound_task_id != task_id:
            return (
                jsonify({"message": "task_id does not correspond to this draft_media_id"}),
                403,
            )

        try:
            async_result = transcode_car_video_source.AsyncResult(task_id)
            state = async_result.state
        except Exception as e:
            current_app.logger.warning("attach_transcoded_video: unable to read job state: %s", e)
            return jsonify({"message": "Unable to read transcode job state"}), 503

        if state == "FAILURE":
            return jsonify({"message": "Transcode job failed"}), 400
        if state != "SUCCESS":
            return jsonify({"message": "Transcode job has not finished yet"}), 409

        # Defense-in-depth only -- see docstring. Never the sole/authoritative
        # identity check; a missing/non-dict result never blocks the (already
        # proven, above) authoritative path.
        try:
            result_payload = async_result.result
        except Exception:
            result_payload = None
        if isinstance(result_payload, dict):
            result_owner = result_payload.get("owner_public_id")
            if result_owner is not None and result_owner != current_user.public_id:
                return (
                    jsonify({"message": "Transcode job result does not match this account"}),
                    403,
                )
            result_draft = result_payload.get("draft_media_id")
            if result_draft is not None and result_draft != draft_media_id:
                return (
                    jsonify(
                        {"message": "Transcode job result does not match this draft_media_id"}
                    ),
                    403,
                )

        # Reconstruct the expected processed key server-side -- NEVER
        # accept a client-supplied key (there isn't one in the request body
        # to begin with; this is derived purely from trusted server state).
        expected_key = processed_video_staging_key(current_user.public_id, draft_media_id)
        if not expected_key:
            return jsonify({"message": "Unable to derive the processed staging key"}), 400

        # Media/video limit -- checked AFTER the idempotency short-circuit
        # above, so a draft already attached before the listing became
        # full stays retrievable (per this endpoint's own contract).
        existing_count = CarVideo.query.filter_by(car_id=car.id).count()
        limit_err = _video_limit_error(existing_count, 1)
        if limit_err:
            return limit_err

        from ..r2_ops import r2_head_object

        meta = r2_head_object(key=expected_key)
        if not meta or not meta.get("exists"):
            return (
                jsonify({"message": "Processed video not found. Is the transcode finished?"}),
                404,
            )

        size = int(meta.get("size") or 0)
        if size <= 0:
            return jsonify({"message": "Processed video object is empty"}), 400
        if size >= vt.FINAL_MAX_BYTES:
            return (
                jsonify({"message": "Processed video exceeds the final size limit"}),
                400,
            )

        stored_ct = (meta.get("content_type") or "").strip().lower().split(";")[0].strip()
        if stored_ct and stored_ct != "video/mp4":
            # The transcode task always uploads with content_type="video/mp4"
            # explicitly -- any other reported type means this object was
            # never actually produced by that task.
            return (
                jsonify({"message": "Processed video content-type is not video/mp4"}),
                400,
            )

        # Permanent key -- Phase 3A durability hardening: DETERMINISTIC
        # (HMAC-derived from owner/car/draft_media_id), NOT a fresh random
        # token per call -- see transcoded_video_permanent_key()'s own
        # docstring. This is what makes every crash point below safely
        # retryable: a retry for the same (owner, car, draft_media_id)
        # always targets the exact same permanent object instead of
        # accumulating a new orphan on every attempt. Still lives directly
        # under the same car_videos/ namespace the normal multipart
        # upload_car_videos() endpoint uses (that endpoint's own
        # random-token scheme is UNCHANGED -- this key scheme is used ONLY
        # here).
        permanent_key = transcoded_video_permanent_key(
            current_user.public_id, car.public_id, draft_media_id
        )
        if not permanent_key:
            return jsonify({"message": "Unable to derive the permanent video key"}), 400

        from ..r2_ops import r2_copy_object

        # Crash-recovery fast path (crash points C/D below): a PREVIOUS
        # attempt may already have copied successfully to this exact same
        # deterministic key and then crashed/lost its response before the
        # DB commit. If the destination already exists with the expected
        # size, it is already correct -- skip the redundant R2 copy
        # round-trip entirely and go straight to creating the DB row.
        # Otherwise (first attempt, or a stale/mismatched leftover from a
        # differently-sized transcode of the same draft) (re-)copy so the
        # destination is freshly re-established from the current staging
        # object.
        dest_meta = r2_head_object(key=permanent_key)
        dest_already_correct = bool(
            dest_meta
            and dest_meta.get("exists")
            and int(dest_meta.get("size") or 0) == size
        )
        if not dest_already_correct:
            try:
                r2_copy_object(
                    source_key=expected_key, dest_key=permanent_key, content_type="video/mp4"
                )
            except Exception as e:
                current_app.logger.warning("attach_transcoded_video: R2 copy failed: %s", e)
                return jsonify({"message": "Failed to promote the processed video"}), 502

            dest_meta = r2_head_object(key=permanent_key)
            if (
                not dest_meta
                or not dest_meta.get("exists")
                or int(dest_meta.get("size") or 0) != size
            ):
                current_app.logger.warning(
                    "attach_transcoded_video: destination verification failed after copy "
                    "(car=%s)",
                    car.public_id,
                )
                return jsonify({"message": "Failed to verify the promoted video"}), 502

        public_base = _r2_public_base()
        video_url = f"{public_base}/{permanent_key}" if public_base else permanent_key

        car_video = CarVideo(
            car_id=car.id,
            video_url=video_url,
            order=existing_count,
            source_draft_media_id=draft_media_id,
        )
        db.session.add(car_video)
        try:
            db.session.commit()
        except Exception:
            db.session.rollback()
            # Concurrent duplicate attach for the same (car_id,
            # draft_media_id) -- the DB unique constraint protects against
            # the race a plain check-then-insert cannot. Resolve to the
            # same idempotent success response rather than erroring.
            existing_after_race = CarVideo.query.filter_by(
                car_id=car.id, source_draft_media_id=draft_media_id
            ).first()
            if existing_after_race:
                return _idempotent_response(existing_after_race, status=200)
            current_app.logger.exception("attach_transcoded_video: DB commit failed")
            return jsonify({"message": "Failed to attach video"}), 500

        log_user_action(current_user, "attach_transcoded_video", "car", car.public_id)

        # Best-effort cleanup -- never rolls back the successful attach
        # above (see docstring).
        try:
            from ..r2_ops import r2_delete_object

            r2_delete_object(key=expected_key)
        except Exception:
            current_app.logger.warning(
                "attach_transcoded_video: failed to delete processed staging object "
                "after a successful attach (car=%s); the existing "
                "cleanup_stale_processed_video_staging_objects sweep will eventually "
                "reclaim it",
                car.public_id,
            )

        return (
            jsonify(
                {
                    "message": "Video attached successfully",
                    "video": car_video.to_dict(),
                    "videos": [car_video.to_dict()],
                }
            ),
            201,
        )
    except Exception:
        db.session.rollback()
        return jsonify({"message": "Failed to attach video"}), 500


def _enqueue_async_car_image_uploads(
    files,
    *,
    current_user,
    skip_blur: bool,
    car=None,
    kind: str = "listing",
    client_media_ids=None,
):
    """
    P-01: validate + stream each file to a temp path, then enqueue the
    existing ``process_car_image_file`` Celery task (blur + downscale +
    persist) instead of running that work inline on this request thread.

    Mirrors the file-validation loop in the synchronous branch exactly
    (same size/extension/magic-byte checks via ``validate_file_upload``,
    same per-file skip-reason convention) so no upload correctness is
    lost -- only *when* the expensive blur/persist work runs changes.

    Returns a Flask response tuple: ``202`` with ``job_ids`` (and any
    per-file ``skipped`` reasons) on success, or ``400`` if every file was
    rejected before it could even be enqueued (never a fabricated success).
    """
    job_ids = []
    skip_reasons = []
    client_media_ids = list(client_media_ids or [])

    for idx, fs in enumerate(files):
        client_media_id = client_media_ids[idx] if idx < len(client_media_ids) else None
        client_media_id = (client_media_id or "").strip() or None
        if not fs or not fs.filename:
            skip_reasons.append("Missing filename")
            continue

        is_valid, msg = validate_file_upload(
            fs,
            max_size_mb=25,
            allowed_extensions=current_app.config["ALLOWED_EXTENSIONS"],
        )
        if not is_valid:
            skip_reasons.append(msg or "Invalid file")
            continue

        # TEMPORARY DEBUG TRACE (plate-blur real-device investigation --
        # safe to delete once diagnosis is complete). Hashes the exact bytes
        # this request carried for this file, before any staging/processing
        # touches them. Never logs bytes, only a digest + size. Must
        # seek(0) back afterward so stage_upload_for_async_job() below still
        # streams the full file to disk.
        try:
            _trace_raw = fs.stream.read()
            fs.stream.seek(0)
            current_app.logger.warning(
                "[BLUR TRACE SERVER] received car_id=%s client_media_id=%s "
                "skip_blur=%s input_sha256=%s input_size=%s",
                (car.id if car is not None else None),
                client_media_id,
                skip_blur,
                hashlib.sha256(_trace_raw).hexdigest(),
                len(_trace_raw),
            )
        except Exception:
            current_app.logger.exception("[BLUR TRACE SERVER] received: failed to hash input")

        filename = generate_secure_filename(fs.filename)
        # OOM-fix follow-up: stage via R2 when configured (production), since
        # carr-worker-fra runs as a separate Render service and cannot read a
        # path on this process's own disk. See
        # kk.media_processing.stage_upload_for_async_job's docstring.
        try:
            temp_abs, source_r2_key = stage_upload_for_async_job(
                fs, filename_hint=filename
            )
        except Exception:
            current_app.logger.exception(
                "_enqueue_async_car_image_uploads: failed to stage upload for Celery"
            )
            skip_reasons.append("Upload failed; please retry")
            continue

        # Media-readiness: `.delay()` is the enqueue-durability boundary
        # (see kk/media_readiness.py) -- only after the broker has
        # accepted the task (this call returns without raising) do we
        # advance the manifest item past "awaiting_upload". If `.delay()`
        # itself raises, this file's manifest item (if any) is correctly
        # left untouched at "awaiting_upload" and the caller sees a 500.
        res = process_car_image_file.delay(
            temp_abs,
            fs.filename,
            False,
            skip_blur,
            owner_public_id=current_user.public_id,
            source_r2_key=source_r2_key,
            car_id=(car.id if car is not None else None),
            kind=kind,
            client_media_id=client_media_id,
        )
        register_job_owner(res.id, current_user.public_id)
        job_ids.append(res.id)

        if car is not None and client_media_id:
            try:
                mark_item_phase_a_accepted(
                    car_id=car.id,
                    client_media_id=client_media_id,
                    job_task_id=res.id,
                )
            except Exception:
                current_app.logger.exception(
                    "_enqueue_async_car_image_uploads: mark_item_phase_a_accepted failed"
                )

    if not job_ids:
        detail = skip_reasons[0] if skip_reasons else "file type/size"
        return jsonify({"message": f"No valid images were uploaded ({detail})."}), 400

    return (
        jsonify(
            {
                "message": f"{len(job_ids)} image(s) queued for processing",
                "job_ids": job_ids,
                "skipped": skip_reasons,
            }
        ),
        202,
    )


@bp.route("/api/cars/<car_id>/images", methods=["POST"])
@jwt_required()
@rate_limit(max_requests=60, window_minutes=60, per_ip=False)
def upload_car_images(car_id: str):
    """Upload car images (accepts 'files' or 'images') and save them."""
    try:
        current_user = get_current_user()
        verify_err = phone_verification_required_response(current_user)
        if verify_err:
            return verify_err

        car = _get_car_by_any_id(car_id)
        if not car:
            return jsonify({"message": "Car not found"}), 404

        if car.seller_id != current_user.id and not current_user.is_admin:
            return jsonify({"message": "Not authorized to upload images for this listing"}), 403

        incoming_files = []
        for key in ("files", "images", "image", "upload", "file", "photo", "photos"):
            if key in request.files:
                incoming_files.extend(request.files.getlist(key))
        if not incoming_files:
            return jsonify({"message": "No image files provided"}), 400

        uploaded_images = []
        skip_reasons = []

        # Listing owners already passed auth above. Honor skip_blur=1 from the app for normal
        # uploads (no automatic plate blur). Explicit blur uses /process-car-images or /blur-image.
        skip_param = (request.args.get("skip_blur") or "").strip().lower()
        requested_skip = skip_param in ("1", "true", "yes", "y", "on")
        skip_blur = bool(requested_skip)
        upload_kind = _normalize_car_image_kind(request.args.get("kind"))
        if upload_kind == "damage":
            limit_err = _damage_photo_limit_error(
                _count_images_of_kind(car, "damage"),
                len(incoming_files),
            )
            if limit_err:
                return limit_err
        else:
            # M-06: cumulative-per-car cap on listing photos. All-or-nothing,
            # same convention as the damage-photo cap above -- a request that
            # would push this car over MAX_LISTING_PHOTOS is rejected outright
            # rather than partially accepted.
            limit_err = _listing_photo_limit_error(
                _count_listing_images(car),
                len(incoming_files),
            )
            if limit_err:
                return limit_err

        # P-01: optional async mode -- enqueue each file to the existing
        # Celery image-processing task (kk/tasks/image_tasks.py) instead of
        # running the (potentially slow, Roboflow-backed) blur+persist
        # pipeline inline on this request thread. Off by default so every
        # existing caller keeps the exact current synchronous response
        # contract unchanged; callers that opt in with `?async=1` get a 202
        # with `job_ids` back and must poll `GET /api/jobs/<task_id>`, then
        # call the existing `POST /api/cars/<car_id>/images/attach` with the
        # resulting `result.rel_path` to actually attach the processed
        # photo to this listing (reuses two already-audited endpoints
        # instead of duplicating their ownership/cap/primary-flag logic in
        # task code).
        want_async = (request.args.get("async") or "").strip().lower() in (
            "1",
            "true",
            "yes",
            "on",
        )
        if want_async:
            # Media-readiness: the caller may pass a `client_media_id` form
            # field once per file, in the SAME order as the files listed
            # above, to bind each upload to a manifest row registered at
            # `create_car()` time (see kk/media_readiness.py). Callers that
            # don't send these (e.g. adding extra photos to an existing,
            # already-ready listing) are unaffected -- car_id/client_media_id
            # simply stay unset for those files and no manifest wiring
            # happens, exactly like before this feature existed.
            client_media_ids = request.form.getlist("client_media_id")
            return _enqueue_async_car_image_uploads(
                incoming_files,
                current_user=current_user,
                skip_blur=skip_blur,
                car=car,
                kind=upload_kind,
                client_media_ids=client_media_ids,
            )

        for fs in incoming_files:
            if not fs or not fs.filename:
                skip_reasons.append("Missing filename")
                continue

            is_valid, msg = validate_file_upload(
                fs,
                max_size_mb=25,
                allowed_extensions=current_app.config["ALLOWED_EXTENSIONS"],
            )
            if not is_valid:
                skip_reasons.append(msg or "Invalid file")
                continue

            try:
                rel_path, _b64 = process_and_store_image(
                    fs,
                    inline_base64=False,
                    skip_blur=skip_blur,
                    owner_public_id=current_user.public_id,
                )
            except DecompressionBombRejected:
                # M-06: Pillow's decompression-bomb guard rejected this file.
                # Skip just this one file (same convention as an invalid file
                # above) -- never persist or return the original bytes, and
                # never leak the underlying PIL exception text to the client.
                skip_reasons.append("Image is too large or complex to process safely")
                continue
            except PlateBlurRequiredRejected:
                # M-08: PLATE_BLUR_REQUIRE_SUCCESS is enabled and this file's
                # plate-blur outcome was not confirmed safe (unconfigured,
                # Roboflow failure, or a processing/encoding failure). Skip
                # just this one file -- never persist the unconfirmed bytes,
                # and never leak the internal status/reason to the client.
                skip_reasons.append("Image could not be verified as safe to publish")
                continue
            except ImageNormalizationFailed:
                # 2026 real-device fix: the source bytes could not be
                # decoded/normalized into genuine JPEG output at all (e.g.
                # an unsupported/corrupt file). Skip just this one file --
                # never persist raw/un-normalized bytes under a `.jpg`
                # filename (the exact real-device bug this guards against).
                skip_reasons.append("Image could not be processed (unsupported or corrupt file)")
                continue
            listing_n = _count_listing_images(car)
            is_primary = upload_kind == "listing" and listing_n == 0
            car_image = CarImage(
                car_id=car.id,
                image_url=rel_path,
                is_primary=is_primary,
                kind=upload_kind,
            )
            db.session.add(car_image)
            uploaded_images.append(car_image.to_dict())

        db.session.commit()

        if not uploaded_images:
            detail = skip_reasons[0] if skip_reasons else "file type/size"
            return jsonify({"message": f"No valid images were uploaded ({detail})."}), 400

        log_user_action(current_user, "upload_images", "car", car.public_id)

        try:
            primary = _pick_primary_listing_url(car)
            if not primary and car.images:
                primary = car.images[0].image_url
        except Exception:
            primary = None

        return (
            jsonify(
                {
                    "message": f"{len(uploaded_images)} images uploaded successfully",
                    "images": [ci for ci in uploaded_images],
                    "image_url": primary or (uploaded_images[0]["image_url"] if uploaded_images else ""),
                }
            ),
            201,
        )
    except Exception as e:
        db.session.rollback()
        current_app.logger.exception("upload_car_images failed: %s", e)
        err = str(e).strip()
        lower = err.lower()
        if any(
            token in lower
            for token in (
                "too long",
                "stringdatarighttruncation",
                "value too long",
                "varying(200)",
            )
        ):
            return (
                jsonify(
                    {
                        "message": "Image URL is too long for the database. Please try again after the latest update."
                    }
                ),
                500,
            )
        if any(
            token in lower
            for token in (
                "r2",
                "upload_folder",
                "persistence",
                "s3",
                "bucket",
                "storage",
                "recursion",
            )
        ):
            return (
                jsonify(
                    {
                        "message": "Image storage is temporarily unavailable. Please try again later."
                    }
                ),
                503,
            )
        return jsonify({"message": "Failed to upload images"}), 500


def attach_processed_car_image(
    car: Car,
    *,
    kind: str,
    rel_path: str,
    source_media_id: str,
    _trace_skip_blur: bool | None = None,
    _trace_processed_sha256: str | None = None,
) -> CarImage:
    """
    Server-side (Celery-task-driven) idempotent CarImage attach -- the
    trusted-input counterpart of ``attach_car_images()`` used by the
    media-readiness self-attach path (``kk/tasks/image_tasks.py``).

    ``_trace_skip_blur``/``_trace_processed_sha256`` are TEMPORARY DEBUG-only
    parameters (plate-blur real-device investigation) -- purely for logging
    at the self-attach point, default ``None``, no effect on behavior. Safe
    to remove along with the log line below once diagnosis is complete.

    ``rel_path`` is always server-generated here (the Celery task's own
    ``persist_jpeg_bytes()`` result), never client input, so this
    deliberately skips the ownership/URL-allow-list checks
    ``attach_car_images()`` needs for client-supplied paths.

    Idempotent: checked-then-insert keyed on ``(car_id, source_media_id)``
    -- the same unique constraint added for ``CarVideo.source_draft_media_id``
    is mirrored onto ``CarImage.source_media_id`` (see the media-readiness
    migration), so a duplicate/redelivered Celery task can never create a
    second ``CarImage`` row for the same manifest item; a race that slips
    past the initial SELECT is caught via the resulting ``IntegrityError``
    and re-resolved to the existing row rather than erroring.

    MUST be called only from inside
    ``kk.media_readiness.transition_media_item_terminal``'s per-car
    ``SELECT ... FOR UPDATE`` lock -- it only ``flush()``es, it never
    commits; the caller's lock + final commit is what makes this safe
    under concurrent completions for the same car.
    """
    if _trace_skip_blur is not None or _trace_processed_sha256 is not None:
        try:
            current_app.logger.warning(
                "[BLUR TRACE SERVER] attached client_media_id=%s "
                "skip_blur_or_processing_mode=%s processed_sha256=%s final_rel_path=%s",
                source_media_id,
                _trace_skip_blur,
                _trace_processed_sha256,
                rel_path,
            )
        except Exception:
            pass

    existing = CarImage.query.filter_by(
        car_id=car.id, source_media_id=source_media_id
    ).first()
    if existing:
        return existing

    normalized_kind = _normalize_car_image_kind(kind)
    if normalized_kind == "damage":
        listing_n = _count_images_of_kind(car, "damage")
    else:
        listing_n = _count_listing_images(car)
    is_primary = normalized_kind == "listing" and listing_n == 0

    image = CarImage(
        car_id=car.id,
        image_url=rel_path,
        is_primary=is_primary,
        kind=normalized_kind,
        source_media_id=source_media_id,
    )
    db.session.add(image)
    try:
        db.session.flush()
    except Exception:
        db.session.rollback()
        existing_after_race = CarImage.query.filter_by(
            car_id=car.id, source_media_id=source_media_id
        ).first()
        if existing_after_race:
            return existing_after_race
        raise
    return image


@bp.route("/api/cars/<car_id>/images/attach", methods=["POST"])
@jwt_required()
def attach_car_images(car_id: str):
    """Attach images by relative paths (uploads/...) or full URLs (e.g. R2 public URL)."""
    try:
        current_user = get_current_user()
        verify_err = phone_verification_required_response(current_user)
        if verify_err:
            return verify_err

        car = _get_car_by_any_id(car_id)
        if not car:
            return jsonify({"message": "Car not found"}), 404

        if car.seller_id != current_user.id and not current_user.is_admin:
            return jsonify({"message": "Not authorized to attach images for this listing"}), 403

        data = request.get_json(silent=True) or {}
        paths = data.get("paths") or data.get("urls") or []
        if not isinstance(paths, list) or not paths:
            return jsonify({"message": "No image paths or URLs provided"}), 400

        attach_kind = _normalize_car_image_kind(data.get("kind"))
        if attach_kind == "damage":
            limit_err = _damage_photo_limit_error(
                _count_images_of_kind(car, "damage"),
                len(paths),
            )
            if limit_err:
                return limit_err
        else:
            # M-06: same cumulative-per-car, all-or-nothing cap as
            # upload_car_images() -- attaching already-staged images must not
            # be a way to bypass the listing-photo cap.
            limit_err = _listing_photo_limit_error(
                _count_listing_images(car),
                len(paths),
            )
            if limit_err:
                return limit_err

        attached = []
        upload_root = os.path.abspath(os.path.join(current_app.root_path, "static", "uploads"))
        # OOM-fix follow-up (item #3, media-attachment idempotency): a
        # retried/duplicated async image job (e.g. after an ambiguous
        # network failure during enqueue, OR -- media-readiness -- the
        # SAME image having already been self-attached server-side by
        # `attach_processed_car_image()` before this client-driven call
        # even runs, see `kk/tasks/image_tasks.py`) is the one case that
        # could ever ask this endpoint to attach the exact same
        # already-processed image path twice for this car. Cheap, safe
        # backstop: never add a second CarImage row for a URL/path already
        # attached to this car, regardless of kind -- a listing photo and
        # a damage photo never legitimately share the same
        # processed-image URL, so this can never accidentally suppress a
        # distinct, intentional attach.
        #
        # Media-readiness fix: the already-attached CASE must still
        # APPEND the existing row to `attached` (not skip it outright) --
        # callers (`SellListingMediaUpload._collectUploadedImageIds`) read
        # `id`s out of this response by POSITION, matched 1:1 against the
        # `paths` they sent, to drive primary-image/layout calls right
        # after. Silently omitting an already-attached row here would
        # misalign that zip and could drop id lookups for it entirely --
        # this happens on EVERY call for a client_media_id-tracked image,
        # since the self-attach above always completes (it's the same
        # Celery task, before the task is even marked SUCCESS) before the
        # client's own poll-driven call to this endpoint can land.
        existing_by_url = {img.image_url: img for img in car.images if img.image_url}
        for rel in paths:
            try:
                rel_str = str(rel or "").strip().lstrip("/").replace("\\", "/")
                # Full URL (e.g. R2 public URL): store as-is
                if rel_str.lower().startswith("http://") or rel_str.lower().startswith("https://"):
                    if not _allowed_attach_media_url(rel_str):
                        continue
                    if (
                        not current_user.is_admin
                        and not _http_url_owned_by_user(rel_str, current_user.id)
                        and not _http_url_staged_by_user(
                            rel_str, current_user.public_id
                        )
                    ):
                        continue
                    if rel_str in existing_by_url:
                        attached.append(existing_by_url[rel_str])
                        continue
                    listing_n = _count_listing_images(car)
                    is_primary = attach_kind == "listing" and listing_n == 0
                    ci = CarImage(
                        car_id=car.id,
                        image_url=rel_str,
                        is_primary=is_primary,
                        kind=attach_kind,
                    )
                    db.session.add(ci)
                    attached.append(ci)
                    existing_by_url[rel_str] = ci
                    continue
                if not rel_str.lower().startswith("uploads/"):
                    continue
                subpath = os.path.relpath(rel_str, "uploads").replace("\\", "/")
                abs_path = safe_join(upload_root, subpath)
                if not abs_path:
                    continue
                abs_path = os.path.abspath(abs_path)
                if not abs_path.startswith(upload_root + os.sep):
                    continue
                if not os.path.isfile(abs_path):
                    continue
                rel_str = f"uploads/{subpath}".replace("\\", "/")
                if rel_str in existing_by_url:
                    attached.append(existing_by_url[rel_str])
                    continue
                listing_n = _count_listing_images(car)
                is_primary = attach_kind == "listing" and listing_n == 0
                ci = CarImage(
                    car_id=car.id,
                    image_url=rel_str,
                    is_primary=is_primary,
                    kind=attach_kind,
                )
                db.session.add(ci)
                attached.append(ci)
                existing_by_url[rel_str] = ci
            except Exception:
                continue

        db.session.commit()

        try:
            primary = _pick_primary_listing_url(car)
            if not primary and car.images:
                primary = car.images[0].image_url
        except Exception:
            primary = None

        return (
            jsonify(
                {
                    "message": f"{len(attached)} images attached successfully",
                    "images": [ci.to_dict() for ci in attached],
                    "image_url": primary or ((attached[0].image_url) if attached else ""),
                }
            ),
            201,
        )
    except Exception:
        db.session.rollback()
        return jsonify({"message": "Failed to attach images"}), 500


@bp.route("/api/cars/<car_id>/videos", methods=["POST"])
@jwt_required()
@rate_limit(max_requests=20, window_minutes=60, per_ip=False)
def upload_car_videos(car_id: str):
    """Upload car videos"""
    try:
        current_user = get_current_user()
        verify_err = phone_verification_required_response(current_user)
        if verify_err:
            return verify_err

        car = _get_car_by_any_id(car_id)
        if not car:
            return jsonify({"message": "Car not found"}), 404

        if car.seller_id != current_user.id and not current_user.is_admin:
            return jsonify({"message": "Not authorized to upload videos for this listing"}), 403

        if "files" not in request.files:
            return jsonify({"message": "No files provided"}), 400

        files = request.files.getlist("files")
        uploaded_videos = []
        rejected = []

        # Media-readiness: normal (already client-compressed) video is the
        # ONE item kind whose Phase A and Phase B are the same atomic
        # request -- see kk/media_readiness.py::mark_normal_video_attached_locked.
        # `client_media_id` is optional, positional-by-index against
        # `files`, same convention as the image async-upload path above.
        client_media_ids = request.form.getlist("client_media_id")
        if client_media_ids:
            # Re-fetch with a row lock BEFORE mutating any manifest state --
            # mark_normal_video_attached_locked() requires the caller to
            # already hold this car's row lock (serializes against any
            # concurrent terminal transition/recompute for the same car).
            car = Car.query.filter_by(id=car.id).with_for_update().one()

        # Two-video regression fix (real-device evidence): when a
        # `client_media_id`-tracked normal video is re-sent -- e.g. a
        # sibling video in the same original batch was rejected, so a
        # later Phase-A/Phase-B/resume pass re-sends the WHOLE batch
        # including this already-successful video, since nothing here
        # previously let the client detect "this exact one already
        # landed" -- this endpoint used to happily create a SECOND
        # `CarVideo` row for it every time, because `source_draft_media_id`
        # was never set on the row it created (so the column's own unique
        # constraint, `uq_car_video_car_id_source_draft_media_id`, could
        # never fire). Building this lookup ONCE, up front, lets the loop
        # below skip re-uploading/re-saving any file whose id is already
        # attached, and set the column going forward so the constraint is
        # real protection, not dead weight, for every future request.
        existing_by_client_media_id: dict[str, CarVideo] = {}
        if client_media_ids:
            existing_rows = CarVideo.query.filter(
                CarVideo.car_id == car.id,
                CarVideo.source_draft_media_id.isnot(None),
            ).all()
            existing_by_client_media_id = {
                row.source_draft_media_id: row for row in existing_rows
            }

        # Section C audit fix (cross-endpoint cap consistency): this
        # endpoint used to enforce NO server-side video-count cap at all,
        # while `attach_transcoded_video()` (the server-transcode promote/
        # attach path) always enforced `MAX_LISTING_VIDEOS` via
        # `_video_limit_error(existing_count, 1)`. A listing could
        # therefore end up with more videos than the transcode path would
        # ever allow, purely depending on which of the two upload paths a
        # given video happened to take -- the SAME cap/constant/rule is
        # now applied here too, per NEW video, using the identical
        # `existing + incoming <= MAX_LISTING_VIDEOS` check. `existing_count`
        # is tracked as a running tally across this request's own loop
        # (mirroring how a second, sequential `attach_transcoded_video`
        # call for the same car would see the just-created row): only
        # videos this request is ABOUT TO CREATE count against it -- an
        # idempotent re-send of an already-attached `client_media_id`
        # (handled by the short-circuit branch below, which is checked
        # BEFORE this) never counts twice and is never itself blocked by
        # the cap, exactly matching `attach_transcoded_video()`'s own
        # "already attached stays retrievable even once the listing is
        # full" contract.
        existing_count = CarVideo.query.filter_by(car_id=car.id).count()

        for idx, f in enumerate(files):
            client_media_id = (
                client_media_ids[idx].strip()
                if idx < len(client_media_ids) and client_media_ids[idx]
                else None
            )
            if not f or not f.filename:
                continue

            if client_media_id and client_media_id in existing_by_client_media_id:
                # Already attached under this exact id (e.g. a retried
                # send of a video a sibling's earlier failure caused to
                # be re-batched) -- never re-upload/re-save it, just
                # re-report the existing row so the caller's response
                # still reflects it as present, and re-run the (idempotent
                # no-op once terminal) manifest transition for safety.
                car_video = existing_by_client_media_id[client_media_id]
                uploaded_videos.append(car_video.to_dict())
                try:
                    mark_normal_video_attached_locked(
                        car=car, client_media_id=client_media_id
                    )
                except Exception:
                    current_app.logger.exception(
                        "upload_car_videos: mark_normal_video_attached_locked "
                        "failed for already-attached video (car_id=%s "
                        "client_media_id=%s)",
                        car.id,
                        client_media_id,
                    )
                continue

            limit_err = _video_limit_error(existing_count, 1)
            if limit_err:
                rejected.append(
                    {
                        "filename": f.filename,
                        "reason": (
                            f"You can add up to {MAX_LISTING_VIDEOS} videos "
                            "per listing."
                        ),
                    }
                )
                continue

            # Some mobile pickers provide filenames without extension.
            # Infer a safe extension from MIME type so validation can pass.
            if "." not in f.filename:
                mt = (getattr(f, "mimetype", "") or "").lower()
                inferred = ""
                if "mp4" in mt:
                    inferred = ".mp4"
                elif "quicktime" in mt or "mov" in mt:
                    inferred = ".mov"
                elif "webm" in mt:
                    inferred = ".webm"
                elif "x-matroska" in mt or "mkv" in mt:
                    inferred = ".mkv"
                elif "avi" in mt:
                    inferred = ".avi"
                if inferred:
                    f.filename = f"{f.filename}{inferred}"
            is_valid, msg = validate_file_upload(
                f,
                max_size_mb=100,
                allowed_extensions=current_app.config["ALLOWED_VIDEO_EXTENSIONS"],
            )
            if not is_valid:
                rejected.append({"filename": f.filename, "reason": msg})
                continue

            if _r2_ready_for_public_object_urls():
                try:
                    stored_url = _upload_video_file_to_r2(f)
                except Exception as e:
                    current_app.logger.exception("R2 video upload failed: %s", e)
                    rejected.append(
                        {"filename": f.filename, "reason": f"R2 upload failed: {e!s}"}
                    )
                    continue
                car_video = CarVideo(
                    car_id=car.id,
                    video_url=stored_url,
                    source_draft_media_id=client_media_id,
                )
            else:
                filename = generate_secure_filename(f.filename)
                file_path = os.path.join(
                    current_app.config["UPLOAD_FOLDER"], "car_videos", filename
                )
                os.makedirs(os.path.dirname(file_path), exist_ok=True)
                f.save(file_path)
                car_video = CarVideo(
                    car_id=car.id,
                    video_url=f"uploads/car_videos/{filename}",
                    source_draft_media_id=client_media_id,
                )

            db.session.add(car_video)
            # Flush now so `car_video.id` (autoincrement PK) is populated
            # before `.to_dict()` below reads it -- without this, a
            # brand-new row's `id` in the response is always `None` (the
            # PK is only assigned by the DB on flush/commit, and
            # `.to_dict()` is a plain attribute read, never an
            # autoflush-triggering query), which would make it impossible
            # for a caller to reconcile the response against this exact
            # row (e.g. by `id`) for anything created in this call.
            db.session.flush()
            uploaded_videos.append(car_video.to_dict())
            existing_count += 1
            if client_media_id:
                existing_by_client_media_id[client_media_id] = car_video

            if client_media_id:
                try:
                    mark_normal_video_attached_locked(
                        car=car, client_media_id=client_media_id
                    )
                except Exception:
                    current_app.logger.exception(
                        "upload_car_videos: mark_normal_video_attached_locked failed "
                        "(car_id=%s client_media_id=%s)",
                        car.id,
                        client_media_id,
                    )

        if not uploaded_videos:
            db.session.rollback()
            detail = rejected[0]["reason"] if rejected else "No valid videos uploaded"
            return jsonify({"message": detail, "videos": [], "rejected": rejected}), 400

        db.session.commit()
        log_user_action(current_user, "upload_videos", "car", car.public_id)

        return jsonify(
            {
                "message": f"{len(uploaded_videos)} videos uploaded successfully",
                "videos": uploaded_videos,
                "rejected": rejected,
            }
        ), 201
    except Exception:
        db.session.rollback()
        return jsonify({"message": "Failed to upload videos"}), 500

