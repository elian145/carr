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
        beat_schedule={
            "process-due-scheduled-notifications": {
                "task": "kk.tasks.notification_tasks.process_due_scheduled_notifications",
                "schedule": 60.0,  # every minute
            },
        },
    )
    return c


celery_app = make_celery()
