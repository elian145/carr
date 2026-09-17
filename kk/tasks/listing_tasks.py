"""Celery tasks for MI-02: featured-listing expiry cleanup.

PRODUCTION_AUDIT.md MI-02: ``Car.is_featured`` never expired on its own --
once an admin flipped it on, a listing stayed featured forever. The fix's
correctness mechanism is query-time enforcement
(``Car.effective_featured_expr()`` / ``Car.is_effectively_featured``,
``kk/models.py``), which already makes an expired listing behave as
non-featured everywhere -- ordering, admin filters/counts, public
serialization -- the instant ``featured_until`` passes, independent of
whether or when this task runs.

This task is data hygiene only: it denormalizes the raw ``is_featured``
column back to ``False`` (and clears ``featured_until``) for rows that have
already expired, so nothing that happens to read the raw column directly
sees a stale ``True``. The application must remain correct between beat
runs -- and does, per the query-time enforcement above.
"""
from __future__ import annotations

import logging

from sqlalchemy import update as sql_update

from ..models import Car, db
from ..time_utils import utcnow
from .celery_app import celery_app

logger = logging.getLogger(__name__)


@celery_app.task(name="kk.tasks.listing_tasks.clear_expired_featured_listings")
def clear_expired_featured_listings() -> dict:
    """Bulk-clear `is_featured`/`featured_until` for expired listings.

    A single bulk UPDATE (no per-row Python loop, no loading Car objects
    into memory) -- there is no upper bound on how many listings could be
    expired at once. Idempotent: re-running finds nothing left to update
    once a row has been cleared (`featured_until` becomes NULL, which no
    longer matches the `isnot(None)` predicate below).
    """
    now = utcnow()
    result = db.session.execute(
        sql_update(Car)
        .where(
            Car.is_featured.is_(True),
            Car.featured_until.isnot(None),
            Car.featured_until <= now,
        )
        .values(is_featured=False, featured_until=None)
    )
    try:
        db.session.commit()
    except Exception:
        db.session.rollback()
        raise

    cleared = result.rowcount or 0
    logger.info("MI-02 cleanup: cleared %s expired featured listing(s)", cleared)
    return {"cleared": cleared}
