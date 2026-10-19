"""Backstop sweep: make sure every pending subject eventually has a CURRENT
decision, even if an enqueue was lost (broker blip, worker restart, a media
job that finished while the mode was off ...).

It only ever ENQUEUES ``moderate_listing`` jobs -- it never decides or
publishes. Jobs are idempotent (see ``engine``), so enqueueing a subject that
turns out to be current is a cheap no-op.

A subject is considered current when a run exists for its exact mode that
finished after the subject was last changed, and is not a retryable HOLD/ERROR
that is due. Because photo / video changes made through the media endpoints do
not touch the listing row, a bounded second pass also compares the CONTENT TOKEN
of subjects that look current with the token their decision was made for.
"""

from __future__ import annotations

import time
from datetime import timedelta

from ..models import Car, CarRevision, ListingModerationRun, db
from ..time_utils import utcnow
from .config import effective_mode, load_settings
from .engine import CLAIM_TTL_SECONDS
from .subjects import Ineligible, resolve_subject, subject_key
from .triggers import request_moderation
from .. import listing_revisions as lr

#: Content-token backstop (see ``sweep``): how many subjects that LOOK current
#: have their content token recomputed per run. Bounded so a large review queue
#: costs a fixed handful of cheap indexed reads (never an AI call) per run; the
#: window rotates, so every subject is re-checked within ``n / limit`` runs.
TOKEN_CHECK_LIMIT = 50
SWEEP_INTERVAL_SECONDS = 120  # kk/tasks/celery_app.py beat schedule


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
    looks_current: list[tuple[str, int, list[ListingModerationRun]]] = []
    for stype, sid, key, changed in candidates:
        if enqueued >= limit:
            break
        runs = by_key.get(key, [])
        if _is_current(runs, changed, now):
            if runs:
                looks_current.append((stype, sid, runs))
            continue
        if request_moderation(stype, sid):
            enqueued += 1

    # Content-token backstop. "Current" above is a TIMESTAMP judgement
    # (a run finished after the listing row last changed), but a photo
    # attached / deleted / re-ordered through a media endpoint changes the
    # content the decision is about WITHOUT touching the row. A subject whose
    # latest decision is for a different content token than it has now is
    # outdated: ask for a fresh evaluation. Bounded: a rotating window of at
    # most TOKEN_CHECK_LIMIT subjects per run, and only subjects with a
    # decision already -- a token no run has seen is the only trigger, so
    # unchanged content never costs a call (the job itself is idempotent too).
    token_checked = token_stale = 0
    if looks_current and enqueued < limit:
        looks_current.sort(key=lambda t: (t[0], t[1]))
        n = len(looks_current)
        budget = min(TOKEN_CHECK_LIMIT, n)
        start = (int(time.time() // SWEEP_INTERVAL_SECONDS) * budget) % n
        for i in range(budget):
            if enqueued >= limit:
                break
            stype, sid, runs = looks_current[(start + i) % n]
            if any(
                r.status == "evaluating"
                and r.claimed_at
                and now - r.claimed_at < timedelta(seconds=CLAIM_TTL_SECONDS)
                for r in runs
            ):
                continue  # being evaluated; the engine re-checks its own token at the end
            try:
                token = resolve_subject(stype, sid).token
            except Ineligible:
                continue
            token_checked += 1
            if any(r.content_token == token for r in runs):
                continue
            token_stale += 1
            if request_moderation(stype, sid):
                enqueued += 1
    return {
        "mode": mode,
        "enqueued": enqueued,
        "candidates": len(candidates),
        "token_checked": token_checked,
        "token_stale": token_stale,
    }
