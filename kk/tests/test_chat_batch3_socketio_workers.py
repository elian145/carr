"""CHAT-1 / Batch 3 — Socket.IO worker policy + legacy send_message compat."""

from __future__ import annotations

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

from kk.socketio_deploy import (
    resolve_web_concurrency,
    socketio_multi_worker_requires_sticky_sessions,
)


def test_default_workers_is_one_even_when_redis_present():
    assert (
        resolve_web_concurrency(
            None,
            redis_url="redis://localhost:6379/0",
            socketio_message_queue="redis://localhost:6379/0",
        )
        == 1
    )


def test_explicit_web_concurrency_honored():
    assert resolve_web_concurrency("2", redis_url="redis://x") == 2
    assert resolve_web_concurrency("1") == 1


def test_invalid_web_concurrency_falls_back_to_one():
    assert resolve_web_concurrency("nope") == 1
    assert resolve_web_concurrency("0") == 1
    assert resolve_web_concurrency("-3") == 1


def test_multi_worker_flag_requires_sticky_sessions():
    assert socketio_multi_worker_requires_sticky_sessions(1) is False
    assert socketio_multi_worker_requires_sticky_sessions(2) is True


def test_app_factory_async_mode_stays_threading_without_eventlet_breakglass(
    monkeypatch,
):
    monkeypatch.setenv("REDIS_URL", "redis://localhost:6379/0")
    monkeypatch.setenv("SOCKETIO_ASYNC_MODE", "eventlet")
    monkeypatch.delenv("SOCKETIO_ALLOW_EVENTLET", raising=False)
    from kk.app_factory import _socketio_async_mode

    assert _socketio_async_mode("production", has_message_queue=True) == "threading"


def test_gunicorn_conf_resolve_matches_helper(monkeypatch):
    """Default WEB_CONCURRENCY remains 1 even when Redis is configured."""
    monkeypatch.delenv("WEB_CONCURRENCY", raising=False)
    monkeypatch.setenv("REDIS_URL", "redis://localhost:6379/0")
    assert (
        resolve_web_concurrency(
            os.environ.get("WEB_CONCURRENCY"),
            redis_url=os.environ.get("REDIS_URL"),
        )
        == 1
    )


def test_gthread_threading_are_compatible_defaults(monkeypatch):
    """CHAT-1: production default path stays gthread + Socket.IO threading."""
    monkeypatch.delenv("SOCKETIO_ASYNC_MODE", raising=False)
    monkeypatch.delenv("SOCKETIO_ALLOW_EVENTLET", raising=False)
    monkeypatch.setenv("REDIS_URL", "redis://localhost:6379/0")
    from kk.app_factory import _socketio_async_mode

    assert _socketio_async_mode("production", has_message_queue=True) == "threading"
    assert resolve_web_concurrency(None, redis_url="redis://x") == 1


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(
        prefix="carlist_chat3_", ignore_cleanup_errors=True
    )
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "chat3.db")

    from kk.app_factory import create_app

    app, socketio, *_ = create_app()
    from kk.models import Car, Message, User, db

    with app.app_context():
        db.drop_all()
        db.create_all()

    yield app, socketio, app.test_client(), db, User, Car, Message

    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    tmp.cleanup()


_PASSWORD = "Aa123456!"


def _make_user(app_ctx, *, tag: str):
    app, _sio, _client, db, User, *_ = app_ctx
    with app.app_context():
        u = User(
            username=f"{tag}_{uuid.uuid4().hex[:8]}",
            phone_number=f"077{uuid.uuid4().int % 10**8:08d}",
            first_name=tag.title(),
            last_name="Test",
            email=None,
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id=f"pub-{uuid.uuid4().hex[:12]}",
        )
        u.set_password(_PASSWORD)
        db.session.add(u)
        db.session.commit()
        return u.id, u.public_id, u.username


def test_legacy_socketio_send_message_still_accepted(app_ctx):
    """Old Android/iOS builds may still emit send_message; keep accepting it."""
    app, socketio, client, db, User, Car, Message = app_ctx
    seller_id, seller_pub, _ = _make_user(app_ctx, tag="leg_seller")
    buyer_id, _buyer_pub, buyer_user = _make_user(app_ctx, tag="leg_buyer")

    with app.app_context():
        car = Car(
            seller_id=seller_id,
            public_id=f"chat3-{uuid.uuid4().hex[:10]}",
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
        car_pub = car.public_id

    login = client.post(
        "/api/auth/login",
        json={"username": buyer_user, "password": _PASSWORD},
    )
    assert login.status_code == 200, login.data
    token = login.get_json()["access_token"]

    sio_client = socketio.test_client(
        app, flask_test_client=client, query_string=f"token={token}"
    )
    assert sio_client.is_connected(), sio_client.get_received()
    sio_client.get_received()

    with patch("kk.socketio_handlers.send_push", return_value=True):
        sio_client.emit(
            "send_message",
            {
                "car_id": car_pub,
                "content": "legacy socket hello",
                "receiver_id": seller_pub,
            },
        )
        sio_client.get_received()
    sio_client.disconnect()

    with app.app_context():
        car_row = Car.query.filter_by(public_id=car_pub).first()
        msg = Message.query.filter_by(sender_id=buyer_id, car_id=car_row.id).first()
        assert msg is not None
        assert msg.content == "legacy socket hello"
        assert msg.receiver_id == seller_id


def test_rest_text_send_still_works_for_new_clients(app_ctx):
    """New Flutter REST path targets the existing /api/chat/<id>/send contract."""
    app, _sio, client, db, User, Car, Message = app_ctx
    seller_id, seller_pub, _ = _make_user(app_ctx, tag="rest_seller")
    buyer_id, _bp, buyer_user = _make_user(app_ctx, tag="rest_buyer")

    with app.app_context():
        car = Car(
            seller_id=seller_id,
            public_id=f"chat3r-{uuid.uuid4().hex[:10]}",
            brand="honda",
            model="civic",
            year=2020,
            mileage=20,
            engine_type="gas",
            transmission="auto",
            drive_type="fwd",
            condition="used",
            body_type="sedan",
            price=12.0,
            location="Erbil",
            is_active=True,
        )
        db.session.add(car)
        db.session.commit()
        car_pub = car.public_id

    login = client.post(
        "/api/auth/login",
        json={"username": buyer_user, "password": _PASSWORD},
    )
    assert login.status_code == 200, login.data
    token = login.get_json()["access_token"]

    with patch("kk.routes.chat.send_push", return_value=True), patch(
        "kk.chat_realtime.emit_message_to_participants"
    ):
        resp = client.post(
            f"/api/chat/{car_pub}/send",
            json={
                "content": "rest hello",
                "receiver_id": seller_pub,
            },
            headers={
                "Authorization": f"Bearer {token}",
                "Idempotency-Key": f"chat3-{uuid.uuid4().hex}",
            },
        )
    assert resp.status_code == 201, resp.data
    body = resp.get_json()
    assert body.get("message", {}).get("content") == "rest hello"

    with app.app_context():
        car_row = Car.query.filter_by(public_id=car_pub).first()
        msg = Message.query.filter_by(sender_id=buyer_id, car_id=car_row.id).first()
        assert msg is not None
        assert msg.content == "rest hello"
