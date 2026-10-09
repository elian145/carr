"""Media-readiness manifest -- closes the admin-approval/media race where a
listing could be approved/activated while its declared media is still
uploading, transcoding, or unattached (see ``kk/media_readiness.py`` for
the full design/state-machine contract).

Covers the mandated test scenarios from the approved design:

  1. App dies immediately after Car creation, before any media upload.
  2. App dies after Phase A success -- zero further client calls needed.
  3. Duplicate Celery tasks never create duplicate CarImage/CarVideo rows.
  4. Fast task completion before the enqueue HTTP response still stamps
     ``phase_a_completed_at``.
  5. A transient worker/storage failure never becomes terminal 'failed'.
  6. A genuine permanent failure -> 'failed' -> admin cannot activate.
  7. A never-uploaded item cannot become Phase-A-complete via the sweep.
  8. Auto-publish is forced pending when expected_media is non-empty,
     regardless of LISTING_REQUIRE_APPROVAL.
  9. Existing (pre-feature) listings default to media_status='ready'.

Plus direct unit coverage of ``kk/media_readiness.py``'s validation/
transition/removal/summary functions, the atomic create_car registration,
and the admin single/bulk activation gate (no force override).
"""

from __future__ import annotations

import os
import sys
import tempfile
import uuid
from datetime import timedelta
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


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_mediareadiness_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "mediareadiness.db")
    os.environ["UPLOAD_FOLDER"] = os.path.join(tmp.name, "uploads")
    for key in _R2_KEYS + ("R2_PUBLIC_URL",):
        os.environ.pop(key, None)

    from kk.app_factory import create_app

    app, socketio, *_ = create_app()
    from kk.models import Car, CarImage, CarMediaItem, CarVideo, User, db

    with app.app_context():
        db.drop_all()
        db.create_all()

    yield app, socketio, app.test_client(), db, User, Car, CarImage, CarVideo, CarMediaItem

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
    monkeypatch.setitem(app.config, "R2_PUBLIC_URL", "https://cdn.example.com")
    return app


@pytest.fixture(autouse=True)
def _clear_job_registries():
    from kk.job_ownership import clear_idempotent_jobs_for_tests, clear_job_owners_for_tests

    clear_job_owners_for_tests()
    clear_idempotent_jobs_for_tests()
    yield
    clear_job_owners_for_tests()
    clear_idempotent_jobs_for_tests()


def _unique_phone() -> str:
    return f"079{uuid.uuid4().int % 10**8:08d}"


def _make_user(app_ctx, *, tag: str, is_admin: bool = False):
    from kk.tests.admin_auth_helpers import attach_admin_account

    app, _socketio, _client, db, User, *_ = app_ctx
    with app.app_context():
        user = User(
            username=f"mr_{tag}_{uuid.uuid4().hex[:10]}",
            phone_number=_unique_phone(),
            first_name="MR",
            last_name="Test",
            is_active=True,
            is_verified=True,
            phone_verified=True,
            is_admin=is_admin,
            public_id=f"mr-{tag}-{uuid.uuid4().hex[:12]}",
        )
        user.set_password(_PASSWORD)
        db.session.add(user)
        db.session.commit()
        if is_admin:
            attach_admin_account(db, user, password=_PASSWORD, username=user.username)
        return user.id, user.username, user.public_id


def _login(client, username: str) -> str:
    from kk.tests.admin_auth_helpers import login_preferring_admin_scope

    return login_preferring_admin_scope(client, username, _PASSWORD)


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _base_car_payload(**overrides) -> dict:
    payload = {
        "brand": "toyota",
        "model": "camry",
        "year": 2021,
        "mileage": 1000,
        "price": 15000,
        "location": "Erbil",
        "condition": "used",
        "body_type": "sedan",
        "transmission": "automatic",
        "drive_type": "fwd",
    }
    payload.update(overrides)
    return payload


def _create_car_with_media(client, token, app_ctx, *, expected_media) -> dict:
    """Returns `Car.to_dict()` (whose ``"id"`` is the PUBLIC id) with one
    extra key, ``"db_id"``, holding the real integer primary key --
    needed because every internal `kk.media_readiness` function takes the
    integer FK, never the public id."""
    r = client.post(
        "/api/cars",
        json=_base_car_payload(expected_media=expected_media),
        headers=_auth(token),
    )
    assert r.status_code == 201, r.data
    car = r.get_json()["car"]
    app = app_ctx[0]
    Car = app_ctx[5]
    with app.app_context():
        db_car = Car.query.filter_by(public_id=car["id"]).one()
        car["db_id"] = db_car.id
    return car


def _make_car_direct(app_ctx, *, seller_id: int, media_status: str | None = None, status: str = "active"):
    """Direct DB construction -- mirrors a pre-existing (pre-feature) row,
    or gives low-level scenario tests precise control that going through
    the HTTP API would not."""
    app, _socketio, _client, db, _User, Car, *_ = app_ctx
    with app.app_context():
        kwargs = dict(
            seller_id=seller_id,
            title="Test Car",
            brand="toyota",
            model="corolla",
            year=2021,
            mileage=10,
            engine_type="gas",
            transmission="auto",
            drive_type="fwd",
            condition="used",
            body_type="sedan",
            price=15.0,
            location="Erbil",
            is_active=True,
            status=status,
        )
        if media_status is not None:
            kwargs["media_status"] = media_status
        car = Car(**kwargs)
        db.session.add(car)
        db.session.commit()
        return car.id, car.public_id


def _get_media_items(app_ctx, car_id: int) -> list:
    app, _socketio, _client, db, _User, _Car, _CarImage, _CarVideo, CarMediaItem = app_ctx
    with app.app_context():
        return (
            CarMediaItem.query.filter_by(car_id=car_id)
            .order_by(CarMediaItem.id.asc())
            .all()
        )


def _get_car(app_ctx, car_id: int):
    app, _socketio, _client, db, _User, Car, *_ = app_ctx
    with app.app_context():
        return Car.query.filter_by(id=car_id).first()


# ---------------------------------------------------------------------------
# Unit tests: validate_expected_media / build_expected_media_items
# ---------------------------------------------------------------------------


class TestValidateExpectedMedia:
    def test_none_is_empty(self, app_ctx):
        from kk.media_readiness import validate_expected_media

        app = app_ctx[0]
        with app.app_context():
            assert validate_expected_media(None) == []

    def test_valid_list_normalized(self, app_ctx):
        from kk.media_readiness import validate_expected_media

        app = app_ctx[0]
        with app.app_context():
            out = validate_expected_media(
                [
                    {"client_media_id": "img-1", "kind": "image"},
                    {"client_media_id": "vid-1", "kind": "video"},
                ]
            )
            assert out == [
                {"client_media_id": "img-1", "kind": "image"},
                {"client_media_id": "vid-1", "kind": "video"},
            ]

    def test_rejects_non_list(self, app_ctx):
        from kk.media_readiness import ExpectedMediaValidationError, validate_expected_media

        app = app_ctx[0]
        with app.app_context():
            with pytest.raises(ExpectedMediaValidationError):
                validate_expected_media({"not": "a list"})

    def test_rejects_invalid_client_media_id(self, app_ctx):
        from kk.media_readiness import ExpectedMediaValidationError, validate_expected_media

        app = app_ctx[0]
        with app.app_context():
            with pytest.raises(ExpectedMediaValidationError):
                validate_expected_media([{"client_media_id": "has a space", "kind": "image"}])

    def test_rejects_bad_kind(self, app_ctx):
        from kk.media_readiness import ExpectedMediaValidationError, validate_expected_media

        app = app_ctx[0]
        with app.app_context():
            with pytest.raises(ExpectedMediaValidationError):
                validate_expected_media([{"client_media_id": "abc", "kind": "audio"}])

    def test_rejects_duplicate_client_media_id(self, app_ctx):
        from kk.media_readiness import ExpectedMediaValidationError, validate_expected_media

        app = app_ctx[0]
        with app.app_context():
            with pytest.raises(ExpectedMediaValidationError):
                validate_expected_media(
                    [
                        {"client_media_id": "dup", "kind": "image"},
                        {"client_media_id": "dup", "kind": "video"},
                    ]
                )

    def test_rejects_too_many_images(self, app_ctx):
        from kk.media_readiness import (
            MAX_EXPECTED_IMAGE_ITEMS,
            ExpectedMediaValidationError,
            validate_expected_media,
        )

        app = app_ctx[0]
        with app.app_context():
            too_many = [
                {"client_media_id": f"img-{i}", "kind": "image"}
                for i in range(MAX_EXPECTED_IMAGE_ITEMS + 1)
            ]
            with pytest.raises(ExpectedMediaValidationError):
                validate_expected_media(too_many)


# ---------------------------------------------------------------------------
# create_car(): atomic manifest registration + forced-pending status
# ---------------------------------------------------------------------------


class TestCreateCarAtomicManifestRegistration:
    def test_expected_media_registers_manifest_rows_and_forces_pending(self, client, app_ctx):
        _uid, username, _pub = _make_user(app_ctx, tag="create1")
        token = _login(client, username)

        car = _create_car_with_media(
            client,
            token,
            app_ctx,
            expected_media=[
                {"client_media_id": "img-a", "kind": "image"},
                {"client_media_id": "img-b", "kind": "image"},
                {"client_media_id": "vid-a", "kind": "video"},
            ],
        )
        # Server-controlled status must be forced pending -- never active
        # at create time when expected_media is non-empty.
        assert car["status"] == "pending"

        items = _get_media_items(app_ctx, car["db_id"])
        assert len(items) == 3
        client_media_ids = {it.client_media_id for it in items}
        assert client_media_ids == {"img-a", "img-b", "vid-a"}
        for it in items:
            assert it.status == "awaiting_upload"
            assert it.phase_a_completed_at is None

        db_car = _get_car(app_ctx, car["db_id"])
        assert db_car.media_status == "processing"

    def test_no_expected_media_is_ready_immediately(self, client, app_ctx):
        _uid, username, _pub = _make_user(app_ctx, tag="create2")
        token = _login(client, username)

        r = client.post("/api/cars", json=_base_car_payload(), headers=_auth(token))
        assert r.status_code == 201, r.data
        car = r.get_json()["car"]

        app = app_ctx[0]
        Car = app_ctx[5]
        with app.app_context():
            db_id = Car.query.filter_by(public_id=car["id"]).one().id

        db_car = _get_car(app_ctx, db_id)
        assert db_car.media_status == "ready"
        assert _get_media_items(app_ctx, db_id) == []

    def test_rejects_invalid_expected_media_with_400(self, client, app_ctx):
        _uid, username, _pub = _make_user(app_ctx, tag="create3")
        token = _login(client, username)

        r = client.post(
            "/api/cars",
            json=_base_car_payload(expected_media=[{"client_media_id": "x y", "kind": "image"}]),
            headers=_auth(token),
        )
        assert r.status_code == 400, r.data


# ---------------------------------------------------------------------------
# Scenario 1: app dies immediately after Car creation, before any upload.
# ---------------------------------------------------------------------------


class TestScenario1NeverUploaded:
    def test_never_uploaded_item_stays_awaiting_upload_and_sweep_does_not_touch_it(
        self, client, app_ctx
    ):
        from kk.media_readiness import sweep_stuck_processing_items

        _uid, username, _pub = _make_user(app_ctx, tag="s1")
        token = _login(client, username)
        car = _create_car_with_media(
            client, token, app_ctx, expected_media=[{"client_media_id": "s1-img", "kind": "image"}]
        )

        items = _get_media_items(app_ctx, car["db_id"])
        assert len(items) == 1
        assert items[0].status == "awaiting_upload"
        assert items[0].phase_a_completed_at is None

        app = app_ctx[0]
        with app.app_context():
            marked = sweep_stuck_processing_items(older_than_seconds=0)
            assert marked == 0

        items_after = _get_media_items(app_ctx, car["db_id"])
        assert items_after[0].status == "awaiting_upload"
        assert items_after[0].phase_a_completed_at is None
        db_car = _get_car(app_ctx, car["db_id"])
        assert db_car.media_status == "processing"

    def test_media_summary_reports_phase_a_incomplete(self, client, app_ctx):
        _uid, username, _pub = _make_user(app_ctx, tag="s1b")
        token = _login(client, username)
        car = _create_car_with_media(
            client, token, app_ctx, expected_media=[{"client_media_id": "s1b-img", "kind": "image"}]
        )

        r = client.get(f"/api/cars/{car['id']}/media-summary", headers=_auth(token))
        assert r.status_code == 200, r.data
        body = r.get_json()
        assert body["phase_a_complete"] is False
        assert body["media_status"] == "processing"
        assert body["items"][0]["status"] == "awaiting_upload"
        assert body["items"][0]["phase_a_complete"] is False

    def test_reopen_can_remove_never_uploaded_item(self, client, app_ctx):
        _uid, username, _pub = _make_user(app_ctx, tag="s1c")
        token = _login(client, username)
        car = _create_car_with_media(
            client, token, app_ctx, expected_media=[{"client_media_id": "s1c-img", "kind": "image"}]
        )

        r = client.delete(
            f"/api/cars/{car['id']}/media-items/s1c-img", headers=_auth(token)
        )
        assert r.status_code == 200, r.data
        assert r.get_json()["removed"] is True

        assert _get_media_items(app_ctx, car["db_id"]) == []
        db_car = _get_car(app_ctx, car["db_id"])
        # No items left -> aggregate recomputes to ready.
        assert db_car.media_status == "ready"

        # Idempotent: removing again is a safe no-op, never an error.
        r2 = client.delete(
            f"/api/cars/{car['id']}/media-items/s1c-img", headers=_auth(token)
        )
        assert r2.status_code == 200, r2.data
        assert r2.get_json()["removed"] is False

    def test_reopen_can_retry_same_client_media_id(self, client, app_ctx):
        from kk.media_readiness import mark_item_phase_a_accepted

        _uid, username, _pub = _make_user(app_ctx, tag="s1d")
        token = _login(client, username)
        car = _create_car_with_media(
            client, token, app_ctx, expected_media=[{"client_media_id": "s1d-img", "kind": "image"}]
        )

        app = app_ctx[0]
        with app.app_context():
            mark_item_phase_a_accepted(
                car_id=car["db_id"], client_media_id="s1d-img", job_task_id="task-retry-1"
            )

        items = _get_media_items(app_ctx, car["db_id"])
        assert items[0].status == "processing"
        assert items[0].phase_a_completed_at is not None


# ---------------------------------------------------------------------------
# Scenario 2: app dies after Phase A success -- zero further client calls.
# ---------------------------------------------------------------------------


class TestScenario2PhaseASuccessZeroFurtherCalls:
    def test_backend_alone_attaches_image_to_ready(self, client, app_ctx):
        from kk.media_readiness import mark_item_phase_a_accepted, transition_media_item_terminal

        _uid, username, _pub = _make_user(app_ctx, tag="s2")
        token = _login(client, username)
        car = _create_car_with_media(
            client, token, app_ctx, expected_media=[{"client_media_id": "s2-img", "kind": "image"}]
        )

        app = app_ctx[0]
        with app.app_context():
            from kk.routes.media import attach_processed_car_image
            from kk.models import Car as CarModel

            # Phase A: enqueue accepted (simulates the ?async=1 route).
            mark_item_phase_a_accepted(
                car_id=car["db_id"], client_media_id="s2-img", job_task_id="task-s2"
            )
            # Phase B: the Celery task itself completes -- NO further
            # client/HTTP call happens between here and the assertions.
            transition_media_item_terminal(
                car_id=car["db_id"],
                client_media_id="s2-img",
                to_status="attached",
                attach_fn=lambda car_obj: attach_processed_car_image(
                    car_obj, kind="listing", rel_path="uploads/car_photos/s2.jpg",
                    source_media_id="s2-img",
                ),
            )

        db_car = _get_car(app_ctx, car["db_id"])
        assert db_car.media_status == "ready"
        items = _get_media_items(app_ctx, car["db_id"])
        assert items[0].status == "attached"
        assert items[0].phase_a_completed_at is not None

        app = app_ctx[0]
        with app.app_context():
            from kk.models import CarImage

            imgs = CarImage.query.filter_by(car_id=car["db_id"]).all()
            assert len(imgs) == 1
            assert imgs[0].source_media_id == "s2-img"

    def test_multi_item_listing_not_ready_until_every_item_attached(self, client, app_ctx):
        from kk.media_readiness import transition_media_item_terminal

        _uid, username, _pub = _make_user(app_ctx, tag="s2b")
        token = _login(client, username)
        car = _create_car_with_media(
            client,
            token,
            app_ctx,
            expected_media=[
                {"client_media_id": "s2b-img1", "kind": "image"},
                {"client_media_id": "s2b-img2", "kind": "image"},
            ],
        )

        app = app_ctx[0]
        with app.app_context():
            from kk.routes.media import attach_processed_car_image

            transition_media_item_terminal(
                car_id=car["db_id"],
                client_media_id="s2b-img1",
                to_status="attached",
                attach_fn=lambda car_obj: attach_processed_car_image(
                    car_obj, kind="listing", rel_path="uploads/car_photos/s2b-1.jpg",
                    source_media_id="s2b-img1",
                ),
            )

        # Only ONE of two items attached so far -- must NOT be ready yet.
        db_car = _get_car(app_ctx, car["db_id"])
        assert db_car.media_status == "processing"

        with app.app_context():
            from kk.routes.media import attach_processed_car_image

            transition_media_item_terminal(
                car_id=car["db_id"],
                client_media_id="s2b-img2",
                to_status="attached",
                attach_fn=lambda car_obj: attach_processed_car_image(
                    car_obj, kind="listing", rel_path="uploads/car_photos/s2b-2.jpg",
                    source_media_id="s2b-img2",
                ),
            )

        db_car2 = _get_car(app_ctx, car["db_id"])
        assert db_car2.media_status == "ready"


# ---------------------------------------------------------------------------
# Scenario 3: duplicate Celery tasks -- no duplicate rows, correct aggregate.
# ---------------------------------------------------------------------------


class TestScenario3DuplicateTasksNoDuplicateRows:
    def test_duplicate_image_terminal_transition_is_a_safe_noop(self, client, app_ctx):
        from kk.media_readiness import transition_media_item_terminal

        _uid, username, _pub = _make_user(app_ctx, tag="s3")
        token = _login(client, username)
        car = _create_car_with_media(
            client, token, app_ctx, expected_media=[{"client_media_id": "s3-img", "kind": "image"}]
        )

        calls = {"n": 0}

        def _attach(car_obj):
            calls["n"] += 1
            from kk.routes.media import attach_processed_car_image

            return attach_processed_car_image(
                car_obj, kind="listing", rel_path="uploads/car_photos/s3.jpg",
                source_media_id="s3-img",
            )

        app = app_ctx[0]
        with app.app_context():
            transition_media_item_terminal(
                car_id=car["db_id"], client_media_id="s3-img", to_status="attached", attach_fn=_attach
            )
        with app.app_context():
            # A second, duplicate/redelivered execution for the SAME item.
            transition_media_item_terminal(
                car_id=car["db_id"], client_media_id="s3-img", to_status="attached", attach_fn=_attach
            )

        # attach_fn is only actually invoked once -- the second call finds
        # the item already terminal and returns before calling it.
        assert calls["n"] == 1

        with app.app_context():
            from kk.models import CarImage

            imgs = CarImage.query.filter_by(car_id=car["db_id"]).all()
            assert len(imgs) == 1

        db_car = _get_car(app_ctx, car["db_id"])
        assert db_car.media_status == "ready"

    def test_duplicate_video_attach_via_shared_client_media_id_never_duplicates(
        self, client, app_ctx, r2_configured, monkeypatch
    ):
        from kk.media_readiness import transition_media_item_terminal

        _uid, username, _pub = _make_user(app_ctx, tag="s3v")
        token = _login(client, username)
        car = _create_car_with_media(
            client, token, app_ctx, expected_media=[{"client_media_id": "s3v-draft", "kind": "video"}]
        )

        import kk.r2_ops as r2_ops_module

        monkeypatch.setattr(
            r2_ops_module,
            "r2_head_object",
            lambda key: {"exists": True, "size": 1234, "content_type": "video/mp4"},
        )
        monkeypatch.setattr(r2_ops_module, "r2_copy_object", lambda **kwargs: None)

        app = app_ctx[0]

        def _attach(car_obj):
            from kk.routes.media import attach_one_transcoded_video

            return attach_one_transcoded_video(
                car_obj, owner_public_id=_pub, draft_media_id="s3v-draft"
            )

        with app.app_context():
            transition_media_item_terminal(
                car_id=car["db_id"], client_media_id="s3v-draft", to_status="attached", attach_fn=_attach
            )
        with app.app_context():
            transition_media_item_terminal(
                car_id=car["db_id"], client_media_id="s3v-draft", to_status="attached", attach_fn=_attach
            )

        with app.app_context():
            from kk.models import CarVideo

            vids = CarVideo.query.filter_by(car_id=car["db_id"]).all()
            assert len(vids) == 1
            assert vids[0].source_draft_media_id == "s3v-draft"

        db_car = _get_car(app_ctx, car["db_id"])
        assert db_car.media_status == "ready"


# ---------------------------------------------------------------------------
# Scenario 4: fast task completion before the enqueue HTTP response.
# ---------------------------------------------------------------------------


class TestScenario4FastCompletionBeforeEnqueueResponse:
    def test_terminal_transition_before_any_phase_a_accept_still_stamps_it(self, client, app_ctx):
        from kk.media_readiness import transition_media_item_terminal

        _uid, username, _pub = _make_user(app_ctx, tag="s4")
        token = _login(client, username)
        car = _create_car_with_media(
            client, token, app_ctx, expected_media=[{"client_media_id": "s4-img", "kind": "image"}]
        )

        # This item's manifest row is still exactly as create_car() left it
        # (awaiting_upload, phase_a_completed_at NULL) -- no
        # mark_item_phase_a_accepted() call happened yet. A task that
        # raced ahead and already finished BEFORE the enqueue endpoint's
        # own response reached the client must still leave this item
        # provably Phase-A-complete.
        app = app_ctx[0]
        with app.app_context():
            from kk.routes.media import attach_processed_car_image

            transition_media_item_terminal(
                car_id=car["db_id"],
                client_media_id="s4-img",
                to_status="attached",
                attach_fn=lambda car_obj: attach_processed_car_image(
                    car_obj, kind="listing", rel_path="uploads/car_photos/s4.jpg",
                    source_media_id="s4-img",
                ),
            )

        items = _get_media_items(app_ctx, car["db_id"])
        assert items[0].phase_a_completed_at is not None
        assert items[0].status == "attached"

        # submitFast()'s exact predicate: every expected item reports
        # phase_a_complete=True -- never hangs waiting on this item.
        r = client.get(f"/api/cars/{car['id']}/media-summary", headers=_auth(token))
        assert r.get_json()["phase_a_complete"] is True


# ---------------------------------------------------------------------------
# Scenario 5: transient failure never becomes terminal.
# ---------------------------------------------------------------------------


class TestScenario5TransientFailureNotTerminal:
    def test_raising_attach_fn_leaves_item_processing_not_failed(self, client, app_ctx):
        from kk.media_readiness import mark_item_phase_a_accepted, transition_media_item_terminal

        _uid, username, _pub = _make_user(app_ctx, tag="s5")
        token = _login(client, username)
        car = _create_car_with_media(
            client, token, app_ctx, expected_media=[{"client_media_id": "s5-img", "kind": "image"}]
        )

        app = app_ctx[0]
        with app.app_context():
            mark_item_phase_a_accepted(
                car_id=car["db_id"], client_media_id="s5-img", job_task_id="task-s5"
            )

        def _flaky_attach(_car_obj):
            raise RuntimeError("simulated transient R2/network failure")

        with app.app_context():
            with pytest.raises(RuntimeError):
                transition_media_item_terminal(
                    car_id=car["db_id"],
                    client_media_id="s5-img",
                    to_status="attached",
                    attach_fn=_flaky_attach,
                )

        items = _get_media_items(app_ctx, car["db_id"])
        assert items[0].status == "processing"  # NOT "failed"
        assert items[0].phase_a_completed_at is not None
        db_car = _get_car(app_ctx, car["db_id"])
        assert db_car.media_status == "processing"  # NOT "failed"

        # A later, successful redelivery/retry can still reach 'attached'.
        with app.app_context():
            from kk.routes.media import attach_processed_car_image

            transition_media_item_terminal(
                car_id=car["db_id"],
                client_media_id="s5-img",
                to_status="attached",
                attach_fn=lambda car_obj: attach_processed_car_image(
                    car_obj, kind="listing", rel_path="uploads/car_photos/s5.jpg",
                    source_media_id="s5-img",
                ),
            )
        items_after = _get_media_items(app_ctx, car["db_id"])
        assert items_after[0].status == "attached"
        db_car_after = _get_car(app_ctx, car["db_id"])
        assert db_car_after.media_status == "ready"

    def test_image_task_transient_exception_does_not_terminal_fail(self, app_ctx, monkeypatch):
        """A non-permanent exception raised inside process_car_image_file's
        pipeline must propagate as an ordinary task failure WITHOUT calling
        transition_media_item_terminal(to_status="failed")."""
        _uid, username, pub = _make_user(app_ctx, tag="s5b")
        car_id, _car_pub = _make_car_direct(app_ctx, seller_id=_uid, media_status="processing")

        app = app_ctx[0]
        with app.app_context():
            from kk.models import CarMediaItem, db

            item = CarMediaItem(
                car_id=car_id, kind="image", client_media_id="s5b-img", status="processing",
            )
            from kk.time_utils import utcnow

            item.phase_a_completed_at = utcnow()
            db.session.add(item)
            db.session.commit()

        import kk.tasks.image_tasks as image_tasks_module

        def _boom(**kwargs):
            raise RuntimeError("simulated transient worker/storage failure")

        monkeypatch.setattr(image_tasks_module, "_process_image_path", _boom)

        with app.app_context():
            with pytest.raises(RuntimeError):
                image_tasks_module.process_car_image_file.run(
                    None,
                    "photo.jpg",
                    False,
                    False,
                    owner_public_id=pub,
                    source_r2_key=None,
                    car_id=car_id,
                    kind="listing",
                    client_media_id="s5b-img",
                )

        items = _get_media_items(app_ctx, car_id)
        matching = [it for it in items if it.client_media_id == "s5b-img"]
        assert matching[0].status == "processing"  # NOT "failed"


# ---------------------------------------------------------------------------
# Scenario 6: genuine permanent failure -> failed -> admin cannot activate.
# ---------------------------------------------------------------------------


class TestScenario6PermanentFailure:
    def test_permanent_rejection_marks_item_and_car_failed(self, client, app_ctx):
        from kk.media_readiness import mark_item_phase_a_accepted, transition_media_item_terminal

        _uid, username, _pub = _make_user(app_ctx, tag="s6")
        token = _login(client, username)
        car = _create_car_with_media(
            client, token, app_ctx, expected_media=[{"client_media_id": "s6-img", "kind": "image"}]
        )

        app = app_ctx[0]
        with app.app_context():
            mark_item_phase_a_accepted(
                car_id=car["db_id"], client_media_id="s6-img", job_task_id="task-s6"
            )
            transition_media_item_terminal(
                car_id=car["db_id"], client_media_id="s6-img", to_status="failed"
            )

        items = _get_media_items(app_ctx, car["db_id"])
        assert items[0].status == "failed"
        db_car = _get_car(app_ctx, car["db_id"])
        assert db_car.media_status == "failed"

    def test_image_task_permanent_rejection_calls_terminal_fail(self, app_ctx, monkeypatch):
        from kk.media_processing import DecompressionBombRejected

        _uid, username, pub = _make_user(app_ctx, tag="s6b")
        car_id, _car_pub = _make_car_direct(app_ctx, seller_id=_uid, media_status="processing")

        app = app_ctx[0]
        with app.app_context():
            from kk.models import CarMediaItem, db
            from kk.time_utils import utcnow

            item = CarMediaItem(
                car_id=car_id, kind="image", client_media_id="s6b-img", status="processing",
            )
            item.phase_a_completed_at = utcnow()
            db.session.add(item)
            db.session.commit()

        import kk.tasks.image_tasks as image_tasks_module

        def _bomb(**kwargs):
            raise DecompressionBombRejected("simulated decompression bomb")

        monkeypatch.setattr(image_tasks_module, "_process_image_path", _bomb)

        with app.app_context():
            with pytest.raises(DecompressionBombRejected):
                image_tasks_module.process_car_image_file.run(
                    None,
                    "photo.jpg",
                    False,
                    False,
                    owner_public_id=pub,
                    source_r2_key=None,
                    car_id=car_id,
                    kind="listing",
                    client_media_id="s6b-img",
                )

        items = _get_media_items(app_ctx, car_id)
        matching = [it for it in items if it.client_media_id == "s6b-img"]
        assert matching[0].status == "failed"

    def test_video_permanent_error_subclass_terminal_fails_when_car_id_given(
        self, app_ctx, monkeypatch
    ):
        from kk.tasks.video_tasks import PermanentVideoTranscodeError

        _uid, username, pub = _make_user(app_ctx, tag="s6c")
        car_id, _car_pub = _make_car_direct(app_ctx, seller_id=_uid, media_status="processing")

        app = app_ctx[0]
        with app.app_context():
            from kk.models import CarMediaItem, db
            from kk.time_utils import utcnow

            item = CarMediaItem(
                car_id=car_id, kind="video", client_media_id="s6c-draft", status="processing",
            )
            item.phase_a_completed_at = utcnow()
            db.session.add(item)
            db.session.commit()

        import kk.tasks.video_tasks as video_tasks_module

        def _permanent(**kwargs):
            raise PermanentVideoTranscodeError("simulated permanent/invalid source")

        monkeypatch.setattr(video_tasks_module, "_transcode_video_source_impl", _permanent)

        with app.app_context():
            with pytest.raises(PermanentVideoTranscodeError):
                video_tasks_module.transcode_car_video_source.run(
                    "some/staging/key",
                    pub,
                    "s6c-draft",
                    car_id=car_id,
                )

        items = _get_media_items(app_ctx, car_id)
        matching = [it for it in items if it.client_media_id == "s6c-draft"]
        assert matching[0].status == "failed"

    def test_admin_cannot_activate_failed_media_listing(self, client, app_ctx):
        from kk.media_readiness import mark_item_phase_a_accepted, transition_media_item_terminal

        _uid, username, _pub = _make_user(app_ctx, tag="s6d")
        token = _login(client, username)
        car = _create_car_with_media(
            client, token, app_ctx, expected_media=[{"client_media_id": "s6d-img", "kind": "image"}]
        )
        app = app_ctx[0]
        with app.app_context():
            mark_item_phase_a_accepted(
                car_id=car["db_id"], client_media_id="s6d-img", job_task_id="task-s6d"
            )
            transition_media_item_terminal(
                car_id=car["db_id"], client_media_id="s6d-img", to_status="failed"
            )

        _aid, admin_username, _apub = _make_user(app_ctx, tag="s6d-admin", is_admin=True)
        admin_token = _login(client, admin_username)

        r = client.patch(
            f"/api/admin/cars/{car['id']}/status",
            json={"is_active": True, "status": "active"},
            headers=_auth(admin_token),
        )
        assert r.status_code == 409, r.data
        assert r.get_json()["media_status"] == "failed"

        db_car = _get_car(app_ctx, car["db_id"])
        assert db_car.status != "active" or not db_car.is_active


# ---------------------------------------------------------------------------
# Scenario 7: never-uploaded item cannot become Phase-A-complete via sweep.
# ---------------------------------------------------------------------------


class TestScenario7SweepNeverFabricatesPhaseA:
    def test_sweep_ignores_awaiting_upload_rows_even_when_very_old(self, client, app_ctx):
        from kk.media_readiness import sweep_stuck_processing_items
        from kk.time_utils import utcnow

        _uid, username, _pub = _make_user(app_ctx, tag="s7")
        token = _login(client, username)
        car = _create_car_with_media(
            client, token, app_ctx, expected_media=[{"client_media_id": "s7-img", "kind": "image"}]
        )

        app = app_ctx[0]
        with app.app_context():
            from kk.models import CarMediaItem, db

            item = CarMediaItem.query.filter_by(car_id=car["db_id"], client_media_id="s7-img").one()
            # Simulate a very old, never-uploaded row -- far older than any
            # sweep timeout, still awaiting_upload, still NULL phase_a.
            item.updated_at = utcnow() - timedelta(days=30)
            db.session.commit()

            # Default (real) timeout -- deliberately NOT older_than_seconds=0
            # here: this test file's DB is shared (module-scoped) across
            # many tests, and a 0-second cutoff would also match any other
            # test's still-"processing" leftover row regardless of how
            # recently it was touched, making a global `marked` count
            # meaningless for isolating THIS row's behavior. The assertion
            # that matters -- that THIS never-uploaded row is untouched --
            # is checked directly below regardless of the global count.
            sweep_stuck_processing_items()

        items = _get_media_items(app_ctx, car["db_id"])
        assert items[0].status == "awaiting_upload"
        assert items[0].phase_a_completed_at is None

    def test_sweep_does_terminal_fail_a_stuck_phase_a_complete_item(self, client, app_ctx):
        from kk.media_readiness import mark_item_phase_a_accepted, sweep_stuck_processing_items
        from kk.time_utils import utcnow

        _uid, username, _pub = _make_user(app_ctx, tag="s7b")
        token = _login(client, username)
        car = _create_car_with_media(
            client, token, app_ctx, expected_media=[{"client_media_id": "s7b-img", "kind": "image"}]
        )

        app = app_ctx[0]
        with app.app_context():
            mark_item_phase_a_accepted(
                car_id=car["db_id"], client_media_id="s7b-img", job_task_id="task-s7b"
            )
            from kk.models import CarMediaItem, db

            item = CarMediaItem.query.filter_by(car_id=car["db_id"], client_media_id="s7b-img").one()
            assert item.phase_a_completed_at is not None
            # Simulate a lost/never-redelivered Phase-B job: stuck in
            # 'processing' well past the sweep's timeout.
            item.updated_at = utcnow() - timedelta(hours=12)
            db.session.commit()

            marked = sweep_stuck_processing_items(older_than_seconds=6 * 3600)
            assert marked == 1

        items = _get_media_items(app_ctx, car["db_id"])
        assert items[0].status == "failed"
        db_car = _get_car(app_ctx, car["db_id"])
        assert db_car.media_status == "failed"


# ---------------------------------------------------------------------------
# Scenario 8: auto-publish is forced pending regardless of
# LISTING_REQUIRE_APPROVAL when expected_media is non-empty.
# ---------------------------------------------------------------------------


class TestScenario8AutoPublishForcedPending:
    def test_forced_pending_even_with_auto_publish_enabled(self, client, app_ctx, monkeypatch):
        # This test module's app_ctx fixture already pop()s
        # LISTING_REQUIRE_APPROVAL and runs with APP_ENV=testing, so
        # listing_require_approval() is False (auto-publish) -- the
        # baseline this test must show expected_media overrides.
        monkeypatch.delenv("LISTING_REQUIRE_APPROVAL", raising=False)

        _uid, username, _pub = _make_user(app_ctx, tag="s8")
        token = _login(client, username)

        # Baseline sanity: WITHOUT expected_media, auto-publish applies.
        r_no_media = client.post("/api/cars", json=_base_car_payload(), headers=_auth(token))
        assert r_no_media.status_code == 201, r_no_media.data
        assert r_no_media.get_json()["car"]["status"] == "active"

        car = _create_car_with_media(
            client, token, app_ctx, expected_media=[{"client_media_id": "s8-img", "kind": "image"}]
        )
        assert car["status"] == "pending"

    def test_forced_pending_with_approval_required_too(self, client, app_ctx, monkeypatch):
        monkeypatch.setenv("LISTING_REQUIRE_APPROVAL", "1")

        _uid, username, _pub = _make_user(app_ctx, tag="s8b")
        token = _login(client, username)
        car = _create_car_with_media(
            client, token, app_ctx, expected_media=[{"client_media_id": "s8b-img", "kind": "image"}]
        )
        assert car["status"] == "pending"
        monkeypatch.delenv("LISTING_REQUIRE_APPROVAL", raising=False)


# ---------------------------------------------------------------------------
# Scenario 9: existing (pre-feature) listings default to media_status='ready'.
# ---------------------------------------------------------------------------


class TestScenario9ExistingListingsDefaultReady:
    def test_directly_constructed_car_defaults_to_ready(self, app_ctx):
        _uid, _username, _pub = _make_user(app_ctx, tag="s9")
        car_id, _car_pub = _make_car_direct(app_ctx, seller_id=_uid)

        db_car = _get_car(app_ctx, car_id)
        assert db_car.media_status == "ready"

    def test_pre_existing_active_listing_is_unaffected_and_activatable(self, client, app_ctx):
        _uid, _username, _pub = _make_user(app_ctx, tag="s9b")
        car_id, _car_pub = _make_car_direct(app_ctx, seller_id=_uid, status="pending")

        _aid, admin_username, _apub = _make_user(app_ctx, tag="s9b-admin", is_admin=True)
        admin_token = _login(client, admin_username)

        r = client.patch(
            f"/api/admin/cars/{car_id}/status",
            json={"is_active": True, "status": "active"},
            headers=_auth(admin_token),
        )
        assert r.status_code == 200, r.data
        assert r.get_json()["car"]["status"] == "active"


# ---------------------------------------------------------------------------
# Admin single/bulk activation gate -- no force override.
# ---------------------------------------------------------------------------


class TestAdminActivationGate:
    def test_single_activation_blocked_while_processing_then_allowed_once_ready(
        self, client, app_ctx
    ):
        from kk.media_readiness import transition_media_item_terminal

        _uid, username, _pub = _make_user(app_ctx, tag="gate1")
        token = _login(client, username)
        car = _create_car_with_media(
            client, token, app_ctx, expected_media=[{"client_media_id": "gate1-img", "kind": "image"}]
        )

        _aid, admin_username, _apub = _make_user(app_ctx, tag="gate1-admin", is_admin=True)
        admin_token = _login(client, admin_username)

        r_blocked = client.patch(
            f"/api/admin/cars/{car['id']}/status",
            json={"is_active": True, "status": "active"},
            headers=_auth(admin_token),
        )
        assert r_blocked.status_code == 409, r_blocked.data

        # Deactivating/hiding a not-ready listing must still be allowed --
        # only making it PUBLICLY VISIBLE is gated.
        r_hide = client.patch(
            f"/api/admin/cars/{car['id']}/status",
            json={"is_active": False},
            headers=_auth(admin_token),
        )
        assert r_hide.status_code == 200, r_hide.data

        app = app_ctx[0]
        with app.app_context():
            from kk.routes.media import attach_processed_car_image

            transition_media_item_terminal(
                car_id=car["db_id"],
                client_media_id="gate1-img",
                to_status="attached",
                attach_fn=lambda car_obj: attach_processed_car_image(
                    car_obj, kind="listing", rel_path="uploads/car_photos/gate1.jpg",
                    source_media_id="gate1-img",
                ),
            )

        r_allowed = client.patch(
            f"/api/admin/cars/{car['id']}/status",
            json={"is_active": True, "status": "active"},
            headers=_auth(admin_token),
        )
        assert r_allowed.status_code == 200, r_allowed.data
        assert r_allowed.get_json()["car"]["status"] == "active"

    def test_bulk_activation_blocks_not_ready_rows_but_applies_others(self, client, app_ctx):
        _uid, username, _pub = _make_user(app_ctx, tag="gate2")
        token = _login(client, username)
        not_ready_car = _create_car_with_media(
            client, token, app_ctx, expected_media=[{"client_media_id": "gate2-img", "kind": "image"}]
        )
        ready_car_id, _ready_pub = _make_car_direct(app_ctx, seller_id=_uid, status="pending")

        _aid, admin_username, _apub = _make_user(app_ctx, tag="gate2-admin", is_admin=True)
        admin_token = _login(client, admin_username)

        r = client.post(
            "/api/admin/cars/bulk-status",
            json={
                "ids": [not_ready_car["id"], ready_car_id],
                "is_active": True,
                "status": "active",
            },
            headers=_auth(admin_token),
        )
        assert r.status_code == 200, r.data
        body = r.get_json()
        # The not-ready listing is reported blocked, not silently updated.
        not_ready_public_id = not_ready_car["id"]
        assert not_ready_public_id in body["blocked"]
        assert not_ready_public_id not in body["updated"]
        assert not_ready_public_id not in body["missing"]

        ready_public_id = _ready_pub
        assert ready_public_id in body["updated"]
        assert ready_public_id not in body["blocked"]

        db_not_ready = _get_car(app_ctx, not_ready_car["db_id"])
        assert db_not_ready.status != "active"

        db_ready = _get_car(app_ctx, ready_car_id)
        assert db_ready.status == "active"
        assert db_ready.is_active is True

    def test_no_force_override_parameter_exists(self, client, app_ctx):
        """Explicit negative test for the design's 'NO force override'
        requirement -- passing any made-up override-ish field must not
        bypass the gate."""
        _uid, username, _pub = _make_user(app_ctx, tag="gate3")
        token = _login(client, username)
        car = _create_car_with_media(
            client, token, app_ctx, expected_media=[{"client_media_id": "gate3-img", "kind": "image"}]
        )
        _aid, admin_username, _apub = _make_user(app_ctx, tag="gate3-admin", is_admin=True)
        admin_token = _login(client, admin_username)

        r = client.patch(
            f"/api/admin/cars/{car['id']}/status",
            json={
                "is_active": True,
                "status": "active",
                "force": True,
                "override_media_check": True,
                "force_activate": True,
            },
            headers=_auth(admin_token),
        )
        assert r.status_code == 409, r.data
