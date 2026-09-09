"""BE-04 regression tests: admin notification broadcasts must not fan out to
FCM recipients synchronously inside the HTTP request.

Bug (PRODUCTION_AUDIT.md BE-04): ``execute_broadcast()`` (``kk/notification_broadcast.py``)
used to be called directly, inline, from three places -- all on the
request thread:

  * ``POST /api/admin/notifications/broadcast`` (the "send now" branch)
  * ``GET /api/admin/notifications/scheduled`` (a "lazy delivery" fallback
    that ran ``process_due_scheduled_notifications()`` on every page load)
  * ``POST /api/admin/notifications/scheduled/process`` (a manual "process
    due" action, also fully synchronous)

At up to 5,000 recipients (``resolve_recipients(..., limit=5000)``), each
recipient can trigger both a DB write and a blocking FCM network call, so
this could block the calling Gunicorn worker for minutes -- see the BE-04
investigation for measured/reasoned timing.

Fix (this file's subject): "send now" broadcasts are now persisted as a
durable ``ScheduledNotification`` row (``scheduled_at=utcnow()``, via the
new ``create_immediate_broadcast_row()``) and handed off to a new Celery
task, ``send_immediate_broadcast_task``, enqueued with
``apply_async(..., ignore_result=True, retry=False)`` -- the exact BE-12
safe-enqueue pattern, with no synchronous fallback if the enqueue itself
fails. ``GET /api/admin/notifications/scheduled`` no longer processes
anything (list-only). ``POST /api/admin/notifications/scheduled/process``
now only performs the cheap BE-03 atomic claim inline and enqueues one
task per claimed row, instead of calling ``execute_broadcast()`` itself.

These tests exercise the real Flask app, real (SQLite-backed) SQLAlchemy
session, and the real admin HTTP routes -- not re-implemented fakes. The
Celery *enqueue boundary* (``send_immediate_broadcast_task.apply_async``/
``.run``) is replaced with controlled mocks, exactly like
``test_be12_retention_dispatch.py`` does for ``retention_dispatch.py``, so
enqueue-failure and "never runs the task body inline" assertions can be
made deterministically without a real broker/worker.

Explicitly out of scope for this file (per the approved BE-04 plan):
  * FCM batching / clearing dead tokens (BE-05).
  * Automatic recovery of a row stuck in "sending" after a worker crash
    or a failed enqueue post-claim (deliberately deferred, not fixed
    here).
  * Idempotency protection against an admin double-clicking /
    double-submitting "send now" (pre-existing gap, deliberately deferred,
    not fixed here).
  * ``execute_broadcast()`` itself, BE-03's atomic claim semantics, and
    BE-12's ``retention_dispatch.py`` are all unmodified and exercised
    only to prove they are not bypassed or duplicated.
"""

from __future__ import annotations

import os
import sys
import tempfile
import time
import uuid
from datetime import timedelta
from pathlib import Path
from unittest import mock

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

os.environ.setdefault("APP_ENV", "testing")
os.environ.setdefault("SECRET_KEY", "test-secret-key-for-be04")
os.environ.setdefault("JWT_SECRET_KEY", "test-jwt-secret-key-for-be04")

from celery.exceptions import OperationalError  # noqa: E402

from kk.tasks.notification_tasks import send_immediate_broadcast_task  # noqa: E402

_PASSWORD = "Aa123456!"


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_be04_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "be04.db")

    from kk.app_factory import create_app

    app, _socketio, *_ = create_app()
    from kk.models import Notification, ScheduledNotification, User, db

    with app.app_context():
        db.drop_all()
        db.create_all()

    yield app, app.test_client(), db, User, ScheduledNotification, Notification

    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    tmp.cleanup()


@pytest.fixture(autouse=True)
def _restore_task_attrs():
    """Belt-and-suspenders restore of the real task callable/apply_async.

    ``send_immediate_broadcast_task`` is a process-wide singleton shared by
    every other test module in the same pytest run; ``monkeypatch`` already
    restores what it patches at teardown, but this is the same extra safety
    net ``test_be12_retention_dispatch.py`` uses for the same reason.
    """
    saved = {
        "apply_async": send_immediate_broadcast_task.apply_async,
        "run": send_immediate_broadcast_task.run,
    }
    yield
    send_immediate_broadcast_task.apply_async = saved["apply_async"]
    send_immediate_broadcast_task.run = saved["run"]


def _phone() -> str:
    return f"079{uuid.uuid4().int % 10**8:08d}"


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _login(client, username: str) -> str:
    r = client.post("/api/auth/login", json={"username": username, "password": _PASSWORD})
    assert r.status_code == 200, r.data
    return r.get_json()["access_token"]


def _make_user(app, db, User, *, tag: str, is_admin: bool = False):
    with app.app_context():
        username = f"be04_{tag}_{uuid.uuid4().hex[:10]}"
        user = User(
            username=username,
            phone_number=_phone(),
            first_name="Be04",
            last_name="Test",
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id=f"be04-{tag}-{uuid.uuid4().hex[:12]}",
            is_admin=is_admin,
        )
        user.set_password(_PASSWORD)
        db.session.add(user)
        db.session.commit()
        return user.id, user.public_id, username


def _clear_scheduled_notifications(app, db, ScheduledNotification):
    """Reset the scheduled_notification table.

    The app_ctx fixture is module-scoped (shared DB across every test in
    this file, matching test_be03's convention), but list_due_pending_ids()
    -- used by the "process due" endpoint tests below -- lists *every* due
    row in the table, not just the one row a given test created. Earlier
    tests in this file deliberately leave their own "send now" rows in
    "pending" (their whole point is proving the enqueue never actually ran
    the task), which would otherwise leak into these listing/count
    assertions. Called only by the tests that need an exact, isolated
    count of due rows.
    """
    with app.app_context():
        ScheduledNotification.query.delete()
        db.session.commit()


def _make_due_row(app, db, ScheduledNotification, *, target_user_public_id: str, tag: str):
    """A pending ScheduledNotification whose scheduled_at is already due."""
    from kk.time_utils import utcnow

    with app.app_context():
        row = ScheduledNotification(
            title=f"BE-04 {tag}",
            message="async broadcast regression test",
            audience="user",
            target_user_public_id=target_user_public_id,
            notification_type="admin",
            send_push=False,
            scheduled_at=utcnow() - timedelta(minutes=5),
            status="pending",
            created_at=utcnow(),
            updated_at=utcnow(),
        )
        db.session.add(row)
        db.session.commit()
        return row.id


# ---------------------------------------------------------------------------
# A, B, C, D: send-now creates exactly one durable row (scheduled_at ~= now),
# enqueues the Celery task with the right row id, and returns quickly
# without ever running execute_broadcast() / the task body inline.
# ---------------------------------------------------------------------------


def test_send_now_is_fast_durable_and_enqueues_without_inline_fan_out(app_ctx, monkeypatch):
    app, client, db, User, ScheduledNotification, Notification = app_ctx
    admin_id, _ap, admin_name = _make_user(app, db, User, tag="sendnow", is_admin=True)
    recipient_id, recipient_pub, _rn = _make_user(app, db, User, tag="recipient")

    fake_apply_async = mock.Mock(return_value=mock.Mock(id="fake-task-id"))
    inline_run = mock.Mock()
    monkeypatch.setattr(send_immediate_broadcast_task, "apply_async", fake_apply_async)
    monkeypatch.setattr(send_immediate_broadcast_task, "run", inline_run)

    import kk.notification_broadcast as notification_broadcast

    inline_execute_broadcast = mock.Mock(side_effect=AssertionError(
        "execute_broadcast() must never be called inline from the send-now route"
    ))
    monkeypatch.setattr(notification_broadcast, "execute_broadcast", inline_execute_broadcast)

    token = _login(client, admin_name)
    title = f"BE-04 send-now {uuid.uuid4().hex[:8]}"
    t0 = time.perf_counter()
    resp = client.post(
        "/api/admin/notifications/broadcast",
        json={
            "title": title,
            "message": "hello",
            "audience": "user",
            "target_user_id": recipient_pub,
            "send_push": True,
        },
        headers=_auth(token),
    )
    elapsed = time.perf_counter() - t0

    # A: fast, and never ran execute_broadcast()/the task body inline.
    assert resp.status_code == 202, resp.data
    assert elapsed < 3.0, f"send-now took {elapsed:.3f}s -- looks like inline fan-out"
    inline_execute_broadcast.assert_not_called()
    inline_run.assert_not_called()

    body = resp.get_json()
    assert body["scheduled"] is False
    assert body["queued"] is True
    assert "created" not in body, "must not report fake completed-broadcast counts"
    assert "pushed" not in body, "must not report fake completed-broadcast counts"
    row_payload = body["scheduled_notification"]
    row_id = row_payload["id"]

    # B: exactly one durable row for this request.
    with app.app_context():
        matches = ScheduledNotification.query.filter_by(title=title).all()
        assert len(matches) == 1, matches
        row = matches[0]
        assert row.id == row_id
        assert row.status == "pending"

        # C: scheduled_at is approximately creation time (well within a
        # generous test-runtime tolerance), not "in the future".
        from kk.time_utils import utcnow

        assert abs((row.scheduled_at - utcnow()).total_seconds()) < 30

    # D: the Celery task was enqueued with the correct row id and the
    # BE-12 safe-enqueue options.
    fake_apply_async.assert_called_once()
    _, kwargs = fake_apply_async.call_args
    assert kwargs["kwargs"] == {"row_id": row_id}
    assert kwargs["ignore_result"] is True
    assert kwargs["retry"] is False

    # No Notification was ever created -- the broadcast has not run.
    with app.app_context():
        assert Notification.query.filter_by(user_id=recipient_id).count() == 0


# ---------------------------------------------------------------------------
# E: enqueue failure -- the API still returns successfully, the row stays
# "pending", and the task body is never run inline as a fallback.
# ---------------------------------------------------------------------------


def test_send_now_enqueue_failure_leaves_row_pending_with_no_inline_fallback(app_ctx, monkeypatch):
    app, client, db, User, ScheduledNotification, Notification = app_ctx
    admin_id, _ap, admin_name = _make_user(app, db, User, tag="enqfail", is_admin=True)
    recipient_id, recipient_pub, _rn = _make_user(app, db, User, tag="enqfailrecipient")

    monkeypatch.setattr(
        send_immediate_broadcast_task,
        "apply_async",
        mock.Mock(side_effect=OperationalError("simulated broker connection failure")),
    )
    inline_run = mock.Mock()
    monkeypatch.setattr(send_immediate_broadcast_task, "run", inline_run)

    token = _login(client, admin_name)
    title = f"BE-04 enqueue-fail {uuid.uuid4().hex[:8]}"
    resp = client.post(
        "/api/admin/notifications/broadcast",
        json={
            "title": title,
            "message": "hello",
            "audience": "user",
            "target_user_id": recipient_pub,
            "send_push": True,
        },
        headers=_auth(token),
    )

    # API still returns successfully -- the durable row is what matters,
    # not whether the enqueue succeeded.
    assert resp.status_code == 202, resp.data
    body = resp.get_json()
    row_id = body["scheduled_notification"]["id"]

    with app.app_context():
        row = db.session.get(ScheduledNotification, row_id)
        assert row.status == "pending", "row must remain pending, not silently lost"

        # Never ran the broadcast inline as a fallback.
        assert Notification.query.filter_by(user_id=recipient_id).count() == 0
    inline_run.assert_not_called()


def test_send_now_enqueue_unexpected_error_also_has_no_inline_fallback(app_ctx, monkeypatch):
    """Same as above but for the broad "last resort" except branch (any
    non-OperationalError exception at the enqueue boundary)."""
    app, client, db, User, ScheduledNotification, Notification = app_ctx
    admin_id, _ap, admin_name = _make_user(app, db, User, tag="enqfail2", is_admin=True)
    recipient_id, recipient_pub, _rn = _make_user(app, db, User, tag="enqfail2recipient")

    monkeypatch.setattr(
        send_immediate_broadcast_task,
        "apply_async",
        mock.Mock(side_effect=RuntimeError("unexpected enqueue failure")),
    )
    inline_run = mock.Mock()
    monkeypatch.setattr(send_immediate_broadcast_task, "run", inline_run)

    token = _login(client, admin_name)
    title = f"BE-04 enqueue-fail2 {uuid.uuid4().hex[:8]}"
    resp = client.post(
        "/api/admin/notifications/broadcast",
        json={
            "title": title,
            "message": "hello",
            "audience": "user",
            "target_user_id": recipient_pub,
            "send_push": True,
        },
        headers=_auth(token),
    )

    assert resp.status_code == 202, resp.data
    row_id = resp.get_json()["scheduled_notification"]["id"]
    with app.app_context():
        row = db.session.get(ScheduledNotification, row_id)
        assert row.status == "pending"
        assert Notification.query.filter_by(user_id=recipient_id).count() == 0
    inline_run.assert_not_called()


# ---------------------------------------------------------------------------
# F: GET /notifications/scheduled is list-only -- it must not claim, send,
# or otherwise change the state of a due, pending row.
# ---------------------------------------------------------------------------


def test_get_scheduled_does_not_process_due_rows(app_ctx, monkeypatch):
    app, client, db, User, ScheduledNotification, Notification = app_ctx
    admin_id, _ap, admin_name = _make_user(app, db, User, tag="getlist", is_admin=True)
    recipient_id, recipient_pub, _rn = _make_user(app, db, User, tag="getlistrecipient")
    row_id = _make_due_row(app, db, ScheduledNotification, target_user_public_id=recipient_pub, tag="getlist")

    import kk.notification_broadcast as notification_broadcast

    never_call = mock.Mock(side_effect=AssertionError("must not be called by GET"))
    monkeypatch.setattr(notification_broadcast, "process_due_scheduled_notifications", never_call)
    monkeypatch.setattr(notification_broadcast, "_claim_and_send_scheduled_notification", never_call)
    monkeypatch.setattr(notification_broadcast, "_try_claim_pending_row", never_call)

    token = _login(client, admin_name)
    resp = client.get("/api/admin/notifications/scheduled", headers=_auth(token))
    assert resp.status_code == 200, resp.data

    never_call.assert_not_called()
    with app.app_context():
        row = db.session.get(ScheduledNotification, row_id)
        assert row.status == "pending", "GET must not claim or process the row"
        assert Notification.query.filter_by(user_id=recipient_id).count() == 0


# ---------------------------------------------------------------------------
# G, H: POST /notifications/scheduled/process claims due rows (cheap,
# inline) and enqueues one task per due row -- it must never call
# execute_broadcast() itself, and it must NOT claim/mutate row state
# itself: only the Celery task that actually fans out may perform the
# pending -> sending transition (see list_due_pending_ids()'s docstring
# for the bug this fixes -- an earlier version pre-claimed here, which
# made every row it "claimed" permanently unreachable by the task).
# ---------------------------------------------------------------------------


def test_process_endpoint_lists_and_enqueues_without_claiming_or_inline_fan_out(app_ctx, monkeypatch):
    app, client, db, User, ScheduledNotification, Notification = app_ctx
    _clear_scheduled_notifications(app, db, ScheduledNotification)
    admin_id, _ap, admin_name = _make_user(app, db, User, tag="processdue", is_admin=True)
    recipient_id, recipient_pub, _rn = _make_user(app, db, User, tag="processduerecipient")
    row_id = _make_due_row(app, db, ScheduledNotification, target_user_public_id=recipient_pub, tag="processdue")

    import kk.notification_broadcast as notification_broadcast

    inline_execute_broadcast = mock.Mock(side_effect=AssertionError(
        "execute_broadcast() must never be called inline from the process-due route"
    ))
    monkeypatch.setattr(notification_broadcast, "execute_broadcast", inline_execute_broadcast)

    fake_apply_async = mock.Mock(return_value=mock.Mock(id="fake-task-id"))
    inline_run = mock.Mock()
    monkeypatch.setattr(send_immediate_broadcast_task, "apply_async", fake_apply_async)
    monkeypatch.setattr(send_immediate_broadcast_task, "run", inline_run)

    token = _login(client, admin_name)
    resp = client.post("/api/admin/notifications/scheduled/process", headers=_auth(token))
    assert resp.status_code == 200, resp.data

    # G: never ran the broadcast inline.
    inline_execute_broadcast.assert_not_called()
    inline_run.assert_not_called()
    with app.app_context():
        assert Notification.query.filter_by(user_id=recipient_id).count() == 0

    body = resp.get_json()
    assert body["due"] == 1
    assert body["queued"] == 1
    assert "claimed" not in body, "must not report a claim -- the HTTP request never claims"
    assert "sent" not in body, "must not report fake completion counts"
    assert "failed" not in body, "must not report fake completion counts"

    # Critical: the HTTP request must NOT have claimed/mutated the row.
    # Only the (mocked-out, in this test) Celery task may transition it.
    with app.app_context():
        row = db.session.get(ScheduledNotification, row_id)
        assert row.status == "pending", (
            "the process-due endpoint must leave due rows pending -- "
            "claiming here would make them unreachable by the task it "
            "hands off to (both use the same pending-only claim primitive)"
        )

    # H: the row was enqueued with the correct id and BE-12 options.
    fake_apply_async.assert_called_once()
    _, kwargs = fake_apply_async.call_args
    assert kwargs["kwargs"] == {"row_id": row_id}
    assert kwargs["ignore_result"] is True
    assert kwargs["retry"] is False


def test_process_endpoint_task_actually_completes_the_broadcast_when_run(app_ctx, monkeypatch):
    """The critical end-to-end link that a mocked apply_async cannot prove:
    capture the row id POST /scheduled/process queues, then actually run
    the REAL Celery task body (not a mock) and prove execute_broadcast()
    is reached exactly once and the row ends up "sent". This is the exact
    regression test for the pre-claim bug (the HTTP endpoint used to flip
    the row to "sending" itself, so when this real task body ran, its own
    claim attempt always found rowcount 0 and execute_broadcast() was
    silently, permanently unreachable).
    """
    app, client, db, User, ScheduledNotification, Notification = app_ctx
    _clear_scheduled_notifications(app, db, ScheduledNotification)
    admin_id, _ap, admin_name = _make_user(app, db, User, tag="processduereal", is_admin=True)
    recipient_id, recipient_pub, _rn = _make_user(
        app, db, User, tag="processduerealrecipient"
    )
    row_id = _make_due_row(
        app, db, ScheduledNotification, target_user_public_id=recipient_pub, tag="processduereal"
    )

    import kk.notification_broadcast as notification_broadcast

    real_execute_broadcast = notification_broadcast.execute_broadcast
    spy_execute_broadcast = mock.Mock(wraps=real_execute_broadcast)
    monkeypatch.setattr(notification_broadcast, "execute_broadcast", spy_execute_broadcast)

    # The enqueue itself is still mocked (no real broker in this test
    # process) -- only the *enqueue call* is faked; the task body invoked
    # below is the real, undecorated production function.
    fake_apply_async = mock.Mock(return_value=mock.Mock(id="fake-task-id"))
    monkeypatch.setattr(send_immediate_broadcast_task, "apply_async", fake_apply_async)

    token = _login(client, admin_name)
    resp = client.post("/api/admin/notifications/scheduled/process", headers=_auth(token))
    assert resp.status_code == 200, resp.data
    body = resp.get_json()
    assert body["due"] == 1
    assert body["queued"] == 1

    with app.app_context():
        row = db.session.get(ScheduledNotification, row_id)
        assert row.status == "pending", "must still be pending right after the HTTP call"

    fake_apply_async.assert_called_once()
    _, kwargs = fake_apply_async.call_args
    assert kwargs["kwargs"] == {"row_id": row_id}

    # Now actually run the real Celery task body synchronously -- exactly
    # what a real worker consuming the queued message would execute.
    # FlaskContextTask normally pushes the app context in __call__() before
    # invoking run(); calling .run() directly here requires we push the
    # context ourselves, which the `with app.app_context()` below does.
    with app.app_context():
        send_immediate_broadcast_task.run(row_id)

    spy_execute_broadcast.assert_called_once()
    with app.app_context():
        row = db.session.get(ScheduledNotification, row_id)
        assert row.status == "sent"
        assert Notification.query.filter_by(user_id=recipient_id).count() == 1


def test_process_endpoint_enqueue_failure_has_no_inline_fallback(app_ctx, monkeypatch):
    app, client, db, User, ScheduledNotification, Notification = app_ctx
    _clear_scheduled_notifications(app, db, ScheduledNotification)
    admin_id, _ap, admin_name = _make_user(app, db, User, tag="processduefail", is_admin=True)
    recipient_id, recipient_pub, _rn = _make_user(
        app, db, User, tag="processduefailrecipient"
    )
    row_id = _make_due_row(
        app, db, ScheduledNotification, target_user_public_id=recipient_pub, tag="processduefail"
    )

    monkeypatch.setattr(
        send_immediate_broadcast_task,
        "apply_async",
        mock.Mock(side_effect=OperationalError("simulated broker connection failure")),
    )
    inline_run = mock.Mock()
    monkeypatch.setattr(send_immediate_broadcast_task, "run", inline_run)

    token = _login(client, admin_name)
    resp = client.post("/api/admin/notifications/scheduled/process", headers=_auth(token))
    assert resp.status_code == 200, resp.data

    body = resp.get_json()
    assert body["due"] == 1
    assert body["queued"] == 0
    assert body["enqueue_errors"] == 1

    inline_run.assert_not_called()
    with app.app_context():
        assert Notification.query.filter_by(user_id=recipient_id).count() == 0
        # The row was never claimed by the HTTP request, so an enqueue
        # failure leaves it exactly where beat (or a later manual retry)
        # can still find and process it -- unlike the old pre-claim
        # design, this is not a stranding scenario.
        row = db.session.get(ScheduledNotification, row_id)
        assert row.status == "pending"


# ---------------------------------------------------------------------------
# I: list_due_pending_ids() (used by the manual "process due" endpoint) is
# read-only and must NOT change row state. The claim itself only happens
# inside process_scheduled_notification_by_id() (used by
# send_immediate_broadcast_task); racing two invocations of THAT for the
# same row -- e.g. a duplicate enqueue, or beat's own sweep picking up the
# same still-pending row the manual endpoint also listed and enqueued --
# must never double-broadcast it.
# ---------------------------------------------------------------------------


def test_list_due_pending_ids_does_not_claim_or_mutate_rows(app_ctx):
    app, client, db, User, ScheduledNotification, Notification = app_ctx
    _clear_scheduled_notifications(app, db, ScheduledNotification)
    recipient_id, recipient_pub, _rn = _make_user(app, db, User, tag="listonlyrecipient")
    row_id = _make_due_row(
        app, db, ScheduledNotification, target_user_public_id=recipient_pub, tag="listonly"
    )

    from kk.notification_broadcast import list_due_pending_ids

    with app.app_context():
        due_ids = list_due_pending_ids(limit=20)
        assert due_ids == [row_id]

        # Read-only: the row must still be "pending" after being listed,
        # and listing it again must return the same id (nothing claimed
        # it, so it stays visible/listable).
        row = db.session.get(ScheduledNotification, row_id)
        assert row.status == "pending"
        assert list_due_pending_ids(limit=20) == [row_id]
        assert Notification.query.filter_by(user_id=recipient_id).count() == 0


def test_concurrent_task_invocations_for_same_listed_row_yield_exactly_one_broadcast(app_ctx):
    """Simulates the real race this design accepts: the manual endpoint
    lists a due row and enqueues send_immediate_broadcast_task for it, but
    before that task runs, something else (a duplicate enqueue of the same
    task, or Celery beat's own periodic sweep) also ends up processing the
    same still-pending row. Both paths funnel through
    process_scheduled_notification_by_id() -> the identical BE-03 claim
    primitive, so only one may actually broadcast.
    """
    app, client, db, User, ScheduledNotification, Notification = app_ctx
    _clear_scheduled_notifications(app, db, ScheduledNotification)
    recipient_id, recipient_pub, _rn = _make_user(app, db, User, tag="racerecipient")
    row_id = _make_due_row(
        app, db, ScheduledNotification, target_user_public_id=recipient_pub, tag="race"
    )

    from kk.notification_broadcast import (
        list_due_pending_ids,
        process_scheduled_notification_by_id,
    )

    with app.app_context():
        # The manual endpoint's read-only listing step -- must not claim.
        due_ids = list_due_pending_ids(limit=20)
        assert due_ids == [row_id]
        row = db.session.get(ScheduledNotification, row_id)
        assert row.status == "pending"

        # Caller A: the task enqueued for this row (or beat's own sweep)
        # wins the race and actually claims + broadcasts it.
        outcome_a = process_scheduled_notification_by_id(row_id)
        assert outcome_a is not None
        assert outcome_a["status"] == "sent"

        # Caller B: a second invocation for the exact same row id (a
        # duplicate enqueue, or beat racing the same task) must find it
        # already claimed/finished and do nothing.
        outcome_b = process_scheduled_notification_by_id(row_id)
        assert outcome_b is None

        # Exactly one broadcast happened overall.
        assert Notification.query.filter_by(user_id=recipient_id).count() == 1
        row = db.session.get(ScheduledNotification, row_id)
        assert row.status == "sent"
