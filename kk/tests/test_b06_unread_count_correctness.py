"""B-06 regression tests: chat unread-count correctness.

Bug (PRODUCTION_AUDIT.md B-06): ``GET /api/chat/unread_count`` (the global
unread badge) counted every unread message addressed to the current user,
including messages from a sender the current user has blocked and messages
that were soft-deleted (``Message.is_deleted == True``, rendered to the user
as "This message was deleted"). The conversation-list unread tally
(``GET /api/chats``) already excluded blocked senders but also failed to
exclude soft-deleted messages.

Fix: both queries now additionally filter ``Message.is_deleted == False``,
and the global endpoint now also excludes messages whose sender is in the
current user's ``BlockedUser`` block-list — reusing the exact same
``BlockedUser.query.filter_by(blocker_id=...)`` semantics already used by
``list_chats()`` and ``get_chat_history()`` in this file. Neither the
response shape nor the receiver/sender semantics changed.

These tests drive the real Flask app + SQLite DB via the test client
(matching the existing pattern in ``test_be17_blocked_users_batch_fetch.py``
and ``test_chat_rest_delivery.py``), creating ``Message`` rows directly so
each scenario is exact and independent of chat-send side effects (push,
sockets, notifications), which are out of scope for B-06.
"""

from __future__ import annotations

import os
import sys
import tempfile
import uuid
from pathlib import Path

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(
        prefix="carlist_b06_", ignore_cleanup_errors=True
    )
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "b06.db")

    from kk.app_factory import create_app

    app, _socketio, *_ = create_app()
    from kk.models import BlockedUser, Car, Message, User, db

    with app.app_context():
        db.drop_all()
        db.create_all()

    yield app, app.test_client(), db, User, Car, Message, BlockedUser

    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    tmp.cleanup()


def _unique_phone() -> str:
    return f"077{uuid.uuid4().int % 10**8:08d}"


def _make_user(app_ctx, *, username: str) -> str:
    """Create an active, verified user and return their public_id."""
    app, _client, db, User, *_ = app_ctx
    with app.app_context():
        user = User(
            username=username,
            phone_number=_unique_phone(),
            first_name=username.title(),
            last_name="Test",
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id=f"pub-{uuid.uuid4().hex[:12]}",
        )
        user.set_password("Aa123456!")
        db.session.add(user)
        db.session.commit()
        return user.public_id


def _login(client, username: str, password: str = "Aa123456!") -> str:
    r = client.post(
        "/api/auth/login", json={"username": username, "password": password}
    )
    assert r.status_code == 200, r.data
    return r.get_json()["access_token"]


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _make_car(app_ctx, seller_public: str) -> str:
    app, _client, db, User, Car, *_ = app_ctx
    with app.app_context():
        seller = User.query.filter_by(public_id=seller_public).first()
        car = Car(
            seller_id=seller.id,
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
        return car.public_id


def _make_message(
    app_ctx,
    *,
    car_public: str,
    sender_public: str,
    receiver_public: str,
    is_read: bool = False,
    is_deleted: bool = False,
    content: str = "hi",
) -> int:
    """Insert a Message row directly, bypassing the send routes — B-06 is a
    read-query fix, not a send-path fix, so the fixture stays minimal."""
    app, _client, db, User, Car, Message, _BlockedUser = app_ctx
    with app.app_context():
        car = Car.query.filter_by(public_id=car_public).first()
        sender = User.query.filter_by(public_id=sender_public).first()
        receiver = User.query.filter_by(public_id=receiver_public).first()
        msg = Message(
            car_id=car.id,
            sender_id=sender.id,
            receiver_id=receiver.id,
            content=content,
            message_type="text",
            is_read=is_read,
            is_deleted=is_deleted,
        )
        db.session.add(msg)
        db.session.commit()
        return msg.id


def _block(app_ctx, *, blocker_public: str, blocked_public: str) -> None:
    app, _client, db, User, _Car, _Message, BlockedUser = app_ctx
    with app.app_context():
        blocker = User.query.filter_by(public_id=blocker_public).first()
        blocked = User.query.filter_by(public_id=blocked_public).first()
        db.session.add(BlockedUser(blocker_id=blocker.id, blocked_id=blocked.id))
        db.session.commit()


def _unread_count(client, token: str) -> int:
    r = client.get("/api/chat/unread_count", headers=_auth(token))
    assert r.status_code == 200, r.data
    body = r.get_json()
    assert set(body.keys()) == {"unread_count"}, body
    return body["unread_count"]


def _conversation_unread(client, token: str, car_public: str) -> int:
    r = client.get("/api/chats", headers=_auth(token))
    assert r.status_code == 200, r.data
    rows = [c for c in r.get_json() if c["car_id"] == car_public]
    if not rows:
        return 0
    assert len(rows) == 1, rows
    return rows[0]["unread_count"]


# --------------------------------------------------------------------------
# 1) Normal unread messages count.
# --------------------------------------------------------------------------


def test_unread_count_counts_normal_unread_messages(app_ctx):
    app, client, *_ = app_ctx
    receiver_username = f"b06_r1_{uuid.uuid4().hex[:8]}"
    sender_username = f"b06_s1_{uuid.uuid4().hex[:8]}"
    receiver_public = _make_user(app_ctx, username=receiver_username)
    sender_public = _make_user(app_ctx, username=sender_username)
    car_public = _make_car(app_ctx, sender_public)

    _make_message(
        app_ctx, car_public=car_public, sender_public=sender_public,
        receiver_public=receiver_public, is_read=False,
    )
    _make_message(
        app_ctx, car_public=car_public, sender_public=sender_public,
        receiver_public=receiver_public, is_read=False,
    )

    token = _login(client, receiver_username)
    assert _unread_count(client, token) == 2


# --------------------------------------------------------------------------
# 2) Read messages do not count.
# --------------------------------------------------------------------------


def test_unread_count_excludes_read_messages(app_ctx):
    app, client, *_ = app_ctx
    receiver_username = f"b06_r2_{uuid.uuid4().hex[:8]}"
    sender_username = f"b06_s2_{uuid.uuid4().hex[:8]}"
    receiver_public = _make_user(app_ctx, username=receiver_username)
    sender_public = _make_user(app_ctx, username=sender_username)
    car_public = _make_car(app_ctx, sender_public)

    _make_message(
        app_ctx, car_public=car_public, sender_public=sender_public,
        receiver_public=receiver_public, is_read=True,
    )
    _make_message(
        app_ctx, car_public=car_public, sender_public=sender_public,
        receiver_public=receiver_public, is_read=False,
    )

    token = _login(client, receiver_username)
    assert _unread_count(client, token) == 1


# --------------------------------------------------------------------------
# 3) Soft-deleted unread message does not count in the global endpoint.
# --------------------------------------------------------------------------


def test_unread_count_excludes_soft_deleted_messages(app_ctx):
    app, client, *_ = app_ctx
    receiver_username = f"b06_r3_{uuid.uuid4().hex[:8]}"
    sender_username = f"b06_s3_{uuid.uuid4().hex[:8]}"
    receiver_public = _make_user(app_ctx, username=receiver_username)
    sender_public = _make_user(app_ctx, username=sender_username)
    car_public = _make_car(app_ctx, sender_public)

    _make_message(
        app_ctx, car_public=car_public, sender_public=sender_public,
        receiver_public=receiver_public, is_read=False, is_deleted=True,
    )
    _make_message(
        app_ctx, car_public=car_public, sender_public=sender_public,
        receiver_public=receiver_public, is_read=False, is_deleted=False,
    )

    token = _login(client, receiver_username)
    assert _unread_count(client, token) == 1


# --------------------------------------------------------------------------
# 4) Message from a sender blocked by the current user does not count
#    globally, while (5) a non-blocked sender's message still does.
# --------------------------------------------------------------------------


def test_unread_count_excludes_blocked_sender_but_counts_others(app_ctx):
    app, client, *_ = app_ctx
    receiver_username = f"b06_r4_{uuid.uuid4().hex[:8]}"
    blocked_sender_username = f"b06_blocked_{uuid.uuid4().hex[:8]}"
    ok_sender_username = f"b06_ok_{uuid.uuid4().hex[:8]}"
    receiver_public = _make_user(app_ctx, username=receiver_username)
    blocked_sender_public = _make_user(app_ctx, username=blocked_sender_username)
    ok_sender_public = _make_user(app_ctx, username=ok_sender_username)
    car_public = _make_car(app_ctx, receiver_public)

    _block(app_ctx, blocker_public=receiver_public, blocked_public=blocked_sender_public)

    _make_message(
        app_ctx, car_public=car_public, sender_public=blocked_sender_public,
        receiver_public=receiver_public, is_read=False,
    )
    _make_message(
        app_ctx, car_public=car_public, sender_public=ok_sender_public,
        receiver_public=receiver_public, is_read=False,
    )

    token = _login(client, receiver_username)
    # Only the non-blocked sender's message counts (5): exactly 1, not 2.
    assert _unread_count(client, token) == 1


# --------------------------------------------------------------------------
# 6) Conversation-list unread tally excludes soft-deleted messages.
# --------------------------------------------------------------------------


def test_conversation_list_unread_excludes_soft_deleted_messages(app_ctx):
    app, client, *_ = app_ctx
    receiver_username = f"b06_r6_{uuid.uuid4().hex[:8]}"
    sender_username = f"b06_s6_{uuid.uuid4().hex[:8]}"
    receiver_public = _make_user(app_ctx, username=receiver_username)
    sender_public = _make_user(app_ctx, username=sender_username)
    car_public = _make_car(app_ctx, sender_public)

    _make_message(
        app_ctx, car_public=car_public, sender_public=sender_public,
        receiver_public=receiver_public, is_read=False, is_deleted=True,
    )
    _make_message(
        app_ctx, car_public=car_public, sender_public=sender_public,
        receiver_public=receiver_public, is_read=False, is_deleted=False,
    )

    token = _login(client, receiver_username)
    assert _conversation_unread(client, token, car_public) == 1


# --------------------------------------------------------------------------
# 7) Conversation-list unread tally still excludes blocked users (existing
#    behavior preserved, not changed by this fix).
# --------------------------------------------------------------------------


def test_conversation_list_unread_still_excludes_blocked_users(app_ctx):
    app, client, *_ = app_ctx
    receiver_username = f"b06_r7_{uuid.uuid4().hex[:8]}"
    blocked_sender_username = f"b06_blocked7_{uuid.uuid4().hex[:8]}"
    receiver_public = _make_user(app_ctx, username=receiver_username)
    blocked_sender_public = _make_user(app_ctx, username=blocked_sender_username)
    car_public = _make_car(app_ctx, receiver_public)

    _block(app_ctx, blocker_public=receiver_public, blocked_public=blocked_sender_public)

    _make_message(
        app_ctx, car_public=car_public, sender_public=blocked_sender_public,
        receiver_public=receiver_public, is_read=False,
    )

    token = _login(client, receiver_username)
    # The blocked sender's conversation must not appear at all (pre-existing
    # behavior, unchanged by this fix).
    assert _conversation_unread(client, token, car_public) == 0


# --------------------------------------------------------------------------
# 8) Mixed messages produce the exact expected count, for both endpoints.
# --------------------------------------------------------------------------


def test_mixed_messages_produce_exact_expected_count(app_ctx):
    app, client, *_ = app_ctx
    receiver_username = f"b06_r8_{uuid.uuid4().hex[:8]}"
    blocked_sender_username = f"b06_blocked8_{uuid.uuid4().hex[:8]}"
    ok_sender_username = f"b06_ok8_{uuid.uuid4().hex[:8]}"
    receiver_public = _make_user(app_ctx, username=receiver_username)
    blocked_sender_public = _make_user(app_ctx, username=blocked_sender_username)
    ok_sender_public = _make_user(app_ctx, username=ok_sender_username)
    car_public = _make_car(app_ctx, receiver_public)

    _block(app_ctx, blocker_public=receiver_public, blocked_public=blocked_sender_public)

    # From the non-blocked sender: 2 genuinely-unread, 1 read, 1 soft-deleted.
    _make_message(
        app_ctx, car_public=car_public, sender_public=ok_sender_public,
        receiver_public=receiver_public, is_read=False,
    )
    _make_message(
        app_ctx, car_public=car_public, sender_public=ok_sender_public,
        receiver_public=receiver_public, is_read=False,
    )
    _make_message(
        app_ctx, car_public=car_public, sender_public=ok_sender_public,
        receiver_public=receiver_public, is_read=True,
    )
    _make_message(
        app_ctx, car_public=car_public, sender_public=ok_sender_public,
        receiver_public=receiver_public, is_read=False, is_deleted=True,
    )
    # From the blocked sender: 3 unread messages that must never count.
    for _ in range(3):
        _make_message(
            app_ctx, car_public=car_public, sender_public=blocked_sender_public,
            receiver_public=receiver_public, is_read=False,
        )

    token = _login(client, receiver_username)
    # Global endpoint: only the 2 genuinely-unread, non-blocked, non-deleted
    # messages count — read (1), deleted (1), and all 3 blocked-sender
    # messages are excluded.
    assert _unread_count(client, token) == 2
    # Conversation-list tally for this car/sender pair: same 2 (blocked
    # sender's messages don't even surface as a conversation row).
    assert _conversation_unread(client, token, car_public) == 2
