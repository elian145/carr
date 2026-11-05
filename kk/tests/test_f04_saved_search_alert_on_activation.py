"""F-04: saved-search alerts must fire when a listing becomes publicly active.

In production every listing starts ``pending`` (LISTING_REQUIRE_APPROVAL, and
listings with media are forced pending), so the only dispatch in ``create_car``
never ran. The alert must fire on the ``pending -> active`` transition made by
an admin (single PATCH, bulk), by automated moderation (live auto-approve) or
by an admin override of a held moderation run.

Pins:
* exactly one dispatch per genuine transition (repeat approvals / already
  active bulk rows / re-sent events never dispatch again);
* nothing for non-activating changes (reject/hide, pending->pending, sold,
  featured-only) and nothing for re-activation of a previously public listing
  (sold/hidden -> active) -- deliberately conservative, see
  ``kk.retention_dispatch.is_new_publication_transition``;
* a dispatch failure (even a raising dispatcher or an unreachable broker)
  never fails or noticeably slows the admin / moderation request;
* matching and the (saved_search, car) de-duplication of the alert task, and
  the existing ``create_car`` dispatch, are unchanged.
"""

from __future__ import annotations

import os
import sys
import tempfile
import time
import uuid
from pathlib import Path

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

_PASSWORD = "Aa123456!"
_CDN = "https://cdn.example.com/car_photos"


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_f04_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "f04.db")
    os.environ["UPLOAD_FOLDER"] = os.path.join(tmp.name, "uploads")

    from kk.app_factory import create_app

    app, _socketio, *_ = create_app()
    from kk.models import db

    with app.app_context():
        db.drop_all()
        db.create_all()
    yield app, app.test_client()
    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    tmp.cleanup()


@pytest.fixture
def app(app_ctx):
    return app_ctx[0]


@pytest.fixture
def client(app_ctx):
    return app_ctx[1]


@pytest.fixture(autouse=True)
def isolate(app, monkeypatch):
    """No broker/network is ever touched; moderation state is reset."""
    from kk.auto_moderation import config
    from kk.models import AppSetting, ListingModerationEvent, ListingModerationRun, db

    for k in (
        "AUTO_MODERATION_DISABLED",
        "AUTO_MODERATION_KILL_SWITCH",
        "AUTO_MODERATION_ALLOW_LIVE",
        "AUTO_MODERATION_ALERT_EMAILS",
        "AUTO_MODERATION_TELEGRAM_BOT_TOKEN",
        "AUTO_MODERATION_TELEGRAM_CHAT_ID",
        "ADMIN_WEB_BASE_URL",
        "LISTING_REQUIRE_APPROVAL",
    ):
        monkeypatch.delenv(k, raising=False)
    monkeypatch.setenv("AUTO_MODERATION_AI_PROVIDER", "stub")

    import kk.tasks.moderation_tasks as mt

    monkeypatch.setattr(mt.moderate_listing_task, "apply_async", lambda *a, **k: None)
    monkeypatch.setattr(mt.send_moderation_alert_task, "apply_async", lambda *a, **k: None)
    with app.app_context():
        ListingModerationEvent.query.delete()
        ListingModerationRun.query.delete()
        AppSetting.query.filter_by(key=config.SETTINGS_KEY).delete()
        db.session.commit()
    yield


@pytest.fixture
def calls(monkeypatch):
    """Every saved-search dispatch (create_car's and the new activation one)."""
    import kk.retention_dispatch as rd
    import kk.routes.cars as cars_routes

    seen: list[int] = []

    def fake(car_id):
        seen.append(car_id)

    monkeypatch.setattr(rd, "dispatch_saved_search_alerts", fake)
    monkeypatch.setattr(cars_routes, "dispatch_saved_search_alerts", fake)
    return seen


# ---------------------------------------------------------------------------
# Builders
# ---------------------------------------------------------------------------


def _auth(token):
    return {"Authorization": f"Bearer {token}"}


def _user(app, *, admin=False, dealer=False):
    from kk.models import User, db
    from kk.tests.admin_auth_helpers import attach_admin_account

    username = f"f04_{uuid.uuid4().hex[:10]}"
    with app.app_context():
        u = User(
            username=username,
            phone_number=f"075{uuid.uuid4().int % 10**8:08d}",
            first_name="F04",
            last_name="Alert",
            is_active=True,
            is_verified=True,
            phone_verified=True,
            is_admin=admin,
            dealer_status="approved" if dealer else "none",
            public_id=f"f04-{uuid.uuid4().hex[:12]}",
        )
        u.set_password(_PASSWORD)
        db.session.add(u)
        db.session.commit()
        if admin:
            attach_admin_account(db, u, password=_PASSWORD, username=username)
        return u.id, username


def _admin_token(app, client):
    from kk.tests.admin_auth_helpers import login_preferring_admin_scope

    _uid, username = _user(app, admin=True)
    return login_preferring_admin_scope(client, username, _PASSWORD)


def _car(app, uid, *, status="pending", active=True, media="ready", photos=3, price=15000, **kw):
    from kk.models import Car, CarImage, CarMediaItem, db
    from kk.time_utils import utcnow

    fields = dict(
        title="Toyota Camry 2021", brand="toyota", model="camry", trim="base", year=2021,
        mileage=45000, engine_type="gasoline", fuel_type="gasoline", transmission="automatic",
        drive_type="fwd", condition="used", body_type="sedan", currency="USD", location="Erbil",
    )
    fields.update(kw)
    with app.app_context():
        car = Car(
            seller_id=uid, public_id=f"car-{uuid.uuid4().hex[:12]}", price=price,
            description="Clean car, regularly serviced, no accidents.",
            is_active=active, status=status, media_status=media, **fields,
        )
        db.session.add(car)
        db.session.flush()
        for i in range(photos):
            cid = f"m{i}-{uuid.uuid4().hex[:6]}"
            processing = media == "processing" and i == photos - 1
            db.session.add(
                CarMediaItem(
                    car_id=car.id, kind="image", client_media_id=cid,
                    status="processing" if processing else "attached",
                    is_cover=(i == 0), sort_order=i, phase_a_completed_at=utcnow(),
                )
            )
            if not processing:
                db.session.add(
                    CarImage(
                        car_id=car.id, image_url=f"{_CDN}/{car.id}_{i}.jpg", is_primary=(i == 0),
                        order=i, kind="listing", source_media_id=cid, image_width=1600,
                        image_height=1200,
                    )
                )
        db.session.commit()
        return {"id": car.id, "public_id": car.public_id, "uid": uid}


def _state(app, car_id):
    from kk.models import Car

    with app.app_context():
        c = Car.query.get(car_id)
        return c.status, c.is_active


def _patch(client, token, car, body):
    return client.patch(f"/api/admin/cars/{car['public_id']}/status", json=body, headers=_auth(token))


def _bulk(client, token, cars, body):
    return client.post(
        "/api/admin/cars/bulk-status",
        json={"ids": [c["public_id"] for c in cars], **body},
        headers=_auth(token),
    )


# ---------------------------------------------------------------------------
# Admin: single status change
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    "body",
    [{"status": "active"}, {"is_active": True, "status": "active"}, {"status": " Active "}],
)
def test_admin_approval_dispatches_exactly_once(app, client, calls, body):
    uid, _ = _user(app)
    car = _car(app, uid, status="pending")
    token = _admin_token(app, client)
    assert _patch(client, token, car, body).status_code == 200
    assert calls == [car["id"]]


def test_repeat_admin_approval_does_not_dispatch_again(app, client, calls):
    uid, _ = _user(app)
    car = _car(app, uid, status="pending")
    token = _admin_token(app, client)
    for _ in range(3):
        assert _patch(client, token, car, {"is_active": True, "status": "active"}).status_code == 200
    assert calls == [car["id"]]


def test_hide_then_reapprove_does_not_announce_again(app, client, calls):
    """Reactivation decision: only pending -> active alerts. A listing that
    was hidden and is restored was (most likely) public before."""
    uid, _ = _user(app)
    car = _car(app, uid, status="pending")
    token = _admin_token(app, client)
    assert _patch(client, token, car, {"status": "active"}).status_code == 200
    assert _patch(client, token, car, {"status": "hidden", "is_active": False}).status_code == 200
    assert _patch(client, token, car, {"status": "active", "is_active": True}).status_code == 200
    assert calls == [car["id"]]


@pytest.mark.parametrize(
    "start_status,start_active,body",
    [
        ("pending", True, {"status": "hidden", "is_active": False}),  # reject / hide
        ("pending", True, {"status": "pending"}),  # pending -> pending
        ("pending", True, {"is_featured": True}),  # featured-only on a pending listing
        ("pending", True, {"status": "sold"}),  # sold is not "new"
        ("pending", True, {"is_active": False}),  # still not public
        ("pending", False, {"status": "pending"}),
        ("active", True, {"status": "active"}),  # already active
        ("active", True, {"status": "sold"}),
        ("active", True, {"is_active": False, "status": "hidden"}),
        ("sold", True, {"status": "active"}),  # re-activation of a once-public listing
        ("hidden", False, {"status": "active", "is_active": True}),  # un-hide
        ("draft", True, {"status": "active"}),
    ],
)
def test_non_activating_or_reactivating_changes_do_not_dispatch(
    app, client, calls, start_status, start_active, body
):
    uid, _ = _user(app)
    car = _car(app, uid, status=start_status, active=start_active)
    token = _admin_token(app, client)
    assert _patch(client, token, car, body).status_code == 200
    assert calls == []


def test_pending_to_active_but_not_public_does_not_dispatch(app, client, calls):
    """is_active=False with status=active is not public: no alert."""
    uid, _ = _user(app)
    car = _car(app, uid, status="pending")
    token = _admin_token(app, client)
    assert _patch(client, token, car, {"status": "active", "is_active": False}).status_code == 200
    assert calls == []


def test_media_not_ready_block_does_not_dispatch(app, client, calls):
    uid, _ = _user(app)
    car = _car(app, uid, status="pending", media="processing")
    token = _admin_token(app, client)
    r = _patch(client, token, car, {"status": "active"})
    assert r.status_code != 200
    assert _state(app, car["id"])[0] == "pending"
    assert calls == []


# ---------------------------------------------------------------------------
# Admin: bulk status change
# ---------------------------------------------------------------------------


def test_bulk_approval_dispatches_only_for_newly_activated(app, client, calls):
    uid, _ = _user(app)
    p1 = _car(app, uid, status="pending")
    p2 = _car(app, uid, status="pending")
    already = _car(app, uid, status="active")
    sold = _car(app, uid, status="sold")
    hidden = _car(app, uid, status="hidden", active=False)
    blocked = _car(app, uid, status="pending", media="processing")
    token = _admin_token(app, client)
    r = _bulk(client, token, [p1, p2, already, sold, hidden, blocked], {"status": "active", "is_active": True})
    assert r.status_code == 200, r.data
    assert blocked["public_id"] in r.get_json()["blocked"]
    assert sorted(calls) == sorted([p1["id"], p2["id"]])
    assert len(calls) == 2

    # repeating the same bulk approval re-alerts nobody
    calls.clear()
    r = _bulk(client, token, [p1, p2, already], {"status": "active", "is_active": True})
    assert r.status_code == 200
    assert calls == []


def test_bulk_reject_or_hide_does_not_dispatch(app, client, calls):
    uid, _ = _user(app)
    cars = [_car(app, uid, status="pending") for _ in range(3)]
    token = _admin_token(app, client)
    assert _bulk(client, token, cars, {"status": "hidden", "is_active": False}).status_code == 200
    assert _bulk(client, token, cars, {"is_featured": True}).status_code == 200
    assert calls == []


# ---------------------------------------------------------------------------
# Dispatch failures never break / slow the admin request
# ---------------------------------------------------------------------------


def test_raising_dispatcher_does_not_fail_single_or_bulk(app, client, monkeypatch):
    import kk.retention_dispatch as rd

    def boom(_car_id):
        raise RuntimeError("dispatcher exploded")

    monkeypatch.setattr(rd, "dispatch_saved_search_alerts", boom)
    uid, _ = _user(app)
    one = _car(app, uid, status="pending")
    many = [_car(app, uid, status="pending") for _ in range(2)]
    token = _admin_token(app, client)
    assert _patch(client, token, one, {"status": "active"}).status_code == 200
    assert _state(app, one["id"]) == ("active", True)
    r = _bulk(client, token, many, {"status": "active"})
    assert r.status_code == 200
    assert all(_state(app, c["id"]) == ("active", True) for c in many)


def test_unreachable_broker_does_not_fail_or_block_admin_approval(app, client, monkeypatch):
    from celery.exceptions import OperationalError

    import kk.tasks.alert_tasks as at

    attempts = []

    def unreachable(*a, **k):
        attempts.append(k)
        raise OperationalError("broker down")

    monkeypatch.setattr(at.notify_saved_searches_for_car, "apply_async", unreachable)
    uid, _ = _user(app)
    car = _car(app, uid, status="pending")
    token = _admin_token(app, client)
    start = time.monotonic()
    r = _patch(client, token, car, {"status": "active"})
    assert r.status_code == 200
    assert time.monotonic() - start < 5
    assert _state(app, car["id"]) == ("active", True)
    assert len(attempts) == 1
    assert attempts[0].get("ignore_result") is True and attempts[0].get("retry") is False


def test_dispatch_happens_after_commit(app, client, monkeypatch):
    """The enqueued car must already be active+committed when the dispatcher
    runs (a worker would otherwise see a still-pending car and skip it)."""
    import kk.retention_dispatch as rd

    uid, _ = _user(app)
    car = _car(app, uid, status="pending")
    seen = []

    def fake(car_id):
        from kk.models import Car, db

        db.session.rollback()
        row = db.session.get(Car, car_id)
        seen.append((row.status, row.is_active))

    monkeypatch.setattr(rd, "dispatch_saved_search_alerts", fake)
    token = _admin_token(app, client)
    assert _patch(client, token, car, {"status": "active"}).status_code == 200
    assert seen == [("active", True)]


# ---------------------------------------------------------------------------
# Automated moderation
# ---------------------------------------------------------------------------


def _live(monkeypatch, app):
    from kk.auto_moderation import config

    monkeypatch.setenv("AUTO_MODERATION_ALLOW_LIVE", "1")
    with app.app_context():
        config.save_settings({"mode": "live"})


def _moderate(app, car_id):
    from kk.auto_moderation.engine import moderate

    with app.app_context():
        return moderate("listing", car_id)


def test_auto_moderation_live_approval_dispatches_once(app, monkeypatch, calls):
    _live(monkeypatch, app)
    uid, _ = _user(app, dealer=True)
    car = _car(app, uid, status="pending")
    assert _moderate(app, car["id"])["outcome"] == "published"
    assert _state(app, car["id"]) == ("active", True)
    assert calls == [car["id"]]
    # a re-delivered / repeated moderation job never re-alerts
    _moderate(app, car["id"])
    _moderate(app, car["id"])
    assert calls == [car["id"]]


def test_auto_moderation_shadow_mode_does_not_dispatch(app, monkeypatch, calls):
    uid, _ = _user(app, dealer=True)
    car = _car(app, uid, status="pending")
    assert _moderate(app, car["id"])["outcome"] != "published"
    assert _state(app, car["id"])[0] == "pending"
    assert calls == []


def test_auto_moderation_needs_review_does_not_dispatch(app, monkeypatch, calls):
    _live(monkeypatch, app)
    uid, _ = _user(app)  # unproven seller -> NEEDS_REVIEW, not published
    car = _car(app, uid, status="pending")
    _moderate(app, car["id"])
    assert _state(app, car["id"])[0] == "pending"
    assert calls == []


def test_auto_moderation_dispatch_failure_does_not_break_publication(app, monkeypatch):
    import kk.retention_dispatch as rd

    def boom(_car_id):
        raise RuntimeError("dispatcher exploded")

    monkeypatch.setattr(rd, "dispatch_saved_search_alerts", boom)
    _live(monkeypatch, app)
    uid, _ = _user(app, dealer=True)
    car = _car(app, uid, status="pending")
    assert _moderate(app, car["id"])["outcome"] == "published"
    assert _state(app, car["id"]) == ("active", True)


def test_moderation_override_approve_dispatches_once(app, client, calls):
    uid, _ = _user(app)  # unproven -> NEEDS_REVIEW
    car = _car(app, uid, status="pending")
    _moderate(app, car["id"])  # shadow mode: records a run, never publishes
    assert calls == []
    token = _admin_token(app, client)
    base = "/api/admin/auto-moderation"
    # the run only exists once moderation recorded it
    from kk.models import ListingModerationRun

    with app.app_context():
        run_id = ListingModerationRun.query.filter_by(car_id=car["id"]).order_by(
            ListingModerationRun.id.desc()
        ).first().public_id
    r = client.post(f"{base}/runs/{run_id}/override", json={"action": "approve"}, headers=_auth(token))
    assert r.status_code == 200, r.data
    assert calls == [car["id"]]
    r = client.post(f"{base}/runs/{run_id}/override", json={"action": "approve"}, headers=_auth(token))
    assert r.status_code == 409
    assert calls == [car["id"]]


def test_revision_approval_of_public_listing_does_not_dispatch(app, monkeypatch, calls):
    """An approved EDIT of an already-public listing is not a new listing:
    PublishResult.newly_active stays False (existing behaviour kept)."""
    from kk.auto_moderation.engine import PublishResult, post_publish

    uid, _ = _user(app)
    car = _car(app, uid, status="active")
    from kk.models import Car

    with app.app_context():
        pr = PublishResult(Car.query.get(car["id"]), None, None)
        assert pr.newly_active is False
        post_publish(pr)
    assert calls == []


# ---------------------------------------------------------------------------
# Matching / de-duplication in the real alert task is unchanged
# ---------------------------------------------------------------------------


def test_activation_alert_reaches_matching_saved_search_once(app, client, monkeypatch):
    import kk.retention_dispatch as rd
    import kk.tasks.alert_tasks as at
    from kk.models import SavedSearch, SavedSearchAlert, db

    pushes = []
    monkeypatch.setattr(at, "_send_retention_push", lambda user, **kw: pushes.append((user.id, kw)))

    def run_task_inline(car_id):
        # ``.run`` (not ``__call__``): calling the task would bind celery's
        # process-wide singleton Flask app to THIS module's database and leak
        # into later test modules (see kk/tasks/celery_app.py).
        with app.app_context():
            at.notify_saved_searches_for_car.run(car_id)

    monkeypatch.setattr(rd, "dispatch_saved_search_alerts", run_task_inline)

    seller_id, _ = _user(app)
    watcher_id, _ = _user(app)
    with app.app_context():
        db.session.add(SavedSearch(user_id=watcher_id, name="Camrys", filters={"brand": "toyota"}, notify=True))
        db.session.add(SavedSearch(user_id=watcher_id, name="BMWs", filters={"brand": "bmw"}, notify=True))
        db.session.commit()
    car = _car(app, seller_id, status="pending")
    token = _admin_token(app, client)

    assert _patch(client, token, car, {"status": "active"}).status_code == 200
    assert len(pushes) == 1  # only the matching search; the BMW search is untouched
    # repeat approval / extra dispatches never alert the same search again
    assert _patch(client, token, car, {"status": "active"}).status_code == 200
    run_task_inline(car["id"])
    assert len(pushes) == 1
    with app.app_context():
        assert SavedSearchAlert.query.filter_by(car_id=car["id"]).count() == 1


# ---------------------------------------------------------------------------
# create_car dispatch is unchanged
# ---------------------------------------------------------------------------


def _create_payload(**extra):
    payload = {
        "brand": "toyota", "model": "corolla", "year": 2021, "mileage": 1000, "price": 15000,
        "location": "Erbil", "condition": "used", "body_type": "sedan",
        "transmission": "automatic", "drive_type": "fwd", "engine_type": "gasoline",
        "fuel_type": "gasoline",
    }
    payload.update(extra)
    return payload


def _seller_headers(app, client):
    _uid, username = _user(app)
    r = client.post("/api/auth/login", json={"username": username, "password": _PASSWORD})
    assert r.status_code == 200, r.data
    return {"Authorization": f"Bearer {r.get_json()['access_token']}"}


def test_create_car_still_dispatches_when_published_immediately(app, client, calls):
    headers = _seller_headers(app, client)
    r = client.post("/api/cars", json=_create_payload(), headers=headers)
    assert r.status_code == 201, r.data
    assert r.get_json()["car"]["status"] == "active"
    assert len(calls) == 1


def test_create_car_pending_does_not_dispatch_until_approved(app, client, monkeypatch, calls):
    monkeypatch.setenv("LISTING_REQUIRE_APPROVAL", "true")
    headers = _seller_headers(app, client)
    r = client.post("/api/cars", json=_create_payload(), headers=headers)
    assert r.status_code == 201, r.data
    created = r.get_json()["car"]
    assert created["status"] == "pending"
    assert calls == []  # the production path: nothing until approval ...
    token = _admin_token(app, client)
    r = client.patch(
        f"/api/admin/cars/{created['id']}/status", json={"status": "active"}, headers=_auth(token)
    )
    assert r.status_code == 200, r.data
    assert len(calls) == 1  # ... and exactly one alert once approved
