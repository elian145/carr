"""Live read receipts: the Socket.IO ``mark_read`` event.

A recipient who is looking at a conversation while a message arrives tells the
server (``mark_read``); the server marks only THAT peer's inbound messages read
through the same helper ``join_chat`` / ``GET /messages`` use, and the existing
``messages_read`` event updates the sender live.

Covered: the live receipt itself, "nothing is marked unless asked", per-thread
isolation for a seller with several buyers, non-participants and unknown
listings, ambiguity, unauthenticated sockets, bursts / rate limiting, and that
no message or notification row is duplicated.

Real Flask app + SQLite + Flask-SocketIO test client, synthetic accounts only.
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

PASSWORD = "Aa123456!"


@pytest.fixture(scope="module")
def ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_mark_read_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "mark_read.db")

    from kk.app_factory import create_app

    app, socketio, *_ = create_app()
    from kk.models import db

    with app.app_context():
        db.drop_all()
        db.create_all()
    yield app, socketio, app.test_client()
    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    tmp.cleanup()


# ---------------------------------------------------------------- helpers ---


def _user(ctx, name: str) -> str:
    app, _sio, _c = ctx
    from kk.models import User, db

    with app.app_context():
        u = User(
            username=f"{name}_{uuid.uuid4().hex[:6]}",
            phone_number=f"077{uuid.uuid4().int % 10**8:08d}",
            first_name=name.title(),
            last_name="Test",
            email=None,
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id=f"pub-{uuid.uuid4().hex[:12]}",
        )
        u.set_password(PASSWORD)
        db.session.add(u)
        db.session.commit()
        return u.public_id


def _login(ctx, public_id: str) -> str:
    app, _sio, client = ctx
    from kk.models import User

    with app.app_context():
        username = User.query.filter_by(public_id=public_id).first().username
    r = client.post("/api/auth/login", json={"username": username, "password": PASSWORD})
    assert r.status_code == 200, r.data
    return r.get_json()["access_token"]


def _car(ctx, seller_public_id: str, *, active: bool = True) -> str:
    app, _sio, _c = ctx
    from kk.models import Car, User, db

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
            is_active=active,
        )
        db.session.add(car)
        db.session.commit()
        return car.public_id


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _sock(ctx, token):
    app, sio, client = ctx
    c = sio.test_client(app, flask_test_client=client, headers=_auth(token))
    assert c.is_connected(), c.get_received()
    c.get_received()
    return c


def _events(sock, name):
    return [e for e in sock.get_received() if e["name"] == name]


def _unread(ctx, car, receiver_public, sender_public) -> int:
    app, _sio, _c = ctx
    from kk.models import Car, Message, User

    with app.app_context():
        r = User.query.filter_by(public_id=receiver_public).first()
        s = User.query.filter_by(public_id=sender_public).first()
        c = Car.query.filter_by(public_id=car).first()
        return Message.query.filter_by(
            car_id=c.id, receiver_id=r.id, sender_id=s.id, is_read=False
        ).count()


def _row_counts(ctx) -> tuple[int, int]:
    app, _sio, _c = ctx
    from kk.models import Message, Notification

    with app.app_context():
        return Message.query.count(), Notification.query.count()


class World:
    """One seller, two buyers, one stranger, one listing."""

    def __init__(self, ctx):
        self.ctx = ctx
        self.s = _user(ctx, "seller")
        self.b1 = _user(ctx, "buyerone")
        self.b2 = _user(ctx, "buyertwo")
        self.x = _user(ctx, "stranger")
        self.car = _car(ctx, self.s)
        self.tok = {u: _login(ctx, u) for u in (self.s, self.b1, self.b2, self.x)}

    def send(self, frm, content, to=None):
        _app, _sio, client = self.ctx
        body = {"content": content}
        if to is not None:
            body["receiver_id"] = to
        r = client.post(f"/api/chat/{self.car}/send", headers=_auth(self.tok[frm]), json=body)
        assert r.status_code == 201, r.data
        return r.get_json()["message"]["id"]

    def sock(self, who):
        return _sock(self.ctx, self.tok[who])


@pytest.fixture
def world(ctx):
    return World(ctx)


# ------------------------------------------------------------------ tests ---


def test_mark_read_marks_inbound_and_updates_the_sender_live(ctx, world):
    sender, receiver = world.sock(world.b1), world.sock(world.s)
    m1 = world.send(world.b1, "one", to=world.s)
    m2 = world.send(world.b1, "two", to=world.s)
    receiver.get_received()
    assert _unread(ctx, world.car, world.s, world.b1) == 2

    receiver.emit("mark_read", {"car_id": world.car, "peer_id": world.b1})

    assert _unread(ctx, world.car, world.s, world.b1) == 0
    reads = _events(sender, "messages_read")
    assert len(reads) == 1
    body = reads[0]["args"][0]
    assert body["reader_id"] == world.s
    assert body["car_id"] == world.car
    assert sorted(body["message_ids"]) == sorted([m1, m2])
    ack = _events(receiver, "read_marked")
    assert ack and ack[0]["args"][0]["ok"] is True
    assert ack[0]["args"][0]["marked"] == 2


def test_nothing_is_marked_unless_the_client_asks(ctx, world):
    sender, receiver = world.sock(world.b1), world.sock(world.s)
    world.send(world.b1, "unseen", to=world.s)
    # Both sockets are connected, and the receiver even joined the room, but a
    # live socket alone is not "viewing": the server must not guess.
    receiver.emit("typing_start", {"car_id": world.car, "peer_id": world.b1})
    assert _unread(ctx, world.car, world.s, world.b1) == 1
    assert _events(sender, "messages_read") == []


def test_buyer_marks_the_sellers_reply_without_naming_the_seller(ctx, world):
    buyer, seller = world.sock(world.b1), world.sock(world.s)
    world.send(world.b1, "hello", to=world.s)
    world.send(world.s, "hi buyer", to=world.b1)
    seller.get_received()
    buyer.emit("mark_read", {"car_id": world.car})  # a buyer's peer is the seller
    assert _unread(ctx, world.car, world.b1, world.s) == 0
    assert len(_events(seller, "messages_read")) == 1


def test_second_call_is_a_noop_and_does_not_notify_again(ctx, world):
    sender, receiver = world.sock(world.b1), world.sock(world.s)
    world.send(world.b1, "once", to=world.s)
    receiver.emit("mark_read", {"car_id": world.car, "peer_id": world.b1})
    assert len(_events(sender, "messages_read")) == 1
    receiver.get_received()
    receiver.emit("mark_read", {"car_id": world.car, "peer_id": world.b1})
    ack = _events(receiver, "read_marked")
    assert ack[0]["args"][0]["ok"] is True and ack[0]["args"][0]["marked"] == 0
    assert _events(sender, "messages_read") == []


def test_a_later_message_is_marked_by_the_next_call(ctx, world):
    sender, receiver = world.sock(world.b1), world.sock(world.s)
    world.send(world.b1, "first", to=world.s)
    receiver.emit("mark_read", {"car_id": world.car, "peer_id": world.b1})
    sender.get_received()
    late = world.send(world.b1, "second", to=world.s)
    assert _unread(ctx, world.car, world.s, world.b1) == 1
    receiver.emit("mark_read", {"car_id": world.car, "peer_id": world.b1})
    reads = _events(sender, "messages_read")
    assert len(reads) == 1 and reads[0]["args"][0]["message_ids"] == [late]


def test_seller_marking_one_buyer_never_touches_another_conversation(ctx, world):
    b1s, b2s = world.sock(world.b1), world.sock(world.b2)
    seller = world.sock(world.s)
    world.send(world.b1, "from b1", to=world.s)
    world.send(world.b2, "from b2", to=world.s)

    seller.emit("mark_read", {"car_id": world.car, "peer_id": world.b2})

    assert _unread(ctx, world.car, world.s, world.b2) == 0
    assert _unread(ctx, world.car, world.s, world.b1) == 1, "b1's thread must stay unread"
    assert len(_events(b2s, "messages_read")) == 1
    assert _events(b1s, "messages_read") == []


def test_ambiguous_seller_call_without_a_peer_marks_nothing(ctx, world):
    b1s, b2s = world.sock(world.b1), world.sock(world.b2)
    seller = world.sock(world.s)
    world.send(world.b1, "from b1", to=world.s)
    world.send(world.b2, "from b2", to=world.s)
    seller.get_received()

    seller.emit("mark_read", {"car_id": world.car})

    ack = _events(seller, "read_marked")
    assert ack and ack[0]["args"][0]["ok"] is False
    assert ack[0]["args"][0]["code"] == "peer_required"
    assert _unread(ctx, world.car, world.s, world.b1) == 1
    assert _unread(ctx, world.car, world.s, world.b2) == 1
    assert _events(b1s, "messages_read") == [] and _events(b2s, "messages_read") == []


def test_a_buyer_cannot_mark_another_buyers_thread(ctx, world):
    world.send(world.b1, "private to b1/seller", to=world.s)
    world.send(world.s, "reply to b1", to=world.b1)
    b2 = world.sock(world.b2)
    b2.emit("mark_read", {"car_id": world.car, "peer_id": world.s})
    b2.emit("mark_read", {"car_id": world.car, "peer_id": world.b1})
    assert _unread(ctx, world.car, world.s, world.b1) == 1
    assert _unread(ctx, world.car, world.b1, world.s) == 1


def test_non_participant_is_denied_and_nothing_changes(ctx, world):
    sender = world.sock(world.b1)
    world.send(world.b1, "not for the stranger", to=world.s)
    stranger = world.sock(world.x)
    before = _row_counts(ctx)

    for peer in (world.b1, world.s, None):
        payload = {"car_id": world.car}
        if peer:
            payload["peer_id"] = peer
        stranger.emit("mark_read", payload)

    acks = _events(stranger, "read_marked")
    assert acks and all(a["args"][0]["ok"] is False for a in acks)
    assert _unread(ctx, world.car, world.s, world.b1) == 1
    assert _events(sender, "messages_read") == []
    assert _row_counts(ctx) == before


def test_unknown_or_inactive_listing_is_refused(ctx, world):
    world.send(world.b1, "x", to=world.s)
    seller = world.sock(world.s)
    seller.emit("mark_read", {"car_id": "no-such-listing", "peer_id": world.b1})
    seller.emit("mark_read", {"peer_id": world.b1})
    app, _sio, _c = ctx
    from kk.models import Car, db

    with app.app_context():
        car = Car.query.filter_by(public_id=world.car).first()
        car.is_active = False
        db.session.commit()
    seller.emit("mark_read", {"car_id": world.car, "peer_id": world.b1})
    acks = _events(seller, "read_marked")
    assert len(acks) == 3 and all(a["args"][0]["ok"] is False for a in acks)
    assert _unread(ctx, world.car, world.s, world.b1) == 1


def test_unauthenticated_socket_cannot_mark_read(ctx, world):
    app, sio, client = ctx
    world.send(world.b1, "x", to=world.s)
    anon = sio.test_client(app, flask_test_client=client)
    if anon.is_connected():
        anon.get_received()
        anon.emit("mark_read", {"car_id": world.car, "peer_id": world.b1})
        assert all(e["name"] != "read_marked" or not e["args"][0]["ok"] for e in anon.get_received())
    assert _unread(ctx, world.car, world.s, world.b1) == 1


def test_malformed_payloads_do_not_crash_or_mark(ctx, world):
    world.send(world.b1, "x", to=world.s)
    seller = world.sock(world.s)
    for bad in (None, "text", 5, [], {"car_id": ["a"]}, {"car_id": {"x": 1}}):
        seller.emit("mark_read", bad)
    assert seller.is_connected()
    assert _unread(ctx, world.car, world.s, world.b1) == 1


def test_burst_is_rate_limited_per_socket_but_still_marks(ctx, world):
    sender, receiver = world.sock(world.b1), world.sock(world.s)
    world.send(world.b1, "burst", to=world.s)
    receiver.get_received()
    for _ in range(60):
        receiver.emit("mark_read", {"car_id": world.car, "peer_id": world.b1})
    acks = _events(receiver, "read_marked")
    assert 0 < len(acks) <= 30, "over-limit calls are dropped silently"
    assert _unread(ctx, world.car, world.s, world.b1) == 0
    assert len(_events(sender, "messages_read")) == 1, "one receipt, not one per call"


def test_marking_read_creates_no_messages_or_notifications(ctx, world):
    world.sock(world.b1)
    receiver = world.sock(world.s)
    world.send(world.b1, "a", to=world.s)
    world.send(world.b1, "b", to=world.s)
    receiver.get_received()
    before = _row_counts(ctx)
    for _ in range(3):
        receiver.emit("mark_read", {"car_id": world.car, "peer_id": world.b1})
    assert _row_counts(ctx) == before
    assert _events(receiver, "new_message") == []
    assert _events(receiver, "new_notification") == []
