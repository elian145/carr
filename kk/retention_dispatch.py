"""Enqueue retention alert tasks (saved search, price drop) with sync fallback."""
from __future__ import annotations

import logging

logger = logging.getLogger(__name__)


def dispatch_saved_search_alerts(car_id: int) -> None:
    from .tasks.alert_tasks import notify_saved_searches_for_car

    try:
        notify_saved_searches_for_car.delay(car_id)
        return
    except Exception as exc:
        logger.debug("Celery delay unavailable for saved search alerts: %s", exc)

    try:
        notify_saved_searches_for_car(car_id)
    except Exception as exc:
        logger.warning("Saved search alert dispatch failed for car %s: %s", car_id, exc)


def dispatch_price_drop_alerts(car_id: int, old_price: float, new_price: float) -> None:
    from .tasks.alert_tasks import notify_price_drop_for_car

    try:
        notify_price_drop_for_car.delay(car_id, old_price, new_price)
        return
    except Exception as exc:
        logger.debug("Celery delay unavailable for price drop alerts: %s", exc)

    try:
        notify_price_drop_for_car(car_id, old_price, new_price)
    except Exception as exc:
        logger.warning("Price drop alert dispatch failed for car %s: %s", car_id, exc)
