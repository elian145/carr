"""Pending edits ("revisions") of already-published listings.

THE RULE
    What the public sees of a listing is only ever changed by an admin
    approving an edit -- never by the seller saving one.

HOW
    When the owner edits a listing that is publicly visible (active / sold),
    the edit is written to a hidden *working copy* of that listing instead of
    the listing itself:

    * ``Car``      -- the approved, public listing. Untouched while editing.
    * working copy -- a second ``Car`` row (``status='revision'``,
      ``is_active=False``, same ``seller_id``) cloned from the approved
      listing the first time the owner edits it, together with its
      ``CarImage`` / ``CarVideo`` rows (the *rows* are cloned, the stored
      files are shared -- no bytes are copied).
    * ``CarRevision`` -- one row per listing linking the two and carrying the
      review state (``editing`` -> ``pending`` -> approved | ``rejected``).

    Because the working copy IS a ``Car``, every existing code path
    (``update_car`` field validation, the media-readiness manifest, image /
    video upload + attach + layout + cover endpoints, the Celery workers, the
    stuck-media sweeper) operates on it with no special casing -- the owner's
    requests are simply routed to it (see ``kk/routes/media.py``). The public
    can't reach it: it is inactive, has a non-public status, and every public
    query already filters on ``is_active`` / ``status``.

    On approval ``publish_revision`` copies the working copy onto the
    approved row inside one transaction: the listing keeps its id (and chats,
    favourites, analytics, the single listing fee); unchanged photos keep
    their ids; new photos are re-parented from the working copy to the
    listing; removed photos' rows are deleted and their storage objects are
    removed only if nothing else references them.

RACES
    * The admin approves exactly what they reviewed: they quote a *content
      token* (hash of the working copy's fields, gallery, media manifest and
      review state); if the owner changed anything since, the token no
      longer matches and approval fails with 409 ``stale_revision``.
    * Lock order is always approved ``Car`` -> ``CarRevision`` -> working
      copy ``Car`` (``SELECT ... FOR UPDATE``). Celery workers only ever lock
      the working copy, so they can never deadlock against a publish; after a
      publish/discard the working copy no longer exists and a late worker is
      a clean no-op (``transition_media_item_terminal`` -> ``car_missing``)
      that deletes its own now-orphaned output file.
    * Publication is blocked while any of the working copy's new media is
      still uploading/processing.

All functions here mutate the session but never ``commit()``; the caller owns
the transaction (and calls ``cleanup_unreferenced_media`` only AFTER commit).
"""

from __future__ import annotations

import hashlib
import json
import logging
import uuid
from collections import defaultdict
from datetime import datetime
from decimal import Decimal

from sqlalchemy.exc import IntegrityError

from .listing_visibility import PUBLIC_LISTING_STATUSES, listing_status_key
from .models import Car, CarImage, CarMediaItem, CarRevision, CarVideo, db
from .time_utils import utcnow

logger = logging.getLogger(__name__)

#: ``Car.status`` of a working copy. Not a member of any public / moderation
#: status set, so every status-based public query excludes it.
WORKING_COPY_STATUS = "revision"

#: Saved but not submitted. This is the state of every draft written by a
#: build that understands moderation (it sends ``X-Carnet-Review-Aware: 1``).
#: Such a draft is NEVER submitted on the seller's behalf: only the seller
#: submits it (or discards it).
REVISION_EDITING = "editing"
#: A draft created by a request WITHOUT that header, i.e. an older installed
#: build that changes photos but never sends a final submit call. It is the
#: only draft the idle sweeper may finalize (see
#: ``sweep_legacy_editing_revisions``). Sticky towards safety: any review-aware
#: request touching the revision turns it into a plain ``editing`` draft.
REVISION_EDITING_LEGACY = "editing_legacy"
REVISION_PENDING = "pending"
REVISION_REJECTED = "rejected"

#: Statuses meaning "not submitted yet".
EDITING_STATUSES = (REVISION_EDITING, REVISION_EDITING_LEGACY)

REVIEW_AWARE_HEADER = "X-Carnet-Review-Aware"


def public_revision_status(status: str | None) -> str | None:
    """Status as shown to clients/admins: the legacy marker is internal."""
    return REVISION_EDITING if status == REVISION_EDITING_LEGACY else status


def request_is_review_aware() -> bool:
    """True when the current request comes from a build that knows about
    listing-edit moderation. Outside a request (tasks, tests of the core
    logic) nothing is assumed about the client: not aware."""
    from flask import has_request_context, request

    if not has_request_context():
        return False
    return (request.headers.get(REVIEW_AWARE_HEADER) or "").strip() == "1"

#: The listing columns an owner can propose changes to; the exact set that is
#: cloned into a working copy and copied back on approval. Anything not here
#: (status, is_active, featured*, views_count, created_at, seller, ai_*,
#: media_status ...) is owned by moderation / the system and is never changed
#: by a seller edit.
PROPOSABLE_FIELDS = (
    "title",
    "title_status",
    "damaged_parts",
    "brand",
    "model",
    "trim",
    "year",
    "mileage",
    "engine_type",
    "fuel_type",
    "transmission",
    "drive_type",
    "condition",
    "body_type",
    "price",
    "currency",
    "location",
    "seating",
    "latitude",
    "longitude",
    "description",
    "color",
    "fuel_economy",
    "vin",
    "engine_size",
    "cylinder_count",
    "region_specs",
    "plate_type",
    "plate_city",
    "contact_phone",
    "contact_phones",
)

_IN_FLIGHT_ITEM_STATUSES = ("awaiting_upload", "processing")


class RevisionError(Exception):
    """A revision operation was refused. ``code`` is a stable machine-readable
    string; ``status`` the HTTP status the route should answer with."""

    def __init__(self, code: str, message: str, status: int = 409, **extra):
        super().__init__(message)
        self.code = code
        self.message = message
        self.status = status
        self.extra = extra

    def to_dict(self) -> dict:
        out = {"message": self.message, "code": self.code}
        out.update(self.extra)
        return out


# ---------------------------------------------------------------------------
# Predicates / lookups
# ---------------------------------------------------------------------------


def is_working_copy(car) -> bool:
    return (getattr(car, "status", None) or "").strip().lower() == WORKING_COPY_STATUS


def listing_is_published(car) -> bool:
    """True when the listing is publicly visible by its own state (active or
    sold, not soft-deleted). Moderation-held listings (pending / hidden /
    draft -- i.e. "Under Review") are NOT published: their edits are applied
    directly because nothing public changes and the admin will review the
    listing itself."""
    return (
        bool(getattr(car, "is_active", False))
        and not is_working_copy(car)
        and listing_status_key(car) in PUBLIC_LISTING_STATUSES
    )


def owner_edit_needs_review(car, user) -> bool:
    """True when ``user`` is the owner of a published listing, i.e. their
    edits must go to a pending revision instead of the live listing. Admins
    and other users never take this path."""
    return (
        user is not None
        and getattr(car, "seller_id", None) is not None
        and car.seller_id == user.id
        and listing_is_published(car)
    )


def get_revision(car) -> CarRevision | None:
    return CarRevision.query.filter_by(car_id=car.id).first()


def get_working_copy(revision: CarRevision | None) -> Car | None:
    if revision is None:
        return None
    return db.session.get(Car, revision.shadow_car_id)


def get_revision_for_working_copy(shadow: Car) -> CarRevision | None:
    return CarRevision.query.filter_by(shadow_car_id=shadow.id).first()


# ---------------------------------------------------------------------------
# Normalisation / comparison helpers
# ---------------------------------------------------------------------------


def _norm(value):
    if isinstance(value, Decimal):
        return format(value.quantize(Decimal("0.01")), "f")
    if isinstance(value, float):
        return round(value, 6)
    if isinstance(value, datetime):
        return value.isoformat()
    if isinstance(value, (list, tuple)):
        return [_norm(v) for v in value]
    if isinstance(value, dict):
        return {str(k): _norm(v) for k, v in value.items()}
    return value


def _copy_value(value):
    if isinstance(value, list):
        return list(value)
    if isinstance(value, dict):
        return dict(value)
    return value


def _is_listing_cover(img) -> bool:
    return bool(getattr(img, "is_primary", False)) and (
        (getattr(img, "kind", None) or "listing").strip().lower() != "damage"
    )


def _image_rows(car_id: int) -> list[CarImage]:
    rows = CarImage.query.filter_by(car_id=car_id).all()
    rows.sort(
        key=lambda i: (
            0 if _is_listing_cover(i) else 1,
            int(i.order or 0),
            int(i.id or 0),
        )
    )
    return rows


def _video_rows(car_id: int) -> list[CarVideo]:
    rows = CarVideo.query.filter_by(car_id=car_id).all()
    rows.sort(key=lambda v: (int(v.order or 0), int(v.id or 0)))
    return rows


def _image_signature(car_id: int) -> list:
    return [
        [
            i.image_url,
            (i.kind or "listing"),
            _is_listing_cover(i),
            None if i.focus_y is None else round(float(i.focus_y), 3),
        ]
        for i in _image_rows(car_id)
    ]


def _cover_url(car_id: int) -> str | None:
    """Storage URL of the listing's cover photo (None if it has none)."""
    for img in _image_rows(car_id):
        if _is_listing_cover(img):
            return img.image_url
    return None


def _video_signature(car_id: int) -> list:
    return [[v.video_url, v.thumbnail_url] for v in _video_rows(car_id)]


def revision_changed_fields(car: Car, shadow: Car) -> list[str]:
    """Which parts of the listing the revision would change (for the admin
    review UI and the "nothing changed" decision)."""
    changed = [
        f
        for f in PROPOSABLE_FIELDS
        if _norm(getattr(car, f, None)) != _norm(getattr(shadow, f, None))
    ]
    if "contact_phone" in changed:
        changed.remove("contact_phone")
        if "contact_phones" not in changed:
            changed.append("contact_phones")
    if _image_signature(car.id) != _image_signature(shadow.id):
        changed.append("images")
    if _video_signature(car.id) != _video_signature(shadow.id):
        changed.append("videos")
    return changed


def working_copy_media_state(shadow: Car) -> dict:
    """Readiness of the working copy's NEW media (its media-readiness
    manifest -- every photo/video the seller declared with the edit).

    * ``ready``      -- no declared item is still uploading / processing.
    * ``failed``     -- declared items that permanently failed. They never
      produced a photo, so the gallery silently lacks them (and, if one was
      the declared cover, another photo has been promoted in its place).
    * ``failed_cover`` -- one of the failed items was the declared cover.
    * ``approvable`` -- every declared item reached ``attached``. Approval
      requires this: a revision is published exactly as the seller declared
      it or not at all (see ``publish_revision``)."""
    items = CarMediaItem.query.filter_by(car_id=shadow.id).all()
    in_flight = sum(1 for it in items if it.status in _IN_FLIGHT_ITEM_STATUSES)
    failed_items = [it for it in items if it.status == "failed"]
    return {
        "ready": in_flight == 0,
        "in_flight": in_flight,
        "failed": len(failed_items),
        "failed_cover": any(bool(it.is_cover) for it in failed_items),
        "approvable": in_flight == 0 and not failed_items,
        "total": len(items),
    }


def revision_has_changes(car: Car, shadow: Car) -> bool:
    if revision_changed_fields(car, shadow):
        return True
    return working_copy_media_state(shadow)["total"] > 0


def revision_content_token(revision: CarRevision, shadow: Car | None = None) -> str:
    """Hash of everything an admin is asked to approve. Changes whenever the
    owner changes a field, the gallery (photos, order, cover, crop), the
    media manifest state (an upload finishing counts), or resubmits."""
    shadow = shadow or get_working_copy(revision)
    if shadow is None:
        return ""
    items = CarMediaItem.query.filter_by(car_id=shadow.id).all()
    payload = {
        "fields": {f: _norm(getattr(shadow, f, None)) for f in PROPOSABLE_FIELDS},
        "images": _image_signature(shadow.id),
        "videos": _video_signature(shadow.id),
        "items": sorted([[it.client_media_id, it.status] for it in items]),
        "status": public_revision_status(revision.status),
        "submitted_at": (
            revision.submitted_at.isoformat() if revision.submitted_at else None
        ),
    }
    raw = json.dumps(payload, sort_keys=True, separators=(",", ":"), default=str)
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()[:40]


# ---------------------------------------------------------------------------
# Locking
# ---------------------------------------------------------------------------


def _lock_car_row(car_id: int) -> Car | None:
    return (
        Car.query.filter_by(id=car_id)
        .with_for_update()
        .populate_existing()
        .one_or_none()
    )


def _lock_revision_row(revision_id: int) -> CarRevision | None:
    return (
        CarRevision.query.filter_by(id=revision_id)
        .with_for_update()
        .populate_existing()
        .one_or_none()
    )


# ---------------------------------------------------------------------------
# Working copy creation
# ---------------------------------------------------------------------------


def _clone_working_copy(car: Car) -> Car:
    shadow = Car(
        public_id=str(uuid.uuid4()),
        seller_id=car.seller_id,
        status=WORKING_COPY_STATUS,
        is_active=False,
        is_featured=False,
        media_status="ready",
        views_count=0,
        created_at=utcnow(),
        updated_at=utcnow(),
        **{f: _copy_value(getattr(car, f, None)) for f in PROPOSABLE_FIELDS},
    )
    db.session.add(shadow)
    db.session.flush()
    for img in _image_rows(car.id):
        db.session.add(
            CarImage(
                car_id=shadow.id,
                image_url=img.image_url,
                is_primary=bool(img.is_primary),
                order=img.order,
                kind=img.kind,
                focus_y=img.focus_y,
                image_width=img.image_width,
                image_height=img.image_height,
                source_media_id=img.source_media_id,
            )
        )
    for vid in _video_rows(car.id):
        db.session.add(
            CarVideo(
                car_id=shadow.id,
                video_url=vid.video_url,
                thumbnail_url=vid.thumbnail_url,
                duration=vid.duration,
                order=vid.order,
                source_draft_media_id=vid.source_draft_media_id,
            )
        )
    db.session.flush()
    db.session.expire(shadow, ["images", "videos"])
    return shadow


def ensure_revision(car: Car) -> CarRevision:
    """Return the listing's revision, creating it (and its working copy) on
    first use. Concurrent first edits serialise on the approved listing's row
    lock, so exactly one working copy is ever created.

    Does not commit: the creation becomes durable together with the
    caller's first change, and is rolled back with it on any error.
    """
    rev = get_revision(car)
    if rev is not None and get_working_copy(rev) is not None:
        _note_client_kind(rev)
        return rev

    if _lock_car_row(car.id) is None:
        raise RevisionError("listing_not_found", "Car not found", 404)
    rev = get_revision(car)  # re-check under the lock
    if rev is not None:
        if get_working_copy(rev) is not None:
            _note_client_kind(rev)
            return rev
        db.session.delete(rev)  # dangling: working copy vanished
        db.session.flush()

    try:
        shadow = _clone_working_copy(car)
        rev = CarRevision(
            car_id=car.id,
            shadow_car_id=shadow.id,
            status=(
                REVISION_EDITING
                if request_is_review_aware()
                else REVISION_EDITING_LEGACY
            ),
        )
        db.session.add(rev)
        db.session.flush()
    except IntegrityError:
        # Lost a race on a database without row locks (SQLite): the winner's
        # revision is the one to use.
        db.session.rollback()
        rev = CarRevision.query.filter_by(car_id=car.id).first()
        if rev is None:
            raise
    return rev


def _note_client_kind(revision: CarRevision) -> None:
    """A review-aware request touched a draft that was started by an older
    build (or whose client could not be told): from now on it is a normal
    draft the seller must submit themselves."""
    if revision.status == REVISION_EDITING_LEGACY and request_is_review_aware():
        revision.status = REVISION_EDITING


def note_owner_media_edit(revision: CarRevision) -> None:
    """The owner changed the working copy's media. A rejected revision goes
    back to ``editing`` (it must be explicitly resubmitted -- never
    ``editing_legacy``: nothing ever auto-submits a rejected edit); a pending
    one stays pending (its content token has changed, so a stale approval of
    the old content is refused)."""
    if revision.status == REVISION_REJECTED:
        revision.status = REVISION_EDITING
    revision.updated_at = utcnow()


def submit_revision(revision: CarRevision) -> None:
    """Mark the revision as submitted for admin review (also a resubmission
    after a rejection)."""
    revision.status = REVISION_PENDING
    revision.submitted_at = utcnow()
    revision.rejection_reason = None
    revision.reviewed_at = None
    revision.reviewed_by = None
    revision.updated_at = utcnow()


# ---------------------------------------------------------------------------
# Media id translation (approved row id -> working-copy row id)
# ---------------------------------------------------------------------------


def working_image_for_id(shadow: Car, image_id: int) -> CarImage | None:
    """Resolve an image id sent by a client to the working copy's row.

    Clients that opened the listing before the working copy existed hold the
    APPROVED row's id; the working copy's clone of that photo is found by its
    (shared) storage URL. Ids that already belong to the working copy
    resolve directly (row ids are globally unique, so there is no overlap).
    """
    direct = CarImage.query.filter_by(id=image_id, car_id=shadow.id).first()
    if direct is not None:
        return direct
    revision = get_revision_for_working_copy(shadow)
    if revision is None:
        return None
    approved = CarImage.query.filter_by(id=image_id, car_id=revision.car_id).first()
    if approved is None:
        return None
    return (
        CarImage.query.filter_by(car_id=shadow.id, image_url=approved.image_url)
        .order_by(CarImage.id.asc())
        .first()
    )


def working_video_for_id(shadow: Car, video_id: int) -> CarVideo | None:
    direct = CarVideo.query.filter_by(id=video_id, car_id=shadow.id).first()
    if direct is not None:
        return direct
    revision = get_revision_for_working_copy(shadow)
    if revision is None:
        return None
    approved = CarVideo.query.filter_by(id=video_id, car_id=revision.car_id).first()
    if approved is None:
        return None
    return (
        CarVideo.query.filter_by(car_id=shadow.id, video_url=approved.video_url)
        .order_by(CarVideo.id.asc())
        .first()
    )


# ---------------------------------------------------------------------------
# Discard
# ---------------------------------------------------------------------------


def _media_urls_of(car_id: int) -> list[str]:
    urls: list[str] = []
    for img in CarImage.query.filter_by(car_id=car_id).all():
        if img.image_url:
            urls.append(img.image_url)
    for vid in CarVideo.query.filter_by(car_id=car_id).all():
        if vid.video_url:
            urls.append(vid.video_url)
        if vid.thumbnail_url:
            urls.append(vid.thumbnail_url)
    return urls


def discard_revision(car: Car) -> list[str]:
    """Delete the listing's pending edit and its working copy (the approved
    listing is untouched). Returns the storage URLs that belonged to the
    working copy; pass them to ``cleanup_unreferenced_media`` AFTER the
    caller commits -- that deletes only files nothing else (the approved
    listing) still references.

    Safe against in-flight media jobs: with the working copy and its
    manifest gone, a late worker's attach is a no-op that removes its own
    output (see ``transition_media_item_terminal``).
    """
    rev = get_revision(car)
    if rev is None:
        return []
    _lock_car_row(car.id)
    rev = _lock_revision_row(rev.id)
    if rev is None:
        return []
    shadow_id = rev.shadow_car_id
    shadow = _lock_car_row(shadow_id)
    urls = _media_urls_of(shadow_id) if shadow is not None else []
    CarMediaItem.query.filter_by(car_id=shadow_id).delete(synchronize_session=False)
    db.session.delete(rev)
    db.session.flush()
    if shadow is not None:
        db.session.delete(shadow)
        db.session.flush()
    return urls


def cleanup_unreferenced_media(urls) -> None:
    """Best-effort storage cleanup, to be called after the transaction that
    removed the rows has COMMITTED. Never deletes an object any listing row
    (approved or working copy) still references; never raises."""
    if not urls:
        return
    try:
        from .routes.media import _delete_media_storage_object
    except Exception:
        logger.exception("cleanup_unreferenced_media: import failed")
        return
    for url in dict.fromkeys(u for u in urls if u):
        try:
            _delete_media_storage_object(url)
        except Exception:
            logger.exception("cleanup_unreferenced_media: delete failed")


# ---------------------------------------------------------------------------
# Review: approve / reject
# ---------------------------------------------------------------------------


def _load_locked_for_review(revision_id: int):
    """Take the three locks in the canonical order and return
    ``(car, revision, shadow)``."""
    probe = db.session.get(CarRevision, revision_id)
    if probe is None:
        raise RevisionError("revision_not_found", "Revision not found", 404)
    car = _lock_car_row(probe.car_id)
    rev = _lock_revision_row(revision_id)
    if rev is None or car is None:
        raise RevisionError(
            "revision_not_found", "Revision no longer exists", 404
        )
    shadow = _lock_car_row(rev.shadow_car_id)
    if shadow is None:
        db.session.delete(rev)
        db.session.flush()
        raise RevisionError(
            "revision_gone",
            "The seller's pending changes no longer exist.",
            409,
        )
    return car, rev, shadow


def _check_reviewable(car, rev, shadow, expected_token: str | None) -> str:
    if rev.status != REVISION_PENDING:
        raise RevisionError(
            "revision_not_pending",
            "These changes are not awaiting review.",
            409,
            revision_status=rev.status,
        )
    if not expected_token:
        raise RevisionError(
            "revision_token_required",
            "revision_token is required (the token of the revision you reviewed).",
            400,
        )
    current = revision_content_token(rev, shadow)
    if expected_token != current:
        raise RevisionError(
            "stale_revision",
            "The seller changed these edits after you opened them. "
            "Reload and review the latest version.",
            409,
            revision_token=current,
        )
    return current


def publish_revision(
    revision_id: int, *, expected_token: str | None, reviewer: str | None
) -> dict:
    """Approve: atomically replace the published listing's data with the
    reviewed working copy. The caller commits, then calls
    ``cleanup_unreferenced_media(result["removed_urls"])``."""
    car, rev, shadow = _load_locked_for_review(revision_id)
    _check_reviewable(car, rev, shadow, expected_token)

    if not listing_is_published(car):
        raise RevisionError(
            "listing_not_published",
            "The listing is not currently active; restore it before "
            "approving the seller's changes.",
            409,
        )
    media = working_copy_media_state(shadow)
    if not media["ready"]:
        raise RevisionError(
            "media_not_ready",
            "The seller's new photos/videos are still uploading or processing.",
            409,
            media=media,
        )
    if media["failed"]:
        # Same rule the admin gate applies to a brand-new listing
        # (`media_status != "ready"`): never publish a gallery that is
        # missing something the seller declared. Without this a failed new
        # cover would be silently replaced by whichever photo was promoted
        # on the working copy, and the public cover would change to a photo
        # the seller never chose.
        raise RevisionError(
            "media_failed",
            "One or more of the seller's new photos/videos failed to "
            "process"
            + (" (including the new cover photo)" if media["failed_cover"] else "")
            + ", so these changes cannot be approved as submitted. Reject "
            "them (the seller keeps the current listing and can resubmit) "
            "or ask the seller to discard and redo the edit.",
            409,
            media=media,
        )
    expected_cover = _cover_url(shadow.id)

    old_price = float(car.price) if car.price is not None else None
    changed = revision_changed_fields(car, shadow)

    for field in PROPOSABLE_FIELDS:
        setattr(car, field, _copy_value(getattr(shadow, field, None)))

    removed_urls = _publish_gallery(car, shadow)
    published_cover = _cover_url(car.id)
    if expected_cover is not None and published_cover != expected_cover:
        # Defence in depth: the public cover must be exactly the cover the
        # admin reviewed. Raising aborts the whole publication (the route
        # rolls the transaction back), leaving the approved listing as is.
        raise RevisionError(
            "cover_mismatch",
            "The cover photo would not match the reviewed cover; nothing was "
            "published.",
            409,
        )

    CarMediaItem.query.filter_by(car_id=shadow.id).delete(synchronize_session=False)
    db.session.delete(rev)
    db.session.flush()
    db.session.delete(shadow)
    db.session.flush()

    car.updated_at = utcnow()
    db.session.flush()
    return {
        "car": car,
        "changed_fields": changed,
        "old_price": old_price,
        "new_price": float(car.price) if car.price is not None else None,
        "removed_urls": removed_urls,
        "reviewed_by": reviewer,
    }


def _publish_gallery(car: Car, shadow: Car) -> list[str]:
    """Make the approved listing's gallery equal the working copy's. Photos
    present on both sides keep their approved row (ids are stable), take the
    working copy's order / cover / crop; new photos are re-parented; photos
    the owner removed are deleted. Returns the storage URLs of removed
    rows (candidates for cleanup after commit)."""
    from .media_readiness import ensure_one_listing_primary_locked

    removed: list[str] = []

    # --- images
    pool: dict[str, list[CarImage]] = defaultdict(list)
    for a in sorted(CarImage.query.filter_by(car_id=car.id).all(), key=lambda r: r.id):
        pool[a.image_url].append(a)
    reparent_images: list[CarImage] = []
    for s in sorted(CarImage.query.filter_by(car_id=shadow.id).all(), key=lambda r: r.id):
        bucket = pool.get(s.image_url)
        if bucket:
            a = bucket.pop(0)
            a.is_primary = bool(s.is_primary)
            a.order = s.order
            a.kind = s.kind
            a.focus_y = s.focus_y
            a.image_width = s.image_width
            a.image_height = s.image_height
        else:
            reparent_images.append(s)
    for bucket in pool.values():
        for a in bucket:
            removed.append(a.image_url)
            db.session.delete(a)
    db.session.flush()
    kept_sources = {
        r.source_media_id
        for r in CarImage.query.filter_by(car_id=car.id).all()
        if r.source_media_id
    }
    for s in reparent_images:
        if s.source_media_id and s.source_media_id in kept_sources:
            s.source_media_id = None  # unique (car_id, source_media_id)
        s.car = car
    db.session.flush()

    # --- videos
    vpool: dict[str, list[CarVideo]] = defaultdict(list)
    for a in sorted(CarVideo.query.filter_by(car_id=car.id).all(), key=lambda r: r.id):
        vpool[a.video_url].append(a)
    reparent_videos: list[CarVideo] = []
    for s in sorted(CarVideo.query.filter_by(car_id=shadow.id).all(), key=lambda r: r.id):
        bucket = vpool.get(s.video_url)
        if bucket:
            a = bucket.pop(0)
            a.order = s.order
            a.thumbnail_url = s.thumbnail_url or a.thumbnail_url
            a.duration = s.duration if s.duration is not None else a.duration
        else:
            reparent_videos.append(s)
    for bucket in vpool.values():
        for a in bucket:
            removed.append(a.video_url)
            if a.thumbnail_url:
                removed.append(a.thumbnail_url)
            db.session.delete(a)
    db.session.flush()
    kept_draft_ids = {
        r.source_draft_media_id
        for r in CarVideo.query.filter_by(car_id=car.id).all()
        if r.source_draft_media_id
    }
    for s in reparent_videos:
        if s.source_draft_media_id and s.source_draft_media_id in kept_draft_ids:
            s.source_draft_media_id = None
        s.car = car
    db.session.flush()

    ensure_one_listing_primary_locked(car)
    db.session.expire(car, ["images", "videos"])
    db.session.expire(shadow, ["images", "videos"])
    return removed


def reject_revision(
    revision_id: int,
    *,
    expected_token: str | None,
    reviewer: str | None,
    reason: str,
) -> CarRevision:
    """Reject: the approved listing stays public and untouched; the owner
    sees ``reason`` and may edit + resubmit or discard."""
    reason = (reason or "").strip()
    if not reason:
        raise RevisionError(
            "reason_required", "A rejection reason is required.", 400
        )
    car, rev, shadow = _load_locked_for_review(revision_id)
    _check_reviewable(car, rev, shadow, expected_token)
    rev.status = REVISION_REJECTED
    rev.rejection_reason = reason[:2000]
    rev.reviewed_at = utcnow()
    rev.reviewed_by = reviewer
    rev.updated_at = utcnow()
    db.session.flush()
    return rev


# ---------------------------------------------------------------------------
# Abandoned / never-submitted edits (``editing`` revisions)
# ---------------------------------------------------------------------------

#: A legacy draft untouched this long is considered finished.
EDITING_IDLE_SECONDS = 30 * 60


def legacy_draft_is_complete(shadow: Car) -> bool:
    """True only when an auto-finalized legacy draft would be a complete,
    reviewable edit: every declared photo/video is attached (none in flight,
    none failed) and the gallery is non-empty with a cover. A draft whose
    uploads failed or are still pending is NOT complete and is never
    auto-submitted."""
    if not working_copy_media_state(shadow)["approvable"]:
        return False
    if not CarImage.query.filter_by(car_id=shadow.id, kind="listing").first():
        return False
    return _cover_url(shadow.id) is not None


def sweep_idle_editing_revisions(
    *,
    idle_seconds: int = EDITING_IDLE_SECONDS,
    limit: int = 200,
) -> dict:
    """Finalize drafts left behind by OLDER installed builds -- nothing else.

    An older build changes photos (routed to the hidden working copy, never
    public) but never sends the final submit call, so its edit would sit
    invisible forever. Such drafts are marked ``editing_legacy`` when they are
    created (the request lacks ``X-Carnet-Review-Aware``). Drafts written by a
    review-aware build (``editing``) belong to the seller, who submits or
    discards them explicitly; this sweeper does not touch them at all, however
    long they sit. Per idle ``editing_legacy`` revision:

    * nothing differs from the live listing  -> discarded (nothing to lose;
      files only the working copy used are removed, shared files never);
    * differs and the draft is complete (``legacy_draft_is_complete``:
      all media attached, none failed/in flight, cover present)
                                              -> submitted for admin review;
    * differs but is incomplete (failed / unfinished uploads)
                                              -> left exactly as it is (never
      submitted, never deleted, never published).

    ``submit_revision`` only sets the status to ``pending``: the live listing
    is untouched until an admin approves. Takes the canonical lock order per
    revision.
    """
    from datetime import timedelta

    now = utcnow()
    cutoff = now - timedelta(seconds=idle_seconds)
    out = {"submitted": 0, "discarded": 0, "skipped": 0}

    ids = [
        r.id
        for r in CarRevision.query.filter(
            CarRevision.status == REVISION_EDITING_LEGACY,
            CarRevision.updated_at < cutoff,
        )
        .order_by(CarRevision.updated_at.asc())
        .limit(limit)
        .all()
    ]
    for rid in ids:
        orphan_urls: list[str] = []
        try:
            try:
                car, rev, shadow = _load_locked_for_review(rid)
            except RevisionError as e:
                if e.code == "revision_gone":
                    db.session.commit()  # dangling row removed
                else:
                    db.session.rollback()
                out["skipped"] += 1
                continue
            if (
                rev.status != REVISION_EDITING_LEGACY
                or (rev.updated_at is not None and rev.updated_at >= cutoff)
                or not listing_is_published(car)
            ):
                db.session.rollback()
                out["skipped"] += 1
                continue
            if not revision_has_changes(car, shadow):
                orphan_urls = discard_revision(car)
                out["discarded"] += 1
            elif legacy_draft_is_complete(shadow):
                submit_revision(rev)
                out["submitted"] += 1
            else:
                db.session.rollback()
                out["skipped"] += 1
                continue
            db.session.commit()
        except Exception:
            db.session.rollback()
            logger.exception("sweep_idle_editing_revisions: revision %s failed", rid)
            out["skipped"] += 1
            continue
        cleanup_unreferenced_media(orphan_urls)
    return out
