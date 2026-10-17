"""Record what a human did with a subject, next to what automation decided.

This is what makes shadow mode measurable: every admin approval / hide /
rejection / delete (existing endpoints, unchanged behaviour) calls
``record_admin_outcome`` AFTER its own commit. It never raises and never
affects the admin action: a failure here is logged and swallowed.

Lookup is by ``subject_key`` (a string), not by foreign key, because the
revision row is deleted when an edit is approved.
"""

from __future__ import annotations

import logging

from ..models import ListingModerationRun, db
from ..time_utils import utcnow
from .engine import log_event
from .subjects import subject_key

logger = logging.getLogger(__name__)

NEGATIVE_OUTCOMES = ("rejected", "hidden", "deleted")


def record_admin_outcome(
    *, subject_type: str, subject_id: int | None, outcome: str, admin: str | None
) -> None:
    if subject_id is None:
        return
    try:
        key = subject_key(subject_type, subject_id)
        runs = (
            ListingModerationRun.query.filter(
                ListingModerationRun.subject_key == key,
                ListingModerationRun.status == "completed",
                ListingModerationRun.admin_outcome.is_(None),
            )
            .order_by(ListingModerationRun.id.desc())
            .all()
        )
        latest_per_mode: dict[str, ListingModerationRun] = {}
        for r in runs:
            latest_per_mode.setdefault(r.mode, r)
        for r in latest_per_mode.values():
            if r.applied_at is not None and outcome == "approved":
                continue  # automation already published it
            r.admin_outcome = outcome
            r.admin_outcome_at = utcnow()
            r.admin_outcome_by = (admin or "")[:100] or None
            log_event(
                r,
                "admin_outcome",
                actor=(admin or "admin")[:100],
                data={"outcome": outcome, "decision": r.decision, "mode": r.mode},
            )
        db.session.commit()
    except Exception:
        db.session.rollback()
        logger.warning("record_admin_outcome failed", exc_info=True)


def outcome_for_status_change(old_bucket: str | None, new_bucket: str | None) -> str | None:
    """Map a status change to an outcome. ``old_bucket`` is ``'pending'`` when
    the listing was awaiting approval, else the bucket from
    ``routes.admin._car_moderation_state`` (``'active'`` / ``'hidden'``)."""
    if old_bucket == "pending" and new_bucket == "active":
        return "approved"
    if old_bucket == "pending" and new_bucket == "hidden":
        return "rejected"
    if old_bucket == "active" and new_bucket == "hidden":
        return "hidden"
    return None
