"""Administrator overrides of automated decisions.

Each action runs the same locks and the same publishing code as the manual
paths, and is logged as an event under the administrator's name. They are
intentionally few:

``approve``         publish exactly the content the run evaluated (the same
                    content-token guard as manual approval of an edit); refused
                    as ``stale`` if the seller changed it since.
``revoke``          take an auto-approved NEW listing back out of public view
                    (hidden, seller notified like any manual hide). Edits that
                    were already published cannot be rolled back here.
``require_review``  pin the listing to manual review: automation will never
                    auto-approve it (and cancels a decision still waiting to be
                    applied).
``clear_review_pin`` undo the pin.
"""

from __future__ import annotations

from .. import listing_revisions as lr
from ..models import Car, ListingModerationRun, db
from ..time_utils import utcnow
from .engine import _lock_run, _lock_subject, log_event, post_publish, publish_subject
from .subjects import Ineligible, resolve_subject


class ActionError(Exception):
    def __init__(self, code: str, message: str, status: int = 409):
        super().__init__(message)
        self.code = code
        self.message = message
        self.status = status

    def to_dict(self) -> dict:
        return {"code": self.code, "message": self.message}


def _subject_id(run: ListingModerationRun) -> int | None:
    if run.subject_type == "revision":
        return run.revision_id
    return run.car_id


def _stamp(run: ListingModerationRun, action: str, admin: str, note: str | None) -> None:
    run.override_action = action
    run.override_by = admin[:100]
    run.override_at = utcnow()
    run.override_note = (note or "").strip()[:500] or None


def approve(run_id: int, *, admin: str, note: str | None = None) -> dict:
    db.session.rollback()
    run = db.session.get(ListingModerationRun, run_id)
    if run is None:
        raise ActionError("not_found", "Run not found", 404)
    sid = _subject_id(run)
    if sid is None:
        raise ActionError("subject_gone", "The listing or edit no longer awaits approval.")
    try:
        _lock_subject(run.subject_type, sid)
        fresh = resolve_subject(run.subject_type, sid)
    except Ineligible as e:
        db.session.rollback()
        raise ActionError(e.code, "The listing or edit no longer awaits approval.")
    run = _lock_run(run_id)
    if fresh.token != run.content_token:
        db.session.rollback()
        raise ActionError(
            "stale_run",
            "The seller changed this content after the decision was made. "
            "Open the current version and review it again.",
        )
    try:
        pr = publish_subject(fresh, reviewer=admin)
    except lr.RevisionError as e:
        db.session.rollback()
        raise ActionError(e.code, e.message, e.status)
    except Ineligible as e:
        db.session.rollback()
        raise ActionError(e.code, "Media is not ready, so this cannot be approved yet.")
    run = _lock_run(run_id)
    _stamp(run, "approve", admin, note)
    run.admin_outcome = "approved"
    run.admin_outcome_at = utcnow()
    run.admin_outcome_by = admin[:100]
    log_event(run, "admin_override_approve", actor=admin, data={"note": run.override_note})
    db.session.commit()
    post_publish(pr)
    return {"message": "Approved", "car_id": pr.car_public_id}


def revoke(run_id: int, *, admin: str, note: str | None = None) -> dict:
    from ..response_cache import invalidate_filter_facets_cache
    from ..routes.admin import (
        _deliver_listing_moderation_notification,
        _queue_listing_moderation_notification,
    )

    db.session.rollback()
    run = db.session.get(ListingModerationRun, run_id)
    if run is None:
        raise ActionError("not_found", "Run not found", 404)
    if run.subject_type != "listing":
        raise ActionError(
            "revoke_not_supported",
            "An approved edit cannot be rolled back here; edit or reject the listing normally.",
        )
    if run.outcome != "published" or run.applied_at is None:
        raise ActionError("not_auto_approved", "This run did not auto-approve the listing.")
    car = Car.query.filter_by(id=run.car_id).with_for_update().populate_existing().one_or_none()
    if car is None:
        raise ActionError("subject_gone", "Listing no longer exists.", 404)
    if (car.status or "").strip().lower() != "active":
        raise ActionError("not_active", "The listing is not currently active.")
    car.status = "hidden"
    car.updated_at = utcnow()
    notification = _queue_listing_moderation_notification(car, "hidden", reason=(note or "").strip() or None)
    seller = car.seller
    run = _lock_run(run_id)
    _stamp(run, "revoke", admin, note)
    run.admin_outcome = "hidden"
    run.admin_outcome_at = utcnow()
    run.admin_outcome_by = admin[:100]
    log_event(run, "admin_override_revoke", actor=admin, data={"note": run.override_note})
    db.session.commit()
    invalidate_filter_facets_cache()
    if notification is not None and seller is not None:
        _deliver_listing_moderation_notification(notification, seller)
    return {"message": "Listing hidden"}


def require_review(run_id: int, *, admin: str, note: str | None = None, clear: bool = False) -> dict:
    db.session.rollback()
    run = db.session.get(ListingModerationRun, run_id)
    if run is None:
        raise ActionError("not_found", "Run not found", 404)
    sid = _subject_id(run)
    if sid is not None:
        try:
            _lock_subject(run.subject_type, sid)
        except Ineligible:
            db.session.rollback()
    run = _lock_run(run_id)
    if clear:
        log_event(run, "manual_only_cleared", actor=admin, data={"note": (note or "")[:500]})
        _stamp(run, "clear_review_pin", admin, note)
    else:
        log_event(run, "manual_only_pinned", actor=admin, data={"note": (note or "")[:500]})
        _stamp(run, "require_review", admin, note)
        if run.outcome == "pending_apply" and run.applied_at is None:
            run.outcome = "queued_for_review"
            log_event(run, "pending_apply_cancelled", actor=admin)
    db.session.commit()
    return {"message": "Review pin cleared" if clear else "Pinned to manual review"}
