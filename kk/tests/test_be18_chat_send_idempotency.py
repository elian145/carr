"""BE-18: idempotency for the five REST chat-send endpoints.

Before this fix, a client retry of a chat-send request — the automatic
client-side timeout retry in `_sendWithAdaptiveTimeout`
(lib/services/api/api_http.dart), the 401-token-refresh retry, or a
user-initiated resend — had no way to tell the server "this is the same
logical send", so every retry inserted a brand-new `Message` row: a visible
duplicate message, plus a duplicate push notification, a duplicate
`Notification` row, and a duplicate Socket.IO `new_message` event
(PRODUCTION_AUDIT.md BE-18).

`kk/idempotency.py` already implements `replay_response()` /
`remember_response()` for `POST /api/cars` (create_car, API-01). This suite
verifies the same helper — with the exact same semantics, not a new system —
is now wired into all five chat-send endpoints:

    POST /api/chat/<id>/send
    POST /api/chat/<id>/send_image
    POST /api/chat/<id>/send_video
    POST /api/chat/<id>/send_audio
    POST /api/chat/<id>/send_media_group
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
        prefix="carlist_be18_", ignore_cleanup_errors=True
    )
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "be18.db")

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


def _auth(token: str, idem_key: str | None = None) -> dict:
    headers = {"Authorization": f"Bearer {token}"}
    if idem_key is not None:
        headers["Idempotency-Key"] = idem_key
    return headers


@pytest.fixture(scope="module")
def seller_ctx(app_ctx):
    username = f"be18_seller_{uuid.uuid4().hex[:8]}"
    public_id = _make_user(app_ctx, username=username, phone=_unique_phone())
    return username, public_id


@pytest.fixture(scope="module")
def buyer_ctx(app_ctx):
    username = f"be18_buyer_{uuid.uuid4().hex[:8]}"
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


def _message_count(app_ctx) -> int:
    app, _socketio, _client, db, _User, _Car, Message, *_ = app_ctx
    with app.app_context():
        return Message.query.count()


def _notification_count(app_ctx, receiver_public_id: str) -> int:
    app, _socketio, _client, db, User, _Car, _Message, Notification = app_ctx
    with app.app_context():
        receiver = User.query.filter_by(public_id=receiver_public_id).first()
        return Notification.query.filter_by(user_id=receiver.id).count()


def _connect_socket(app_ctx, token: str):
    app, socketio, flask_client, *_ = app_ctx
    sio_client = socketio.test_client(
        app, flask_test_client=flask_client, query_string=f"token={token}"
    )
    assert sio_client.is_connected(), sio_client.get_received()
    sio_client.get_received()  # drain the initial "connected" event
    return sio_client


# H-03: chat attachment uploads magic-byte-sniff the actual body against the
# claimed extension (kk/security.py::sniff_bytes), so these use real
# container signatures rather than arbitrary placeholder bytes.
_FAKE_JPEG_BYTES = b"\xff\xd8\xff\xe0fake-jpeg-bytes"
_FAKE_MP4_BYTES = b"\x00\x00\x00\x18ftypmp42fake-mp4-bytes"
_FAKE_M4A_BYTES = b"\x00\x00\x00\x18ftypM4A fake-m4a-bytes"


def _send_text(client, token, car_id, receiver_id, *, idem_key=None, content="hello there"):
    return client.post(
        f"/api/chat/{car_id}/send",
        headers=_auth(token, idem_key),
        json={"content": content, "receiver_id": receiver_id},
    )


def _send_image(client, token, car_id, receiver_id, *, idem_key=None, **_kw):
    return client.post(
        f"/api/chat/{car_id}/send_image",
        headers=_auth(token, idem_key),
        data={
            "receiver_id": receiver_id,
            "file": (io.BytesIO(_FAKE_JPEG_BYTES), "photo.jpg"),
        },
        content_type="multipart/form-data",
    )


def _send_video(client, token, car_id, receiver_id, *, idem_key=None, **_kw):
    return client.post(
        f"/api/chat/{car_id}/send_video",
        headers=_auth(token, idem_key),
        data={
            "receiver_id": receiver_id,
            "file": (io.BytesIO(_FAKE_MP4_BYTES), "clip.mp4"),
        },
        content_type="multipart/form-data",
    )


def _send_audio(client, token, car_id, receiver_id, *, idem_key=None, **_kw):
    return client.post(
        f"/api/chat/{car_id}/send_audio",
        headers=_auth(token, idem_key),
        data={
            "receiver_id": receiver_id,
            "file": (io.BytesIO(_FAKE_M4A_BYTES), "voice.m4a"),
        },
        content_type="multipart/form-data",
    )


def _send_media_group(client, token, car_id, receiver_id, *, idem_key=None, **_kw):
    return client.post(
        f"/api/chat/{car_id}/send_media_group",
        headers=_auth(token, idem_key),
        data={
            "receiver_id": receiver_id,
            "attachments": [
                (io.BytesIO(_FAKE_JPEG_BYTES), "a.jpg"),
                (io.BytesIO(_FAKE_JPEG_BYTES), "b.jpg"),
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


def _fresh_thread(app_ctx, client, seller_ctx, buyer_ctx):
    """New car + an initial buyer->seller message so the seller is an
    allowed receiver for every send-endpoint variant under test."""
    seller_username, seller_public = seller_ctx
    buyer_username, buyer_public = buyer_ctx
    car_public = _make_car(app_ctx, seller_public)
    seller_token = _login(client, seller_username)
    buyer_token = _login(client, buyer_username)
    first = _send_text(client, buyer_token, car_public, seller_public, content="hi, interested")
    assert first.status_code == 201, first.data
    return car_public, seller_token, buyer_public


# --------------------------------------------------------------------------
# 1) Same key + same endpoint: exactly one Message, replay is byte-identical,
#    and delivery (push/notification/socket) happens only once. (also covers
#    item 6: replay does not invoke delivery a second time)
# --------------------------------------------------------------------------


@pytest.mark.parametrize("kind", ["text", "image", "video", "audio", "media_group"])
def test_same_key_replays_without_duplicate_message_or_delivery(
    app_ctx, client, seller_ctx, buyer_ctx, kind
):
    car_public, seller_token, buyer_public = _fresh_thread(app_ctx, client, seller_ctx, buyer_ctx)
    send_fn = _ENDPOINTS[kind]
    idem_key = f"idem-{kind}-{uuid.uuid4().hex[:12]}"

    buyer_username, _ = buyer_ctx
    buyer_token = _login(client, buyer_username)
    buyer_socket = _connect_socket(app_ctx, buyer_token)
    before_messages = _message_count(app_ctx)
    before_notifs = _notification_count(app_ctx, buyer_public)

    with patch("kk.chat_realtime.send_push") as push_mock:
        push_mock.return_value = True

        first = send_fn(client, seller_token, car_public, buyer_public, idem_key=idem_key)
        assert first.status_code == 201, first.data
        first_body = first.get_json()
        assert _message_count(app_ctx) == before_messages + 1

        # Retry with the identical key — simulates a timeout retry, a
        # 401-refresh retry, or any other client-side re-send of the same
        # logical attempt.
        second = send_fn(client, seller_token, car_public, buyer_public, idem_key=idem_key)

    # Replayed response: same status, same body, same message identity.
    assert second.status_code == first.status_code == 201
    second_body = second.get_json()
    assert second_body == first_body
    assert second_body["message"]["id"] == first_body["message"]["id"]
    assert second_body["success"] is True

    # No second Message row was inserted.
    assert _message_count(app_ctx) == before_messages + 1

    # No second delivery side effect: exactly one push, one Notification row,
    # one `new_message` socket event — not two.
    push_mock.assert_called_once()
    assert _notification_count(app_ctx, buyer_public) == before_notifs + 1
    received = buyer_socket.get_received()
    new_message_events = [e for e in received if e.get("name") == "new_message"]
    assert len(new_message_events) == 1, received
    buyer_socket.disconnect()


# --------------------------------------------------------------------------
# 2) No Idempotency-Key: existing behavior unchanged — two requests create
#    two Messages (backward compatibility for existing/older clients).
# --------------------------------------------------------------------------


@pytest.mark.parametrize("kind", ["text", "image", "video", "audio", "media_group"])
def test_no_key_creates_two_messages_backward_compatible(
    app_ctx, client, seller_ctx, buyer_ctx, kind
):
    car_public, seller_token, buyer_public = _fresh_thread(app_ctx, client, seller_ctx, buyer_ctx)
    send_fn = _ENDPOINTS[kind]

    before = _message_count(app_ctx)
    with patch("kk.chat_realtime.send_push"):
        first = send_fn(client, seller_token, car_public, buyer_public, idem_key=None)
        second = send_fn(client, seller_token, car_public, buyer_public, idem_key=None)

    assert first.status_code == 201, first.data
    assert second.status_code == 201, second.data
    assert first.get_json()["message"]["id"] != second.get_json()["message"]["id"]
    assert _message_count(app_ctx) == before + 2


# --------------------------------------------------------------------------
# 3) Different keys: always create separate messages.
# --------------------------------------------------------------------------


def test_different_keys_create_separate_messages(app_ctx, client, seller_ctx, buyer_ctx):
    car_public, seller_token, buyer_public = _fresh_thread(app_ctx, client, seller_ctx, buyer_ctx)

    before = _message_count(app_ctx)
    key_a = f"idem-a-{uuid.uuid4().hex[:8]}"
    key_b = f"idem-b-{uuid.uuid4().hex[:8]}"
    with patch("kk.chat_realtime.send_push"):
        first = _send_text(client, seller_token, car_public, buyer_public, idem_key=key_a, content="a")
        second = _send_text(client, seller_token, car_public, buyer_public, idem_key=key_b, content="b")

    assert first.status_code == 201, first.data
    assert second.status_code == 201, second.data
    assert first.get_json()["message"]["id"] != second.get_json()["message"]["id"]
    assert _message_count(app_ctx) == before + 2


# --------------------------------------------------------------------------
# 4) Empty/missing key is treated as "no idempotency key" (existing
#    kk/idempotency.py semantics: `replay_response`/`remember_response` are
#    no-ops for a falsy/whitespace-only key).
# --------------------------------------------------------------------------


@pytest.mark.parametrize("blank_key", ["", "   "])
def test_blank_key_treated_as_missing(app_ctx, client, seller_ctx, buyer_ctx, blank_key):
    car_public, seller_token, buyer_public = _fresh_thread(app_ctx, client, seller_ctx, buyer_ctx)

    before = _message_count(app_ctx)
    with patch("kk.chat_realtime.send_push"):
        first = _send_text(client, seller_token, car_public, buyer_public, idem_key=blank_key, content="a")
        second = _send_text(client, seller_token, car_public, buyer_public, idem_key=blank_key, content="b")

    assert first.status_code == 201, first.data
    assert second.status_code == 201, second.data
    assert first.get_json()["message"]["id"] != second.get_json()["message"]["id"]
    assert _message_count(app_ctx) == before + 2


# --------------------------------------------------------------------------
# 5) Cross-scope sanity: the same raw key string used against two different
#    send endpoints does not collide (each endpoint uses its own `scope`).
# --------------------------------------------------------------------------


def test_same_key_different_endpoint_does_not_collide(app_ctx, client, seller_ctx, buyer_ctx):
    car_public, seller_token, buyer_public = _fresh_thread(app_ctx, client, seller_ctx, buyer_ctx)

    before = _message_count(app_ctx)
    shared_key = f"idem-shared-{uuid.uuid4().hex[:8]}"
    with patch("kk.chat_realtime.send_push"):
        text_resp = _send_text(client, seller_token, car_public, buyer_public, idem_key=shared_key)
        image_resp = _send_image(client, seller_token, car_public, buyer_public, idem_key=shared_key)

    assert text_resp.status_code == 201, text_resp.data
    assert image_resp.status_code == 201, image_resp.data
    assert text_resp.get_json()["message"]["id"] != image_resp.get_json()["message"]["id"]
    assert _message_count(app_ctx) == before + 2


# --------------------------------------------------------------------------
# 6) Documented existing limitation (kk/idempotency.py): the helper keys
#    purely on (scope, actor_id, idem_key) — it does NOT fingerprint the
#    request body. Reusing the same key with a *different* body replays the
#    first response verbatim; it does not detect the mismatch or process the
#    second body. This is pre-existing `create_car`/API-01 behavior, not a
#    new limitation introduced by this BE-18 change, and this test documents
#    it rather than inventing new "body changed" semantics.
# --------------------------------------------------------------------------


def test_same_key_different_body_replays_the_first_response_verbatim(
    app_ctx, client, seller_ctx, buyer_ctx
):
    car_public, seller_token, buyer_public = _fresh_thread(app_ctx, client, seller_ctx, buyer_ctx)

    before = _message_count(app_ctx)
    idem_key = f"idem-same-body-mismatch-{uuid.uuid4().hex[:8]}"
    with patch("kk.chat_realtime.send_push"):
        first = _send_text(
            client, seller_token, car_public, buyer_public, idem_key=idem_key, content="first content"
        )
        assert first.status_code == 201, first.data

        second = _send_text(
            client, seller_token, car_public, buyer_public, idem_key=idem_key, content="a totally different message"
        )

    # No second Message was created for the second (different) body.
    assert _message_count(app_ctx) == before + 1

    # The replayed response is the *first* request's response — it does not
    # reflect "a totally different message", proving there is no body
    # fingerprinting. Callers must not reuse a key across genuinely different
    # message content.
    assert second.status_code == 201
    assert second.get_json() == first.get_json()
    assert second.get_json()["message"]["content"] == "first content"
