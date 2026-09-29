"""Real-device regression: "I submitted TWO videos. One video encountered
an error and did not upload."

Root cause (client-side, fixed in `lib/features/sell/sell_listing_media_upload.dart`):
both Flutter callers of `ApiService.uploadCarVideos` (Phase A's
`runPhaseAOnly` and Phase B's `uploadForCar`) unconditionally credited
`videosToUpload.length` regardless of what `POST /api/cars/<id>/videos`
actually confirmed, and Phase B's own "already uploaded?" guard was a
coarse `existingVideoCount >= videosToUpload.length` count comparison --
which can never distinguish "1 of 2 videos already succeeded, only retry
the failed one" from "neither succeeded yet". When one video in a batch
is rejected while its sibling succeeds, that coarse check stays false
forever for this car, so every later Phase-A/Phase-B/resume pass
re-sends the WHOLE batch again, including the already-successful video.

This file covers the BACKEND half of the fix: `upload_car_videos()`
(`kk/routes/media.py`) previously created a brand-new `CarVideo` row on
every call, for every accepted file, WITHOUT ever setting
`CarVideo.source_draft_media_id` -- so the column's own unique
constraint (`uq_car_video_car_id_source_draft_media_id`) could never
fire, and a client re-send of an already-successful video (via the
buggy count-based guard above, or any other retry path) created a
genuine DUPLICATE `CarVideo` row. The fix sets
`source_draft_media_id=client_media_id` on every row it creates, and
short-circuits (no re-upload/re-save, no new row) when a request
re-sends a `client_media_id` that already has a `CarVideo` row for this
car.
"""

from __future__ import annotations

import os
import sys
import tempfile
import uuid
from io import BytesIO
from pathlib import Path

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

_PASSWORD = "Aa123456!"

# Minimal valid ISO-BMFF ("ftyp" box, brand "isom") header so
# `kk.security.sniff_bytes(..., "mp4")` accepts it as a real MP4.
_MP4_HEADER = b"\x00\x00\x00\x18ftypisom\x00\x00\x02\x00isomiso2avc1mp41"


def _fake_video_bytes(marker: bytes = b"", size: int = 4096) -> bytes:
    body = _MP4_HEADER + marker
    return body + (b"\x00" * max(0, size - len(body)))


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(
        prefix="carlist_twovideo_", ignore_cleanup_errors=True
    )
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "twovideo.db")
    os.environ["UPLOAD_FOLDER"] = os.path.join(tmp.name, "uploads")
    # Deliberately NOT R2-configured -- exercises the local-disk save
    # branch, which is simpler to assert against in this test file (the
    # duplicate-guard logic itself is identical either way, before the
    # branch on `_r2_ready_for_public_object_urls()`).
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
    return f"078{uuid.uuid4().int % 10**8:08d}"


def _make_user(app_ctx):
    app, _client, db, User, *_ = app_ctx
    username = f"tv_{uuid.uuid4().hex[:10]}"
    with app.app_context():
        user = User(
            username=username,
            phone_number=_unique_phone(),
            first_name="TwoVideo",
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


def _make_car(app_ctx, seller_id: int):
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


def _car_video_count(app_ctx, car_id: int) -> int:
    app, _client, db, _User, _Car, CarVideo = app_ctx
    with app.app_context():
        return CarVideo.query.filter_by(car_id=car_id).count()


class TestTwoVideosDistinctClientMediaIds:
    def test_two_videos_with_distinct_ids_both_succeed_independently(
        self, app_ctx, client
    ):
        ctx = _setup_seller(app_ctx, client)
        resp = client.post(
            f"/api/cars/{ctx['car_public_id']}/videos",
            data={
                "files": [
                    (BytesIO(_fake_video_bytes(b"A")), "a.mp4"),
                    (BytesIO(_fake_video_bytes(b"B")), "b.mp4"),
                ],
                "client_media_id": ["draft_video_a", "draft_video_b"],
            },
            headers=_auth(ctx["token"]),
            content_type="multipart/form-data",
        )
        assert resp.status_code == 201, resp.get_json()
        body = resp.get_json()
        assert len(body["videos"]) == 2
        assert body["rejected"] == []
        assert _car_video_count(app_ctx, ctx["car_id"]) == 2


class TestDuplicateGuard:
    def test_resending_an_already_attached_client_media_id_never_creates_a_second_row(
        self, app_ctx, client
    ):
        ctx = _setup_seller(app_ctx, client)

        first = client.post(
            f"/api/cars/{ctx['car_public_id']}/videos",
            data={
                "files": (BytesIO(_fake_video_bytes(b"A")), "a.mp4"),
                "client_media_id": "draft_video_a",
            },
            headers=_auth(ctx["token"]),
            content_type="multipart/form-data",
        )
        assert first.status_code == 201, first.get_json()
        first_video_id = first.get_json()["videos"][0]["id"]
        assert _car_video_count(app_ctx, ctx["car_id"]) == 1

        # Simulate the exact real-device scenario the client-side fix
        # closes: a later Phase-A/Phase-B/resume pass re-sends the SAME
        # already-successful video (e.g. because a sibling video in the
        # original batch failed and the whole batch was re-attempted).
        second = client.post(
            f"/api/cars/{ctx['car_public_id']}/videos",
            data={
                "files": (BytesIO(_fake_video_bytes(b"A")), "a.mp4"),
                "client_media_id": "draft_video_a",
            },
            headers=_auth(ctx["token"]),
            content_type="multipart/form-data",
        )
        assert second.status_code == 201, second.get_json()
        second_body = second.get_json()
        assert len(second_body["videos"]) == 1
        assert second_body["videos"][0]["id"] == first_video_id, (
            "re-sending an already-attached client_media_id must "
            "re-report the SAME row, never create a new one"
        )
        assert _car_video_count(app_ctx, ctx["car_id"]) == 1, (
            "a real duplicate CarVideo row was created for an "
            "already-successful video"
        )

    def test_one_new_and_one_already_attached_video_in_the_same_request(
        self, app_ctx, client
    ):
        ctx = _setup_seller(app_ctx, client)
        first = client.post(
            f"/api/cars/{ctx['car_public_id']}/videos",
            data={
                "files": (BytesIO(_fake_video_bytes(b"A")), "a.mp4"),
                "client_media_id": "draft_video_a",
            },
            headers=_auth(ctx["token"]),
            content_type="multipart/form-data",
        )
        assert first.status_code == 201, first.get_json()

        # Re-send video A (already attached) alongside a brand-new video
        # B, mirroring "sibling B failed Phase A earlier, so this retry
        # batch still includes both A and B".
        second = client.post(
            f"/api/cars/{ctx['car_public_id']}/videos",
            data={
                "files": [
                    (BytesIO(_fake_video_bytes(b"A")), "a.mp4"),
                    (BytesIO(_fake_video_bytes(b"B")), "b.mp4"),
                ],
                "client_media_id": ["draft_video_a", "draft_video_b"],
            },
            headers=_auth(ctx["token"]),
            content_type="multipart/form-data",
        )
        assert second.status_code == 201, second.get_json()
        assert len(second.get_json()["videos"]) == 2
        assert _car_video_count(app_ctx, ctx["car_id"]) == 2, (
            "video A must not be duplicated just because it was re-sent "
            "alongside a genuinely new video B"
        )


class TestPartialBatchFailureReporting:
    def test_one_rejected_and_one_valid_video_in_the_same_request(
        self, app_ctx, client
    ):
        ctx = _setup_seller(app_ctx, client)
        resp = client.post(
            f"/api/cars/{ctx['car_public_id']}/videos",
            data={
                "files": [
                    (BytesIO(b"not a real video file"), "bad.mp4"),
                    (BytesIO(_fake_video_bytes(b"GOOD")), "good.mp4"),
                ],
                "client_media_id": ["draft_bad", "draft_good"],
            },
            headers=_auth(ctx["token"]),
            content_type="multipart/form-data",
        )
        # At least one file succeeded -> whole request succeeds (matches
        # the pre-existing "only fail if ZERO files succeeded" contract).
        assert resp.status_code == 201, resp.get_json()
        body = resp.get_json()
        assert len(body["videos"]) == 1, (
            "the response's `videos` array must reflect ONLY the video "
            "that actually succeeded -- a client blindly crediting "
            "`videosToUpload.length` instead of this array's real "
            "length is exactly the client-side bug this response shape "
            "is meant to let the caller detect"
        )
        assert len(body["rejected"]) == 1
        assert body["rejected"][0]["filename"] == "bad.mp4"
        assert _car_video_count(app_ctx, ctx["car_id"]) == 1
