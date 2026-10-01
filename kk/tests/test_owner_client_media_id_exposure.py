"""Optimistic-local-media fix (Flutter `OwnerMediaOverlay` exact-identity
reconciliation): `GET /api/cars/<id>` must expose each image/video's
`client_media_id` (`CarImage.source_media_id` / `CarVideo.
source_draft_media_id` -- already durably stored at self-attach time, see
`kk/media_readiness.py`, but never previously surfaced in any response)
to the LISTING OWNER (or an admin) ONLY -- never to a public/non-owner
viewer, and never for legacy rows that predate the client_media_id
concept (`None`, which the Flutter overlay already treats as "fall back
to positional pairing").

Same fixture/self-attach technique as
`test_five_image_self_attach_serialization.py` (direct `.run()` calls,
no Celery broker needed), plus a real login flow (same pattern as
`test_media_readiness_manifest.py`'s `_login`/`_auth`) to exercise the
REAL `include_private` ownership gate in `kk/routes/cars.py::get_car`.
"""

from __future__ import annotations

import os
import sys
import tempfile
import uuid
from io import BytesIO
from pathlib import Path

import pytest
import PIL.Image as PILImage

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

_PASSWORD = "Aa123456!"


def _distinct_image_bytes(seed: int) -> bytes:
    im = PILImage.new(
        "RGB", (24, 24), color=((seed * 37) % 256, (seed * 61) % 256, (seed * 89) % 256)
    )
    buf = BytesIO()
    im.save(buf, format="JPEG", quality=90)
    return buf.getvalue()


def _write_temp(tmp_path, data: bytes, name: str) -> str:
    p = str(tmp_path / name)
    with open(p, "wb") as fh:
        fh.write(data)
    return p


@pytest.fixture()
def app_ctx():
    tmp = tempfile.TemporaryDirectory(
        prefix="carlist_owner_client_media_id_", ignore_cleanup_errors=True
    )
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "owner_client_media_id.db")
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

    from kk.models import Car, CarImage, CarMediaItem, CarVideo, User, db

    with app.app_context():
        db.drop_all()
        db.create_all()

    yield app, app.test_client(), db, User, Car, CarImage, CarVideo, CarMediaItem

    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    tmp.cleanup()


@pytest.fixture(autouse=True)
def _no_real_r2_network(monkeypatch):
    monkeypatch.setattr("kk.r2_ops.r2_put_bytes", lambda **kwargs: None)


def _unique_phone() -> str:
    return f"078{uuid.uuid4().int % 10**8:08d}"


def _make_user(app_ctx, *, tag: str):
    app, _client, db, User, *_ = app_ctx
    with app.app_context():
        user = User(
            username=f"u_{tag}_{uuid.uuid4().hex[:10]}",
            phone_number=_unique_phone(),
            first_name="Test",
            last_name=tag,
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id=f"u-{tag}-{uuid.uuid4().hex[:12]}",
        )
        user.set_password(_PASSWORD)
        db.session.add(user)
        db.session.commit()
        return user.id, user.username


def _login(client, username: str) -> str:
    r = client.post(
        "/api/auth/login", json={"username": username, "password": _PASSWORD}
    )
    assert r.status_code == 200, r.data
    return r.get_json()["access_token"]


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _make_car_with_media(app_ctx, tmp_path, *, seller_id: int):
    """One self-attached image (via the real Celery-task-run path, exactly
    like `test_five_image_self_attach_serialization.py`) with a known
    `client_media_id`, one legacy image with no `client_media_id`
    (source_media_id NULL), and one video row with a known
    `client_media_id` inserted directly (serialization-only concern, the
    attach pipeline itself is already covered elsewhere)."""
    app, _client, db, _User, Car, CarImage, CarVideo, CarMediaItem = app_ctx
    from kk.tasks.image_tasks import process_car_image_file

    with app.app_context():
        car = Car(
            seller_id=seller_id,
            public_id=f"car-{uuid.uuid4().hex[:12]}",
            brand="toyota",
            model="camry",
            year=2020,
            mileage=1000,
            engine_type="gas",
            transmission="auto",
            drive_type="fwd",
            condition="used",
            body_type="sedan",
            price=20000,
            location="Erbil",
            is_active=True,
        )
        db.session.add(car)
        db.session.commit()
        car_id, car_public_id = car.id, car.public_id

        client_media_id = f"img_{uuid.uuid4().hex[:16]}"
        db.session.add(
            CarMediaItem(
                car_id=car_id,
                kind="image",
                client_media_id=client_media_id,
                status="awaiting_upload",
            )
        )
        db.session.commit()

    temp_abs = _write_temp(tmp_path, _distinct_image_bytes(0), "photo_0.jpg")
    with app.app_context():
        process_car_image_file.run(
            temp_abs,
            "photo_0.jpg",
            False,
            True,  # skip_blur
            owner_public_id=None,
            source_r2_key=None,
            car_id=car_id,
            kind="listing",
            client_media_id=client_media_id,
        )

    with app.app_context():
        # Legacy image row: attached via the older client-driven path,
        # source_media_id NULL -- must never crash/produce a fake id.
        db.session.add(
            CarImage(
                car_id=car_id,
                image_url="https://cdn.example.com/car_photos/legacy.jpg",
                is_primary=False,
                order=1,
                kind="listing",
                source_media_id=None,
            )
        )
        video_client_media_id = f"vid_{uuid.uuid4().hex[:16]}"
        db.session.add(
            CarVideo(
                car_id=car_id,
                video_url="https://cdn.example.com/car_videos/clip.mp4",
                order=0,
                source_draft_media_id=video_client_media_id,
            )
        )
        db.session.commit()

    return car_public_id, client_media_id, video_client_media_id


class TestOwnerOnlyClientMediaIdExposure:
    def test_owner_sees_client_media_id_for_image_and_video(
        self, app_ctx, tmp_path
    ):
        app, client, db, User, Car, CarImage, CarVideo, CarMediaItem = app_ctx
        seller_id, seller_username = _make_user(app_ctx, tag="seller")
        car_public_id, image_cmid, video_cmid = _make_car_with_media(
            app_ctx, tmp_path, seller_id=seller_id
        )

        token = _login(client, seller_username)
        resp = client.get(f"/api/cars/{car_public_id}", headers=_auth(token))
        assert resp.status_code == 200, resp.data
        car = resp.get_json()["car"]

        images_by_url = {img["image_url"]: img for img in car["images"]}
        self_attached = [
            img for img in car["images"] if img.get("client_media_id") == image_cmid
        ]
        assert len(self_attached) == 1, (
            f"expected exactly 1 image with client_media_id={image_cmid!r}, "
            f"got: {car['images']}"
        )
        legacy = images_by_url["https://cdn.example.com/car_photos/legacy.jpg"]
        assert legacy.get("client_media_id") is None, (
            "a legacy (no source_media_id) image must serialize "
            "client_media_id as null, never a fabricated value"
        )

        assert len(car["videos"]) == 1
        assert car["videos"][0]["client_media_id"] == video_cmid

    def test_non_owner_never_sees_client_media_id(self, app_ctx, tmp_path):
        app, client, db, User, Car, CarImage, CarVideo, CarMediaItem = app_ctx
        seller_id, _seller_username = _make_user(app_ctx, tag="seller2")
        other_id, other_username = _make_user(app_ctx, tag="buyer")
        car_public_id, image_cmid, video_cmid = _make_car_with_media(
            app_ctx, tmp_path, seller_id=seller_id
        )

        token = _login(client, other_username)
        resp = client.get(f"/api/cars/{car_public_id}", headers=_auth(token))
        assert resp.status_code == 200, resp.data
        car = resp.get_json()["car"]

        for img in car["images"]:
            assert "client_media_id" not in img, (
                "a non-owner must never see client_media_id, even for an "
                f"image that genuinely has one ({image_cmid}): {img}"
            )
        for vid in car["videos"]:
            assert "client_media_id" not in vid, (
                f"a non-owner must never see client_media_id ({video_cmid}): "
                f"{vid}"
            )

    def test_unauthenticated_viewer_never_sees_client_media_id(
        self, app_ctx, tmp_path
    ):
        app, client, db, User, Car, CarImage, CarVideo, CarMediaItem = app_ctx
        seller_id, _seller_username = _make_user(app_ctx, tag="seller3")
        car_public_id, _image_cmid, _video_cmid = _make_car_with_media(
            app_ctx, tmp_path, seller_id=seller_id
        )

        resp = client.get(f"/api/cars/{car_public_id}")
        assert resp.status_code == 200, resp.data
        car = resp.get_json()["car"]

        for img in car["images"]:
            assert "client_media_id" not in img
        for vid in car["videos"]:
            assert "client_media_id" not in vid

    def test_legacy_rows_with_null_client_media_id_keep_a_valid_response(
        self, app_ctx, tmp_path
    ):
        """Required contract check: a response containing legacy rows
        (`client_media_id` is `None`) must remain a fully valid,
        well-formed `car` payload -- every other expected field still
        present, correct types, 200 status -- never a partial/malformed
        response just because one or more media rows predate
        `client_media_id`."""
        app, client, db, User, Car, CarImage, CarVideo, CarMediaItem = app_ctx
        seller_id, seller_username = _make_user(app_ctx, tag="seller_legacy")
        car_public_id, image_cmid, video_cmid = _make_car_with_media(
            app_ctx, tmp_path, seller_id=seller_id
        )

        token = _login(client, seller_username)
        resp = client.get(f"/api/cars/{car_public_id}", headers=_auth(token))
        assert resp.status_code == 200, resp.data
        car = resp.get_json()["car"]

        # The legacy image (source_media_id=None) must still carry every
        # other expected field, correctly typed, alongside its null
        # client_media_id -- not a stripped-down/partial row.
        images_by_url = {img["image_url"]: img for img in car["images"]}
        legacy = images_by_url["https://cdn.example.com/car_photos/legacy.jpg"]
        assert legacy["client_media_id"] is None
        assert isinstance(legacy["id"], int)
        assert isinstance(legacy["order"], int)
        assert legacy["kind"] == "listing"
        assert "is_primary" in legacy

        # The whole payload is still well-formed: both rows present, the
        # self-attached (id-bearing) row is untouched by the legacy row's
        # null id.
        assert len(car["images"]) == 2
        self_attached = [
            img for img in car["images"] if img["image_url"] != legacy["image_url"]
        ]
        assert len(self_attached) == 1
        assert self_attached[0]["client_media_id"] == image_cmid

        assert len(car["videos"]) == 1
        assert car["videos"][0]["client_media_id"] == video_cmid
        assert isinstance(car["videos"][0]["id"], int)

    def test_media_ordering_unchanged_by_client_media_id_exposure(
        self, app_ctx, tmp_path
    ):
        """Required contract check: adding `client_media_id` must never
        reorder `images`/`videos` -- same order for the owner (who now
        sees the extra field) and a non-owner (who does not), and videos
        keep their existing `(order, id)` sort exactly as before."""
        app, client, db, User, Car, CarImage, CarVideo, CarMediaItem = app_ctx
        seller_id, seller_username = _make_user(app_ctx, tag="seller_order")
        buyer_id, buyer_username = _make_user(app_ctx, tag="buyer_order")

        with app.app_context():
            car = Car(
                seller_id=seller_id,
                public_id=f"car-{uuid.uuid4().hex[:12]}",
                brand="toyota",
                model="corolla",
                year=2019,
                mileage=500,
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

            # 3 images at orders 2, 0, 1 (deliberately out of natural
            # insertion order) -- some with a client_media_id, one legacy.
            db.session.add_all(
                [
                    CarImage(
                        car_id=car_id,
                        image_url="https://cdn.example.com/car_photos/order2.jpg",
                        order=2,
                        kind="listing",
                        source_media_id="img_order2",
                    ),
                    CarImage(
                        car_id=car_id,
                        image_url="https://cdn.example.com/car_photos/order0.jpg",
                        order=0,
                        kind="listing",
                        source_media_id=None,
                    ),
                    CarImage(
                        car_id=car_id,
                        image_url="https://cdn.example.com/car_photos/order1.jpg",
                        order=1,
                        kind="listing",
                        source_media_id="img_order1",
                    ),
                    # 2 videos at orders 1, 0 -- `_serialize_videos` sorts
                    # by (order, id) regardless of insertion order.
                    CarVideo(
                        car_id=car_id,
                        video_url="https://cdn.example.com/car_videos/v_order1.mp4",
                        order=1,
                        source_draft_media_id="vid_order1",
                    ),
                    CarVideo(
                        car_id=car_id,
                        video_url="https://cdn.example.com/car_videos/v_order0.mp4",
                        order=0,
                        source_draft_media_id=None,
                    ),
                ]
            )
            db.session.commit()

        owner_token = _login(client, seller_username)
        buyer_token = _login(client, buyer_username)

        owner_resp = client.get(
            f"/api/cars/{car_public_id}", headers=_auth(owner_token)
        )
        buyer_resp = client.get(
            f"/api/cars/{car_public_id}", headers=_auth(buyer_token)
        )
        assert owner_resp.status_code == 200, owner_resp.data
        assert buyer_resp.status_code == 200, buyer_resp.data
        owner_car = owner_resp.get_json()["car"]
        buyer_car = buyer_resp.get_json()["car"]

        # Images are stored/iterated in relationship (insertion) order,
        # NOT re-sorted by the `order` field at serialization time --
        # confirm that positional order is IDENTICAL between the owner's
        # (client_media_id-bearing) response and the non-owner's
        # (client_media_id-free) response: the new field never causes a
        # reorder.
        owner_image_urls = [img["image_url"] for img in owner_car["images"]]
        buyer_image_urls = [img["image_url"] for img in buyer_car["images"]]
        assert owner_image_urls == buyer_image_urls == [
            "https://cdn.example.com/car_photos/order2.jpg",
            "https://cdn.example.com/car_photos/order0.jpg",
            "https://cdn.example.com/car_photos/order1.jpg",
        ]

        # Videos: `_serialize_videos` explicitly sorts by (order, id) --
        # confirm that sort is unaffected by `include_private`, i.e. the
        # owner and non-owner see videos in the exact same order, only
        # differing in whether `client_media_id` is present.
        owner_video_urls = [v["video_url"] for v in owner_car["videos"]]
        buyer_video_urls = [v["video_url"] for v in buyer_car["videos"]]
        assert owner_video_urls == buyer_video_urls == [
            "https://cdn.example.com/car_videos/v_order0.mp4",
            "https://cdn.example.com/car_videos/v_order1.mp4",
        ]
        assert owner_car["videos"][0]["client_media_id"] is None
        assert owner_car["videos"][1]["client_media_id"] == "vid_order1"
        for vid in buyer_car["videos"]:
            assert "client_media_id" not in vid
