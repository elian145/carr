"""M-07 (chat-attachment follow-up): per-file size caps for chat uploads.

PRODUCTION_AUDIT.md M-07 found ``MAX_CONTENT_LENGTH`` defaults to a generous
250MB, applied as a single global request-body cap shared by every route.
Investigation found this global cap intentional (it exists to support
grouped multi-attachment chat messages) and correctly enforced by Werkzeug,
but chat's single-file endpoints (``send_image``/``send_video``/
``send_audio``) and the grouped endpoint (``send_media_group``) had no
per-file size cap of their own -- a single attachment could legitimately be
up to 250MB, unlike every other upload endpoint in this app (listing
images/videos, profile pictures, dealer photos), which already have a
stricter per-file cap on top of the global one.

This suite covers the "Option B" remediation: new per-file caps added to
``kk/routes/chat.py`` --

    image = 8MB   (kk.routes.chat._CHAT_IMAGE_MAX_MB)
    video = 100MB (kk.routes.chat._CHAT_VIDEO_MAX_MB)
    audio = 10MB  (kk.routes.chat._CHAT_AUDIO_MAX_MB)

-- and the accompanying ``RequestEntityTooLarge`` -> 413 handling that was
already correct in ``send_media_group_message`` but missing from the three
single-attachment endpoints (they previously fell through to a generic 500).

Sections:
    A. Pure unit tests for the new helpers (no Flask app; deterministic
       byte-exact boundary checks without allocating real multi-MB buffers)
    B. Single-endpoint (image/video/audio) oversized/normal, via HTTP
    C. Grouped-media (send_media_group) per-file validation, all-or-nothing
       pre-flight, no partial persistence, existing 10-file cap preserved
    D. 413 handling for RequestEntityTooLarge (the *global* MAX_CONTENT_LENGTH
       body cap, a different mechanism from the new per-file checks above)
       across all four attachment endpoints

No real >1MB file is ever allocated: oversized-file scenarios are produced
by monkeypatching ``kk.routes.chat._file_size_bytes`` to report a controlled
fake size for a specific (tiny, real) uploaded file, so the actual test
payloads stay tiny while the code under test genuinely believes the file is
oversized.
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
from werkzeug.datastructures import FileStorage

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

import kk.routes.chat as chat_module

# ---------------------------------------------------------------------------
# Shared fixture bytes -- same real container-magic-byte convention already
# used by kk/tests/test_be18_chat_send_idempotency.py and
# kk/tests/test_h03_upload_content_validation.py (H-03: chat attachments are
# magic-byte-sniffed, so placeholder bytes must pass `sniff_bytes()`).
# ---------------------------------------------------------------------------
_FAKE_JPEG_BYTES = b"\xff\xd8\xff\xe0fake-jpeg-bytes"
_FAKE_MP4_BYTES = b"\x00\x00\x00\x18ftypmp42fake-mp4-bytes"
_FAKE_M4A_BYTES = b"\x00\x00\x00\x18ftypM4A fake-m4a-bytes"

FAKE_CHAT_BUCKET_CONFIG = {
    "R2_ACCOUNT_ID": "test-account-id",
    "R2_CHAT_BUCKET_NAME": "carzo-chat-media-test",
    "R2_CHAT_ACCESS_KEY_ID": "test-chat-access-key",
    "R2_CHAT_SECRET_ACCESS_KEY": "test-chat-secret-key",
}


def _fake_presign_get(*, key: str, expires_in: int = 600, timeout: float = 30) -> str:
    return f"https://fake-r2-presigned.example.test/{key}?X-Amz-Expires={expires_in}&sig=test"


# ===========================================================================
# A. Pure unit tests -- no Flask app, no DB, no real large buffers.
# ===========================================================================


def _fake_file(name: str, content: bytes = b"x") -> FileStorage:
    return FileStorage(stream=io.BytesIO(content), filename=name)


class TestChatAttachmentMaxMbConstants:
    """Pin the exact values requested for M-07 Option B."""

    def test_image_limit_is_8mb(self):
        assert chat_module._CHAT_IMAGE_MAX_MB == 8

    def test_video_limit_is_100mb(self):
        assert chat_module._CHAT_VIDEO_MAX_MB == 100

    def test_audio_limit_is_10mb(self):
        assert chat_module._CHAT_AUDIO_MAX_MB == 10


class TestChatAttachmentSizeErrorUnit:
    """Deterministic boundary behavior via a monkeypatched _file_size_bytes,
    so exact-boundary bytes never require allocating a real 8MB/100MB/10MB
    buffer."""

    @pytest.mark.parametrize(
        "filename,max_mb",
        [
            ("photo.jpg", chat_module._CHAT_IMAGE_MAX_MB),
            ("clip.mp4", chat_module._CHAT_VIDEO_MAX_MB),
            ("voice.m4a", chat_module._CHAT_AUDIO_MAX_MB),
        ],
    )
    def test_exactly_at_cap_is_accepted(self, monkeypatch, filename, max_mb):
        monkeypatch.setattr(
            chat_module, "_file_size_bytes", lambda f: max_mb * 1024 * 1024
        )
        assert chat_module._chat_attachment_size_error(_fake_file(filename)) is None

    @pytest.mark.parametrize(
        "filename,max_mb,label",
        [
            ("photo.jpg", chat_module._CHAT_IMAGE_MAX_MB, "Image"),
            ("clip.mp4", chat_module._CHAT_VIDEO_MAX_MB, "Video"),
            ("voice.m4a", chat_module._CHAT_AUDIO_MAX_MB, "Audio file"),
        ],
    )
    def test_one_byte_over_cap_is_rejected(self, monkeypatch, filename, max_mb, label):
        monkeypatch.setattr(
            chat_module, "_file_size_bytes", lambda f: max_mb * 1024 * 1024 + 1
        )
        result = chat_module._chat_attachment_size_error(_fake_file(filename))
        assert result is not None
        body, status = result
        assert status == 413
        assert body == {"message": f"{label} is too large. Maximum size is {max_mb}MB."}
        # No filesystem paths, exception text, or internal storage details leaked.
        assert "chat_uploads" not in body["message"]
        assert "chat_videos" not in body["message"]
        assert "chat_audio" not in body["message"]
        assert "Traceback" not in body["message"]

    def test_one_byte_under_cap_is_accepted(self, monkeypatch):
        monkeypatch.setattr(
            chat_module,
            "_file_size_bytes",
            lambda f: chat_module._CHAT_IMAGE_MAX_MB * 1024 * 1024 - 1,
        )
        assert chat_module._chat_attachment_size_error(_fake_file("photo.jpg")) is None

    def test_unrecognized_extension_is_not_size_checked(self, monkeypatch):
        # Unknown extensions are left entirely to the existing extension
        # allow-list checks at each call site (unchanged "Unsupported ...
        # format" behavior) -- the new size helper must not itself accept
        # or reject them.
        monkeypatch.setattr(chat_module, "_file_size_bytes", lambda f: 10**9)
        assert chat_module._chat_attachment_size_error(_fake_file("archive.zip")) is None

    def test_small_real_file_never_rejected_for_any_type(self):
        # No mocking at all: genuinely tiny real fixtures must always pass.
        assert chat_module._chat_attachment_size_error(
            _fake_file("a.jpg", _FAKE_JPEG_BYTES)
        ) is None
        assert chat_module._chat_attachment_size_error(
            _fake_file("a.mp4", _FAKE_MP4_BYTES)
        ) is None
        assert chat_module._chat_attachment_size_error(
            _fake_file("a.m4a", _FAKE_M4A_BYTES)
        ) is None

    def test_size_check_does_not_disturb_stream_position(self):
        """The size probe must leave the stream at its original position so
        the subsequent magic-byte sniff / upload still reads from the start."""
        f = _fake_file("a.jpg", _FAKE_JPEG_BYTES)
        f.seek(0)
        assert chat_module._chat_attachment_size_error(f) is None
        assert f.tell() == 0
        assert f.read() == _FAKE_JPEG_BYTES


# ===========================================================================
# Flask app fixtures (module-scoped, R2 mocked -- no real network calls, no
# real files written to kk/static/chat_*).
# ===========================================================================


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_m07_chat_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "m07_chat.db")

    from kk.app_factory import create_app

    app, socketio, *_ = create_app()
    app.config.update(FAKE_CHAT_BUCKET_CONFIG)
    from kk.models import Car, Message, User, db

    with app.app_context():
        db.drop_all()
        db.create_all()

    yield app, socketio, app.test_client(), db, User, Car, Message

    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    tmp.cleanup()


@pytest.fixture
def client(app_ctx):
    return app_ctx[2]


@pytest.fixture(autouse=True)
def _mock_r2_chat_ops():
    """No real R2 network calls anywhere in this file. Also lets tests
    assert on `put_mock.call_count` to prove no partial persistence."""
    with patch("kk.r2_ops.r2_chat_put_bytes") as put_mock, patch(
        "kk.r2_ops.r2_presign_get", side_effect=_fake_presign_get
    ) as presign_mock:
        yield put_mock, presign_mock


def _unique_phone() -> str:
    return f"078{uuid.uuid4().int % 10**8:08d}"


def _make_user(app_ctx, *, username: str, phone: str) -> str:
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
    username = f"m07_seller_{uuid.uuid4().hex[:8]}"
    public_id = _make_user(app_ctx, username=username, phone=_unique_phone())
    return username, public_id


@pytest.fixture(scope="module")
def buyer_ctx(app_ctx):
    username = f"m07_buyer_{uuid.uuid4().hex[:8]}"
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
    app, _socketio, _client, db, _User, _Car, Message = app_ctx
    with app.app_context():
        return Message.query.count()


@pytest.fixture(scope="module")
def thread_ctx(app_ctx, seller_ctx, buyer_ctx):
    """One car + an established message thread (seller may reply to buyer)."""
    module_client = app_ctx[2]
    seller_username, seller_public = seller_ctx
    buyer_username, buyer_public = buyer_ctx
    car_public = _make_car(app_ctx, seller_public)
    seller_token = _login(module_client, seller_username)
    buyer_token = _login(module_client, buyer_username)
    r = module_client.post(
        f"/api/chat/{car_public}/send",
        headers=_auth(buyer_token),
        json={"content": "hi", "receiver_id": seller_public},
    )
    assert r.status_code == 201, r.data
    return car_public, seller_token, buyer_public


@pytest.fixture
def size_override(monkeypatch):
    """Patch _file_size_bytes so specific filenames report a controlled fake
    size (to simulate an oversized upload without allocating a real
    multi-MB buffer); any filename not in the override dict falls through
    to the real implementation (its genuine, tiny, actual size)."""
    original = chat_module._file_size_bytes
    overrides: dict[str, int] = {}

    def _fake(file_storage):
        name = getattr(file_storage, "filename", None)
        if name in overrides:
            return overrides[name]
        return original(file_storage)

    monkeypatch.setattr(chat_module, "_file_size_bytes", _fake)
    return overrides


def _oversized(max_mb: int) -> int:
    return max_mb * 1024 * 1024 + 1


# ===========================================================================
# B. Single-endpoint (image/video/audio) oversized/normal, via HTTP.
# ===========================================================================


class TestSendImageSizeLimit:
    def test_oversized_image_is_rejected(self, client, thread_ctx, size_override):
        car_public, seller_token, buyer_public = thread_ctx
        size_override["huge.jpg"] = _oversized(chat_module._CHAT_IMAGE_MAX_MB)
        resp = client.post(
            f"/api/chat/{car_public}/send_image",
            headers=_auth(seller_token),
            data={
                "receiver_id": buyer_public,
                "file": (io.BytesIO(_FAKE_JPEG_BYTES), "huge.jpg"),
            },
            content_type="multipart/form-data",
        )
        assert resp.status_code == 413, resp.data
        assert resp.get_json()["message"] == (
            f"Image is too large. Maximum size is {chat_module._CHAT_IMAGE_MAX_MB}MB."
        )

    def test_normal_image_succeeds(self, client, thread_ctx):
        car_public, seller_token, buyer_public = thread_ctx
        resp = client.post(
            f"/api/chat/{car_public}/send_image",
            headers=_auth(seller_token),
            data={
                "receiver_id": buyer_public,
                "file": (io.BytesIO(_FAKE_JPEG_BYTES), "normal.jpg"),
            },
            content_type="multipart/form-data",
        )
        assert resp.status_code == 201, resp.data
        assert resp.get_json()["message"]["message_type"] == "image"


class TestSendVideoSizeLimit:
    def test_oversized_video_is_rejected(self, client, thread_ctx, size_override):
        car_public, seller_token, buyer_public = thread_ctx
        size_override["huge.mp4"] = _oversized(chat_module._CHAT_VIDEO_MAX_MB)
        resp = client.post(
            f"/api/chat/{car_public}/send_video",
            headers=_auth(seller_token),
            data={
                "receiver_id": buyer_public,
                "file": (io.BytesIO(_FAKE_MP4_BYTES), "huge.mp4"),
            },
            content_type="multipart/form-data",
        )
        assert resp.status_code == 413, resp.data
        assert resp.get_json()["message"] == (
            f"Video is too large. Maximum size is {chat_module._CHAT_VIDEO_MAX_MB}MB."
        )

    def test_normal_video_succeeds(self, client, thread_ctx):
        car_public, seller_token, buyer_public = thread_ctx
        resp = client.post(
            f"/api/chat/{car_public}/send_video",
            headers=_auth(seller_token),
            data={
                "receiver_id": buyer_public,
                "file": (io.BytesIO(_FAKE_MP4_BYTES), "normal.mp4"),
            },
            content_type="multipart/form-data",
        )
        assert resp.status_code == 201, resp.data
        assert resp.get_json()["message"]["message_type"] == "video"


class TestSendAudioSizeLimit:
    def test_oversized_audio_is_rejected(self, client, thread_ctx, size_override):
        car_public, seller_token, buyer_public = thread_ctx
        size_override["huge.m4a"] = _oversized(chat_module._CHAT_AUDIO_MAX_MB)
        resp = client.post(
            f"/api/chat/{car_public}/send_audio",
            headers=_auth(seller_token),
            data={
                "receiver_id": buyer_public,
                "file": (io.BytesIO(_FAKE_M4A_BYTES), "huge.m4a"),
            },
            content_type="multipart/form-data",
        )
        assert resp.status_code == 413, resp.data
        assert resp.get_json()["message"] == (
            f"Audio file is too large. Maximum size is {chat_module._CHAT_AUDIO_MAX_MB}MB."
        )

    def test_normal_audio_succeeds(self, client, thread_ctx):
        car_public, seller_token, buyer_public = thread_ctx
        resp = client.post(
            f"/api/chat/{car_public}/send_audio",
            headers=_auth(seller_token),
            data={
                "receiver_id": buyer_public,
                "file": (io.BytesIO(_FAKE_M4A_BYTES), "normal.m4a"),
            },
            content_type="multipart/form-data",
        )
        assert resp.status_code == 201, resp.data
        assert resp.get_json()["message"]["message_type"] == "audio"


# ===========================================================================
# C. Grouped-media (send_media_group): per-file validation, all-or-nothing
#    pre-flight, no partial persistence, existing 10-file cap preserved.
# ===========================================================================


class TestSendMediaGroupSizeLimit:
    def test_oversized_image_in_group_rejects_whole_request(
        self, client, thread_ctx, size_override, _mock_r2_chat_ops, app_ctx
    ):
        car_public, seller_token, buyer_public = thread_ctx
        put_mock, _presign_mock = _mock_r2_chat_ops
        put_mock.reset_mock()
        before = _message_count(app_ctx)
        size_override["huge.jpg"] = _oversized(chat_module._CHAT_IMAGE_MAX_MB)

        resp = client.post(
            f"/api/chat/{car_public}/send_media_group",
            headers=_auth(seller_token),
            data={
                "receiver_id": buyer_public,
                "attachments": [
                    (io.BytesIO(_FAKE_JPEG_BYTES), "good1.jpg"),
                    (io.BytesIO(_FAKE_JPEG_BYTES), "huge.jpg"),
                ],
            },
            content_type="multipart/form-data",
        )
        assert resp.status_code == 413, resp.data
        assert resp.get_json()["message"] == (
            f"Image is too large. Maximum size is {chat_module._CHAT_IMAGE_MAX_MB}MB."
        )
        # No partial persistence: neither file was ever uploaded, and no
        # Message row was created for the rejected request.
        assert put_mock.call_count == 0
        assert _message_count(app_ctx) == before

    def test_oversized_video_in_group_rejects_whole_request(
        self, client, thread_ctx, size_override, _mock_r2_chat_ops, app_ctx
    ):
        car_public, seller_token, buyer_public = thread_ctx
        put_mock, _presign_mock = _mock_r2_chat_ops
        put_mock.reset_mock()
        before = _message_count(app_ctx)
        size_override["huge.mp4"] = _oversized(chat_module._CHAT_VIDEO_MAX_MB)

        resp = client.post(
            f"/api/chat/{car_public}/send_media_group",
            headers=_auth(seller_token),
            data={
                "receiver_id": buyer_public,
                "attachments": [
                    (io.BytesIO(_FAKE_JPEG_BYTES), "good1.jpg"),
                    (io.BytesIO(_FAKE_MP4_BYTES), "huge.mp4"),
                ],
            },
            content_type="multipart/form-data",
        )
        assert resp.status_code == 413, resp.data
        assert resp.get_json()["message"] == (
            f"Video is too large. Maximum size is {chat_module._CHAT_VIDEO_MAX_MB}MB."
        )
        assert put_mock.call_count == 0
        assert _message_count(app_ctx) == before

    def test_oversized_audio_in_group_rejects_whole_request(
        self, client, thread_ctx, size_override, _mock_r2_chat_ops, app_ctx
    ):
        car_public, seller_token, buyer_public = thread_ctx
        put_mock, _presign_mock = _mock_r2_chat_ops
        put_mock.reset_mock()
        before = _message_count(app_ctx)
        size_override["huge.m4a"] = _oversized(chat_module._CHAT_AUDIO_MAX_MB)

        resp = client.post(
            f"/api/chat/{car_public}/send_media_group",
            headers=_auth(seller_token),
            data={
                "receiver_id": buyer_public,
                "attachments": [
                    (io.BytesIO(_FAKE_JPEG_BYTES), "good1.jpg"),
                    (io.BytesIO(_FAKE_M4A_BYTES), "huge.m4a"),
                ],
            },
            content_type="multipart/form-data",
        )
        assert resp.status_code == 413, resp.data
        assert resp.get_json()["message"] == (
            f"Audio file is too large. Maximum size is {chat_module._CHAT_AUDIO_MAX_MB}MB."
        )
        assert put_mock.call_count == 0
        assert _message_count(app_ctx) == before

    def test_oversized_last_file_still_blocks_earlier_valid_ones_from_persisting(
        self, client, thread_ctx, size_override, _mock_r2_chat_ops, app_ctx
    ):
        """The oversized file is deliberately LAST in the list: proves the
        pre-flight pass validates every file before uploading ANY of them,
        not just files before the first oversized one."""
        car_public, seller_token, buyer_public = thread_ctx
        put_mock, _presign_mock = _mock_r2_chat_ops
        put_mock.reset_mock()
        before = _message_count(app_ctx)
        size_override["huge.mp4"] = _oversized(chat_module._CHAT_VIDEO_MAX_MB)

        resp = client.post(
            f"/api/chat/{car_public}/send_media_group",
            headers=_auth(seller_token),
            data={
                "receiver_id": buyer_public,
                "attachments": [
                    (io.BytesIO(_FAKE_JPEG_BYTES), "good1.jpg"),
                    (io.BytesIO(_FAKE_JPEG_BYTES), "good2.jpg"),
                    (io.BytesIO(_FAKE_M4A_BYTES), "good3.m4a"),
                    (io.BytesIO(_FAKE_MP4_BYTES), "huge.mp4"),
                ],
            },
            content_type="multipart/form-data",
        )
        assert resp.status_code == 413, resp.data
        # Zero uploads -- not "3 succeeded, 1 failed".
        assert put_mock.call_count == 0
        assert _message_count(app_ctx) == before

    def test_mixed_normal_files_succeed(self, client, thread_ctx):
        car_public, seller_token, buyer_public = thread_ctx
        resp = client.post(
            f"/api/chat/{car_public}/send_media_group",
            headers=_auth(seller_token),
            data={
                "receiver_id": buyer_public,
                "attachments": [
                    (io.BytesIO(_FAKE_JPEG_BYTES), "a.jpg"),
                    (io.BytesIO(_FAKE_MP4_BYTES), "b.mp4"),
                    (io.BytesIO(_FAKE_M4A_BYTES), "c.m4a"),
                ],
            },
            content_type="multipart/form-data",
        )
        assert resp.status_code == 201, resp.data
        body = resp.get_json()["message"]
        assert body["message_type"] == "media_group"
        assert len(body["attachments"]) == 3

    def test_existing_ten_file_cap_still_enforced(self, client, thread_ctx):
        car_public, seller_token, buyer_public = thread_ctx
        resp = client.post(
            f"/api/chat/{car_public}/send_media_group",
            headers=_auth(seller_token),
            data={
                "receiver_id": buyer_public,
                "attachments": [
                    (io.BytesIO(_FAKE_JPEG_BYTES), f"a{i}.jpg") for i in range(11)
                ],
            },
            content_type="multipart/form-data",
        )
        assert resp.status_code == 400, resp.data
        assert resp.get_json()["message"] == "You can send up to 10 attachments at once"


# ===========================================================================
# D. 413 handling for the *global* MAX_CONTENT_LENGTH request-body cap
#    (Werkzeug-level RequestEntityTooLarge) -- a different mechanism from
#    the new per-file checks above. Uses a tiny MAX_CONTENT_LENGTH on a
#    throwaway app config override so any real (tiny) multipart body
#    already exceeds it -- no large buffers needed here either.
# ===========================================================================


class TestRequestEntityTooLargeHandling:
    @pytest.fixture(autouse=True)
    def _tiny_body_limit(self, app_ctx):
        app = app_ctx[0]
        original = app.config.get("MAX_CONTENT_LENGTH")
        app.config["MAX_CONTENT_LENGTH"] = 10  # bytes -- any real multipart body exceeds this
        yield
        app.config["MAX_CONTENT_LENGTH"] = original

    def test_send_image_returns_413_not_500(self, client, thread_ctx):
        car_public, seller_token, buyer_public = thread_ctx
        resp = client.post(
            f"/api/chat/{car_public}/send_image",
            headers=_auth(seller_token),
            data={
                "receiver_id": buyer_public,
                "file": (io.BytesIO(_FAKE_JPEG_BYTES), "a.jpg"),
            },
            content_type="multipart/form-data",
        )
        assert resp.status_code == 413, resp.data
        assert "too large" in resp.get_json()["message"].lower()

    def test_send_video_returns_413_not_500(self, client, thread_ctx):
        car_public, seller_token, buyer_public = thread_ctx
        resp = client.post(
            f"/api/chat/{car_public}/send_video",
            headers=_auth(seller_token),
            data={
                "receiver_id": buyer_public,
                "file": (io.BytesIO(_FAKE_MP4_BYTES), "a.mp4"),
            },
            content_type="multipart/form-data",
        )
        assert resp.status_code == 413, resp.data
        assert "too large" in resp.get_json()["message"].lower()

    def test_send_audio_returns_413_not_500(self, client, thread_ctx):
        car_public, seller_token, buyer_public = thread_ctx
        resp = client.post(
            f"/api/chat/{car_public}/send_audio",
            headers=_auth(seller_token),
            data={
                "receiver_id": buyer_public,
                "file": (io.BytesIO(_FAKE_M4A_BYTES), "a.m4a"),
            },
            content_type="multipart/form-data",
        )
        assert resp.status_code == 413, resp.data
        assert "too large" in resp.get_json()["message"].lower()

    def test_send_media_group_still_returns_413(self, client, thread_ctx):
        """Regression guard: this endpoint's RequestEntityTooLarge handling
        already existed before M-07 Option B -- must remain correct."""
        car_public, seller_token, buyer_public = thread_ctx
        resp = client.post(
            f"/api/chat/{car_public}/send_media_group",
            headers=_auth(seller_token),
            data={
                "receiver_id": buyer_public,
                "attachments": [(io.BytesIO(_FAKE_JPEG_BYTES), "a.jpg")],
            },
            content_type="multipart/form-data",
        )
        assert resp.status_code == 413, resp.data
        assert "too large" in resp.get_json()["message"].lower()
