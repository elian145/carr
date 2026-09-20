"""CarNet V1 feature-completeness batch 2 -- item 1 (edit listing: delete
photos/videos from backend/storage).

Bug: the sell wizard let a seller remove a photo/video from the in-memory
edit draft, but nothing ever told the backend to delete the corresponding
``CarImage``/``CarVideo`` row (or its underlying storage object), so a
"removed" photo/video silently stayed live on the server forever.

Fix: ``DELETE /api/cars/<car_id>/images/<image_id>`` and
``DELETE /api/cars/<car_id>/videos/<video_id>`` in ``kk/routes/media.py``.

Covers:
  * Ownership: only the listing's seller (or an admin) may delete its media;
    an image/video id that exists but belongs to a *different* car 404s
    (no IDOR) rather than deleting cross-listing.
  * DB row removed, storage object deletion attempted (R2 delete mocked;
    local-disk file actually removed on disk).
  * A storage-backend failure during deletion never blocks the DB delete
    (already-missing / unreachable storage object is handled safely).
  * The last remaining "listing" (non-damage) photo cannot be deleted (400
    guard) -- damage photos have no such minimum.
  * Deleting the current primary photo promotes the next remaining listing
    photo to primary so the listing's cover never disappears.
  * Video deletion has no minimum-count invariant (videos are optional).
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


# ---------------------------------------------------------------------------
# R2-backed app fixture (storage deletion is mocked; DB behavior is real).
# ---------------------------------------------------------------------------


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(
        prefix="carlist_cnv1b2_media_", ignore_cleanup_errors=True
    )
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "media_delete.db")
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

    from kk.models import Car, CarImage, CarVideo, User, db

    with app.app_context():
        db.drop_all()
        db.create_all()

    yield app, app.test_client(), db, User, Car, CarImage, CarVideo

    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    tmp.cleanup()


@pytest.fixture
def client(app_ctx):
    return app_ctx[1]


def _make_user(app_ctx, *, is_admin: bool = False) -> tuple[str, int, str]:
    app, _client, db, User, *_ = app_ctx
    username = f"cnv1b2_{uuid.uuid4().hex[:10]}"
    with app.app_context():
        user = User(
            username=username,
            phone_number=_unique_phone(),
            first_name="Media",
            last_name="Test",
            is_active=True,
            is_verified=True,
            phone_verified=True,
            is_admin=is_admin,
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


def _add_image(
    app_ctx,
    car_id: int,
    *,
    url: str,
    kind: str = "listing",
    is_primary: bool = False,
    order: int = 0,
) -> int:
    app, _client, db, _User, _Car, CarImage, _CarVideo = app_ctx
    with app.app_context():
        img = CarImage(
            car_id=car_id,
            image_url=url,
            kind=kind,
            is_primary=is_primary,
            order=order,
        )
        db.session.add(img)
        db.session.commit()
        return img.id


def _add_video(app_ctx, car_id: int, *, url: str) -> int:
    app, _client, db, _User, _Car, _CarImage, CarVideo = app_ctx
    with app.app_context():
        vid = CarVideo(car_id=car_id, video_url=url)
        db.session.add(vid)
        db.session.commit()
        return vid.id


def _seller(app_ctx, client):
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


def _image_exists(app_ctx, image_id: int) -> bool:
    app, _client, db, _User, _Car, CarImage, _CarVideo = app_ctx
    with app.app_context():
        return db.session.get(CarImage, image_id) is not None


def _video_exists(app_ctx, video_id: int) -> bool:
    app, _client, db, _User, _Car, _CarImage, CarVideo = app_ctx
    with app.app_context():
        return db.session.get(CarVideo, video_id) is not None


def _get_image(app_ctx, image_id: int):
    app, _client, db, _User, _Car, CarImage, _CarVideo = app_ctx
    with app.app_context():
        return db.session.get(CarImage, image_id)


# ---------------------------------------------------------------------------
# Ownership / IDOR
# ---------------------------------------------------------------------------


def test_delete_image_requires_ownership(app_ctx, client, monkeypatch):
    import kk.r2_ops as r2_ops_module

    monkeypatch.setattr(r2_ops_module, "r2_delete_object", lambda **_kw: None)

    owner = _seller(app_ctx, client)
    _other_public_id, _other_id, other_username = _make_user(app_ctx)
    other_token = _login(client, other_username)

    _add_image(app_ctx, owner["car_id"], url="https://cdn.example.com/car_photos/a.jpg", is_primary=True)
    img2 = _add_image(app_ctx, owner["car_id"], url="https://cdn.example.com/car_photos/b.jpg")

    r = client.delete(
        f"/api/cars/{owner['car_public_id']}/images/{img2}",
        headers=_auth(other_token),
    )
    assert r.status_code == 403, r.data
    assert _image_exists(app_ctx, img2) is True


def test_delete_image_404_for_image_on_a_different_car_no_idor(
    app_ctx, client, monkeypatch
):
    import kk.r2_ops as r2_ops_module

    monkeypatch.setattr(r2_ops_module, "r2_delete_object", lambda **_kw: None)

    seller_a = _seller(app_ctx, client)
    seller_b = _seller(app_ctx, client)
    _add_image(app_ctx, seller_a["car_id"], url="https://cdn.example.com/car_photos/a1.jpg", is_primary=True)
    image_on_a = _add_image(
        app_ctx, seller_a["car_id"], url="https://cdn.example.com/car_photos/a2.jpg"
    )

    # seller_b guesses/knows an image id that actually belongs to seller_a's
    # car, but addresses it via seller_b's own car id.
    r = client.delete(
        f"/api/cars/{seller_b['car_public_id']}/images/{image_on_a}",
        headers=_auth(seller_b["token"]),
    )
    assert r.status_code == 404, r.data
    assert _image_exists(app_ctx, image_on_a) is True


def test_admin_can_delete_another_users_image(app_ctx, client, monkeypatch):
    import kk.r2_ops as r2_ops_module

    monkeypatch.setattr(r2_ops_module, "r2_delete_object", lambda **_kw: None)

    seller = _seller(app_ctx, client)
    _add_image(app_ctx, seller["car_id"], url="https://cdn.example.com/car_photos/p1.jpg", is_primary=True)
    img2 = _add_image(app_ctx, seller["car_id"], url="https://cdn.example.com/car_photos/p2.jpg")

    _admin_public_id, _admin_id, admin_username = _make_user(app_ctx, is_admin=True)
    admin_token = _login(client, admin_username)

    r = client.delete(
        f"/api/cars/{seller['car_public_id']}/images/{img2}",
        headers=_auth(admin_token),
    )
    assert r.status_code == 200, r.data
    assert _image_exists(app_ctx, img2) is False


# ---------------------------------------------------------------------------
# DB row + storage deletion
# ---------------------------------------------------------------------------


def test_delete_image_removes_db_row_and_calls_r2_delete_with_key(
    app_ctx, client, monkeypatch
):
    import kk.r2_ops as r2_ops_module

    calls = []
    monkeypatch.setattr(
        r2_ops_module, "r2_delete_object", lambda **kw: calls.append(kw)
    )

    ctx = _seller(app_ctx, client)
    _add_image(app_ctx, ctx["car_id"], url="https://cdn.example.com/car_photos/keep.jpg", is_primary=True)
    img2 = _add_image(
        app_ctx, ctx["car_id"], url="https://cdn.example.com/car_photos/delete-me.jpg"
    )

    r = client.delete(
        f"/api/cars/{ctx['car_public_id']}/images/{img2}",
        headers=_auth(ctx["token"]),
    )
    assert r.status_code == 200, r.data
    assert _image_exists(app_ctx, img2) is False
    assert calls == [{"key": "car_photos/delete-me.jpg"}]


def test_delete_image_storage_failure_does_not_block_db_delete(
    app_ctx, client, monkeypatch
):
    import kk.r2_ops as r2_ops_module

    def _boom(**_kw):
        raise RuntimeError("simulated R2 outage")

    monkeypatch.setattr(r2_ops_module, "r2_delete_object", _boom)

    ctx = _seller(app_ctx, client)
    _add_image(app_ctx, ctx["car_id"], url="https://cdn.example.com/car_photos/keep2.jpg", is_primary=True)
    img2 = _add_image(
        app_ctx, ctx["car_id"], url="https://cdn.example.com/car_photos/gone.jpg"
    )

    r = client.delete(
        f"/api/cars/{ctx['car_public_id']}/images/{img2}",
        headers=_auth(ctx["token"]),
    )
    assert r.status_code == 200, r.data
    assert _image_exists(app_ctx, img2) is False


def test_delete_video_removes_db_row_and_calls_r2_delete(
    app_ctx, client, monkeypatch
):
    import kk.r2_ops as r2_ops_module

    calls = []
    monkeypatch.setattr(
        r2_ops_module, "r2_delete_object", lambda **kw: calls.append(kw)
    )

    ctx = _seller(app_ctx, client)
    video_id = _add_video(
        app_ctx, ctx["car_id"], url="https://cdn.example.com/car_videos/clip.mp4"
    )

    r = client.delete(
        f"/api/cars/{ctx['car_public_id']}/videos/{video_id}",
        headers=_auth(ctx["token"]),
    )
    assert r.status_code == 200, r.data
    assert _video_exists(app_ctx, video_id) is False
    assert calls == [{"key": "car_videos/clip.mp4"}]


def test_delete_video_requires_ownership(app_ctx, client, monkeypatch):
    import kk.r2_ops as r2_ops_module

    monkeypatch.setattr(r2_ops_module, "r2_delete_object", lambda **_kw: None)

    ctx = _seller(app_ctx, client)
    video_id = _add_video(
        app_ctx, ctx["car_id"], url="https://cdn.example.com/car_videos/mine.mp4"
    )
    _other_public_id, _other_id, other_username = _make_user(app_ctx)
    other_token = _login(client, other_username)

    r = client.delete(
        f"/api/cars/{ctx['car_public_id']}/videos/{video_id}",
        headers=_auth(other_token),
    )
    assert r.status_code == 403, r.data
    assert _video_exists(app_ctx, video_id) is True


# ---------------------------------------------------------------------------
# Minimum-photo invariant + primary reassignment
# ---------------------------------------------------------------------------


def test_cannot_delete_the_last_remaining_listing_photo(app_ctx, client, monkeypatch):
    import kk.r2_ops as r2_ops_module

    monkeypatch.setattr(r2_ops_module, "r2_delete_object", lambda **_kw: None)

    ctx = _seller(app_ctx, client)
    only_image = _add_image(
        app_ctx,
        ctx["car_id"],
        url="https://cdn.example.com/car_photos/only.jpg",
        is_primary=True,
    )

    r = client.delete(
        f"/api/cars/{ctx['car_public_id']}/images/{only_image}",
        headers=_auth(ctx["token"]),
    )
    assert r.status_code == 400, r.data
    assert _image_exists(app_ctx, only_image) is True


def test_damage_photo_has_no_minimum_count_invariant(app_ctx, client, monkeypatch):
    import kk.r2_ops as r2_ops_module

    monkeypatch.setattr(r2_ops_module, "r2_delete_object", lambda **_kw: None)

    ctx = _seller(app_ctx, client)
    # Listing photo present (unrelated to the damage-photo count).
    _add_image(
        app_ctx, ctx["car_id"], url="https://cdn.example.com/car_photos/listing.jpg", is_primary=True
    )
    only_damage = _add_image(
        app_ctx,
        ctx["car_id"],
        url="https://cdn.example.com/car_photos/damage-only.jpg",
        kind="damage",
    )

    r = client.delete(
        f"/api/cars/{ctx['car_public_id']}/images/{only_damage}",
        headers=_auth(ctx["token"]),
    )
    assert r.status_code == 200, r.data
    assert _image_exists(app_ctx, only_damage) is False


def test_deleting_primary_photo_promotes_next_remaining_photo(
    app_ctx, client, monkeypatch
):
    import kk.r2_ops as r2_ops_module

    monkeypatch.setattr(r2_ops_module, "r2_delete_object", lambda **_kw: None)

    ctx = _seller(app_ctx, client)
    primary = _add_image(
        app_ctx,
        ctx["car_id"],
        url="https://cdn.example.com/car_photos/cover.jpg",
        is_primary=True,
        order=0,
    )
    second = _add_image(
        app_ctx,
        ctx["car_id"],
        url="https://cdn.example.com/car_photos/second.jpg",
        is_primary=False,
        order=1,
    )

    r = client.delete(
        f"/api/cars/{ctx['car_public_id']}/images/{primary}",
        headers=_auth(ctx["token"]),
    )
    assert r.status_code == 200, r.data
    assert _image_exists(app_ctx, primary) is False

    remaining = _get_image(app_ctx, second)
    assert remaining is not None
    assert remaining.is_primary is True


# ---------------------------------------------------------------------------
# Local-disk storage deletion (no R2 configured)
# ---------------------------------------------------------------------------


@pytest.fixture(scope="module")
def local_app_ctx():
    tmp = tempfile.TemporaryDirectory(
        prefix="carlist_cnv1b2_media_local_", ignore_cleanup_errors=True
    )
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "media_delete_local.db")
    os.environ["UPLOAD_FOLDER"] = os.path.join(tmp.name, "uploads")
    for key in (
        "R2_PUBLIC_URL",
        "R2_ACCOUNT_ID",
        "R2_BUCKET_NAME",
        "R2_ACCESS_KEY_ID",
        "R2_SECRET_ACCESS_KEY",
    ):
        os.environ.pop(key, None)

    from kk.app_factory import create_app

    app, _socketio, *_ = create_app()
    for key in (
        "R2_PUBLIC_URL",
        "R2_ACCOUNT_ID",
        "R2_BUCKET_NAME",
        "R2_ACCESS_KEY_ID",
        "R2_SECRET_ACCESS_KEY",
    ):
        app.config.pop(key, None)

    from kk.models import Car, CarImage, CarVideo, User, db

    with app.app_context():
        db.drop_all()
        db.create_all()

    yield app, app.test_client(), db, User, Car, CarImage, CarVideo

    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    tmp.cleanup()


def test_delete_image_removes_local_disk_file(local_app_ctx):
    app, client, db, User, Car, CarImage, _CarVideo = local_app_ctx

    username = f"cnv1b2_local_{uuid.uuid4().hex[:10]}"
    with app.app_context():
        user = User(
            username=username,
            phone_number=_unique_phone(),
            first_name="Local",
            last_name="Test",
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id=f"pub-{uuid.uuid4().hex[:12]}",
        )
        user.set_password(_PASSWORD)
        db.session.add(user)
        db.session.commit()
        seller_id = user.id

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
        car_id = car.id
        car_public_id = car.public_id

        upload_root = app.config["UPLOAD_FOLDER"]
        photos_dir = os.path.join(upload_root, "car_photos")
        os.makedirs(photos_dir, exist_ok=True)
        filename = f"local_{uuid.uuid4().hex[:8]}.jpg"
        abs_path = os.path.join(photos_dir, filename)
        with open(abs_path, "wb") as fh:
            fh.write(b"fake-jpeg-bytes")
        rel_url = f"uploads/car_photos/{filename}"

        keep = CarImage(
            car_id=car_id, image_url="uploads/car_photos/keep.jpg", is_primary=True
        )
        target = CarImage(car_id=car_id, image_url=rel_url, is_primary=False)
        db.session.add_all([keep, target])
        db.session.commit()
        target_id = target.id

    token = _login(client, username)

    assert os.path.isfile(abs_path)

    r = client.delete(
        f"/api/cars/{car_public_id}/images/{target_id}",
        headers=_auth(token),
    )
    assert r.status_code == 200, r.data
    assert not os.path.isfile(abs_path), "local storage file must be removed"

    with app.app_context():
        assert db.session.get(CarImage, target_id) is None


def test_delete_image_missing_local_file_is_handled_safely(local_app_ctx):
    """The DB row references a local file that is already gone (e.g. a
    prior manual cleanup / retry) -- deletion must still succeed, not 500."""
    app, client, db, User, Car, CarImage, _CarVideo = local_app_ctx

    username = f"cnv1b2_localmiss_{uuid.uuid4().hex[:10]}"
    with app.app_context():
        user = User(
            username=username,
            phone_number=_unique_phone(),
            first_name="LocalMiss",
            last_name="Test",
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id=f"pub-{uuid.uuid4().hex[:12]}",
        )
        user.set_password(_PASSWORD)
        db.session.add(user)
        db.session.commit()
        seller_id = user.id

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
        car_id = car.id
        car_public_id = car.public_id

        keep = CarImage(
            car_id=car_id, image_url="uploads/car_photos/keep2.jpg", is_primary=True
        )
        target = CarImage(
            car_id=car_id,
            image_url="uploads/car_photos/already-gone.jpg",
            is_primary=False,
        )
        db.session.add_all([keep, target])
        db.session.commit()
        target_id = target.id

    token = _login(client, username)

    r = client.delete(
        f"/api/cars/{car_public_id}/images/{target_id}",
        headers=_auth(token),
    )
    assert r.status_code == 200, r.data
    with app.app_context():
        assert db.session.get(CarImage, target_id) is None
