from __future__ import annotations

import os

from celery import Celery


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

    c = Celery("kk", broker=broker, backend=backend, include=["kk.tasks.image_tasks"])
    c.conf.update(
        task_serializer="json",
        accept_content=["json"],
        result_serializer="json",
        timezone="UTC",
        enable_utc=True,
        task_track_started=True,
        broker_connection_retry_on_startup=True,
    )
    return c


celery_app = make_celery()

