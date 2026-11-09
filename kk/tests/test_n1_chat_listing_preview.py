"""N-1: chat must never store/return a client-fabricated listing preview.

Before this fix every chat send path (REST JSON, REST multipart
``send_media_group`` and the Socket.IO ``send_message`` event) copied the
client-supplied ``listing_preview`` dict verbatim into ``Message.listing_preview``
and echoed it to the other participant: a forged card could show an arbitrary
title/price, an external (tracking / phishing) image URL, or ~MBs of data.

Now the preview is derived server-side from the referenced Car row (only the
listing id is read from the client), only when the listing is active and
visible to both parties, and legacy forged rows are re-derived / dropped on
read. Payload sizes are capped through ``kk.chat_payload`` for every path.
"""

from __future__ import annotations

import io
import json
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

PASSWORD = "Aa123456!"
EVIL_URL = "https://evil.example/pixel.jpg"
_FAKE_JPEG_BYTES = b"\xff\xd8\xff\xe0fake-jpeg-bytes"

FAKE_CHAT_BUCKET_CONFIG = {
    "R2_ACCOUNT_ID": "test-account-id",
    "R2_CHAT_BUCKET_NAME": "carzo-chat-media-test",
    "R2_CHAT_ACCESS_KEY_ID": "test-chat-access-key",
    "R2_CHAT_SECRET_ACCESS_KEY": "test-chat-secret-key",
}


def _fake_presign_get(*, key: str, expires_in: int = 600, timeout: float = 30) -> str:
    return f"https://fake-r2-presigned.example.test/{key}?sig=test"


@pytest.fixture(scope="module")
def ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_n1_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "n1.db")

    from kk.app_factory import create_app

    app, socketio, *_ = create_app()
    app.config.update(FAKE_CHAT_BUCKET_CONFIG)
    from kk.models import db

    with app.app_context():
        db.drop_all()
        db.create_all()
    yield app, socketio, app.test_client()
    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    tmp.cleanup()


@pytest.fixture(autouse=True)
def _isolation(monkeypatch):
    from kk import socketio_handlers as sh

    monkeypatch.setattr(sh, "_LIMITER", sh.EventRateLimiter())
    with patch("kk.r2_ops.r2_chat_put_bytes"), patch(
        "kk.r2_ops.r2_presign_get", side_effect=_fake_presign_get
    ):
        yield


def _mk_user(ctx, name):
    app, _sio, client = ctx
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
        pub, uname = u.public_id, u.username
    r = client.post("/api/auth/login", json={"username": uname, "password": PASSWORD})
    assert r.status_code == 200, r.data
    return pub, r.get_json()["access_token"]


def _mk_car(ctx, seller_pub, **kw):
    app, _sio, _c = ctx
    from kk.models import Car, CarImage, User, db

    with app.app_context():
        seller = User.query.filter_by(public_id=seller_pub).first()
        fields = dict(
            seller_id=seller.id,
            title="Real Corolla",
            brand="toyota",
            model="corolla",
            year=2021,
            mileage=10,
            engine_type="gas",
            transmission="auto",
            drive_type="fwd",
            condition="used",
            body_type="sedan",
            price=15000.0,
            currency="USD",
            location="Erbil",
            is_active=True,
        )
        fields.update(kw)
        car = Car(**fields)
        db.session.add(car)
        db.session.flush()
        db.session.add(
            CarImage(
                car_id=car.id,
                image_url="car_photos/real_corolla.jpg",
                is_primary=True,
                kind="listing",
            )
        )
        db.session.commit()
        return car.public_id


@pytest.fixture
def world(ctx):
    seller, seller_tok = _mk_user(ctx, "seller")
    buyer, buyer_tok = _mk_user(ctx, "buyer")
    return {
        "seller": seller,
        "seller_tok": seller_tok,
        "buyer": buyer,
        "buyer_tok": buyer_tok,
        "car": _mk_car(ctx, seller),
    }


def _forged(car_id):
    return {
        "id": car_id,
        "title": "FAKE: Free Ferrari, pay me first",
        "price": 1,
        "currency": "EUR",
        "location": "Nowhere",
        "image_url": EVIL_URL,
        "images": [{"image_url": EVIL_URL}, EVIL_URL],
        "brand": "ferrari",
        "blob": "x" * 3000,
    }


def _auth(tok):
    return {"Authorization": f"Bearer {tok}"}


def _post_json(ctx, tok, car, receiver, preview, content="hi"):
    _a, _s, client = ctx
    body = {"content": content, "receiver_id": receiver}
    if preview is not None:
        body["listing_preview"] = preview
    return client.post(f"/api/chat/{car}/send", headers=_auth(tok), json=body)


def _post_group(ctx, tok, car, receiver, preview, content="pics"):
    _a, _s, client = ctx
    data = {
        "receiver_id": receiver,
        "content": content,
        "attachments": (io.BytesIO(_FAKE_JPEG_BYTES), "photo.jpg"),
    }
    if preview is not None:
        data["listing_preview"] = preview if isinstance(preview, str) else json.dumps(preview)
    return client.post(
        f"/api/chat/{car}/send_media_group",
        headers=_auth(tok),
        data=data,
        content_type="multipart/form-data",
    )


def _socket_send(ctx, tok, payload):
    app, sio, client = ctx
    c = sio.test_client(app, flask_test_client=client, headers=_auth(tok))
    assert c.is_connected()
    c.get_received()
    c.emit("send_message", payload)
    return c.get_received()


def _sent(events):
    return [e["args"][0] for e in events if e["name"] == "message_sent"]


def _errors(events):
    return [e["args"][0] for e in events if e["name"] == "error"]


def _assert_trusted(preview, car_id):
    assert preview is not None
    assert preview["id"] == car_id
    assert preview["title"] == "Real Corolla"
    assert preview["price"] == 15000.0
    assert preview["currency"] == "USD"
    assert preview["location"] == "Erbil"
    assert preview["image_url"] == "uploads/car_photos/real_corolla.jpg"
    blob = json.dumps(preview)
    assert "evil.example" not in blob
    assert "FAKE" not in blob
    assert "blob" not in preview
    assert "images" not in preview or all(
        "evil" not in json.dumps(i) for i in preview["images"]
    )


def _stored_previews(ctx, car_pub):
    app, _s, _c = ctx
    from kk.models import Car, Message

    with app.app_context():
        car = Car.query.filter_by(public_id=car_pub).first()
        return [m.listing_preview for m in Message.query.filter_by(car_id=car.id).all()]


# ---------------------------------------------------------------------------
# Positive: legitimate sharing yields a trusted, DB-derived preview.
# ---------------------------------------------------------------------------


class TestLegitShare:
    def test_rest_json_id_only_preview_is_derived_from_db(self, ctx, world):
        r = _post_json(ctx, world["buyer_tok"], world["car"], world["seller"], {"id": world["car"]})
        assert r.status_code == 201, r.data
        _assert_trusted(r.get_json()["message"]["listing_preview"], world["car"])
        _assert_trusted(_stored_previews(ctx, world["car"])[0], world["car"])

    def test_rest_json_flutter_style_preview_uses_db_values(self, ctx, world):
        # The app currently sends title/price/image copied from the listing
        # details page together with the id: only the id may be honoured.
        preview = {
            "id": world["car"],
            "title": "Real Corolla",
            "price": 15000.0,
            "currency": "USD",
            "location": "Erbil",
            "image_url": "car_photos/real_corolla.jpg",
            "brand": "toyota",
            "model": "corolla",
            "year": 2021,
        }
        r = _post_json(ctx, world["buyer_tok"], world["car"], world["seller"], preview)
        assert r.status_code == 201, r.data
        _assert_trusted(r.get_json()["message"]["listing_preview"], world["car"])

    def test_preview_without_id_defaults_to_conversation_listing(self, ctx, world):
        r = _post_json(ctx, world["buyer_tok"], world["car"], world["seller"], {"title": "x"})
        assert r.status_code == 201, r.data
        _assert_trusted(r.get_json()["message"]["listing_preview"], world["car"])

    def test_multipart_preview_is_derived_from_db(self, ctx, world):
        r = _post_group(ctx, world["buyer_tok"], world["car"], world["seller"], {"id": world["car"]})
        assert r.status_code == 201, r.data
        _assert_trusted(r.get_json()["message"]["listing_preview"], world["car"])

    def test_socket_preview_is_derived_from_db(self, ctx, world):
        events = _socket_send(
            ctx,
            world["buyer_tok"],
            {
                "car_id": world["car"],
                "receiver_id": world["seller"],
                "content": "hello",
                "listing_preview": {"id": world["car"]},
            },
        )
        sent = _sent(events)
        assert len(sent) == 1, events
        _assert_trusted(sent[0]["message"]["listing_preview"], world["car"])

    def test_no_preview_stays_none(self, ctx, world):
        r = _post_json(ctx, world["buyer_tok"], world["car"], world["seller"], None)
        assert r.status_code == 201
        assert r.get_json()["message"]["listing_preview"] is None


# ---------------------------------------------------------------------------
# Negative: forged content is ignored / rejected.
# ---------------------------------------------------------------------------


class TestForgedPreviewIgnored:
    def test_rest_json_forged_fields_are_ignored(self, ctx, world):
        r = _post_json(
            ctx, world["buyer_tok"], world["car"], world["seller"], _forged(world["car"]), "x"
        )
        assert r.status_code == 201, r.data
        _assert_trusted(r.get_json()["message"]["listing_preview"], world["car"])
        stored = json.dumps(_stored_previews(ctx, world["car"]))
        assert "evil.example" not in stored and "FAKE" not in stored and "xxxxxxxx" not in stored

    def test_multipart_forged_fields_are_ignored(self, ctx, world):
        r = _post_group(ctx, world["buyer_tok"], world["car"], world["seller"], _forged(world["car"]))
        assert r.status_code == 201, r.data
        _assert_trusted(r.get_json()["message"]["listing_preview"], world["car"])

    def test_socket_forged_fields_are_ignored(self, ctx, world):
        small = _forged(world["car"])
        small["blob"] = "y" * 50
        events = _socket_send(
            ctx,
            world["buyer_tok"],
            {
                "car_id": world["car"],
                "receiver_id": world["seller"],
                "content": "hello",
                "listing_preview": small,
            },
        )
        sent = _sent(events)
        assert len(sent) == 1, events
        _assert_trusted(sent[0]["message"]["listing_preview"], world["car"])

    def test_forged_preview_is_not_leaked_to_receiver_via_history(self, ctx, world):
        _post_json(ctx, world["buyer_tok"], world["car"], world["seller"], _forged(world["car"]), "x")
        _a, _s, client = ctx
        r = client.get(f"/api/chat/{world['car']}/messages", headers=_auth(world["seller_tok"]))
        assert r.status_code == 200
        blob = json.dumps(r.get_json())
        assert "evil.example" not in blob and "FAKE" not in blob

    def test_preview_that_is_not_an_object_is_rejected(self, ctx, world):
        r = _post_json(ctx, world["buyer_tok"], world["car"], world["seller"], "javascript:alert(1)")
        assert r.status_code == 400
        assert r.get_json().get("code") == "invalid_listing_preview"

    def test_non_string_preview_id_is_rejected(self, ctx, world):
        r = _post_json(
            ctx, world["buyer_tok"], world["car"], world["seller"], {"id": {"$ne": 1}}
        )
        assert r.status_code == 400


# ---------------------------------------------------------------------------
# Negative: unknown / unauthorized / deleted / draft listings.
# ---------------------------------------------------------------------------


class TestUnauthorizedListing:
    def test_unknown_listing_id_rejected_same_as_private(self, ctx, world):
        r = _post_json(
            ctx, world["buyer_tok"], world["car"], world["seller"], {"id": "does-not-exist"}
        )
        assert r.status_code == 404
        assert r.get_json()["code"] == "listing_preview_unavailable"
        assert _stored_previews(ctx, world["car"]) == []

    @pytest.mark.parametrize("status", ["draft", "pending", "hidden"])
    def test_other_users_private_listing_does_not_leak(self, ctx, world, status):
        other_seller, _ = _mk_user(ctx, "other")
        private = _mk_car(ctx, other_seller, status=status, title="SECRET PRIVATE CAR")
        r = _post_json(ctx, world["buyer_tok"], world["car"], world["seller"], {"id": private})
        unknown = _post_json(
            ctx, world["buyer_tok"], world["car"], world["seller"], {"id": "nope-nope"}
        )
        assert r.status_code == unknown.status_code == 404
        # Identical body: existence of the private listing is not revealed.
        assert r.get_json() == unknown.get_json()
        assert "SECRET" not in r.get_data(as_text=True)
        assert _stored_previews(ctx, world["car"]) == []

    def test_deleted_listing_preview_rejected(self, ctx, world):
        other_seller, _ = _mk_user(ctx, "other")
        gone = _mk_car(ctx, other_seller, is_active=False, title="GONE CAR")
        r = _post_json(ctx, world["buyer_tok"], world["car"], world["seller"], {"id": gone})
        assert r.status_code == 404
        assert "GONE" not in r.get_data(as_text=True)

    def test_socket_unauthorized_preview_gets_error_and_no_message(self, ctx, world):
        other_seller, _ = _mk_user(ctx, "other")
        private = _mk_car(ctx, other_seller, status="draft", title="SECRET PRIVATE CAR")
        events = _socket_send(
            ctx,
            world["buyer_tok"],
            {
                "car_id": world["car"],
                "receiver_id": world["seller"],
                "content": "hello",
                "listing_preview": {"id": private},
            },
        )
        assert _sent(events) == []
        errs = _errors(events)
        assert errs and errs[0].get("code") == "listing_preview_unavailable"
        assert "SECRET" not in json.dumps(events)
        assert _stored_previews(ctx, world["car"]) == []

    def test_multipart_unauthorized_preview_rejected(self, ctx, world):
        other_seller, _ = _mk_user(ctx, "other")
        private = _mk_car(ctx, other_seller, status="hidden")
        r = _post_group(ctx, world["buyer_tok"], world["car"], world["seller"], {"id": private})
        assert r.status_code == 404
        assert _stored_previews(ctx, world["car"]) == []

    def test_conversation_listing_hidden_after_thread_drops_preview_request(self, ctx, world):
        # A listing that became non-public cannot be advertised to the peer.
        _post_json(ctx, world["buyer_tok"], world["car"], world["seller"], None, "first")
        app, _s, _c = ctx
        from kk.models import Car, db

        with app.app_context():
            Car.query.filter_by(public_id=world["car"]).update({"status": "hidden"})
            db.session.commit()
        r = _post_json(
            ctx, world["seller_tok"], world["car"], world["buyer"], {"id": world["car"]}, "again"
        )
        assert r.status_code == 404


# ---------------------------------------------------------------------------
# Payload limits (shared across REST JSON / multipart / socket).
# ---------------------------------------------------------------------------


class TestPayloadLimits:
    def test_rest_json_oversized_preview_rejected(self, ctx, world):
        r = _post_json(
            ctx,
            world["buyer_tok"],
            world["car"],
            world["seller"],
            {"id": world["car"], "blob": "x" * 20000},
        )
        assert r.status_code == 413
        assert r.get_json()["code"] == "payload_too_large"
        assert _stored_previews(ctx, world["car"]) == []

    def test_rest_json_oversized_content_rejected(self, ctx, world):
        from kk.chat_payload import MAX_CHAT_CONTENT_CHARS

        r = _post_json(
            ctx, world["buyer_tok"], world["car"], world["seller"], None, "a" * (MAX_CHAT_CONTENT_CHARS + 1)
        )
        assert r.status_code == 400
        assert r.get_json()["code"] == "content_too_long"

    def test_rest_json_content_at_limit_is_accepted(self, ctx, world):
        from kk.chat_payload import MAX_CHAT_CONTENT_CHARS

        r = _post_json(
            ctx, world["buyer_tok"], world["car"], world["seller"], None, "a" * MAX_CHAT_CONTENT_CHARS
        )
        assert r.status_code == 201

    def test_rest_json_total_body_too_large_rejected(self, ctx, world):
        from kk.chat_payload import MAX_CHAT_JSON_BODY_BYTES

        _a, _s, client = ctx
        r = client.post(
            f"/api/chat/{world['car']}/send",
            headers=_auth(world["buyer_tok"]),
            json={
                "content": "hi",
                "receiver_id": world["seller"],
                "extra": "z" * (MAX_CHAT_JSON_BODY_BYTES + 10),
            },
        )
        assert r.status_code == 413
        assert r.get_json()["code"] == "payload_too_large"

    def test_multipart_oversized_preview_rejected(self, ctx, world):
        r = _post_group(
            ctx,
            world["buyer_tok"],
            world["car"],
            world["seller"],
            json.dumps({"id": world["car"], "blob": "x" * 20000}),
        )
        assert r.status_code == 413
        assert r.get_json()["code"] == "payload_too_large"
        assert _stored_previews(ctx, world["car"]) == []

    def test_multipart_invalid_preview_json_rejected(self, ctx, world):
        r = _post_group(ctx, world["buyer_tok"], world["car"], world["seller"], "{not json")
        assert r.status_code == 400
        assert r.get_json()["code"] == "invalid_listing_preview"

    def test_multipart_oversized_content_rejected(self, ctx, world):
        from kk.chat_payload import MAX_CHAT_CONTENT_CHARS

        r = _post_group(
            ctx, world["buyer_tok"], world["car"], world["seller"], None, "a" * (MAX_CHAT_CONTENT_CHARS + 1)
        )
        assert r.status_code == 400
        assert r.get_json()["code"] == "content_too_long"
        assert _stored_previews(ctx, world["car"]) == []

    def test_multipart_image_caption_oversized_rejected(self, ctx, world):
        from kk.chat_payload import MAX_CHAT_CONTENT_CHARS

        _a, _s, client = ctx
        r = client.post(
            f"/api/chat/{world['car']}/send_image",
            headers=_auth(world["buyer_tok"]),
            data={
                "receiver_id": world["seller"],
                "content": "c" * (MAX_CHAT_CONTENT_CHARS + 1),
                "file": (io.BytesIO(_FAKE_JPEG_BYTES), "photo.jpg"),
            },
            content_type="multipart/form-data",
        )
        assert r.status_code == 400
        assert r.get_json()["code"] == "content_too_long"

    def test_socket_oversized_preview_rejected_with_error(self, ctx, world):
        events = _socket_send(
            ctx,
            world["buyer_tok"],
            {
                "car_id": world["car"],
                "receiver_id": world["seller"],
                "content": "hello",
                "listing_preview": {"id": world["car"], "title": "x" * 20000},
            },
        )
        assert _sent(events) == []
        errs = _errors(events)
        assert errs and errs[0]["code"] == "payload_too_large"
        assert _stored_previews(ctx, world["car"]) == []

    def test_socket_oversized_content_rejected(self, ctx, world):
        from kk.chat_payload import MAX_CHAT_CONTENT_CHARS

        events = _socket_send(
            ctx,
            world["buyer_tok"],
            {
                "car_id": world["car"],
                "receiver_id": world["seller"],
                "content": "a" * (MAX_CHAT_CONTENT_CHARS + 1),
            },
        )
        assert _sent(events) == []
        errs = _errors(events)
        assert errs and errs[0]["code"] == "content_too_long"

    def test_socket_total_payload_too_large_rejected(self, ctx, world):
        from kk.chat_payload import MAX_CHAT_SOCKET_PAYLOAD_BYTES

        events = _socket_send(
            ctx,
            world["buyer_tok"],
            {
                "car_id": world["car"],
                "receiver_id": world["seller"],
                "content": "hello",
                "junk": "z" * (MAX_CHAT_SOCKET_PAYLOAD_BYTES + 10),
            },
        )
        assert _sent(events) == []
        errs = _errors(events)
        assert errs and errs[0]["code"] == "payload_too_large"


# ---------------------------------------------------------------------------
# Regression: legacy forged previews are sanitized on read.
# ---------------------------------------------------------------------------


def _insert_legacy(ctx, car_pub, sender_pub, receiver_pub, preview):
    app, _s, _c = ctx
    from kk.models import Car, Message, User, db

    with app.app_context():
        car = Car.query.filter_by(public_id=car_pub).first()
        s = User.query.filter_by(public_id=sender_pub).first()
        r = User.query.filter_by(public_id=receiver_pub).first()
        m = Message(
            sender_id=s.id,
            receiver_id=r.id,
            car_id=car.id,
            content="legacy",
            message_type="text",
            listing_preview=preview,
        )
        db.session.add(m)
        db.session.commit()
        return m.public_id


class TestLegacyRowsSanitizedOnRead:
    def test_history_rederives_from_listing(self, ctx, world):
        _insert_legacy(ctx, world["car"], world["buyer"], world["seller"], _forged(world["car"]))
        _a, _s, client = ctx
        r = client.get(f"/api/chat/{world['car']}/messages", headers=_auth(world["seller_tok"]))
        assert r.status_code == 200
        msgs = [m for m in r.get_json()["messages"] if m["content"] == "legacy"]
        assert len(msgs) == 1
        _assert_trusted(msgs[0]["listing_preview"], world["car"])
        assert "evil.example" not in r.get_data(as_text=True)

    def test_legacy_preview_for_nonpublic_listing_is_dropped(self, ctx, world):
        _insert_legacy(ctx, world["car"], world["buyer"], world["seller"], _forged(world["car"]))
        app, _s, _c = ctx
        from kk.models import Car, db

        with app.app_context():
            Car.query.filter_by(public_id=world["car"]).update({"status": "hidden"})
            db.session.commit()
        _a, _s2, client = ctx
        r = client.get(f"/api/chat/{world['car']}/messages", headers=_auth(world["seller_tok"]))
        assert r.status_code == 200
        msgs = [m for m in r.get_json()["messages"] if m["content"] == "legacy"]
        assert msgs[0]["listing_preview"] is None
        assert "evil.example" not in r.get_data(as_text=True)

    def test_legacy_preview_without_listing_is_dropped(self, ctx, world):
        # Listing row removed (Message.car_id SET NULL) -> nothing to derive from.
        from kk.chat_payload import sanitize_stored_listing_preview

        assert sanitize_stored_listing_preview(_forged("x"), None) is None
        assert sanitize_stored_listing_preview("garbage", None) is None

    def test_reply_preview_text_unaffected(self, ctx, world):
        mid = _insert_legacy(ctx, world["car"], world["buyer"], world["seller"], _forged(world["car"]))
        r = _post_json_reply(ctx, world, mid)
        assert r.status_code == 201, r.data
        assert r.get_json()["message"]["reply_to_message"]["content"] in ("legacy",)


def _post_json_reply(ctx, world, reply_id):
    _a, _s, client = ctx
    return client.post(
        f"/api/chat/{world['car']}/send",
        headers=_auth(world["seller_tok"]),
        json={"content": "re", "receiver_id": world["buyer"], "reply_to_message_id": reply_id},
    )
