"""BE-12 regression tests: retention alert dispatch must not fail open into
synchronous, in-request task execution.

Bug (PRODUCTION_AUDIT.md BE-12): ``kk/retention_dispatch.py`` used to do::

    try:
        task.delay(...)
        return
    except Exception:
        task(...)   # ran the task function directly, in-request

Investigation established two problems with that pattern:

1. When the Celery result backend (Redis in production) is unreachable,
   ``.delay()`` does not fail fast: ``Celery.send_task()`` subscribes for
   the eventual result (``self.backend.on_task_call(...)``) *before* the
   message is published, which hit the backend's own connection retry
   policy (default ``max_retries=20``, ~1s apart) and blocked the calling
   thread for roughly a minute in local reproduction before raising.
2. Only after that block did the old code run the alert task function
   directly and synchronously inside the calling (Flask/Gunicorn) request
   thread -- turning a "fire and forget" push notification into a
   mandatory, in-request side effect whenever Celery was unavailable.

The fix (``kk/retention_dispatch.py``) enqueues with
``apply_async(..., ignore_result=True, retry=False)`` instead of
``.delay()``:

- ``ignore_result=True`` skips the backend result-consumer subscription
  entirely (confirmed by reading the installed Celery 5.3.4 source,
  ``celery/app/base.py::Celery.send_task``:
  ``if not ignore_result: self.backend.on_task_call(...)``) -- this is
  exactly the call that caused the ~1 minute block.
- ``retry=False`` disables Celery's own broker-publish retry loop
  (``task_publish_retry``) so a broker connection failure raises
  immediately instead of retrying for up to ~1s per publish attempt.
- On any enqueue failure, the dispatcher logs a warning and returns.
  There is **no fallback to calling the task function directly** --
  losing a best-effort alert because Celery is briefly unavailable is
  acceptable; blocking or hijacking the request is not.

These tests exercise the real ``kk.retention_dispatch`` module and the
real Celery task objects from ``kk.tasks.alert_tasks`` (not re-implemented
fakes), but replace only the Celery *enqueue boundary*
(``Task.apply_async``/``Task.delay``) with controlled fakes so failure
modes (a broker/backend outage) can be exercised deterministically and
quickly, without depending on a real Redis outage or the real ~60s retry
storm. This mirrors the instruction to use a controlled mock/failure at
the enqueue boundary rather than relying only on ``memory://`` (which does
not exercise the failure path at all -- see
``test_memory_broker_enqueue_success_does_not_run_task_inline`` below,
which documents that ``memory://`` alone proves nothing about the failure
path).

Out of scope, intentionally not touched or asserted on here (per the
BE-12 fix's own scope limits):
- BE-04 (``kk/notification_broadcast.py`` broadcast fan-out).
- BE-13 (whether a Celery worker/beat process is actually running in
  production) -- a reachable broker with no consuming worker is exactly
  the case tested by
  ``test_apply_async_success_does_not_attempt_inline_fallback``: dispatch
  must return once the message is (apparently) enqueued, regardless of
  whether anything is actually consuming it. That is BE-13's concern, not
  BE-12's.
- The alert task bodies (``kk/tasks/alert_tasks.py``) and scheduled
  notification processing (``kk/notification_broadcast.py``) are not
  modified or exercised beyond confirming they are never invoked
  synchronously by the dispatcher.
"""
from __future__ import annotations

import os
import sys
import time
from pathlib import Path
from unittest import mock

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

os.environ.setdefault("APP_ENV", "testing")
os.environ.setdefault("SECRET_KEY", "test-secret-key-for-be12")
os.environ.setdefault("JWT_SECRET_KEY", "test-jwt-secret-key-for-be12")

from celery.exceptions import OperationalError  # noqa: E402

import kk.retention_dispatch as retention_dispatch  # noqa: E402
from kk.tasks.alert_tasks import (  # noqa: E402
    notify_price_drop_for_car,
    notify_saved_searches_for_car,
)


@pytest.fixture(autouse=True)
def _restore_task_attrs():
    """Belt-and-suspenders restore of the real task callables/apply_async.

    ``monkeypatch.setattr`` already restores whatever it patched at test
    teardown; this fixture is an extra safety net (these are process-wide
    singletons shared by every other test module in the same pytest run)
    so a failed/aborted test can never leave a patched task behind for
    unrelated tests.
    """
    saved = {
        "saved_search_apply_async": notify_saved_searches_for_car.apply_async,
        "saved_search_delay": notify_saved_searches_for_car.delay,
        "saved_search_run": notify_saved_searches_for_car.run,
        "price_drop_apply_async": notify_price_drop_for_car.apply_async,
        "price_drop_delay": notify_price_drop_for_car.delay,
        "price_drop_run": notify_price_drop_for_car.run,
    }
    yield
    notify_saved_searches_for_car.apply_async = saved["saved_search_apply_async"]
    notify_saved_searches_for_car.delay = saved["saved_search_delay"]
    notify_saved_searches_for_car.run = saved["saved_search_run"]
    notify_price_drop_for_car.apply_async = saved["price_drop_apply_async"]
    notify_price_drop_for_car.delay = saved["price_drop_delay"]
    notify_price_drop_for_car.run = saved["price_drop_run"]


# ---------------------------------------------------------------------------
# 1 & 6. Successful dispatch enqueues via apply_async(...) with the expected
# ignore_result=True / retry=False options -- never via .delay().
# ---------------------------------------------------------------------------


def test_saved_search_dispatch_enqueues_via_apply_async_with_expected_options(monkeypatch):
    fake_apply_async = mock.Mock(return_value=mock.Mock(id="fake-task-id"))
    fake_delay = mock.Mock()
    monkeypatch.setattr(notify_saved_searches_for_car, "apply_async", fake_apply_async)
    monkeypatch.setattr(notify_saved_searches_for_car, "delay", fake_delay)

    retention_dispatch.dispatch_saved_search_alerts(42)

    fake_apply_async.assert_called_once()
    _, kwargs = fake_apply_async.call_args
    assert kwargs["args"] == (42,)
    assert kwargs["ignore_result"] is True, "ignore_result=True is required to skip the backend result-consumer subscribe that caused the ~60s block"
    assert kwargs["retry"] is False, "retry=False is required to avoid the broker-side publish retry loop"
    fake_delay.assert_not_called()


def test_price_drop_dispatch_enqueues_via_apply_async_with_expected_options(monkeypatch):
    fake_apply_async = mock.Mock(return_value=mock.Mock(id="fake-task-id"))
    fake_delay = mock.Mock()
    monkeypatch.setattr(notify_price_drop_for_car, "apply_async", fake_apply_async)
    monkeypatch.setattr(notify_price_drop_for_car, "delay", fake_delay)

    retention_dispatch.dispatch_price_drop_alerts(7, 20000.0, 15000.0)

    fake_apply_async.assert_called_once()
    _, kwargs = fake_apply_async.call_args
    assert kwargs["args"] == (7, 20000.0, 15000.0)
    assert kwargs["ignore_result"] is True
    assert kwargs["retry"] is False
    fake_delay.assert_not_called()


# ---------------------------------------------------------------------------
# 2. (Also covered above for both alert types -- kept as one pair of tests
# per the "successful dispatch queues X asynchronously" requirement.)
# ---------------------------------------------------------------------------


def test_successful_saved_search_dispatch_returns_without_running_task_body(monkeypatch):
    """A successful enqueue must not run the task body -- it is genuinely async."""
    fake_apply_async = mock.Mock(return_value=mock.Mock(id="fake-task-id"))
    inline_run = mock.Mock()
    monkeypatch.setattr(notify_saved_searches_for_car, "apply_async", fake_apply_async)
    monkeypatch.setattr(notify_saved_searches_for_car, "run", inline_run)

    retention_dispatch.dispatch_saved_search_alerts(1)

    inline_run.assert_not_called()


def test_successful_price_drop_dispatch_returns_without_running_task_body(monkeypatch):
    fake_apply_async = mock.Mock(return_value=mock.Mock(id="fake-task-id"))
    inline_run = mock.Mock()
    monkeypatch.setattr(notify_price_drop_for_car, "apply_async", fake_apply_async)
    monkeypatch.setattr(notify_price_drop_for_car, "run", inline_run)

    retention_dispatch.dispatch_price_drop_alerts(1, 100.0, 90.0)

    inline_run.assert_not_called()


# ---------------------------------------------------------------------------
# 3, 4, 7. Enqueue failure (simulated broker/backend outage via a Celery
# exception raised at the enqueue boundary) must NOT run the task inline,
# must be logged, and the old direct-call fallback must be structurally
# impossible (proven by asserting the task body is never invoked).
# ---------------------------------------------------------------------------


def test_saved_search_enqueue_failure_does_not_run_task_inline(monkeypatch):
    monkeypatch.setattr(
        notify_saved_searches_for_car,
        "apply_async",
        mock.Mock(side_effect=OperationalError("simulated broker connection failure")),
    )
    inline_run = mock.Mock()
    monkeypatch.setattr(notify_saved_searches_for_car, "run", inline_run)

    # Assert directly against the module's own logger object rather than
    # via pytest's caplog/root-logger capture: some other test module in
    # the full suite mutates global `logging` state (root/handler levels)
    # in a way that is process-wide and outlives its own test, which made
    # caplog-based assertions here flaky when run as part of the full
    # `kk/tests` suite even though the code path itself was unaffected.
    # Patching the logger directly is deterministic and still proves the
    # dispatcher actually calls `logger.warning(...)`.
    fake_logger = mock.Mock()
    monkeypatch.setattr(retention_dispatch, "logger", fake_logger)

    # Requirement 5: dispatch failure must not propagate to the caller.
    retention_dispatch.dispatch_saved_search_alerts(99)

    # Requirement 3 / 7: the task body was never executed -- no sync fallback.
    inline_run.assert_not_called()

    # Requirement 4: the failure was logged, not swallowed silently.
    fake_logger.warning.assert_called_once()
    (msg, *_rest), _kwargs = fake_logger.warning.call_args
    assert "Saved search alert enqueue failed" in msg


def test_price_drop_enqueue_failure_does_not_run_task_inline(monkeypatch):
    monkeypatch.setattr(
        notify_price_drop_for_car,
        "apply_async",
        mock.Mock(side_effect=OperationalError("simulated broker connection failure")),
    )
    inline_run = mock.Mock()
    monkeypatch.setattr(notify_price_drop_for_car, "run", inline_run)

    fake_logger = mock.Mock()
    monkeypatch.setattr(retention_dispatch, "logger", fake_logger)

    retention_dispatch.dispatch_price_drop_alerts(99, 500.0, 400.0)

    inline_run.assert_not_called()
    fake_logger.warning.assert_called_once()
    (msg, *_rest), _kwargs = fake_logger.warning.call_args
    assert "Price drop alert enqueue failed" in msg


def test_unexpected_enqueue_exception_is_also_swallowed_and_logged(monkeypatch):
    """Defensive: even a non-OperationalError raised while enqueuing must
    not run the task inline or propagate -- it should hit the generic
    except-and-log safety net, not a sync fallback.
    """
    monkeypatch.setattr(
        notify_saved_searches_for_car,
        "apply_async",
        mock.Mock(side_effect=RuntimeError("unexpected enqueue error")),
    )
    inline_run = mock.Mock()
    monkeypatch.setattr(notify_saved_searches_for_car, "run", inline_run)

    fake_logger = mock.Mock()
    monkeypatch.setattr(retention_dispatch, "logger", fake_logger)

    retention_dispatch.dispatch_saved_search_alerts(5)

    inline_run.assert_not_called()
    fake_logger.exception.assert_called_once()
    (msg, *_rest), _kwargs = fake_logger.exception.call_args
    assert "enqueue failed unexpectedly" in msg


# ---------------------------------------------------------------------------
# 5. Dispatch failure must not propagate back to the car create/update
# caller (kk/routes/cars.py calls these with no exception-handling
# expectation beyond "must not raise").
# ---------------------------------------------------------------------------


def test_dispatch_failure_never_raises_to_caller(monkeypatch):
    monkeypatch.setattr(
        notify_saved_searches_for_car,
        "apply_async",
        mock.Mock(side_effect=OperationalError("simulated")),
    )
    monkeypatch.setattr(
        notify_price_drop_for_car,
        "apply_async",
        mock.Mock(side_effect=OperationalError("simulated")),
    )

    # Neither call should raise -- this is exactly what create_car/update_car
    # in kk/routes/cars.py rely on (they call these with a defensive
    # try/except of their own, but the dispatcher itself must not need it).
    retention_dispatch.dispatch_saved_search_alerts(1)
    retention_dispatch.dispatch_price_drop_alerts(1, 10.0, 5.0)


# ---------------------------------------------------------------------------
# 8. The dispatcher must return promptly on enqueue failure -- no internal
# retry loop, no synchronous task execution, no multi-second block.
# ---------------------------------------------------------------------------


def test_dispatcher_returns_promptly_when_enqueue_fails(monkeypatch):
    monkeypatch.setattr(
        notify_saved_searches_for_car,
        "apply_async",
        mock.Mock(side_effect=OperationalError("simulated")),
    )

    t0 = time.monotonic()
    retention_dispatch.dispatch_saved_search_alerts(1)
    elapsed = time.monotonic() - t0

    # Generous bound: must be nowhere near the ~64s result-backend retry
    # storm observed pre-fix. A correct implementation returns in
    # microseconds once apply_async raises immediately.
    assert elapsed < 2.0, (
        f"dispatch_saved_search_alerts took {elapsed:.3f}s on enqueue failure -- "
        "expected a prompt return with no retry/inline fallback"
    )


# ---------------------------------------------------------------------------
# Regression guard: statically prove the old "call the task function
# directly" fallback line is gone from the source, so a future edit can't
# silently reintroduce it.
# ---------------------------------------------------------------------------


def test_source_has_no_direct_task_call_fallback():
    import inspect

    # Only inspect the actual function bodies (not the module docstring,
    # which necessarily *discusses* `.delay()` and the old fallback pattern
    # for documentation purposes).
    fn_src = "\n".join(
        [
            inspect.getsource(retention_dispatch.dispatch_saved_search_alerts),
            inspect.getsource(retention_dispatch.dispatch_price_drop_alerts),
        ]
    )

    # The old bug called the task object directly as a plain function
    # (`notify_saved_searches_for_car(car_id)` / `notify_price_drop_for_car(...)`)
    # as a fallback. Guard against that exact pattern reappearing.
    assert "notify_saved_searches_for_car(car_id)" not in fn_src
    assert "notify_price_drop_for_car(car_id, old_price, new_price)" not in fn_src

    # And guard against the other half of the old bug: using the
    # options-less `.delay()` shorthand, which cannot express
    # ignore_result/retry and was the entry point into the whole problem.
    assert ".delay(" not in fn_src

    # Confirm apply_async is used with the two options required to avoid
    # the result-backend retry storm and the broker publish retry loop.
    assert "ignore_result=True" in fn_src
    assert "retry=False" in fn_src


# ---------------------------------------------------------------------------
# Real (non-mocked) sanity check: memory:// enqueue succeeds and the task
# is never run synchronously by the dispatcher. This does NOT exercise the
# failure path (memory:// never raises here) -- it only documents, with
# real Celery/kombu code, that a "successful" enqueue on this transport is
# genuinely fire-and-forget from the dispatcher's point of view, consistent
# with the BE-12 investigation's finding that memory:// does not execute
# tasks inline.
# ---------------------------------------------------------------------------


def test_memory_broker_enqueue_success_does_not_run_task_inline(monkeypatch):
    from kk.tasks.celery_app import celery_app

    if not str(celery_app.conf.broker_url or "").startswith("memory://"):
        pytest.skip("this process's celery_app is not using the memory:// broker")

    inline_run = mock.Mock()
    monkeypatch.setattr(notify_saved_searches_for_car, "run", inline_run)

    retention_dispatch.dispatch_saved_search_alerts(123456)

    inline_run.assert_not_called()


# ---------------------------------------------------------------------------
# Real (non-mocked) integration check: an actually-unreachable broker must
# raise via the real Celery/kombu code path fast enough that no retry storm
# occurred, and the dispatcher must still swallow it and return quickly.
# Runs in a subprocess because celery_app's broker/backend URLs are fixed
# once at first import (module-level singleton) and must not be mutated for
# the rest of this test session.
# ---------------------------------------------------------------------------


def test_real_unreachable_broker_fails_fast_not_in_64_seconds():
    import subprocess

    script = f"""
import os, sys, time
sys.path.insert(0, r{str(_REPO_ROOT)!r})
os.environ["APP_ENV"] = "testing"
os.environ["SECRET_KEY"] = "test-secret-key-for-be12"
os.environ["JWT_SECRET_KEY"] = "test-jwt-secret-key-for-be12"
os.environ["SMS_PROVIDER"] = "console"
os.environ["REDIS_URL"] = "redis://127.0.0.1:54329/0"  # nothing listens here

from kk.retention_dispatch import dispatch_saved_search_alerts

t0 = time.monotonic()
dispatch_saved_search_alerts(1)
elapsed = time.monotonic() - t0
print("ELAPSED", elapsed)
"""
    t0 = time.monotonic()
    proc = subprocess.run(
        [sys.executable, "-c", script],
        capture_output=True,
        text=True,
        timeout=45,
    )
    wall = time.monotonic() - t0

    assert proc.returncode == 0, (
        f"subprocess failed (rc={proc.returncode}):\nSTDOUT:\n{proc.stdout}\nSTDERR:\n{proc.stderr}"
    )
    assert "ELAPSED" in proc.stdout, proc.stdout

    elapsed_str = proc.stdout.strip().splitlines()[-1].split()[-1]
    elapsed = float(elapsed_str)

    # Pre-fix this took ~64s (a 20-attempt, ~1s-apart result-backend retry
    # storm). Post-fix it is bounded by a single connection attempt. 30s is
    # a very generous ceiling that still clearly distinguishes "no retry
    # storm" from the pre-fix ~64s behavior, while tolerating slow/loaded
    # CI network stacks for a single connect attempt.
    assert elapsed < 30.0, (
        f"dispatch_saved_search_alerts took {elapsed:.2f}s against an unreachable "
        "broker -- expected a single fast connection attempt, not a multi-retry storm"
    )
    # Independent bound on the whole subprocess (imports + migrations +
    # the call itself) so a real regression can't hide behind slow startup.
    assert wall < 45.0
