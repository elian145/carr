"""C-02: integration tests for the five REST chat-send endpoints' delivery side effects.

Before this fix, `send_message`/`send_audio_message`/`send_media_group_message`
had ad-hoc, duplicated FCM push logic and never emitted a Socket.IO `new_message`
event or created a `Notification` row; `send_image_message`/`send_video_message`
had *no* delivery side effects at all (PRODUCTION_AUDIT.md C-02).

These tests drive the real Flask app + SQLite DB + Socket.IO test client and
assert, for every one of the five REST send endpoints:

  - the message is durably persisted (HTTP 201 + `message` in the DB),
  - exactly one `new_message` Socket.IO event reaches the receiver,
  - exactly one push (`send_push`) call is made,
  - exactly one `Notification` row is created for the receiver,
  - a failure in any single delivery side effect (socket, push, notification,
    or a simulated Socket.IO/Redis outage) never turns the successful send into
    an HTTP 500 — the message is still persisted and 201 is still returned,
  - an unauthorized receiver produces no delivery side effects at all.
"""

from __future__ import annotations

import io
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
        prefix="carlist_c02_", ignore_cleanup_errors=True
    )
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "c02.db")

    from kk.app_factory import create_app

    app, socketio, *_ = create_app()
    from kk.models import Car, Message, Notification, User, db

    with app.app_context():
        db.drop_all()
        db.create_all()

    yield app, socketio, app.test_client(), db, User, Car, Message, Notification

    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    tmp.cleanup()


@pytest.fixture
def client(app_ctx):
    return app_ctx[2]


def _unique_phone() -> str:
    return f"077{uuid.uuid4().int % 10**8:08d}"


def _make_user(app_ctx, *, username: str, phone: str) -> str:
    """Create an active, phone-verified user and return their public_id."""
    app, _socketio, _client, db, User, *_ = app_ctx
    with app.app_context():
        existing = User.query.filter_by(username=username).first()
        if existing:
            return existing.public_id
        user = User(
            username=username,
            phone_number=phone,
            first_name=username.title(),
            last_name="Test",
            email=None,
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id=f"pub-{uuid.uuid4().hex[:12]}",
            # A dummy FCM token so push delivery is actually attempted; the
            # real firebase-admin call is mocked out in each test.
            firebase_token=f"test-fcm-token-{uuid.uuid4().hex[:8]}",
        )
        user.set_password("Aa123456!")
        db.session.add(user)
        db.session.commit()
        return user.public_id


def _login(client, username: str, password: str = "Aa123456!") -> str:
    r = client.post("/api/auth/login", json={"username": username, "password": password})
    assert r.status_code == 200, r.data
    return r.get_json()["access_token"]


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture(scope="module")
def seller_ctx(app_ctx):
    username = f"c02_seller_{uuid.uuid4().hex[:8]}"
    public_id = _make_user(app_ctx, username=username, phone=_unique_phone())
    return username, public_id


@pytest.fixture(scope="module")
def buyer_ctx(app_ctx):
    username = f"c02_buyer_{uuid.uuid4().hex[:8]}"
    public_id = _make_user(app_ctx, username=username, phone=_unique_phone())
    return username, public_id


@pytest.fixture(scope="module")
def stranger_ctx(app_ctx):
    """A third user with no prior chat thread on the listing (used for the
    unauthorized-receiver test)."""
    username = f"c02_stranger_{uuid.uuid4().hex[:8]}"
    public_id = _make_user(app_ctx, username=username, phone=_unique_phone())
    return username, public_id


def _make_car(app_ctx, seller_public_id: str) -> str:
    app, _socketio, _client, db, User, Car, *_ = app_ctx
    with app.app_context():
        seller = User.query.filter_by(public_id=seller_public_id).first()
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


def _connect_socket(app_ctx, token: str):
    app, socketio, flask_client, *_ = app_ctx
    sio_client = socketio.test_client(
        app, flask_test_client=flask_client, query_string=f"token={token}"
    )
    assert sio_client.is_connected(), sio_client.get_received()
    sio_client.get_received()  # drain the initial "connected" event
    return sio_client


def _notification_count(app_ctx, receiver_public_id: str) -> int:
    app, _socketio, _client, db, User, _Car, _Message, Notification = app_ctx
    with app.app_context():
        receiver = User.query.filter_by(public_id=receiver_public_id).first()
        return Notification.query.filter_by(user_id=receiver.id).count()


def _message_count(app_ctx) -> int:
    app, _socketio, _client, db, *_rest = app_ctx
    from kk.models import Message

    with app.app_context():
        return Message.query.count()


# --------------------------------------------------------------------------
# 1) All five endpoints: message persisted + exactly one socket/push/notif.
# --------------------------------------------------------------------------


def _send_text(client, token, car_id, receiver_id, content="hello there"):
    return client.post(
        f"/api/chat/{car_id}/send",
        headers=_auth(token),
        json={"content": content, "receiver_id": receiver_id},
    )


def _send_image(client, token, car_id, receiver_id):
    return client.post(
        f"/api/chat/{car_id}/send_image",
        headers=_auth(token),
        data={
            "receiver_id": receiver_id,
            "file": (io.BytesIO(b"fake-jpeg-bytes"), "photo.jpg"),
        },
        content_type="multipart/form-data",
    )


def _send_video(client, token, car_id, receiver_id):
    return client.post(
        f"/api/chat/{car_id}/send_video",
        headers=_auth(token),
        data={
            "receiver_id": receiver_id,
            "file": (io.BytesIO(b"fake-mp4-bytes"), "clip.mp4"),
        },
        content_type="multipart/form-data",
    )


def _send_audio(client, token, car_id, receiver_id):
    return client.post(
        f"/api/chat/{car_id}/send_audio",
        headers=_auth(token),
        data={
            "receiver_id": receiver_id,
            "file": (io.BytesIO(b"fake-m4a-bytes"), "voice.m4a"),
        },
        content_type="multipart/form-data",
    )


def _send_media_group(client, token, car_id, receiver_id):
    return client.post(
        f"/api/chat/{car_id}/send_media_group",
        headers=_auth(token),
        data={
            "receiver_id": receiver_id,
            "attachments": [
                (io.BytesIO(b"fake-jpeg-bytes"), "a.jpg"),
                (io.BytesIO(b"fake-jpeg-bytes"), "b.jpg"),
            ],
        },
        content_type="multipart/form-data",
    )


_ENDPOINTS = {
    "text": _send_text,
    "image": _send_image,
    "video": _send_video,
    "audio": _send_audio,
    "media_group": _send_media_group,
}


@pytest.mark.parametrize("kind", ["text", "image", "video", "audio", "media_group"])
def test_endpoint_persists_message_and_delivers_exactly_once(
    app_ctx, client, seller_ctx, buyer_ctx, kind
):
    seller_username, seller_public = seller_ctx
    buyer_username, buyer_public = buyer_ctx
    car_public = _make_car(app_ctx, seller_public)

    seller_token = _login(client, seller_username)
    buyer_token = _login(client, buyer_username)

    # Buyer contacts seller first (always allowed on a public listing) so the
    # thread exists; then the seller replies using the endpoint under test.
    first_contact = _send_text(client, buyer_token, car_public, seller_public, content="hi, interested")
    assert first_contact.status_code == 201, first_contact.data

    buyer_socket = _connect_socket(app_ctx, buyer_token)
    before_notifs = _notification_count(app_ctx, buyer_public)

    with patch("kk.chat_realtime.send_push") as push_mock:
        push_mock.return_value = True
        send_fn = _ENDPOINTS[kind]
        response = send_fn(client, seller_token, car_public, buyer_public)

    assert response.status_code == 201, response.data
    body = response.get_json()
    assert body["success"] is True
    assert body["message"]["id"]

    # Exactly one push call to the buyer.
    push_mock.assert_called_once()

    # Exactly one new Notification row for the buyer.
    after_notifs = _notification_count(app_ctx, buyer_public)
    assert after_notifs == before_notifs + 1

    # Exactly one `new_message` socket event reached the buyer.
    received = buyer_socket.get_received()
    new_message_events = [e for e in received if e.get("name") == "new_message"]
    assert len(new_message_events) == 1, received
    assert new_message_events[0]["args"][0]["id"] == body["message"]["id"]

    buyer_socket.disconnect()


# --------------------------------------------------------------------------
# 2) Failure isolation: socket / push / notification failures never turn a
#    successful send into HTTP 500, and the message is still persisted.
# --------------------------------------------------------------------------


def test_socket_failure_still_returns_201_and_persists_message(
    app_ctx, client, seller_ctx, buyer_ctx
):
    seller_username, seller_public = seller_ctx
    buyer_username, buyer_public = buyer_ctx
    car_public = _make_car(app_ctx, seller_public)
    seller_token = _login(client, seller_username)
    buyer_token = _login(client, buyer_username)
    _send_text(client, buyer_token, car_public, seller_public, content="hi")

    before = _message_count(app_ctx)
    with patch(
        "kk.chat_realtime.emit_message_to_participants",
        side_effect=RuntimeError("socket transport down"),
    ):
        response = _send_text(client, seller_token, car_public, buyer_public, content="socket-fail-test")

    assert response.status_code == 201, response.data
    assert _message_count(app_ctx) == before + 1


def test_push_failure_still_returns_201_and_persists_message(
    app_ctx, client, seller_ctx, buyer_ctx
):
    seller_username, seller_public = seller_ctx
    buyer_username, buyer_public = buyer_ctx
    car_public = _make_car(app_ctx, seller_public)
    seller_token = _login(client, seller_username)
    buyer_token = _login(client, buyer_username)
    _send_text(client, buyer_token, car_public, seller_public, content="hi")

    before = _message_count(app_ctx)
    with patch(
        "kk.chat_realtime.send_push",
        side_effect=RuntimeError("fcm exploded"),
    ):
        response = _send_text(client, seller_token, car_public, buyer_public, content="push-fail-test")

    assert response.status_code == 201, response.data
    assert _message_count(app_ctx) == before + 1


def test_notification_failure_still_returns_201_and_persists_message(
    app_ctx, client, seller_ctx, buyer_ctx
):
    seller_username, seller_public = seller_ctx
    buyer_username, buyer_public = buyer_ctx
    car_public = _make_car(app_ctx, seller_public)
    seller_token = _login(client, seller_username)
    buyer_token = _login(client, buyer_username)
    _send_text(client, buyer_token, car_public, seller_public, content="hi")

    before = _message_count(app_ctx)
    with patch(
        "kk.chat_realtime.Notification",
        side_effect=RuntimeError("notification model exploded"),
    ):
        response = _send_text(client, seller_token, car_public, buyer_public, content="notif-fail-test")

    assert response.status_code == 201, response.data
    assert _message_count(app_ctx) == before + 1

    # The session must remain usable for subsequent requests (not left broken).
    follow_up = _send_text(client, seller_token, car_public, buyer_public, content="after-notif-fail")
    assert follow_up.status_code == 201, follow_up.data


def test_redis_socketio_outage_still_returns_201_and_persists_message(
    app_ctx, client, seller_ctx, buyer_ctx
):
    """Simulate the Socket.IO message queue (Redis) being unreachable."""
    seller_username, seller_public = seller_ctx
    buyer_username, buyer_public = buyer_ctx
    car_public = _make_car(app_ctx, seller_public)
    seller_token = _login(client, seller_username)
    buyer_token = _login(client, buyer_username)
    _send_text(client, buyer_token, car_public, seller_public, content="hi")

    before = _message_count(app_ctx)
    with patch(
        "kk.chat_realtime.socketio.emit",
        side_effect=ConnectionError("redis unavailable"),
    ):
        response = _send_text(client, seller_token, car_public, buyer_public, content="redis-down-test")

    assert response.status_code == 201, response.data
    assert _message_count(app_ctx) == before + 1


# --------------------------------------------------------------------------
# 3) Unauthorized receiver: no delivery side effects at all.
# --------------------------------------------------------------------------


def test_unauthorized_receiver_produces_no_delivery_side_effects(
    app_ctx, client, seller_ctx, stranger_ctx
):
    seller_username, seller_public = seller_ctx
    _stranger_username, stranger_public = stranger_ctx
    car_public = _make_car(app_ctx, seller_public)
    seller_token = _login(client, seller_username)

    before_messages = _message_count(app_ctx)
    before_notifs = _notification_count(app_ctx, stranger_public)

    with patch("kk.chat_realtime.deliver_message") as deliver_mock, patch(
        "kk.chat_realtime.send_push"
    ) as push_mock:
        # Seller -> stranger with no prior thread and stranger is not the
        # listing seller: `_resolve_chat_receiver` must reject this.
        response = _send_text(client, seller_token, car_public, stranger_public, content="uninvited")

    assert response.status_code == 400, response.data
    assert response.get_json().get("message") == "receiver_id required or not allowed"

    deliver_mock.assert_not_called()
    push_mock.assert_not_called()
    assert _message_count(app_ctx) == before_messages
    assert _notification_count(app_ctx, stranger_public) == before_notifs


# --------------------------------------------------------------------------
# 4) Explicit no-duplicate tests for text / audio / media_group.
# --------------------------------------------------------------------------


@pytest.mark.parametrize("kind", ["text", "audio", "media_group"])
def test_no_duplicate_push_or_notification_for_a_single_send(
    app_ctx, client, seller_ctx, buyer_ctx, kind
):
    seller_username, seller_public = seller_ctx
    buyer_username, buyer_public = buyer_ctx
    car_public = _make_car(app_ctx, seller_public)
    seller_token = _login(client, seller_username)
    buyer_token = _login(client, buyer_username)
    _send_text(client, buyer_token, car_public, seller_public, content="hi")

    buyer_socket = _connect_socket(app_ctx, buyer_token)
    before_notifs = _notification_count(app_ctx, buyer_public)

    with patch("kk.chat_realtime.send_push") as push_mock:
        push_mock.return_value = True
        send_fn = _ENDPOINTS[kind]
        response = send_fn(client, seller_token, car_public, buyer_public)

    assert response.status_code == 201, response.data
    assert push_mock.call_count == 1, "push must be sent exactly once, not duplicated"

    after_notifs = _notification_count(app_ctx, buyer_public)
    assert after_notifs == before_notifs + 1, "exactly one Notification row, not duplicated"

    received = buyer_socket.get_received()
    new_message_events = [e for e in received if e.get("name") == "new_message"]
    assert len(new_message_events) == 1, "exactly one new_message socket event, not duplicated"

    buyer_socket.disconnect()
