"""Celery Beat wrapper for the media-readiness backstop sweep (see
``kk/media_readiness.py::sweep_stuck_processing_items``).

Kept as a thin task wrapper, same pattern as
``kk/tasks/image_tasks.py``/``video_tasks.py``'s own staging-cleanup
sweeps -- the actual logic lives in ``kk/media_readiness.py`` so it can be
unit-tested directly, without Celery, and is the ONLY place allowed to
write ``CarMediaItem``/``Car.media_status`` (see that module's docstring).

MANDATORY CORRECTION (see kk/media_readiness.py's own docstring on
``sweep_stuck_processing_items``): this sweep NEVER fabricates Phase-A
completion. It only ever terminal-fails a row that has ALREADY completed
Phase A (``phase_a_completed_at IS NOT NULL``) and has been stuck in
``processing`` longer than the timeout -- a lost/never-redelivered Phase-B
job. A row still at ``awaiting_upload`` with ``phase_a_completed_at IS
NULL`` (never uploaded at all) is never touched by this sweep, no matter
how much time has passed.
"""

from __future__ import annotations

import logging

from .celery_app import celery_app

logger = logging.getLogger(__name__)


@celery_app.task(name="kk.sweep_stuck_media_readiness_items")
def sweep_stuck_media_readiness_items():
    """Hourly backstop: terminal-fail any Phase-A-complete manifest item
    that has been stuck in ``processing`` for too long (lost/never-
    redelivered Phase-B job). See module docstring for what this
    deliberately never touches."""
    from ..media_readiness import sweep_stuck_processing_items

    count = sweep_stuck_processing_items()
    if count:
        logger.info(
            "sweep_stuck_media_readiness_items: marked %d stuck item(s) failed", count
        )
    return {"ok": True, "marked_failed": count}
