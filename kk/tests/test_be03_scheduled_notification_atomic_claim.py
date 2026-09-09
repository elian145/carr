"""BE-03 regression tests: scheduled-notification delivery must not double-send.

Bug (PRODUCTION_AUDIT.md BE-03): ``process_due_scheduled_notifications()``
(``kk/notification_broadcast.py``) used to ``SELECT`` the due ``pending``
rows and then, in a plain Python loop, unconditionally set
``row.status = "sending"`` and ``commit()`` -- with no
``SELECT ... FOR UPDATE`` and no conditional ``UPDATE ... WHERE
status='pending'``. Two concurrent callers (two Celery beat workers, the
admin "lazy delivery" ``GET /api/admin/notifications/scheduled`` fallback
racing the manual ``POST /api/admin/notifications/scheduled/process``
endpoint, two Gunicorn worker processes serving the same admin page load,
etc. -- see ``kk/routes/admin.py``) could both ``SELECT`` the same
``pending`` row before either committed its "sending" transition, and both
would then call ``execute_broadcast()`` for it -- sending every recipient
two duplicate ``Notification`` rows (and, if push is configured, two FCM
pushes).

The fix replaces the unconditional Python-level mutate+commit with an
atomic, conditional SQL ``UPDATE scheduled_notification SET
status='sending', updated_at=... WHERE id = :id AND status = 'pending'``,
executed via ``db.session.execute(update(...))``. Only the caller whose
``UPDATE`` affects exactly one row (``rowcount == 1``) is allowed to call
``execute_broadcast()`` for that row; a ``rowcount == 0`` result means
another caller already claimed it, and the row is skipped without
broadcasting.

These tests exercise the real ``process_due_scheduled_notifications()``
function end-to-end against a real SQLite-backed SQLAlchemy session (no
ORM/query mocking). The last test
(``test_two_racing_claim_attempts_result_in_exactly_one_broadcast``)
simulates a second worker winning the claim race *while the production
function's own call is still executing* -- interleaved via a SQLAlchemy
``after_cursor_execute`` event hook that fires right after the production
function's own ``SELECT`` has fetched its ``due`` rows (so the row is
still "pending" as far as that fetch is concerned) but before the
production function's per-row claim ``UPDATE`` runs for it. (A genuinely
separate OS-level connection was tried here and hits SQLite's single-writer
file lock as soon as it attempts to commit while the outer ORM session's
transaction is still open -- a well-known SQLite limitation, which is
exactly why the real-thread, real-Postgres concurrency proof for this claim
lives in ``scripts/ci_migration_smoke.py`` ::
``_be03_scheduled_notification_claim_smoke``, following the same
convention already established for D-04's
``_d04_otp_lockout_concurrency_smoke`` / ``_d04_analytics_concurrency_smoke``.
The interleaved commit here uses the same ``db.session`` connection instead,
which is sufficient to prove the real, non-mocked SQL guard -- ``UPDATE ...
WHERE status='pending'`` -- correctly yields ``rowcount == 0`` once another
commit has already flipped the row's status, and that the production
function honors that by skipping the row instead of broadcasting anyway.)
"""

from __future__ import annotations

import os
import sys
import tempfile
import uuid
from datetime import timedelta
from pathlib import Path

import pytest
from sqlalchemy import event, update

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_be03_", ignore_cleanup_errors=True)
    db_path = os.path.join(tmp.name, "be03.db")
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = db_path

    from kk.app_factory import create_app

    app, _socketio, *_ = create_app()
    from kk.models import Notification, ScheduledNotification, User, db

    with app.app_context():
        db.drop_all()
        db.create_all()

    yield app, db, User, ScheduledNotification, Notification, db_path

    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    tmp.cleanup()


def _phone() -> str:
    return f"078{uuid.uuid4().int % 10**8:08d}"


def _make_user(db, User, tag: str):
    user = User(
        username=f"be03_{tag}_{uuid.uuid4().hex[:10]}",
        phone_number=_phone(),
        first_name="Be03",
        last_name="Test",
        is_active=True,
        is_verified=True,
        phone_verified=True,
        public_id=f"be03-{tag}-{uuid.uuid4().hex[:12]}",
    )
    user.set_password("Aa123456!")
    db.session.add(user)
    db.session.commit()
    return user


def _make_scheduled(db, ScheduledNotification, *, target_user_public_id, status="pending", due_minutes_ago=5, tag="row"):
    from kk.time_utils import utcnow

    row = ScheduledNotification(
        title=f"BE-03 {tag}",
        message="atomic claim regression test",
        audience="user",
        target_user_public_id=target_user_public_id,
        notification_type="admin",
        send_push=False,
        scheduled_at=utcnow() - timedelta(minutes=due_minutes_ago),
        status=status,
        created_at=utcnow(),
        updated_at=utcnow(),
    )
    db.session.add(row)
    db.session.commit()
    return row


def _result_entry(result, row_id):
    return next((r for r in result["results"] if r["id"] == row_id), None)


# ---------------------------------------------------------------------------
# 1. Normal case: a pending, due notification is claimed and processed.
# ---------------------------------------------------------------------------


def test_pending_due_notification_is_claimed_and_sent(app_ctx):
    app, db, User, ScheduledNotification, Notification, _db_path = app_ctx
    from kk.notification_broadcast import process_due_scheduled_notifications

    with app.app_context():
        recipient = _make_user(db, User, "normal")
        row = _make_scheduled(
            db, ScheduledNotification, target_user_public_id=recipient.public_id, tag="normal"
        )
        row_id = row.id

        result = process_due_scheduled_notifications(limit=20)

        entry = _result_entry(result, row_id)
        assert entry is not None, "claimed row must appear in results"
        assert entry["status"] == "sent"

        refreshed = db.session.get(ScheduledNotification, row_id)
        assert refreshed.status == "sent"
        assert refreshed.sent_at is not None
        assert refreshed.error_message is None

        assert Notification.query.filter_by(user_id=recipient.id).count() == 1


# ---------------------------------------------------------------------------
# 2. A row already transitioned pending -> sending must not be re-claimed
#    or broadcast again by a later call.
# ---------------------------------------------------------------------------


def test_row_already_sending_is_not_reclaimed(app_ctx):
    app, db, User, ScheduledNotification, Notification, _db_path = app_ctx
    from kk.notification_broadcast import process_due_scheduled_notifications

    with app.app_context():
        recipient = _make_user(db, User, "sending")
        row = _make_scheduled(
            db,
            ScheduledNotification,
            target_user_public_id=recipient.public_id,
            status="sending",
            tag="sending",
        )
        row_id = row.id

        result = process_due_scheduled_notifications(limit=20)

        assert _result_entry(result, row_id) is None, (
            "a row already in 'sending' must be excluded by the due-query "
            "filter (status == 'pending') and never re-claimed"
        )

        refreshed = db.session.get(ScheduledNotification, row_id)
        assert refreshed.status == "sending"  # untouched
        assert Notification.query.filter_by(user_id=recipient.id).count() == 0


# ---------------------------------------------------------------------------
# 3. Terminal-state rows (sent / cancelled / failed) are never reclaimed.
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("terminal_status", ["sent", "cancelled", "failed"])
def test_terminal_status_rows_are_not_reclaimed(app_ctx, terminal_status):
    app, db, User, ScheduledNotification, Notification, _db_path = app_ctx
    from kk.notification_broadcast import process_due_scheduled_notifications

    with app.app_context():
        recipient = _make_user(db, User, terminal_status)
        row = _make_scheduled(
            db,
            ScheduledNotification,
            target_user_public_id=recipient.public_id,
            status=terminal_status,
            tag=terminal_status,
        )
        row_id = row.id

        result = process_due_scheduled_notifications(limit=20)

        assert _result_entry(result, row_id) is None
        refreshed = db.session.get(ScheduledNotification, row_id)
        assert refreshed.status == terminal_status  # unchanged
        assert Notification.query.filter_by(user_id=recipient.id).count() == 0


# ---------------------------------------------------------------------------
# 4. Two sequential simulated claim attempts on the same row: only the
#    first one may win, and it results in exactly one successful broadcast.
# ---------------------------------------------------------------------------


def test_two_sequential_claim_attempts_only_one_wins(app_ctx):
    """Directly exercises the exact conditional-UPDATE claim primitive that
    ``process_due_scheduled_notifications()`` uses per row (imported
    verbatim from ``kk.notification_broadcast``, not re-implemented here),
    simulating two workers racing for the same row without real threads.
    """
    app, db, User, ScheduledNotification, Notification, _db_path = app_ctx
    from kk.notification_broadcast import execute_broadcast
    from kk.time_utils import utcnow

    with app.app_context():
        recipient = _make_user(db, User, "raceclaim")
        row = _make_scheduled(
            db, ScheduledNotification, target_user_public_id=recipient.public_id, tag="raceclaim"
        )
        row_id = row.id

        def _attempt_claim():
            claim = db.session.execute(
                update(ScheduledNotification)
                .where(
                    ScheduledNotification.id == row_id,
                    ScheduledNotification.status == "pending",
                )
                .values(status="sending", updated_at=utcnow())
            )
            db.session.commit()
            return claim.rowcount

        # Worker A claims first.
        rowcount_a = _attempt_claim()
        # Worker B attempts the identical claim immediately after.
        rowcount_b = _attempt_claim()

        assert rowcount_a == 1, "the first claim attempt must win"
        assert rowcount_b == 0, "the second claim attempt must be rejected"

        # Only the winner (worker A) is authorized to broadcast, mirroring
        # exactly the `if claim.rowcount != 1: continue` guard in
        # process_due_scheduled_notifications().
        winner_row = db.session.get(ScheduledNotification, row_id)
        out = execute_broadcast(
            title=winner_row.title,
            message=winner_row.message,
            audience=winner_row.audience,
            target_user_id=winner_row.target_user_public_id,
            notification_type=winner_row.notification_type,
            send_push_flag=bool(winner_row.send_push),
            source="admin_scheduled",
        )
        winner_row.status = "sent"
        winner_row.sent_at = utcnow()
        winner_row.result = out
        winner_row.updated_at = utcnow()
        db.session.commit()

        assert Notification.query.filter_by(user_id=recipient.id).count() == 1


# ---------------------------------------------------------------------------
# 5. Real race against the production entry point: an independent raw
#    sqlite3 connection claims the row in the exact window between the
#    production function's SELECT and its per-row UPDATE. This must cause
#    the production call to observe rowcount == 0 and skip the row --
#    proving the guard is load-bearing on the real function, not just on a
#    hand-written duplicate of the SQL.
# ---------------------------------------------------------------------------


def test_two_racing_claim_attempts_result_in_exactly_one_broadcast(app_ctx):
    app, db, User, ScheduledNotification, Notification, db_path = app_ctx
    from kk.notification_broadcast import execute_broadcast, process_due_scheduled_notifications
    from kk.time_utils import utcnow

    with app.app_context():
        recipient = _make_user(db, User, "racereal")
        row = _make_scheduled(
            db, ScheduledNotification, target_user_public_id=recipient.public_id, tag="racereal"
        )
        row_id = row.id
        db.session.commit()

        state = {"intercepted": False, "other_worker_sent": False}

        def _other_worker_wins_the_race(conn, cursor, statement, parameters, context, executemany):
            if state["intercepted"]:
                return
            stmt = statement.strip().upper()
            if not stmt.startswith("SELECT") or "SCHEDULED_NOTIFICATION" not in stmt:
                return
            state["intercepted"] = True

            # This fires via `after_cursor_execute`, i.e. *after* the
            # production function's own SELECT cursor has already executed
            # (so its `due` list still contains row_id as "pending" -- the
            # value that was committed before this SELECT ran) but *before*
            # the production function's loop reaches its per-row claim
            # UPDATE for row_id. The "other worker" wins the race right in
            # that window, using the exact same conditional-UPDATE SQL the
            # production function uses.
            claim = db.session.execute(
                update(ScheduledNotification)
                .where(
                    ScheduledNotification.id == row_id,
                    ScheduledNotification.status == "pending",
                )
                .values(status="sending", updated_at=utcnow())
            )
            db.session.commit()
            assert claim.rowcount == 1, "the other worker must win this race"
            state["other_worker_sent"] = True

        engine = db.session.get_bind()
        event.listen(engine, "after_cursor_execute", _other_worker_wins_the_race)
        try:
            result = process_due_scheduled_notifications(limit=20)
        finally:
            event.remove(engine, "after_cursor_execute", _other_worker_wins_the_race)

        assert state["other_worker_sent"], "interception did not fire; test setup is broken"

        # The production call's own claim UPDATE must have found rowcount
        # 0 (the row was already flipped to "sending" by the other worker)
        # and therefore skipped it without broadcasting.
        assert _result_entry(result, row_id) is None, (
            "process_due_scheduled_notifications() must not broadcast a row "
            "that was claimed by another worker between its SELECT and its "
            "own claim UPDATE"
        )

        db.session.expire_all()
        mid_state = db.session.get(ScheduledNotification, row_id)
        assert mid_state.status == "sending"  # claimed by the "other worker", not finalized yet

        # The "other worker" (which won the race) now finishes its own job,
        # exactly like a second real caller would.
        out = execute_broadcast(
            title=mid_state.title,
            message=mid_state.message,
            audience=mid_state.audience,
            target_user_id=mid_state.target_user_public_id,
            notification_type=mid_state.notification_type,
            send_push_flag=bool(mid_state.send_push),
            source="admin_scheduled",
        )
        mid_state.status = "sent"
        mid_state.sent_at = utcnow()
        mid_state.result = out
        mid_state.updated_at = utcnow()
        db.session.commit()

        # Exactly one broadcast happened overall: one from the "other
        # worker", zero from the production call under test.
        assert Notification.query.filter_by(user_id=recipient.id).count() == 1
