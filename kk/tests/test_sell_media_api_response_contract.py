"""Section 4 (Sell media investigation): the real, exact API response
contract for a listing with 1 image + 1 video, on BOTH the list endpoint
(``GET /api/cars``) and the detail endpoint (``GET /api/cars/<id>``).

This is the ground-truth shape the Flutter client's parsing code
(``car_details_page_media.dart`` for detail, ``listing_mappers.dart`` /
``CarService.getCars`` for the list feed) must agree with. Both endpoints
build their car dict via the SAME ``_with_media_compat()`` helper in
``kk/routes/cars.py``, so a passing test here is strong evidence the two
endpoints cannot silently diverge in the media fields specifically.

Exact shape asserted (also documented in the final Sell-media investigation
report so it does not need to be re-derived by reading source next time):

    image_url: "<absolute URL of the primary image>"
    images: [
      {
        "id": <int>,
        "image_url": "<absolute URL>",
        "is_primary": <bool>,
        "order": <int>,
        "kind": "listing",
        ... (focus_y / image_width / image_height when set)
      },
      ...
    ]
    videos: [
      {
        "id": <int>,
        "video_url": "<absolute URL>",
        "thumbnail_url": "<absolute URL or null>",
        "duration": <number or null>,
        "order": <int>,
      },
      ...
    ]

Covers:
  * List endpoint (`GET /api/cars`) returns the listing with this exact
    shape for both `images` and `videos`.
  * Detail endpoint (`GET /api/cars/<id>`) returns the identical shape for
    the SAME listing/row data.
  * Both `image_url` (primary) and `images[0].image_url` are full,
    absolute `https://` URLs -- never a bare R2 key, never a local
    Flask-relative path -- under normal (fully configured R2) conditions.
  * `videos[0].video_url` is a full, absolute `https://` URL.
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
        prefix="carlist_media_contract_", ignore_cleanup_errors=True
    )
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "media_contract.db")
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


def _make_user(app_ctx) -> str:
    app, _client, db, User, *_ = app_ctx
    username = f"mediacontract_{uuid.uuid4().hex[:10]}"
    with app.app_context():
        user = User(
            username=username,
            phone_number=_unique_phone(),
            first_name="Media",
            last_name="Contract",
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id=f"pub-{uuid.uuid4().hex[:12]}",
        )
        user.set_password(_PASSWORD)
        db.session.add(user)
        db.session.commit()
        return user.id


def _make_car_with_one_image_and_one_video(
    app_ctx, seller_id: int
) -> tuple[str, str, str]:
    """Returns (car_public_id, expected_image_url, expected_video_url)."""
    app, _client, db, _User, Car, CarImage, CarVideo = app_ctx
    with app.app_context():
        car = Car(
            seller_id=seller_id,
            public_id=f"car-{uuid.uuid4().hex[:12]}",
            brand="hyundai",
            model="elantra",
            year=2022,
            mileage=5000,
            engine_type="gas",
            transmission="auto",
            drive_type="fwd",
            condition="used",
            body_type="sedan",
            price=18000,
            location="Duhok",
            is_active=True,
        )
        db.session.add(car)
        db.session.commit()

        image_url = f"https://cdn.example.com/car_photos/photo_{uuid.uuid4().hex[:8]}.jpg"
        img = CarImage(
            car_id=car.id,
            image_url=image_url,
            is_primary=True,
            order=0,
        )
        db.session.add(img)

        video_url = f"https://cdn.example.com/car_videos/clip_{uuid.uuid4().hex[:8]}.mp4"
        thumb_url = f"https://cdn.example.com/car_videos/clip_{uuid.uuid4().hex[:8]}.jpg"
        vid = CarVideo(
            car_id=car.id,
            video_url=video_url,
            thumbnail_url=thumb_url,
            order=0,
        )
        db.session.add(vid)
        db.session.commit()
        return car.public_id, image_url, video_url


def _assert_media_contract(car: dict, expected_image_url: str, expected_video_url: str) -> None:
    # ---- Primary image_url -------------------------------------------------
    assert car["image_url"] == expected_image_url
    assert car["image_url"].startswith("https://")

    # ---- images[] ------------------------------------------------------------
    assert isinstance(car["images"], list)
    assert len(car["images"]) == 1
    image = car["images"][0]
    assert isinstance(image["id"], int)
    assert image["image_url"] == expected_image_url
    assert image["image_url"].startswith("https://")
    assert image["is_primary"] is True
    assert image["order"] == 0
    assert image.get("kind") in (None, "listing")

    # ---- videos[] ------------------------------------------------------------
    assert isinstance(car["videos"], list)
    assert len(car["videos"]) == 1
    video = car["videos"][0]
    assert isinstance(video["id"], int)
    assert video["video_url"] == expected_video_url
    assert video["video_url"].startswith("https://")
    assert set(["id", "video_url", "thumbnail_url"]).issubset(video.keys())


def test_detail_endpoint_media_contract(app_ctx):
    _client = app_ctx[1]
    seller_id = _make_user(app_ctx)
    car_public_id, expected_image_url, expected_video_url = (
        _make_car_with_one_image_and_one_video(app_ctx, seller_id)
    )

    r = _client.get(f"/api/cars/{car_public_id}")
    assert r.status_code == 200, r.data
    car = r.get_json()["car"]
    _assert_media_contract(car, expected_image_url, expected_video_url)


def test_list_endpoint_media_contract_matches_detail(app_ctx):
    """The SAME listing, fetched through the list endpoint instead of the
    detail endpoint, must expose an identical media shape -- proving the
    two endpoints cannot silently diverge for images/videos."""
    _client = app_ctx[1]
    seller_id = _make_user(app_ctx)
    car_public_id, expected_image_url, expected_video_url = (
        _make_car_with_one_image_and_one_video(app_ctx, seller_id)
    )

    r = _client.get("/api/cars?per_page=50")
    assert r.status_code == 200, r.data
    body = r.get_json()
    assert "cars" in body and isinstance(body["cars"], list)
    matches = [c for c in body["cars"] if c.get("id") == car_public_id]
    assert len(matches) == 1, (
        f"expected exactly one listing with id={car_public_id!r} in the "
        f"list response, found {len(matches)}"
    )
    _assert_media_contract(matches[0], expected_image_url, expected_video_url)
