"""Backstop sweep: make sure every pending subject eventually has a CURRENT
decision, even if an enqueue was lost (broker blip, worker restart, a media
job that finished while the mode was off ...).

It only ever ENQUEUES ``moderate_listing`` jobs -- it never decides or
publishes. Jobs are idempotent (see ``engine``), so enqueueing a subject that
turns out to be current is a cheap no-op.

A subject is considered current when a run exists for its exact mode that
finished after the subject was last changed, and is not a retryable HOLD/ERROR
that is due.
"""

from __future__ import annotations

from datetime import timedelta

from ..models import Car, CarRevision, ListingModerationRun, db
from ..time_utils import utcnow
from .config import effective_mode, load_settings
from .engine import CLAIM_TTL_SECONDS
from .subjects import subject_key
from .triggers import request_moderation
from .. import listing_revisions as lr


def _is_current(runs: list[ListingModerationRun], changed_at, now) -> bool:
    for r in runs:
        if r.status == "evaluating":
            if r.claimed_at and now - r.claimed_at < timedelta(seconds=CLAIM_TTL_SECONDS):
                return True
            continue
        if r.status == "error":
            if r.next_retry_at and r.next_retry_at > now and (changed_at is None or r.updated_at >= changed_at):
                return True
            continue
        if r.status != "completed":
            continue
        if changed_at is not None and r.updated_at is not None and r.updated_at < changed_at:
            continue
        if r.decision != "HOLD":
            return True
        if r.next_retry_at is None or r.next_retry_at > now:
            return True
    return False


def sweep(limit: int = 100) -> dict:
    settings = load_settings()
    mode = effective_mode(settings)
    if mode == "off":
        return {"mode": mode, "enqueued": 0}
    now = utcnow()
    candidates: list[tuple[str, int, str, object]] = []

    cars = (
        Car.query.filter(
            Car.status == "pending",
            Car.is_active.is_(True),
            Car.media_status.in_(("ready", "failed")),
        )
        .order_by(Car.updated_at.asc())
        .limit(500)
        .all()
    )
    for c in cars:
        candidates.append(("listing", c.id, subject_key("listing", c.id), c.updated_at))

    revs = (
        CarRevision.query.filter(CarRevision.status == lr.REVISION_PENDING)
        .order_by(CarRevision.updated_at.asc())
        .limit(500)
        .all()
    )
    for rev in revs:
        shadow = db.session.get(Car, rev.shadow_car_id)
        if shadow is None or shadow.media_status not in ("ready", "failed"):
            continue
        changed = max(
            [t for t in (rev.updated_at, shadow.updated_at) if t is not None], default=None
        )
        candidates.append(("revision", rev.id, subject_key("revision", rev.id), changed))

    if not candidates:
        return {"mode": mode, "enqueued": 0}
    keys = [c[2] for c in candidates]
    by_key: dict[str, list[ListingModerationRun]] = {}
    for r in ListingModerationRun.query.filter(
        ListingModerationRun.subject_key.in_(keys), ListingModerationRun.mode == mode
    ).all():
        by_key.setdefault(r.subject_key, []).append(r)

    enqueued = 0
    for stype, sid, key, changed in candidates:
        if enqueued >= limit:
            break
        if _is_current(by_key.get(key, []), changed, now):
            continue
        if request_moderation(stype, sid):
            enqueued += 1
    return {"mode": mode, "enqueued": enqueued, "candidates": len(candidates)}
