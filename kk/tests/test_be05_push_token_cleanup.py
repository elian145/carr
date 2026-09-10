"""BE-05 regression tests: permanently invalid FCM tokens are cleared.

Bug (PRODUCTION_AUDIT.md BE-05): ``send_push()`` (``kk/push.py``) caught every
FCM exception generically and never distinguished a definitive, permanent
invalid-token error (``UnregisteredError`` / ``SenderIdMismatchError``) from
a transient error (``QuotaExceededError``), a server-credential error
(``ThirdPartyAuthError``), or any other/unknown exception -- so a dead token
was logged and then retried forever, on every future broadcast, saved-search
alert, price-drop alert, and chat message to that user.

Fix (this file's subject): ``send_push()`` now accepts an optional
``user_id`` keyword. If and only if FCM raises one of the real
``firebase_admin.messaging`` SDK's own permanent-invalid-token exception
classes, the stored token is cleared via a single, race-safe conditional
``UPDATE user SET firebase_token = NULL WHERE id = :user_id AND
firebase_token = :token`` (``kk.push._clear_invalidated_token``) -- clearing
it ONLY if it still holds the exact value FCM just rejected, so a token that
changed (refresh, logout, re-login) in the meantime is never clobbered.
Every other exception type (transient, credential, network, unknown) leaves
the token untouched (fail closed). All 6 existing ``send_push()`` call sites
now pass ``user_id`` so the cleanup applies consistently everywhere:

    1. kk/notification_broadcast.py  (execute_broadcast)      -- tests 7, 8
    2. kk/routes/admin.py            (dealer-application push) -- test 12b
    3. kk/socketio_handlers.py       (send_message socket event) -- test 12c
    4. kk/routes/chat.py             (push_test route)          -- test 12a
    5. kk/tasks/alert_tasks.py       (_send_retention_push)      -- test 12d
    6. kk/chat_realtime.py           (deliver_message)           -- test 12e

Explicitly out of scope for this file (per the approved BE-05 plan):
  * FCM batching/multicast (a separate, later performance finding).
  * Multi-device / multiple-tokens-per-user support (pre-existing gap, not
    part of this fix).
  * An ``is_active``/inactive flag or failure counters (deliberately not
    implemented -- see the BE-05 investigation's alternatives-considered
    section).
  * Any change to BE-04's Celery architecture, ``ScheduledNotification``
    state handling, or the immediate-broadcast task -- ``execute_broadcast()``
    itself is exercised here only to prove BE-05 doesn't disturb it.
  * Firebase Console/credentials configuration.
"""

from __future__ import annotations

import os
import sys
import tempfile
import uuid
from pathlib import Path
from unittest import mock

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

os.environ.setdefault("APP_ENV", "testing")
os.environ.setdefault("SECRET_KEY", "test-secret-key-for-be05")
os.environ.setdefault("JWT_SECRET_KEY", "test-jwt-secret-key-for-be05")

from firebase_admin import messaging as fcm_messaging  # noqa: E402

import kk.push as push_module  # noqa: E402

_PASSWORD = "Aa123456!"


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_be05_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "be05.db")

    from kk.app_factory import create_app

    app, socketio, *_ = create_app()
    from kk.models import Car, DealerApplication, Notification, User, db

    with app.app_context():
        db.drop_all()
        db.create_all()

    yield app, socketio, app.test_client(), db, User, Car, Notification, DealerApplication

    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    tmp.cleanup()


@pytest.fixture
def client(app_ctx):
    return app_ctx[2]


@pytest.fixture(autouse=True)
def _stub_firebase_ready(monkeypatch):
    """Make FCM report as "configured" for every test in this module without
    real Firebase credentials, so every ``send_push()`` call site actually
    reaches ``messaging.send()`` (which each test mocks individually to
    succeed/fail as needed). This only stubs the *readiness* check
    (``_ensure_firebase`` / ``_service_account_oauth_ok``); it does not touch
    ``messaging.send`` itself, and it does not touch token-cleanup logic.
    """
    monkeypatch.setattr(push_module, "_ensure_firebase", lambda: object())
    monkeypatch.setattr(push_module, "_service_account_oauth_ok", lambda: True)
    yield


def _phone() -> str:
    return f"078{uuid.uuid4().int % 10**8:08d}"


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _login(client, username: str) -> str:
    r = client.post("/api/auth/login", json={"username": username, "password": _PASSWORD})
    assert r.status_code == 200, r.data
    return r.get_json()["access_token"]


def _make_user(
    app,
    db,
    User,
    *,
    tag: str,
    firebase_token: str | None = None,
    is_admin: bool = False,
):
    with app.app_context():
        username = f"be05_{tag}_{uuid.uuid4().hex[:10]}"
        user = User(
            username=username,
            phone_number=_phone(),
            first_name="Be05",
            last_name="Test",
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id=f"be05-{tag}-{uuid.uuid4().hex[:12]}",
            is_admin=is_admin,
            firebase_token=firebase_token,
        )
        user.set_password(_PASSWORD)
        db.session.add(user)
        db.session.commit()
        return user.id, user.public_id, username


def _make_car(app, db, Car, *, seller_id: int, tag: str):
    with app.app_context():
        car = Car(
            seller_id=seller_id,
            public_id=f"be05-car-{tag}-{uuid.uuid4().hex[:10]}",
            brand="toyota",
            model="corolla",
            year=2021,
            mileage=10,
            engine_type="gas",
            transmission="auto",
            drive_type="fwd",
            condition="used",
            body_type="sedan",
            price=15.0,
            location="Erbil",
            is_active=True,
        )
        db.session.add(car)
        db.session.commit()
        return car.id, car.public_id


def _get_token(app, db, User, user_id: int) -> str | None:
    with app.app_context():
        user = db.session.get(User, user_id)
        return user.firebase_token if user else None


def _send_side_effect(*, fail_token_map: dict[str, BaseException] | None = None):
    """``firebase_admin.messaging.send`` replacement: raises a specific
    exception for specific tokens (matched by ``message.token``); any other
    token succeeds."""
    fail_token_map = fail_token_map or {}

    def _send(message, app=None):
        exc = fail_token_map.get(message.token)
        if exc is not None:
            raise exc
        return "projects/test/messages/fake-id"

    return _send


# ---------------------------------------------------------------------------
# 1-6: send_push() classification -- the shared mechanism used by all 6
# call sites. Firebase's own real SDK exception classes are raised (no
# string/type-name matching in the test, mirroring the production code).
# ---------------------------------------------------------------------------


def test_unregistered_error_clears_token(app_ctx):
    app, _socketio, _client, db, User, *_ = app_ctx
    user_id, _pub, _name = _make_user(app, db, User, tag="unreg", firebase_token="tok-unreg-A")

    with mock.patch(
        "firebase_admin.messaging.send",
        side_effect=_send_side_effect(
            fail_token_map={"tok-unreg-A": fcm_messaging.UnregisteredError("app instance unregistered")}
        ),
    ):
        with app.app_context():
            ok = push_module.send_push("tok-unreg-A", title="t", body="b", user_id=user_id)

    assert ok is False
    assert _get_token(app, db, User, user_id) is None


def test_sender_id_mismatch_error_clears_token(app_ctx):
    app, _socketio, _client, db, User, *_ = app_ctx
    user_id, _pub, _name = _make_user(app, db, User, tag="mismatch", firebase_token="tok-mismatch-A")

    with mock.patch(
        "firebase_admin.messaging.send",
        side_effect=_send_side_effect(
            fail_token_map={"tok-mismatch-A": fcm_messaging.SenderIdMismatchError("sender id mismatch")}
        ),
    ):
        with app.app_context():
            ok = push_module.send_push("tok-mismatch-A", title="t", body="b", user_id=user_id)

    assert ok is False
    assert _get_token(app, db, User, user_id) is None


def test_quota_exceeded_error_does_not_clear_token(app_ctx):
    app, _socketio, _client, db, User, *_ = app_ctx
    user_id, _pub, _name = _make_user(app, db, User, tag="quota", firebase_token="tok-quota-A")

    with mock.patch(
        "firebase_admin.messaging.send",
        side_effect=_send_side_effect(
            fail_token_map={"tok-quota-A": fcm_messaging.QuotaExceededError("rate limited")}
        ),
    ):
        with app.app_context():
            ok = push_module.send_push("tok-quota-A", title="t", body="b", user_id=user_id)

    assert ok is False
    # Transient error -- token must survive untouched.
    assert _get_token(app, db, User, user_id) == "tok-quota-A"


def test_third_party_auth_error_does_not_clear_token(app_ctx):
    app, _socketio, _client, db, User, *_ = app_ctx
    user_id, _pub, _name = _make_user(app, db, User, tag="tpauth", firebase_token="tok-tpauth-A")

    with mock.patch(
        "firebase_admin.messaging.send",
        side_effect=_send_side_effect(
            fail_token_map={"tok-tpauth-A": fcm_messaging.ThirdPartyAuthError("bad APNs credentials")}
        ),
    ):
        with app.app_context():
            ok = push_module.send_push("tok-tpauth-A", title="t", body="b", user_id=user_id)

    assert ok is False
    # Server-credential problem, not a token problem -- must survive untouched.
    assert _get_token(app, db, User, user_id) == "tok-tpauth-A"


def test_unknown_exception_does_not_clear_token(app_ctx):
    app, _socketio, _client, db, User, *_ = app_ctx
    user_id, _pub, _name = _make_user(app, db, User, tag="unknown", firebase_token="tok-unknown-A")

    with mock.patch(
        "firebase_admin.messaging.send",
        side_effect=_send_side_effect(
            fail_token_map={"tok-unknown-A": RuntimeError("some unrelated network blip")}
        ),
    ):
        with app.app_context():
            ok = push_module.send_push("tok-unknown-A", title="t", body="b", user_id=user_id)

    assert ok is False
    # Fail closed: an unrecognized exception type must never clear a token.
    assert _get_token(app, db, User, user_id) == "tok-unknown-A"


def test_successful_send_leaves_token_unchanged(app_ctx):
    app, _socketio, _client, db, User, *_ = app_ctx
    user_id, _pub, _name = _make_user(app, db, User, tag="ok", firebase_token="tok-ok-A")

    with mock.patch("firebase_admin.messaging.send", side_effect=_send_side_effect()):
        with app.app_context():
            ok = push_module.send_push("tok-ok-A", title="t", body="b", user_id=user_id)

    assert ok is True
    assert _get_token(app, db, User, user_id) == "tok-ok-A"


# ---------------------------------------------------------------------------
# 7, 8: execute_broadcast() -- one invalid token doesn't stop the broadcast,
# and a subsequent broadcast never re-attempts an already-cleared token.
# Recipients are injected via a monkeypatched resolve_recipients() so these
# tests are isolated from other users created elsewhere in this module-scoped
# DB, while execute_broadcast()'s own loop/commit/send_push logic (the code
# actually under test) is completely real and unmodified.
# ---------------------------------------------------------------------------


def test_broadcast_one_invalid_token_does_not_stop_other_recipients(app_ctx, monkeypatch):
    app, _socketio, _client, db, User, _Car, Notification, _DA = app_ctx
    a_id, _ap, _an = _make_user(app, db, User, tag="bcastA", firebase_token="tok-bcast-A")
    b_id, _bp, _bn = _make_user(app, db, User, tag="bcastB", firebase_token="tok-bcast-B")
    c_id, _cp, _cn = _make_user(app, db, User, tag="bcastC", firebase_token="tok-bcast-C")

    import kk.notification_broadcast as nb

    send_mock = mock.Mock(
        side_effect=_send_side_effect(
            fail_token_map={"tok-bcast-A": fcm_messaging.UnregisteredError("gone")}
        )
    )

    with app.app_context():
        users = [db.session.get(User, uid) for uid in (a_id, b_id, c_id)]
        monkeypatch.setattr(nb, "resolve_recipients", lambda **kw: (users, None))

        with mock.patch("firebase_admin.messaging.send", send_mock):
            title = f"BE-05 bcast {uuid.uuid4().hex[:8]}"
            result = nb.execute_broadcast(
                title=title,
                message="hello",
                audience="all",
                send_push_flag=True,
                source="test_be05",
            )

        # The broadcast continued for all three recipients despite A's
        # permanent failure -- Notification rows created for everyone.
        assert Notification.query.filter_by(title=title).count() == 3
        assert result["created"] == 3
        # Exactly the two valid tokens (B, C) succeeded.
        assert result["pushed"] == 2

    assert send_mock.call_count == 3, "the loop must not stop early on A's failure"
    assert _get_token(app, db, User, a_id) is None
    assert _get_token(app, db, User, b_id) == "tok-bcast-B"
    assert _get_token(app, db, User, c_id) == "tok-bcast-C"


def test_repeated_broadcast_does_not_retry_permanently_invalid_token(app_ctx, monkeypatch):
    app, _socketio, _client, db, User, _Car, _Notification, _DA = app_ctx
    a_id, _ap, _an = _make_user(app, db, User, tag="repeatA", firebase_token="tok-repeat-A")
    b_id, _bp, _bn = _make_user(app, db, User, tag="repeatB", firebase_token="tok-repeat-B")

    import kk.notification_broadcast as nb

    def _fresh_users():
        return [db.session.get(User, uid) for uid in (a_id, b_id)]

    send_mock = mock.Mock(
        side_effect=_send_side_effect(
            fail_token_map={"tok-repeat-A": fcm_messaging.UnregisteredError("gone")}
        )
    )

    # First broadcast: A fails permanently and its token is cleared.
    with app.app_context():
        monkeypatch.setattr(nb, "resolve_recipients", lambda **kw: (_fresh_users(), None))
        with mock.patch("firebase_admin.messaging.send", send_mock):
            nb.execute_broadcast(
                title=f"BE-05 repeat1 {uuid.uuid4().hex[:8]}",
                message="hi",
                audience="all",
                send_push_flag=True,
            )

    assert _get_token(app, db, User, a_id) is None
    assert send_mock.call_count == 2  # both A and B attempted on the first broadcast

    send_mock.reset_mock()
    # Force a fresh read on the next broadcast, exactly like a brand-new
    # Celery task invocation would get a brand-new session/query.
    with app.app_context():
        db.session.remove()

    # Second broadcast: A now has no stored token at all -- must not be
    # attempted again.
    with app.app_context():
        monkeypatch.setattr(nb, "resolve_recipients", lambda **kw: (_fresh_users(), None))
        with mock.patch("firebase_admin.messaging.send", send_mock):
            result2 = nb.execute_broadcast(
                title=f"BE-05 repeat2 {uuid.uuid4().hex[:8]}",
                message="hi",
                audience="all",
                send_push_flag=True,
            )

    called_tokens = [c.args[0].token for c in send_mock.call_args_list]
    assert "tok-repeat-A" not in called_tokens
    assert send_mock.call_count == 1, "only B's still-valid token may be attempted"
    assert result2["pushed"] == 1
    # Notification rows are still created for both recipients regardless of
    # push outcome -- BE-05 must not change Notification fan-out semantics.
    assert result2["created"] == 2


# ---------------------------------------------------------------------------
# 9: CRITICAL race test -- exercises the REAL conditional UPDATE (not a
# mocked cleanup helper). A concurrent write changes the token to a new
# value between the failed FCM call and the cleanup; the new value must
# survive untouched.
# ---------------------------------------------------------------------------


def test_race_concurrent_token_refresh_is_not_clobbered_by_cleanup(app_ctx):
    app, _socketio, _client, db, User, *_ = app_ctx
    flask_app = app
    user_id, _pub, _name = _make_user(app, db, User, tag="race", firebase_token="token-A")

    def _send_and_race(message, app=None):
        # Signature intentionally mirrors the real call site exactly
        # (``messaging.send(message, app=app)``) so a mock patch actually
        # runs instead of raising TypeError on an unexpected keyword.
        #
        # Simulate the exact race the BE-05 fix must survive: between the
        # worker reading "token-A" and FCM's rejection response arriving,
        # the user's device refreshes to a new token and re-registers it
        # with the backend -- a real, independent, committed write to the
        # same row.
        with flask_app.app_context():
            u = db.session.get(User, user_id)
            u.firebase_token = "token-B"
            db.session.commit()
        raise fcm_messaging.UnregisteredError("gone")

    with mock.patch("firebase_admin.messaging.send", side_effect=_send_and_race):
        with app.app_context():
            ok = push_module.send_push("token-A", title="t", body="b", user_id=user_id)

    assert ok is False
    # The conditional UPDATE only matches firebase_token == "token-A"; since
    # it had already changed to "token-B" by the time cleanup ran, the real
    # database UPDATE must affect 0 rows and token-B must survive.
    assert _get_token(app, db, User, user_id) == "token-B"


# ---------------------------------------------------------------------------
# 10: cleanup is a safe no-op when the token was already cleared (0 rows
# affected must never raise or break the caller).
# ---------------------------------------------------------------------------


def test_cleanup_is_noop_when_token_already_cleared(app_ctx):
    app, _socketio, _client, db, User, *_ = app_ctx
    user_id, _pub, _name = _make_user(app, db, User, tag="alreadyclear", firebase_token=None)

    with app.app_context():
        # Directly exercise the real conditional UPDATE with a token value
        # that no longer matches anything for this user (already None).
        push_module._clear_invalidated_token(user_id, "some-stale-token-value")

    assert _get_token(app, db, User, user_id) is None


# ---------------------------------------------------------------------------
# 11: existing logout / admin-purge / account-deletion token handling is
# unaffected by BE-05 (these routes already cleared firebase_token before
# this change and must continue to do so, unmodified).
# ---------------------------------------------------------------------------


def test_logout_still_clears_firebase_token(app_ctx):
    app, _socketio, client, db, User, *_ = app_ctx
    user_id, _pub, username = _make_user(app, db, User, tag="logout", firebase_token="tok-logout")
    token = _login(client, username)

    resp = client.post("/api/auth/logout", headers=_auth(token))
    assert resp.status_code == 200, resp.data
    assert _get_token(app, db, User, user_id) is None


def test_admin_purge_still_clears_firebase_token(app_ctx):
    app, _socketio, client, db, User, *_ = app_ctx
    _admin_id, _ap, admin_name = _make_user(app, db, User, tag="purgeadmin", is_admin=True)
    target_id, target_pub, _tn = _make_user(app, db, User, tag="purgetarget", firebase_token="tok-purge")

    token = _login(client, admin_name)
    resp = client.delete(f"/api/admin/users/{target_pub}/purge", headers=_auth(token))
    assert resp.status_code == 200, resp.data
    assert _get_token(app, db, User, target_id) is None


def test_delete_account_hard_delete_removes_user_row(app_ctx):
    app, _socketio, client, db, User, *_ = app_ctx
    user_id, _pub, username = _make_user(app, db, User, tag="delacct", firebase_token="tok-delacct")
    token = _login(client, username)

    resp = client.post(
        "/api/auth/delete-account",
        json={"password": _PASSWORD},
        headers=_auth(token),
    )
    assert resp.status_code == 200, resp.data
    with app.app_context():
        assert db.session.get(User, user_id) is None


# ---------------------------------------------------------------------------
# 12: all 6 send_push() call sites individually covered end-to-end.
# (12b is the admin dealer-approval push; 12c is the socketio send_message
# event; 12a is the chat.py push_test route; 12d is alert_tasks retention
# push; 12e is chat_realtime.deliver_message. execute_broadcast() -- call
# site 1 -- is covered by tests 7 and 8 above.)
# ---------------------------------------------------------------------------


def test_12a_push_test_route_clears_permanently_invalid_token(app_ctx):
    app, _socketio, client, db, User, *_ = app_ctx
    user_id, _pub, username = _make_user(app, db, User, tag="pushtest", firebase_token="tok-pushtest")
    token = _login(client, username)

    with mock.patch(
        "firebase_admin.messaging.send",
        side_effect=fcm_messaging.UnregisteredError("gone"),
    ):
        resp = client.post("/api/users/push_test", headers=_auth(token))

    assert resp.status_code == 503, resp.data
    assert _get_token(app, db, User, user_id) is None


def test_12b_admin_dealer_approval_push_clears_permanently_invalid_token(app_ctx):
    app, _socketio, client, db, User, _Car, _Notification, DealerApplication = app_ctx
    _admin_id, _ap, admin_name = _make_user(app, db, User, tag="dealeradmin", is_admin=True)
    dealer_id, dealer_pub, _dn = _make_user(app, db, User, tag="dealertarget", firebase_token="tok-dealer")

    with app.app_context():
        appn = DealerApplication(
            user_id=dealer_id,
            status="submitted",
            dealership_name="BE-05 Test Motors",
            dealership_phone="07700000000",
            dealership_location="Erbil",
        )
        db.session.add(appn)
        db.session.commit()

    token = _login(client, admin_name)
    with mock.patch(
        "firebase_admin.messaging.send",
        side_effect=fcm_messaging.UnregisteredError("gone"),
    ):
        resp = client.post(f"/api/admin/dealers/{dealer_pub}/approve", headers=_auth(token))

    assert resp.status_code == 200, resp.data
    assert _get_token(app, db, User, dealer_id) is None


def test_12c_socketio_send_message_clears_permanently_invalid_receiver_token(app_ctx):
    app, socketio, client, db, User, Car, _Notification, _DA = app_ctx
    buyer_id, _bp, buyer_name = _make_user(app, db, User, tag="siobuyer")
    seller_id, seller_pub, _sn = _make_user(app, db, User, tag="sioseller", firebase_token="tok-sio")
    _car_id, car_pub = _make_car(app, db, Car, seller_id=seller_id, tag="sio")

    buyer_token = _login(client, buyer_name)
    sio_client = socketio.test_client(app, flask_test_client=client, query_string=f"token={buyer_token}")
    assert sio_client.is_connected(), sio_client.get_received()
    sio_client.get_received()  # drain the initial "connected" event

    with mock.patch(
        "firebase_admin.messaging.send",
        side_effect=fcm_messaging.UnregisteredError("gone"),
    ):
        sio_client.emit(
            "send_message",
            {"car_id": car_pub, "content": "hello via socket", "receiver_id": seller_pub},
        )
        sio_client.get_received()

    sio_client.disconnect()

    assert _get_token(app, db, User, seller_id) is None


def test_12d_retention_push_clears_permanently_invalid_token(app_ctx):
    app, _socketio, _client, db, User, *_ = app_ctx
    user_id, _pub, _name = _make_user(app, db, User, tag="retention", firebase_token="tok-retention")

    from kk.tasks.alert_tasks import _send_retention_push

    with app.app_context():
        user = db.session.get(User, user_id)
        with mock.patch(
            "firebase_admin.messaging.send",
            side_effect=fcm_messaging.UnregisteredError("gone"),
        ):
            _send_retention_push(
                user,
                title="Price drop",
                body="cheaper now",
                notification_type="price_drop",
                data={},
            )

    assert _get_token(app, db, User, user_id) is None


def test_12e_deliver_message_clears_permanently_invalid_receiver_token(app_ctx):
    app, _socketio, _client, db, User, Car, _Notification, _DA = app_ctx
    sender_id, _sp, _sn = _make_user(app, db, User, tag="delivsender")
    receiver_id, _rp, _rn = _make_user(app, db, User, tag="delivreceiver", firebase_token="tok-deliver")
    car_id, _cp = _make_car(app, db, Car, seller_id=receiver_id, tag="deliv")

    from kk.chat_realtime import deliver_message
    from kk.models import Message

    with app.app_context():
        sender = db.session.get(User, sender_id)
        receiver = db.session.get(User, receiver_id)

        msg = Message(
            sender_id=sender.id,
            receiver_id=receiver.id,
            car_id=car_id,
            content="hi",
            message_type="text",
        )
        db.session.add(msg)
        db.session.commit()
        db.session.refresh(msg)

        with mock.patch(
            "firebase_admin.messaging.send",
            side_effect=fcm_messaging.UnregisteredError("gone"),
        ):
            deliver_message(msg, sender=sender, receiver=receiver)

    assert _get_token(app, db, User, receiver_id) is None
