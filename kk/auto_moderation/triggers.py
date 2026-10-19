"""Fire-and-forget enqueueing of moderation jobs.

Follows ``kk/retention_dispatch.py`` (BE-12): ``apply_async(ignore_result=True,
retry=False)`` so an unreachable broker fails fast instead of blocking the
seller's request for a minute, and a failure to enqueue is logged and swallowed
-- NEVER run inline, and never allowed to break listing creation, media
processing or an admin action. A lost trigger is harmless: the periodic sweep
(``kk.sweep_listing_moderation``) finds every pending subject that still lacks
a current decision.
"""

from __future__ import annotations

import logging

from celery.exceptions import OperationalError

logger = logging.getLogger(__name__)


def request_moderation(
    subject_type: str,
    subject_id: int,
    *,
    countdown: int | None = None,
    trigger: str = "event",
) -> bool:
    from ..tasks.moderation_tasks import moderate_listing_task

    try:
        opts = {"countdown": int(countdown)} if countdown else {}
        moderate_listing_task.apply_async(
            args=(subject_type, int(subject_id), trigger),
            ignore_result=True,
            retry=False,
            **opts,
        )
        return True
    except OperationalError as exc:
        logger.warning(
            "moderation enqueue failed for %s:%s (broker unavailable): %s",
            subject_type,
            subject_id,
            exc,
        )
    except Exception:  # pragma: no cover - defensive last resort only
        logger.exception("moderation enqueue failed for %s:%s", subject_type, subject_id)
    return False


#: A seller attaching / deleting / re-ordering photos usually does it in a burst
#: (several calls within seconds). Each call asks for a re-check, but the job is
#: delayed by this many seconds: the first job to run judges the FINAL gallery
#: and every later one finds that exact content already decided (a no-op, no AI
#: call). Without the delay a burst of N photos could cost N provider rounds.
MEDIA_CHANGE_DEBOUNCE_SECONDS = 30


def request_moderation_for_car(car_id: int | None, *, countdown: int | None = None) -> bool:
    """Called AFTER a commit that may have made a listing / pending edit
    ready for evaluation (create, media finished, edit submitted, seller
    edited a pending listing). Never raises."""
    if not car_id:
        return False
    try:
        from ..models import db
        from .config import effective_mode
        from .subjects import subject_for_car_id

        if effective_mode() == "off":
            return False
        subject = subject_for_car_id(int(car_id))
        if subject is None:
            return False
        return request_moderation(subject[0], subject[1], countdown=countdown)
    except Exception:
        try:
            from ..models import db

            db.session.rollback()
        except Exception:
            pass
        logger.warning("request_moderation_for_car failed for car %s", car_id, exc_info=True)
        return False


def request_moderation_after_media_change(car_id: int | None) -> bool:
    """Called AFTER a committed change to a listing's / pending edit's photos
    or videos made through the media endpoints (attach, upload, delete,
    cover, layout). Those endpoints change the content the decision is about
    without touching the listing row, so nothing else would notice.

    * Nothing is requested while declared media is still uploading
      (``media_status == "processing"``): unfinished uploads are never judged,
      and the upload finishing triggers the evaluation itself.
    * Only a subject that currently has one is evaluated (a new listing under
      review, or a SUBMITTED edit); a published listing's media edits live in
      a working copy and reach moderation only through the revision workflow.
    * The job is delayed (``MEDIA_CHANGE_DEBOUNCE_SECONDS``) and idempotent: a
      content token that already has a decision costs nothing.

    Never raises; a lost request is recovered by the sweep."""
    if not car_id:
        return False
    try:
        from ..models import Car, db

        status = db.session.query(Car.media_status).filter(Car.id == int(car_id)).scalar()
        if status == "processing":
            return False
        return request_moderation_for_car(car_id, countdown=MEDIA_CHANGE_DEBOUNCE_SECONDS)
    except Exception:
        try:
            from ..models import db

            db.session.rollback()
        except Exception:
            pass
        logger.warning("request_moderation_after_media_change failed for car %s", car_id, exc_info=True)
        return False


def dispatch_alert(run_id: int) -> bool:
    from ..tasks.moderation_tasks import send_moderation_alert_task

    try:
        send_moderation_alert_task.apply_async(
            args=(int(run_id),), ignore_result=True, retry=False
        )
        return True
    except Exception as exc:
        logger.warning("moderation alert enqueue failed for run %s: %s", run_id, type(exc).__name__)
        return False
