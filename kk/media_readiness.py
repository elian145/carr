"""
Media-readiness manifest: the ONLY module allowed to write `CarMediaItem`
rows or `Car.media_status`.

Backs the fix for the admin-approval/media race audited and designed
across several review passes (see PRODUCTION_AUDIT.md / chat history for
the full rationale). Summary of the contract this module implements:

STATE MACHINE (CarMediaItem.status):
    awaiting_upload -> processing -> attached
    awaiting_upload -> processing -> failed
    awaiting_upload -> attached                 (normal video ONLY --
                                                   upload+attach is one
                                                   atomic request)

PHASE-A COMPLETENESS is tracked SEPARATELY from `status`, via the
write-once `phase_a_completed_at` timestamp:
    - Non-NULL means: source bytes were confirmed server/R2-owned AND the
      required async job was durably accepted by the broker (or, for
      normal video, the same atomic request already attached it).
    - It is set exactly once and NEVER cleared.
    - `status` may race ahead to 'attached' or 'failed' before or after
      this is set -- `submitFast()`'s readiness check (and this module's
      `media_summary()`) reads THIS field, never `status`, so a fast
      task completion can never make Phase A appear incomplete, and a
      never-uploaded item can never appear complete just because time
      passed (see `sweep_stuck_processing_items()`'s docstring).

AT-LEAST-ONCE CORRECTNESS: Celery task delivery is at-least-once, not
exactly-once, and the Redis-backed enqueue dedupe
(`kk.job_ownership.register_idempotent_job_task_id`) is an OPTIMIZATION to
avoid duplicate compute -- never a correctness requirement. Correctness
instead comes from:
  - a stable client_media_id (unique per item, chosen by the client)
  - a DB uniqueness constraint on (car_id, client_media_id) for the
    manifest row itself, and on (car_id, source_media_id /
    source_draft_media_id) for the attached CarImage/CarVideo row
  - `transition_media_item_terminal()`'s per-car row lock, which
    serializes every terminal transition for one car so a duplicate/
    redelivered task's second attempt is always a safe no-op
  - idempotent attach functions (kk.routes.media's
    attach_processed_car_image / attach_one_transcoded_video)
  - deterministic storage keys, so two redelivered executions writing
    the "same" processed object converge rather than orphan one copy

PERMANENT vs TRANSIENT FAILURE: only a task's own classification of a
DETERMINISTIC, unrecoverable failure (corrupt/invalid source, a
decompression-bomb rejection, a mandatory plate-blur rejection, an
unsupported format after definitive validation) may call
`transition_media_item_terminal(to_status="failed")`. A transient failure
(network/R2 timeout, broker hiccup, worker restart/OOM, a transient
ffmpeg/process error) must simply raise/let Celery retry/redeliver --
never call this function -- leaving the item at 'processing' so a later
successful attempt can still reach 'attached'.
"""

from __future__ import annotations

import logging
import re
from datetime import timedelta
from typing import Callable

from .models import Car, CarMediaItem, db
from .time_utils import utcnow

logger = logging.getLogger(__name__)

# Same charset/length rule as kk.media_processing's existing
# `_DRAFT_MEDIA_ID_RE` -- shared here so both images (image_media_id) and
# videos (draft_media_id) use one validator. Deliberately bounded/safe
# even though this value is never used as a path segment in THIS module
# (kk.media_processing derives its own R2-key-safe validator separately;
# duplicated intentionally rather than importing across that boundary, to
# keep kk.media_processing free of any dependency on this module).
_CLIENT_MEDIA_ID_RE = re.compile(r"^[A-Za-z0-9_-]{1,128}$")

# Mirrors kk/routes/media.py's MAX_LISTING_PHOTOS + MAX_DAMAGE_PHOTOS /
# MAX_LISTING_VIDEOS caps -- kept as separate constants here (not imported
# from kk.routes.media) to avoid a routes -> media_readiness -> routes
# import cycle; kept numerically in sync via the comment below and the
# cross-referencing test in kk/tests/test_media_readiness_manifest.py.
MAX_EXPECTED_IMAGE_ITEMS = 30  # 20 (MAX_LISTING_PHOTOS) + 10 (MAX_DAMAGE_PHOTOS)
MAX_EXPECTED_VIDEO_ITEMS = 3  # MAX_LISTING_VIDEOS

_TERMINAL_STATUSES = ("attached", "failed")
_KINDS = ("image", "video")


def is_valid_client_media_id(value) -> bool:
    """True when `value` is a safe, bounded client-chosen media identity."""
    return bool(value) and bool(_CLIENT_MEDIA_ID_RE.match(str(value)))


class ExpectedMediaValidationError(ValueError):
    """Raised by `validate_expected_media()`; callers map this to a 400."""


def validate_expected_media(raw) -> list[dict]:
    """
    Validate the `expected_media` list from a `create_car` request body.

    Returns a de-duplicated, normalized list of
    ``{"client_media_id": str, "kind": "image"|"video"}`` dicts, or raises
    `ExpectedMediaValidationError` with a caller-safe message. `None`/
    missing input is treated as "no expected media" (empty list), not an
    error -- back-compat for any caller that never sends this field.
    """
    if raw is None:
        return []
    if not isinstance(raw, list):
        raise ExpectedMediaValidationError("expected_media must be a list")

    seen: set[str] = set()
    out: list[dict] = []
    image_count = 0
    video_count = 0
    for entry in raw:
        if not isinstance(entry, dict):
            raise ExpectedMediaValidationError(
                "Each expected_media entry must be an object"
            )
        client_media_id = str(entry.get("client_media_id") or "").strip()
        kind = str(entry.get("kind") or "").strip().lower()
        if not is_valid_client_media_id(client_media_id):
            raise ExpectedMediaValidationError(
                "Invalid or missing client_media_id in expected_media"
            )
        if kind not in _KINDS:
            raise ExpectedMediaValidationError(
                "expected_media[].kind must be 'image' or 'video'"
            )
        if client_media_id in seen:
            raise ExpectedMediaValidationError(
                "Duplicate client_media_id in expected_media"
            )
        seen.add(client_media_id)
        if kind == "image":
            image_count += 1
        else:
            video_count += 1
        out.append({"client_media_id": client_media_id, "kind": kind})

    if image_count > MAX_EXPECTED_IMAGE_ITEMS:
        raise ExpectedMediaValidationError(
            f"Too many expected images (max {MAX_EXPECTED_IMAGE_ITEMS})"
        )
    if video_count > MAX_EXPECTED_VIDEO_ITEMS:
        raise ExpectedMediaValidationError(
            f"Too many expected videos (max {MAX_EXPECTED_VIDEO_ITEMS})"
        )
    return out


def build_expected_media_items(expected_media: list[dict]) -> list[CarMediaItem]:
    """Construct (not yet added to any session) `CarMediaItem` rows.

    Caller (``create_car``) sets `.car_id` after flushing the new `Car` row
    to obtain its id, then adds these to the SAME session/transaction that
    creates the `Car` row -- see kk/routes/cars.py::create_car. Never
    called anywhere else; this is what makes "the manifest is registered
    atomically with the Car row" true.
    """
    return [
        CarMediaItem(
            kind=item["kind"],
            client_media_id=item["client_media_id"],
            status="awaiting_upload",
        )
        for item in expected_media
    ]


def _recompute_media_status_locked(car: Car) -> str:
    """Recompute `car.media_status` from the FULL current row set for this
    car. Caller MUST already hold a row lock on `car`
    (`Car.query...with_for_update()`) -- every writer in this module goes
    through that lock before calling this. Pure function of current DB
    state (never an increment/decrement), so redelivered/duplicate/
    concurrent callers always converge on the correct aggregate, never a
    stale one -- see this module's docstring."""
    rows = CarMediaItem.query.filter_by(car_id=car.id).all()
    if any(r.status == "failed" for r in rows):
        new_status = "failed"
    elif any(r.status in ("awaiting_upload", "processing") for r in rows):
        new_status = "processing"
    else:
        new_status = "ready"
    if car.media_status != new_status:
        car.media_status = new_status
        car.updated_at = utcnow()
    return new_status


def mark_item_phase_a_accepted(
    *, car_id: int, client_media_id: str, job_task_id: str | None = None
) -> None:
    """
    Non-terminal ``awaiting_upload -> processing`` transition.

    Called by the enqueue endpoint (image ``?async=1`` / video-transcode
    ``finalize``) AFTER ``.delay()`` has already returned a task id (the
    broker accepted the message) -- see the enqueue-durability rule this
    backs: the DB write happens only after the enqueue side-effect is
    already durable, so a crash between the two never leaves a committed
    'processing' row with nothing actually queued.

    Deliberately does NOT touch `Car.media_status` (already 'processing'
    since car-creation time whenever any `CarMediaItem` row exists for
    this car) and deliberately does NOT take the per-car lock -- this
    transition can never change the aggregate, so a plain guarded
    single-row UPDATE is sufficient and cheap.

    Idempotent: a retried enqueue call that finds the row already past
    'awaiting_upload' -- because a fast task completion already advanced
    it (see `transition_media_item_terminal`'s own
    `phase_a_completed_at` stamp), or because an earlier retry already
    ran -- is a no-op.
    """
    item = CarMediaItem.query.filter_by(
        car_id=car_id, client_media_id=client_media_id
    ).first()
    if item is None or item.status != "awaiting_upload":
        return
    item.status = "processing"
    if job_task_id:
        item.job_task_id = job_task_id
    if item.phase_a_completed_at is None:
        item.phase_a_completed_at = utcnow()
    item.updated_at = utcnow()
    db.session.commit()


def mark_normal_video_attached_locked(*, car: Car, client_media_id: str) -> None:
    """
    ``awaiting_upload -> attached`` in ONE step -- the only item kind
    allowed to skip `processing` entirely, because a normal
    (already client-compressed) video's multipart upload IS its attach
    (see kk/routes/media.py::upload_car_videos). Caller MUST already hold
    `car`'s row lock (`with_for_update()`) and must call this BEFORE
    committing the surrounding transaction.
    """
    item = CarMediaItem.query.filter_by(
        car_id=car.id, client_media_id=client_media_id
    ).first()
    if item is None or item.status in _TERMINAL_STATUSES:
        return
    item.status = "attached"
    if item.phase_a_completed_at is None:
        item.phase_a_completed_at = utcnow()
    item.updated_at = utcnow()
    db.session.flush()
    _recompute_media_status_locked(car)


def transition_media_item_terminal(
    *,
    car_id: int,
    client_media_id: str,
    to_status: str,
    attach_fn: Callable[[Car], None] | None = None,
) -> None:
    """
    The ONLY function allowed to move a `CarMediaItem` into a terminal
    state (``attached`` or ``failed``) for the async (image /
    server-transcode video) pipelines.

    Locks the `Car` row FIRST (``SELECT ... FOR UPDATE``) -- every
    concurrent, duplicate-enqueued, or redelivered caller for the SAME car
    serializes on this lock, which is what makes the aggregate recompute
    below race-free (see this module's docstring / the approved design's
    crash matrix).

    ``attach_fn(car)``: called ONLY for ``to_status="attached"``, INSIDE
    this same locked transaction -- must perform the actual idempotent
    ``CarImage``/``CarVideo`` insert (see
    ``kk.routes.media.attach_processed_car_image`` /
    ``attach_one_transcoded_video``). Its own unique-constraint-backed
    check-then-insert is defense-in-depth; the lock above is the primary
    guarantee against a duplicate row.

    At-least-once safe: if two executions for the SAME item both reach
    this function (duplicate `.delay()` call, or a Celery redelivery),
    whichever commits first wins; the second, once it acquires the lock,
    finds ``item.status`` already terminal and returns WITHOUT calling
    ``attach_fn`` again and WITHOUT touching `media_status` again.

    ``phase_a_completed_at`` is stamped here too (guarded by ``IS NULL``)
    -- a task reaching a terminal outcome at all is itself proof Phase A
    was completed (the job WAS durably accepted), so it is correct -- and
    necessary, to close the "fast completion races the enqueue handler's
    own write" case -- to retroactively stamp it here if nothing already
    did.

    Any exception raised by ``attach_fn`` (or anything else in this
    function) rolls back and re-raises -- callers (the Celery tasks) must
    let that propagate as an ordinary task failure for a TRANSIENT
    problem (no terminal transition happened, item stays exactly as it
    was); only a task's own classification of a PERMANENT failure should
    call this function with ``to_status="failed"`` in the first place.
    """
    if to_status not in _TERMINAL_STATUSES:
        raise ValueError(
            f"transition_media_item_terminal: invalid to_status {to_status!r}"
        )

    try:
        car = Car.query.filter_by(id=car_id).with_for_update().one_or_none()
        if car is None:
            db.session.rollback()
            return  # car deleted concurrently -- nothing to attach to

        item = CarMediaItem.query.filter_by(
            car_id=car_id, client_media_id=client_media_id
        ).one_or_none()
        if item is None:
            logger.warning(
                "transition_media_item_terminal: unknown client_media_id "
                "for car_id=%s (kind mismatch or stale caller?)",
                car_id,
            )
            db.session.rollback()
            return

        if item.status in _TERMINAL_STATUSES:
            # Already terminal -- duplicate/redelivered call. Safe no-op:
            # never re-run attach_fn, never touch media_status again.
            db.session.rollback()
            return

        if to_status == "attached" and attach_fn is not None:
            attach_fn(car)

        item.status = to_status
        if item.phase_a_completed_at is None:
            item.phase_a_completed_at = utcnow()
        item.updated_at = utcnow()
        db.session.flush()

        _recompute_media_status_locked(car)
        db.session.commit()
    except Exception:
        db.session.rollback()
        raise


def remove_expected_media_item_locked(*, car: Car, client_media_id: str) -> dict:
    """
    Phase-A cleanup: delete a `CarMediaItem` row that never completed
    Phase A (a synchronous rejection -- bad file, upload never landed).
    Caller MUST already hold `car`'s row lock.

    Idempotent: removing an already-removed/never-existent id returns
    ``{"removed": False, "reason": "not_found"}`` (never an error).

    Refuses to remove any item that has already completed Phase A
    (``processing``/``attached``/``failed`` all imply
    ``phase_a_completed_at IS NOT NULL``) -- an already-attached item, or
    one already mid/post Phase-B, is never touched by this endpoint.
    """
    item = CarMediaItem.query.filter_by(
        car_id=car.id, client_media_id=client_media_id
    ).one_or_none()
    if item is None:
        return {
            "removed": False,
            "reason": "not_found",
            "media_status": car.media_status,
        }
    if item.phase_a_completed_at is not None or item.status == "attached":
        return {
            "removed": False,
            "reason": "already_phase_a_complete",
            "media_status": car.media_status,
        }

    db.session.delete(item)
    db.session.flush()
    new_status = _recompute_media_status_locked(car)
    return {"removed": True, "media_status": new_status}


def media_summary(car: Car) -> dict:
    """
    Server-authoritative summary for Flutter's resume logic (see
    ``GET /api/cars/<id>/media-summary``). Deliberately exposes
    ``phase_a_complete`` per item (derived from `phase_a_completed_at`),
    NOT raw `status`, so the client checks exactly the field the approved
    design requires `submitFast()` to check.
    """
    items = (
        CarMediaItem.query.filter_by(car_id=car.id).order_by(CarMediaItem.id.asc()).all()
    )
    return {
        "media_status": car.media_status,
        "items": [it.to_dict() for it in items],
        "phase_a_complete": all(it.phase_a_completed_at is not None for it in items),
    }


# ---------------------------------------------------------------------------
# Backstop sweep (Celery Beat) -- see kk/tasks/media_readiness_tasks.py.
#
# MANDATORY CORRECTION: the sweep must NEVER stamp `phase_a_completed_at`
# merely because time passed. A row that is still `awaiting_upload` with
# `phase_a_completed_at IS NULL` has NEVER been confirmed server/R2-owned
# or durably enqueued -- the seller's app may simply have died before
# ever uploading it. Calling `transition_media_item_terminal` on such a
# row would (by that function's own contract) stamp
# `phase_a_completed_at`, i.e. FABRICATE Phase-A completion for an item
# that never left the seller's device. That is exactly the bug this
# correction forbids.
#
# The sweep therefore ONLY EVER targets rows where
# `phase_a_completed_at IS ALREADY NOT NULL` (Phase A genuinely completed)
# AND `status == "processing"` for longer than the timeout (a lost/never-
# redelivered Phase-B task). Calling `transition_media_item_terminal` on
# THOSE rows is correct and a no-op on `phase_a_completed_at`, since it is
# already set.
#
# A row stuck at `awaiting_upload` + `phase_a_completed_at IS NULL` is
# left exactly as-is by this sweep, forever. Resolving it is the seller's
# own responsibility (retry the same client_media_id, or call the removal
# endpoint) -- never the sweep's. If abandoned-draft cleanup is wanted for
# THAT case, it must be a separate, explicit stale-listing/stale-draft
# cleanup concern, never implemented by touching this table's Phase-A
# invariant.
# ---------------------------------------------------------------------------
STALE_PROCESSING_TIMEOUT_SECONDS = 6 * 3600  # generous vs. real job durations


def sweep_stuck_processing_items(
    *, older_than_seconds: int = STALE_PROCESSING_TIMEOUT_SECONDS
) -> int:
    """
    Marks 'failed' every `CarMediaItem` row that:
      - has ALREADY completed Phase A (`phase_a_completed_at IS NOT NULL`
        -- so this never fabricates completion for a never-uploaded item),
      - is still 'processing' (not yet terminal),
      - and has been in that state for longer than `older_than_seconds`.

    Returns the number of items marked failed. Safe to run repeatedly --
    each row it touches moves to a terminal state on its first sweep and
    is therefore excluded from every subsequent sweep's query.
    """
    cutoff = utcnow() - timedelta(seconds=older_than_seconds)
    stuck = CarMediaItem.query.filter(
        CarMediaItem.status == "processing",
        CarMediaItem.phase_a_completed_at.isnot(None),
        CarMediaItem.updated_at < cutoff,
    ).all()
    count = 0
    for stuck_item in stuck:
        transition_media_item_terminal(
            car_id=stuck_item.car_id,
            client_media_id=stuck_item.client_media_id,
            to_status="failed",
        )
        count += 1
    return count
