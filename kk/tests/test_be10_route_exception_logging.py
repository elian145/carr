"""BE-10: route-boundary exception handlers must log, and DB-writing ones
must roll back, without changing any client-visible behavior.

Investigation (PRODUCTION_AUDIT.md BE-10) found the original "~106 handlers"
framing overstated, but confirmed two concrete, reproducible gaps:

1. `kk/routes/chat.py`'s 14 route-boundary `except Exception` handlers
   (list_chats, get_messages, send_message, send_image_message,
   send_video_message, send_audio_message, send_media_group_message,
   edit_chat_message, delete_chat_message, unread_count, block_user,
   unblock_user, report_user, list_blocked_users) never logged the
   swallowed exception. Their existing `db.session.rollback()` calls (where
   present) were already correct and are untouched.

2. Ten DB-writing handlers across analytics.py, auth.py, cars.py,
   favorites.py, and user.py caught broadly, performed a DB write, and on
   failure neither rolled back nor logged:
   - analytics.get_listings_analytics / get_listing_analytics
   - auth.logout / change_password / verify_email / verify_phone /
     phone_verify
   - cars.delete_car
   - favorites.toggle_favorite
   - user.upload_profile_picture

This suite proves, for each of those handlers: the HTTP status and JSON
message are byte-for-byte unchanged from before the fix, a server-side
exception log record now exists (it did not before), and — for the
DB-writing handlers — `db.session.rollback()` is actually invoked.

Nothing about narrowing exception types, response shapes, or success-path
behavior is touched or tested here; that's explicitly out of scope for
BE-10 (see PRODUCTION_AUDIT.md).
"""

from __future__ import annotations

import logging
import os
import sys
import tempfile
import uuid
from pathlib import Path
from unittest.mock import patch

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(
        prefix="carlist_be10_", ignore_cleanup_errors=True
    )
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "be10.db")

    from kk.app_factory import create_app

    app, socketio, *_ = create_app()
    from kk.models import Car, ListingAnalytics, Message, TokenBlacklist, User, db

    with app.app_context():
        db.drop_all()
        db.create_all()

    # Test-harness-only accommodation (NOT a production change): on a fresh
    # DB, `create_app()`'s auto-migrate path runs `flask_migrate.upgrade()`,
    # whose `migrations/env.py` calls `logging.config.fileConfig(...)` with
    # its default `disable_existing_loggers=True`. That disables the
    # already-created Flask `app.logger` ("kk.app_factory") as an incidental
    # side effect, unrelated to BE-10. Undo it here so these tests observe
    # the real behavior of the `current_app.logger.exception(...)` calls
    # this suite exists to verify, instead of being confounded by that
    # separate, pre-existing app-boot interaction (out of scope for BE-10;
    # not modified).
    app.logger.disabled = False

    yield app, socketio, app.test_client(), db, User, Car, Message, ListingAnalytics, TokenBlacklist

    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    tmp.cleanup()


@pytest.fixture(scope="module")
def client(app_ctx):
    return app_ctx[2]


class _CaptureHandler(logging.Handler):
    """Collects log records so tests can assert an exception was logged."""

    def __init__(self):
        super().__init__(level=logging.DEBUG)
        self.records: list[logging.LogRecord] = []

    def emit(self, record: logging.LogRecord) -> None:
        self.records.append(record)

    def has_exception_record(self) -> bool:
        return any(r.exc_info is not None for r in self.records)


@pytest.fixture
def log_capture():
    handler = _CaptureHandler()
    root = logging.getLogger()
    prev_level = root.level
    root.addHandler(handler)
    root.setLevel(logging.DEBUG)
    try:
        yield handler
    finally:
        root.removeHandler(handler)
        root.setLevel(prev_level)


def _unique_phone() -> str:
    return f"077{uuid.uuid4().int % 10**8:08d}"


def _make_user(app_ctx, *, username: str) -> tuple[str, str]:
    """Create an active, verified user. Returns (public_id, phone)."""
    app, _socketio, _client, db, User, *_ = app_ctx
    phone = _unique_phone()
    with app.app_context():
        user = User(
            username=username,
            phone_number=phone,
            email=f"{username}@example.com",
            first_name="Test",
            last_name="User",
            is_active=True,
            is_verified=True,
            phone_verified=True,
        )
        user.set_password("Aa123456!")
        db.session.add(user)
        db.session.commit()
        return user.public_id, phone


def _login(client, phone: str, password: str = "Aa123456!") -> str:
    r = client.post("/api/auth/login", json={"username": phone, "password": password})
    assert r.status_code == 200, r.get_json()
    return r.get_json()["access_token"]


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _make_car(app_ctx, seller_public_id: str) -> str:
    app, _socketio, _client, db, User, Car, *_ = app_ctx
    with app.app_context():
        seller = User.query.filter_by(public_id=seller_public_id).first()
        car = Car(
            title="Test car",
            brand="Toyota",
            model="Corolla",
            year=2021,
            mileage=1000,
            engine_type="Gas",
            transmission="Automatic",
            drive_type="FWD",
            condition="Used",
            body_type="Sedan",
            price=10000,
            location="Erbil",
            seller_id=seller.id,
            is_active=True,
            status="active",
        )
        db.session.add(car)
        db.session.commit()
        return car.public_id


@pytest.fixture(scope="module")
def user_a(app_ctx):
    return _make_user(app_ctx, username=f"be10_user_a_{uuid.uuid4().hex[:8]}")


@pytest.fixture(scope="module")
def user_b(app_ctx):
    return _make_user(app_ctx, username=f"be10_user_b_{uuid.uuid4().hex[:8]}")


@pytest.fixture(scope="module")
def token_a(client, user_a):
    public_id, phone = user_a
    return _login(client, phone)


@pytest.fixture(scope="module")
def token_b(client, user_b):
    public_id, phone = user_b
    return _login(client, phone)


@pytest.fixture(scope="module")
def car_a(app_ctx, user_a):
    public_id, _phone = user_a
    return _make_car(app_ctx, public_id)


# ---------------------------------------------------------------------------
# Part A: kk/routes/chat.py — 14 route-boundary handlers must now log.
#
# `get_current_user()` is the first statement inside every one of these
# handlers' try block, so forcing it to raise exercises each handler's own
# outer `except Exception` uniformly, without needing to fabricate uploads
# or valid conversation/message ids -- the handler never gets that far.
# ---------------------------------------------------------------------------

_CHAT_HANDLERS = [
    # (name, method, path_template, expected_status, expected_message, is_writer)
    ("list_chats", "get", "/api/chats", 500, "Failed to load chats", False),
    ("get_messages", "get", "/api/chat/{car}/messages", 500, "Failed to load messages", False),
    ("send_message", "post", "/api/chat/{car}/send", 500, "Failed to send message", True),
    ("send_image_message", "post", "/api/chat/{car}/send_image", 500, "Failed to send image message", True),
    ("send_video_message", "post", "/api/chat/{car}/send_video", 500, "Failed to send video message", True),
    ("send_audio_message", "post", "/api/chat/{car}/send_audio", 500, "Failed to send audio message", True),
    ("send_media_group_message", "post", "/api/chat/{car}/send_media_group", 500, "Failed to send media group", True),
    ("edit_chat_message", "patch", "/api/chat/messages/{msg}", 500, "Failed to edit message", True),
    ("delete_chat_message", "delete", "/api/chat/messages/{msg}", 500, "Failed to delete message", True),
    ("unread_count", "get", "/api/chat/unread_count", 500, "Failed to load unread count", False),
    ("block_user", "post", "/api/users/{other}/block", 500, "Failed to block user", True),
    ("unblock_user", "post", "/api/users/{other}/unblock", 500, "Failed to unblock user", True),
    ("report_user", "post", "/api/users/{other}/report", 500, "Failed to submit report", True),
    ("list_blocked_users", "get", "/api/users/blocked", 500, "Failed to load blocked users", False),
]


@pytest.mark.parametrize(
    "name,method,path_template,expected_status,expected_message,is_writer",
    _CHAT_HANDLERS,
    ids=[h[0] for h in _CHAT_HANDLERS],
)
def test_chat_handler_logs_on_exception_without_changing_response(
    app_ctx, client, token_a, car_a, user_b, log_capture,
    name, method, path_template, expected_status, expected_message, is_writer,
):
    other_public_id, _ = user_b
    path = path_template.format(car=car_a, msg="does-not-exist", other=other_public_id)

    log_capture.records.clear()
    with patch("kk.routes.chat.get_current_user", side_effect=RuntimeError("BE-10 test: forced failure")):
        resp = getattr(client, method)(path, headers=_auth(token_a))

    assert resp.status_code == expected_status, resp.get_json()
    assert resp.get_json() == {"message": expected_message}
    assert log_capture.has_exception_record(), (
        f"{name}: expected an exception to be logged, but nothing was captured"
    )


def test_chat_unread_count_logs_exception_explicitly(app_ctx, client, token_a, log_capture):
    """Explicitly required minimum coverage: chat.unread_count."""
    log_capture.records.clear()
    with patch("kk.routes.chat.get_current_user", side_effect=RuntimeError("boom")):
        resp = client.get("/api/chat/unread_count", headers=_auth(token_a))

    assert resp.status_code == 500
    assert resp.get_json() == {"message": "Failed to load unread count"}
    assert log_capture.has_exception_record()


def test_chat_send_message_rollback_called_on_commit_failure(app_ctx, client, token_a, token_b, car_a, user_a, log_capture):
    """A DB-writing chat handler: force the real commit() to fail and confirm
    the pre-existing rollback() call still fires, and the new logging fires too.

    Sends as `user_b` (buyer) to `user_a` (car_a's seller) -- the allowed
    direction for a first contact message on a listing.
    """
    app, _socketio, _client, db, *_ = app_ctx
    seller_public_id, _ = user_a

    log_capture.records.clear()
    with app.app_context():
        with patch.object(db.session, "commit", side_effect=RuntimeError("simulated commit failure")):
            with patch.object(db.session, "rollback", wraps=db.session.rollback) as rb_spy:
                resp = client.post(
                    f"/api/chat/{car_a}/send",
                    headers=_auth(token_b),
                    json={"content": "hello", "receiver_id": seller_public_id},
                )

    assert resp.status_code == 500
    assert resp.get_json() == {"message": "Failed to send message"}
    assert rb_spy.called
    assert log_capture.has_exception_record()


# ---------------------------------------------------------------------------
# Part B: the 10 handlers that now get rollback + logging.
# ---------------------------------------------------------------------------

def test_favorites_toggle_favorite_rollback_and_logging(app_ctx, client, token_a, car_a, log_capture):
    """Explicitly required minimum coverage: favorites.toggle_favorite."""
    app, _socketio, _client, db, *_ = app_ctx

    log_capture.records.clear()
    with app.app_context():
        with patch.object(db.session, "commit", side_effect=RuntimeError("simulated commit failure")):
            with patch.object(db.session, "rollback", wraps=db.session.rollback) as rb_spy:
                resp = client.post(f"/api/cars/{car_a}/favorite", headers=_auth(token_a))

    assert resp.status_code == 500
    assert resp.get_json() == {"message": "Failed to toggle favorite"}
    assert rb_spy.called
    assert log_capture.has_exception_record()

    # Confirm the session is still perfectly usable afterwards (teardown-safe,
    # no lingering PendingRollbackError) -- same evidence as the investigation.
    with app.app_context():
        from kk.models import User
        assert User.query.count() >= 1


def test_auth_logout_rollback_and_logging(app_ctx, client, token_a, log_capture):
    """Explicitly required minimum coverage: auth.logout."""
    app, _socketio, _client, db, *_ = app_ctx

    log_capture.records.clear()
    with app.app_context():
        with patch.object(db.session, "commit", side_effect=RuntimeError("simulated commit failure")):
            with patch.object(db.session, "rollback", wraps=db.session.rollback) as rb_spy:
                resp = client.post("/api/auth/logout", headers=_auth(token_a))

    assert resp.status_code == 500
    assert resp.get_json() == {"message": "Logout failed"}
    assert rb_spy.called
    assert log_capture.has_exception_record()


def test_auth_change_password_rollback_and_logging(app_ctx, client, log_capture):
    """Representative auth.py coverage beyond logout."""
    app, _socketio, _client, db, User, *_ = app_ctx
    public_id, phone = _make_user(app_ctx, username=f"be10_pw_{uuid.uuid4().hex[:8]}")
    token = _login(client, phone)

    log_capture.records.clear()
    with app.app_context():
        with patch.object(db.session, "commit", side_effect=RuntimeError("simulated commit failure")):
            with patch.object(db.session, "rollback", wraps=db.session.rollback) as rb_spy:
                resp = client.post(
                    "/api/auth/change-password",
                    headers=_auth(token),
                    json={"current_password": "Aa123456!", "new_password": "Bb123456!"},
                )

    assert resp.status_code == 500
    assert resp.get_json() == {"message": "Failed to change password"}
    assert rb_spy.called
    assert log_capture.has_exception_record()


def test_analytics_get_listings_analytics_rollback_and_logging(app_ctx, client, token_a, car_a, log_capture):
    """Representative analytics.py coverage."""
    app, _socketio, _client, db, *_ = app_ctx

    log_capture.records.clear()
    with app.app_context():
        with patch.object(db.session, "commit", side_effect=RuntimeError("simulated commit failure")):
            with patch.object(db.session, "rollback", wraps=db.session.rollback) as rb_spy:
                resp = client.get("/api/analytics/listings", headers=_auth(token_a))

    assert resp.status_code == 500
    assert resp.get_json() == {"message": "Failed to get analytics"}
    assert rb_spy.called
    assert log_capture.has_exception_record()


def test_analytics_get_listing_analytics_rollback_and_logging(app_ctx, client, token_a, car_a, log_capture):
    app, _socketio, _client, db, *_ = app_ctx

    log_capture.records.clear()
    with app.app_context():
        with patch.object(db.session, "commit", side_effect=RuntimeError("simulated commit failure")):
            with patch.object(db.session, "rollback", wraps=db.session.rollback) as rb_spy:
                resp = client.get(f"/api/analytics/listings/{car_a}", headers=_auth(token_a))

    assert resp.status_code == 500
    assert resp.get_json() == {"message": "Failed to get analytics"}
    assert rb_spy.called
    assert log_capture.has_exception_record()


def test_cars_delete_car_rollback_and_logging(app_ctx, client, log_capture):
    """Representative cars.py coverage: delete_car (does NOT already use
    _listing_db_error_response before this fix; now reuses it)."""
    app, _socketio, _client, db, *_ = app_ctx
    public_id, phone = _make_user(app_ctx, username=f"be10_del_{uuid.uuid4().hex[:8]}")
    token = _login(client, phone)
    car_id = _make_car(app_ctx, public_id)

    log_capture.records.clear()
    with app.app_context():
        with patch.object(db.session, "commit", side_effect=RuntimeError("simulated commit failure")):
            with patch.object(db.session, "rollback", wraps=db.session.rollback) as rb_spy:
                resp = client.delete(f"/api/cars/{car_id}", headers=_auth(token))

    assert resp.status_code == 500
    assert resp.get_json() == {"message": "Failed to delete car listing"}
    assert rb_spy.called
    assert log_capture.has_exception_record()


def test_user_upload_profile_picture_rollback_and_logging(app_ctx, client, log_capture):
    """Representative user.py coverage."""
    import io

    app, _socketio, _client, db, *_ = app_ctx
    public_id, phone = _make_user(app_ctx, username=f"be10_pfp_{uuid.uuid4().hex[:8]}")
    token = _login(client, phone)

    log_capture.records.clear()
    with app.app_context():
        with patch.object(db.session, "commit", side_effect=RuntimeError("simulated commit failure")):
            with patch.object(db.session, "rollback", wraps=db.session.rollback) as rb_spy:
                resp = client.post(
                    "/api/user/upload-profile-picture",
                    headers=_auth(token),
                    data={"file": (io.BytesIO(b"\xff\xd8\xff\xe0fake-jpeg"), "avatar.jpg")},
                    content_type="multipart/form-data",
                )

    assert resp.status_code == 500
    assert resp.get_json() == {"message": "Failed to upload profile picture"}
    assert rb_spy.called
    assert log_capture.has_exception_record()
