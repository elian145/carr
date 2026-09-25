"""Phase 3A of the server-side video transcode fallback: PROMOTION/ATTACH.

Covers ``POST /api/media/r2/attach-transcoded-video``
(``kk/routes/media.py::attach_transcoded_video``):

  - AUTH: unauthenticated rejected, wrong car owner rejected, task owned
    by a different user rejected.
  - JOB: unknown task rejected, pending task rejected, failed task
    rejected, SUCCESS accepted, task/draft mismatch rejected.
  - OBJECT: missing / zero-byte / oversized processed object rejected.
  - SUCCESS: copied to a permanent key, ``CarVideo`` row created,
    processed staging object deleted after success, normal media
    response shape.
  - IDEMPOTENCY: exact retry returns the same row (no duplicate
    copy/create), a concurrent-insert race is resolved via the DB unique
    constraint, retry after the staging object was already deleted still
    succeeds.
  - FAILURE ORDERING: R2 copy failure -> no DB row + staging retained;
    DB commit failure after a successful copy -> retry recoverable;
    staging-delete failure after a successful commit -> attach still
    reports success.
  - LIMITS: the per-listing video cap is enforced for a *new* draft, but
    an already-attached draft stays retrievable even once the listing is
    at/over that cap.
  - FEATURE FLAG: disabled -> feature-not-found response; enabled -> works.

Every R2 call (HEAD/copy/delete) and every Celery
``AsyncResult``/idempotent-enqueue lookup is mocked -- no real R2
credentials, Celery worker, or ffmpeg binary are required to run this
file.
"""

from __future__ import annotations

import os
import sys
import tempfile
import uuid
from pathlib import Path

import pytest
import sqlalchemy as sa

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

import kk.r2_ops as r2_ops_module  # noqa: E402
import kk.video_transcoding as vt  # noqa: E402

_PASSWORD = "Aa123456!"
_R2_KEYS = (
    "R2_ACCOUNT_ID",
    "R2_BUCKET_NAME",
    "R2_ACCESS_KEY_ID",
    "R2_SECRET_ACCESS_KEY",
)
_ATTACH_URL = "/api/media/r2/attach-transcoded-video"


# ---------------------------------------------------------------------------
# Fixtures (mirrors test_video_transcode_phase2.py's conventions)
# ---------------------------------------------------------------------------


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_vidattach_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "vidattach.db")
    os.environ["UPLOAD_FOLDER"] = os.path.join(tmp.name, "uploads")
    for key in _R2_KEYS + ("R2_PUBLIC_URL",):
        os.environ.pop(key, None)

    from kk.app_factory import create_app

    app, socketio, *_ = create_app()
    app.config["R2_PUBLIC_URL"] = "https://cdn.example.com"
    from kk.models import Car, CarVideo, User, db

    with app.app_context():
        db.drop_all()
        db.create_all()

    yield app, socketio, app.test_client(), db, User, Car, CarVideo

    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    tmp.cleanup()


@pytest.fixture
def client(app_ctx):
    return app_ctx[2]


@pytest.fixture
def r2_configured(app_ctx, monkeypatch):
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
    return f"078{uuid.uuid4().int % 10**8:08d}"


def _make_user(app_ctx, *, username: str, phone: str) -> tuple[str, int]:
    app, _socketio, _client, db, User, *_ = app_ctx
    with app.app_context():
        existing = User.query.filter_by(username=username).first()
        if existing:
            return existing.public_id, existing.id
        user = User(
            username=username,
            phone_number=phone,
            first_name=username.title(),
            last_name="Test",
            email=None,
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id=f"pub-{uuid.uuid4().hex[:12]}",
        )
        user.set_password(_PASSWORD)
        db.session.add(user)
        db.session.commit()
        return user.public_id, user.id


def _login(client, username: str) -> str:
    r = client.post("/api/auth/login", json={"username": username, "password": _PASSWORD})
    assert r.status_code == 200, r.data
    return r.get_json()["access_token"]


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture(scope="module")
def seller_ctx(app_ctx):
    username = f"vid3a_seller_{uuid.uuid4().hex[:8]}"
    public_id, user_id = _make_user(app_ctx, username=username, phone=_unique_phone())
    return username, public_id, user_id


@pytest.fixture(scope="module")
def other_seller_ctx(app_ctx):
    username = f"vid3a_other_{uuid.uuid4().hex[:8]}"
    public_id, user_id = _make_user(app_ctx, username=username, phone=_unique_phone())
    return username, public_id, user_id


def _make_car(app_ctx, seller_id: int) -> tuple[int, str]:
    app, _socketio, _client, db, _User, Car, _CarVideo = app_ctx
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


def _video_rows(app_ctx, car_id: int):
    app, _socketio, _client, db, _User, _Car, CarVideo = app_ctx
    with app.app_context():
        return CarVideo.query.filter_by(car_id=car_id).all()


def _video_count(app_ctx, car_id: int) -> int:
    return len(_video_rows(app_ctx, car_id))


def _new_task_id(tag: str) -> str:
    return f"task-{tag}-{uuid.uuid4().hex[:16]}"


def _new_draft_id() -> str:
    return f"draft-{uuid.uuid4().hex[:16]}"


def _processed_key(app_ctx, owner_public_id: str, draft_media_id: str) -> str:
    """``processed_video_staging_key()`` reads ``current_app.config`` (the
    HMAC secret), so it needs an app context outside of a request."""
    from kk.media_processing import processed_video_staging_key

    app = app_ctx[0]
    with app.app_context():
        return processed_video_staging_key(owner_public_id, draft_media_id)


def _permanent_key(app_ctx, owner_public_id: str, car_public_id: str, draft_media_id: str) -> str:
    """Same app-context requirement as ``_processed_key`` above, for the
    deterministic permanent-video key helper."""
    from kk.media_processing import transcoded_video_permanent_key

    app = app_ctx[0]
    with app.app_context():
        return transcoded_video_permanent_key(owner_public_id, car_public_id, draft_media_id)


class _FakeAsyncResult:
    def __init__(self, state: str, result=None):
        self.state = state
        self.result = result


def _setup_job(
    monkeypatch,
    *,
    owner_public_id: str,
    draft_media_id: str,
    task_id: str,
    state: str = "SUCCESS",
    result=None,
    bind: bool = True,
):
    """Registers ownership + the dedupe-key -> task_id binding (unless
    ``bind`` is False, used by the "unknown task" tests) and mocks
    ``transcode_car_video_source.AsyncResult`` to report ``state``."""
    from kk.job_ownership import register_idempotent_job_task_id, register_job_owner
    from kk.tasks import video_tasks

    if bind:
        register_job_owner(task_id, owner_public_id)
        dedupe_key = video_tasks.video_job_dedupe_key(owner_public_id, draft_media_id)
        register_idempotent_job_task_id(dedupe_key, task_id)

    monkeypatch.setattr(
        video_tasks.transcode_car_video_source,
        "AsyncResult",
        lambda tid: _FakeAsyncResult(state, result),
    )


def _install_r2_fakes(monkeypatch, *, processed_key: str, processed_meta: dict):
    """Fakes r2_head_object/r2_copy_object/r2_delete_object as a small
    coherent in-memory R2, keyed off ``processed_key`` for the staging
    object and dynamically tracking whatever destination key(s) a copy
    call writes to. Returns the mutable ``state`` dict so tests can
    inspect calls / inject failures / simulate staging having already
    been deleted."""
    state = {
        "copy_calls": [],
        "delete_calls": [],
        "copied_keys": {},  # dest_key -> size
        "copy_exc": None,
        "delete_exc": None,
        "staging_deleted": False,
    }

    def fake_head(*, key, timeout=30):
        if key == processed_key:
            if state["staging_deleted"]:
                return {"exists": False, "size": None, "content_type": None}
            return dict(processed_meta)
        if key in state["copied_keys"]:
            return {
                "exists": True,
                "size": state["copied_keys"][key],
                "content_type": "video/mp4",
            }
        return {"exists": False, "size": None, "content_type": None}

    def fake_copy(*, source_key, dest_key, content_type=None, timeout=60):
        state["copy_calls"].append(
            {"source_key": source_key, "dest_key": dest_key, "content_type": content_type}
        )
        if state["copy_exc"] is not None:
            raise state["copy_exc"]
        state["copied_keys"][dest_key] = int(processed_meta.get("size") or 0)

    def fake_delete(*, key, timeout=30):
        state["delete_calls"].append(key)
        if key == processed_key:
            state["staging_deleted"] = True
        if state["delete_exc"] is not None:
            raise state["delete_exc"]

    monkeypatch.setattr(r2_ops_module, "r2_head_object", fake_head)
    monkeypatch.setattr(r2_ops_module, "r2_copy_object", fake_copy)
    monkeypatch.setattr(r2_ops_module, "r2_delete_object", fake_delete)
    return state


def _attach(client, token, *, car_id, draft_media_id, task_id):
    return client.post(
        _ATTACH_URL,
        json={"car_id": car_id, "draft_media_id": draft_media_id, "task_id": task_id},
        headers=_auth(token),
    )


def _good_meta(size: int = 2048) -> dict:
    return {"exists": True, "size": size, "content_type": "video/mp4"}


# ---------------------------------------------------------------------------
# FEATURE FLAG
# ---------------------------------------------------------------------------


class TestFeatureFlag:
    def test_disabled_returns_not_found(self, app_ctx, client, r2_configured, seller_ctx, monkeypatch):
        monkeypatch.delenv("VIDEO_SOURCE_STAGING_ENABLED", raising=False)
        username, owner_public_id, seller_id = seller_ctx
        car_id, car_public_id = _make_car(app_ctx, seller_id)
        draft_media_id = _new_draft_id()
        task_id = _new_task_id("flagoff")

        _install_r2_fakes(
            monkeypatch,
            processed_key=_processed_key(app_ctx, owner_public_id, draft_media_id),
            processed_meta=_good_meta(),
        )
        _setup_job(monkeypatch, owner_public_id=owner_public_id, draft_media_id=draft_media_id, task_id=task_id)

        token = _login(client, username)
        r = _attach(client, token, car_id=car_public_id, draft_media_id=draft_media_id, task_id=task_id)
        assert r.status_code == 404, r.data
        assert _video_count(app_ctx, car_id) == 0

    def test_enabled_works(self, app_ctx, client, r2_configured, seller_ctx, monkeypatch):
        # _enable_video_source_staging autouse fixture already sets this.
        username, owner_public_id, seller_id = seller_ctx
        car_id, car_public_id = _make_car(app_ctx, seller_id)
        draft_media_id = _new_draft_id()
        task_id = _new_task_id("flagon")

        _install_r2_fakes(
            monkeypatch,
            processed_key=_processed_key(app_ctx, owner_public_id, draft_media_id),
            processed_meta=_good_meta(),
        )
        _setup_job(monkeypatch, owner_public_id=owner_public_id, draft_media_id=draft_media_id, task_id=task_id)

        token = _login(client, username)
        r = _attach(client, token, car_id=car_public_id, draft_media_id=draft_media_id, task_id=task_id)
        assert r.status_code == 201, r.data
        assert _video_count(app_ctx, car_id) == 1


# ---------------------------------------------------------------------------
# AUTH
# ---------------------------------------------------------------------------


class TestAuth:
    def test_unauthenticated_rejected(self, app_ctx, client, r2_configured, seller_ctx):
        _username, _owner, seller_id = seller_ctx
        car_id, car_public_id = _make_car(app_ctx, seller_id)
        r = client.post(
            _ATTACH_URL,
            json={
                "car_id": car_public_id,
                "draft_media_id": _new_draft_id(),
                "task_id": _new_task_id("noauth"),
            },
        )
        assert r.status_code == 401, r.data

    def test_wrong_car_owner_rejected(self, app_ctx, client, r2_configured, seller_ctx, other_seller_ctx, monkeypatch):
        _username, owner_public_id, seller_id = seller_ctx
        other_username, _other_owner, _other_id = other_seller_ctx
        car_id, car_public_id = _make_car(app_ctx, seller_id)  # owned by seller_ctx
        draft_media_id = _new_draft_id()
        task_id = _new_task_id("wrongowner")

        _install_r2_fakes(
            monkeypatch,
            processed_key=_processed_key(app_ctx, owner_public_id, draft_media_id),
            processed_meta=_good_meta(),
        )
        _setup_job(monkeypatch, owner_public_id=owner_public_id, draft_media_id=draft_media_id, task_id=task_id)

        other_token = _login(client, other_username)
        r = _attach(client, other_token, car_id=car_public_id, draft_media_id=draft_media_id, task_id=task_id)
        assert r.status_code == 403, r.data
        assert _video_count(app_ctx, car_id) == 0

    def test_task_owned_by_different_user_rejected(
        self, app_ctx, client, r2_configured, seller_ctx, other_seller_ctx, monkeypatch
    ):
        username, owner_public_id, seller_id = seller_ctx
        _other_username, other_owner_public_id, _other_id = other_seller_ctx
        car_id, car_public_id = _make_car(app_ctx, seller_id)
        draft_media_id = _new_draft_id()
        task_id = _new_task_id("otherowner")

        # The task/dedupe binding belongs to the OTHER user, not the caller.
        _install_r2_fakes(
            monkeypatch,
            processed_key=_processed_key(app_ctx, other_owner_public_id, draft_media_id),
            processed_meta=_good_meta(),
        )
        _setup_job(
            monkeypatch,
            owner_public_id=other_owner_public_id,
            draft_media_id=draft_media_id,
            task_id=task_id,
        )

        token = _login(client, username)  # caller is seller_ctx, task belongs to other_seller_ctx
        r = _attach(client, token, car_id=car_public_id, draft_media_id=draft_media_id, task_id=task_id)
        assert r.status_code == 403, r.data
        assert _video_count(app_ctx, car_id) == 0


# ---------------------------------------------------------------------------
# JOB
# ---------------------------------------------------------------------------


class TestJob:
    def test_unknown_task_rejected(self, app_ctx, client, r2_configured, seller_ctx, monkeypatch):
        username, owner_public_id, seller_id = seller_ctx
        car_id, car_public_id = _make_car(app_ctx, seller_id)
        draft_media_id = _new_draft_id()
        task_id = _new_task_id("unknown")

        _install_r2_fakes(
            monkeypatch,
            processed_key=_processed_key(app_ctx, owner_public_id, draft_media_id),
            processed_meta=_good_meta(),
        )
        # Never registered/bound anywhere -- simulates a task_id nobody ever enqueued.
        _setup_job(
            monkeypatch,
            owner_public_id=owner_public_id,
            draft_media_id=draft_media_id,
            task_id=task_id,
            bind=False,
        )

        token = _login(client, username)
        r = _attach(client, token, car_id=car_public_id, draft_media_id=draft_media_id, task_id=task_id)
        assert r.status_code == 403, r.data
        assert _video_count(app_ctx, car_id) == 0

    def test_pending_task_rejected(self, app_ctx, client, r2_configured, seller_ctx, monkeypatch):
        username, owner_public_id, seller_id = seller_ctx
        car_id, car_public_id = _make_car(app_ctx, seller_id)
        draft_media_id = _new_draft_id()
        task_id = _new_task_id("pending")

        _install_r2_fakes(
            monkeypatch,
            processed_key=_processed_key(app_ctx, owner_public_id, draft_media_id),
            processed_meta=_good_meta(),
        )
        _setup_job(
            monkeypatch,
            owner_public_id=owner_public_id,
            draft_media_id=draft_media_id,
            task_id=task_id,
            state="STARTED",
        )

        token = _login(client, username)
        r = _attach(client, token, car_id=car_public_id, draft_media_id=draft_media_id, task_id=task_id)
        assert r.status_code == 409, r.data
        assert _video_count(app_ctx, car_id) == 0

    def test_failed_task_rejected(self, app_ctx, client, r2_configured, seller_ctx, monkeypatch):
        username, owner_public_id, seller_id = seller_ctx
        car_id, car_public_id = _make_car(app_ctx, seller_id)
        draft_media_id = _new_draft_id()
        task_id = _new_task_id("failed")

        _install_r2_fakes(
            monkeypatch,
            processed_key=_processed_key(app_ctx, owner_public_id, draft_media_id),
            processed_meta=_good_meta(),
        )
        _setup_job(
            monkeypatch,
            owner_public_id=owner_public_id,
            draft_media_id=draft_media_id,
            task_id=task_id,
            state="FAILURE",
        )

        token = _login(client, username)
        r = _attach(client, token, car_id=car_public_id, draft_media_id=draft_media_id, task_id=task_id)
        assert r.status_code == 400, r.data
        assert _video_count(app_ctx, car_id) == 0

    def test_success_accepted(self, app_ctx, client, r2_configured, seller_ctx, monkeypatch):
        username, owner_public_id, seller_id = seller_ctx
        car_id, car_public_id = _make_car(app_ctx, seller_id)
        draft_media_id = _new_draft_id()
        task_id = _new_task_id("success")

        _install_r2_fakes(
            monkeypatch,
            processed_key=_processed_key(app_ctx, owner_public_id, draft_media_id),
            processed_meta=_good_meta(),
        )
        _setup_job(monkeypatch, owner_public_id=owner_public_id, draft_media_id=draft_media_id, task_id=task_id)

        token = _login(client, username)
        r = _attach(client, token, car_id=car_public_id, draft_media_id=draft_media_id, task_id=task_id)
        assert r.status_code == 201, r.data
        assert _video_count(app_ctx, car_id) == 1

    def test_task_draft_mismatch_rejected(self, app_ctx, client, r2_configured, seller_ctx, monkeypatch):
        """The task's own structured result reports a DIFFERENT
        draft_media_id than the one supplied in the request -- rejected
        even though the dedupe-key binding lookup itself uses the
        request's draft_media_id (defense-in-depth cross-check)."""
        username, owner_public_id, seller_id = seller_ctx
        car_id, car_public_id = _make_car(app_ctx, seller_id)
        draft_media_id = _new_draft_id()
        other_draft_media_id = _new_draft_id()
        task_id = _new_task_id("mismatch")

        _install_r2_fakes(
            monkeypatch,
            processed_key=_processed_key(app_ctx, owner_public_id, draft_media_id),
            processed_meta=_good_meta(),
        )
        _setup_job(
            monkeypatch,
            owner_public_id=owner_public_id,
            draft_media_id=draft_media_id,
            task_id=task_id,
            result={"owner_public_id": owner_public_id, "draft_media_id": other_draft_media_id},
        )

        token = _login(client, username)
        r = _attach(client, token, car_id=car_public_id, draft_media_id=draft_media_id, task_id=task_id)
        assert r.status_code == 403, r.data
        assert _video_count(app_ctx, car_id) == 0


# ---------------------------------------------------------------------------
# OBJECT
# ---------------------------------------------------------------------------


class TestObject:
    def test_missing_object_rejected(self, app_ctx, client, r2_configured, seller_ctx, monkeypatch):
        username, owner_public_id, seller_id = seller_ctx
        car_id, car_public_id = _make_car(app_ctx, seller_id)
        draft_media_id = _new_draft_id()
        task_id = _new_task_id("missing")

        _install_r2_fakes(
            monkeypatch,
            processed_key=_processed_key(app_ctx, owner_public_id, draft_media_id),
            processed_meta={"exists": False, "size": None, "content_type": None},
        )
        _setup_job(monkeypatch, owner_public_id=owner_public_id, draft_media_id=draft_media_id, task_id=task_id)

        token = _login(client, username)
        r = _attach(client, token, car_id=car_public_id, draft_media_id=draft_media_id, task_id=task_id)
        assert r.status_code == 404, r.data
        assert _video_count(app_ctx, car_id) == 0

    def test_zero_byte_object_rejected(self, app_ctx, client, r2_configured, seller_ctx, monkeypatch):
        username, owner_public_id, seller_id = seller_ctx
        car_id, car_public_id = _make_car(app_ctx, seller_id)
        draft_media_id = _new_draft_id()
        task_id = _new_task_id("zerobyte")

        _install_r2_fakes(
            monkeypatch,
            processed_key=_processed_key(app_ctx, owner_public_id, draft_media_id),
            processed_meta={"exists": True, "size": 0, "content_type": "video/mp4"},
        )
        _setup_job(monkeypatch, owner_public_id=owner_public_id, draft_media_id=draft_media_id, task_id=task_id)

        token = _login(client, username)
        r = _attach(client, token, car_id=car_public_id, draft_media_id=draft_media_id, task_id=task_id)
        assert r.status_code == 400, r.data
        assert _video_count(app_ctx, car_id) == 0

    def test_oversized_object_rejected(self, app_ctx, client, r2_configured, seller_ctx, monkeypatch):
        username, owner_public_id, seller_id = seller_ctx
        car_id, car_public_id = _make_car(app_ctx, seller_id)
        draft_media_id = _new_draft_id()
        task_id = _new_task_id("oversized")

        _install_r2_fakes(
            monkeypatch,
            processed_key=_processed_key(app_ctx, owner_public_id, draft_media_id),
            processed_meta={"exists": True, "size": vt.FINAL_MAX_BYTES + 1, "content_type": "video/mp4"},
        )
        _setup_job(monkeypatch, owner_public_id=owner_public_id, draft_media_id=draft_media_id, task_id=task_id)

        token = _login(client, username)
        r = _attach(client, token, car_id=car_public_id, draft_media_id=draft_media_id, task_id=task_id)
        assert r.status_code == 400, r.data
        assert _video_count(app_ctx, car_id) == 0


# ---------------------------------------------------------------------------
# SUCCESS
# ---------------------------------------------------------------------------


class TestSuccess:
    def test_copied_to_permanent_key_and_row_created_and_staging_deleted(
        self, app_ctx, client, r2_configured, seller_ctx, monkeypatch
    ):
        username, owner_public_id, seller_id = seller_ctx
        car_id, car_public_id = _make_car(app_ctx, seller_id)
        draft_media_id = _new_draft_id()
        task_id = _new_task_id("full-success")

        processed_key = _processed_key(app_ctx, owner_public_id, draft_media_id)
        state = _install_r2_fakes(monkeypatch, processed_key=processed_key, processed_meta=_good_meta(size=4096))
        _setup_job(monkeypatch, owner_public_id=owner_public_id, draft_media_id=draft_media_id, task_id=task_id)

        token = _login(client, username)
        r = _attach(client, token, car_id=car_public_id, draft_media_id=draft_media_id, task_id=task_id)
        assert r.status_code == 201, r.data
        body = r.get_json()

        # Normal media response shape (mirrors the other attach endpoints).
        assert "video" in body and "videos" in body
        assert isinstance(body["videos"], list) and len(body["videos"]) == 1
        assert body["video"] == body["videos"][0]
        assert set(["id", "video_url", "thumbnail_url", "duration", "order"]).issubset(body["video"].keys())
        assert body["video"]["video_url"].startswith("https://cdn.example.com/car_videos/")

        # Copied from the processed staging key to a fresh car_videos/*.mp4 key.
        assert len(state["copy_calls"]) == 1
        assert state["copy_calls"][0]["source_key"] == processed_key
        assert state["copy_calls"][0]["dest_key"].startswith("car_videos/")
        assert state["copy_calls"][0]["dest_key"].endswith(".mp4")
        assert state["copy_calls"][0]["content_type"] == "video/mp4"

        # Exactly one CarVideo row, bound to this draft_media_id.
        rows = _video_rows(app_ctx, car_id)
        assert len(rows) == 1
        assert rows[0].source_draft_media_id == draft_media_id
        assert rows[0].video_url == body["video"]["video_url"]

        # Processed staging object deleted after the successful attach.
        assert state["delete_calls"] == [processed_key]


# ---------------------------------------------------------------------------
# IDEMPOTENCY
# ---------------------------------------------------------------------------


class TestIdempotency:
    def test_exact_retry_returns_same_row_no_duplicate(self, app_ctx, client, r2_configured, seller_ctx, monkeypatch):
        username, owner_public_id, seller_id = seller_ctx
        car_id, car_public_id = _make_car(app_ctx, seller_id)
        draft_media_id = _new_draft_id()
        task_id = _new_task_id("retry-same")

        processed_key = _processed_key(app_ctx, owner_public_id, draft_media_id)
        state = _install_r2_fakes(monkeypatch, processed_key=processed_key, processed_meta=_good_meta())
        _setup_job(monkeypatch, owner_public_id=owner_public_id, draft_media_id=draft_media_id, task_id=task_id)

        token = _login(client, username)
        r1 = _attach(client, token, car_id=car_public_id, draft_media_id=draft_media_id, task_id=task_id)
        assert r1.status_code == 201, r1.data
        video_1 = r1.get_json()["video"]

        r2 = _attach(client, token, car_id=car_public_id, draft_media_id=draft_media_id, task_id=task_id)
        assert r2.status_code == 200, r2.data
        video_2 = r2.get_json()["video"]

        assert video_1 == video_2
        assert _video_count(app_ctx, car_id) == 1
        # No second R2 copy/HEAD-chain work on the retry -- the idempotency
        # short-circuit returns before any of that.
        assert len(state["copy_calls"]) == 1

    def test_retry_after_staging_already_deleted_still_succeeds(
        self, app_ctx, client, r2_configured, seller_ctx, monkeypatch
    ):
        """A retry that arrives AFTER the first call's cleanup already
        deleted the processed staging object must still return the
        existing row (the idempotency short-circuit never touches R2 at
        all)."""
        username, owner_public_id, seller_id = seller_ctx
        car_id, car_public_id = _make_car(app_ctx, seller_id)
        draft_media_id = _new_draft_id()
        task_id = _new_task_id("retry-after-delete")

        processed_key = _processed_key(app_ctx, owner_public_id, draft_media_id)
        state = _install_r2_fakes(monkeypatch, processed_key=processed_key, processed_meta=_good_meta())
        _setup_job(monkeypatch, owner_public_id=owner_public_id, draft_media_id=draft_media_id, task_id=task_id)

        token = _login(client, username)
        r1 = _attach(client, token, car_id=car_public_id, draft_media_id=draft_media_id, task_id=task_id)
        assert r1.status_code == 201, r1.data
        assert state["staging_deleted"] is True

        r2 = _attach(client, token, car_id=car_public_id, draft_media_id=draft_media_id, task_id=task_id)
        assert r2.status_code == 200, r2.data
        assert r2.get_json()["video"] == r1.get_json()["video"]
        assert _video_count(app_ctx, car_id) == 1

    def test_concurrent_race_protected_by_db_uniqueness(
        self, app_ctx, client, r2_configured, seller_ctx, monkeypatch
    ):
        """Simulates a genuine race: another request's row is inserted and
        committed (via a raw, independent connection) in the narrow window
        between this request's own idempotency check and its own commit.
        The unique constraint must turn the resulting IntegrityError into
        the same idempotent success response, not a 500 and not two rows.
        """
        username, owner_public_id, seller_id = seller_ctx
        car_id, car_public_id = _make_car(app_ctx, seller_id)
        draft_media_id = _new_draft_id()
        task_id = _new_task_id("race")

        processed_key = _processed_key(app_ctx, owner_public_id, draft_media_id)
        _install_r2_fakes(monkeypatch, processed_key=processed_key, processed_meta=_good_meta())
        _setup_job(monkeypatch, owner_public_id=owner_public_id, draft_media_id=draft_media_id, task_id=task_id)

        # Log in BEFORE patching commit -- login itself may also commit, and
        # that must not consume the "first call" slot below (otherwise the
        # shadow row would already exist before the idempotency check even
        # runs, short-circuiting the test without ever exercising the
        # IntegrityError-recovery path this test is meant to prove).
        token = _login(client, username)

        app, _socketio, _client, db, *_ = app_ctx
        real_commit_fn = sa.orm.Session.commit
        call_count = {"n": 0}
        shadow_url = "https://cdn.example.com/car_videos/shadow-race-winner.mp4"

        def racing_commit(*args, **kwargs):
            call_count["n"] += 1
            if call_count["n"] == 1:
                # A "concurrent" request wins the race first, via a fully
                # independent connection/transaction.
                with db.engine.begin() as conn:
                    conn.execute(
                        sa.text(
                            "INSERT INTO car_video (car_id, video_url, source_draft_media_id) "
                            "VALUES (:car_id, :video_url, :draft)"
                        ),
                        {"car_id": car_id, "video_url": shadow_url, "draft": draft_media_id},
                    )
                # Now let the real commit proceed -- it must now fail with
                # a unique-constraint violation because of the row above.
                return real_commit_fn(db.session(), *args, **kwargs)
            return real_commit_fn(db.session(), *args, **kwargs)

        monkeypatch.setattr(db.session, "commit", racing_commit)

        r = _attach(client, token, car_id=car_public_id, draft_media_id=draft_media_id, task_id=task_id)
        assert call_count["n"] == 1  # racing_commit really was invoked by THIS request
        assert r.status_code == 200, r.data  # idempotent-response path, not 201
        assert r.get_json()["video"]["video_url"] == shadow_url

        # Exactly the one (shadow) row -- our own attempt never persisted.
        rows = _video_rows(app_ctx, car_id)
        assert len(rows) == 1
        assert rows[0].video_url == shadow_url


# ---------------------------------------------------------------------------
# FAILURE ORDERING
# ---------------------------------------------------------------------------


class TestFailureOrdering:
    def test_copy_failure_leaves_no_db_row_and_staging_retained(
        self, app_ctx, client, r2_configured, seller_ctx, monkeypatch
    ):
        username, owner_public_id, seller_id = seller_ctx
        car_id, car_public_id = _make_car(app_ctx, seller_id)
        draft_media_id = _new_draft_id()
        task_id = _new_task_id("copyfail")

        processed_key = _processed_key(app_ctx, owner_public_id, draft_media_id)
        state = _install_r2_fakes(monkeypatch, processed_key=processed_key, processed_meta=_good_meta())
        state["copy_exc"] = RuntimeError("simulated R2 copy failure")
        _setup_job(monkeypatch, owner_public_id=owner_public_id, draft_media_id=draft_media_id, task_id=task_id)

        token = _login(client, username)
        r = _attach(client, token, car_id=car_public_id, draft_media_id=draft_media_id, task_id=task_id)
        assert r.status_code == 502, r.data
        assert _video_count(app_ctx, car_id) == 0
        assert len(state["copy_calls"]) == 1
        assert state["delete_calls"] == []  # staging never touched

    def test_db_failure_after_copy_is_retry_recoverable(
        self, app_ctx, client, r2_configured, seller_ctx, monkeypatch
    ):
        username, owner_public_id, seller_id = seller_ctx
        car_id, car_public_id = _make_car(app_ctx, seller_id)
        draft_media_id = _new_draft_id()
        task_id = _new_task_id("dbfail")

        processed_key = _processed_key(app_ctx, owner_public_id, draft_media_id)
        state = _install_r2_fakes(monkeypatch, processed_key=processed_key, processed_meta=_good_meta())
        _setup_job(monkeypatch, owner_public_id=owner_public_id, draft_media_id=draft_media_id, task_id=task_id)

        # Log in BEFORE patching commit -- login itself may also commit, and
        # the "fail exactly once" budget below must apply to the attach
        # endpoint's own commit, not an unrelated earlier one.
        token = _login(client, username)

        app, _socketio, _client, db, *_ = app_ctx
        real_commit_fn = sa.orm.Session.commit
        call_count = {"n": 0}

        def flaky_commit(*args, **kwargs):
            call_count["n"] += 1
            if call_count["n"] == 1:
                raise RuntimeError("simulated DB failure after copy")
            return real_commit_fn(db.session(), *args, **kwargs)

        monkeypatch.setattr(db.session, "commit", flaky_commit)

        r1 = _attach(client, token, car_id=car_public_id, draft_media_id=draft_media_id, task_id=task_id)
        assert r1.status_code == 500, r1.data
        assert _video_count(app_ctx, car_id) == 0
        # The (orphaned, but not really -- see below) permanent copy from
        # the failed attempt happened, but no DB row exists yet -- fully
        # retryable.
        assert len(state["copy_calls"]) == 1
        first_dest_key = state["copy_calls"][0]["dest_key"]

        r2 = _attach(client, token, car_id=car_public_id, draft_media_id=draft_media_id, task_id=task_id)
        assert r2.status_code == 201, r2.data
        assert _video_count(app_ctx, car_id) == 1
        # Phase 3A durability hardening: the permanent key is now
        # DETERMINISTIC, and the retry's own destination-HEAD finds it
        # already correctly populated from the first (DB-failed) attempt --
        # so it is NOT re-copied at all (no second copy call), and it is
        # definitely NOT a fresh/different key.
        assert len(state["copy_calls"]) == 1
        rows = _video_rows(app_ctx, car_id)
        assert rows[0].video_url.endswith(first_dest_key)

    def test_staging_delete_failure_does_not_undo_success(
        self, app_ctx, client, r2_configured, seller_ctx, monkeypatch
    ):
        username, owner_public_id, seller_id = seller_ctx
        car_id, car_public_id = _make_car(app_ctx, seller_id)
        draft_media_id = _new_draft_id()
        task_id = _new_task_id("deletefail")

        processed_key = _processed_key(app_ctx, owner_public_id, draft_media_id)
        state = _install_r2_fakes(monkeypatch, processed_key=processed_key, processed_meta=_good_meta())
        state["delete_exc"] = RuntimeError("simulated staging delete failure")
        _setup_job(monkeypatch, owner_public_id=owner_public_id, draft_media_id=draft_media_id, task_id=task_id)

        token = _login(client, username)
        r = _attach(client, token, car_id=car_public_id, draft_media_id=draft_media_id, task_id=task_id)
        assert r.status_code == 201, r.data  # attach itself still reports success
        assert _video_count(app_ctx, car_id) == 1
        assert state["delete_calls"] == [processed_key]  # delete was attempted


# ---------------------------------------------------------------------------
# LIMITS
# ---------------------------------------------------------------------------


class TestLimits:
    def test_limit_enforced_for_new_draft(self, app_ctx, client, r2_configured, seller_ctx, monkeypatch):
        from kk.routes.media import MAX_LISTING_VIDEOS

        username, owner_public_id, seller_id = seller_ctx
        car_id, car_public_id = _make_car(app_ctx, seller_id)

        # Fill the listing up to the cap via the endpoint itself, so each
        # video also has a distinct source_draft_media_id (matches how
        # these rows are actually created in production).
        token = _login(client, username)
        for i in range(MAX_LISTING_VIDEOS):
            draft_media_id = _new_draft_id()
            task_id = _new_task_id(f"fill-{i}")
            processed_key = _processed_key(app_ctx, owner_public_id, draft_media_id)
            _install_r2_fakes(monkeypatch, processed_key=processed_key, processed_meta=_good_meta())
            _setup_job(monkeypatch, owner_public_id=owner_public_id, draft_media_id=draft_media_id, task_id=task_id)
            r = _attach(client, token, car_id=car_public_id, draft_media_id=draft_media_id, task_id=task_id)
            assert r.status_code == 201, r.data

        assert _video_count(app_ctx, car_id) == MAX_LISTING_VIDEOS

        # One more, NEW draft -- must be rejected by the limit.
        draft_media_id = _new_draft_id()
        task_id = _new_task_id("over-limit")
        processed_key = _processed_key(app_ctx, owner_public_id, draft_media_id)
        _install_r2_fakes(monkeypatch, processed_key=processed_key, processed_meta=_good_meta())
        _setup_job(monkeypatch, owner_public_id=owner_public_id, draft_media_id=draft_media_id, task_id=task_id)
        r = _attach(client, token, car_id=car_public_id, draft_media_id=draft_media_id, task_id=task_id)
        assert r.status_code == 400, r.data
        assert _video_count(app_ctx, car_id) == MAX_LISTING_VIDEOS

    def test_already_attached_draft_retrievable_even_when_limit_full(
        self, app_ctx, client, r2_configured, seller_ctx, monkeypatch
    ):
        from kk.routes.media import MAX_LISTING_VIDEOS

        username, owner_public_id, seller_id = seller_ctx
        car_id, car_public_id = _make_car(app_ctx, seller_id)
        token = _login(client, username)

        # Attach the FIRST draft normally.
        first_draft = _new_draft_id()
        first_task = _new_task_id("first")
        first_key = _processed_key(app_ctx, owner_public_id, first_draft)
        _install_r2_fakes(monkeypatch, processed_key=first_key, processed_meta=_good_meta())
        _setup_job(monkeypatch, owner_public_id=owner_public_id, draft_media_id=first_draft, task_id=first_task)
        r = _attach(client, token, car_id=car_public_id, draft_media_id=first_draft, task_id=first_task)
        assert r.status_code == 201, r.data
        first_video = r.get_json()["video"]

        # Fill the REMAINING capacity with other drafts so the listing is
        # now completely full.
        for i in range(MAX_LISTING_VIDEOS - 1):
            draft_media_id = _new_draft_id()
            task_id = _new_task_id(f"fill2-{i}")
            processed_key = _processed_key(app_ctx, owner_public_id, draft_media_id)
            _install_r2_fakes(monkeypatch, processed_key=processed_key, processed_meta=_good_meta())
            _setup_job(monkeypatch, owner_public_id=owner_public_id, draft_media_id=draft_media_id, task_id=task_id)
            r = _attach(client, token, car_id=car_public_id, draft_media_id=draft_media_id, task_id=task_id)
            assert r.status_code == 201, r.data

        assert _video_count(app_ctx, car_id) == MAX_LISTING_VIDEOS

        # Retrying the FIRST draft again (already attached) must still
        # succeed with the SAME row, even though the listing is now full.
        _install_r2_fakes(monkeypatch, processed_key=first_key, processed_meta=_good_meta())
        _setup_job(monkeypatch, owner_public_id=owner_public_id, draft_media_id=first_draft, task_id=first_task)
        r = _attach(client, token, car_id=car_public_id, draft_media_id=first_draft, task_id=first_task)
        assert r.status_code == 200, r.data
        assert r.get_json()["video"] == first_video
        assert _video_count(app_ctx, car_id) == MAX_LISTING_VIDEOS


# ---------------------------------------------------------------------------
# DETERMINISTIC PERMANENT KEY (Phase 3A durability hardening)
# ---------------------------------------------------------------------------


class TestTranscodedVideoPermanentKeyUnit:
    """Unit tests for ``kk.media_processing.transcoded_video_permanent_key``
    -- the deterministic, HMAC-derived permanent-video key that replaced
    the previous ``car_videos/{secrets.token_hex(16)}.mp4`` random token.
    """

    def test_deterministic_for_same_inputs(self, app_ctx):
        k1 = _permanent_key(app_ctx, "pub-owner-1", "car-1", "draft-1")
        k2 = _permanent_key(app_ctx, "pub-owner-1", "car-1", "draft-1")
        assert k1 == k2 and k1 is not None

    def test_namespace_and_extension(self, app_ctx):
        k = _permanent_key(app_ctx, "pub-owner-1", "car-1", "draft-1")
        assert k.startswith("car_videos/")
        assert k.endswith(".mp4")
        # Not nested under either staging prefix.
        assert "_staging" not in k
        assert "_processed_staging" not in k

    def test_opaque_no_raw_inputs_leaked_in_key(self, app_ctx):
        owner, car, draft = "pub-owner-secret", "car-public-id-123", "draft-media-abc"
        k = _permanent_key(app_ctx, owner, car, draft)
        assert owner not in k
        assert car not in k
        assert draft not in k

    def test_differs_by_owner(self, app_ctx):
        k1 = _permanent_key(app_ctx, "pub-owner-1", "car-1", "draft-1")
        k2 = _permanent_key(app_ctx, "pub-owner-2", "car-1", "draft-1")
        assert k1 != k2

    def test_differs_by_car(self, app_ctx):
        k1 = _permanent_key(app_ctx, "pub-owner-1", "car-1", "draft-1")
        k2 = _permanent_key(app_ctx, "pub-owner-1", "car-2", "draft-1")
        assert k1 != k2

    def test_differs_by_draft_media_id(self, app_ctx):
        k1 = _permanent_key(app_ctx, "pub-owner-1", "car-1", "draft-1")
        k2 = _permanent_key(app_ctx, "pub-owner-1", "car-1", "draft-2")
        assert k1 != k2

    def test_returns_none_for_invalid_draft_media_id(self, app_ctx):
        assert _permanent_key(app_ctx, "pub-owner-1", "car-1", "../x") is None

    def test_returns_none_for_missing_owner_or_car(self, app_ctx):
        assert _permanent_key(app_ctx, "", "car-1", "draft-1") is None
        assert _permanent_key(app_ctx, "pub-owner-1", "", "draft-1") is None

    def test_returns_none_without_secret_key(self, app_ctx, monkeypatch):
        app = app_ctx[0]
        with app.app_context():
            monkeypatch.setitem(app.config, "SECRET_KEY", "")
            from kk.media_processing import transcoded_video_permanent_key

            assert transcoded_video_permanent_key("pub-owner-1", "car-1", "draft-1") is None


# ---------------------------------------------------------------------------
# CRASH-POINT RECOVERY WITH THE DETERMINISTIC DESTINATION KEY
# ---------------------------------------------------------------------------


class TestDeterministicKeyCrashRecovery:
    def test_permanent_object_already_exists_but_db_row_does_not(
        self, app_ctx, client, r2_configured, seller_ctx, monkeypatch
    ):
        """Simulates crash point C/D: a PRIOR attempt's copy already
        landed at the (deterministic) permanent key, but that attempt
        never reached the DB commit (crashed, lost response, etc.) -- no
        CarVideo row exists yet. A fresh call must recognize the
        already-correct destination, skip re-copying entirely, and create
        the DB row directly."""
        username, owner_public_id, seller_id = seller_ctx
        car_id, car_public_id = _make_car(app_ctx, seller_id)
        draft_media_id = _new_draft_id()
        task_id = _new_task_id("preexisting-dest")

        processed_key = _processed_key(app_ctx, owner_public_id, draft_media_id)
        state = _install_r2_fakes(monkeypatch, processed_key=processed_key, processed_meta=_good_meta(size=3333))
        _setup_job(monkeypatch, owner_public_id=owner_public_id, draft_media_id=draft_media_id, task_id=task_id)

        # Pre-seed the destination as if a PRIOR (crashed) attempt already
        # copied successfully -- without ever going through this endpoint.
        expected_dest = _permanent_key(app_ctx, owner_public_id, car_public_id, draft_media_id)
        state["copied_keys"][expected_dest] = 3333

        token = _login(client, username)
        r = _attach(client, token, car_id=car_public_id, draft_media_id=draft_media_id, task_id=task_id)
        assert r.status_code == 201, r.data
        assert _video_count(app_ctx, car_id) == 1

        # The copy was NEVER (re-)invoked -- the pre-existing, correctly
        # sized destination was recognized and reused as-is.
        assert state["copy_calls"] == []

        rows = _video_rows(app_ctx, car_id)
        assert rows[0].video_url.endswith(expected_dest)

    def test_retry_after_copy_before_commit_reuses_same_destination_key(
        self, app_ctx, client, r2_configured, seller_ctx, monkeypatch
    ):
        """Crash point D, driven through the real endpoint twice: the
        first call's copy succeeds but its OWN commit is forced to fail;
        the retry must target the exact SAME deterministic destination
        key (never a second/different one) and succeed."""
        username, owner_public_id, seller_id = seller_ctx
        car_id, car_public_id = _make_car(app_ctx, seller_id)
        draft_media_id = _new_draft_id()
        task_id = _new_task_id("retry-same-dest")

        processed_key = _processed_key(app_ctx, owner_public_id, draft_media_id)
        state = _install_r2_fakes(monkeypatch, processed_key=processed_key, processed_meta=_good_meta())
        _setup_job(monkeypatch, owner_public_id=owner_public_id, draft_media_id=draft_media_id, task_id=task_id)

        expected_dest = _permanent_key(app_ctx, owner_public_id, car_public_id, draft_media_id)

        token = _login(client, username)

        app, _socketio, _client, db, *_ = app_ctx
        real_commit_fn = sa.orm.Session.commit
        call_count = {"n": 0}

        def flaky_commit(*args, **kwargs):
            call_count["n"] += 1
            if call_count["n"] == 1:
                raise RuntimeError("simulated crash after copy, before commit")
            return real_commit_fn(db.session(), *args, **kwargs)

        monkeypatch.setattr(db.session, "commit", flaky_commit)

        r1 = _attach(client, token, car_id=car_public_id, draft_media_id=draft_media_id, task_id=task_id)
        assert r1.status_code == 500, r1.data
        assert len(state["copy_calls"]) == 1
        assert state["copy_calls"][0]["dest_key"] == expected_dest

        r2 = _attach(client, token, car_id=car_public_id, draft_media_id=draft_media_id, task_id=task_id)
        assert r2.status_code == 201, r2.data
        # No second destination key was ever generated -- and no second
        # copy call was even needed, since the retry's own destination
        # check found the first attempt's copy already correct.
        assert len(state["copy_calls"]) == 1
        assert r2.get_json()["video"]["video_url"].endswith(expected_dest)


# ---------------------------------------------------------------------------
# JOB / DEDUPE / RESULT TTL DURABILITY AUDIT
# ---------------------------------------------------------------------------


class TestTTLDurabilityAudit:
    """Asserts the ACTUAL configured TTL relationship this feature depends
    on, rather than assuming it -- see
    ``kk/tasks/video_tasks.py::VIDEO_JOB_AUTH_TTL_SECONDS``'s docstring for
    the full rationale."""

    def test_processed_staging_ttl_is_strictly_less_than_job_auth_ttl(self):
        from kk.tasks.video_tasks import (
            VIDEO_JOB_AUTH_TTL_SECONDS,
            _PROCESSED_VIDEO_STAGING_STALE_AFTER_SECONDS,
        )

        assert _PROCESSED_VIDEO_STAGING_STALE_AFTER_SECONDS == 48 * 3600
        assert VIDEO_JOB_AUTH_TTL_SECONDS == 72 * 3600
        assert _PROCESSED_VIDEO_STAGING_STALE_AFTER_SECONDS < VIDEO_JOB_AUTH_TTL_SECONDS
        # At least a 24h safety margin (clock/scheduling skew + the
        # up-to-1h staging-cleanup sweep interval).
        margin = VIDEO_JOB_AUTH_TTL_SECONDS - _PROCESSED_VIDEO_STAGING_STALE_AFTER_SECONDS
        assert margin >= 24 * 3600

    def test_celery_result_expires_covers_the_same_window(self):
        from kk.tasks.celery_app import celery_app
        from kk.tasks.video_tasks import (
            VIDEO_JOB_AUTH_TTL_SECONDS,
            _PROCESSED_VIDEO_STAGING_STALE_AFTER_SECONDS,
        )

        result_expires = celery_app.conf.result_expires
        assert result_expires == VIDEO_JOB_AUTH_TTL_SECONDS
        assert result_expires >= _PROCESSED_VIDEO_STAGING_STALE_AFTER_SECONDS + 24 * 3600

    def test_job_owner_and_dedupe_default_ttls_are_shorter_than_processed_staging(self):
        """Documents WHY an explicit ``ttl_s=`` override was necessary at
        the video enqueue call site: the job_ownership.py module-level
        defaults (shared with unrelated, non-video callers) are still only
        24h -- deliberately UNCHANGED by this hardening pass, per the
        instruction to avoid touching unrelated idempotency records."""
        from kk.job_ownership import _DEFAULT_IDEMPOTENCY_TTL_S, _DEFAULT_TTL_S
        from kk.tasks.video_tasks import _PROCESSED_VIDEO_STAGING_STALE_AFTER_SECONDS

        assert _DEFAULT_TTL_S == 24 * 3600
        assert _DEFAULT_IDEMPOTENCY_TTL_S == 24 * 3600
        assert _DEFAULT_TTL_S < _PROCESSED_VIDEO_STAGING_STALE_AFTER_SECONDS
        assert _DEFAULT_IDEMPOTENCY_TTL_S < _PROCESSED_VIDEO_STAGING_STALE_AFTER_SECONDS


# ---------------------------------------------------------------------------
# DELAYED RESUME
# ---------------------------------------------------------------------------


class TestDelayedResume:
    """Represents a seller who: (1) successfully transcoded a source video,
    (2) did NOT immediately submit/attach it, and (3) returns well over a
    day later (but still within the processed-staging object's guaranteed
    lifetime) to finish the listing. Time is simulated by monkeypatching
    ``time.time()`` inside ``kk.job_ownership`` -- never a real sleep."""

    def test_attach_succeeds_after_a_simulated_40_hour_delay(
        self, app_ctx, client, r2_configured, seller_ctx, monkeypatch
    ):
        import time as time_module

        from kk import job_ownership as job_ownership_module
        from kk.job_ownership import register_idempotent_job_task_id, register_job_owner
        from kk.tasks import video_tasks
        from kk.tasks.video_tasks import VIDEO_JOB_AUTH_TTL_SECONDS

        username, owner_public_id, seller_id = seller_ctx
        car_id, car_public_id = _make_car(app_ctx, seller_id)
        draft_media_id = _new_draft_id()
        task_id = _new_task_id("delayed-resume")

        processed_key = _processed_key(app_ctx, owner_public_id, draft_media_id)
        _install_r2_fakes(monkeypatch, processed_key=processed_key, processed_meta=_good_meta())

        # Register EXACTLY as finalize_video_source_upload() does today --
        # with the production VIDEO_JOB_AUTH_TTL_SECONDS, not a
        # test-shortened value.
        t0 = time_module.time()
        register_job_owner(task_id, owner_public_id, ttl_s=VIDEO_JOB_AUTH_TTL_SECONDS)
        dedupe_key = video_tasks.video_job_dedupe_key(owner_public_id, draft_media_id)
        register_idempotent_job_task_id(dedupe_key, task_id, ttl_s=VIDEO_JOB_AUTH_TTL_SECONDS)
        monkeypatch.setattr(
            video_tasks.transcode_car_video_source,
            "AsyncResult",
            lambda tid: _FakeAsyncResult("SUCCESS"),
        )

        # 40h later: well past the OLD 24h default TTL, still comfortably
        # inside both the 48h processed-staging guarantee and the new 72h
        # auth TTL.
        delayed_now = t0 + 40 * 3600
        monkeypatch.setattr(job_ownership_module.time, "time", lambda: delayed_now)

        token = _login(client, username)
        r = _attach(client, token, car_id=car_public_id, draft_media_id=draft_media_id, task_id=task_id)
        assert r.status_code == 201, r.data
        assert _video_count(app_ctx, car_id) == 1

    def test_old_default_ttl_would_have_already_expired_at_the_same_delay(
        self, monkeypatch
    ):
        """Contrast case (not exercised through the endpoint): proves the
        fix actually matters -- registering with job_ownership.py's own
        (unchanged, still 24h) DEFAULT ttl_s and then advancing the same
        40h shows the record IS already gone, which is exactly the dead
        end this hardening pass closes for the VIDEO workflow specifically
        (via the explicit ttl_s= override at the video enqueue call site,
        not by changing the shared default itself)."""
        import time as time_module

        from kk import job_ownership as job_ownership_module
        from kk.job_ownership import get_registered_job_owner, register_job_owner

        task_id = _new_task_id("old-default-ttl")
        owner_public_id = "pub-owner-old-ttl-demo"

        t0 = time_module.time()
        register_job_owner(task_id, owner_public_id)  # default ttl_s (24h)

        monkeypatch.setattr(job_ownership_module.time, "time", lambda: t0 + 40 * 3600)

        assert get_registered_job_owner(task_id) is None
