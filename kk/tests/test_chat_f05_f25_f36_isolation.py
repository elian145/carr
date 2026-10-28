"""F-05 / F-25 / F-36: chat conversation isolation and socket authentication.

One seller, several buyers, one listing:

* F-05  conversations with different buyers must never merge: history, replies,
        reply targets, "reply to whoever wrote last" and read receipts are all
        scoped to ONE (listing, seller, buyer) conversation.
* F-25  typing indicators reach only the other participant of the conversation
        they belong to -- never the other buyers.
* F-36  a socket is bound to the account and token it authenticated with; an
        expired / invalid / revoked token is refused (never silently accepted as
        a guest) and a live socket is closed when its token expires.

Everything runs against the real Flask app + SQLite + the Flask-SocketIO test
client with synthetic accounts only (no network, no external services).
"""

from __future__ import annotations

import os
import sys
import tempfile
import uuid
from datetime import timedelta
from pathlib import Path
from unittest.mock import patch

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

PASSWORD = "Aa123456!"


@pytest.fixture(scope="module")
def ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_chat_iso_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "chat_iso.db")

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


def _phone() -> str:
    return f"077{uuid.uuid4().int % 10**8:08d}"


def _user(ctx, name: str) -> str:
    app, _sio, _c = ctx
    from kk.models import User, db

    with app.app_context():
        u = User(
            username=f"{name}_{uuid.uuid4().hex[:6]}",
            phone_number=_phone(),
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


def _username(ctx, public_id: str) -> str:
    app, _sio, _c = ctx
    from kk.models import User

    with app.app_context():
        return User.query.filter_by(public_id=public_id).first().username


def _login(ctx, public_id: str) -> str:
    _app, _sio, client = ctx
    r = client.post(
        "/api/auth/login",
        json={"username": _username(ctx, public_id), "password": PASSWORD},
    )
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


def _send(ctx, token, car, content, receiver=None, reply_to=None):
    _app, _sio, client = ctx
    body = {"content": content}
    if receiver is not None:
        body["receiver_id"] = receiver
    if reply_to is not None:
        body["reply_to_message_id"] = reply_to
    return client.post(f"/api/chat/{car}/send", headers=_auth(token), json=body)


def _history(ctx, token, car, peer=None):
    _app, _sio, client = ctx
    url = f"/api/chat/{car}/messages"
    if peer is not None:
        url += f"?peer_id={peer}"
    return client.get(url, headers=_auth(token))


def _sock(ctx, token):
    app, sio, client = ctx
    c = sio.test_client(
        app, flask_test_client=client, headers={"Authorization": f"Bearer {token}"}
    )
    assert c.is_connected(), c.get_received()
    c.get_received()
    return c


def _events(sock, name):
    return [e for e in sock.get_received() if e["name"] == name]


def _drain(sock):
    """Everything queued for a client, even after the server closed it
    (the test client's ``get_received`` refuses once disconnected)."""
    out, sock.queue = list(sock.queue), []
    return out


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
    """One seller, three buyers, one stranger, one listing."""

    def __init__(self, ctx):
        self.ctx = ctx
        self.s = _user(ctx, "seller")
        self.b1 = _user(ctx, "buyerone")
        self.b2 = _user(ctx, "buyertwo")
        self.b3 = _user(ctx, "buyerthree")
        self.x = _user(ctx, "stranger")
        self.car = _car(ctx, self.s)
        self.tok = {u: _login(ctx, u) for u in (self.s, self.b1, self.b2, self.b3, self.x)}

    def send(self, frm, content, to=None, reply_to=None):
        return _send(self.ctx, self.tok[frm], self.car, content, receiver=to, reply_to=reply_to)

    def seed(self):
        """b1, b2 and b3 each open a thread; the seller answers b1 and b2."""
        for b, text in ((self.b1, "b1 hello"), (self.b2, "b2 hello"), (self.b3, "b3 hello")):
            r = self.send(b, text, to=self.s)
            assert r.status_code == 201, r.data
        assert self.send(self.s, "s -> b1", to=self.b1).status_code == 201
        assert self.send(self.s, "s -> b2", to=self.b2).status_code == 201


@pytest.fixture
def world(ctx):
    return World(ctx)


def _texts(resp):
    return [m["content"] for m in resp.get_json()["messages"]]


# ===================================================================== F-05 ==


class TestF05ConversationsDoNotMerge:
    def test_seller_without_receiver_is_rejected_when_several_buyers(self, ctx, world):
        world.seed()
        # b2 wrote LAST; the old "reply to whoever wrote last" fallback would
        # have sent this meant-for-b1 text to b2.
        before = _history(ctx, world.tok[world.b2], world.car).get_json()["total"]
        r = world.send(world.s, "meant for b1 only")
        assert r.status_code == 400, r.data
        assert _history(ctx, world.tok[world.b2], world.car).get_json()["total"] == before
        assert "meant for b1 only" not in _texts(_history(ctx, world.tok[world.b1], world.car))

    def test_seller_without_receiver_still_works_with_exactly_one_buyer(self, ctx, world):
        assert world.send(world.b1, "hi", to=world.s).status_code == 201
        r = world.send(world.s, "reply, no receiver_id")
        assert r.status_code == 201, r.data
        assert r.get_json()["message"]["receiver_id"] == world.b1

    def test_seller_history_is_scoped_to_the_named_buyer(self, ctx, world):
        world.seed()
        s = world.tok[world.s]
        assert _texts(_history(ctx, s, world.car, world.b1)) == ["b1 hello", "s -> b1"]
        assert _texts(_history(ctx, s, world.car, world.b2)) == ["b2 hello", "s -> b2"]
        assert _texts(_history(ctx, s, world.car, world.b3)) == ["b3 hello"]

    def test_seller_history_without_peer_is_refused_when_ambiguous(self, ctx, world):
        world.seed()
        r = _history(ctx, world.tok[world.s], world.car)
        assert r.status_code == 400
        assert r.get_json().get("code") == "peer_required"

    def test_seller_history_without_peer_is_fine_with_one_buyer(self, ctx, world):
        world.send(world.b1, "only one", to=world.s)
        r = _history(ctx, world.tok[world.s], world.car)
        assert r.status_code == 200
        assert _texts(r) == ["only one"]

    def test_unknown_or_unrelated_peer_yields_an_empty_conversation(self, ctx, world):
        world.seed()
        s = world.tok[world.s]
        assert _texts(_history(ctx, s, world.car, world.x)) == []
        assert _texts(_history(ctx, s, world.car, "no-such-user")) == []
        assert _texts(_history(ctx, s, world.car, world.s)) == []  # myself

    def test_buyers_only_ever_see_their_own_conversation(self, ctx, world):
        world.seed()
        assert _texts(_history(ctx, world.tok[world.b1], world.car)) == ["b1 hello", "s -> b1"]
        assert _texts(_history(ctx, world.tok[world.b2], world.car)) == ["b2 hello", "s -> b2"]
        # a buyer naming ANOTHER buyer as the peer gets nothing
        assert _texts(_history(ctx, world.tok[world.b1], world.car, world.b2)) == []
        assert _texts(_history(ctx, world.tok[world.x], world.car)) == []

    def test_interleaved_messages_land_in_the_right_conversations(self, ctx, world):
        s1, s2 = world.b1, world.b2
        order = [
            (s1, "a1", world.s), (s2, "b1", world.s), (world.s, "a2", s1),
            (world.b3, "c1", world.s), (world.s, "b2", s2), (s2, "b3", world.s),
            (world.s, "c2", world.b3), (s1, "a3", world.s),
        ]
        for frm, text, to in order:
            assert world.send(frm, text, to=to).status_code == 201
        s = world.tok[world.s]
        assert _texts(_history(ctx, s, world.car, s1)) == ["a1", "a2", "a3"]
        assert _texts(_history(ctx, s, world.car, s2)) == ["b1", "b2", "b3"]
        assert _texts(_history(ctx, s, world.car, world.b3)) == ["c1", "c2"]

    def test_realtime_new_message_reaches_only_the_two_participants(self, ctx, world):
        assert world.send(world.b2, "opening", to=world.s).status_code == 201
        sk = {u: _sock(ctx, world.tok[u]) for u in (world.s, world.b1, world.b2)}
        assert world.send(world.b1, "from b1", to=world.s).status_code == 201
        assert world.send(world.s, "to b2", to=world.b2).status_code == 201
        got = {u: [e["args"][0]["content"] for e in _events(sk[u], "new_message")] for u in sk}
        assert got[world.s] == ["from b1", "to b2"]
        assert got[world.b1] == ["from b1"]
        assert got[world.b2] == ["to b2"]

    def test_reply_target_from_another_conversation_is_refused(self, ctx, world):
        world.seed()
        s = world.tok[world.s]
        b1_msg = _history(ctx, s, world.car, world.b1).get_json()["messages"][0]["id"]
        # quoting b1's message in a reply to b2 would disclose its text to b2
        r = world.send(world.s, "leaky", to=world.b2, reply_to=b1_msg)
        assert r.status_code == 404, r.data
        ok = world.send(world.s, "fine", to=world.b1, reply_to=b1_msg)
        assert ok.status_code == 201, ok.data
        assert ok.get_json()["message"]["reply_to_message_id"] == b1_msg

    def test_socket_send_applies_the_same_rules(self, ctx, world):
        world.seed()
        s_sock = _sock(ctx, world.tok[world.s])
        b1_msg = _history(ctx, world.tok[world.s], world.car, world.b1).get_json()["messages"][0]["id"]
        # ambiguous receiver
        s_sock.emit("send_message", {"car_id": world.car, "content": "who?"})
        assert any(e["name"] == "error" for e in s_sock.get_received())
        # cross-conversation reply
        s_sock.emit(
            "send_message",
            {"car_id": world.car, "content": "x", "receiver_id": world.b2, "reply_to_message_id": b1_msg},
        )
        assert any(e["name"] == "error" for e in s_sock.get_received())
        assert "who?" not in _texts(_history(ctx, world.tok[world.b2], world.car))
        assert "x" not in _texts(_history(ctx, world.tok[world.b2], world.car))

    def test_opening_one_thread_marks_only_that_buyers_messages_read(self, ctx, world):
        world.seed()
        b1s, b2s = _sock(ctx, world.tok[world.b1]), _sock(ctx, world.tok[world.b2])
        assert _unread(ctx, world.car, world.s, world.b1) == 1
        assert _unread(ctx, world.car, world.s, world.b2) == 1
        # the seller opens b1's conversation over REST
        assert _history(ctx, world.tok[world.s], world.car, world.b1).status_code == 200
        assert _unread(ctx, world.car, world.s, world.b1) == 0
        assert _unread(ctx, world.car, world.s, world.b2) == 1, "b2's thread must stay unread"
        assert _unread(ctx, world.car, world.s, world.b3) == 1
        # only b1 is told about the read
        assert len(_events(b1s, "messages_read")) == 1
        assert _events(b2s, "messages_read") == []

    def test_join_chat_marks_read_for_the_named_buyer_only(self, ctx, world):
        world.seed()
        b1s, b2s = _sock(ctx, world.tok[world.b1]), _sock(ctx, world.tok[world.b2])
        s_sock = _sock(ctx, world.tok[world.s])
        s_sock.emit("join_chat", {"car_id": world.car, "peer_id": world.b2})
        joined = _events(s_sock, "joined_chat")
        assert joined and joined[0]["args"][0]["ok"] is True
        assert _unread(ctx, world.car, world.s, world.b2) == 0
        assert _unread(ctx, world.car, world.s, world.b1) == 1
        assert _unread(ctx, world.car, world.s, world.b3) == 1
        assert _events(b1s, "messages_read") == []
        assert len(_events(b2s, "messages_read")) == 1

    def test_seller_join_without_peer_marks_nothing_when_ambiguous(self, ctx, world):
        world.seed()
        s_sock = _sock(ctx, world.tok[world.s])
        s_sock.emit("join_chat", {"car_id": world.car})
        joined = _events(s_sock, "joined_chat")
        assert joined and joined[0]["args"][0]["ok"] is False
        assert joined[0]["args"][0]["code"] == "peer_required"
        assert _unread(ctx, world.car, world.s, world.b1) == 1
        assert _unread(ctx, world.car, world.s, world.b2) == 1

    def test_chat_list_has_one_row_per_buyer_with_its_own_unread_count(self, ctx, world):
        world.seed()
        _app, _sio, client = ctx
        rows = client.get("/api/chats", headers=_auth(world.tok[world.s])).get_json()
        mine = [r for r in rows if r["car_id"] == world.car]
        assert sorted(r["other_user"]["id"] for r in mine) == sorted([world.b1, world.b2, world.b3])
        assert all(r["unread_count"] == 1 for r in mine)

    def test_deleted_buyers_threads_stay_separate(self, ctx, world):
        world.seed()
        app, _sio, _c = ctx
        from kk.models import Car, Message, User, db

        # b2 and b3 delete their accounts: their rows lose the live id but keep
        # a per-counterpart marker (see Message.deleted_counterpart_marker).
        with app.app_context():
            car = Car.query.filter_by(public_id=world.car).first()
            for pub, marker in ((world.b2, 902), (world.b3, 903)):
                u = User.query.filter_by(public_id=pub).first()
                for m in Message.query.filter(
                    Message.car_id == car.id,
                    (Message.sender_id == u.id) | (Message.receiver_id == u.id),
                ).all():
                    m.deleted_counterpart_marker = marker
                    if m.sender_id == u.id:
                        m.sender_id = None
                    if m.receiver_id == u.id:
                        m.receiver_id = None
            db.session.commit()
        s = world.tok[world.s]
        assert _texts(_history(ctx, s, world.car, "deleted-user:902")) == ["b2 hello", "s -> b2"]
        assert _texts(_history(ctx, s, world.car, "deleted-user:903")) == ["b3 hello"]
        # several conversations + no peer named -> never merged
        assert _history(ctx, s, world.car).status_code == 400
        _app, _sio, client = ctx
        rows = client.get("/api/chats", headers=_auth(s)).get_json()
        keys = sorted(
            r.get("peer_key")
            for r in rows
            if r["car_id"] == world.car and r["other_user"]["id"] is None
        )
        assert keys == ["deleted-user:902", "deleted-user:903"]
        # opening a deleted thread clears ITS unread messages only
        assert _history(ctx, s, world.car, "deleted-user:902").status_code == 200
        rows = client.get("/api/chats", headers=_auth(s)).get_json()
        by_key = {r.get("peer_key"): r["unread_count"] for r in rows if r["car_id"] == world.car}
        # (deleted counterparts report unread 0 in the list; the live buyer b1 is untouched)
        assert _unread(ctx, world.car, world.s, world.b1) == 1
        assert by_key  # rows still listed


# ===================================================================== F-25 ==


class TestF25TypingStaysInTheConversation:
    def _setup(self, ctx, world):
        world.seed()
        sk = {u: _sock(ctx, world.tok[u]) for u in (world.s, world.b1, world.b2, world.b3, world.x)}
        # everyone joins THEIR conversation (the seller joins one room per buyer)
        sk[world.b1].emit("join_chat", {"car_id": world.car})
        sk[world.b2].emit("join_chat", {"car_id": world.car})
        sk[world.b3].emit("join_chat", {"car_id": world.car})
        sk[world.s].emit("join_chat", {"car_id": world.car, "peer_id": world.b1})
        sk[world.s].emit("join_chat", {"car_id": world.car, "peer_id": world.b2})
        sk[world.s].emit("join_chat", {"car_id": world.car, "peer_id": world.b3})
        sk[world.x].emit("join_chat", {"car_id": world.car})
        for s in sk.values():
            s.get_received()
        return sk

    def _typing(self, sock):
        return [e["args"][0] for e in _events(sock, "typing")]

    def test_a_buyers_typing_reaches_only_the_seller(self, ctx, world):
        sk = self._setup(ctx, world)
        sk[world.b1].emit("typing_start", {"car_id": world.car})
        got = {u: self._typing(s) for u, s in sk.items()}
        assert [t["user_id"] for t in got[world.s]] == [world.b1]
        assert got[world.s][0]["peer_id"] == world.s
        assert got[world.s][0]["car_id"] == world.car
        assert got[world.b1] == [] and got[world.b2] == [] and got[world.b3] == []
        assert got[world.x] == []

    def test_typing_does_not_leak_between_buyers_either_way(self, ctx, world):
        sk = self._setup(ctx, world)
        sk[world.b2].emit("typing_start", {"car_id": world.car})
        sk[world.b2].emit("typing_stop", {"car_id": world.car})
        got = {u: self._typing(s) for u, s in sk.items()}
        assert [t["typing"] for t in got[world.s]] == [True, False]
        assert got[world.b1] == [] and got[world.b3] == []

    def test_the_sellers_typing_reaches_only_the_named_buyer(self, ctx, world):
        sk = self._setup(ctx, world)
        sk[world.s].emit("typing_start", {"car_id": world.car, "peer_id": world.b1})
        got = {u: self._typing(s) for u, s in sk.items()}
        assert [t["user_id"] for t in got[world.b1]] == [world.s]
        assert got[world.b1][0]["peer_id"] == world.b1
        assert got[world.b2] == [] and got[world.b3] == [] and got[world.x] == []
        assert got[world.s] == []

    def test_a_seller_typing_without_naming_a_buyer_is_dropped(self, ctx, world):
        sk = self._setup(ctx, world)
        sk[world.s].emit("typing_start", {"car_id": world.car})
        assert all(self._typing(s) == [] for s in sk.values())

    def test_a_non_participant_cannot_type_into_or_join_a_conversation(self, ctx, world):
        sk = self._setup(ctx, world)
        sk[world.x].emit("typing_start", {"car_id": world.car})
        sk[world.x].emit("typing_start", {"car_id": world.car, "peer_id": world.b1})
        sk[world.x].emit("join_chat", {"car_id": world.car, "peer_id": world.b1})
        joined = _events(sk[world.x], "joined_chat")
        assert all(j["args"][0]["ok"] is False for j in joined)
        assert all(self._typing(s) == [] for s in sk.values())

    def test_a_buyer_cannot_target_another_buyer(self, ctx, world):
        sk = self._setup(ctx, world)
        sk[world.b1].emit("typing_start", {"car_id": world.car, "peer_id": world.b2})
        assert all(self._typing(s) == [] for s in sk.values())

    def test_a_buyer_with_no_thread_yet_cannot_reach_the_seller_room(self, ctx, world):
        # b3-like newcomer: public listing, no prior message
        fresh = _user(ctx, "freshbuyer")
        tok = _login(ctx, fresh)
        s_sock = _sock(ctx, world.tok[world.s])
        world.seed()
        s_sock.emit("join_chat", {"car_id": world.car, "peer_id": world.b1})
        s_sock.get_received()
        f = _sock(ctx, tok)
        f.emit("typing_start", {"car_id": world.car})
        assert self._typing(s_sock) == [], "typing needs an existing thread (soft deny)"

    def test_blocked_users_cannot_type_at_each_other(self, ctx, world):
        sk = self._setup(ctx, world)
        _app, _sio, client = ctx
        assert client.post(f"/api/users/{world.b1}/block", headers=_auth(world.tok[world.s])).status_code in (200, 201)
        for s in sk.values():
            s.get_received()
        sk[world.b1].emit("typing_start", {"car_id": world.car})
        sk[world.s].emit("typing_start", {"car_id": world.car, "peer_id": world.b1})
        assert all(self._typing(s) == [] for s in sk.values())

    def test_two_listings_do_not_share_typing(self, ctx, world):
        sk = self._setup(ctx, world)
        other_car = _car(ctx, world.s)
        # b1 chats with the same seller about ANOTHER listing
        assert _send(ctx, world.tok[world.b1], other_car, "second car", receiver=world.s).status_code == 201
        sk[world.b1].emit("join_chat", {"car_id": other_car})
        sk[world.s].emit("join_chat", {"car_id": other_car, "peer_id": world.b1})
        for s in sk.values():
            s.get_received()
        sk[world.b1].emit("typing_start", {"car_id": other_car})
        got = self._typing(sk[world.s])
        assert [t["car_id"] for t in got] == [other_car]


# ===================================================================== F-36 ==


def _token(ctx, public_id, **kw):
    app, _sio, _c = ctx
    from flask_jwt_extended import create_access_token

    with app.app_context():
        return create_access_token(identity=public_id, **kw)


def _connect_raw(ctx, token):
    app, sio, client = ctx
    return sio.test_client(
        app, flask_test_client=client, headers={"Authorization": f"Bearer {token}"}
    )


class TestF36SocketAuthenticationLifetime:
    def test_valid_token_connects_authenticated_with_its_expiry(self, ctx, world):
        c = _connect_raw(ctx, world.tok[world.b1])
        assert c.is_connected()
        ev = _events(c, "connected")[0]["args"][0]
        assert ev["authenticated"] is True and ev["user_id"] == world.b1
        assert isinstance(ev["expires_at"], int) and ev["expires_at"] > 0

    def test_expired_token_is_refused_not_downgraded_to_a_guest(self, ctx, world):
        expired = _token(ctx, world.b1, expires_delta=timedelta(seconds=-30))
        c = _connect_raw(ctx, expired)
        assert not c.is_connected()

    def test_garbage_token_is_refused(self, ctx, world):
        assert not _connect_raw(ctx, "not.a.jwt").is_connected()
        assert not _connect_raw(ctx, "a.b.c").is_connected()

    def test_refresh_token_is_not_accepted_as_a_socket_credential(self, ctx, world):
        app, _sio, client = ctx
        r = client.post(
            "/api/auth/login",
            json={"username": _username(ctx, world.b1), "password": PASSWORD},
        )
        refresh = r.get_json().get("refresh_token")
        assert refresh
        assert not _connect_raw(ctx, refresh).is_connected()

    def test_token_presented_through_a_forbidden_source_is_refused(
        self, ctx, world, monkeypatch
    ):
        """A JWT in the query string (when that source is disabled) is a
        presented credential: it must be refused, not downgraded to a guest.
        Connecting with no credentials at all stays an anonymous guest."""
        from kk import socketio_handlers as sh

        app, sio, client = ctx
        monkeypatch.setattr(sh, "_allow_socket_query_token", lambda: False)
        c = sio.test_client(
            app,
            flask_test_client=client,
            query_string=f"token={world.tok[world.b1]}",
        )
        assert not c.is_connected()

        guest = sio.test_client(app, flask_test_client=client)
        assert guest.is_connected()
        ev = _events(guest, "connected")[0]["args"][0]
        assert ev["authenticated"] is False

        # The very same token through the Authorization header is accepted.
        assert _connect_raw(ctx, world.tok[world.b1]).is_connected()

    def test_no_credentials_is_still_an_anonymous_connection(self, ctx):
        app, sio, client = ctx
        c = sio.test_client(app, flask_test_client=client)
        assert c.is_connected()
        ev = _events(c, "connected")[0]["args"][0]
        assert ev["authenticated"] is False and ev["user_id"] is None

    def test_unknown_or_inactive_account_is_refused(self, ctx, world):
        assert not _connect_raw(ctx, _token(ctx, "pub-does-not-exist")).is_connected()
        app, _sio, _c = ctx
        from kk.models import User, db

        with app.app_context():
            u = User.query.filter_by(public_id=world.b3).first()
            u.is_active = False
            db.session.commit()
        assert not _connect_raw(ctx, world.tok[world.b3]).is_connected()

    def test_live_socket_is_closed_when_its_token_expires(self, ctx, world):
        from kk import socketio_handlers as sh

        world.seed()
        short = _token(ctx, world.b1, expires_delta=timedelta(seconds=120))
        c = _connect_raw(ctx, short)
        assert c.is_connected()
        c.get_received()
        # time passes beyond the token's expiry; the next event is refused AND
        # the connection is torn down with an explicit reason
        real = sh._now
        with patch.object(sh, "_now", lambda: real() + 600):
            c.emit("typing_start", {"car_id": world.car})
            received = _drain(c)
        assert any(
            e["name"] == "auth_expired" and e["args"][0]["code"] == "token_expired"
            for e in received
        ), received
        assert not c.is_connected()

    def test_an_expired_socket_stops_receiving_private_events(self, ctx, world):
        from kk import socketio_handlers as sh

        world.seed()
        short = _token(ctx, world.b1, expires_delta=timedelta(seconds=120))
        c = _connect_raw(ctx, short)
        c.get_received()
        (sid,) = [k for k, v in sh._SOCKET_AUTH.items() if v["user_public_id"] == world.b1][-1:]
        real = sh._now
        with patch.object(sh, "_now", lambda: real() + 600):
            assert sh.enforce_socket_expiry(sid) is True
        assert not c.is_connected()
        # a new message for b1 must not reach the dead socket
        world.send(world.s, "after expiry", to=world.b1)
        assert [e for e in _drain(c) if e["name"] == "new_message"] == []

    def test_enforce_expiry_is_a_noop_while_the_token_is_valid(self, ctx, world):
        from kk import socketio_handlers as sh

        c = _connect_raw(ctx, world.tok[world.b2])
        c.get_received()
        sid = [k for k, v in sh._SOCKET_AUTH.items() if v["user_public_id"] == world.b2][-1]
        assert sh.enforce_socket_expiry(sid) is False
        assert c.is_connected()

    def test_reconnect_with_a_fresh_token_works_after_expiry(self, ctx, world):
        from kk import socketio_handlers as sh

        world.seed()
        short = _token(ctx, world.b1, expires_delta=timedelta(seconds=120))
        old = _connect_raw(ctx, short)
        old.get_received()
        real = sh._now
        with patch.object(sh, "_now", lambda: real() + 600):
            old.emit("typing_start", {"car_id": world.car})
        assert not old.is_connected()
        fresh = _connect_raw(ctx, _login(ctx, world.b1))
        assert fresh.is_connected()
        fresh.get_received()
        world.send(world.s, "welcome back", to=world.b1)
        assert [e["args"][0]["content"] for e in _events(fresh, "new_message")] == ["welcome back"]

    def test_a_revoked_token_is_refused_at_connect_and_on_live_sockets(self, ctx, world):
        _app, _sio, client = ctx
        tok = _login(ctx, world.b2)
        live = _connect_raw(ctx, tok)
        assert live.is_connected()
        live.get_received()
        r = client.post("/api/auth/logout", headers=_auth(tok), json={})
        assert r.status_code in (200, 204), r.data
        # the still-open socket is closed on its next event ...
        live.emit("typing_start", {"car_id": world.car})
        assert any(e["name"] == "auth_expired" for e in _drain(live))
        assert not live.is_connected()
        # ... and the revoked token cannot open a new one
        assert not _connect_raw(ctx, tok).is_connected()

    def test_each_socket_is_bound_to_its_own_account(self, ctx, world):
        world.seed()
        a, b = _sock(ctx, world.tok[world.b1]), _sock(ctx, world.tok[world.b2])
        world.send(world.s, "for b1", to=world.b1)
        world.send(world.s, "for b2", to=world.b2)
        assert [e["args"][0]["content"] for e in _events(a, "new_message")] == ["for b1"]
        assert [e["args"][0]["content"] for e in _events(b, "new_message")] == ["for b2"]

    def test_account_switch_reconnect_does_not_inherit_the_previous_account(self, ctx, world):
        world.seed()
        first = _sock(ctx, world.tok[world.b1])
        first.disconnect()
        second = _sock(ctx, world.tok[world.b2])
        world.send(world.s, "for b1 again", to=world.b1)
        world.send(world.s, "for b2 again", to=world.b2)
        assert [e["args"][0]["content"] for e in _events(second, "new_message")] == ["for b2 again"]

    def test_events_use_the_bound_account_never_one_named_in_the_payload(self, ctx, world):
        world.seed()
        b1 = _sock(ctx, world.tok[world.b1])
        # b1 claims to be the seller / names the seller as the sender
        b1.emit(
            "send_message",
            {"car_id": world.car, "content": "spoof", "receiver_id": world.b2, "sender_id": world.s},
        )
        assert any(e["name"] == "error" for e in b1.get_received())
        assert "spoof" not in _texts(_history(ctx, world.tok[world.b2], world.car))
