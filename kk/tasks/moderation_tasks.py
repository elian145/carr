"""Celery tasks for automated listing moderation (see ``kk/auto_moderation``).

Thin wrappers: the logic lives in ``kk/auto_moderation`` so it can be tested
without Celery. Delivery is at-least-once and the work is idempotent, so a
duplicated or re-delivered ``kk.moderate_listing`` finds the existing decision
(``(subject, content token, mode)`` is unique) instead of deciding twice.
A message lost with a worker is recovered by ``kk.sweep_listing_moderation``.
"""

from __future__ import annotations

import logging

from .celery_app import celery_app

logger = logging.getLogger(__name__)


@celery_app.task(name="kk.moderate_listing", soft_time_limit=150, time_limit=200)
def moderate_listing_task(subject_type: str, subject_id: int, trigger: str = "event"):
    """Evaluate one new listing (``listing``) or one submitted edit
    (``revision``). Never raises for a moderation outcome; engine failures are
    recorded as HOLD with a retry schedule, never as an approval."""
    from ..auto_moderation.engine import moderate
    from ..auto_moderation.triggers import dispatch_alert, request_moderation

    result = moderate(subject_type, int(subject_id), trigger=trigger)
    if result.get("reenqueue"):
        # The seller changed the content while we evaluated: judge the new one.
        request_moderation(subject_type, int(subject_id))
    elif result.get("retry_in"):
        request_moderation(subject_type, int(subject_id), countdown=int(result["retry_in"]))
    if result.get("alert") and result.get("run_id"):
        dispatch_alert(int(result["run_id"]))
    return {k: v for k, v in result.items() if isinstance(v, (str, int, float, bool, type(None)))}


@celery_app.task(name="kk.send_moderation_alert")
def send_moderation_alert_task(run_id: int):
    from ..auto_moderation.alerts import send_alert_for_run

    try:
        return send_alert_for_run(int(run_id))
    except Exception as exc:
        logger.warning("send_moderation_alert failed: %s", type(exc).__name__)
        return {"sent": False, "reason": "error"}


@celery_app.task(name="kk.sweep_listing_moderation")
def sweep_listing_moderation():
    """Every 2 minutes: enqueue moderation for every pending listing / edit
    that has no current decision. Only enqueues; never decides or publishes."""
    from ..auto_moderation.sweep import sweep

    result = sweep()
    if result.get("enqueued"):
        logger.info("sweep_listing_moderation: %s", result)
    return {"ok": True, **result}
