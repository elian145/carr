from __future__ import annotations

import os
from typing import Any

from celery import Celery, Task

# Process-local Flask app for Celery workers (P-06). Created once per process.
_flask_app: Any | None = None


def get_celery_flask_app():
    """Return a shared Flask app for this worker/process (lazy singleton)."""
    global _flask_app
    if _flask_app is None:
        from kk.app_factory import create_app

        _flask_app, *_ = create_app()
    return _flask_app


def reset_celery_flask_app_for_tests() -> None:
    """Test helper: drop the cached app so the next call rebuilds."""
    global _flask_app
    _flask_app = None


class FlaskContextTask(Task):
    """Run every task inside one shared Flask app context (no per-task create_app)."""

    abstract = True

    def __call__(self, *args, **kwargs):
        app = get_celery_flask_app()
        with app.app_context():
            return self.run(*args, **kwargs)


def make_celery() -> Celery:
    """
    Create a Celery app configured from environment variables.

    Uses REDIS_URL as both broker and result backend by default.
    """
    raw_redis = (os.environ.get("REDIS_URL") or "").strip()
    if raw_redis:
        broker = (os.environ.get("CELERY_BROKER_URL") or "").strip() or raw_redis
        backend = (os.environ.get("CELERY_RESULT_BACKEND") or "").strip() or raw_redis
    else:
        # Dev/test fallback: no external broker required. Not suitable for multi-process/production.
        broker = (os.environ.get("CELERY_BROKER_URL") or "").strip() or "memory://"
        backend = (os.environ.get("CELERY_RESULT_BACKEND") or "").strip() or "cache+memory://"

    c = Celery(
        "kk",
        broker=broker,
        backend=backend,
        include=[
            "kk.tasks.image_tasks",
            "kk.tasks.alert_tasks",
            "kk.tasks.notification_tasks",
            "kk.tasks.listing_tasks",
            "kk.tasks.video_tasks",
        ],
    )
    c.Task = FlaskContextTask
    c.conf.update(
        task_serializer="json",
        accept_content=["json"],
        result_serializer="json",
        timezone="UTC",
        enable_utc=True,
        task_track_started=True,
        broker_connection_retry_on_startup=True,
        # Phase 3A durability hardening: Celery's own default
        # ``result_expires`` (1 day) was SHORTER than the processed-video
        # staging TTL (48h -- see
        # kk/tasks/video_tasks.py::_PROCESSED_VIDEO_STAGING_STALE_AFTER_SECONDS)
        # that ``attach_transcoded_video()`` (kk/routes/media.py) depends
        # on the transcode task's own result staying readable for (it reads
        # ``AsyncResult.state``/``.result`` as part of its authorization
        # check). Raised to match
        # kk/tasks/video_tasks.py::VIDEO_JOB_AUTH_TTL_SECONDS (72h) --
        # see that constant's docstring for the full TTL-alignment
        # rationale. There is no supported per-task override for this
        # backend-wide setting, so this applies to every task's result, not
        # just the video one; a longer result TTL is a strictly safe change
        # for any task (more forgiving client-side polling, a little extra
        # Redis memory), never a correctness/security concern.
        result_expires=72 * 3600,
        # Operational hardening: carr-worker-fra runs at --concurrency=1 and
        # now includes a long-running task (video transcode, up to ~470s
        # for a legitimate worst-case source -- see
        # kk/tasks/video_tasks.py's VIDEO_TRANSCODE_FFMPEG_TIMEOUT_SECONDS).
        # Celery's default worker_prefetch_multiplier=4 would let this
        # single worker process reserve up to 4 messages from the broker
        # at once, even though it can only ever execute one at a time --
        # those reserved-but-unstarted messages sit invisible to any other
        # worker and are not released back to the queue until this worker
        # restarts, which is unnecessary and only matters for throughput
        # tuning on multi-task-at-once workers, not this one. Setting this
        # to 1 makes the worker fetch (and therefore visibly queue-block
        # other consumers on) at most one message at a time, matching its
        # actual execution concurrency. Deliberately does NOT change
        # --concurrency itself (that remains 1, set on the Render
        # startCommand, not here).
        worker_prefetch_multiplier=1,
        beat_schedule={
            "process-due-scheduled-notifications": {
                "task": "kk.tasks.notification_tasks.process_due_scheduled_notifications",
                "schedule": 60.0,  # every minute
            },
            # MI-02: data-hygiene only -- query-time enforcement
            # (Car.effective_featured_expr()) is what actually keeps expired
            # featured listings from behaving as featured; this just
            # denormalizes the raw is_featured column back to False on a
            # reasonable cadence. See kk/tasks/listing_tasks.py.
            "clear-expired-featured-listings": {
                "task": "kk.tasks.listing_tasks.clear_expired_featured_listings",
                "schedule": 3600.0,  # hourly
            },
            # OOM-fix follow-up: backstop sweep for R2 async-image-staging
            # objects abandoned by a lost/crashed job (see
            # kk/tasks/image_tasks.py::cleanup_stale_image_staging_objects).
            # Normal jobs always clean up their own staging object; this
            # only catches the rare abandoned case.
            #
            # Bugfix: this task is registered with the explicit SHORT name
            # "kk.cleanup_stale_image_staging_objects" (see the
            # @celery_app.task(name=...) decorator in image_tasks.py) --
            # unlike the sibling entries above, which use the
            # dotted-module-path form because that is the name their own
            # tasks are registered under. Beat previously sent the
            # dotted-module-path-style name here too
            # ("kk.tasks.image_tasks.cleanup_stale_image_staging_objects"),
            # which was never a registered task name, so the worker logged
            # "Received unregistered task of type ...". Must exactly match
            # the registered name, not the module path.
            "cleanup-stale-image-staging-objects": {
                "task": "kk.cleanup_stale_image_staging_objects",
                "schedule": 3600.0,  # hourly
            },
            # Phase 1 of the server-side video transcode fallback: backstop
            # sweep for R2 source-video-staging objects abandoned before
            # (or after) finalize (see
            # kk/tasks/video_tasks.py::cleanup_stale_video_staging_objects
            # and kk/media_processing.py::VIDEO_SOURCE_STAGING_KEY_PREFIX).
            # Registered name and this schedule's "task" string are written
            # identically on purpose -- see that task's own docstring for
            # why (the sibling image-staging entry above was just fixed for
            # exactly this kind of mismatch).
            "cleanup-stale-video-staging-objects": {
                "task": "kk.cleanup_stale_video_staging_objects",
                "schedule": 3600.0,  # hourly sweep; see video_tasks.py for the (now 24h) stale-age threshold
            },
            # Phase 2 of the server-side video transcode fallback: backstop
            # sweep for R2 PROCESSED-video-staging objects abandoned before
            # a (not-yet-implemented) Phase 3 attach step consumes them
            # (see kk/tasks/video_tasks.py::cleanup_stale_processed_video_staging_objects
            # and kk/media_processing.py::PROCESSED_VIDEO_STAGING_KEY_PREFIX).
            # Same "registered name == Beat 'task' string" precaution as
            # its Phase 1 sibling immediately above.
            "cleanup-stale-processed-video-staging-objects": {
                "task": "kk.cleanup_stale_processed_video_staging_objects",
                "schedule": 3600.0,  # hourly sweep; see video_tasks.py for the 48h stale-age threshold
            },
        },
    )
    return c


celery_app = make_celery()
