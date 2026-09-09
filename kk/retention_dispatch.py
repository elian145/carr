"""Enqueue retention alert tasks (saved search, price drop) -- fire-and-forget.

BE-12 fix (see PRODUCTION_AUDIT.md). The previous version of this module
caught *any* exception from ``Task.delay()`` and, on failure, ran the
alert task function directly and synchronously inside the calling
(Flask/Gunicorn) request thread:

    try:
        task.delay(...)
        return
    except Exception:
        task(...)   # <-- ran inline, in-request

Investigation established two independent problems with that pattern:

1. **Unbounded request blocking, not a fast "fail open".** When the Celery
   result backend (Redis in production) is unreachable, ``.delay()`` does
   not fail fast. ``Celery.send_task()`` calls ``self.backend.on_task_call()``
   -- which, for the Redis backend, subscribes for the eventual result --
   *before* the task message is ever published. On a real connection
   failure this hits the backend's own connection retry policy (default
   ``max_retries=20``, ~1s apart) and blocked the calling thread for
   **roughly a minute** in local reproduction, before raising. Only after
   that minute-long block would the old code have started running the
   alert task inline.
2. **Mandatory synchronous execution disguised as a fallback.** Even once
   the exception was raised, running the task function directly inside
   the request bypassed the entire point of dispatching it to Celery: a
   listing create/update request would end up doing the alert's DB
   queries and push-notification sends itself, synchronously, whenever
   Celery was unavailable for any reason.

Fix: enqueue with ``apply_async(..., ignore_result=True, retry=False)``
instead of ``.delay()``:

- ``ignore_result=True`` skips the result-backend subscription entirely
  (``Celery.send_task``: ``if not ignore_result: self.backend.on_task_call(...)``).
  That call is exactly what caused the ~1 minute block above. Neither
  ``dispatch_saved_search_alerts`` nor ``dispatch_price_drop_alerts`` (nor
  their only caller, ``kk/routes/cars.py``) ever reads a task result, so
  disabling result storage for these two tasks changes nothing observable
  and removes the blocking risk at its source.
- ``retry=False`` disables Celery's own broker-publish retry loop
  (``task_publish_retry``, default 3 attempts) on the *broker* side, so a
  broker connection failure raises immediately instead of retrying inline
  for up to ~1s per publish attempt.
- ``.delay()`` cannot express either of these -- it is a fixed shorthand
  for ``apply_async(args, kwargs)`` with no extra options -- so
  ``apply_async()`` is used explicitly.

If enqueuing still fails (e.g. the broker/backend is genuinely
unreachable), the failure is logged and the function returns. There is no
fallback to calling the task function directly, and there never will be
one added silently here again: losing a best-effort saved-search or
price-drop push notification because Celery is briefly unavailable is
acceptable; blocking or hijacking a listing create/update request because
of it is not.

Explicitly out of scope for this fix (do not "fix" here):
- Whether a Celery worker is actually consuming the queue in production
  (BE-13, status unknown). A reachable broker with no worker still makes
  ``apply_async()`` return successfully -- the message is queued, not
  lost, and this module has no way to observe worker liveness.
- The alert task bodies themselves (``kk/tasks/alert_tasks.py``) and
  scheduled-notification processing (``kk/notification_broadcast.py``) --
  unrelated to this fail-open dispatcher.
"""
from __future__ import annotations

import logging

from celery.exceptions import OperationalError

logger = logging.getLogger(__name__)


def dispatch_saved_search_alerts(car_id: int) -> None:
    from .tasks.alert_tasks import notify_saved_searches_for_car

    try:
        notify_saved_searches_for_car.apply_async(
            args=(car_id,),
            ignore_result=True,
            retry=False,
        )
    except OperationalError as exc:
        # Broker/backend unreachable (e.g. Redis down). Expected failure
        # mode -- log and return. Never fall back to running the task
        # inline; never block the caller waiting on it.
        logger.warning(
            "Saved search alert enqueue failed for car %s (broker unavailable): %s",
            car_id,
            exc,
        )
    except Exception as exc:  # pragma: no cover - defensive last resort only
        # Anything else unexpected while enqueuing (not a connection
        # failure). Still must not raise into the caller or run inline.
        logger.exception(
            "Saved search alert enqueue failed unexpectedly for car %s: %s",
            car_id,
            exc,
        )


def dispatch_price_drop_alerts(car_id: int, old_price: float, new_price: float) -> None:
    from .tasks.alert_tasks import notify_price_drop_for_car

    try:
        notify_price_drop_for_car.apply_async(
            args=(car_id, old_price, new_price),
            ignore_result=True,
            retry=False,
        )
    except OperationalError as exc:
        logger.warning(
            "Price drop alert enqueue failed for car %s (broker unavailable): %s",
            car_id,
            exc,
        )
    except Exception as exc:  # pragma: no cover - defensive last resort only
        logger.exception(
            "Price drop alert enqueue failed unexpectedly for car %s: %s",
            car_id,
            exc,
        )
