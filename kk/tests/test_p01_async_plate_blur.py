"""P-01 regression tests.

PRODUCTION_AUDIT.md P-01 (MEDIUM): "Synchronous Roboflow plate-blur call (up
to 60s) inside upload request" -- ``POST /api/cars/<car_id>/images``
(``upload_car_images()`` in ``kk/routes/media.py``) previously always ran
``process_and_store_image()`` (which can invoke the Roboflow plate-blur
network call, up to ``ROBOFLOW_TIMEOUT_S`` seconds per file) synchronously
on the request thread, for every uploaded file, one at a time.

Fix: an opt-in ``?async=1`` mode enqueues each validated file to the
existing Celery task (``kk.tasks.image_tasks.process_car_image_file`` --
already used by ``POST /api/process-car-images?async=1`` in
``kk/routes/ai.py``) instead of running the blur/downscale/persist pipeline
inline, and returns ``202`` with ``job_ids`` immediately. The default
(no ``async`` param) behavior is completely unchanged -- every existing
caller keeps the exact current synchronous response contract.

These tests cover:
  A. Default (no ``async`` param) upload behavior is unchanged (regression
     guard against any accidental behavior change from the new branch).
  B. ``?async=1`` returns 202 + one job id per valid file, registers job
     ownership, does not create any CarImage row synchronously, and still
     enforces the existing per-car photo cap / per-file validation exactly
     like the sync path (no fake success, no lost/bypassed validation).
  C. The temp file handed to the Celery task actually exists (and has the
     right content) at enqueue time, and the real task -- run synchronously
     via ``.apply()`` (no broker/worker needed), mirroring the existing
     ``test_m06_image_cap_and_pixel_bomb.py`` convention -- successfully
     processes and persists it end-to-end, proving the async path never
     loses the file/job.
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
import PIL.Image as PILImage

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from kk.routes import media as media_routes  # noqa: E402

_PASSWORD = "Aa123456!"


def _tiny_jpeg_bytes(color=(30, 120, 200), size=(20, 20)) -> bytes:
    im = PILImage.new("RGB", size, color=color)
    buf = BytesIO()
    im.save(buf, format="JPEG", quality=80)
    return buf.getvalue()


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_p01_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "p01.db")
    os.environ["UPLOAD_FOLDER"] = os.path.join(tmp.name, "uploads")
    os.environ.pop("ROBOFLOW_API_KEY", None)
    for key in ("R2_ACCOUNT_ID", "R2_BUCKET_NAME", "R2_ACCESS_KEY_ID", "R2_SECRET_ACCESS_KEY", "R2_PUBLIC_URL"):
        os.environ.pop(key, None)

    from kk.app_factory import create_app

    app, _socketio, *_ = create_app()
    for key in ("R2_ACCOUNT_ID", "R2_BUCKET_NAME", "R2_ACCESS_KEY_ID", "R2_SECRET_ACCESS_KEY", "R2_PUBLIC_URL"):
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


@pytest.fixture(autouse=True)
def _clear_job_owners():
    from kk.job_ownership import clear_job_owners_for_tests

    clear_job_owners_for_tests()
    yield
    clear_job_owners_for_tests()


def _unique_phone() -> str:
    return f"077{uuid.uuid4().int % 10**8:08d}"


def _make_user(app_ctx) -> tuple[str, int, str]:
    app, _client, db, User, *_ = app_ctx
    username = f"p01_{uuid.uuid4().hex[:10]}"
    with app.app_context():
        user = User(
            username=username,
            phone_number=_unique_phone(),
            first_name="P01",
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


def _image_count(app_ctx, car_id: int) -> int:
    app, _client, db, _User, _Car, CarImage = app_ctx
    with app.app_context():
        return CarImage.query.filter_by(car_id=car_id).count()


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


def _files_payload(n: int, field: str = "files") -> dict:
    return {field: [(BytesIO(_tiny_jpeg_bytes()), f"photo-{i}.jpg") for i in range(n)]}


class _FakeAsyncResult:
    def __init__(self, task_id: str):
        self.id = task_id


class _FakeTask:
    """Stand-in for ``process_car_image_file`` that records ``.delay()``
    calls without touching Celery/broker at all."""

    def __init__(self):
        self.calls: list[tuple[tuple, dict]] = []

    def delay(self, *args, **kwargs):
        tid = f"fake-{uuid.uuid4().hex}"
        self.calls.append((args, kwargs))
        return _FakeAsyncResult(tid)


# ---------------------------------------------------------------------------
# A. Default (synchronous) behavior is unchanged
# ---------------------------------------------------------------------------


class TestSyncDefaultUnchanged:
    def test_default_upload_is_still_synchronous_and_returns_201(self, app_ctx, client):
        ctx = _setup_seller(app_ctx, client)
        resp = client.post(
            f"/api/cars/{ctx['car_public_id']}/images",
            data=_files_payload(2),
            headers=_auth(ctx["token"]),
            content_type="multipart/form-data",
        )
        assert resp.status_code == 201, resp.get_json()
        body = resp.get_json()
        assert len(body["images"]) == 2
        assert _image_count(app_ctx, ctx["car_id"]) == 2
        assert "job_ids" not in body


# ---------------------------------------------------------------------------
# B. Async opt-in mode
# ---------------------------------------------------------------------------


class TestAsyncOptIn:
    def test_async_upload_returns_202_with_job_ids_and_no_immediate_carimage(
        self, app_ctx, client, monkeypatch
    ):
        ctx = _setup_seller(app_ctx, client)
        fake_task = _FakeTask()
        monkeypatch.setattr(media_routes, "process_car_image_file", fake_task)

        resp = client.post(
            f"/api/cars/{ctx['car_public_id']}/images?async=1",
            data=_files_payload(3),
            headers=_auth(ctx["token"]),
            content_type="multipart/form-data",
        )
        assert resp.status_code == 202, resp.get_json()
        body = resp.get_json()
        assert len(body["job_ids"]) == 3
        assert len(fake_task.calls) == 3

        # P-01: enqueuing must never create the CarImage row up front -- the
        # actual image bytes have not been blurred/persisted yet, so doing
        # so would be a "fake success".
        assert _image_count(app_ctx, ctx["car_id"]) == 0

    def test_async_upload_registers_job_ownership_for_the_uploader(
        self, app_ctx, client, monkeypatch
    ):
        from kk.job_ownership import get_registered_job_owner

        ctx = _setup_seller(app_ctx, client)
        fake_task = _FakeTask()
        monkeypatch.setattr(media_routes, "process_car_image_file", fake_task)

        resp = client.post(
            f"/api/cars/{ctx['car_public_id']}/images?async=1",
            data=_files_payload(1),
            headers=_auth(ctx["token"]),
            content_type="multipart/form-data",
        )
        assert resp.status_code == 202, resp.get_json()
        job_id = resp.get_json()["job_ids"][0]
        assert get_registered_job_owner(job_id) == ctx["public_id"]

    def test_async_upload_still_enforces_listing_photo_cap(self, app_ctx, client, monkeypatch):
        ctx = _setup_seller(app_ctx, client)
        fake_task = _FakeTask()
        monkeypatch.setattr(media_routes, "process_car_image_file", fake_task)
        over_cap = media_routes.MAX_LISTING_PHOTOS + 1

        resp = client.post(
            f"/api/cars/{ctx['car_public_id']}/images?async=1",
            data=_files_payload(over_cap),
            headers=_auth(ctx["token"]),
            content_type="multipart/form-data",
        )
        assert resp.status_code == 400, resp.get_json()
        assert fake_task.calls == []

    def test_async_upload_rejects_invalid_file_without_enqueueing(
        self, app_ctx, client, monkeypatch
    ):
        ctx = _setup_seller(app_ctx, client)
        fake_task = _FakeTask()
        monkeypatch.setattr(media_routes, "process_car_image_file", fake_task)

        resp = client.post(
            f"/api/cars/{ctx['car_public_id']}/images?async=1",
            data={"files": (BytesIO(b"not-an-image"), "evil.exe")},
            headers=_auth(ctx["token"]),
            content_type="multipart/form-data",
        )
        assert resp.status_code == 400, resp.get_json()
        assert fake_task.calls == []

    def test_async_upload_stages_a_real_temp_file_readable_at_enqueue_time(
        self, app_ctx, client, monkeypatch
    ):
        """The temp file handed to the Celery task must actually exist on
        disk (streamed via FileStorage.save(), not lost) with the uploaded
        bytes intact at the moment of enqueue."""
        ctx = _setup_seller(app_ctx, client)
        fake_task = _FakeTask()
        monkeypatch.setattr(media_routes, "process_car_image_file", fake_task)
        source_bytes = _tiny_jpeg_bytes()

        resp = client.post(
            f"/api/cars/{ctx['car_public_id']}/images?async=1",
            data={"files": (BytesIO(source_bytes), "photo.jpg")},
            headers=_auth(ctx["token"]),
            content_type="multipart/form-data",
        )
        assert resp.status_code == 202, resp.get_json()
        assert len(fake_task.calls) == 1
        args, kwargs = fake_task.calls[0]
        temp_abs = args[0]
        assert os.path.isfile(temp_abs)
        with open(temp_abs, "rb") as fh:
            assert fh.read() == source_bytes
        assert kwargs["owner_public_id"] == ctx["public_id"]


# ---------------------------------------------------------------------------
# C. End-to-end: the real Celery task actually processes the staged file
# ---------------------------------------------------------------------------


class TestAsyncTaskEndToEnd:
    def test_real_task_processes_and_persists_the_staged_file(
        self, app_ctx, client, monkeypatch
    ):
        """Runs the real ``process_car_image_file`` task synchronously
        (``.apply()``, no broker/worker needed) against the exact temp path
        the route staged, proving the async path never loses the
        file/job -- a worker picking up the enqueued job would succeed."""
        from kk.tasks import celery_app as celery_app_module
        from kk.tasks.image_tasks import process_car_image_file as real_task

        app = app_ctx[0]
        monkeypatch.setattr(celery_app_module, "get_celery_flask_app", lambda: app)

        ctx = _setup_seller(app_ctx, client)
        fake_task = _FakeTask()
        monkeypatch.setattr(media_routes, "process_car_image_file", fake_task)

        resp = client.post(
            f"/api/cars/{ctx['car_public_id']}/images?async=1",
            data={"files": (BytesIO(_tiny_jpeg_bytes()), "photo.jpg")},
            headers=_auth(ctx["token"]),
            content_type="multipart/form-data",
        )
        assert resp.status_code == 202, resp.get_json()
        args, kwargs = fake_task.calls[0]
        temp_abs = args[0]
        assert os.path.isfile(temp_abs)

        result = real_task.apply(args=args, kwargs=kwargs)
        assert result.successful(), result.result
        out = result.result
        assert out["ok"] is True
        assert out["rel_path"]

        # Task's own `finally:` cleans up the temp file it was handed.
        assert not os.path.isfile(temp_abs)
