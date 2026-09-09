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


@celery_app.task(name="kk.tasks.notification_tasks.send_immediate_broadcast")
def send_immediate_broadcast_task(row_id: int):
    """BE-04: send a single "send now" admin broadcast off the HTTP request
    thread.

    ``row_id`` refers to a ScheduledNotification row created by
    ``create_immediate_broadcast_row()`` (``scheduled_at=utcnow()``) or
    claimed ahead of time by ``claim_due_scheduled_notifications()`` (the
    manual "process due" admin action). Either way, the actual claim
    (BE-03's atomic conditional UPDATE) happens inside
    ``process_scheduled_notification_by_id()``, so this task is safe to
    enqueue even if beat's own periodic sweep (or another enqueue of this
    same task) is racing to process the same row -- only one of them will
    win the claim and actually broadcast.
    """
    from ..notification_broadcast import process_scheduled_notification_by_id

    result = process_scheduled_notification_by_id(row_id)
    logger.info("immediate broadcast row %s processed: %s", row_id, result)
    return result
