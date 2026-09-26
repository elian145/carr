"""Issue-3 regression tests (real-device evidence): ``POST
/api/cars/<car_id>/videos`` returned HTTP 400 for genuinely valid ``.mov``
files.

Root cause (confirmed by code reading, not speculation): ``upload_car_videos()``
in ``kk/routes/media.py`` calls ``validate_file_upload()`` ->
``validate_file_upload_security()`` (``kk/security.py``), which -- once the
extension/size checks pass -- calls ``sniff_bytes(header, "mov")`` ->
``_is_mov(header)``. Before the fix, ``_is_mov`` required the ISO-BMFF
``ftyp`` box's ``major_brand`` to be the EXACT 4-byte QuickTime code
``"qt  "``, incorrectly rejecting:

  1. ``.mov`` files whose ``ftyp`` major_brand is an MP4-family code (e.g.
     ``"isom"``) -- MOV and MP4 share the exact same ISO-BMFF container
     format, so a muxer/export pipeline is free to declare either brand
     while still writing a ``.mov`` filename.
  2. "Classic" pre-``ftyp`` QuickTime movies that start directly with a
     top-level atom (``moov``/``mdat``/``free``/etc.) instead of an
     ISO-BMFF ``ftyp`` box at all -- the exact shape real devices were
     observed producing at durable paths like
     ``sell_draft_media/<draftId>/video_XXXXXXXX.mov``.

On rejection, every file failed validation, so
``validate_file_upload_security()`` returned
``(False, "File content does not match its extension")``, every uploaded
file landed in ``rejected``, and -- since ``uploaded_videos`` was empty --
``upload_car_videos()`` rolled back and returned
``jsonify({"message": detail, "videos": [], "rejected": rejected}), 400``.

``kk/security.py::_is_mov()`` unit tests already cover the byte-signature
logic directly (see ``test_h03_upload_content_validation.py::TestSniffBytes``).
This file adds the full HTTP-level regression: a real
``POST /api/cars/<car_id>/videos`` multipart request, using the same
durable-storage filename convention (``video_XXXXXXXX.mov``) real-device
logs showed, must now succeed for every genuinely valid ``.mov`` shape --
while a non-video payload with a spoofed ``.mov`` extension must still be
rejected (proving the fix did not "loosen validation" or "blindly allow
everything").
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

_PASSWORD = "Aa123456!"

# Three real, legitimate `.mov` byte shapes (see `kk/security.py::_is_mov`
# docstring for the full explanation of each):
#   1. Canonical QuickTime ftyp brand "qt  ".
MOV_QT_BRAND_BYTES = (
    b"\x00\x00\x00\x14ftypqt  " + b"\x00\x00\x02\x00" + b"\x00" * 512
)
#   2. MP4-family ftyp brand ("isom") with a `.mov` extension/filename --
#      genuinely the same ISO-BMFF container format as `.mp4`.
MOV_ISOM_BRAND_BYTES = (
    b"\x00\x00\x00\x14ftypisom" + b"\x00\x00\x02\x00" + b"\x00" * 512
)
#   3. "Classic" pre-ftyp QuickTime movie starting directly with a `moov`
#      top-level atom -- no ftyp box at all.
MOV_CLASSIC_ATOM_BYTES = b"\x00\x00\x00\x08moov" + b"\x00" * 512

# Not a video of any kind -- must still be rejected even with a `.mov`
# extension/filename (proves the fix is narrow, not "allow everything").
NOT_A_VIDEO_BYTES = b"<html><body>not a video</body></html>" + b"\x00" * 32


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_mov_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "mov.db")
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
    username = f"mov_{uuid.uuid4().hex[:10]}"
    with app.app_context():
        user = User(
            username=username,
            phone_number=_unique_phone(),
            first_name="Mov",
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


class TestUploadCarVideosMovContentValidation:
    @pytest.mark.parametrize(
        "video_bytes,label",
        [
            (MOV_QT_BRAND_BYTES, "qt_brand"),
            (MOV_ISOM_BRAND_BYTES, "isom_brand"),
            (MOV_CLASSIC_ATOM_BYTES, "classic_atom"),
        ],
        ids=["qt_brand", "isom_brand", "classic_atom"],
    )
    def test_genuine_mov_shapes_are_accepted(
        self, app_ctx, client, monkeypatch, video_bytes, label
    ):
        ctx = _setup_seller(app_ctx, client)
        calls: list[str] = []

        def fake_r2_put_file(*, key, file_path, content_type, timeout=120):
            assert os.path.isfile(file_path)
            calls.append(file_path)

        monkeypatch.setattr(r2_ops_module, "r2_put_file", fake_r2_put_file)

        # Same durable-storage filename convention real-device logs showed:
        # `sell_draft_media/<draftId>/video_XXXXXXXX.mov`.
        filename = f"video_{uuid.uuid4().hex[:8]}.mov"
        resp = client.post(
            f"/api/cars/{ctx['car_public_id']}/videos",
            data={"files": (BytesIO(video_bytes), filename)},
            headers=_auth(ctx["token"]),
            content_type="multipart/form-data",
        )
        assert resp.status_code == 201, (label, resp.get_json())
        body = resp.get_json()
        assert len(body["videos"]) == 1
        assert not body.get("rejected"), (label, body.get("rejected"))
        assert len(calls) == 1

    def test_non_video_content_with_mov_extension_is_still_rejected(
        self, app_ctx, client, monkeypatch
    ):
        """The fix must be narrow: it recognizes specific, concrete binary
        signatures (a real ISO-BMFF ftyp box with an MP4/QuickTime brand,
        or a known classic QuickTime atom name) -- it does not "loosen
        validation" or "blindly allow everything" with a `.mov`
        extension."""
        ctx = _setup_seller(app_ctx, client)
        calls: list[str] = []
        monkeypatch.setattr(
            r2_ops_module,
            "r2_put_file",
            lambda **_kw: calls.append("called"),
        )

        resp = client.post(
            f"/api/cars/{ctx['car_public_id']}/videos",
            data={"files": (BytesIO(NOT_A_VIDEO_BYTES), "video_fake0001.mov")},
            headers=_auth(ctx["token"]),
            content_type="multipart/form-data",
        )
        assert resp.status_code == 400, resp.get_json()
        assert calls == [], "R2 must never be called for a rejected file"
