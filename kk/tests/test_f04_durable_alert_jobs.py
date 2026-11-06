"""F-04 durable saved-search alert delivery (job table, claim-first task, sweep).

Everything here runs on the default SQLite test database with the Celery broker
and FCM stubbed; the PostgreSQL-only claims (real concurrency, migration) live
in ``test_f04_pg_durable_alerts.py``.

Delivery semantics under test -- external push is AT-LEAST-ONCE, never claimed
exactly-once: duplicate pushes are BOUNDED (a crash between push and commit
re-pushes that one pair on redrive), a push is never skipped by a crash, and the
unique constraints keep ONE committed alert row / in-app Notification per
(saved search, car) pair.

Groups: flag modes, first-publication recording on every activation path,
negatives (un-hide / sold -> active / edits / re-approval), transaction
atomicity, claim-first + crash/retry semantics, sweep (broker outage, lease,
batch bound, expiry window, attempts cap, concurrency), beat registration.
"""

from __future__ import annotations

import os
import sys
import tempfile
import threading
import uuid
from datetime import timedelta
from pathlib import Path

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

_PASSWORD = "Aa123456!"
_CDN = "https://cdn.example.com/car_photos"
FLAG = "SAVED_SEARCH_ALERT_DURABILITY"


# ---------------------------------------------------------------------------
# App / isolation fixtures
# ---------------------------------------------------------------------------


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_f04d_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ.pop(FLAG, None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "f04d.db")
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
    """Flag off by default, no broker/FCM, clean alert/job/moderation state."""
    from kk.auto_moderation import config
    from kk.models import (
        AppSetting,
        ListingModerationEvent,
        ListingModerationRun,
        Notification,
        SavedSearch,
        SavedSearchAlert,
        SavedSearchAlertJob,
        db,
    )

    for k in (
        FLAG,
        "SAVED_SEARCH_ALERT_MAX_AGE_HOURS",
        "SAVED_SEARCH_ALERT_LEASE_SECONDS",
        "SAVED_SEARCH_ALERT_MAX_ATTEMPTS",
        "SAVED_SEARCH_ALERT_SWEEP_BATCH",
        "SAVED_SEARCH_ALERT_SWEEP_GRACE_SECONDS",
        "SAVED_SEARCH_ALERT_JOB_BUDGET_SECONDS",
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

    # create_app() on this module's fresh SQLite file runs the Alembic chain
    # in-process; migrations/env.py calls logging.config.fileConfig(), whose
    # default disable_existing_loggers=True silences every logger created
    # earlier (a test-only artefact: production runs `flask db upgrade` in its
    # own process). Re-enable the loggers whose output these tests assert on.
    import logging

    for name in ("kk.saved_search_alert_jobs", "kk.tasks.alert_tasks"):
        logging.getLogger(name).disabled = False

    import kk.tasks.moderation_tasks as mt

    monkeypatch.setattr(mt.moderate_listing_task, "apply_async", lambda *a, **k: None)
    monkeypatch.setattr(mt.send_moderation_alert_task, "apply_async", lambda *a, **k: None)
    with app.app_context():
        for model in (
            SavedSearchAlertJob,
            SavedSearchAlert,
            SavedSearch,
            Notification,
            ListingModerationEvent,
            ListingModerationRun,
        ):
            model.query.delete()
        AppSetting.query.filter_by(key=config.SETTINGS_KEY).delete()
        db.session.commit()
    yield


class Broker:
    """Stands in for ``notify_saved_searches_for_car.apply_async``."""

    def __init__(self):
        self.calls: list[tuple[tuple, dict]] = []
        self.fail: Exception | None = None

    @property
    def car_ids(self):
        return [a[0] for a, _k in self.calls]


@pytest.fixture
def broker(monkeypatch):
    import kk.tasks.alert_tasks as at

    b = Broker()

    def fake_apply_async(args=(), kwargs=None, **options):
        if b.fail is not None:
            raise b.fail
        b.calls.append((tuple(args), dict(options)))

    monkeypatch.setattr(at.notify_saved_searches_for_car, "apply_async", fake_apply_async)
    return b


class Pushes:
    def __init__(self):
        self.sent: list[dict] = []
        self.hook = None  # called before recording; may raise
        self.result = True

    def by_search(self):
        out: dict[str, int] = {}
        for p in self.sent:
            sid = p["data"]["saved_search_id"]
            out[sid] = out.get(sid, 0) + 1
        return out


@pytest.fixture
def pushes(monkeypatch):
    import kk.tasks.alert_tasks as at

    p = Pushes()

    def fake_send_push(token, *, title, body, data=None, user_id=None):
        if p.hook is not None:
            p.hook(token, data)
        p.sent.append({"token": token, "title": title, "data": dict(data or {}), "user_id": user_id})
        return p.result

    monkeypatch.setattr(at, "send_push", fake_send_push)
    return p


def _set_flag(monkeypatch, value):
    monkeypatch.setenv(FLAG, value)


# ---------------------------------------------------------------------------
# Builders
# ---------------------------------------------------------------------------


def _auth(token):
    return {"Authorization": f"Bearer {token}"}


def _user(app, *, admin=False, dealer=False, token=False):
    from kk.models import User, db
    from kk.tests.admin_auth_helpers import attach_admin_account

    username = f"f04d_{uuid.uuid4().hex[:10]}"
    with app.app_context():
        u = User(
            username=username,
            phone_number=f"075{uuid.uuid4().int % 10**8:08d}",
            first_name="F04",
            last_name="Durable",
            is_active=True,
            is_verified=True,
            phone_verified=True,
            is_admin=admin,
            dealer_status="approved" if dealer else "none",
            public_id=f"f04d-{uuid.uuid4().hex[:12]}",
        )
        u.set_password(_PASSWORD)
        if token:
            u.firebase_token = f"fcm-{uuid.uuid4().hex[:10]}"
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


def _search(app, uid, filters=None, *, name="Camrys", notify=True):
    from kk.models import SavedSearch, db

    with app.app_context():
        s = SavedSearch(user_id=uid, name=name, filters=filters or {"brand": "toyota"}, notify=notify)
        db.session.add(s)
        db.session.commit()
        return s.id, s.public_id


def _watchers(app, n=1):
    """n watchers with FCM tokens, each with one matching saved search."""
    out = []
    for i in range(n):
        uid, _ = _user(app, token=True)
        sid, spub = _search(app, uid, name=f"S{i}")
        out.append({"uid": uid, "sid": sid, "spub": spub})
    return out


def _job(app, car_id):
    from kk.models import SavedSearchAlertJob

    with app.app_context():
        j = SavedSearchAlertJob.query.filter_by(car_id=car_id).first()
        if j is None:
            return None
        return {
            "id": j.id, "created_at": j.created_at, "claimed_at": j.claimed_at,
            "next_run_at": j.next_run_at, "finished_at": j.finished_at,
            "outcome": j.outcome, "attempts": j.attempts, "last_error": j.last_error,
        }


def _job_count(app):
    from kk.models import SavedSearchAlertJob

    with app.app_context():
        return SavedSearchAlertJob.query.count()


def _alert_rows(app, car_id):
    from kk.models import SavedSearchAlert

    with app.app_context():
        return SavedSearchAlert.query.filter_by(car_id=car_id).count()


def _notif_count(app, notification_type="saved_search"):
    from kk.models import Notification

    with app.app_context():
        return Notification.query.filter_by(notification_type=notification_type).count()


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


def _run_task(app, car_id):
    """The real fast-path task body (``.run``: the Celery ``__call__`` would bind
    the process-wide singleton Flask app to this module's database)."""
    import kk.tasks.alert_tasks as at

    with app.app_context():
        return at.notify_saved_searches_for_car.run(car_id)


def _process(app, car_id, mode="on", **kw):
    import kk.tasks.alert_tasks as at

    with app.app_context():
        return at.process_saved_search_alert_job(car_id, mode=mode, **kw)


def _reconcile(app, enqueue, now=None):
    from kk import saved_search_alert_jobs as jobs

    with app.app_context():
        return jobs.reconcile(now, enqueue=enqueue)


def _reset_alert_state(app):
    from kk.models import SavedSearch, SavedSearchAlert, SavedSearchAlertJob, db

    with app.app_context():
        for model in (SavedSearchAlertJob, SavedSearchAlert, SavedSearch):
            model.query.delete()
        db.session.commit()


# ---------------------------------------------------------------------------
# 1. Flag modes
# ---------------------------------------------------------------------------


def test_flag_values_default_off_and_garbage_is_off(monkeypatch):
    from kk import saved_search_alert_jobs as jobs

    assert jobs.durability_mode() == "off"
    for raw, expected in [("off", "off"), (" RECORD ", "record"), ("On", "on"), ("", "off"),
                          ("true", "off"), ("1", "off"), ("enabled", "off")]:
        monkeypatch.setenv(FLAG, raw)
        assert jobs.durability_mode() == expected, raw


def test_flag_off_writes_no_job_on_any_activation_path(app, client, broker):
    uid, _ = _user(app)
    one = _car(app, uid)
    many = [_car(app, uid) for _ in range(2)]
    token = _admin_token(app, client)
    assert _patch(client, token, one, {"status": "active"}).status_code == 200
    assert _bulk(client, token, many, {"status": "active"}).status_code == 200
    assert _job_count(app) == 0
    # fast path exactly as before: one enqueue per activated car
    assert sorted(broker.car_ids) == sorted([one["id"]] + [c["id"] for c in many])


def test_flag_off_sweep_returns_immediately_and_touches_nothing(app, monkeypatch):
    from kk import saved_search_alert_jobs as jobs
    from kk.models import db

    def boom(*a, **k):
        raise AssertionError("flag off: the sweep must not touch the database")

    with app.app_context():
        monkeypatch.setattr(db.session, "execute", boom)
        monkeypatch.setattr(db.session, "query", boom)
        out = jobs.reconcile(enqueue=lambda *a, **k: boom())
    assert out == {"mode": "off"}


def test_flag_off_task_is_the_legacy_push_before_claim_order(app, client, pushes):
    """Legacy: the SavedSearchAlert row is written AFTER the push."""
    from kk.models import SavedSearchAlert, db

    seen = []
    pushes.hook = lambda token, data: seen.append(db.session.query(SavedSearchAlert).count())
    w = _watchers(app, 1)
    seller, _ = _user(app)
    car = _car(app, seller, status="active")
    out = _run_task(app, car["id"])
    assert out == {"matched": 1}
    assert seen == [0]  # nothing claimed at push time
    assert _alert_rows(app, car["id"]) == 1
    assert w


def test_on_mode_task_claims_the_pair_before_the_push(app, client, pushes, monkeypatch):
    """Claim-first: when the push happens the pair's row is already flushed in
    the same session (and uncommitted: a crash would roll it back)."""
    from kk.models import SavedSearchAlert, db

    _set_flag(monkeypatch, "on")
    seen = []
    pushes.hook = lambda token, data: seen.append(db.session.query(SavedSearchAlert).count())
    _watchers(app, 1)
    seller, _ = _user(app)
    car = _car(app, seller, status="active")
    assert _run_task(app, car["id"]) == {"matched": 1}
    assert seen == [1]


def test_record_mode_sweep_counts_only_and_sends_nothing(app, client, broker, pushes, monkeypatch):
    _set_flag(monkeypatch, "record")
    _watchers(app, 1)
    seller, _ = _user(app)
    lost = _car(app, seller)
    ok = _car(app, seller)
    token = _admin_token(app, client)

    broker.fail = None
    assert _patch(client, token, lost, {"status": "active"}).status_code == 200  # message "lost" (never run)
    assert _patch(client, token, ok, {"status": "active"}).status_code == 200
    assert _job(app, lost["id"]) is not None and _job(app, ok["id"]) is not None
    # the fast path for `ok` completes -> job done; `lost` was never delivered
    out = _run_task(app, ok["id"])
    assert out == {"matched": 1}
    assert _job(app, ok["id"])["outcome"] == "done"

    created = _job(app, lost["id"])["created_at"]
    enqueued = []
    stats = _reconcile(app, lambda *a, **k: enqueued.append(a), now=created + timedelta(minutes=10))
    assert stats["mode"] == "record"
    assert stats["would_redrive"] == 1 and stats["would_expire"] == 0
    assert enqueued == []  # sends nothing
    assert len(pushes.sent) == 1  # only the fast-path push for `ok`
    j = _job(app, lost["id"])
    assert j["finished_at"] is None and j["attempts"] == 0 and j["claimed_at"] is None  # untouched

    # old unfinished rows are only COUNTED as would_expire in record mode
    stats = _reconcile(app, lambda *a, **k: None, now=created + timedelta(hours=80))
    assert stats["would_expire"] == 1 and _job(app, lost["id"])["finished_at"] is None


def test_record_mode_fast_path_duplicates_are_still_deduped(app, pushes, monkeypatch):
    _set_flag(monkeypatch, "record")
    _watchers(app, 2)
    seller, _ = _user(app)
    car = _car(app, seller, status="active")
    for _ in range(3):
        _run_task(app, car["id"])
    assert sorted(pushes.by_search().values()) == [1, 1]
    assert _alert_rows(app, car["id"]) == 2
    assert _notif_count(app) == 2


# ---------------------------------------------------------------------------
# 2. First publication: a job on every activation path ...
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("mode", ["record", "on"])
def test_admin_single_approve_records_exactly_one_job(app, client, broker, monkeypatch, mode):
    _set_flag(monkeypatch, mode)
    uid, _ = _user(app)
    car = _car(app, uid)
    token = _admin_token(app, client)
    assert _patch(client, token, car, {"status": "active"}).status_code == 200
    assert _job_count(app) == 1
    j = _job(app, car["id"])
    assert j["finished_at"] is None and j["attempts"] == 0
    # repeated approval: no second job (UNIQUE(car_id)), admin call still fine
    assert _patch(client, token, car, {"status": "active"}).status_code == 200
    assert _job_count(app) == 1


def test_admin_bulk_approve_records_only_for_newly_activated(app, client, broker, monkeypatch):
    _set_flag(monkeypatch, "on")
    uid, _ = _user(app)
    p1, p2 = _car(app, uid), _car(app, uid)
    already = _car(app, uid, status="active")
    sold = _car(app, uid, status="sold")
    hidden = _car(app, uid, status="hidden", active=False)
    blocked = _car(app, uid, media="processing")
    token = _admin_token(app, client)
    r = _bulk(client, token, [p1, p2, already, sold, hidden, blocked], {"status": "active", "is_active": True})
    assert r.status_code == 200, r.data
    assert _job(app, p1["id"]) and _job(app, p2["id"])
    for other in (already, sold, hidden, blocked):
        assert _job(app, other["id"]) is None
    assert _job_count(app) == 2


def test_bulk_rolls_back_every_job_when_a_later_row_fails(app, client, broker, monkeypatch):
    """The whole bulk is one transaction: a ValueError on a later row (past
    featured_until) rolls back activations AND the job rows already added."""
    _set_flag(monkeypatch, "on")
    uid, _ = _user(app)
    cars = [_car(app, uid) for _ in range(3)]
    token = _admin_token(app, client)
    r = _bulk(client, token, cars, {"status": "active", "is_featured": True,
                                    "featured_until": "2001-01-01T00:00:00Z"})
    assert r.status_code == 400
    assert _job_count(app) == 0
    assert all(_state(app, c["id"])[0] == "pending" for c in cars)


def _live(monkeypatch, app):
    from kk.auto_moderation import config

    monkeypatch.setenv("AUTO_MODERATION_ALLOW_LIVE", "1")
    with app.app_context():
        config.save_settings({"mode": "live"})


def _moderate(app, car_id):
    from kk.auto_moderation.engine import moderate

    with app.app_context():
        return moderate("listing", car_id)


def test_auto_moderation_publish_records_job_once(app, broker, monkeypatch):
    _set_flag(monkeypatch, "on")
    _live(monkeypatch, app)
    uid, _ = _user(app, dealer=True)
    car = _car(app, uid)
    assert _moderate(app, car["id"])["outcome"] == "published"
    assert _job(app, car["id"]) is not None
    _moderate(app, car["id"])
    assert _job_count(app) == 1


def test_auto_moderation_shadow_or_review_records_no_job(app, broker, monkeypatch):
    _set_flag(monkeypatch, "on")
    uid, _ = _user(app, dealer=True)
    car = _car(app, uid)
    assert _moderate(app, car["id"])["outcome"] != "published"  # shadow mode
    assert _job_count(app) == 0


def test_admin_override_approve_records_job(app, client, broker, monkeypatch):
    _set_flag(monkeypatch, "on")
    uid, _ = _user(app)  # unproven seller -> NEEDS_REVIEW
    car = _car(app, uid)
    _moderate(app, car["id"])
    from kk.models import ListingModerationRun

    with app.app_context():
        run_id = ListingModerationRun.query.filter_by(car_id=car["id"]).order_by(
            ListingModerationRun.id.desc()
        ).first().public_id
    token = _admin_token(app, client)
    r = client.post(
        f"/api/admin/auto-moderation/runs/{run_id}/override",
        json={"action": "approve"}, headers=_auth(token),
    )
    assert r.status_code == 200, r.data
    assert _job(app, car["id"]) is not None


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


def test_create_published_records_job_but_create_pending_does_not(app, client, broker, monkeypatch):
    _set_flag(monkeypatch, "on")
    headers = _seller_headers(app, client)
    r = client.post("/api/cars", json=_create_payload(), headers=headers)
    assert r.status_code == 201 and r.get_json()["car"]["status"] == "active"
    assert _job_count(app) == 1

    monkeypatch.setenv("LISTING_REQUIRE_APPROVAL", "true")
    r = client.post("/api/cars", json=_create_payload(), headers=headers)
    assert r.status_code == 201 and r.get_json()["car"]["status"] == "pending"
    assert _job_count(app) == 1  # nothing for the pending one ...
    token = _admin_token(app, client)
    created = r.get_json()["car"]
    r = client.patch(f"/api/admin/cars/{created['id']}/status", json={"status": "active"}, headers=_auth(token))
    assert r.status_code == 200
    assert _job_count(app) == 2  # ... until it is approved


def test_job_recorded_when_seller_account_is_gone(app, client, broker, monkeypatch):
    """No seller notification is possible (seller_id NULL) but the durable
    marker is independent of the Notification table."""
    from kk.models import Car, db

    _set_flag(monkeypatch, "on")
    uid, _ = _user(app)
    car = _car(app, uid)
    with app.app_context():
        Car.query.get(car["id"]).seller_id = None
        db.session.commit()
    token = _admin_token(app, client)
    assert _patch(client, token, car, {"status": "active"}).status_code == 200
    assert _job(app, car["id"]) is not None


def test_car_already_alerted_never_gets_a_job(app, monkeypatch):
    """Evidence of a previous alert blocks a job even without a job row."""
    from kk.models import SavedSearchAlert, db
    from kk import saved_search_alert_jobs as jobs

    _set_flag(monkeypatch, "on")
    w = _watchers(app, 1)
    uid, _ = _user(app)
    car = _car(app, uid, status="active")
    with app.app_context():
        db.session.add(SavedSearchAlert(saved_search_id=w[0]["sid"], car_id=car["id"]))
        db.session.commit()
        assert jobs.record_alert_job(car["id"]) is False
        db.session.rollback()
    assert _job_count(app) == 0


# ---------------------------------------------------------------------------
# 3. ... and never for anything that is not a first publication
# ---------------------------------------------------------------------------


def test_unhide_sold_reactivation_and_edits_never_record_a_job(app, client, broker, monkeypatch):
    _set_flag(monkeypatch, "on")
    uid, _ = _user(app)
    token = _admin_token(app, client)
    cases = [
        ("hidden", False, {"status": "active", "is_active": True}),  # un-hide
        ("sold", True, {"status": "active"}),  # sold -> active (admin)
        ("draft", True, {"status": "active"}),
        ("active", True, {"status": "active"}),  # already active
        ("active", True, {"is_featured": True}),
    ]
    for status, active, body in cases:
        car = _car(app, uid, status=status, active=active)
        assert _patch(client, token, car, body).status_code == 200
        assert _job(app, car["id"]) is None, (status, body)
    assert _job_count(app) == 0
    assert broker.calls == []


def test_seller_mark_active_and_put_status_and_price_edit_record_no_job(app, client, broker, monkeypatch):
    _set_flag(monkeypatch, "on")
    headers = _seller_headers(app, client)
    r = client.post("/api/cars", json=_create_payload(), headers=headers)
    assert r.status_code == 201
    created = r.get_json()["car"]
    assert _job_count(app) == 1  # the create itself (first publication)
    first_job = _job(app, _numeric_id(app, created["id"]))

    assert client.post(f"/api/cars/{created['id']}/mark-sold", headers=headers).status_code == 200
    assert client.post(f"/api/cars/{created['id']}/mark-active", headers=headers).status_code == 200
    assert client.put(f"/api/cars/{created['id']}", json={"status": "sold"}, headers=headers).status_code == 200
    assert client.put(f"/api/cars/{created['id']}", json={"status": "active"}, headers=headers).status_code == 200
    assert client.put(f"/api/cars/{created['id']}", json={"price": 14000}, headers=headers).status_code == 200
    assert _job_count(app) == 1
    assert _job(app, _numeric_id(app, created["id"]))["id"] == first_job["id"]


def _numeric_id(app, public_id):
    from kk.models import Car

    with app.app_context():
        return Car.query.filter_by(public_id=public_id).one().id


def test_reapproval_of_an_already_published_listing_does_not_alert_again(
    app, client, broker, pushes, monkeypatch
):
    """published (job done) -> admin sets pending -> approves again: the legacy
    pending->active rule dispatches again, but with the flag ON the finished
    job suppresses it, so a search created in between is NOT alerted.
    With the flag OFF (today's behaviour) it is: the contrast is the point."""
    import kk.retention_dispatch as rd

    def run_inline(car_id):
        _run_task(app, car_id)

    monkeypatch.setattr(rd, "dispatch_saved_search_alerts", run_inline)

    results = {}
    for mode in ("on", "off"):
        if mode == "on":
            _set_flag(monkeypatch, "on")
        else:
            monkeypatch.delenv(FLAG, raising=False)
        pushes.sent.clear()
        _reset_alert_state(app)
        first = _watchers(app, 1)
        uid, _ = _user(app)
        car = _car(app, uid)
        token = _admin_token(app, client)
        assert _patch(client, token, car, {"status": "active"}).status_code == 200
        assert len(pushes.sent) == 1  # genuine first publication
        newcomer = _watchers(app, 1)  # created after publication
        assert _patch(client, token, car, {"status": "pending"}).status_code == 200
        assert _patch(client, token, car, {"status": "active"}).status_code == 200
        results[mode] = len(pushes.sent)
        assert first and newcomer
    assert results["on"] == 1  # nobody new alerted
    assert results["off"] == 2  # legacy behaviour unchanged when the flag is off


# ---------------------------------------------------------------------------
# 4. Transaction atomicity
# ---------------------------------------------------------------------------


def test_failed_activation_commit_leaves_neither_job_nor_activation(app, client, broker, monkeypatch):
    from kk.models import db

    _set_flag(monkeypatch, "on")
    uid, _ = _user(app)
    car = _car(app, uid)
    token = _admin_token(app, client)

    real_commit = db.session.commit
    state = {"armed": True}

    def failing_commit():
        if state["armed"]:
            state["armed"] = False
            raise RuntimeError("commit failed")
        return real_commit()

    with monkeypatch.context() as m:
        m.setattr(db.session, "commit", failing_commit)
        r = _patch(client, token, car, {"status": "active"})
    assert r.status_code == 500
    assert _state(app, car["id"])[0] == "pending"
    assert _job_count(app) == 0
    assert broker.calls == []  # nothing dispatched for a rolled-back activation


def test_media_gate_block_creates_no_job(app, client, broker, monkeypatch):
    _set_flag(monkeypatch, "on")
    uid, _ = _user(app)
    car = _car(app, uid, media="processing")
    token = _admin_token(app, client)
    assert _patch(client, token, car, {"status": "active"}).status_code == 409
    assert _job_count(app) == 0 and _state(app, car["id"])[0] == "pending"


def test_missing_job_table_degrades_to_fast_path_only(app, client, broker, monkeypatch):
    """Worker/web deployed before the migration: activation must still work."""
    from sqlalchemy import text
    from kk.models import db

    _set_flag(monkeypatch, "on")
    uid, _ = _user(app)
    car = _car(app, uid)
    token = _admin_token(app, client)
    with app.app_context():
        db.session.execute(text("ALTER TABLE saved_search_alert_job RENAME TO saved_search_alert_job_x"))
        db.session.commit()
    try:
        r = _patch(client, token, car, {"status": "active"})
        assert r.status_code == 200, r.data
        assert _state(app, car["id"]) == ("active", True)
        assert broker.car_ids == [car["id"]]  # fast path unaffected
        out = _reconcile(app, lambda *a, **k: None)
        assert out.get("error")  # sweep logs and skips instead of raising
    finally:
        with app.app_context():
            db.session.rollback()
            db.session.execute(text("ALTER TABLE saved_search_alert_job_x RENAME TO saved_search_alert_job"))
            db.session.commit()


def test_task_degrades_to_legacy_when_job_table_missing(app, pushes, monkeypatch):
    from sqlalchemy import text
    from kk.models import db

    _set_flag(monkeypatch, "on")
    _watchers(app, 1)
    uid, _ = _user(app)
    car = _car(app, uid, status="active")
    with app.app_context():
        db.session.execute(text("ALTER TABLE saved_search_alert_job RENAME TO saved_search_alert_job_x"))
        db.session.commit()
    try:
        assert _run_task(app, car["id"]) == {"matched": 1}
    finally:
        with app.app_context():
            db.session.rollback()
            db.session.execute(text("ALTER TABLE saved_search_alert_job_x RENAME TO saved_search_alert_job"))
            db.session.commit()
    assert len(pushes.sent) == 1


# ---------------------------------------------------------------------------
# 5. Task: first publication -> exactly one job, one alert per pair
# ---------------------------------------------------------------------------


def test_first_publication_creates_one_job_and_one_alert_per_matching_search(
    app, client, pushes, monkeypatch
):
    import kk.retention_dispatch as rd

    _set_flag(monkeypatch, "on")
    monkeypatch.setattr(rd, "dispatch_saved_search_alerts", lambda cid: _run_task(app, cid))
    w = _watchers(app, 2)
    nomatch_uid, _ = _user(app, token=True)
    _search(app, nomatch_uid, {"brand": "bmw"}, name="BMWs")
    seller, _ = _user(app)
    car = _car(app, seller)
    token = _admin_token(app, client)

    assert _patch(client, token, car, {"status": "active"}).status_code == 200
    assert _job_count(app) == 1
    assert len(pushes.sent) == 2
    assert pushes.by_search() == {w[0]["spub"]: 1, w[1]["spub"]: 1}
    assert _alert_rows(app, car["id"]) == 2
    assert _notif_count(app) == 2
    j = _job(app, car["id"])
    assert j["outcome"] == "done" and j["finished_at"] and j["claimed_at"] is None and j["attempts"] == 1


def test_duplicate_task_delivery_keeps_duplicate_pushes_bounded(app, client, broker, pushes, monkeypatch):
    """Duplicate delivery of the same car message: with a finished job the
    duplicates are no-ops; the unique constraint backstops everything else.
    (At-least-once on the external push; NOT claimed exactly-once.)"""
    _set_flag(monkeypatch, "on")
    w = _watchers(app, 2)
    seller, _ = _user(app)
    car = _car(app, seller)
    token = _admin_token(app, client)
    assert _patch(client, token, car, {"status": "active"}).status_code == 200
    for _ in range(4):
        _run_task(app, car["id"])
    assert pushes.by_search() == {w[0]["spub"]: 1, w[1]["spub"]: 1}
    assert _alert_rows(app, car["id"]) == 2 and _notif_count(app) == 2
    assert _run_task(app, car["id"]) == {"matched": 0, "skipped": "job_finished_or_leased"}


def test_task_without_job_row_still_alerts_like_before(app, pushes, monkeypatch):
    """A message queued before the deploy / flag flip (no job row) is served."""
    _set_flag(monkeypatch, "on")
    w = _watchers(app, 1)
    seller, _ = _user(app)
    car = _car(app, seller, status="active")
    assert _job(app, car["id"]) is None
    assert _run_task(app, car["id"]) == {"matched": 1}
    assert pushes.by_search() == {w[0]["spub"]: 1}
    assert _job(app, car["id"]) is None  # no bookkeeping invented


def test_listing_not_public_keeps_job_owed_then_alerts_after_it_is_public_again(
    app, client, broker, pushes, monkeypatch
):
    _set_flag(monkeypatch, "on")
    w = _watchers(app, 1)
    seller, _ = _user(app)
    car = _car(app, seller)
    token = _admin_token(app, client)
    assert _patch(client, token, car, {"status": "active"}).status_code == 200
    assert _patch(client, token, car, {"status": "hidden", "is_active": False}).status_code == 200
    created = _job(app, car["id"])["created_at"]

    t1 = created + timedelta(minutes=5)
    assert _process(app, car["id"], now=t1) == {"matched": 0, "skipped": "inactive_or_missing"}
    j = _job(app, car["id"])
    assert pushes.sent == [] and j["finished_at"] is None
    assert j["attempts"] == 0 and j["claimed_at"] is None  # no attempt consumed
    assert j["next_run_at"] == t1 + timedelta(seconds=900)

    assert _patch(client, token, car, {"status": "active", "is_active": True}).status_code == 200  # un-hide
    assert _job_count(app) == 1
    out = _process(app, car["id"], now=t1 + timedelta(minutes=20))
    assert out == {"matched": 1}
    assert pushes.by_search() == {w[0]["spub"]: 1}
    assert _job(app, car["id"])["outcome"] == "done"


# ---------------------------------------------------------------------------
# 6. Claim-first crash / retry semantics
# ---------------------------------------------------------------------------


def _published_car_with_job(app, client, monkeypatch, watchers=1):
    """Activated through the real admin route with the flag on (a pending job),
    broker stubbed so nothing ran yet."""
    w = _watchers(app, watchers)
    seller, _ = _user(app)
    car = _car(app, seller)
    token = _admin_token(app, client)
    assert _patch(client, token, car, {"status": "active"}).status_code == 200
    return w, car


def test_claim_lost_to_a_competing_claimer_skips_the_push(app, client, broker, pushes, monkeypatch):
    """Unique-key race: another runner inserts the pair between our pre-check
    and our claim. We get IntegrityError and must NOT push (they do)."""
    import kk.tasks.alert_tasks as at
    from kk.models import SavedSearchAlert, User, db

    _set_flag(monkeypatch, "on")
    w = _watchers(app, 1)
    seller, _ = _user(app)
    car = _car(app, seller, status="active")

    with app.app_context():
        original_get = db.session.get
        competitor = {"done": False}

        def get_and_race(model, ident, *a, **k):
            row = original_get(model, ident, *a, **k)
            if model is User and not competitor["done"]:
                competitor["done"] = True
                with db.engine.begin() as conn:  # the competitor's own committed claim
                    conn.execute(
                        SavedSearchAlert.__table__.insert().values(
                            saved_search_id=w[0]["sid"], car_id=car["id"]
                        )
                    )
            return row

        monkeypatch.setattr(db.session, "get", get_and_race)
        out = at.process_saved_search_alert_job(car["id"], mode="on")
    assert out == {"matched": 0}
    assert pushes.sent == [] and _notif_count(app) == 0
    assert _alert_rows(app, car["id"]) == 1  # the competitor's row only


def test_push_error_after_claim_rolls_the_claim_back_and_job_is_redriven(
    app, client, broker, pushes, monkeypatch
):
    _set_flag(monkeypatch, "on")
    w, car = _published_car_with_job(app, client, monkeypatch)
    created = _job(app, car["id"])["created_at"]

    def explode(token, data):
        raise RuntimeError("fcm down")

    pushes.hook = explode
    t1 = created + timedelta(minutes=4)
    out = _process(app, car["id"], now=t1)
    assert out["matched"] == 0 and out["incomplete"] == "partial_errors"
    assert _alert_rows(app, car["id"]) == 0 and _notif_count(app) == 0  # claim rolled back
    j = _job(app, car["id"])
    assert j["attempts"] == 1 and j["claimed_at"] is None and j["finished_at"] is None
    assert j["next_run_at"] == t1 + timedelta(seconds=120) and j["last_error"]

    pushes.hook = None
    assert _process(app, car["id"], now=t1 + timedelta(seconds=121)) == {"matched": 1}
    assert pushes.by_search() == {w[0]["spub"]: 1}
    assert _job(app, car["id"])["outcome"] == "done"


def test_commit_failure_after_push_repushes_that_pair_once_on_redrive(
    app, client, broker, pushes, monkeypatch
):
    """Crash window: push went out, the commit of claim+Notification failed.
    The claim is rolled back, so the redrive pushes the pair AGAIN (one
    duplicate, bounded) instead of ever missing it; only one alert row and one
    Notification are ever committed."""
    from kk.models import db

    _set_flag(monkeypatch, "on")
    w, car = _published_car_with_job(app, client, monkeypatch)
    created = _job(app, car["id"])["created_at"]
    t1 = created + timedelta(minutes=4)

    with app.app_context():
        real_commit = db.session.commit
        calls = {"n": 0}

        def commit_fails_once_after_push():
            if pushes.sent and calls["n"] == 0:
                calls["n"] += 1
                raise RuntimeError("connection lost during commit")
            return real_commit()

        monkeypatch.setattr(db.session, "commit", commit_fails_once_after_push)
        import kk.tasks.alert_tasks as at

        first = at.process_saved_search_alert_job(car["id"], mode="on", now=t1)
        monkeypatch.setattr(db.session, "commit", real_commit)
    assert first["incomplete"] == "partial_errors"
    assert len(pushes.sent) == 1 and _alert_rows(app, car["id"]) == 0

    assert _process(app, car["id"], now=t1 + timedelta(seconds=121)) == {"matched": 1}
    assert len(pushes.sent) == 2  # exactly one duplicate push for the crashed pair
    assert pushes.by_search() == {w[0]["spub"]: 2}
    assert _alert_rows(app, car["id"]) == 1 and _notif_count(app) == 1
    assert _job(app, car["id"])["outcome"] == "done"


def test_worker_killed_mid_dispatch_lease_expiry_completes_only_the_remaining(
    app, client, broker, pushes, monkeypatch
):
    """BaseException (kill/SystemExit) in the middle of the second search: the
    job stays leased; after the lease expires the redrive skips the committed
    first pair and alerts the rest."""
    _set_flag(monkeypatch, "on")
    w, car = _published_car_with_job(app, client, monkeypatch, watchers=3)
    created = _job(app, car["id"])["created_at"]
    t1 = created + timedelta(minutes=4)

    def die_on_second(token, data):
        if len(pushes.sent) == 1:
            raise SystemExit("worker killed")

    pushes.hook = die_on_second
    with pytest.raises(SystemExit):
        _process(app, car["id"], now=t1)
    from kk.models import db

    with app.app_context():
        db.session.rollback()
    assert len(pushes.sent) == 1 and _alert_rows(app, car["id"]) == 1
    j = _job(app, car["id"])
    assert j["claimed_at"] == t1 and j["finished_at"] is None

    # the lease is still live: a duplicate/redriven message cannot take over
    assert _process(app, car["id"], now=t1 + timedelta(seconds=60)) == {
        "matched": 0, "skipped": "job_finished_or_leased"
    }
    assert len(pushes.sent) == 1

    pushes.hook = None
    out = _process(app, car["id"], now=t1 + timedelta(seconds=901))
    assert out == {"matched": 2}
    assert sorted(pushes.by_search().values()) == [1, 1, 1]  # first pair NOT re-pushed
    assert _alert_rows(app, car["id"]) == 3 and _notif_count(app) == 3
    j = _job(app, car["id"])
    assert j["outcome"] == "done" and j["attempts"] == 2


def test_budget_exhausted_run_resumes_without_burning_an_attempt(
    app, client, broker, pushes, monkeypatch
):
    _set_flag(monkeypatch, "on")
    w, car = _published_car_with_job(app, client, monkeypatch, watchers=2)
    created = _job(app, car["id"])["created_at"]
    t1 = created + timedelta(minutes=4)
    out = _process(app, car["id"], now=t1, budget_seconds=-1)  # already out of budget
    assert out == {"matched": 0, "incomplete": "partial_budget"}
    j = _job(app, car["id"])
    assert j["attempts"] == 0 and j["claimed_at"] is None and j["next_run_at"] == t1
    assert _process(app, car["id"], now=t1 + timedelta(seconds=1)) == {"matched": 2}


def test_push_returning_false_is_not_retried_and_in_app_notification_exists(
    app, client, broker, pushes, monkeypatch
):
    """Documented limit: an FCM rejection (False) is best effort and is NOT
    retried (unchanged from the legacy task); the claim and the in-app
    Notification still commit."""
    _set_flag(monkeypatch, "on")
    pushes.result = False
    w, car = _published_car_with_job(app, client, monkeypatch)
    assert _run_task(app, car["id"]) == {"matched": 1}
    assert _run_task(app, car["id"])["skipped"] == "job_finished_or_leased"
    assert len(pushes.sent) == 1 and _alert_rows(app, car["id"]) == 1 and _notif_count(app) == 1


# ---------------------------------------------------------------------------
# 7. Sweep
# ---------------------------------------------------------------------------


def _inline_enqueue(app, now_holder, mode="on"):
    """Sweep enqueue that runs the per-job task immediately at ``now_holder[0]``."""
    def enqueue(car_id, *, expires):
        _process(app, car_id, mode=mode, now=now_holder[0])
    return enqueue


def test_broker_outage_at_enqueue_then_sweep_recovers_the_alert_once(
    app, client, broker, pushes, monkeypatch
):
    from celery.exceptions import OperationalError

    _set_flag(monkeypatch, "on")
    broker.fail = OperationalError("redis down")
    w = _watchers(app, 2)
    seller, _ = _user(app)
    car = _car(app, seller)
    token = _admin_token(app, client)
    assert _patch(client, token, car, {"status": "active"}).status_code == 200  # admin unaffected
    assert broker.calls == [] and pushes.sent == []
    j = _job(app, car["id"])
    assert j is not None and j["finished_at"] is None  # committed with the activation
    created = j["created_at"]

    # inside the grace period the sweep leaves the fast path alone
    out = _reconcile(app, lambda *a, **k: pytest.fail("too early"), now=created + timedelta(seconds=60))
    assert out["redriven"] == 0

    now_holder = [created + timedelta(minutes=4)]
    out = _reconcile(app, _inline_enqueue(app, now_holder), now=now_holder[0])
    assert out["redriven"] == 1 and out["expired"] == 0 and out["failed"] == 0
    assert pushes.by_search() == {w[0]["spub"]: 1, w[1]["spub"]: 1}
    assert _job(app, car["id"])["outcome"] == "done"
    # next tick: nothing left, no re-send
    out = _reconcile(app, _inline_enqueue(app, now_holder), now=now_holder[0] + timedelta(minutes=5))
    assert out["redriven"] == 0 and len(pushes.sent) == 2


def test_sweep_enqueues_short_per_job_tasks_with_a_bounded_batch(app, client, broker, monkeypatch):
    monkeypatch.setenv("SAVED_SEARCH_ALERT_SWEEP_BATCH", "10")
    _set_flag(monkeypatch, "on")
    uid, _ = _user(app)
    token = _admin_token(app, client)
    cars = [_car(app, uid) for _ in range(25)]
    assert _bulk(client, token, cars, {"status": "active"}).status_code == 200
    assert _job_count(app) == 25
    t0 = max(_job(app, c["id"])["created_at"] for c in cars) + timedelta(minutes=4)

    enqueued: list[tuple[int, float]] = []
    seen: set[int] = set()
    for tick in range(3):
        out = _reconcile(app, lambda cid, *, expires: enqueued.append((cid, expires)),
                         now=t0 + timedelta(seconds=tick))
        assert out["redriven"] == (10 if tick < 2 else 5)
    ids = [cid for cid, _e in enqueued]
    assert sorted(ids) == sorted(c["id"] for c in cars) and len(set(ids)) == 25  # each once
    assert all(e == 600 for _c, e in enqueued)  # message expires with its dispatch lease
    seen.update(ids)
    # nothing ran inline: no pushes, no job processed
    assert all(_job(app, c["id"])["attempts"] == 0 for c in cars)


def test_dispatch_lease_blocks_reenqueue_until_visibility_lapses_message_lost(
    app, client, broker, monkeypatch
):
    """The enqueued message is "lost" (Redis flush): it is re-enqueued only
    after DISPATCH_VISIBILITY_SECONDS, never every tick."""
    _set_flag(monkeypatch, "on")
    uid, _ = _user(app)
    car = _car(app, uid)
    assert _patch(client, _admin_token(app, client), car, {"status": "active"}).status_code == 200
    t = _job(app, car["id"])["created_at"] + timedelta(minutes=4)
    sent = []
    enq = lambda cid, *, expires: sent.append(cid)  # noqa: E731
    assert _reconcile(app, enq, now=t)["redriven"] == 1
    assert _reconcile(app, enq, now=t + timedelta(minutes=5))["redriven"] == 0
    assert _reconcile(app, enq, now=t + timedelta(minutes=9, seconds=59))["redriven"] == 0
    assert _reconcile(app, enq, now=t + timedelta(minutes=10, seconds=1))["redriven"] == 1
    assert sent == [car["id"], car["id"]]


def test_enqueue_failure_releases_the_dispatch_lease_for_the_next_tick(app, client, broker, monkeypatch):
    _set_flag(monkeypatch, "on")
    uid, _ = _user(app)
    car = _car(app, uid)
    assert _patch(client, _admin_token(app, client), car, {"status": "active"}).status_code == 200
    t = _job(app, car["id"])["created_at"] + timedelta(minutes=4)

    def broken(cid, *, expires):
        raise ConnectionError("broker unreachable")

    out = _reconcile(app, broken, now=t)
    assert out["enqueue_failed"] == 1 and out["redriven"] == 0
    assert _job(app, car["id"])["next_run_at"] is None
    sent = []
    assert _reconcile(app, lambda cid, *, expires: sent.append(cid), now=t + timedelta(seconds=1))["redriven"] == 1
    assert sent == [car["id"]]


def test_sweep_skips_leased_and_backed_off_jobs(app, client, broker, monkeypatch):
    from kk import saved_search_alert_jobs as jobs

    _set_flag(monkeypatch, "on")
    uid, _ = _user(app)
    leased, backed_off = _car(app, uid), _car(app, uid)
    token = _admin_token(app, client)
    assert _bulk(client, token, [leased, backed_off], {"status": "active"}).status_code == 200
    t = _job(app, leased["id"])["created_at"] + timedelta(minutes=4)
    with app.app_context():
        assert jobs.claim_job(leased["id"], now=t).status == "claimed"
        claim = jobs.claim_job(backed_off["id"], now=t)
        assert jobs.defer_job(backed_off["id"], claim.token, delay_seconds=300,
                              count_attempt=False, now=t)
    sent = []
    enq = lambda cid, *, expires: sent.append(cid)  # noqa: E731
    assert _reconcile(app, enq, now=t + timedelta(minutes=2))["redriven"] == 0  # lease live / backed off
    out = _reconcile(app, enq, now=t + timedelta(seconds=901))  # both ready again
    assert sorted(sent) == sorted([leased["id"], backed_off["id"]]) and out["redriven"] == 2


def test_expiry_after_72h_marks_expired_logs_counts_and_never_sends_late(
    app, client, broker, pushes, monkeypatch, caplog
):
    import logging

    _set_flag(monkeypatch, "on")
    _watchers(app, 1)
    uid, _ = _user(app)
    old, young = _car(app, uid), _car(app, uid)
    token = _admin_token(app, client)
    assert _patch(client, token, old, {"status": "active"}).status_code == 200
    assert _patch(client, token, young, {"status": "active"}).status_code == 200
    created = _job(app, old["id"])["created_at"]

    # exactly at the boundary the job is still owed (and is redriven) ...
    sent = []
    out = _reconcile(app, lambda cid, *, expires: sent.append(cid), now=created + timedelta(hours=71, minutes=59))
    assert out["expired"] == 0 and sorted(sent) == sorted([old["id"], young["id"]])

    # ... one minute past the window: expired, counted, logged, nothing sent
    sent.clear()
    late = created + timedelta(hours=72, minutes=1)
    with caplog.at_level(logging.WARNING, logger="kk.saved_search_alert_jobs"):
        out = _reconcile(app, lambda cid, *, expires: sent.append(cid), now=late)
    assert out["expired"] == 2 and out["redriven"] == 0 and sent == []
    assert any("EXPIRED" in r.message and "count=2" in r.message for r in caplog.records)
    for car in (old, young):
        j = _job(app, car["id"])
        assert j["outcome"] == "expired" and j["finished_at"] is not None
    # a late message (or manual run) is refused: never delivered beyond the window
    assert _process(app, old["id"], now=late) == {"matched": 0, "skipped": "job_finished_or_leased"}
    assert pushes.sent == []
    assert _alert_rows(app, old["id"]) == 0


def test_expiry_catches_unexpired_but_overdue_rows_even_if_claim_is_attempted_first(app, client, broker, monkeypatch):
    """claim_job itself refuses a job past the window (the sweep may not have
    run yet), so a stale queued message cannot deliver late."""
    from kk import saved_search_alert_jobs as jobs

    _set_flag(monkeypatch, "on")
    uid, _ = _user(app)
    car = _car(app, uid)
    assert _patch(client, _admin_token(app, client), car, {"status": "active"}).status_code == 200
    created = _job(app, car["id"])["created_at"]
    with app.app_context():
        assert jobs.claim_job(car["id"], now=created + timedelta(hours=72, seconds=1)).status == "not_owner"
        assert jobs.claim_job(car["id"], now=created + timedelta(hours=71)).status == "claimed"


def test_recovery_window_is_configurable(app, client, broker, monkeypatch):
    from kk import saved_search_alert_jobs as jobs

    _set_flag(monkeypatch, "on")
    assert jobs.max_age() == timedelta(hours=72)  # default
    monkeypatch.setenv("SAVED_SEARCH_ALERT_MAX_AGE_HOURS", "2")
    uid, _ = _user(app)
    car = _car(app, uid)
    assert _patch(client, _admin_token(app, client), car, {"status": "active"}).status_code == 200
    created = _job(app, car["id"])["created_at"]
    assert _reconcile(app, lambda *a, **k: None, now=created + timedelta(hours=1, minutes=59))["expired"] == 0
    assert _reconcile(app, lambda *a, **k: None, now=created + timedelta(hours=2, minutes=1))["expired"] == 1
    monkeypatch.setenv("SAVED_SEARCH_ALERT_MAX_AGE_HOURS", "not-a-number")
    assert jobs.max_age() == timedelta(hours=72)


def test_poison_car_hits_attempt_cap_then_failed_and_other_cars_still_flow(
    app, client, broker, pushes, monkeypatch, caplog
):
    import logging
    from kk import saved_search_alert_jobs as jobs

    _set_flag(monkeypatch, "on")
    w = _watchers(app, 1)
    seller, _ = _user(app)
    bad, good = _car(app, seller, brand="toyota"), _car(app, seller, brand="toyota")
    token = _admin_token(app, client)
    assert _patch(client, token, bad, {"status": "active"}).status_code == 200
    assert _patch(client, token, good, {"status": "active"}).status_code == 200
    created = _job(app, bad["id"])["created_at"]

    def poison(tok, data):
        if data["car_id"] == bad["public_id"]:
            raise RuntimeError("poison")

    pushes.hook = poison
    t = created + timedelta(minutes=4)
    for attempt in range(5):
        t = t + timedelta(minutes=20)
        _process(app, bad["id"], now=t)
        j = _job(app, bad["id"])
        assert j["attempts"] == attempt + 1 and j["finished_at"] is None
    _process(app, good["id"], now=t)
    assert _job(app, good["id"])["outcome"] == "done"
    assert pushes.by_search() == {w[0]["spub"]: 1}  # only `good` was ever delivered

    # the 6th message cannot claim (attempts exhausted) ...
    assert _process(app, bad["id"], now=t + timedelta(minutes=20)) == {
        "matched": 0, "skipped": "job_finished_or_leased"
    }
    # ... and the sweep surfaces it as failed with an ERROR
    with caplog.at_level(logging.ERROR, logger="kk.saved_search_alert_jobs"):
        out = _reconcile(app, lambda *a, **k: None, now=t + timedelta(minutes=30))
    assert out["failed"] == 1
    assert _job(app, bad["id"])["outcome"] == "failed"
    assert any("FAILED" in r.message for r in caplog.records)
    with app.app_context():
        stats = jobs.job_stats(t + timedelta(minutes=30))
    assert stats["failed"] == 1 and stats["done"] == 1


# ---------------------------------------------------------------------------
# 8. Concurrency (threads on SQLite; real PG concurrency in the PG module)
# ---------------------------------------------------------------------------


def _threads(app, fn, n):
    barrier = threading.Barrier(n)
    results: list = [None] * n
    errors: list = []

    def work(i):
        try:
            with app.app_context():
                barrier.wait(timeout=10)
                results[i] = fn(i)
        except Exception as exc:  # pragma: no cover - surfaced below
            errors.append(exc)

    ts = [threading.Thread(target=work, args=(i,)) for i in range(n)]
    for t in ts:
        t.start()
    for t in ts:
        t.join(30)
    assert not errors, errors
    return results


def test_two_runners_claiming_the_same_job_only_one_wins(app, client, broker, monkeypatch):
    from kk import saved_search_alert_jobs as jobs

    _set_flag(monkeypatch, "on")
    uid, _ = _user(app)
    car = _car(app, uid)
    assert _patch(client, _admin_token(app, client), car, {"status": "active"}).status_code == 200
    t = _job(app, car["id"])["created_at"] + timedelta(minutes=4)
    res = _threads(app, lambda i: jobs.claim_job(car["id"], now=t).status, 6)
    assert sorted(res) == ["claimed"] + ["not_owner"] * 5
    assert _job(app, car["id"])["attempts"] == 1


def test_two_concurrent_sweeps_do_not_double_enqueue(app, client, broker, monkeypatch):
    _set_flag(monkeypatch, "on")
    uid, _ = _user(app)
    token = _admin_token(app, client)
    cars = [_car(app, uid) for _ in range(8)]
    assert _bulk(client, token, cars, {"status": "active"}).status_code == 200
    t = max(_job(app, c["id"])["created_at"] for c in cars) + timedelta(minutes=4)
    monkeypatch.setenv("SAVED_SEARCH_ALERT_SWEEP_BATCH", "50")
    lock = threading.Lock()
    enqueued: list[int] = []

    def enq(cid, *, expires):
        with lock:
            enqueued.append(cid)

    from kk import saved_search_alert_jobs as jobs

    outs = _threads(app, lambda i: jobs.reconcile(t, enqueue=enq), 3)
    assert sorted(enqueued) == sorted(c["id"] for c in cars)  # one enqueue per job (dispatch lease), not a delivery claim
    assert sum(o["redriven"] for o in outs) == 8


def test_concurrent_task_runs_for_one_car_push_each_pair_once(app, client, broker, pushes, monkeypatch):
    """Two fast-path workers (or beat + worker) on the same car with a live
    job: the lease admits one; the pair claim is the backstop."""
    _set_flag(monkeypatch, "on")
    w = _watchers(app, 3)
    seller, _ = _user(app)
    car = _car(app, seller)
    assert _patch(client, _admin_token(app, client), car, {"status": "active"}).status_code == 200
    import kk.tasks.alert_tasks as at

    res = _threads(app, lambda i: at.notify_saved_searches_for_car.run(car["id"]), 4)
    assert sorted(pushes.by_search().values()) == [1, 1, 1]
    assert sum(r.get("matched", 0) for r in res) == 3
    assert _alert_rows(app, car["id"]) == 3 and _notif_count(app) == 3
    assert w


# ---------------------------------------------------------------------------
# 9. Beat registration (bounded, expiring, short tasks)
# ---------------------------------------------------------------------------


def test_beat_entry_is_registered_expiring_and_tick_is_bounded():
    from kk.tasks.celery_app import celery_app

    celery_app.loader.import_default_modules()
    entry = celery_app.conf.beat_schedule["reconcile-saved-search-alerts"]
    assert entry["task"] == "kk.reconcile_saved_search_alerts"
    assert entry["task"] in celery_app.tasks
    assert entry["schedule"] == 300.0
    assert 0 < entry["options"]["expires"] < entry["schedule"]
    task = celery_app.tasks[entry["task"]]
    assert task.soft_time_limit and task.time_limit  # the sweep itself is short and bounded


def test_sweep_task_enqueues_the_alert_task_with_bounded_publish_options(
    app, client, broker, monkeypatch
):
    """The beat task publishes the per-job task like retention_dispatch does
    (no result subscription, no inline publish retry) plus ``expires``."""
    import kk.tasks.alert_tasks as at

    with app.app_context():
        assert at.reconcile_saved_search_alerts.run() == {"mode": "off"}  # flag off: no-op
    _set_flag(monkeypatch, "on")
    uid, _ = _user(app)
    car = _car(app, uid)
    assert _patch(client, _admin_token(app, client), car, {"status": "active"}).status_code == 200
    broker.calls.clear()
    created = _job(app, car["id"])["created_at"]
    from kk import saved_search_alert_jobs as jobs

    with app.app_context():
        out = jobs.reconcile(created + timedelta(minutes=4), enqueue=at._enqueue_alert_job)
    assert out["redriven"] == 1
    assert broker.calls == [
        ((car["id"],), {"ignore_result": True, "retry": False, "expires": 600})
    ]


def test_off_mode_task_is_registered_under_its_historic_name():
    import kk.tasks.alert_tasks as at

    assert at.notify_saved_searches_for_car.name == "kk.tasks.alert_tasks.notify_saved_searches_for_car"
