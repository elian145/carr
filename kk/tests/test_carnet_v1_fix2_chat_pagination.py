"""CarNet V1 release-candidate fix 2 -- chat pagination direction.

Bug: ``GET /api/chat/<conversation_id>/messages`` always sorted ascending
and paginated forward with `page`/offset (``page=1`` == oldest messages).
Flutter opened a conversation at ``page=1`` (expecting the newest
messages) and requested ``page+1`` when the user scrolled up (expecting
OLDER messages). For any conversation with more than one page of history,
this meant:
  * opening a conversation showed the OLDEST messages, not the latest.
  * scrolling up loaded NEWER messages instead of older ones.

Fix: ``get_messages()`` (``kk/routes/chat.py``) now has a single supported
pagination contract: with no `before` cursor it returns the newest
`per_page` messages; passing `before` (the ISO timestamp of the oldest
message currently loaded) returns the next-older page. The response
`messages` array is always in ascending chronological order. `page`/offset
pagination has been removed entirely (no second, competing scheme).

Covers (with a 120-message conversation, more than 2 pages at the default
50/page):
  * Opening the conversation (no `before`) returns the newest 50 messages,
    in ascending order, with `has_more=True`.
  * Passing `before=<oldest loaded message's created_at>` returns the next
    50 older messages, still ascending, contiguous with (and strictly
    older than) the first page -- no gap, no overlap.
  * Repeating with the new oldest cursor reaches the remaining tail
    (`has_more=False` once the true oldest message has been returned).
  * Concatenating all three pages, oldest-to-newest, reconstructs the full
    120-message history with no duplicates and no missing messages.
  * `total` always reports the conversation's full message count,
    independent of the `before` cursor.
"""

from __future__ import annotations

import os
import sys
import tempfile
import uuid
from datetime import timedelta
from pathlib import Path

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

_PASSWORD = "Aa123456!"


def _unique_phone() -> str:
    return f"079{uuid.uuid4().int % 10**8:08d}"


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(
        prefix="carlist_cnv1fix2_chat_page_", ignore_cleanup_errors=True
    )
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "chat_page.db")

    from kk.app_factory import create_app

    app, _socketio, *_ = create_app()
    from kk.models import Car, Message, User, db
    from kk.time_utils import utcnow

    with app.app_context():
        db.drop_all()
        db.create_all()

    yield app, app.test_client(), db, User, Car, Message, utcnow

    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    tmp.cleanup()


@pytest.fixture
def client(app_ctx):
    return app_ctx[1]


def _make_user(app_ctx) -> tuple[str, int, str]:
    app, _client, db, User, *_ = app_ctx
    username = f"cnv1fix2_{uuid.uuid4().hex[:10]}"
    with app.app_context():
        user = User(
            username=username,
            phone_number=_unique_phone(),
            first_name="Chat",
            last_name="Page",
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id=f"pub-{uuid.uuid4().hex[:12]}",
        )
        user.set_password(_PASSWORD)
        db.session.add(user)
        db.session.commit()
        return user.public_id, user.id, username


def _login(client, username: str) -> str:
    r = client.post(
        "/api/auth/login", json={"username": username, "password": _PASSWORD}
    )
    assert r.status_code == 200, r.data
    return r.get_json()["access_token"]


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _make_car(app_ctx, seller_id: int) -> tuple[int, str]:
    app, _client, db, _User, Car, *_ = app_ctx
    with app.app_context():
        car = Car(
            seller_id=seller_id,
            public_id=f"car-{uuid.uuid4().hex[:12]}",
            brand="toyota",
            model="corolla",
            year=2021,
            mileage=10,
            engine_type="gas",
            transmission="auto",
            drive_type="fwd",
            condition="used",
            body_type="sedan",
            price=15000,
            location="Erbil",
            is_active=True,
        )
        db.session.add(car)
        db.session.commit()
        return car.id, car.public_id


def _seed_conversation(app_ctx, *, car_id: int, seller_id: int, buyer_id: int, n: int) -> list[str]:
    """Creates `n` alternating messages with strictly increasing timestamps
    (one minute apart) so ordering is unambiguous. Returns the message
    contents in creation (== chronological) order, each uniquely
    identifiable as "msg-<index>"."""
    app, _client, db, _User, _Car, Message, utcnow = app_ctx
    contents = [f"msg-{i:04d}" for i in range(n)]
    with app.app_context():
        base = utcnow()
        for i, text in enumerate(contents):
            sender_id = seller_id if i % 2 == 0 else buyer_id
            receiver_id = buyer_id if i % 2 == 0 else seller_id
            db.session.add(
                Message(
                    car_id=car_id,
                    sender_id=sender_id,
                    receiver_id=receiver_id,
                    content=text,
                    created_at=base + timedelta(minutes=i),
                )
            )
        db.session.commit()
    return contents


def _contents(body: dict) -> list[str]:
    return [m["content"] for m in body["messages"]]


def test_opening_conversation_returns_newest_messages_ascending(app_ctx, client):
    _seller_pub, seller_id, seller_username = _make_user(app_ctx)
    _buyer_pub, buyer_id, _buyer_username = _make_user(app_ctx)
    car_id, car_public_id = _make_car(app_ctx, seller_id)
    all_contents = _seed_conversation(
        app_ctx, car_id=car_id, seller_id=seller_id, buyer_id=buyer_id, n=120
    )
    token = _login(client, seller_username)

    r = client.get(f"/api/chat/{car_public_id}/messages", headers=_auth(token))
    assert r.status_code == 200, r.data
    body = r.get_json()

    assert body["total"] == 120
    assert body["has_more"] is True
    assert len(body["messages"]) == 50
    # The newest 50 messages (msg-0070 .. msg-0119), in ascending order.
    expected = all_contents[70:120]
    assert _contents(body) == expected


def test_scrolling_up_loads_strictly_older_contiguous_page(app_ctx, client):
    _seller_pub, seller_id, seller_username = _make_user(app_ctx)
    _buyer_pub, buyer_id, _buyer_username = _make_user(app_ctx)
    car_id, car_public_id = _make_car(app_ctx, seller_id)
    all_contents = _seed_conversation(
        app_ctx, car_id=car_id, seller_id=seller_id, buyer_id=buyer_id, n=120
    )
    token = _login(client, seller_username)

    r1 = client.get(f"/api/chat/{car_public_id}/messages", headers=_auth(token))
    body1 = r1.get_json()
    oldest_loaded = body1["messages"][0]["created_at"]

    r2 = client.get(
        f"/api/chat/{car_public_id}/messages",
        query_string={"before": oldest_loaded},
        headers=_auth(token),
    )
    assert r2.status_code == 200, r2.data
    body2 = r2.get_json()

    assert body2["has_more"] is True
    assert len(body2["messages"]) == 50
    expected_page_2 = all_contents[20:70]
    assert _contents(body2) == expected_page_2

    # Contiguous, no overlap: page 2's last message directly precedes
    # page 1's first message.
    assert body2["messages"][-1]["content"] == "msg-0069"
    assert body1["messages"][0]["content"] == "msg-0070"

    # Third (final) page reaches the true oldest message and reports no more.
    oldest_loaded_2 = body2["messages"][0]["created_at"]
    r3 = client.get(
        f"/api/chat/{car_public_id}/messages",
        query_string={"before": oldest_loaded_2},
        headers=_auth(token),
    )
    body3 = r3.get_json()
    assert body3["has_more"] is False
    expected_page_3 = all_contents[0:20]
    assert _contents(body3) == expected_page_3

    # Reconstructing oldest-to-newest from all three pages reproduces the
    # full 120-message history with no duplicates and no gaps.
    reconstructed = _contents(body3) + _contents(body2) + _contents(body1)
    assert reconstructed == all_contents
    assert len(set(reconstructed)) == 120


def test_small_conversation_has_no_more_and_single_page(app_ctx, client):
    _seller_pub, seller_id, seller_username = _make_user(app_ctx)
    _buyer_pub, buyer_id, _buyer_username = _make_user(app_ctx)
    car_id, car_public_id = _make_car(app_ctx, seller_id)
    all_contents = _seed_conversation(
        app_ctx, car_id=car_id, seller_id=seller_id, buyer_id=buyer_id, n=5
    )
    token = _login(client, seller_username)

    r = client.get(f"/api/chat/{car_public_id}/messages", headers=_auth(token))
    body = r.get_json()
    assert body["total"] == 5
    assert body["has_more"] is False
    assert _contents(body) == all_contents


def test_before_cursor_respects_participant_authorization(app_ctx, client):
    """An unrelated third user must not be able to page through someone
    else's conversation via the `before` cursor either."""
    _seller_pub, seller_id, seller_username = _make_user(app_ctx)
    _buyer_pub, buyer_id, _buyer_username = _make_user(app_ctx)
    _stranger_pub, _stranger_id, stranger_username = _make_user(app_ctx)
    car_id, car_public_id = _make_car(app_ctx, seller_id)
    _seed_conversation(
        app_ctx, car_id=car_id, seller_id=seller_id, buyer_id=buyer_id, n=60
    )
    stranger_token = _login(client, stranger_username)

    r = client.get(
        f"/api/chat/{car_public_id}/messages",
        query_string={"before": "2999-01-01T00:00:00Z"},
        headers=_auth(stranger_token),
    )
    assert r.status_code == 200, r.data
    body = r.get_json()
    assert body["messages"] == []
    assert body["total"] == 0
