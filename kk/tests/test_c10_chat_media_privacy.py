"""C-10: private chat-media storage with scoped, short-lived presigned URLs.

Chat media (image/video/audio/media_group) must be stored in the PRIVATE
``R2_CHAT_*`` bucket as a bare object key — never a public URL — and only
ever resolved to a short-lived presigned GET URL for a caller who has
already passed the pre-existing chat participant-authorization check
(``get_messages`` / ``_message_for_user`` in ``kk/routes/chat.py``).

No real Cloudflare credentials are used anywhere in this file. All R2
network/subprocess calls are mocked:
  - ``kk.r2_ops.r2_chat_put_bytes`` (upload)
  - ``kk.r2_ops.r2_presign_get`` (download URL)
  - ``kk.r2_ops._run_r2_op`` (lowest-level subprocess boundary, for the
    r2_ops-unit-level tests)

Sections:
  A. kk/config.py — chat R2 config validation (unit, no Flask app needed)
  B. kk/r2_ops.py — bucket/credential selection, presign_get shape (unit)
  C. tools/r2_s3_op.py — the real subprocess script's presign_get op,
     exercised directly with dummy (non-network) credentials
  D. kk/models.py resolver helpers — pass-through vs presign, fail-closed
  E. kk/routes/chat.py upload path — private bucket only, bare key stored
  F. End-to-end authorization + security (real Flask app + sqlite)
  G. Negative control — proves the authorization test actually catches a
     bypass (bypass is applied and reverted within the same test; nothing
     is left changed in the working tree)
  H. Fix regression tests (final security review): edit_chat_message()
     positional+type attachment matching, and fail-closed on fully-absent
     R2_CHAT_* in production (the latter is covered in section A above).
"""

from __future__ import annotations

import io
import json
import os
import subprocess
import sys
import tempfile
import uuid
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))


FAKE_CHAT_BUCKET_CONFIG = {
    "R2_ACCOUNT_ID": "test-account-id",
    "R2_CHAT_BUCKET_NAME": "carzo-chat-media-test",
    "R2_CHAT_ACCESS_KEY_ID": "test-chat-access-key",
    "R2_CHAT_SECRET_ACCESS_KEY": "test-chat-secret-key",
}

# Distinct sentinel so tests can assert the (unrelated) public listing-media
# config is never touched/used for chat uploads.
SENTINEL_PUBLIC_CONFIG = {
    "R2_BUCKET_NAME": "carzo-listing-media-public",
    "R2_ACCESS_KEY_ID": "listing-access-key",
    "R2_SECRET_ACCESS_KEY": "listing-secret-key",
    "R2_PUBLIC_URL": "https://pub-sentinel-should-never-appear.example.test",
}


def _fake_presign_get(*, key: str, expires_in: int = 600, timeout: float = 30) -> str:
    return f"https://fake-r2-presigned.example.test/{key}?X-Amz-Expires={expires_in}&sig=test"


# ---------------------------------------------------------------------------
# A. kk/config.py — chat R2 config validation
# ---------------------------------------------------------------------------


class TestChatMediaConfigValidation:
    def setup_method(self):
        self._saved = {
            k: os.environ.get(k)
            for k in (
                "R2_ACCOUNT_ID",
                "R2_CHAT_BUCKET_NAME",
                "R2_CHAT_ACCESS_KEY_ID",
                "R2_CHAT_SECRET_ACCESS_KEY",
                "ALLOW_EPHEMERAL_UPLOADS",
            )
        }
        for k in self._saved:
            os.environ.pop(k, None)

    def teardown_method(self):
        for k, v in self._saved.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v

    def test_storage_mode_disk_when_fully_unset(self):
        from kk.config import chat_media_storage_mode

        assert chat_media_storage_mode() == "disk"

    def test_storage_mode_r2_private_when_fully_set(self):
        from kk.config import chat_media_storage_mode

        os.environ.update(FAKE_CHAT_BUCKET_CONFIG)
        assert chat_media_storage_mode() == "r2_private"

    def test_storage_mode_incomplete_when_partially_set(self):
        from kk.config import chat_media_storage_mode

        os.environ["R2_CHAT_BUCKET_NAME"] = "some-bucket"
        # access key / secret / account id intentionally left unset
        assert chat_media_storage_mode() == "r2_chat_incomplete"

    def test_validate_chat_media_persistence_raises_in_production_when_partial(self):
        from kk.config import validate_chat_media_persistence

        os.environ["R2_CHAT_BUCKET_NAME"] = "some-bucket"
        with pytest.raises(RuntimeError, match="Chat-media R2 configuration is incomplete"):
            validate_chat_media_persistence("production")

    def test_validate_chat_media_persistence_ok_when_fully_configured(self):
        from kk.config import validate_chat_media_persistence

        os.environ.update(FAKE_CHAT_BUCKET_CONFIG)
        validate_chat_media_persistence("production")  # must not raise

    def test_validate_chat_media_persistence_raises_in_production_when_fully_absent(self):
        """Fully-absent R2_CHAT_* must ALSO fail closed in production: the
        local-disk fallback it would silently use is unauthenticated, which
        is exactly what C-10 exists to prevent."""
        from kk.config import validate_chat_media_persistence

        with pytest.raises(RuntimeError, match="Chat-media R2 configuration is missing"):
            validate_chat_media_persistence("production")

    def test_validate_chat_media_persistence_skipped_outside_production(self):
        from kk.config import validate_chat_media_persistence

        os.environ["R2_CHAT_BUCKET_NAME"] = "some-bucket"  # partial
        validate_chat_media_persistence("development")  # must not raise
        validate_chat_media_persistence("testing")  # must not raise

    def test_validate_chat_media_persistence_escape_hatch(self):
        from kk.config import validate_chat_media_persistence

        os.environ["R2_CHAT_BUCKET_NAME"] = "some-bucket"  # partial
        os.environ["ALLOW_EPHEMERAL_UPLOADS"] = "1"
        validate_chat_media_persistence("production")  # must not raise


# ---------------------------------------------------------------------------
# B. kk/r2_ops.py — bucket/credential selection + presign shape
# ---------------------------------------------------------------------------


class TestR2OpsChatBucketSelection:
    def _app(self):
        app = MagicMock()
        app.config = {**FAKE_CHAT_BUCKET_CONFIG, **SENTINEL_PUBLIC_CONFIG}
        return app

    def test_r2_chat_put_bytes_uses_chat_bucket_not_public_bucket(self, monkeypatch):
        from kk import r2_ops

        monkeypatch.setattr(r2_ops, "current_app", self._app())
        captured = {}

        def _fake_run(payload, *, timeout):
            captured.update(payload)
            return {"ok": True}

        monkeypatch.setattr(r2_ops, "_run_r2_op", _fake_run)
        r2_ops.r2_chat_put_bytes(key="chat_uploads/abc.jpg", body=b"data", content_type="image/jpeg")

        assert captured["bucket"] == FAKE_CHAT_BUCKET_CONFIG["R2_CHAT_BUCKET_NAME"]
        assert captured["bucket"] != SENTINEL_PUBLIC_CONFIG["R2_BUCKET_NAME"]
        assert captured["access_key"] == FAKE_CHAT_BUCKET_CONFIG["R2_CHAT_ACCESS_KEY_ID"]
        assert captured["op"] == "put_object"

    def test_r2_presign_get_uses_chat_bucket_and_get_op(self, monkeypatch):
        from kk import r2_ops

        monkeypatch.setattr(r2_ops, "current_app", self._app())
        captured = {}

        def _fake_run(payload, *, timeout):
            captured.update(payload)
            return {"ok": True, "download_url": "https://example.test/signed"}

        monkeypatch.setattr(r2_ops, "_run_r2_op", _fake_run)
        url = r2_ops.r2_presign_get(key="chat_uploads/abc.jpg")

        assert captured["bucket"] == FAKE_CHAT_BUCKET_CONFIG["R2_CHAT_BUCKET_NAME"]
        assert captured["op"] == "presign_get"
        assert url == "https://example.test/signed"

    def test_r2_presign_get_default_expiry_is_bounded_short_lived(self, monkeypatch):
        """C-10 requires a short, bounded default expiry (~10 minutes)."""
        from kk import r2_ops

        monkeypatch.setattr(r2_ops, "current_app", self._app())
        captured = {}

        def _fake_run(payload, *, timeout):
            captured.update(payload)
            return {"ok": True, "download_url": "https://example.test/signed"}

        monkeypatch.setattr(r2_ops, "_run_r2_op", _fake_run)
        r2_ops.r2_presign_get(key="chat_uploads/abc.jpg")

        assert captured["expires_in"] == r2_ops.CHAT_PRESIGN_GET_DEFAULT_EXPIRES_SECONDS
        # Bounded: short-lived (<= 15 min) and not absurdly short (>= 1 min).
        assert 60 <= captured["expires_in"] <= 900

    def test_r2_presign_get_raises_on_empty_download_url(self, monkeypatch):
        from kk import r2_ops

        monkeypatch.setattr(r2_ops, "current_app", self._app())
        monkeypatch.setattr(r2_ops, "_run_r2_op", lambda payload, *, timeout: {"ok": True, "download_url": ""})

        with pytest.raises(RuntimeError):
            r2_ops.r2_presign_get(key="chat_uploads/abc.jpg")

    def test_r2_chat_configured_from_config_true_only_when_all_four_present(self):
        from kk.r2_ops import r2_chat_configured_from_config

        assert r2_chat_configured_from_config(FAKE_CHAT_BUCKET_CONFIG) is True
        incomplete = dict(FAKE_CHAT_BUCKET_CONFIG)
        incomplete.pop("R2_CHAT_SECRET_ACCESS_KEY")
        assert r2_chat_configured_from_config(incomplete) is False


# ---------------------------------------------------------------------------
# C. tools/r2_s3_op.py — real subprocess script, dummy (non-network) creds
# ---------------------------------------------------------------------------


class TestR2S3OpPresignGetScript:
    """Presigned URL generation is a local signing operation — boto3 needs
    no network access to produce one, so this exercises the REAL script
    (not a mock of it) with throwaway dummy credentials."""

    def _run_script(self, payload: dict) -> dict:
        script = str(_REPO_ROOT / "tools" / "r2_s3_op.py")
        proc = subprocess.run(
            [sys.executable, script],
            input=json.dumps(payload),
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert proc.stdout.strip(), proc.stderr
        return json.loads(proc.stdout)

    def test_presign_get_returns_get_object_url_containing_bucket_and_key(self):
        result = self._run_script(
            {
                "op": "presign_get",
                "account_id": "dummy-account",
                "bucket": "dummy-chat-bucket",
                "access_key": "AKIADUMMYDUMMYDUMMY",
                "secret_key": "dummysecretdummysecretdummysecretdummy1",
                "key": "chat_uploads/deadbeef.jpg",
                "expires_in": 600,
            }
        )
        assert result.get("ok") is True, result
        url = result["download_url"]
        assert "dummy-chat-bucket" in url
        assert "chat_uploads/deadbeef.jpg" in url
        # SigV4 presigned GET must carry an expiry and signature, and must
        # not be a PUT (no way to directly assert HTTP verb from the URL
        # alone, but a GET presign never includes a Content-Type param the
        # way our presign_put does).
        assert "X-Amz-Expires=600" in url
        assert "X-Amz-Signature=" in url

    def test_presign_put_still_works_unchanged(self):
        """Guard against accidentally breaking the existing listing-media
        presigned PUT while adding presign_get."""
        result = self._run_script(
            {
                "op": "presign_put",
                "account_id": "dummy-account",
                "bucket": "dummy-listing-bucket",
                "access_key": "AKIADUMMYDUMMYDUMMY",
                "secret_key": "dummysecretdummysecretdummysecretdummy1",
                "key": "car_photos/deadbeef.jpg",
                "content_type": "image/jpeg",
                "expires_in": 900,
            }
        )
        assert result.get("ok") is True, result
        assert "upload_url" in result
        assert "download_url" not in result


# ---------------------------------------------------------------------------
# D. kk/models.py resolver helpers
# ---------------------------------------------------------------------------


class TestResolveChatMediaRef:
    def test_none_and_empty_resolve_to_none(self):
        from kk.models import _resolve_chat_media_ref

        assert _resolve_chat_media_ref(None) is None
        assert _resolve_chat_media_ref("") is None
        assert _resolve_chat_media_ref("   ") is None

    def test_legacy_public_url_passes_through_unchanged(self):
        from kk.models import _resolve_chat_media_ref

        legacy = "https://pub-old.r2.dev/chat_uploads/legacy.jpg"
        assert _resolve_chat_media_ref(legacy) == legacy

    def test_local_static_fallback_path_passes_through_unchanged(self):
        from kk.models import _resolve_chat_media_ref

        local = "/static/chat_uploads/local.jpg"
        assert _resolve_chat_media_ref(local) == local

    def test_bare_object_key_is_presigned(self, monkeypatch):
        from kk import models, r2_ops

        monkeypatch.setattr(r2_ops, "r2_presign_get", _fake_presign_get)
        result = models._resolve_chat_media_ref("chat_uploads/new-key.jpg")
        assert result == _fake_presign_get(key="chat_uploads/new-key.jpg")
        assert result.startswith("https://fake-r2-presigned.example.test/chat_uploads/new-key.jpg")

    def test_presign_failure_fails_closed_returns_none(self, monkeypatch):
        """A storage hiccup must degrade gracefully (None), never raise out
        of message serialization."""
        from kk import models, r2_ops

        monkeypatch.setattr(r2_ops, "r2_presign_get", MagicMock(side_effect=RuntimeError("R2 unreachable")))
        result = models._resolve_chat_media_ref("chat_uploads/broken-key.jpg")
        assert result is None


class TestResolveChatAttachmentsList:
    def test_non_list_passes_through(self):
        from kk.models import _resolve_chat_attachments_list

        assert _resolve_chat_attachments_list(None) is None

    def test_resolves_each_item_and_adds_stable_key(self, monkeypatch):
        from kk import models, r2_ops

        monkeypatch.setattr(r2_ops, "r2_presign_get", _fake_presign_get)
        items = [
            {"type": "image", "url": "chat_uploads/a.jpg"},
            {"type": "video", "url": "chat_videos/b.mp4"},
        ]
        resolved = models._resolve_chat_attachments_list(items)
        assert len(resolved) == 2
        assert resolved[0]["url"].startswith("https://fake-r2-presigned.example.test/chat_uploads/a.jpg")
        assert resolved[0]["key"] == "chat_uploads/a.jpg"
        assert resolved[1]["key"] == "chat_videos/b.mp4"

    def test_drops_only_the_item_that_fails_to_resolve(self, monkeypatch):
        from kk import models, r2_ops

        def _flaky(*, key: str, expires_in: int = 600, timeout: float = 30):
            if "broken" in key:
                raise RuntimeError("boom")
            return _fake_presign_get(key=key, expires_in=expires_in)

        monkeypatch.setattr(r2_ops, "r2_presign_get", _flaky)
        items = [
            {"type": "image", "url": "chat_uploads/good.jpg"},
            {"type": "image", "url": "chat_uploads/broken.jpg"},
        ]
        resolved = models._resolve_chat_attachments_list(items)
        assert len(resolved) == 1
        assert "good.jpg" in resolved[0]["url"]


# ---------------------------------------------------------------------------
# E. kk/routes/chat.py upload path — private bucket only
# ---------------------------------------------------------------------------


class TestUploadChatAttachmentPrivateBucket:
    def _file(self, name="photo.jpg", content=b"fake-jpeg-bytes"):
        from werkzeug.datastructures import FileStorage

        return FileStorage(stream=io.BytesIO(content), filename=name)

    def test_uses_private_chat_bucket_and_returns_bare_key(self, monkeypatch):
        from kk import r2_ops
        from kk.routes import chat as chat_routes

        app = MagicMock()
        app.config = {**FAKE_CHAT_BUCKET_CONFIG, **SENTINEL_PUBLIC_CONFIG}
        monkeypatch.setattr(chat_routes, "current_app", app)

        put_mock = MagicMock()
        monkeypatch.setattr(r2_ops, "r2_chat_put_bytes", put_mock)

        key = chat_routes._upload_chat_attachment(
            self._file(),
            allowed_extensions=chat_routes._CHAT_IMAGE_EXTENSIONS,
            subdir="chat_uploads",
            content_types={".jpg": "image/jpeg"},
        )

        put_mock.assert_called_once()
        assert key.startswith("chat_uploads/")
        assert key.endswith(".jpg")
        # Never a URL — bare key only.
        assert not key.startswith("http://")
        assert not key.startswith("https://")
        assert not key.startswith("/")
        # Never the public sentinel value.
        assert SENTINEL_PUBLIC_CONFIG["R2_PUBLIC_URL"] not in key

    def test_never_calls_public_listing_upload_function(self, monkeypatch):
        """Chat uploads must go through r2_chat_put_bytes, never the
        listing-media r2_put_bytes."""
        from kk import r2_ops
        from kk.routes import chat as chat_routes

        app = MagicMock()
        app.config = {**FAKE_CHAT_BUCKET_CONFIG, **SENTINEL_PUBLIC_CONFIG}
        monkeypatch.setattr(chat_routes, "current_app", app)

        chat_put_mock = MagicMock()
        public_put_mock = MagicMock()
        monkeypatch.setattr(r2_ops, "r2_chat_put_bytes", chat_put_mock)
        monkeypatch.setattr(r2_ops, "r2_put_bytes", public_put_mock)

        chat_routes._upload_chat_attachment(
            self._file(),
            allowed_extensions=chat_routes._CHAT_IMAGE_EXTENSIONS,
            subdir="chat_uploads",
            content_types={".jpg": "image/jpeg"},
        )

        chat_put_mock.assert_called_once()
        public_put_mock.assert_not_called()

    def test_falls_back_to_local_disk_when_chat_bucket_not_configured(self, monkeypatch, tmp_path):
        """Existing pre-C-10 local-disk fallback must keep working for local
        dev environments that don't set R2_CHAT_*."""
        from kk.routes import chat as chat_routes

        app = MagicMock()
        app.config = dict(SENTINEL_PUBLIC_CONFIG)  # no R2_CHAT_* at all
        app.root_path = str(tmp_path)
        monkeypatch.setattr(chat_routes, "current_app", app)

        key = chat_routes._upload_chat_attachment(
            self._file(),
            allowed_extensions=chat_routes._CHAT_IMAGE_EXTENSIONS,
            subdir="chat_uploads",
            content_types={".jpg": "image/jpeg"},
        )
        assert key.startswith("/static/chat_uploads/")


# ---------------------------------------------------------------------------
# F. End-to-end authorization + security (real Flask app + sqlite)
# ---------------------------------------------------------------------------


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_c10_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "c10.db")

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


@pytest.fixture
def _mock_r2_chat_ops():
    """End-to-end tests (sections F/G) run with R2 network/subprocess calls
    mocked — no real Cloudflare credentials are used or required.

    NOT module-autouse: sections A-E unit-test the real `r2_ops`/`chat.py`
    functions directly (including `r2_chat_put_bytes`/`r2_presign_get`
    themselves), so autouse-patching them file-wide would make those unit
    tests vacuously pass against a mock instead of the real implementation.
    """
    with patch("kk.r2_ops.r2_chat_put_bytes") as put_mock, patch(
        "kk.r2_ops.r2_presign_get", side_effect=_fake_presign_get
    ) as presign_mock:
        yield put_mock, presign_mock


def _unique_phone() -> str:
    return f"079{uuid.uuid4().int % 10**8:08d}"


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
    username = f"c10_seller_{uuid.uuid4().hex[:8]}"
    public_id = _make_user(app_ctx, username=username, phone=_unique_phone())
    return username, public_id


@pytest.fixture(scope="module")
def buyer_ctx(app_ctx):
    username = f"c10_buyer_{uuid.uuid4().hex[:8]}"
    public_id = _make_user(app_ctx, username=username, phone=_unique_phone())
    return username, public_id


@pytest.fixture(scope="module")
def stranger_ctx(app_ctx):
    username = f"c10_stranger_{uuid.uuid4().hex[:8]}"
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


def _send_image(client, token, car_id, receiver_id, content=b"fake-jpeg-bytes", name="photo.jpg"):
    return client.post(
        f"/api/chat/{car_id}/send_image",
        headers=_auth(token),
        data={"receiver_id": receiver_id, "file": (io.BytesIO(content), name)},
        content_type="multipart/form-data",
    )


def _get_messages(client, token, car_id):
    return client.get(f"/api/chat/{car_id}/messages", headers=_auth(token))


def _find_message(body: dict, message_public_id: str) -> dict | None:
    for m in body.get("messages", []):
        if m["id"] == message_public_id:
            return m
    return None


class TestC10EndToEndAuthorization:
    @pytest.fixture(autouse=True)
    def _auto_mock_r2(self, _mock_r2_chat_ops):
        """Scope the R2 mocks to this class only (see `_mock_r2_chat_ops`)."""
        return _mock_r2_chat_ops

    def test_sender_can_access_own_sent_media(self, app_ctx, client, seller_ctx, buyer_ctx):
        seller_username, seller_public = seller_ctx
        buyer_username, buyer_public = buyer_ctx
        car_public = _make_car(app_ctx, seller_public)
        seller_token = _login(client, seller_username)
        buyer_token = _login(client, buyer_username)

        # Establish a thread so the seller may message the buyer.
        client.post(
            f"/api/chat/{car_public}/send",
            headers=_auth(buyer_token),
            json={"content": "hi", "receiver_id": seller_public},
        )

        resp = _send_image(client, seller_token, car_public, buyer_public)
        assert resp.status_code == 201, resp.data
        message_id = resp.get_json()["message"]["id"]

        list_resp = _get_messages(client, seller_token, car_public)
        assert list_resp.status_code == 200
        msg = _find_message(list_resp.get_json(), message_id)
        assert msg is not None
        assert msg["attachment_url"].startswith("https://fake-r2-presigned.example.test/chat_uploads/")

    def test_receiver_can_access_media(self, app_ctx, client, seller_ctx, buyer_ctx):
        seller_username, seller_public = seller_ctx
        buyer_username, buyer_public = buyer_ctx
        car_public = _make_car(app_ctx, seller_public)
        seller_token = _login(client, seller_username)
        buyer_token = _login(client, buyer_username)

        client.post(
            f"/api/chat/{car_public}/send",
            headers=_auth(buyer_token),
            json={"content": "hi", "receiver_id": seller_public},
        )
        resp = _send_image(client, seller_token, car_public, buyer_public)
        message_id = resp.get_json()["message"]["id"]

        list_resp = _get_messages(client, buyer_token, car_public)
        msg = _find_message(list_resp.get_json(), message_id)
        assert msg is not None
        assert msg["attachment_url"] is not None
        assert msg["attachment_url"].startswith("https://fake-r2-presigned.example.test/")

    def test_unrelated_authenticated_user_cannot_access_media(
        self, app_ctx, client, seller_ctx, buyer_ctx, stranger_ctx, _mock_r2_chat_ops
    ):
        seller_username, seller_public = seller_ctx
        buyer_username, buyer_public = buyer_ctx
        stranger_username, _stranger_public = stranger_ctx
        car_public = _make_car(app_ctx, seller_public)
        seller_token = _login(client, seller_username)
        buyer_token = _login(client, buyer_username)
        stranger_token = _login(client, stranger_username)

        client.post(
            f"/api/chat/{car_public}/send",
            headers=_auth(buyer_token),
            json={"content": "hi", "receiver_id": seller_public},
        )
        resp = _send_image(client, seller_token, car_public, buyer_public)
        message_id = resp.get_json()["message"]["id"]

        _put_mock, presign_mock = _mock_r2_chat_ops
        presign_mock.reset_mock()

        list_resp = _get_messages(client, stranger_token, car_public)
        assert list_resp.status_code == 200
        msg = _find_message(list_resp.get_json(), message_id)
        # The message must not even appear in the unrelated user's list...
        assert msg is None
        # ...and authorization must be checked BEFORE presigning: the
        # unrelated user's request must never trigger a presign call at all.
        presign_mock.assert_not_called()

    def test_unauthenticated_user_cannot_obtain_a_presigned_url(self, app_ctx, client, seller_ctx, buyer_ctx):
        seller_username, seller_public = seller_ctx
        buyer_username, buyer_public = buyer_ctx
        car_public = _make_car(app_ctx, seller_public)
        seller_token = _login(client, seller_username)
        buyer_token = _login(client, buyer_username)

        client.post(
            f"/api/chat/{car_public}/send",
            headers=_auth(buyer_token),
            json={"content": "hi", "receiver_id": seller_public},
        )
        _send_image(client, seller_token, car_public, buyer_public)

        no_auth_resp = client.get(f"/api/chat/{car_public}/messages")
        assert no_auth_resp.status_code == 401

    def test_deleted_message_does_not_expose_media(
        self, app_ctx, client, seller_ctx, buyer_ctx, _mock_r2_chat_ops
    ):
        seller_username, seller_public = seller_ctx
        buyer_username, buyer_public = buyer_ctx
        car_public = _make_car(app_ctx, seller_public)
        seller_token = _login(client, seller_username)
        buyer_token = _login(client, buyer_username)

        client.post(
            f"/api/chat/{car_public}/send",
            headers=_auth(buyer_token),
            json={"content": "hi", "receiver_id": seller_public},
        )
        resp = _send_image(client, seller_token, car_public, buyer_public)
        message_id = resp.get_json()["message"]["id"]

        del_resp = client.delete(f"/api/chat/messages/{message_id}", headers=_auth(seller_token))
        assert del_resp.status_code == 200
        assert del_resp.get_json()["message"]["attachment_url"] is None

        _put_mock, presign_mock = _mock_r2_chat_ops
        presign_mock.reset_mock()

        list_resp = _get_messages(client, buyer_token, car_public)
        msg = _find_message(list_resp.get_json(), message_id)
        assert msg is not None
        assert msg["attachment_url"] is None
        assert msg["attachments"] == []
        presign_mock.assert_not_called()

    def test_stored_value_is_object_key_not_a_public_url(self, app_ctx, client, seller_ctx, buyer_ctx):
        app, _socketio, _client, db, User, Car, Message = app_ctx
        seller_username, seller_public = seller_ctx
        buyer_username, buyer_public = buyer_ctx
        car_public = _make_car(app_ctx, seller_public)
        seller_token = _login(client, seller_username)
        buyer_token = _login(client, buyer_username)

        client.post(
            f"/api/chat/{car_public}/send",
            headers=_auth(buyer_token),
            json={"content": "hi", "receiver_id": seller_public},
        )
        resp = _send_image(client, seller_token, car_public, buyer_public)
        message_id = resp.get_json()["message"]["id"]

        with app.app_context():
            row = Message.query.filter_by(public_id=message_id).first()
            raw_stored = row.attachment_url
        assert raw_stored is not None
        assert not raw_stored.startswith("http://")
        assert not raw_stored.startswith("https://")
        assert raw_stored.startswith("chat_uploads/")

    def test_new_chat_uploads_use_only_the_private_bucket(
        self, app_ctx, client, seller_ctx, buyer_ctx, _mock_r2_chat_ops
    ):
        seller_username, seller_public = seller_ctx
        buyer_username, buyer_public = buyer_ctx
        car_public = _make_car(app_ctx, seller_public)
        seller_token = _login(client, seller_username)
        buyer_token = _login(client, buyer_username)

        client.post(
            f"/api/chat/{car_public}/send",
            headers=_auth(buyer_token),
            json={"content": "hi", "receiver_id": seller_public},
        )
        with patch("kk.r2_ops.r2_put_bytes") as public_put_mock:
            resp = _send_image(client, seller_token, car_public, buyer_public)
            assert resp.status_code == 201, resp.data
            public_put_mock.assert_not_called()

        put_mock, _presign_mock = _mock_r2_chat_ops
        put_mock.assert_called_once()

    def test_no_permanent_public_chat_url_is_generated(
        self, app_ctx, client, seller_ctx, buyer_ctx
    ):
        seller_username, seller_public = seller_ctx
        buyer_username, buyer_public = buyer_ctx
        car_public = _make_car(app_ctx, seller_public)
        seller_token = _login(client, seller_username)
        buyer_token = _login(client, buyer_username)

        client.post(
            f"/api/chat/{car_public}/send",
            headers=_auth(buyer_token),
            json={"content": "hi", "receiver_id": seller_public},
        )
        resp = _send_image(client, seller_token, car_public, buyer_public)
        body = resp.get_json()
        assert SENTINEL_PUBLIC_CONFIG["R2_PUBLIC_URL"] not in json.dumps(body)

    def test_c02_delivery_still_emits_exactly_once_with_media(
        self, app_ctx, client, seller_ctx, buyer_ctx
    ):
        """C-10 must not regress C-02: still exactly one new_message socket
        event, now carrying a presigned (not permanent) media URL."""
        app, socketio, _client, *_ = app_ctx
        seller_username, seller_public = seller_ctx
        buyer_username, buyer_public = buyer_ctx
        car_public = _make_car(app_ctx, seller_public)
        seller_token = _login(client, seller_username)
        buyer_token = _login(client, buyer_username)

        client.post(
            f"/api/chat/{car_public}/send",
            headers=_auth(buyer_token),
            json={"content": "hi", "receiver_id": seller_public},
        )

        sio_client = socketio.test_client(app, flask_test_client=client, query_string=f"token={buyer_token}")
        assert sio_client.is_connected()
        sio_client.get_received()

        with patch("kk.chat_realtime.send_push"):
            resp = _send_image(client, seller_token, car_public, buyer_public)
        assert resp.status_code == 201, resp.data

        received = sio_client.get_received()
        new_message_events = [e for e in received if e.get("name") == "new_message"]
        assert len(new_message_events) == 1
        payload = new_message_events[0]["args"][0]
        assert payload["attachment_url"].startswith("https://fake-r2-presigned.example.test/")
        sio_client.disconnect()


# ---------------------------------------------------------------------------
# G. Negative control — proves the authorization test actually catches a
#    bypass. The bypass is applied and reverted within this single test;
#    nothing is left changed afterwards.
# ---------------------------------------------------------------------------


class TestNegativeControlAuthorizationBypass:
    @pytest.fixture(autouse=True)
    def _auto_mock_r2(self, _mock_r2_chat_ops):
        """Scope the R2 mocks to this class only (see `_mock_r2_chat_ops`)."""
        return _mock_r2_chat_ops

    def test_removing_the_participant_filter_makes_the_unauthorized_test_fail(
        self, app_ctx, client, seller_ctx, buyer_ctx, stranger_ctx, _mock_r2_chat_ops
    ):
        """
        Deliberately bypass the participant-authorization check that
        `get_messages()` relies on, and confirm that the unrelated-user
        protection this suite depends on demonstrably breaks. This proves
        the earlier `test_unrelated_authenticated_user_cannot_access_media`
        test is actually exercising the authorization boundary and not
        vacuously passing.

        The bypass is a monkeypatch scoped to this test only (via a
        `try/finally` around the real object) — no source file is modified,
        and nothing is left changed in the working tree afterwards.
        """
        from kk.routes import chat as chat_routes

        seller_username, seller_public = seller_ctx
        buyer_username, buyer_public = buyer_ctx
        stranger_username, _stranger_public = stranger_ctx
        car_public = _make_car(app_ctx, seller_public)
        seller_token = _login(client, seller_username)
        buyer_token = _login(client, buyer_username)
        stranger_token = _login(client, stranger_username)

        client.post(
            f"/api/chat/{car_public}/send",
            headers=_auth(buyer_token),
            json={"content": "hi", "receiver_id": seller_public},
        )
        resp = _send_image(client, seller_token, car_public, buyer_public)
        message_id = resp.get_json()["message"]["id"]

        original_or_ = chat_routes.or_
        try:
            # Bypass: make the "sender OR receiver" participant filter always
            # true (`1 == 1`) instead of checking sender/receiver identity —
            # i.e. simulate the authorization check being deleted.
            chat_routes.or_ = lambda *args, **kwargs: chat_routes.Message.id == chat_routes.Message.id

            list_resp = _get_messages(client, stranger_token, car_public)
            body = list_resp.get_json()
            msg = _find_message(body, message_id)

            # With the authorization check bypassed, the stranger CAN now see
            # the message — demonstrating the earlier protection test would
            # have failed had this bug shipped.
            assert msg is not None, (
                "negative control did not reproduce a bypass — the real "
                "authorization test may not be exercising this code path"
            )
        finally:
            chat_routes.or_ = original_or_

        # Restore verified: the real protection is back in effect.
        list_resp_after = _get_messages(client, stranger_token, car_public)
        msg_after = _find_message(list_resp_after.get_json(), message_id)
        assert msg_after is None


# ---------------------------------------------------------------------------
# H. Fix regression tests (final security review)
#    1. edit_chat_message() positional+type attachment matching
#    2. (fail-closed on fully-absent R2_CHAT_* — see section A above:
#       test_validate_chat_media_persistence_raises_in_production_when_fully_absent)
# ---------------------------------------------------------------------------


class TestEditChatMessagePositionalAttachmentMatching:
    """Regression test for fix #1: the existing (unmodified) Flutter client
    always resubmits each kept attachment's PRESIGNED `url` (never the
    stable stored key) when editing a message. Before the fix, this made
    editing ANY post-C-10 private-media message 400 unconditionally. The
    fix resolves real stored keys positionally, ignoring the client-
    submitted url/key value entirely."""

    @pytest.fixture(autouse=True)
    def _auto_mock_r2(self, _mock_r2_chat_ops):
        return _mock_r2_chat_ops

    @staticmethod
    def _bare_key_from_fake_presigned(url: str) -> str:
        return url.split("example.test/", 1)[1].split("?")[0]

    def test_editing_a_media_group_message_with_presigned_urls_keeps_correct_count(
        self, app_ctx, client, seller_ctx, buyer_ctx
    ):
        seller_username, seller_public = seller_ctx
        buyer_username, buyer_public = buyer_ctx
        car_public = _make_car(app_ctx, seller_public)
        seller_token = _login(client, seller_username)
        buyer_token = _login(client, buyer_username)

        client.post(
            f"/api/chat/{car_public}/send",
            headers=_auth(buyer_token),
            json={"content": "hi", "receiver_id": seller_public},
        )

        files = [
            (io.BytesIO(b"fake-jpeg-1"), "a.jpg"),
            (io.BytesIO(b"fake-jpeg-2"), "b.jpg"),
            (io.BytesIO(b"fake-jpeg-3"), "c.jpg"),
        ]
        send_resp = client.post(
            f"/api/chat/{car_public}/send_media_group",
            headers=_auth(seller_token),
            data={"receiver_id": buyer_public, "attachments": files},
            content_type="multipart/form-data",
        )
        assert send_resp.status_code == 201, send_resp.data
        sent = send_resp.get_json()["message"]
        message_id = sent["id"]
        assert len(sent["attachments"]) == 3

        # Round 1: keep ALL 3 attachments, only change the caption — the
        # exact shape the real Flutter client sends. Before the fix this
        # 400'd unconditionally because `url` here is a PRESIGNED url, not
        # the stored key.
        keep_all_payload = [{"type": a["type"], "url": a["url"]} for a in sent["attachments"]]
        edit_resp = client.patch(
            f"/api/chat/messages/{message_id}",
            headers=_auth(seller_token),
            json={"content": "updated caption", "attachments": keep_all_payload},
        )
        assert edit_resp.status_code == 200, edit_resp.data
        edited = edit_resp.get_json()["message"]
        assert edited["content"] == "updated caption"
        assert len(edited["attachments"]) == 3
        for a in edited["attachments"]:
            assert a["url"].startswith("https://fake-r2-presigned.example.test/chat_uploads/")

        # Round 2: remove the middle attachment. Client submits only 2
        # items (its own presigned urls again, now stale) — backend must
        # ignore those values and resolve real keys positionally.
        keep_two_payload = [
            {"type": edited["attachments"][0]["type"], "url": edited["attachments"][0]["url"]},
            {"type": edited["attachments"][2]["type"], "url": edited["attachments"][2]["url"]},
        ]
        edit_resp2 = client.patch(
            f"/api/chat/messages/{message_id}",
            headers=_auth(seller_token),
            json={"content": "updated caption", "attachments": keep_two_payload},
        )
        assert edit_resp2.status_code == 200, edit_resp2.data
        edited2 = edit_resp2.get_json()["message"]
        assert len(edited2["attachments"]) == 2

        # The two kept keys must both be among the three ORIGINALLY stored
        # keys for THIS message — never a foreign/guessed key — verified at
        # the DB layer, where the stable key (not the presigned url) lives.
        app, _socketio, _client, db, User, Car, Message = app_ctx
        with app.app_context():
            row = Message.query.filter_by(public_id=message_id).first()
            stored_keys = {item["url"] for item in row.attachments}
        original_keys = {self._bare_key_from_fake_presigned(a["url"]) for a in sent["attachments"]}
        assert len(stored_keys) == 2
        assert stored_keys.issubset(original_keys)

    def test_editing_cannot_inject_a_foreign_or_out_of_range_attachment(
        self, app_ctx, client, seller_ctx, buyer_ctx
    ):
        """Security guard for the same fix: since the submitted url/key
        value is no longer trusted for matching at all, submitting MORE
        attachments than the message actually has (an attempt to smuggle a
        foreign/guessed key alongside the real one) must be rejected, and
        must leave the message completely unchanged."""
        seller_username, seller_public = seller_ctx
        buyer_username, buyer_public = buyer_ctx
        car_public = _make_car(app_ctx, seller_public)
        seller_token = _login(client, seller_username)
        buyer_token = _login(client, buyer_username)

        client.post(
            f"/api/chat/{car_public}/send",
            headers=_auth(buyer_token),
            json={"content": "hi", "receiver_id": seller_public},
        )
        resp = _send_image(client, seller_token, car_public, buyer_public)
        sent = resp.get_json()["message"]
        message_id = sent["id"]

        malicious_payload = [
            {"type": "image", "url": sent["attachment_url"]},
            {"type": "image", "url": "https://fake-r2-presigned.example.test/chat_uploads/someone-elses-key.jpg"},
        ]
        edit_resp = client.patch(
            f"/api/chat/messages/{message_id}",
            headers=_auth(seller_token),
            json={"content": "hacked caption", "attachments": malicious_payload},
        )
        assert edit_resp.status_code == 400, edit_resp.data

        app, _socketio, _client, db, User, Car, Message = app_ctx
        with app.app_context():
            row = Message.query.filter_by(public_id=message_id).first()
            assert row.content != "hacked caption"
            assert row.attachment_url is not None
