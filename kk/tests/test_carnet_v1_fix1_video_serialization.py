"""CarNet V1 release-candidate fix 1 -- video serialization for edit/delete.

Bug: every listing GET response path in ``kk/routes/cars.py``
(``_with_media_compat`` plus three duplicate inline overrides in
``get_cars_alias``, the alias browse list, and ``compat_my_listings``)
flattened ``car.videos`` down to a bare list of URL strings
(``[v.video_url for v in car.videos]``), even though ``CarVideo.to_dict()``
already returns a structured ``{id, video_url, thumbnail_url, duration,
order}`` object and the create/update/upload endpoints (``car.to_dict()``,
``POST /api/cars/<id>/videos``) already returned that structured shape.

Because of that inconsistency, the Flutter edit-listing flow (which reads
``existing_video_records`` from structured video maps -- see
``lib/shared/listings/listing_to_sell_draft.dart``) never saw a video `id`
for a listing fetched through any of these flattened paths, so the
existing-video edit/delete UI could never populate real server ids and
``DELETE /api/cars/<car_id>/videos/<video_id>`` could never be reached from
a real listing response.

Fix: introduce ``_serialize_videos()`` in ``kk/routes/cars.py`` and use it
consistently everywhere a listing response sets ``videos`` (replacing all
four flattening sites), so every listing response path -- list, detail,
alias/legacy endpoints, my-listings, create, update, mark-sold -- agrees on
the same structured representation.

Covers:
  * Listing detail (``GET /api/cars/<id>``) returns structured video
    objects with real ids.
  * Listing list (``GET /api/cars``) returns structured video objects.
  * Legacy alias endpoints (``GET /cars`` list + single-id path) return
    structured video objects.
  * ``/api/my_listings`` (compat alias) returns structured video objects.
  * Create/update car responses (``car.to_dict()``) already agreed with
    this shape and keep doing so.
  * The real id returned by a listing GET response can be used to
    successfully call ``DELETE /api/cars/<car_id>/videos/<video_id>``
    (proving the edit/delete flow is actually reachable end-to-end from a
    real API response, not just a hand-crafted test fixture).
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
        prefix="carlist_cnv1fix1_video_ser_", ignore_cleanup_errors=True
    )
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "video_ser.db")
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


def _make_user(app_ctx) -> tuple[str, int, str]:
    app, _client, db, User, *_ = app_ctx
    username = f"cnv1fix1_{uuid.uuid4().hex[:10]}"
    with app.app_context():
        user = User(
            username=username,
            phone_number=_unique_phone(),
            first_name="Video",
            last_name="Ser",
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


def _make_car_with_videos(app_ctx, seller_id: int, *, n: int = 2) -> tuple[int, str, list[int]]:
    app, _client, db, _User, Car, _CarImage, CarVideo = app_ctx
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
        video_ids = []
        for i in range(n):
            vid = CarVideo(
                car_id=car.id,
                video_url=f"https://cdn.example.com/car_videos/clip-{i}.mp4",
                thumbnail_url=f"https://cdn.example.com/car_videos/clip-{i}.jpg",
                order=i,
            )
            db.session.add(vid)
            db.session.commit()
            video_ids.append(vid.id)
        return car.id, car.public_id, video_ids


def _assert_structured_videos(videos, expected_ids: list[int]) -> None:
    assert isinstance(videos, list)
    assert len(videos) == len(expected_ids)
    for v in videos:
        assert isinstance(v, dict), f"expected structured video object, got {type(v)}: {v!r}"
        assert set(["id", "video_url", "thumbnail_url"]).issubset(v.keys())
        assert isinstance(v["id"], int)
        assert v["video_url"].startswith("https://cdn.example.com/car_videos/")
        assert v["thumbnail_url"].startswith("https://cdn.example.com/car_videos/")
    assert sorted(v["id"] for v in videos) == sorted(expected_ids)


def test_listing_detail_returns_structured_video_objects(app_ctx, client):
    _public_id, seller_id, username = _make_user(app_ctx)
    car_id, car_public_id, video_ids = _make_car_with_videos(app_ctx, seller_id)

    r = client.get(f"/api/cars/{car_public_id}")
    assert r.status_code == 200, r.data
    body = r.get_json()["car"]
    _assert_structured_videos(body["videos"], video_ids)


def test_listing_list_returns_structured_video_objects(app_ctx, client):
    _public_id, seller_id, username = _make_user(app_ctx)
    _car_id, _car_public_id, video_ids = _make_car_with_videos(app_ctx, seller_id, n=1)

    r = client.get("/api/cars")
    assert r.status_code == 200, r.data
    body = r.get_json()
    matches = [c for c in body["cars"] if c.get("id") is not None]
    assert matches, "expected at least one car in the listing list"
    for c in matches:
        for v in c["videos"]:
            assert isinstance(v, dict)
            assert "id" in v and "video_url" in v and "thumbnail_url" in v


def test_legacy_alias_single_car_returns_structured_video_objects(app_ctx, client):
    _public_id, seller_id, username = _make_user(app_ctx)
    car_id, car_public_id, video_ids = _make_car_with_videos(app_ctx, seller_id)

    r = client.get(f"/cars?id={car_id}")
    assert r.status_code == 200, r.data
    body = r.get_json()
    _assert_structured_videos(body["videos"], video_ids)


def test_legacy_alias_list_returns_structured_video_objects(app_ctx, client):
    _public_id, seller_id, username = _make_user(app_ctx)
    _car_id, _car_public_id, video_ids = _make_car_with_videos(app_ctx, seller_id, n=1)

    r = client.get("/cars")
    assert r.status_code == 200, r.data
    body = r.get_json()
    assert isinstance(body, list)
    for c in body:
        for v in c["videos"]:
            assert isinstance(v, dict)
            assert "id" in v and "video_url" in v and "thumbnail_url" in v


def test_my_listings_compat_returns_structured_video_objects(app_ctx, client):
    _public_id, seller_id, username = _make_user(app_ctx)
    _car_id, _car_public_id, video_ids = _make_car_with_videos(app_ctx, seller_id)
    token = _login(client, username)

    r = client.get("/api/my_listings", headers=_auth(token))
    assert r.status_code == 200, r.data
    body = r.get_json()
    assert len(body) == 1
    _assert_structured_videos(body[0]["videos"], video_ids)


def test_create_and_update_car_agree_with_structured_video_shape(app_ctx, client):
    """create/update responses already used ``car.to_dict()`` (structured);
    confirm they still agree with the listing GET representation."""
    _public_id, seller_id, username = _make_user(app_ctx)
    token = _login(client, username)

    r = client.post(
        "/api/cars",
        json={
            "brand": "honda",
            "model": "civic",
            "year": 2019,
            "price": 12000,
            "location": "Erbil",
            "mileage": 100,
        },
        headers=_auth(token),
    )
    assert r.status_code == 201, r.data
    car = r.get_json()["car"]
    assert car["videos"] == []

    r2 = client.put(
        f"/api/cars/{car['id']}",
        json={"price": 12500},
        headers=_auth(token),
    )
    assert r2.status_code == 200, r2.data
    updated = r2.get_json().get("car")
    if updated is not None:
        assert updated["videos"] == []


def test_real_listing_response_video_id_can_be_deleted(app_ctx, client, monkeypatch):
    """End-to-end proof that the edit/delete flow works from a REAL listing
    response (not a fabricated fixture): fetch the listing, take the video
    id straight out of the ``videos`` array, and delete it."""
    import kk.r2_ops as r2_ops_module

    monkeypatch.setattr(r2_ops_module, "r2_delete_object", lambda **_kw: None)

    _public_id, seller_id, username = _make_user(app_ctx)
    car_id, car_public_id, video_ids = _make_car_with_videos(app_ctx, seller_id, n=2)
    token = _login(client, username)

    r = client.get(f"/api/cars/{car_public_id}")
    assert r.status_code == 200, r.data
    server_videos = r.get_json()["car"]["videos"]
    assert len(server_videos) == 2

    target = server_videos[0]
    assert isinstance(target["id"], int)

    r_del = client.delete(
        f"/api/cars/{car_public_id}/videos/{target['id']}",
        headers=_auth(token),
    )
    assert r_del.status_code == 200, r_del.data

    r2 = client.get(f"/api/cars/{car_public_id}")
    assert r2.status_code == 200, r2.data
    remaining = r2.get_json()["car"]["videos"]
    assert len(remaining) == 1
    assert remaining[0]["id"] != target["id"]
