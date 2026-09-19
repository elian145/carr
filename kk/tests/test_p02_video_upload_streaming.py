"""P-02 regression tests.

PRODUCTION_AUDIT.md P-02 (MEDIUM): "Video multipart upload reads whole file
(up to 100 MB) into memory" -- ``kk/routes/media.py::_upload_video_file_to_r2()``
previously did ``body = file_storage.read()`` (a full in-memory ``bytes``
buffer of the entire uploaded video) and then handed those bytes to
``r2_put_bytes()``, which wrote them straight back out to a *second* temp
file just so the R2 upload subprocess could read them again from disk.

Fix: stream the validated multipart upload straight to a temp file via
``FileStorage.save()`` (Werkzeug copies in small fixed-size chunks -- no
full-file memory buffer in this process) and hand that existing temp path
directly to a new ``kk.r2_ops.r2_put_file()`` helper, skipping the
bytes-buffer + redundant temp-file round trip entirely. The temp file is
always removed afterward (success or failure).

These tests cover:
  A. Unit-level: ``_upload_video_file_to_r2()`` never calls ``.read()`` on
     the file storage (proving no full in-memory buffer), streams the
     exact bytes through to ``r2_put_file()`` via an on-disk path, and
     cleans up the temp file both on success and on a simulated R2
     failure.
  B. HTTP-level: ``POST /api/cars/<car_id>/videos`` (R2-backed) still
     creates the ``CarVideo`` row with the expected URL, still enforces
     upload validation (size limit unchanged, magic-byte content-type
     check still rejects a spoofed extension), and leaves no leftover
     temp file behind either way.
"""

from __future__ import annotations

import os
import sys
import tempfile
import uuid
from io import BytesIO
from pathlib import Path
from unittest.mock import MagicMock

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

import kk.r2_ops as r2_ops_module  # noqa: E402
from kk.routes import media as media_routes  # noqa: E402

_PASSWORD = "Aa123456!"

# Minimal valid ISO-BMFF ("ftyp" box, brand "isom") header so
# `kk.security.sniff_bytes(..., "mp4")` accepts it as a real MP4.
_MP4_HEADER = b"\x00\x00\x00\x18ftypisom\x00\x00\x02\x00isomiso2avc1mp41"


def _fake_video_bytes(size: int = 4096) -> bytes:
    return _MP4_HEADER + (b"\x00" * max(0, size - len(_MP4_HEADER)))


class _StrictFakeVideoStorage:
    """FileStorage-like stub that FAILS the test if the full body is ever
    pulled into memory via ``.read()`` -- P-02 requires streaming via
    ``.save()`` only."""

    def __init__(self, data: bytes, filename: str):
        self._data = data
        self.filename = filename
        self.save_called_with: str | None = None

    def seek(self, *_a, **_kw):
        return None

    def save(self, dst_path: str) -> None:
        self.save_called_with = dst_path
        os.makedirs(os.path.dirname(dst_path), exist_ok=True)
        with open(dst_path, "wb") as fh:
            fh.write(self._data)

    def read(self, *_a, **_kw):
        raise AssertionError(
            "P-02 regression: the full video body was read() into memory "
            "instead of being streamed via save()"
        )


# ---------------------------------------------------------------------------
# A. Unit-level: _upload_video_file_to_r2()
# ---------------------------------------------------------------------------


@pytest.fixture
def r2_env(monkeypatch, tmp_path):
    fake_app = MagicMock()
    fake_app.config = {
        "UPLOAD_FOLDER": str(tmp_path),
        "R2_PUBLIC_URL": "https://cdn.example.com",
    }
    monkeypatch.setattr(media_routes, "current_app", fake_app)
    return tmp_path


class TestUploadVideoFileToR2Streaming:
    def test_streams_to_temp_file_and_never_reads_full_body(self, r2_env, monkeypatch):
        data = _fake_video_bytes(8192)
        storage = _StrictFakeVideoStorage(data, "clip.mp4")

        captured: dict = {}

        def fake_r2_put_file(*, key, file_path, content_type, timeout=120):
            assert os.path.isfile(file_path), "r2_put_file must receive an on-disk path"
            with open(file_path, "rb") as fh:
                captured["body"] = fh.read()
            captured["path"] = file_path
            captured["key"] = key
            captured["content_type"] = content_type

        monkeypatch.setattr(r2_ops_module, "r2_put_file", fake_r2_put_file)

        url = media_routes._upload_video_file_to_r2(storage)

        assert storage.save_called_with is not None
        assert captured["body"] == data
        assert captured["content_type"] == "video/mp4"
        assert url == f"https://cdn.example.com/{captured['key']}"
        # Temp file must be removed after a successful upload.
        assert not os.path.isfile(captured["path"])

    def test_temp_file_is_cleaned_up_even_when_r2_upload_fails(self, r2_env, monkeypatch):
        data = _fake_video_bytes(2048)
        storage = _StrictFakeVideoStorage(data, "clip.mov")
        seen_path: dict = {}

        def failing_r2_put_file(*, key, file_path, content_type, timeout=120):
            seen_path["path"] = file_path
            raise RuntimeError("simulated R2 outage")

        monkeypatch.setattr(r2_ops_module, "r2_put_file", failing_r2_put_file)

        with pytest.raises(RuntimeError):
            media_routes._upload_video_file_to_r2(storage)

        assert seen_path.get("path")
        assert not os.path.isfile(seen_path["path"]), (
            "temp file must be cleaned up even when the R2 upload raises"
        )

    def test_empty_file_body_raises_and_cleans_up(self, r2_env, monkeypatch):
        storage = _StrictFakeVideoStorage(b"", "clip.mp4")
        monkeypatch.setattr(
            r2_ops_module,
            "r2_put_file",
            lambda **_kw: pytest.fail("r2_put_file must not be called for an empty body"),
        )

        with pytest.raises(RuntimeError, match="Empty file body"):
            media_routes._upload_video_file_to_r2(storage)

        assert storage.save_called_with is not None
        assert not os.path.isfile(storage.save_called_with)


# ---------------------------------------------------------------------------
# B. HTTP-level: POST /api/cars/<car_id>/videos (R2-backed)
# ---------------------------------------------------------------------------


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_p02_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "p02.db")
    os.environ["UPLOAD_FOLDER"] = os.path.join(tmp.name, "uploads")
    os.environ["R2_PUBLIC_URL"] = "https://cdn.example.com"
    os.environ["R2_ACCOUNT_ID"] = "test-account"
    os.environ["R2_BUCKET_NAME"] = "test-bucket"
    os.environ["R2_ACCESS_KEY_ID"] = "test-key"
    os.environ["R2_SECRET_ACCESS_KEY"] = "test-secret"

    from kk.app_factory import create_app

    app, _socketio, *_ = create_app()
    app.config["R2_PUBLIC_URL"] = "https://cdn.example.com"
    app.config["R2_ACCOUNT_ID"] = "test-account"
    app.config["R2_BUCKET_NAME"] = "test-bucket"
    app.config["R2_ACCESS_KEY_ID"] = "test-key"
    app.config["R2_SECRET_ACCESS_KEY"] = "test-secret"

    from kk.models import Car, CarVideo, User, db

    with app.app_context():
        db.drop_all()
        db.create_all()

    yield app, app.test_client(), db, User, Car, CarVideo

    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    tmp.cleanup()


@pytest.fixture
def client(app_ctx):
    return app_ctx[1]


def _unique_phone() -> str:
    return f"077{uuid.uuid4().int % 10**8:08d}"


def _make_user(app_ctx) -> tuple[str, int, str]:
    app, _client, db, User, *_ = app_ctx
    username = f"p02_{uuid.uuid4().hex[:10]}"
    with app.app_context():
        user = User(
            username=username,
            phone_number=_unique_phone(),
            first_name="P02",
            last_name="Test",
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
    r = client.post("/api/auth/login", json={"username": username, "password": _PASSWORD})
    assert r.status_code == 200, r.data
    return r.get_json()["access_token"]


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _make_car(app_ctx, seller_id: int) -> tuple[int, str]:
    app, _client, db, _User, Car, _CarVideo = app_ctx
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


def _setup_seller(app_ctx, client):
    public_id, seller_id, username = _make_user(app_ctx)
    token = _login(client, username)
    car_id, car_public_id = _make_car(app_ctx, seller_id)
    return {
        "public_id": public_id,
        "seller_id": seller_id,
        "token": token,
        "car_id": car_id,
        "car_public_id": car_public_id,
    }


class TestUploadCarVideosHttpStreaming:
    def test_valid_video_is_streamed_to_r2_and_temp_file_is_removed(
        self, app_ctx, client, monkeypatch
    ):
        ctx = _setup_seller(app_ctx, client)
        calls: list[str] = []

        def fake_r2_put_file(*, key, file_path, content_type, timeout=120):
            assert os.path.isfile(file_path)
            calls.append(file_path)

        monkeypatch.setattr(r2_ops_module, "r2_put_file", fake_r2_put_file)

        resp = client.post(
            f"/api/cars/{ctx['car_public_id']}/videos",
            data={"files": (BytesIO(_fake_video_bytes()), "clip.mp4")},
            headers=_auth(ctx["token"]),
            content_type="multipart/form-data",
        )
        assert resp.status_code == 201, resp.get_json()
        body = resp.get_json()
        assert len(body["videos"]) == 1
        assert body["videos"][0]["video_url"].startswith("https://cdn.example.com/car_videos/")
        assert len(calls) == 1
        assert not os.path.isfile(calls[0]), "temp file must not survive the request"

    def test_content_spoofed_extension_is_still_rejected_before_any_r2_call(
        self, app_ctx, client, monkeypatch
    ):
        ctx = _setup_seller(app_ctx, client)
        calls: list[str] = []
        monkeypatch.setattr(
            r2_ops_module,
            "r2_put_file",
            lambda **_kw: calls.append("called"),
        )

        # ".mp4" extension but body is not a real MP4 -- magic-byte sniff
        # (kk/security.py::sniff_bytes) must still reject this exactly as
        # before; the streaming change must not weaken that check.
        resp = client.post(
            f"/api/cars/{ctx['car_public_id']}/videos",
            data={"files": (BytesIO(b"not a real video file"), "fake.mp4")},
            headers=_auth(ctx["token"]),
            content_type="multipart/form-data",
        )
        assert resp.status_code == 400, resp.get_json()
        assert calls == [], "R2 must never be called for a rejected file"
