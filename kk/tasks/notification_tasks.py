"""Celery tasks for scheduled admin notifications."""

from __future__ import annotations

import logging

from .celery_app import celery_app

logger = logging.getLogger(__name__)


@celery_app.task(name="kk.tasks.notification_tasks.process_due_scheduled_notifications")
def process_due_scheduled_notifications_task(limit: int = 20):
    from ..notification_broadcast import process_due_scheduled_notifications

    result = process_due_scheduled_notifications(limit=limit)
    logger.info("scheduled notifications processed: %s", result)
    return result
