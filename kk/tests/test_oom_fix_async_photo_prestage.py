"""OOM-fix follow-up regression tests.

Context (see the read-only OOM audit and its follow-up fix): moving Sell
photo prestaging onto the existing Celery async image-processing pipeline
(``POST /api/process-car-images?async=1``) surfaced a second, pre-existing
bug in that same pipeline: ``process_car_image_file.delay(temp_abs, ...)``
passed a *local filesystem path* as a task argument, but in real production
``carr`` (web) and ``carr-worker-fra`` (Celery worker) are separate Render
services with non-shared, ephemeral disks -- a path written by the web
process is not readable by the worker that actually runs the task. Render
never shares a local disk across services (see
``kk/docs/UPLOAD_PERSISTENCE.md``).

Fix: when R2 is configured (the production default), the enqueuing route
stages the original upload bytes to a short-lived R2 object instead
(``kk.media_processing.stage_upload_for_async_job``) and passes that key as
``source_r2_key``; the worker downloads it to its own local disk before
processing (``kk.tasks.image_tasks._process_image_path``), and removes both
the downloaded copy and the R2 staging object when done -- success or
failure. When R2 is not configured (dev/test, no separate worker service),
behavior is unchanged: a local ``temp_abs`` path is used directly, exactly
as before this fix (see ``test_p01_async_plate_blur.py`` /
``test_m06_image_cap_and_pixel_bomb.py``, which run with R2 unconfigured and
must keep passing unmodified).

These tests cover:
  A. ``stage_upload_for_async_job()`` stages to R2 and removes the local
     temp file when R2 is configured; falls back to returning a local
     ``temp_abs`` (unchanged behavior) when R2 is not configured.
  B. ``_process_image_path(source_r2_key=...)`` downloads from R2, processes
     normally, and cleans up both the downloaded local copy and the R2
     staging object -- on success AND on a hard rejection
     (``DecompressionBombRejected``).
  C. HTTP-level: with R2 configured, both async-enqueue routes
     (``/api/process-car-images?async=1`` and
     ``/api/cars/<id>/images?async=1``) stage via R2 and pass
     ``source_r2_key`` (not a locally-meaningful ``temp_abs``) to the Celery
     task.
  D. ``cleanup_stale_image_staging_objects`` (the Celery Beat backstop
     sweep) no-ops when R2 is not configured, and delegates to
     ``r2_cleanup_stale_staging`` with the expected prefix/age when it is.
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

import kk.r2_ops as r2_ops_module  # noqa: E402
from kk.routes import ai as ai_routes  # noqa: E402
from kk.routes import media as media_routes  # noqa: E402

_PASSWORD = "Aa123456!"
_R2_KEYS = (
    "R2_ACCOUNT_ID",
    "R2_BUCKET_NAME",
    "R2_ACCESS_KEY_ID",
    "R2_SECRET_ACCESS_KEY",
)


def _tiny_jpeg_bytes(color=(30, 120, 200), size=(20, 20)) -> bytes:
    im = PILImage.new("RGB", size, color=color)
    buf = BytesIO()
    im.save(buf, format="JPEG", quality=80)
    return buf.getvalue()


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_oomfix_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "oomfix.db")
    os.environ["UPLOAD_FOLDER"] = os.path.join(tmp.name, "uploads")
    os.environ.pop("ROBOFLOW_API_KEY", None)
    for key in _R2_KEYS + ("R2_PUBLIC_URL",):
        os.environ.pop(key, None)

    from kk.app_factory import create_app

    app, _socketio, *_ = create_app()
    for key in _R2_KEYS + ("R2_PUBLIC_URL",):
        app.config.pop(key, None)

    from kk.models import Car, User, db

    with app.app_context():
        db.drop_all()
        db.create_all()

    yield app, app.test_client(), db, User, Car

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


@pytest.fixture
def r2_configured(app_ctx, monkeypatch):
    """Turn on R2 for the app used by ``app_ctx`` for the duration of one
    test -- ``monkeypatch`` reverts this automatically afterward, so other
    (module-scoped-app) tests still see R2 unconfigured by default, matching
    ``test_p01_async_plate_blur.py`` / ``test_m06_image_cap_and_pixel_bomb.py``'s
    existing no-R2 convention."""
    app = app_ctx[0]
    for key in _R2_KEYS:
        monkeypatch.setitem(app.config, key, f"test-{key.lower()}")
    return app


def _unique_phone() -> str:
    return f"077{uuid.uuid4().int % 10**8:08d}"


def _make_user(app_ctx) -> tuple[str, int, str]:
    app, _client, db, User, *_ = app_ctx
    username = f"oomfix_{uuid.uuid4().hex[:10]}"
    with app.app_context():
        user = User(
            username=username,
            phone_number=_unique_phone(),
            first_name="OomFix",
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
    app, _client, db, _User, Car = app_ctx
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


class _FakeFileStorage:
    """Minimal ``FileStorage``-like stub -- only ``.save()`` is used by
    ``stage_upload_for_async_job``."""

    def __init__(self, data: bytes, filename: str):
        self._data = data
        self.filename = filename

    def save(self, dst_path: str) -> None:
        os.makedirs(os.path.dirname(dst_path), exist_ok=True)
        with open(dst_path, "wb") as fh:
            fh.write(self._data)


# ---------------------------------------------------------------------------
# A. stage_upload_for_async_job()
# ---------------------------------------------------------------------------


class TestStageUploadForAsyncJob:
    def test_stages_to_r2_and_removes_local_temp_when_r2_configured(
        self, app_ctx, r2_configured, monkeypatch
    ):
        from kk.media_processing import stage_upload_for_async_job

        app = app_ctx[0]
        data = _tiny_jpeg_bytes()
        fs = _FakeFileStorage(data, "photo.jpg")

        captured: dict = {}

        def fake_r2_put_file(*, key, file_path, content_type, timeout=120):
            assert os.path.isfile(file_path), "r2_put_file must receive an on-disk path"
            with open(file_path, "rb") as fh:
                captured["body"] = fh.read()
            captured["key"] = key
            captured["path_at_call_time"] = file_path

        monkeypatch.setattr(r2_ops_module, "r2_put_file", fake_r2_put_file)

        with app.app_context():
            temp_abs, source_r2_key = stage_upload_for_async_job(
                fs, filename_hint="photo.jpg"
            )

        assert temp_abs is None
        assert source_r2_key == captured["key"]
        assert source_r2_key.startswith("car_photos/_staging/")
        assert captured["body"] == data
        # The local temp file used to stage the upload must be gone once
        # this returns -- it is redundant (and would never be cleaned up
        # otherwise) once the bytes are durably in R2.
        assert not os.path.isfile(captured["path_at_call_time"])

    def test_falls_back_to_local_temp_path_when_r2_not_configured(
        self, app_ctx, monkeypatch
    ):
        """Unchanged behavior for dev/test/single-process deployments --
        this is the exact case ``test_p01_async_plate_blur.py`` /
        ``test_m06_image_cap_and_pixel_bomb.py`` already depend on."""
        from kk.media_processing import stage_upload_for_async_job

        app = app_ctx[0]
        for key in _R2_KEYS:
            assert key not in app.config or not app.config.get(key)

        monkeypatch.setattr(
            r2_ops_module,
            "r2_put_file",
            lambda **_kw: pytest.fail("r2_put_file must not be called when R2 is not configured"),
        )

        data = _tiny_jpeg_bytes()
        fs = _FakeFileStorage(data, "photo.jpg")

        with app.app_context():
            temp_abs, source_r2_key = stage_upload_for_async_job(
                fs, filename_hint="photo.jpg"
            )

        assert source_r2_key is None
        assert temp_abs is not None
        assert os.path.isfile(temp_abs)
        with open(temp_abs, "rb") as fh:
            assert fh.read() == data


# ---------------------------------------------------------------------------
# B. _process_image_path(source_r2_key=...)
# ---------------------------------------------------------------------------


class TestProcessImagePathWithR2Staging:
    def test_downloads_from_r2_processes_and_cleans_up_both(
        self, app_ctx, r2_configured, monkeypatch, tmp_path
    ):
        from kk.tasks import image_tasks

        app = app_ctx[0]
        source_bytes = _tiny_jpeg_bytes()

        get_calls: list[dict] = []

        def fake_r2_get_file(*, key, dest_path, timeout=120):
            get_calls.append({"key": key, "dest_path": dest_path})
            with open(dest_path, "wb") as fh:
                fh.write(source_bytes)

        delete_calls: list[str] = []
        monkeypatch.setattr(r2_ops_module, "r2_get_file", fake_r2_get_file)
        monkeypatch.setattr(
            r2_ops_module, "r2_delete_object", lambda *, key, timeout=30: delete_calls.append(key)
        )

        with app.app_context():
            result = image_tasks._process_image_path(
                temp_abs=None,
                original_filename="photo.jpg",
                inline_base64=False,
                skip_blur=True,
                source_r2_key="car_photos/_staging/abc123.jpg",
            )

        assert result.get("rel_path")
        assert len(get_calls) == 1
        assert get_calls[0]["key"] == "car_photos/_staging/abc123.jpg"
        downloaded_path = get_calls[0]["dest_path"]
        # The worker's own downloaded copy must be removed once processing
        # finishes -- never left behind on the worker's disk.
        assert not os.path.isfile(downloaded_path)
        # The R2 staging object itself must also be cleaned up.
        assert delete_calls == ["car_photos/_staging/abc123.jpg"]

    def test_r2_staged_source_cleans_up_even_on_bomb_rejection(
        self, app_ctx, r2_configured, monkeypatch
    ):
        from kk import media_processing
        from kk.tasks import image_tasks

        app = app_ctx[0]
        monkeypatch.setattr(PILImage, "MAX_IMAGE_PIXELS", 100)

        def fake_r2_get_file(*, key, dest_path, timeout=120):
            with open(dest_path, "wb") as fh:
                fh.write(_tiny_jpeg_bytes())

        delete_calls: list[str] = []
        monkeypatch.setattr(r2_ops_module, "r2_get_file", fake_r2_get_file)
        monkeypatch.setattr(
            r2_ops_module, "r2_delete_object", lambda *, key, timeout=30: delete_calls.append(key)
        )
        mock_persist = MagicMock()
        monkeypatch.setattr(media_processing, "persist_jpeg_bytes", mock_persist)

        with app.app_context():
            with pytest.raises(media_processing.DecompressionBombRejected):
                image_tasks._process_image_path(
                    temp_abs=None,
                    original_filename="photo.jpg",
                    inline_base64=False,
                    skip_blur=True,
                    source_r2_key="car_photos/_staging/bomb.jpg",
                )

        mock_persist.assert_not_called()
        # Cleanup must still happen even though processing raised.
        assert delete_calls == ["car_photos/_staging/bomb.jpg"]


# ---------------------------------------------------------------------------
# C. HTTP-level: both async-enqueue routes stage via R2 when configured
# ---------------------------------------------------------------------------


class TestAsyncEnqueueRoutesStageViaR2:
    def test_process_car_images_async_stages_via_r2_not_local_path(
        self, app_ctx, client, r2_configured, monkeypatch
    ):
        ctx = _setup_seller(app_ctx, client)
        fake_task = _FakeTask()
        monkeypatch.setattr(ai_routes, "process_car_image_file", fake_task)

        staged_paths_at_call_time: list[str] = []

        def fake_r2_put_file(*, key, file_path, content_type, timeout=120):
            staged_paths_at_call_time.append(file_path)
            assert os.path.isfile(file_path)

        monkeypatch.setattr(r2_ops_module, "r2_put_file", fake_r2_put_file)

        resp = client.post(
            "/api/process-car-images?async=1",
            data={"images": (BytesIO(_tiny_jpeg_bytes()), "photo.jpg")},
            headers=_auth(ctx["token"]),
            content_type="multipart/form-data",
        )
        assert resp.status_code == 202, resp.get_json()
        assert len(resp.get_json()["job_ids"]) == 1
        assert len(fake_task.calls) == 1

        args, kwargs = fake_task.calls[0]
        temp_abs = args[0]
        # Web process must hand the worker an R2 key, not a path meaningful
        # only on this machine's own disk.
        assert temp_abs is None
        assert kwargs["source_r2_key"].startswith("car_photos/_staging/")
        # And the local copy this route made to stage it must already be
        # gone by the time the response is returned.
        assert len(staged_paths_at_call_time) == 1
        assert not os.path.isfile(staged_paths_at_call_time[0])

    def test_car_images_async_upload_stages_via_r2_not_local_path(
        self, app_ctx, client, r2_configured, monkeypatch
    ):
        ctx = _setup_seller(app_ctx, client)
        fake_task = _FakeTask()
        monkeypatch.setattr(media_routes, "process_car_image_file", fake_task)
        monkeypatch.setattr(
            r2_ops_module,
            "r2_put_file",
            lambda *, key, file_path, content_type, timeout=120: None,
        )

        resp = client.post(
            f"/api/cars/{ctx['car_public_id']}/images?async=1",
            data={"files": (BytesIO(_tiny_jpeg_bytes()), "photo.jpg")},
            headers=_auth(ctx["token"]),
            content_type="multipart/form-data",
        )
        assert resp.status_code == 202, resp.get_json()
        assert len(fake_task.calls) == 1
        args, kwargs = fake_task.calls[0]
        assert args[0] is None
        assert kwargs["source_r2_key"].startswith("car_photos/_staging/")

    def test_async_enqueue_still_works_without_r2_configured(
        self, app_ctx, client, monkeypatch
    ):
        """Regression guard: with R2 unconfigured (dev/test default for
        this module), both routes must keep behaving exactly like before
        this fix -- a real local temp_abs, no source_r2_key."""
        ctx = _setup_seller(app_ctx, client)
        fake_task = _FakeTask()
        monkeypatch.setattr(ai_routes, "process_car_image_file", fake_task)
        monkeypatch.setattr(
            r2_ops_module,
            "r2_put_file",
            lambda **_kw: pytest.fail("r2_put_file must not be called when R2 is not configured"),
        )

        resp = client.post(
            "/api/process-car-images?async=1",
            data={"images": (BytesIO(_tiny_jpeg_bytes()), "photo.jpg")},
            headers=_auth(ctx["token"]),
            content_type="multipart/form-data",
        )
        assert resp.status_code == 202, resp.get_json()
        args, kwargs = fake_task.calls[0]
        assert os.path.isfile(args[0])
        assert kwargs.get("source_r2_key") is None


# ---------------------------------------------------------------------------
# D. cleanup_stale_image_staging_objects (Celery Beat backstop sweep)
# ---------------------------------------------------------------------------


class TestCleanupStaleImageStagingObjects:
    def test_noop_when_r2_not_configured(self, app_ctx, monkeypatch):
        from kk.tasks import image_tasks

        app = app_ctx[0]
        monkeypatch.setattr(
            r2_ops_module,
            "r2_cleanup_stale_staging",
            lambda **_kw: pytest.fail("must not call R2 when it is not configured"),
        )
        with app.app_context():
            out = image_tasks.cleanup_stale_image_staging_objects.run()
        assert out["ok"] is True
        assert out["deleted"] == 0

    def test_delegates_to_r2_cleanup_with_expected_prefix_and_age(
        self, app_ctx, r2_configured, monkeypatch
    ):
        from kk.tasks import image_tasks

        app = app_ctx[0]
        captured: dict = {}

        def fake_cleanup(*, prefix, older_than_seconds, timeout=60):
            captured["prefix"] = prefix
            captured["older_than_seconds"] = older_than_seconds
            return 5

        monkeypatch.setattr(r2_ops_module, "r2_cleanup_stale_staging", fake_cleanup)

        with app.app_context():
            out = image_tasks.cleanup_stale_image_staging_objects.run()

        assert out == {"ok": True, "deleted": 5}
        assert captured["prefix"] == "car_photos/_staging/"
        assert captured["older_than_seconds"] == 6 * 3600
