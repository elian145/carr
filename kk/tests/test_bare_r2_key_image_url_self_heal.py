"""Regression: a bare R2 object key in ``CarImage.image_url`` must not be
silently dropped from listing API responses.

Bug (production "created listing still shows a placeholder" incident):
``kk/media_processing.py::persist_jpeg_bytes`` returns a **bare R2 object
key** (e.g. ``car_photos/<owner_tag>/<file>.jpg``, no scheme/host) whenever
R2 is configured (credentials present) but ``R2_PUBLIC_URL`` is unset *at
upload time* -- see that function's ``if public_base: return
f"{public_base}/{bucket_key}"`` / ``return bucket_key`` branches. That value
is neither an absolute URL nor a path that exists on the *web* process's
local disk (the bytes are genuinely in R2, not on local disk), so
``kk/routes/cars.py::_resolve_rel`` used to fall through to its final
``return ""``. Because ``_with_media_compat`` does ``if not resolved:
continue`` for the ``images`` array, and the primary-image fallback
(``primary_rel = _resolve_rel(raw_primary) or raw_primary``) fell back to
the *raw bare key* for ``image_url`` -- the image was either dropped
outright (from ``images``) or exposed as a domain-less string the Flutter
client would then misinterpret as a Flask-relative path and 404 on.

Fix: ``_resolve_rel`` now treats an unresolvable relative value as a bare
R2 key and reconstructs its public URL from the *current* R2_PUBLIC_URL
config, instead of dropping it -- self-healing even for rows written while
R2_PUBLIC_URL was temporarily missing, as long as it is correctly set now.

Covers:
  * A bare R2 key resolves to a full https:// URL once R2_PUBLIC_URL is
    configured, and is no longer dropped from ``images``.
  * The primary ``image_url`` field also resolves to the full URL (not the
    bare key).
  * Without R2_PUBLIC_URL configured, the old (safe) behavior is
    preserved: an unresolvable value is still dropped, not fabricated.
  * A real local ``uploads/car_photos/<file>`` relative path that exists on
    disk still resolves via the local-disk branch (this fix must not
    change that pre-existing, correct behavior).
  * An already-absolute ``https://...`` URL passes through unchanged (no
    double-prefixing regression).
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

_PASSWORD = "Aa123456!"


def _unique_phone() -> str:
    return f"078{uuid.uuid4().int % 10**8:08d}"


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(
        prefix="carlist_bare_r2_key_", ignore_cleanup_errors=True
    )
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "bare_r2_key.db")
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

    from kk.models import Car, CarImage, User, db

    with app.app_context():
        db.drop_all()
        db.create_all()

    yield app, app.test_client(), db, User, Car, CarImage

    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    tmp.cleanup()


def _make_user(app_ctx) -> tuple[int, str]:
    app, _client, db, User, *_ = app_ctx
    username = f"barer2key_{uuid.uuid4().hex[:10]}"
    with app.app_context():
        user = User(
            username=username,
            phone_number=_unique_phone(),
            first_name="Bare",
            last_name="Key",
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id=f"pub-{uuid.uuid4().hex[:12]}",
        )
        user.set_password(_PASSWORD)
        db.session.add(user)
        db.session.commit()
        return user.id, username


def _make_car_with_image(app_ctx, seller_id: int, image_url: str) -> str:
    app, _client, db, _User, Car, CarImage = app_ctx
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
        img = CarImage(
            car_id=car.id,
            image_url=image_url,
            is_primary=True,
            order=0,
        )
        db.session.add(img)
        db.session.commit()
        return car.public_id


def test_bare_r2_key_self_heals_to_full_url_when_r2_public_url_configured(app_ctx):
    """The core bug fix: a bare key (as if written while R2_PUBLIC_URL was
    missing) must resolve to a full URL now that R2_PUBLIC_URL is set,
    and must NOT be dropped from the images array."""
    app, client, _db, _User, _Car, _CarImage = app_ctx
    seller_id, _username = _make_user(app_ctx)
    bare_key = f"car_photos/u{uuid.uuid4().hex[:16]}/photo_{uuid.uuid4().hex[:8]}.jpg"
    car_public_id = _make_car_with_image(app_ctx, seller_id, bare_key)

    r = client.get(f"/api/cars/{car_public_id}")
    assert r.status_code == 200, r.data
    car = r.get_json()["car"]

    expected_full_url = f"https://cdn.example.com/{bare_key}"

    # Not dropped from the images array.
    assert car["images"], "image was silently dropped from the images array"
    assert car["images"][0]["image_url"] == expected_full_url

    # Primary image_url also resolves to the full URL, not the bare key.
    assert car["image_url"] == expected_full_url
    assert not car["image_url"].startswith("car_photos/")


def test_bare_r2_key_without_r2_public_url_configured_still_drops_safely(app_ctx):
    """Without R2_PUBLIC_URL configured, a bare key that also doesn't exist
    on local disk cannot be resolved to a real URL by `_resolve_rel` --
    `images` must still omit it (old, safe behavior; this fix must not
    fabricate a URL out of nothing). The separate, pre-existing
    `primary_rel = _resolve_rel(...) or raw_primary` fallback in
    `_with_media_compat` is unrelated to this fix and unchanged: it still
    surfaces the raw bare key on `image_url` rather than an empty string."""
    app, client, _db, _User, _Car, _CarImage = app_ctx
    seller_id, _username = _make_user(app_ctx)
    bare_key = f"car_photos/u{uuid.uuid4().hex[:16]}/photo_{uuid.uuid4().hex[:8]}.jpg"
    car_public_id = _make_car_with_image(app_ctx, seller_id, bare_key)

    original = app.config.get("R2_PUBLIC_URL")
    app.config["R2_PUBLIC_URL"] = ""
    try:
        r = client.get(f"/api/cars/{car_public_id}")
    finally:
        app.config["R2_PUBLIC_URL"] = original
    assert r.status_code == 200, r.data
    car = r.get_json()["car"]

    assert car["images"] == []
    assert car["image_url"] == bare_key


def test_absolute_https_url_passes_through_unchanged(app_ctx):
    """No regression to the already-correct, dominant production case."""
    app, client, _db, _User, _Car, _CarImage = app_ctx
    seller_id, _username = _make_user(app_ctx)
    full_url = f"https://cdn.example.com/car_photos/existing_{uuid.uuid4().hex[:8]}.jpg"
    car_public_id = _make_car_with_image(app_ctx, seller_id, full_url)

    r = client.get(f"/api/cars/{car_public_id}")
    assert r.status_code == 200, r.data
    car = r.get_json()["car"]

    assert car["images"][0]["image_url"] == full_url
    assert car["image_url"] == full_url


def test_real_local_relative_path_still_resolves_via_local_disk(app_ctx):
    """A genuinely local `uploads/car_photos/<file>` path that exists on
    disk must keep resolving via the local-disk branch, not be redirected
    through the new R2 fallback."""
    app, client, _db, _User, _Car, _CarImage = app_ctx
    seller_id, _username = _make_user(app_ctx)
    filename = f"local_{uuid.uuid4().hex[:8]}.jpg"
    rel = f"uploads/car_photos/{filename}"

    static_root = os.path.join(app.root_path, "static")
    abs_dir = os.path.join(static_root, "uploads", "car_photos")
    os.makedirs(abs_dir, exist_ok=True)
    abs_path = os.path.join(abs_dir, filename)
    with open(abs_path, "wb") as fh:
        fh.write(b"fake-jpeg-bytes")
    try:
        car_public_id = _make_car_with_image(app_ctx, seller_id, rel)
        r = client.get(f"/api/cars/{car_public_id}")
        assert r.status_code == 200, r.data
        car = r.get_json()["car"]

        assert car["images"][0]["image_url"] == rel
        assert car["image_url"] == rel
    finally:
        try:
            os.remove(abs_path)
        except OSError:
            pass
