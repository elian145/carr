"""Section C audit finding: MAX_LISTING_VIDEOS must be enforced
IDENTICALLY by both server-side video-attach paths --
POST /api/cars/<id>/videos (upload_car_videos(), the normal
already-client-compressed multipart path) and
POST /api/media/r2/attach-transcoded-video (attach_transcoded_video(),
the server-transcode promote/attach path).

Before this fix, upload_car_videos() enforced NO cap at all -- a listing
could end up with more videos than the transcode path would ever allow,
purely depending on which of the two upload paths a given video's source
happened to need. attach_transcoded_video() already correctly enforced
the cap via _video_limit_error(existing_count, 1) (see
kk/tests/test_video_phase3a_attach.py::TestLimits for that endpoint's own
pre-existing coverage).

This file proves the SAME existing + incoming <= MAX_LISTING_VIDEOS rule,
using the SAME MAX_LISTING_VIDEOS constant, now holds for
upload_car_videos() too -- including when the existing count was built up
via the OTHER endpoint (the actual cross-endpoint gap), and that the
already-attached-draft "stays retrievable even once full" exception
(idempotent re-send) is preserved on BOTH endpoints.

Deliberately R2-account-configured but WITHOUT R2_PUBLIC_URL set, so
upload_car_videos() takes its local-disk-save branch (no real R2 PUT
needed for that endpoint) while attach_transcoded_video() -- which only
requires _r2_configured(), not a public URL -- still works normally
against mocked R2 HEAD/copy/delete calls.
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
_R2_KEYS = (
    "R2_ACCOUNT_ID",
    "R2_BUCKET_NAME",
    "R2_ACCESS_KEY_ID",
    "R2_SECRET_ACCESS_KEY",
)
_ATTACH_URL = "/api/media/r2/attach-transcoded-video"

# Minimal valid ISO-BMFF ("ftyp" box, brand "isom") header so
# kk.security.sniff_bytes(..., "mp4") accepts it as a real MP4.
_MP4_HEADER = b"\x00\x00\x00\x18ftypisom\x00\x00\x02\x00isomiso2avc1mp41"


def _fake_video_bytes(marker: bytes = b"", size: int = 4096) -> bytes:
    body = _MP4_HEADER + marker
    return body + (b"\x00" * max(0, size - len(body)))


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(
        prefix="carlist_videocap_", ignore_cleanup_errors=True
    )
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "videocap.db")
    os.environ["UPLOAD_FOLDER"] = os.path.join(tmp.name, "uploads")
    for key in _R2_KEYS + ("R2_PUBLIC_URL", "VIDEO_SOURCE_STAGING_ENABLED"):
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


@pytest.fixture
def r2_configured(app_ctx, monkeypatch):
    """R2 account credentials only -- deliberately NEVER sets
    R2_PUBLIC_URL, so upload_car_videos()'s
    _r2_ready_for_public_object_urls() stays False (local-disk save
    branch) while attach_transcoded_video()'s _r2_configured() check
    (which does not need a public URL) still passes."""
    app = app_ctx[0]
    for key in _R2_KEYS:
        monkeypatch.setitem(app.config, key, f"test-{key.lower()}")
    return app


@pytest.fixture(autouse=True)
def _enable_video_source_staging(monkeypatch):
    monkeypatch.setenv("VIDEO_SOURCE_STAGING_ENABLED", "1")


@pytest.fixture(autouse=True)
def _clear_job_registries():
    from kk.job_ownership import clear_idempotent_jobs_for_tests, clear_job_owners_for_tests

    clear_job_owners_for_tests()
    clear_idempotent_jobs_for_tests()
    yield
    clear_job_owners_for_tests()
    clear_idempotent_jobs_for_tests()


def _unique_phone() -> str:
    return f"077{uuid.uuid4().int % 10**8:08d}"


def _make_user(app_ctx):
    app, _client, db, User, *_ = app_ctx
    username = f"vc_{uuid.uuid4().hex[:10]}"
    with app.app_context():
        user = User(
            username=username,
            phone_number=_unique_phone(),
            first_name="VideoCap",
            last_name="Test",
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id=f"pub-vc-{uuid.uuid4().hex[:12]}",
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
            public_id=f"car-vc-{uuid.uuid4().hex[:12]}",
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


def _upload_multipart_video(client, ctx, *, client_media_id: str, marker: bytes):
    return client.post(
        f"/api/cars/{ctx['car_public_id']}/videos",
        data={
            "files": (BytesIO(_fake_video_bytes(marker)), f"{client_media_id}.mp4"),
            "client_media_id": client_media_id,
        },
        headers=_auth(ctx["token"]),
        content_type="multipart/form-data",
    )


# ---------------------------------------------------------------------------
# attach_transcoded_video() helpers (mirrors test_video_phase3a_attach.py)
# ---------------------------------------------------------------------------


class _FakeAsyncResult:
    def __init__(self, state: str, result=None):
        self.state = state
        self.result = result


def _new_task_id(tag: str) -> str:
    return f"task-{tag}-{uuid.uuid4().hex[:16]}"


def _new_draft_id() -> str:
    return f"draft-{uuid.uuid4().hex[:16]}"


def _processed_key(app_ctx, owner_public_id: str, draft_media_id: str) -> str:
    from kk.media_processing import processed_video_staging_key

    app = app_ctx[0]
    with app.app_context():
        return processed_video_staging_key(owner_public_id, draft_media_id)


def _setup_job(monkeypatch, *, owner_public_id: str, draft_media_id: str, task_id: str):
    from kk.job_ownership import register_idempotent_job_task_id, register_job_owner
    from kk.tasks import video_tasks

    register_job_owner(task_id, owner_public_id)
    dedupe_key = video_tasks.video_job_dedupe_key(owner_public_id, draft_media_id)
    register_idempotent_job_task_id(dedupe_key, task_id)
    monkeypatch.setattr(
        video_tasks.transcode_car_video_source,
        "AsyncResult",
        lambda tid: _FakeAsyncResult("SUCCESS", None),
    )


def _install_r2_fakes(monkeypatch, *, processed_key: str, processed_meta: dict):
    import kk.r2_ops as r2_ops_module

    state = {"copied_keys": {}}

    def fake_head(*, key, timeout=30):
        if key == processed_key:
            return dict(processed_meta)
        if key in state["copied_keys"]:
            return {
                "exists": True,
                "size": state["copied_keys"][key],
                "content_type": "video/mp4",
            }
        return {"exists": False, "size": None, "content_type": None}

    def fake_copy(*, source_key, dest_key, content_type=None, timeout=60):
        state["copied_keys"][dest_key] = int(processed_meta.get("size") or 0)

    def fake_delete(*, key, timeout=30):
        pass

    monkeypatch.setattr(r2_ops_module, "r2_head_object", fake_head)
    monkeypatch.setattr(r2_ops_module, "r2_copy_object", fake_copy)
    monkeypatch.setattr(r2_ops_module, "r2_delete_object", fake_delete)
    return state


def _good_meta(size: int = 2048) -> dict:
    return {"exists": True, "size": size, "content_type": "video/mp4"}


def _attach_transcoded(client, token, *, car_id, draft_media_id, task_id):
    return client.post(
        _ATTACH_URL,
        json={"car_id": car_id, "draft_media_id": draft_media_id, "task_id": task_id},
        headers=_auth(token),
    )


def _do_attach_transcoded_video(app_ctx, client, ctx, monkeypatch, *, draft_media_id: str):
    task_id = _new_task_id(draft_media_id)
    processed_key = _processed_key(app_ctx, ctx["public_id"], draft_media_id)
    _install_r2_fakes(monkeypatch, processed_key=processed_key, processed_meta=_good_meta())
    _setup_job(
        monkeypatch,
        owner_public_id=ctx["public_id"],
        draft_media_id=draft_media_id,
        task_id=task_id,
    )
    return _attach_transcoded(
        client, ctx["token"], car_id=ctx["car_public_id"], draft_media_id=draft_media_id, task_id=task_id
    )


# ---------------------------------------------------------------------------
# TESTS
# ---------------------------------------------------------------------------


class TestUploadCarVideosCapEnforcement:
    def test_multipart_batch_larger_than_cap_from_empty_is_partially_accepted(
        self, app_ctx, client
    ):
        from kk.routes.media import MAX_LISTING_VIDEOS

        ctx = _setup_seller(app_ctx, client)
        files = [
            (BytesIO(_fake_video_bytes(str(i).encode())), f"v{i}.mp4")
            for i in range(MAX_LISTING_VIDEOS + 2)
        ]
        client_media_ids = [f"draft_{i}" for i in range(MAX_LISTING_VIDEOS + 2)]
        resp = client.post(
            f"/api/cars/{ctx['car_public_id']}/videos",
            data={"files": files, "client_media_id": client_media_ids},
            headers=_auth(ctx["token"]),
            content_type="multipart/form-data",
        )
        assert resp.status_code == 201, resp.get_json()
        body = resp.get_json()
        assert len(body["videos"]) == MAX_LISTING_VIDEOS
        assert len(body["rejected"]) == 2
        for r in body["rejected"]:
            assert "up to" in r["reason"]
        assert _car_video_count(app_ctx, ctx["car_id"]) == MAX_LISTING_VIDEOS

    def test_new_video_rejected_once_cap_is_full_via_multipart(self, app_ctx, client):
        from kk.routes.media import MAX_LISTING_VIDEOS

        ctx = _setup_seller(app_ctx, client)
        for i in range(MAX_LISTING_VIDEOS):
            r = _upload_multipart_video(
                client, ctx, client_media_id=f"fill_{i}", marker=str(i).encode()
            )
            assert r.status_code == 201, r.get_json()
        assert _car_video_count(app_ctx, ctx["car_id"]) == MAX_LISTING_VIDEOS

        r = _upload_multipart_video(
            client, ctx, client_media_id="over_limit", marker=b"over"
        )
        # Zero files succeeded (the only one submitted was over the cap)
        # -> whole request reports 400, matching the pre-existing
        # "only fail if ZERO files succeeded" contract.
        assert r.status_code == 400, r.get_json()
        assert "up to" in r.get_json()["message"]
        assert _car_video_count(app_ctx, ctx["car_id"]) == MAX_LISTING_VIDEOS

    def test_already_attached_client_media_id_retrievable_even_when_cap_full(
        self, app_ctx, client
    ):
        from kk.routes.media import MAX_LISTING_VIDEOS

        ctx = _setup_seller(app_ctx, client)
        first = _upload_multipart_video(
            client, ctx, client_media_id="draft_first", marker=b"first"
        )
        assert first.status_code == 201, first.get_json()
        first_id = first.get_json()["videos"][0]["id"]

        for i in range(MAX_LISTING_VIDEOS - 1):
            r = _upload_multipart_video(
                client, ctx, client_media_id=f"fill_{i}", marker=str(i).encode()
            )
            assert r.status_code == 201, r.get_json()
        assert _car_video_count(app_ctx, ctx["car_id"]) == MAX_LISTING_VIDEOS

        # Re-sending the FIRST (already-attached) draft again must still
        # succeed with the SAME row, even though the listing is now full --
        # matches attach_transcoded_video()'s identical contract.
        retry = _upload_multipart_video(
            client, ctx, client_media_id="draft_first", marker=b"first"
        )
        assert retry.status_code == 201, retry.get_json()
        assert retry.get_json()["videos"][0]["id"] == first_id
        assert _car_video_count(app_ctx, ctx["car_id"]) == MAX_LISTING_VIDEOS


class TestCrossEndpointCapConsistency:
    """The actual Section C audit gap: before this fix, videos attached
    via attach_transcoded_video() did not count against
    upload_car_videos()'s (nonexistent) cap, so a listing could exceed
    MAX_LISTING_VIDEOS by mixing both upload paths."""

    def test_cap_filled_via_transcode_attach_now_blocks_multipart_upload(
        self, app_ctx, client, r2_configured, monkeypatch
    ):
        from kk.routes.media import MAX_LISTING_VIDEOS

        ctx = _setup_seller(app_ctx, client)
        for i in range(MAX_LISTING_VIDEOS):
            r = _do_attach_transcoded_video(
                app_ctx, client, ctx, monkeypatch, draft_media_id=f"vst_fill_{i}"
            )
            assert r.status_code == 201, r.get_json()
        assert _car_video_count(app_ctx, ctx["car_id"]) == MAX_LISTING_VIDEOS

        # THE BUG THIS FIX CLOSES: before the fix, this multipart upload
        # had no cap check at all and would have succeeded, taking the
        # listing to MAX_LISTING_VIDEOS + 1.
        r = _upload_multipart_video(
            client, ctx, client_media_id="one_too_many", marker=b"over"
        )
        assert r.status_code == 400, r.get_json()
        assert "up to" in r.get_json()["message"]
        assert _car_video_count(app_ctx, ctx["car_id"]) == MAX_LISTING_VIDEOS

    def test_cap_filled_via_multipart_still_blocks_transcode_attach(
        self, app_ctx, client, r2_configured, monkeypatch
    ):
        from kk.routes.media import MAX_LISTING_VIDEOS

        ctx = _setup_seller(app_ctx, client)
        for i in range(MAX_LISTING_VIDEOS):
            r = _upload_multipart_video(
                client, ctx, client_media_id=f"fill_{i}", marker=str(i).encode()
            )
            assert r.status_code == 201, r.get_json()
        assert _car_video_count(app_ctx, ctx["car_id"]) == MAX_LISTING_VIDEOS

        r = _do_attach_transcoded_video(
            app_ctx, client, ctx, monkeypatch, draft_media_id="vst_over_limit"
        )
        assert r.status_code == 400, r.get_json()
        assert _car_video_count(app_ctx, ctx["car_id"]) == MAX_LISTING_VIDEOS

    def test_mixed_origin_running_tally_blocks_exactly_at_the_shared_cap(
        self, app_ctx, client, r2_configured, monkeypatch
    ):
        """(MAX_LISTING_VIDEOS - 1) videos via transcode-attach, then ONE
        more via multipart reaches the cap exactly (allowed); the NEXT
        one via either path must then be rejected -- proving the running
        tally is a single shared count regardless of which endpoint
        contributed to it."""
        from kk.routes.media import MAX_LISTING_VIDEOS

        ctx = _setup_seller(app_ctx, client)
        for i in range(MAX_LISTING_VIDEOS - 1):
            r = _do_attach_transcoded_video(
                app_ctx, client, ctx, monkeypatch, draft_media_id=f"vst_mix_{i}"
            )
            assert r.status_code == 201, r.get_json()
        assert _car_video_count(app_ctx, ctx["car_id"]) == MAX_LISTING_VIDEOS - 1

        last = _upload_multipart_video(
            client, ctx, client_media_id="mix_last", marker=b"last"
        )
        assert last.status_code == 201, last.get_json()
        assert _car_video_count(app_ctx, ctx["car_id"]) == MAX_LISTING_VIDEOS

        over_multipart = _upload_multipart_video(
            client, ctx, client_media_id="mix_over_multipart", marker=b"over1"
        )
        assert over_multipart.status_code == 400, over_multipart.get_json()

        over_transcode = _do_attach_transcoded_video(
            app_ctx, client, ctx, monkeypatch, draft_media_id="vst_mix_over"
        )
        assert over_transcode.status_code == 400, over_transcode.get_json()
        assert _car_video_count(app_ctx, ctx["car_id"]) == MAX_LISTING_VIDEOS
