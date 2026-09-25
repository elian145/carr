"""Phase 1 follow-up: Celery Beat backstop cleanup for abandoned SOURCE
video staging objects.

See ``kk/media_processing.py::video_source_staging_key`` and
``kk/routes/media.py``'s ``sign_video_source_upload`` /
``finalize_video_source_upload`` endpoints for the rest of Phase 1 (secure
direct-to-R2 source-video staging).

This module does NOT perform any video transcoding. It only deletes stale
staging objects under ``VIDEO_SOURCE_STAGING_KEY_PREFIX`` -- mirroring
``kk.tasks.image_tasks.cleanup_stale_image_staging_objects`` exactly (same
6-hour backstop convention, same ``r2_cleanup_stale_staging()`` call). As of
Phase 1 there is no transcode consumer yet, so this sweep is the ONLY
cleanup path for these objects (a normal, successfully-finalized upload has
no automatic follow-up deletion yet -- that will be added alongside the
transcode consumer in a later phase).
"""

from __future__ import annotations

import logging

from .celery_app import celery_app

logger = logging.getLogger(__name__)

# 6h matches the image-staging sweep's own convention/rationale exactly
# (see kk.tasks.image_tasks.cleanup_stale_image_staging_objects's
# docstring): real uploads should finish in well under this, so anything
# still present after 6 hours is safely assumed abandoned, not merely slow.
_VIDEO_STAGING_STALE_AFTER_SECONDS = 6 * 3600


@celery_app.task(name="kk.cleanup_stale_video_staging_objects")
def cleanup_stale_video_staging_objects():
    """Backstop sweep for abandoned R2 source-video-staging objects.

    Registered under the exact SHORT name Celery Beat schedules it by (see
    ``kk/tasks/celery_app.py``'s ``beat_schedule``) -- the Beat task-name
    mismatch that broke the sibling image-staging sweep
    (registered name did not match the string Beat sent) was fixed
    independently just before this task was added; this task's name and
    its Beat schedule entry are deliberately written identically from the
    start to avoid repeating that bug.
    """
    from flask import current_app

    from ..media_processing import VIDEO_SOURCE_STAGING_KEY_PREFIX, _r2_configured

    if not _r2_configured():
        return {"ok": True, "deleted": 0, "skipped": "r2_not_configured"}

    from ..r2_ops import r2_cleanup_stale_staging

    deleted = r2_cleanup_stale_staging(
        prefix=VIDEO_SOURCE_STAGING_KEY_PREFIX,
        older_than_seconds=_VIDEO_STAGING_STALE_AFTER_SECONDS,
    )
    if deleted:
        current_app.logger.info(
            "cleanup_stale_video_staging_objects: deleted %d stale staging object(s)",
            deleted,
        )
    return {"ok": True, "deleted": deleted}
