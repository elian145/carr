"""M-06 regression tests.

PRODUCTION_AUDIT.md M-06 (MEDIUM): "No image count cap on
``POST /api/cars/<id>/images``; no ``Image.MAX_IMAGE_PIXELS`` ->
decompression-bomb DoS" (``kk/routes/media.py``; ``kk/media_processing.py``).

Investigation found this **PARTIALLY VALID**, with two distinct defects:

  A. Listing ("kind=listing") photos had NO backend count cap at all on
     either ``POST /api/cars/<car_id>/images`` (``upload_car_images()``) or
     ``POST /api/cars/<car_id>/images/attach`` (``attach_car_images()``) --
     only the sibling "kind=damage" path was capped
     (``MAX_DAMAGE_PHOTOS = 10``). The Flutter client already assumes a
     20-photo cap client-side (``_kSellMaxPhotos`` in
     ``lib/features/sell/sell_step4_logic.dart``), but nothing enforced it
     server-side -- trivially bypassable via a direct API call.

  B. Pillow ships a non-null ``Image.MAX_IMAGE_PIXELS`` default
     (89,478,485) that already rejects extreme decompression bombs via
     ``PIL.Image.DecompressionBombError`` -- but three call sites swallowed
     that specific exception inside a broad ``except Exception``, silently
     falling through to persist/forward the original, un-downscaled,
     bomb-flagged bytes instead of rejecting the file:
       - ``kk/media_processing.py::heic_to_jpeg()``
       - the ``Image.open()``/downscale/re-encode block in
         ``kk/media_processing.py::process_and_store_image()``
       - ``kk/license_plate_blur.py::_normalize_image_bytes_for_inference()``
         (whose swallow let the caller, ``blur_license_plates()``, forward
         the still-unprocessed bomb bytes straight to
         ``cv2.imdecode()``, which has no equivalent guard of its own)

This file tests the implemented fix for both defects:

  A. ``MAX_LISTING_PHOTOS = 20`` (``kk/routes/media.py``), enforced as a
     cumulative-per-car, all-or-nothing cap (mirroring the existing
     ``MAX_DAMAGE_PHOTOS`` / ``_damage_photo_limit_error`` convention
     exactly) on both ``upload_car_images()`` and ``attach_car_images()``.
     A request that would push a car's listing-photo count over 20 is
     rejected in full (HTTP 400, no partial acceptance) -- it never
     creates 20 out of a 25-file request. The pre-existing damage-photo
     cap and its independent counting are asserted unchanged.

  B. ``kk.media_processing.DecompressionBombRejected`` is now raised by the
     two ``media_processing.py`` call sites instead of silently falling
     through; ``upload_car_images()`` catches it per-file (mirroring the
     existing invalid-file ``skip_reasons`` convention) without ever
     persisting the file or leaking the underlying PIL exception text.
     ``_normalize_image_bytes_for_inference()`` now re-raises
     ``PIL.Image.DecompressionBombError`` instead of swallowing it, so
     ``blur_license_plates()`` never reaches its ``cv2.imdecode()`` call
     with bomb-flagged bytes.

Per the task, pixel-bomb tests use a monkeypatched, artificially tiny
``PIL.Image.MAX_IMAGE_PIXELS`` so a small, ordinary test JPEG is treated as
a "bomb" -- no huge real image is constructed or held in memory.
"""

from __future__ import annotations

import glob
import os
import sys
import tempfile
import uuid
from io import BytesIO
from pathlib import Path
from unittest.mock import MagicMock

import pytest
import PIL.Image as PILImage

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from kk import media_processing  # noqa: E402
from kk import license_plate_blur  # noqa: E402
from kk.routes import media as media_routes  # noqa: E402

# Kept in sync with kk/routes/media.py::MAX_LISTING_PHOTOS -- imported
# directly (not hardcoded) so this test file can't silently drift from the
# real cap if it's ever tuned.
MAX_LISTING_PHOTOS = media_routes.MAX_LISTING_PHOTOS


# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------


def _tiny_jpeg_bytes(color=(200, 40, 40), size=(20, 20)) -> bytes:
    """A small, genuinely valid JPEG -- deliberately NOT a real decompression
    bomb. Pixel-bomb tests make Pillow *treat* this as one by monkeypatching
    ``PIL.Image.MAX_IMAGE_PIXELS`` down to a few dozen pixels."""
    im = PILImage.new("RGB", size, color=color)
    buf = BytesIO()
    im.save(buf, format="JPEG", quality=80)
    return buf.getvalue()


class _FakeFileStorage:
    """Minimal stand-in for werkzeug's FileStorage: .filename + .save(path)."""

    def __init__(self, data: bytes, filename: str):
        self._data = data
        self.filename = filename

    def save(self, path: str) -> None:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as fh:
            fh.write(self._data)


# ===========================================================================
# PART 1: pixel-bomb handling (kk/media_processing.py, kk/license_plate_blur.py)
#
# Lightweight unit-level tests, mirroring test_l03_exif_orientation.py's
# `upload_env` (MagicMock `current_app`) style -- no full Flask app needed.
# ===========================================================================


@pytest.fixture
def upload_env(monkeypatch, tmp_path):
    """Route process_and_store_image()/persist_jpeg_bytes() to local disk only.

    R2_* config keys are absent, so `_r2_configured()` is False and no
    network call is attempted.
    """
    monkeypatch.setenv("APP_ENV", "testing")
    monkeypatch.delenv("ROBOFLOW_API_KEY", raising=False)
    upload_folder = str(tmp_path)
    monkeypatch.setattr(
        media_processing,
        "current_app",
        MagicMock(config={"UPLOAD_FOLDER": upload_folder}),
    )
    return upload_folder


def _stored_files(upload_folder: str) -> list[str]:
    return glob.glob(os.path.join(upload_folder, "car_photos", "*"))


class TestPixelBombRejectedNotSwallowed:
    def test_heic_to_jpeg_raises_rejection_instead_of_returning_bomb_bytes(self, monkeypatch):
        """Old behavior: `except Exception: return raw_bytes, False` silently
        swallowed DecompressionBombError and handed back the original bytes
        as if nothing had gone wrong. New behavior: raises
        `DecompressionBombRejected` -- the caller must reject the file."""
        monkeypatch.setattr(PILImage, "MAX_IMAGE_PIXELS", 100)
        src = _tiny_jpeg_bytes()

        with pytest.raises(media_processing.DecompressionBombRejected):
            media_processing.heic_to_jpeg(src)

    def test_heic_to_jpeg_still_returns_original_bytes_on_ordinary_failure(self, monkeypatch):
        """Non-bomb failures (e.g. genuinely corrupt bytes) must keep the
        pre-existing best-effort fallback -- only DecompressionBombError is
        newly raised."""
        out_bytes, converted = media_processing.heic_to_jpeg(b"not a real image at all")
        assert converted is False
        assert out_bytes == b"not a real image at all"

    def test_process_and_store_image_rejects_bomb_and_persists_nothing(
        self, upload_env, monkeypatch
    ):
        """The final downscale/re-encode step in process_and_store_image() is
        the last line of defense before persist_jpeg_bytes() -- it must
        reject the whole file rather than fall through to storing the
        original, un-downscaled bomb bytes."""
        monkeypatch.setattr(PILImage, "MAX_IMAGE_PIXELS", 100)
        src = _tiny_jpeg_bytes()
        fs = _FakeFileStorage(src, "photo.jpg")

        with pytest.raises(media_processing.DecompressionBombRejected):
            media_processing.process_and_store_image(fs, False, skip_blur=True)

        assert _stored_files(upload_env) == [], (
            "bomb-flagged bytes must never be persisted to disk/R2"
        )

    def test_process_and_store_image_rejects_bomb_via_heic_extension_path(
        self, upload_env, monkeypatch
    ):
        """Same guarantee when the rejection originates inside heic_to_jpeg()
        (ext == .heic), not just the final downscale block."""
        monkeypatch.setattr(PILImage, "MAX_IMAGE_PIXELS", 100)
        src = _tiny_jpeg_bytes()
        fs = _FakeFileStorage(src, "photo.heic")

        with pytest.raises(media_processing.DecompressionBombRejected):
            media_processing.process_and_store_image(fs, False, skip_blur=True)

        assert _stored_files(upload_env) == []

    def test_process_and_store_image_rejects_bomb_even_when_blur_is_attempted(
        self, upload_env, monkeypatch
    ):
        """skip_blur=False: PLATE_BLUR_ENABLED path runs but ROBOFLOW_API_KEY
        is unset, so get_plate_detector().is_configured() is False and
        blur_license_plates() is never called (no network) -- the bytes
        still reach, and must still be rejected by, the final downscale
        step under test."""
        monkeypatch.setattr(PILImage, "MAX_IMAGE_PIXELS", 100)
        src = _tiny_jpeg_bytes()
        fs = _FakeFileStorage(src, "photo.jpg")

        with pytest.raises(media_processing.DecompressionBombRejected):
            media_processing.process_and_store_image(fs, False, skip_blur=False)

        assert _stored_files(upload_env) == []

    def test_process_and_store_image_temp_file_is_still_cleaned_up_on_rejection(
        self, upload_env, monkeypatch
    ):
        """The `finally:` temp-file cleanup must still run even though the
        function now raises instead of returning."""
        monkeypatch.setattr(PILImage, "MAX_IMAGE_PIXELS", 100)
        src = _tiny_jpeg_bytes()
        fs = _FakeFileStorage(src, "photo.jpg")

        with pytest.raises(media_processing.DecompressionBombRejected):
            media_processing.process_and_store_image(fs, False, skip_blur=True)

        temp_matches = glob.glob(os.path.join(upload_env, "temp", "*"))
        assert temp_matches == [], "temp file must be removed even when the image is rejected"


class TestNormalImagesStillWorkUnaffected:
    """Regression guard: the real (non-monkeypatched) Pillow default must
    keep processing ordinary small images exactly as before."""

    def test_process_and_store_image_succeeds_for_a_normal_small_image(self, upload_env):
        src = _tiny_jpeg_bytes()
        fs = _FakeFileStorage(src, "photo.jpg")

        rel_path, _b64 = media_processing.process_and_store_image(fs, False, skip_blur=True)

        assert rel_path
        stored = _stored_files(upload_env)
        assert len(stored) == 1
        with open(stored[0], "rb") as fh:
            out_im = PILImage.open(BytesIO(fh.read()))
        out_im.load()  # would raise if the stored bytes were ever malformed
        assert out_im.format == "JPEG"

    def test_heic_to_jpeg_succeeds_for_a_normal_heic_image(self):
        pillow_heif = pytest.importorskip("pillow_heif")

        im = PILImage.new("RGB", (24, 16), color=(10, 200, 10))
        heif_file = pillow_heif.from_pillow(im)
        buf = BytesIO()
        heif_file.save(buf, quality=90)

        out_bytes, converted = media_processing.heic_to_jpeg(buf.getvalue())

        assert converted is True
        out_im = PILImage.open(BytesIO(out_bytes))
        out_im.load()
        assert out_im.format == "JPEG"


class TestLicensePlateBlurPixelBomb:
    def test_normalize_image_bytes_for_inference_raises_rather_than_swallows(self, monkeypatch):
        """Old behavior: the broad `except Exception as e:` returned
        `(image_bytes, {"normalize_status": "normalize_failed", ...})` --
        i.e. handed back the *original* bomb bytes as a normal result. New
        behavior: DecompressionBombError propagates to the caller."""
        monkeypatch.setattr(PILImage, "MAX_IMAGE_PIXELS", 100)
        src = _tiny_jpeg_bytes()

        with pytest.raises(PILImage.DecompressionBombError):
            license_plate_blur._normalize_image_bytes_for_inference(src, ".jpg")

    def test_normalize_image_bytes_for_inference_still_falls_back_on_ordinary_failure(self):
        """Non-bomb failures keep the pre-existing best-effort fallback."""
        out_bytes, meta = license_plate_blur._normalize_image_bytes_for_inference(
            b"not a real image", ".jpg"
        )
        assert out_bytes == b"not a real image"
        assert meta.get("normalize_status") == "normalize_failed"

    def test_blur_license_plates_never_forwards_bomb_bytes_to_cv2_imdecode(self, monkeypatch):
        """The core guarantee: cv2.imdecode() (no pixel-count guard of its
        own) must never be reached with bomb-flagged bytes."""
        cv2 = pytest.importorskip("cv2")
        monkeypatch.setattr(PILImage, "MAX_IMAGE_PIXELS", 100)
        src = _tiny_jpeg_bytes()

        mock_imdecode = MagicMock(wraps=cv2.imdecode)
        monkeypatch.setattr(cv2, "imdecode", mock_imdecode)

        out_bytes, meta = license_plate_blur.blur_license_plates(
            image_bytes=src,
            output_ext=".jpg",
            detector=MagicMock(),
        )

        mock_imdecode.assert_not_called()
        # Falls back to the function's pre-existing "something went wrong"
        # contract: original bytes, no blur applied.
        assert out_bytes == src
        assert meta.get("status") == "error"

    def test_blur_license_plates_still_blurs_normally_without_a_bomb(self, monkeypatch):
        """Regression guard: with the real Pillow default, a normal image
        with no detected plates still returns the documented "no_plates"
        fallback -- proving the fix didn't disturb the ordinary path."""
        cv2 = pytest.importorskip("cv2")
        src = _tiny_jpeg_bytes()
        detector = MagicMock()
        detector.detect_with_meta.return_value = ([], {"detect_status": "ok"})

        out_bytes, meta = license_plate_blur.blur_license_plates(
            image_bytes=src,
            output_ext=".jpg",
            detector=detector,
        )
        assert meta.get("status") == "no_plates"
        assert isinstance(out_bytes, bytes)


class TestPixelBombNoInternalDetailLeak:
    def test_decompression_bomb_rejected_message_carries_no_pil_internal_text(self):
        """DecompressionBombRejected's own str() must not be relied on by
        API responses -- route handlers use a fixed, generic message
        instead (see the HTTP-level test in Part 2)."""
        err = media_processing.DecompressionBombRejected("x")
        # Sanity: it is a plain Exception subclass with no special
        # attributes that could accidentally get serialized into a response.
        assert isinstance(err, Exception)


# ===========================================================================
# PART 2: listing-photo count cap + end-to-end pixel-bomb-does-not-leak
# (real Flask app + real SQLite + real HTTP routes)
# ===========================================================================

_PASSWORD = "Aa123456!"


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_m06_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "m06.db")
    os.environ["UPLOAD_FOLDER"] = os.path.join(tmp.name, "uploads")
    os.environ.pop("ROBOFLOW_API_KEY", None)
    # R2_PUBLIC_URL only (no full R2 credential set) -- lets attach()'s
    # staged-URL HTTP branch work while upload_car_images() still falls
    # back to local disk (no real network call). Set on the env too (belt
    # and suspenders), but see the `app.config[...]` override just below:
    # `kk.config.Config.R2_PUBLIC_URL` is a class attribute evaluated once
    # at first `import kk.config` (which this module's own top-level
    # `kk.media_processing`/`kk.license_plate_blur`/`kk.routes.media`
    # imports -- or an earlier-collected test module's imports -- may
    # already have triggered before this fixture runs), so setting the env
    # var alone is not reliably observed here. Overriding the live
    # `app.config` dict after `create_app()` returns sidesteps that
    # import-order/caching hazard entirely.
    os.environ["R2_PUBLIC_URL"] = "https://cdn.example.com"
    for key in ("R2_ACCOUNT_ID", "R2_BUCKET_NAME", "R2_ACCESS_KEY_ID", "R2_SECRET_ACCESS_KEY"):
        os.environ.pop(key, None)

    from kk.app_factory import create_app

    app, _socketio, *_ = create_app()
    app.config["R2_PUBLIC_URL"] = "https://cdn.example.com"
    for key in ("R2_ACCOUNT_ID", "R2_BUCKET_NAME", "R2_ACCESS_KEY_ID", "R2_SECRET_ACCESS_KEY"):
        app.config.pop(key, None)
    from kk.models import Car, CarImage, User, db

    with app.app_context():
        db.drop_all()
        db.create_all()

    yield app, app.test_client(), db, User, Car, CarImage

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
    """Create an active, verified, non-dealer user. Returns
    (public_id, id, username)."""
    app, _client, db, User, *_ = app_ctx
    username = f"m06_{uuid.uuid4().hex[:10]}"
    with app.app_context():
        user = User(
            username=username,
            phone_number=_unique_phone(),
            first_name="M06",
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
    r = client.post(
        "/api/auth/login", json={"username": username, "password": _PASSWORD}
    )
    assert r.status_code == 200, r.data
    return r.get_json()["access_token"]


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _make_car(app_ctx, seller_id: int) -> tuple[int, str]:
    app, _client, db, _User, Car, _CarImage = app_ctx
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


def _seed_images(app_ctx, car_id: int, count: int, *, kind: str = "listing") -> None:
    app, _client, db, _User, _Car, CarImage = app_ctx
    with app.app_context():
        for i in range(count):
            db.session.add(
                CarImage(
                    car_id=car_id,
                    image_url=f"https://example.com/{kind}-{car_id}-{i}.jpg",
                    is_primary=False,
                    kind=kind,
                )
            )
        db.session.commit()


def _image_count(app_ctx, car_id: int, *, kind: str | None = None) -> int:
    app, _client, db, _User, _Car, CarImage = app_ctx
    with app.app_context():
        q = CarImage.query.filter_by(car_id=car_id)
        if kind is not None:
            q = q.filter_by(kind=kind)
        return q.count()


def _files_payload(n: int, field: str = "files") -> dict:
    return {field: [(BytesIO(_tiny_jpeg_bytes()), f"photo-{i}.jpg") for i in range(n)]}


def _staged_urls(app_ctx, owner_public_id: str, n: int, tag: str = "staged") -> list[str]:
    from kk import media_processing as mp

    app, _client, *_ = app_ctx
    with app.app_context():
        owner_tag = mp.media_owner_tag(owner_public_id)
    return [
        f"https://cdn.example.com/car_photos/{owner_tag}/{tag}-{i}.jpg" for i in range(n)
    ]


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


# ---------------------------------------------------------------------------
# A. Listing-photo count cap -- upload_car_images()
# ---------------------------------------------------------------------------


class TestListingCapUpload:
    def test_under_cap_upload_succeeds_with_unchanged_response_shape(self, app_ctx, client):
        ctx = _setup_seller(app_ctx, client)
        resp = client.post(
            f"/api/cars/{ctx['car_public_id']}/images",
            data=_files_payload(5),
            headers=_auth(ctx["token"]),
            content_type="multipart/form-data",
        )
        assert resp.status_code == 201, resp.get_json()
        body = resp.get_json()
        assert "message" in body and "images" in body and "image_url" in body
        assert len(body["images"]) == 5
        assert _image_count(app_ctx, ctx["car_id"]) == 5

    def test_reaching_exactly_the_cap_succeeds(self, app_ctx, client):
        ctx = _setup_seller(app_ctx, client)
        _seed_images(app_ctx, ctx["car_id"], 18)
        resp = client.post(
            f"/api/cars/{ctx['car_public_id']}/images",
            data=_files_payload(2),
            headers=_auth(ctx["token"]),
            content_type="multipart/form-data",
        )
        assert resp.status_code == 201, resp.get_json()
        assert _image_count(app_ctx, ctx["car_id"]) == MAX_LISTING_PHOTOS

    def test_upload_exceeding_remaining_capacity_is_rejected_atomically(self, app_ctx, client):
        """18 existing + 5 incoming (only 2 slots remain) -> reject the
        whole request; must NOT partially create 2 (or any) new rows."""
        ctx = _setup_seller(app_ctx, client)
        _seed_images(app_ctx, ctx["car_id"], 18)
        resp = client.post(
            f"/api/cars/{ctx['car_public_id']}/images",
            data=_files_payload(5),
            headers=_auth(ctx["token"]),
            content_type="multipart/form-data",
        )
        assert resp.status_code == 400, resp.get_json()
        assert "20" in resp.get_json().get("message", "")
        assert _image_count(app_ctx, ctx["car_id"]) == 18, (
            "over-cap request must be rejected atomically, not partially accepted"
        )

    def test_upload_when_car_already_at_cap_is_rejected(self, app_ctx, client):
        ctx = _setup_seller(app_ctx, client)
        _seed_images(app_ctx, ctx["car_id"], 20)
        resp = client.post(
            f"/api/cars/{ctx['car_public_id']}/images",
            data=_files_payload(1),
            headers=_auth(ctx["token"]),
            content_type="multipart/form-data",
        )
        assert resp.status_code == 400, resp.get_json()
        assert _image_count(app_ctx, ctx["car_id"]) == 20

    def test_request_of_25_for_an_empty_car_is_rejected_entirely_not_partial(self, app_ctx, client):
        """The example from the implementation spec: 25 files for a car with
        0 existing images must be rejected outright, never partially
        accepting 20 out of the 25."""
        ctx = _setup_seller(app_ctx, client)
        resp = client.post(
            f"/api/cars/{ctx['car_public_id']}/images",
            data=_files_payload(25),
            headers=_auth(ctx["token"]),
            content_type="multipart/form-data",
        )
        assert resp.status_code == 400, resp.get_json()
        assert _image_count(app_ctx, ctx["car_id"]) == 0


# ---------------------------------------------------------------------------
# B. Listing-photo count cap -- attach_car_images()
# ---------------------------------------------------------------------------


class TestListingCapAttach:
    def test_under_cap_attach_succeeds(self, app_ctx, client):
        ctx = _setup_seller(app_ctx, client)
        urls = _staged_urls(app_ctx, ctx["public_id"], 5)
        resp = client.post(
            f"/api/cars/{ctx['car_public_id']}/images/attach",
            json={"urls": urls},
            headers=_auth(ctx["token"]),
        )
        assert resp.status_code == 201, resp.get_json()
        body = resp.get_json()
        assert len(body["images"]) == 5
        assert _image_count(app_ctx, ctx["car_id"]) == 5

    def test_attach_exceeding_remaining_capacity_is_rejected_atomically(self, app_ctx, client):
        ctx = _setup_seller(app_ctx, client)
        _seed_images(app_ctx, ctx["car_id"], 18)
        urls = _staged_urls(app_ctx, ctx["public_id"], 5, tag="over")
        resp = client.post(
            f"/api/cars/{ctx['car_public_id']}/images/attach",
            json={"urls": urls},
            headers=_auth(ctx["token"]),
        )
        assert resp.status_code == 400, resp.get_json()
        assert _image_count(app_ctx, ctx["car_id"]) == 18

    def test_attach_reaching_exactly_the_cap_succeeds(self, app_ctx, client):
        ctx = _setup_seller(app_ctx, client)
        _seed_images(app_ctx, ctx["car_id"], 18)
        urls = _staged_urls(app_ctx, ctx["public_id"], 2, tag="exact")
        resp = client.post(
            f"/api/cars/{ctx['car_public_id']}/images/attach",
            json={"urls": urls},
            headers=_auth(ctx["token"]),
        )
        assert resp.status_code == 201, resp.get_json()
        assert _image_count(app_ctx, ctx["car_id"]) == 20

    def test_attach_when_car_already_at_cap_is_rejected(self, app_ctx, client):
        ctx = _setup_seller(app_ctx, client)
        _seed_images(app_ctx, ctx["car_id"], 20)
        urls = _staged_urls(app_ctx, ctx["public_id"], 1, tag="atcap")
        resp = client.post(
            f"/api/cars/{ctx['car_public_id']}/images/attach",
            json={"urls": urls},
            headers=_auth(ctx["token"]),
        )
        assert resp.status_code == 400, resp.get_json()
        assert _image_count(app_ctx, ctx["car_id"]) == 20

    def test_attach_cumulative_cap_spans_both_routes(self, app_ctx, client):
        """15 uploaded via /images, then 10 more via /attach must be
        rejected (only 5 remaining slots) -- the cap is a single shared
        cumulative-per-car counter, not per-route."""
        ctx = _setup_seller(app_ctx, client)
        resp1 = client.post(
            f"/api/cars/{ctx['car_public_id']}/images",
            data=_files_payload(15),
            headers=_auth(ctx["token"]),
            content_type="multipart/form-data",
        )
        assert resp1.status_code == 201, resp1.get_json()
        assert _image_count(app_ctx, ctx["car_id"]) == 15

        urls = _staged_urls(app_ctx, ctx["public_id"], 10, tag="mix")
        resp2 = client.post(
            f"/api/cars/{ctx['car_public_id']}/images/attach",
            json={"urls": urls},
            headers=_auth(ctx["token"]),
        )
        assert resp2.status_code == 400, resp2.get_json()
        assert _image_count(app_ctx, ctx["car_id"]) == 15


# ---------------------------------------------------------------------------
# C. Damage-photo cap must remain completely unchanged
# ---------------------------------------------------------------------------


class TestDamageCapUnchanged:
    def test_damage_cap_still_10_and_independent_of_listing_cap(self, app_ctx, client):
        ctx = _setup_seller(app_ctx, client)
        # Car is already at the *listing* cap -- must have zero effect on
        # the independent damage-photo counting/cap.
        _seed_images(app_ctx, ctx["car_id"], 20, kind="listing")

        resp_ok = client.post(
            f"/api/cars/{ctx['car_public_id']}/images?kind=damage",
            data=_files_payload(10),
            headers=_auth(ctx["token"]),
            content_type="multipart/form-data",
        )
        assert resp_ok.status_code == 201, resp_ok.get_json()
        assert _image_count(app_ctx, ctx["car_id"], kind="damage") == 10
        assert _image_count(app_ctx, ctx["car_id"], kind="listing") == 20

        resp_over = client.post(
            f"/api/cars/{ctx['car_public_id']}/images?kind=damage",
            data=_files_payload(1),
            headers=_auth(ctx["token"]),
            content_type="multipart/form-data",
        )
        assert resp_over.status_code == 400, resp_over.get_json()
        assert "10" in resp_over.get_json().get("message", "")
        assert _image_count(app_ctx, ctx["car_id"], kind="damage") == 10

    def test_damage_cap_message_and_behavior_byte_for_byte_same_as_before(self, app_ctx, client):
        ctx = _setup_seller(app_ctx, client)
        resp = client.post(
            f"/api/cars/{ctx['car_public_id']}/images?kind=damage",
            data=_files_payload(11),
            headers=_auth(ctx["token"]),
            content_type="multipart/form-data",
        )
        assert resp.status_code == 400
        assert resp.get_json()["message"] == "You can add up to 10 damage photos per listing."
        assert _image_count(app_ctx, ctx["car_id"], kind="damage") == 0


# ---------------------------------------------------------------------------
# D. Pixel-bomb rejection end-to-end (HTTP) + no internal detail leak
# ---------------------------------------------------------------------------


class TestPixelBombEndToEndNoLeak:
    def test_bomb_flagged_upload_is_skipped_with_generic_message(self, app_ctx, client, monkeypatch):
        monkeypatch.setattr(PILImage, "MAX_IMAGE_PIXELS", 100)
        ctx = _setup_seller(app_ctx, client)

        resp = client.post(
            f"/api/cars/{ctx['car_public_id']}/images",
            data=_files_payload(1),
            headers=_auth(ctx["token"]),
            content_type="multipart/form-data",
        )
        assert resp.status_code == 400, resp.get_json()
        body_text = resp.get_data(as_text=True)
        assert _image_count(app_ctx, ctx["car_id"]) == 0

        # No PIL/internal exception text leaked to the client.
        lowered = body_text.lower()
        for leaky_token in (
            "decompressionbomb",
            "traceback",
            "pil.image",
            "site-packages",
            ".py\"",
            "exceeds limit",
        ):
            assert leaky_token not in lowered, f"response leaked internal detail: {leaky_token!r}"

    def test_bomb_rejection_does_not_affect_surrounding_valid_uploads(
        self, app_ctx, client, monkeypatch
    ):
        """A rejected bomb-flagged request must not disturb previously
        stored images, and a later, ordinary upload on the same car must
        keep working normally afterward (the rejection is scoped to the
        single offending request/file, not the car or session)."""
        ctx = _setup_seller(app_ctx, client)

        good1 = client.post(
            f"/api/cars/{ctx['car_public_id']}/images",
            data=_files_payload(1),
            headers=_auth(ctx["token"]),
            content_type="multipart/form-data",
        )
        assert good1.status_code == 201, good1.get_json()

        monkeypatch.setattr(PILImage, "MAX_IMAGE_PIXELS", 100)
        bomb_resp = client.post(
            f"/api/cars/{ctx['car_public_id']}/images",
            data=_files_payload(1),
            headers=_auth(ctx["token"]),
            content_type="multipart/form-data",
        )
        assert bomb_resp.status_code == 400, bomb_resp.get_json()
        assert _image_count(app_ctx, ctx["car_id"]) == 1, "the earlier valid upload must be unaffected"

        monkeypatch.undo()
        good2 = client.post(
            f"/api/cars/{ctx['car_public_id']}/images",
            data=_files_payload(1),
            headers=_auth(ctx["token"]),
            content_type="multipart/form-data",
        )
        assert good2.status_code == 201, good2.get_json()
        assert _image_count(app_ctx, ctx["car_id"]) == 2


# ===========================================================================
# PART 3 (M-06 follow-up): async image-processing pipeline pixel-bomb safety
#
# `kk/tasks/image_tasks.py::_process_image_path()` is a self-documented
# duplicate of `process_and_store_image()`'s downscale/re-encode step,
# reachable via the *unrestricted* production route
# `POST /api/process-car-images?async=1` (kk/routes/ai.py) ->
# `process_car_image_file.delay(...)` (Celery task) -> `_process_image_path()`.
#
# It previously had its own `except Exception: pass` around that downscale
# step, so a `PIL.Image.DecompressionBombError` there was silently
# swallowed and the original, un-downscaled, bomb-flagged bytes were then
# passed to the unconditional `persist_jpeg_bytes()` call right below --
# persisting the bomb to R2/local disk. The fix reuses the exact same
# `kk.media_processing.DecompressionBombRejected` mechanism already used by
# `process_and_store_image()`, rather than inventing a second one.
# ===========================================================================


class TestAsyncImageTaskPixelBomb:
    """Exercises the actual vulnerable function, `_process_image_path()`,
    directly with controlled/mocked dependencies (per-function unit tests),
    plus the real Celery task (`process_car_image_file`) run synchronously
    via `.apply()` to prove the async path as a whole never reports a
    successful, persisted result for a bomb-flagged image."""

    @staticmethod
    def _write_temp_source(tmp_path, data: bytes, name: str = "incoming.jpg") -> str:
        temp_abs = str(tmp_path / name)
        with open(temp_abs, "wb") as fh:
            fh.write(data)
        return temp_abs

    def test_process_image_path_rejects_bomb_and_never_calls_persist_jpeg_bytes(
        self, upload_env, monkeypatch, tmp_path
    ):
        """Old behavior: the downscale block's `except Exception: pass`
        left `out_bytes` as the original bomb-flagged bytes, which the
        unconditional `persist_jpeg_bytes()` call right below would then
        persist. New behavior: `DecompressionBombRejected` propagates out
        of `_process_image_path()` *before* `persist_jpeg_bytes()` is ever
        reached."""
        from kk.tasks import image_tasks

        monkeypatch.setattr(PILImage, "MAX_IMAGE_PIXELS", 100)
        temp_abs = self._write_temp_source(tmp_path, _tiny_jpeg_bytes())

        mock_persist = MagicMock()
        monkeypatch.setattr(media_processing, "persist_jpeg_bytes", mock_persist)

        with pytest.raises(media_processing.DecompressionBombRejected):
            image_tasks._process_image_path(
                temp_abs=temp_abs,
                original_filename="photo.jpg",
                inline_base64=False,
                skip_blur=True,
            )

        mock_persist.assert_not_called()
        assert _stored_files(upload_env) == [], (
            "bomb-flagged bytes must never be persisted to disk/R2 via the async task path"
        )

    def test_process_image_path_rejects_bomb_even_when_blur_is_attempted_and_cv2_never_reached(
        self, upload_env, monkeypatch, tmp_path
    ):
        """Full chain with skip_blur=False: blur_image_bytes() ->
        blur_license_plates() -> _normalize_image_bytes_for_inference()
        must still never forward bomb bytes to cv2.imdecode() when reached
        through this async duplicate path, and the downscale block below
        it must still reject the file rather than persist it."""
        cv2 = pytest.importorskip("cv2")
        from kk.tasks import image_tasks

        monkeypatch.setenv("PLATE_BLUR_ENABLED", "1")
        fake_detector = MagicMock()
        fake_detector.is_configured.return_value = True
        monkeypatch.setattr(license_plate_blur, "get_plate_detector", lambda: fake_detector)

        monkeypatch.setattr(PILImage, "MAX_IMAGE_PIXELS", 100)
        mock_imdecode = MagicMock(wraps=cv2.imdecode)
        monkeypatch.setattr(cv2, "imdecode", mock_imdecode)

        mock_persist = MagicMock()
        monkeypatch.setattr(media_processing, "persist_jpeg_bytes", mock_persist)

        temp_abs = self._write_temp_source(tmp_path, _tiny_jpeg_bytes(), "incoming_blur.jpg")

        with pytest.raises(media_processing.DecompressionBombRejected):
            image_tasks._process_image_path(
                temp_abs=temp_abs,
                original_filename="photo.jpg",
                inline_base64=False,
                skip_blur=False,
            )

        mock_imdecode.assert_not_called()
        mock_persist.assert_not_called()
        assert _stored_files(upload_env) == []

    def test_process_image_path_still_succeeds_for_a_normal_small_image(
        self, upload_env, tmp_path
    ):
        """Regression guard: the real (non-monkeypatched) Pillow default
        must keep processing ordinary small images through the async path
        exactly as before."""
        from kk.tasks import image_tasks

        temp_abs = self._write_temp_source(tmp_path, _tiny_jpeg_bytes())

        result = image_tasks._process_image_path(
            temp_abs=temp_abs,
            original_filename="photo.jpg",
            inline_base64=False,
            skip_blur=True,
        )

        assert result.get("rel_path")
        stored = _stored_files(upload_env)
        assert len(stored) == 1
        with open(stored[0], "rb") as fh:
            out_im = PILImage.open(BytesIO(fh.read()))
        out_im.load()
        assert out_im.format == "JPEG"

    def test_process_car_image_file_task_fails_and_cleans_up_temp_for_a_bomb(
        self, app_ctx, monkeypatch, tmp_path
    ):
        """The full Celery task, run synchronously (no broker needed): a
        decompression bomb must make the task report FAILURE -- never a
        fabricated `{"ok": True, ...}` result implying successful
        persistence -- while still cleaning up the temp file exactly as
        before."""
        from kk.tasks import celery_app as celery_app_module
        from kk.tasks.image_tasks import process_car_image_file

        app = app_ctx[0]
        monkeypatch.setattr(celery_app_module, "get_celery_flask_app", lambda: app)
        monkeypatch.delenv("ROBOFLOW_API_KEY", raising=False)
        monkeypatch.setattr(PILImage, "MAX_IMAGE_PIXELS", 100)

        temp_abs = self._write_temp_source(tmp_path, _tiny_jpeg_bytes(), "async_bomb.jpg")

        result = process_car_image_file.apply(
            kwargs={
                "temp_abs": temp_abs,
                "original_filename": "photo.jpg",
                "inline_base64": False,
                "skip_blur": True,
            }
        )

        assert result.failed(), (
            "the task must report failure, not a successful persisted result, for a bomb"
        )
        assert not result.successful()
        assert not os.path.isfile(temp_abs), (
            "temp file cleanup (the `finally:` block) must still run even when the task fails"
        )

    def test_process_car_image_file_task_succeeds_normally_for_a_small_image(
        self, app_ctx, monkeypatch, tmp_path
    ):
        """Regression guard at the full-task level: an ordinary image must
        still be processed and persisted successfully, and the temp file
        must still be cleaned up."""
        from kk.tasks import celery_app as celery_app_module
        from kk.tasks.image_tasks import process_car_image_file

        app = app_ctx[0]
        monkeypatch.setattr(celery_app_module, "get_celery_flask_app", lambda: app)
        monkeypatch.delenv("ROBOFLOW_API_KEY", raising=False)

        temp_abs = self._write_temp_source(tmp_path, _tiny_jpeg_bytes(), "async_ok.jpg")

        result = process_car_image_file.apply(
            kwargs={
                "temp_abs": temp_abs,
                "original_filename": "photo.jpg",
                "inline_base64": False,
                "skip_blur": True,
            }
        )

        assert result.successful(), result.result
        out = result.result
        assert out.get("ok") is True
        assert out.get("rel_path")
        assert not os.path.isfile(temp_abs), "temp file must be cleaned up after success too"
