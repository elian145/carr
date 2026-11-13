"""``join_chat`` visibility: a reconnect re-join must not mark unseen messages read.

When Socket.IO reconnects, the app re-sends ``join_chat``. ``join_chat`` marks the
conversation read, which is wrong if the conversation is covered or the app is
backgrounded. The client now states ``visible: false`` in that case: the room is
still joined (live delivery) but nothing is marked read; the client reports it
with ``mark_read`` once the user is looking again. The REST history fetch has the
same switch (``mark_read=0``) for the app's background sync.

Covered: skip when explicitly not visible (bool and string forms), messages
missed while the receiver was offline stay unread through the re-join and the
background fetch, then become read live (sender gets ``messages_read``) via
``mark_read``, full backward compatibility (field absent / true / junk), the
security checks still run, seller thread isolation, and the REST default.

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
    tmp = tempfile.TemporaryDirectory(prefix="carlist_rejoin_vis_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "rejoin_vis.db")

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


def _car(ctx, seller_public_id: str) -> str:
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
            is_active=True,
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

    def history(self, who, peer=None, **params):
        _app, _sio, client = self.ctx
        q = dict(params)
        if peer:
            q["peer_id"] = peer
        r = client.get(f"/api/chat/{self.car}/messages", headers=_auth(self.tok[who]), query_string=q)
        assert r.status_code == 200, r.data
        return r.get_json()


@pytest.fixture
def world(ctx):
    return World(ctx)


def _join(sock, car, peer=None, **extra):
    payload = {"car_id": car, **extra}
    if peer:
        payload["peer_id"] = peer
    sock.emit("join_chat", payload)
    return _events(sock, "joined_chat")


# ----------------------------------------------- reconnect while NOT visible ---


def test_rejoin_not_visible_joins_the_room_but_marks_nothing_read(ctx, world):
    sender = world.sock(world.b1)
    world.send(world.b1, "unseen", to=world.s)
    receiver = world.sock(world.s)  # the reconnected socket

    ack = _join(receiver, world.car, world.b1, visible=False)

    assert ack and ack[0]["args"][0]["ok"] is True
    assert ack[0]["args"][0]["room"]
    assert ack[0]["args"][0]["read_skipped"] is True
    assert _unread(ctx, world.car, world.s, world.b1) == 1
    assert _events(sender, "messages_read") == []


@pytest.mark.parametrize("flag", ["false", "FALSE", "0", "no"])
def test_string_forms_of_false_are_also_not_visible(ctx, world, flag):
    world.send(world.b1, "unseen", to=world.s)
    receiver = world.sock(world.s)
    _join(receiver, world.car, world.b1, visible=flag)
    assert _unread(ctx, world.car, world.s, world.b1) == 1


def test_a_covered_rejoin_still_receives_live_messages(ctx, world):
    receiver = world.sock(world.s)
    _join(receiver, world.car, world.b1, visible=False)
    receiver.get_received()
    world.send(world.b1, "arrives while covered", to=world.s)
    got = _events(receiver, "new_message")
    assert got, "the room / user room must still deliver while covered"
    assert _unread(ctx, world.car, world.s, world.b1) == 1


def test_missed_messages_stay_unread_then_are_marked_live_on_return(ctx, world):
    sender = world.sock(world.b1)
    # The receiver is offline (socket down): three messages are missed.
    ids = [world.send(world.b1, f"missed {i}", to=world.s) for i in range(3)]
    sender.get_received()
    assert _unread(ctx, world.car, world.s, world.b1) == 3

    # Reconnect while backgrounded / covered: joined, nothing read.
    receiver = world.sock(world.s)
    _join(receiver, world.car, world.b1, visible=False)
    assert _unread(ctx, world.car, world.s, world.b1) == 3
    assert _events(sender, "messages_read") == []

    # The user comes back: the client reports it, the sender sees it live.
    receiver.emit("mark_read", {"car_id": world.car, "peer_id": world.b1})
    assert _unread(ctx, world.car, world.s, world.b1) == 0
    reads = _events(sender, "messages_read")
    assert len(reads) == 1
    assert sorted(reads[0]["args"][0]["message_ids"]) == sorted(ids)


def test_a_message_arriving_after_the_covered_rejoin_is_included_on_return(ctx, world):
    sender = world.sock(world.b1)
    m1 = world.send(world.b1, "missed", to=world.s)
    receiver = world.sock(world.s)
    _join(receiver, world.car, world.b1, visible=False)
    m2 = world.send(world.b1, "while covered", to=world.s)
    assert _unread(ctx, world.car, world.s, world.b1) == 2
    sender.get_received()

    receiver.emit("mark_read", {"car_id": world.car, "peer_id": world.b1})
    reads = _events(sender, "messages_read")
    assert len(reads) == 1
    assert sorted(reads[0]["args"][0]["message_ids"]) == sorted([m1, m2])


def test_background_history_fetch_returns_messages_without_marking_read(ctx, world):
    sender = world.sock(world.b1)
    world.send(world.b1, "missed one", to=world.s)
    world.send(world.b1, "missed two", to=world.s)
    sender.get_received()

    body = world.history(world.s, world.b1, mark_read="0")

    assert [m["content"] for m in body["messages"]] == ["missed one", "missed two"]
    assert all(m["is_read"] is False for m in body["messages"])
    assert _unread(ctx, world.car, world.s, world.b1) == 2
    assert _events(sender, "messages_read") == []

    # ...and the reconnect + return path then reports them.
    receiver = world.sock(world.s)
    receiver.emit("mark_read", {"car_id": world.car, "peer_id": world.b1})
    assert _unread(ctx, world.car, world.s, world.b1) == 0
    assert len(_events(sender, "messages_read")) == 1


@pytest.mark.parametrize("flag", ["false", "no", "0"])
def test_history_mark_read_off_switch_spellings(ctx, world, flag):
    world.send(world.b1, "x", to=world.s)
    world.history(world.s, world.b1, mark_read=flag)
    assert _unread(ctx, world.car, world.s, world.b1) == 1


def test_history_fetch_marks_read_by_default_unchanged(ctx, world):
    sender = world.sock(world.b1)
    world.send(world.b1, "x", to=world.s)
    sender.get_received()
    world.history(world.s, world.b1)  # an older app version: no parameter
    assert _unread(ctx, world.car, world.s, world.b1) == 0
    assert len(_events(sender, "messages_read")) == 1


@pytest.mark.parametrize("flag", ["1", "true", "yes", "", "banana"])
def test_history_other_mark_read_values_still_mark(ctx, world, flag):
    world.send(world.b1, "x", to=world.s)
    world.history(world.s, world.b1, mark_read=flag)
    assert _unread(ctx, world.car, world.s, world.b1) == 0


# ---------------------------------------------- reconnect while visible / old app ---


def test_rejoin_visible_true_marks_read_like_before(ctx, world):
    sender = world.sock(world.b1)
    m1 = world.send(world.b1, "seen", to=world.s)
    receiver = world.sock(world.s)

    ack = _join(receiver, world.car, world.b1, visible=True)

    assert ack[0]["args"][0]["ok"] is True
    assert "read_skipped" not in ack[0]["args"][0]
    assert _unread(ctx, world.car, world.s, world.b1) == 0
    reads = _events(sender, "messages_read")
    assert len(reads) == 1 and reads[0]["args"][0]["message_ids"] == [m1]


def test_old_app_without_the_field_still_marks_read_on_join(ctx, world):
    sender = world.sock(world.b1)
    world.send(world.b1, "seen", to=world.s)
    receiver = world.sock(world.s)

    ack = _join(receiver, world.car, world.b1)  # exactly what older builds send

    assert ack[0]["args"][0]["ok"] is True
    assert "read_skipped" not in ack[0]["args"][0]
    assert _unread(ctx, world.car, world.s, world.b1) == 0
    assert len(_events(sender, "messages_read")) == 1


@pytest.mark.parametrize("junk", [None, 1, "maybe", "", "true", [], {}, 3.5])
def test_unrecognised_visibility_values_keep_the_old_behaviour(ctx, world, junk):
    world.send(world.b1, "seen", to=world.s)
    receiver = world.sock(world.s)
    _join(receiver, world.car, world.b1, visible=junk)
    assert _unread(ctx, world.car, world.s, world.b1) == 0


# ------------------------------------------------------- security / isolation ---


def test_not_visible_does_not_bypass_access_checks(ctx, world):
    world.send(world.b1, "private", to=world.s)
    stranger = world.sock(world.x)
    ack = _join(stranger, world.car, world.b1, visible=False)
    assert ack and ack[0]["args"][0]["ok"] is False
    assert ack[0]["args"][0]["code"] == "chat_access_denied"
    assert ack[0]["args"][0]["room"] is None
    assert _unread(ctx, world.car, world.s, world.b1) == 1


def test_not_visible_does_not_bypass_peer_resolution(ctx, world):
    world.send(world.b1, "one", to=world.s)
    world.send(world.b2, "two", to=world.s)
    seller = world.sock(world.s)
    ack = _join(seller, world.car, None, visible=False)  # ambiguous: two buyers
    assert ack[0]["args"][0]["ok"] is False
    assert ack[0]["args"][0]["room"] is None


def test_unauthenticated_socket_is_still_refused(ctx, world):
    app, sio, client = ctx
    world.send(world.b1, "x", to=world.s)
    anon = sio.test_client(app, flask_test_client=client)
    if anon.is_connected():
        anon.get_received()
        anon.emit("join_chat", {"car_id": world.car, "peer_id": world.b1, "visible": False})
        events = anon.get_received()
        assert not [e for e in events if e["name"] == "joined_chat" and e["args"][0].get("ok")]
    assert _unread(ctx, world.car, world.s, world.b1) == 1


def test_a_covered_rejoin_in_one_thread_leaves_the_other_buyers_thread_alone(ctx, world):
    world.send(world.b1, "from one", to=world.s)
    world.send(world.b2, "from two", to=world.s)
    seller = world.sock(world.s)

    _join(seller, world.car, world.b1, visible=False)
    assert _unread(ctx, world.car, world.s, world.b1) == 1
    assert _unread(ctx, world.car, world.s, world.b2) == 1

    seller.emit("mark_read", {"car_id": world.car, "peer_id": world.b1})
    assert _unread(ctx, world.car, world.s, world.b1) == 0
    assert _unread(ctx, world.car, world.s, world.b2) == 1


def test_no_rows_or_notifications_are_created_by_the_covered_rejoin(ctx, world):
    app, _sio, _c = ctx
    from kk.models import Message, Notification

    world.send(world.b1, "x", to=world.s)
    with app.app_context():
        before = (Message.query.count(), Notification.query.count())
    receiver = world.sock(world.s)
    _join(receiver, world.car, world.b1, visible=False)
    receiver.emit("mark_read", {"car_id": world.car, "peer_id": world.b1})
    with app.app_context():
        assert (Message.query.count(), Notification.query.count()) == before
