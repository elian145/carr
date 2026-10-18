"""Automated listing moderation: engine, revisions, admin API, alerts, sweep.

Pins the contract:

* default mode is SHADOW: decisions are recorded, nothing is ever published;
* AUTO_APPROVE only when every mandatory check passes AND the seller is
  proven AND no uncertain signal remains; never after an outage / timeout;
* jobs are idempotent (duplicate / re-delivered / resumed), results for
  content the seller has since changed are discarded, and a human acting first
  always wins;
* edits of Active listings: old version stays visible, only a SUBMITTED edit is
  eligible, publication is the existing atomic ``publish_revision``;
* kill switch, live gate, permissions, alerts without PII, old-app
  compatibility, broker / provider outages.
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
_CDN = "https://cdn.example.com/car_photos"


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_auto_moderation_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "automod.db")
    os.environ["UPLOAD_FOLDER"] = os.path.join(tmp.name, "uploads")
    os.environ["R2_PUBLIC_URL"] = "https://cdn.example.com"
    os.environ["R2_ACCOUNT_ID"] = "test-account"
    os.environ["R2_BUCKET_NAME"] = "test-bucket"
    os.environ["R2_ACCESS_KEY_ID"] = "test-key"
    os.environ["R2_SECRET_ACCESS_KEY"] = "test-secret"

    from kk.app_factory import create_app

    app, _socketio, *_ = create_app()
    for key in ("R2_PUBLIC_URL", "R2_ACCOUNT_ID", "R2_BUCKET_NAME", "R2_ACCESS_KEY_ID", "R2_SECRET_ACCESS_KEY"):
        app.config[key] = os.environ[key]

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
def clean(app, monkeypatch):
    """Fresh moderation state + environment for every test; no real broker,
    network or mail is ever touched."""
    from kk.auto_moderation import ai, config
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
    ai.STUB_RESPONSE = None
    # Never enqueue to a broker from these tests unless a test says so.
    enqueued: list = []
    import kk.tasks.moderation_tasks as mt

    monkeypatch.setattr(
        mt.moderate_listing_task, "apply_async",
        lambda *a, **k: enqueued.append(("job", k)),
    )
    monkeypatch.setattr(
        mt.send_moderation_alert_task, "apply_async",
        lambda *a, **k: enqueued.append(("alert", k)),
    )
    with app.app_context():
        ListingModerationEvent.query.delete()
        ListingModerationRun.query.delete()
        AppSetting.query.filter_by(key=config.SETTINGS_KEY).delete()
        db.session.commit()
    yield enqueued
    ai.STUB_RESPONSE = None


# ---------------------------------------------------------------------------
# Builders
# ---------------------------------------------------------------------------


def _auth(token):
    return {"Authorization": f"Bearer {token}"}


def _user(app, *, admin=False, role=None, verified=True, active=True, dealer=False):
    from kk.models import User, db
    from kk.tests.admin_auth_helpers import attach_admin_account

    username = f"am_{uuid.uuid4().hex[:10]}"
    with app.app_context():
        u = User(
            username=username,
            phone_number=f"075{uuid.uuid4().int % 10**8:08d}",
            first_name="Auto",
            last_name="Mod",
            is_active=active,
            is_verified=True,
            phone_verified=verified,
            is_admin=admin,
            admin_role=role,
            dealer_status="approved" if dealer else "none",
            public_id=f"am-{uuid.uuid4().hex[:12]}",
        )
        u.set_password(_PASSWORD)
        db.session.add(u)
        db.session.commit()
        if admin:
            attach_admin_account(db, u, password=_PASSWORD, username=username)
        return u.id, username


def _login(client, username):
    from kk.tests.admin_auth_helpers import login_preferring_admin_scope

    return login_preferring_admin_scope(client, username, _PASSWORD)


def _admin_token(app, client, role=None):
    _uid, username = _user(app, admin=True, role=role)
    return _login(client, username)


def _car(
    app,
    uid,
    *,
    status="pending",
    photos=3,
    media="ready",
    description="Clean car, regularly serviced, no accidents.",
    vin=None,
    price=15000,
    active=True,
    **kw,
):
    """A listing with `photos` attached photos (first = declared cover) and its
    media manifest. media: ready | processing | failed."""
    from kk.models import Car, CarImage, CarMediaItem, db
    from kk.time_utils import utcnow

    fields = dict(
        title="Toyota Camry 2021",
        brand="toyota",
        model="camry",
        trim="base",
        year=2021,
        mileage=45000,
        engine_type="gasoline",
        fuel_type="gasoline",
        transmission="automatic",
        drive_type="fwd",
        condition="used",
        body_type="sedan",
        currency="USD",
        location="Erbil",
    )
    fields.update(kw)
    with app.app_context():
        car = Car(
            seller_id=uid,
            public_id=f"car-{uuid.uuid4().hex[:12]}",
            price=price,
            description=description,
            vin=vin,
            is_active=active,
            status=status,
            media_status=media,
            **fields,
        )
        db.session.add(car)
        db.session.flush()
        ids = []
        for i in range(photos):
            cid = f"m{i}-{uuid.uuid4().hex[:6]}"
            is_last = i == photos - 1
            item_status = "attached"
            if media == "processing" and is_last:
                item_status = "processing"
            if media == "failed" and is_last:
                item_status = "failed"
            db.session.add(
                CarMediaItem(
                    car_id=car.id, kind="image", client_media_id=cid, status=item_status,
                    is_cover=(i == 0), sort_order=i, phase_a_completed_at=utcnow(),
                )
            )
            if item_status == "attached":
                img = CarImage(
                    car_id=car.id, image_url=f"{_CDN}/{car.id}_{i}.jpg", is_primary=(i == 0),
                    order=i, kind="listing", source_media_id=cid, image_width=1600, image_height=1200,
                )
                db.session.add(img)
                db.session.flush()
                ids.append(img.id)
        db.session.commit()
        return {"car_id": car.id, "public_id": car.public_id, "uid": uid, "image_ids": ids}


def _trusted_seller(app, **kw):
    """Seller with one listing a human already approved (active)."""
    uid, username = _user(app, **kw)
    # deliberately a DIFFERENT vehicle so later test listings are not duplicates of it
    _car(app, uid, status="active", media="ready", price=7777, brand="honda", model="civic", year=2015,
         mileage=150000, title="Honda Civic 2015", description="Sold earlier; unrelated older listing text.")
    return uid, username


def _live(monkeypatch, app, **extra):
    from kk.auto_moderation import config

    monkeypatch.setenv("AUTO_MODERATION_ALLOW_LIVE", "1")
    with app.app_context():
        config.save_settings({"mode": "live", **extra})


def _settings(app, **patch):
    from kk.auto_moderation import config

    with app.app_context():
        return config.save_settings(config.validate_patch(patch))


def _moderate(app, stype, sid, **kw):
    from kk.auto_moderation.engine import moderate

    with app.app_context():
        return moderate(stype, sid, **kw)


def _runs(app, car_id=None):
    from kk.models import ListingModerationRun

    with app.app_context():
        q = ListingModerationRun.query
        if car_id is not None:
            q = q.filter_by(car_id=car_id)
        return [
            dict(
                id=r.id, public_id=r.public_id, decision=r.decision, outcome=r.outcome, mode=r.mode,
                status=r.status, applied=r.applied_at is not None, codes=[x["code"] for x in (r.reasons or [])],
                attempts=r.attempts, admin_outcome=r.admin_outcome, token=r.content_token,
                next_retry_at=r.next_retry_at,
            )
            for r in q.order_by(ListingModerationRun.id).all()
        ]


def _events(app, car_id):
    from kk.models import ListingModerationEvent

    with app.app_context():
        return [
            e.event_type
            for e in ListingModerationEvent.query.filter_by(car_id=car_id).order_by(ListingModerationEvent.id)
        ]


def _car_state(app, car_id):
    from kk.models import Car

    with app.app_context():
        c = Car.query.get(car_id)
        return dict(status=c.status, is_active=c.is_active, description=c.description, brand=c.brand,
                    price=float(c.price))


def _notifications(app, uid):
    from kk.models import Notification

    with app.app_context():
        return Notification.query.filter_by(user_id=uid, notification_type="listing_status").count()


def _revision(app, car_id, *, status="pending", media=None, **changes):
    """A hidden working copy with `changes`, in the given review state."""
    from kk import listing_revisions as lr
    from kk.models import Car, db

    with app.app_context():
        car = Car.query.get(car_id)
        rev = lr.ensure_revision(car)
        shadow = lr.get_working_copy(rev)
        for k, v in changes.items():
            setattr(shadow, k, v)
        if status == "pending":
            lr.submit_revision(rev)
        else:
            rev.status = status
        db.session.commit()
        return rev.id, shadow.id, rev.public_id


def _published_car(app, uid, **kw):
    return _car(app, uid, status="active", media="ready", **kw)


# ---------------------------------------------------------------------------
# Shadow mode (default)
# ---------------------------------------------------------------------------


def test_default_mode_is_shadow_and_never_publishes(app):
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)
    r = _moderate(app, "listing", c["car_id"])
    assert r["decision"] == "AUTO_APPROVE", _runs(app, c["car_id"])[0]["codes"]
    assert r["outcome"] == "shadow_would_approve"
    st = _car_state(app, c["car_id"])
    assert st["status"] == "pending"  # NOT published
    assert _notifications(app, uid) == 0
    runs = _runs(app, c["car_id"])
    assert len(runs) == 1 and runs[0]["mode"] == "shadow" and not runs[0]["applied"]
    assert _events(app, c["car_id"]) == ["claimed", "decision"]


def test_shadow_decisions_are_recorded_for_flagged_listings_too(app):
    uid, _ = _trusted_seller(app)
    c = _car(app, uid, description="western union only, guaranteed profit")
    r = _moderate(app, "listing", c["car_id"])
    assert r["decision"] == "NEEDS_REVIEW" and r["outcome"] == "queued_for_review"
    assert "scam_language" in _runs(app, c["car_id"])[0]["codes"]
    assert _car_state(app, c["car_id"])["status"] == "pending"


def _openai_luna(monkeypatch, responder):
    """Real OpenAI adapter configured for gpt-6-luna / effort none, with the
    network replaced by ``responder(request_body)`` (value or exception)."""
    from kk.auto_moderation import ai

    monkeypatch.setenv("AUTO_MODERATION_AI_PROVIDER", "openai")
    monkeypatch.setenv("AUTO_MODERATION_OPENAI_API_KEY", "sk-DUMMY-not-a-real-key")
    monkeypatch.setenv("AUTO_MODERATION_AI_MODEL", "gpt-6-luna")
    monkeypatch.setenv("AUTO_MODERATION_AI_REASONING_EFFORT", "none")
    sent: list[dict] = []

    class _Resp:
        def __init__(self, status, body):
            self.status_code, self._body = status, body

        def json(self):
            return self._body

    def fake_post(url, headers=None, json=None, timeout=None, **kw):
        sent.append(json)
        out = responder(json)
        if isinstance(out, BaseException):
            raise out
        return _Resp(*out)

    monkeypatch.setattr(ai.requests, "post", fake_post)
    return sent


def _luna_ok(body):
    import json as _json

    n = sum(1 for p in body["messages"][1]["content"] if p["type"] == "image_url")
    verdict = {
        "text": {"ok": True, "flags": []},
        "images": [{"index": i, "is_car_photo": True, "flags": []} for i in range(n)],
        "confidence": 0.95,
    }
    return 200, {"choices": [{"finish_reason": "stop", "message": {"content": _json.dumps(verdict)}}]}


def test_shadow_mode_with_gpt_6_luna_records_would_approve_but_publishes_nothing(app, monkeypatch):
    sent = _openai_luna(monkeypatch, _luna_ok)
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)
    r = _moderate(app, "listing", c["car_id"])
    assert r["decision"] == "AUTO_APPROVE" and r["outcome"] == "shadow_would_approve"
    assert sent and all(b["model"] == "gpt-6-luna" and b["reasoning_effort"] == "none" for b in sent)
    assert _car_state(app, c["car_id"])["status"] == "pending"  # NOT published
    assert _notifications(app, uid) == 0
    runs = _runs(app, c["car_id"])
    assert len(runs) == 1 and runs[0]["mode"] == "shadow" and not runs[0]["applied"]


def test_db_live_without_environment_allowance_stays_shadow_with_openai(app, monkeypatch):
    from kk.auto_moderation import config

    _openai_luna(monkeypatch, _luna_ok)
    with app.app_context():
        config.save_settings({"mode": "live"})  # the environment does NOT allow live
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)
    r = _moderate(app, "listing", c["car_id"])
    assert r["outcome"] == "shadow_would_approve"
    assert _car_state(app, c["car_id"])["status"] == "pending"
    assert _runs(app, c["car_id"])[0]["mode"] == "shadow"


@pytest.mark.parametrize(
    "responder",
    [
        lambda b: (200, {"choices": [{"finish_reason": "length", "message": {"content": ""}}]}),  # reasoning ate the cap
        lambda b: (200, {"choices": [{"finish_reason": "length", "message": {"content": '{"text": {"ok": tr'}}]}),
        lambda b: (200, {"choices": [{"finish_reason": "stop", "message": {"content": "not json"}}]}),
        lambda b: (200, {"choices": [{"finish_reason": "stop", "message": {"content": None}}]}),
        lambda b: (400, {}),
        lambda b: (429, {}),
        lambda b: (500, {}),
        lambda b: __import__("requests").Timeout(),
        lambda b: __import__("requests").ConnectionError("down"),
    ],
    ids=["empty-length", "truncated-json", "prose", "null-content", "http400", "http429", "http500", "timeout",
         "connection"],
)
def test_shadow_mode_with_gpt_6_luna_failures_never_approve_or_publish(app, monkeypatch, responder):
    _openai_luna(monkeypatch, responder)
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)
    r = _moderate(app, "listing", c["car_id"])
    assert r["decision"] in ("HOLD", "NEEDS_REVIEW")
    assert r["outcome"] != "shadow_would_approve"
    assert _car_state(app, c["car_id"])["status"] == "pending"
    assert _notifications(app, uid) == 0
    runs = _runs(app, c["car_id"])
    assert len(runs) == 1 and runs[0]["mode"] == "shadow" and not runs[0]["applied"]
    assert runs[0]["decision"] in ("HOLD", "NEEDS_REVIEW")


def test_mode_off_does_nothing(app):
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)
    _settings(app, mode="off")
    assert _moderate(app, "listing", c["car_id"])["outcome"] == "skipped_off"
    assert _runs(app) == []


def test_env_disabled_does_nothing(app, monkeypatch):
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)
    monkeypatch.setenv("AUTO_MODERATION_DISABLED", "1")
    assert _moderate(app, "listing", c["car_id"])["outcome"] == "skipped_off"


# ---------------------------------------------------------------------------
# Live mode: new listings
# ---------------------------------------------------------------------------


def test_live_auto_approves_clearly_legitimate_listing(app, monkeypatch):
    _live(monkeypatch, app)
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)
    r = _moderate(app, "listing", c["car_id"])
    assert r["outcome"] == "published"
    st = _car_state(app, c["car_id"])
    assert st["status"] == "active" and st["is_active"] is True
    assert _notifications(app, uid) == 1  # same seller notification as manual approval
    run = _runs(app, c["car_id"])[0]
    assert run["decision"] == "AUTO_APPROVE" and run["applied"] and run["outcome"] == "published"
    assert _events(app, c["car_id"]) == ["claimed", "decision", "published"]


def test_live_without_environment_allowance_stays_shadow(app, monkeypatch):
    from kk.auto_moderation import config

    with app.app_context():
        config.save_settings({"mode": "live"})  # DB says live, env does not allow it
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)
    r = _moderate(app, "listing", c["car_id"])
    assert r["outcome"] == "shadow_would_approve"
    assert _car_state(app, c["car_id"])["status"] == "pending"
    assert _runs(app, c["car_id"])[0]["mode"] == "shadow"


def test_kill_switch_blocks_approval_immediately(app, monkeypatch):
    from kk.auto_moderation import config

    _live(monkeypatch, app)
    with app.app_context():
        config.set_kill_switch(True, actor="ops", reason="incident")
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)
    r = _moderate(app, "listing", c["car_id"])
    assert r["outcome"] == "shadow_would_approve"
    assert _car_state(app, c["car_id"])["status"] == "pending"


def test_kill_switch_engaged_after_decision_blocks_apply(app, monkeypatch):
    """Decision recorded (pending_apply), kill switch pulled before the apply
    step: the apply re-reads it under the subject lock and refuses."""
    from kk.auto_moderation import config, engine

    _live(monkeypatch, app)
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)
    real_apply = engine._apply
    monkeypatch.setattr(engine, "_apply", lambda *a, **k: {"outcome": "deferred"})
    assert _moderate(app, "listing", c["car_id"])["outcome"] == "deferred"
    assert _runs(app, c["car_id"])[0]["outcome"] == "pending_apply"
    with app.app_context():
        config.set_kill_switch(True, actor="ops", reason="incident")
    monkeypatch.setattr(engine, "_apply", real_apply)
    r = _moderate(app, "listing", c["car_id"])  # redelivered job
    # kill switch -> effective mode is shadow -> a fresh shadow run, never a publish
    assert _car_state(app, c["car_id"])["status"] == "pending"
    assert r["outcome"] in ("shadow_would_approve", "blocked_killswitch")
    with app.app_context():
        r2 = real_apply(_runs(app, c["car_id"])[0]["id"], "listing", c["car_id"])
    assert r2["outcome"] == "blocked_killswitch"
    assert _car_state(app, c["car_id"])["status"] == "pending"


def test_unproven_seller_is_never_auto_approved(app, monkeypatch):
    _live(monkeypatch, app)
    uid, _ = _user(app)  # no approved listing yet
    c = _car(app, uid)
    r = _moderate(app, "listing", c["car_id"])
    assert r["decision"] == "NEEDS_REVIEW"
    assert "seller_unproven" in _runs(app, c["car_id"])[0]["codes"]
    assert _car_state(app, c["car_id"])["status"] == "pending"


def test_approved_dealer_can_be_auto_approved_without_history(app, monkeypatch):
    _live(monkeypatch, app)
    uid, _ = _user(app, dealer=True)
    c = _car(app, uid)
    assert _moderate(app, "listing", c["car_id"])["outcome"] == "published"


def test_automation_approvals_do_not_build_trust(app, monkeypatch):
    """A seller whose only active listing was auto-approved by automation is
    still 'unproven' for the next listing."""
    _live(monkeypatch, app)
    uid, _ = _user(app, dealer=True)
    first = _car(app, uid)
    assert _moderate(app, "listing", first["car_id"])["outcome"] == "published"
    with app.app_context():
        from kk.models import User, db

        User.query.get(uid).dealer_status = "none"
        db.session.commit()
    second = _car(app, uid)
    r = _moderate(app, "listing", second["car_id"])
    assert r["decision"] == "NEEDS_REVIEW"
    assert "seller_unproven" in _runs(app, second["car_id"])[-1]["codes"]


@pytest.mark.parametrize(
    "mutate,code",
    [
        (dict(verified=False), "seller_not_verified"),
        (dict(active=False), "seller_inactive"),
    ],
)
def test_account_restrictions_are_never_bypassed(app, monkeypatch, mutate, code):
    _live(monkeypatch, app)
    uid, _ = _trusted_seller(app, **mutate)
    c = _car(app, uid)
    r = _moderate(app, "listing", c["car_id"])
    assert r["decision"] == "NEEDS_REVIEW"
    assert code in _runs(app, c["car_id"])[0]["codes"]
    assert _car_state(app, c["car_id"])["status"] == "pending"


def test_open_reports_and_abuse_history_block_auto_approval(app, monkeypatch):
    from kk.models import ListingReport, db

    _live(monkeypatch, app)
    uid, _ = _trusted_seller(app)
    reporter, _ = _user(app)
    other = _car(app, uid, status="active")
    with app.app_context():
        db.session.add(ListingReport(reporter_id=reporter, car_id=other["car_id"], reason="scam", status="pending"))
        db.session.commit()
    c = _car(app, uid)
    assert _moderate(app, "listing", c["car_id"])["decision"] == "NEEDS_REVIEW"
    assert "seller_open_reports" in _runs(app, c["car_id"])[0]["codes"]


def test_payment_requirement_cannot_be_bypassed(app, monkeypatch):
    _live(monkeypatch, app, listing_payment_required=True)
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)
    assert _moderate(app, "listing", c["car_id"])["decision"] == "NEEDS_REVIEW"
    assert "payment_unverifiable" in _runs(app, c["car_id"])[0]["codes"]
    assert _car_state(app, c["car_id"])["status"] == "pending"


def test_duplicate_listing_and_vin_reuse_need_review(app, monkeypatch):
    _live(monkeypatch, app)
    uid, _ = _trusted_seller(app)
    first = _car(app, uid)
    assert _moderate(app, "listing", first["car_id"])["outcome"] == "published"
    dup = _car(app, uid)  # identical details from the same seller
    assert _moderate(app, "listing", dup["car_id"])["decision"] == "NEEDS_REVIEW"
    assert "duplicate_listing" in _runs(app, dup["car_id"])[0]["codes"]

    vin = "1HGCM82633A004352"
    a, _ = _trusted_seller(app)
    b, _ = _trusted_seller(app)
    _car(app, a, status="active", vin=vin, mileage=1)
    c2 = _car(app, b, vin=vin, price=18000)
    assert _moderate(app, "listing", c2["car_id"])["decision"] == "NEEDS_REVIEW"
    assert "vin_other_seller" in _runs(app, c2["car_id"])[0]["codes"]


# ---------------------------------------------------------------------------
# AI is advisory; outages never approve
# ---------------------------------------------------------------------------


def test_ai_flagged_goes_to_review_not_rejection(app, monkeypatch):
    from kk.auto_moderation import ai

    _live(monkeypatch, app)
    ai.STUB_RESPONSE = {
        "text": {"ok": True, "flags": []},
        "images": [{"index": 0, "is_car_photo": False, "flags": []}] + [
            {"index": i, "is_car_photo": True, "flags": []} for i in (1, 2)
        ],
        "confidence": 0.9,
    }
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)
    r = _moderate(app, "listing", c["car_id"])
    assert r["decision"] == "NEEDS_REVIEW"
    run = _runs(app, c["car_id"])[0]
    assert "ai_flagged" in run["codes"]
    assert _car_state(app, c["car_id"])["status"] == "pending"  # not rejected, not approved


def test_ai_uncertain_goes_to_review(app, monkeypatch):
    from kk.auto_moderation import ai

    _live(monkeypatch, app)
    ai.STUB_RESPONSE = {"_status": "uncertain", "error": "invalid_response"}
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)
    assert _moderate(app, "listing", c["car_id"])["decision"] == "NEEDS_REVIEW"


def test_ai_outage_holds_and_never_approves_then_recovers(app, monkeypatch, clean):
    from kk.auto_moderation import ai

    _live(monkeypatch, app)
    ai.STUB_RESPONSE = ConnectionError("provider down")
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)
    r = _moderate(app, "listing", c["car_id"])
    assert r["decision"] == "HOLD" and r["outcome"] == "held"
    assert r["retry_in"] == 60  # scheduled retry, not an approval
    assert _car_state(app, c["car_id"])["status"] == "pending"
    run = _runs(app, c["car_id"])[0]
    assert "ai_unavailable" in run["codes"] and run["next_retry_at"] is not None
    assert _notifications(app, uid) == 0

    # an immediate duplicate job respects the back-off: no second provider call
    assert _moderate(app, "listing", c["car_id"])["outcome"] == "backoff"

    # provider recovers; the retry (after the back-off) can now approve
    ai.STUB_RESPONSE = None
    from kk.models import ListingModerationRun, db
    from kk.time_utils import utcnow

    with app.app_context():
        r0 = ListingModerationRun.query.first()
        r0.next_retry_at = utcnow() - timedelta(seconds=1)
        db.session.commit()
    r = _moderate(app, "listing", c["car_id"])
    assert r["outcome"] == "published"
    runs = _runs(app, c["car_id"])
    assert len(runs) == 1 and runs[0]["attempts"] == 2


def test_ai_timeout_text_is_never_an_approval(app, monkeypatch):
    from kk.auto_moderation import ai

    _live(monkeypatch, app)
    ai.STUB_RESPONSE = {"_status": "unavailable", "error": "timeout"}
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)
    r = _moderate(app, "listing", c["car_id"])
    assert r["decision"] == "HOLD"
    assert _car_state(app, c["car_id"])["status"] == "pending"


def test_retries_exhausted_stays_held_without_schedule(app, monkeypatch):
    from kk.auto_moderation import ai

    _live(monkeypatch, app)
    _settings(app, retry={"max_attempts": 1})
    ai.STUB_RESPONSE = {"_status": "unavailable", "error": "timeout"}
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)
    r = _moderate(app, "listing", c["car_id"])
    assert r["decision"] == "HOLD" and not r.get("retry_in")
    assert "retries_exhausted" in _events(app, c["car_id"])


def test_engine_exception_records_hold_never_approves(app, monkeypatch):
    from kk.auto_moderation import engine

    _live(monkeypatch, app)
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)

    def boom(*a, **k):
        raise RuntimeError("db exploded")

    monkeypatch.setattr(engine, "evaluate", boom)
    r = _moderate(app, "listing", c["car_id"])
    assert r["outcome"] == "error" and r["retry_in"]
    run = _runs(app, c["car_id"])[0]
    assert run["decision"] == "HOLD" and run["status"] == "error" and not run["applied"]
    assert "engine_error" in run["codes"]
    assert _car_state(app, c["car_id"])["status"] == "pending"


def test_ai_required_by_default_and_not_configured_means_review(app, monkeypatch):
    _live(monkeypatch, app)
    monkeypatch.setenv("AUTO_MODERATION_AI_PROVIDER", "none")
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)
    assert _moderate(app, "listing", c["car_id"])["decision"] == "NEEDS_REVIEW"
    assert "ai_not_configured" in _runs(app, c["car_id"])[0]["codes"]


def test_rules_only_approval_needs_server_operator_opt_in(app, client, monkeypatch):
    """Disabling the AI requirement is not a dashboard decision: the stored
    setting alone changes nothing, and the API refuses to store it."""
    from kk.auto_moderation import config

    sup = _admin_token(app, client, "super_admin")
    r = client.put(f"{BASE}/settings", json={"require_ai_for_auto_approve": False}, headers=_auth(sup))
    assert r.status_code == 400 and "cannot be disabled" in r.get_json()["message"]
    _live(monkeypatch, app, require_ai_for_auto_approve=False)  # forced into the store
    monkeypatch.setenv("AUTO_MODERATION_AI_PROVIDER", "none")
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)
    r = _moderate(app, "listing", c["car_id"])
    assert r["decision"] == "NEEDS_REVIEW"
    assert "ai_not_configured" in _runs(app, c["car_id"])[0]["codes"]
    assert _car_state(app, c["car_id"])["status"] == "pending"
    # only with the operator opt-in is rules-only possible
    monkeypatch.setenv("AUTO_MODERATION_ALLOW_RULES_ONLY", "1")
    assert config.validate_patch({"require_ai_for_auto_approve": False})
    c2 = _car(app, uid, price=15999, brand="kia", model="rio", title="Kia Rio 2021",
              description="Another vehicle with its own words, nothing in common.")
    assert _moderate(app, "listing", c2["car_id"])["outcome"] == "published"


def test_ai_is_skipped_when_rules_already_flag(app, monkeypatch):
    from kk.auto_moderation import ai

    calls = []
    ai.STUB_RESPONSE = lambda *a: calls.append(1) or {"text": {"ok": True}, "images": [], "confidence": 1}
    uid, _ = _user(app)  # unproven -> rules already flag
    c = _car(app, uid)
    _moderate(app, "listing", c["car_id"])
    assert calls == []
    _settings(app, ai={"only_if_candidate": False})
    ai.STUB_RESPONSE = lambda t, d, u: calls.append(1) or {
        "text": {"ok": True, "flags": []},
        "images": [{"index": i, "is_car_photo": True, "flags": []} for i in range(len(u))],
        "confidence": 1,
    }
    c2 = _car(app, uid)
    _moderate(app, "listing", c2["car_id"])
    assert calls == [1]


# ---------------------------------------------------------------------------
# Media readiness / cover
# ---------------------------------------------------------------------------


def test_unfinished_media_is_held_not_approved(app, monkeypatch):
    _live(monkeypatch, app)
    uid, _ = _trusted_seller(app)
    c = _car(app, uid, media="processing")
    r = _moderate(app, "listing", c["car_id"])
    assert r["decision"] == "HOLD" and "media_processing" in _runs(app, c["car_id"])[0]["codes"]
    assert _car_state(app, c["car_id"])["status"] == "pending"


def test_failed_media_is_held_and_never_published(app, monkeypatch):
    _live(monkeypatch, app)
    uid, _ = _trusted_seller(app)
    c = _car(app, uid, media="failed")
    r = _moderate(app, "listing", c["car_id"])
    assert r["decision"] == "HOLD" and "media_failed" in _runs(app, c["car_id"])[0]["codes"]
    assert _car_state(app, c["car_id"])["status"] == "pending"
    assert not r.get("retry_in")  # permanent for this content; a human decides


def test_media_finishing_changes_token_and_gets_evaluated(app, monkeypatch):
    """Processing -> HOLD; once the last photo attaches the content token
    differs, so the listing is evaluated again and approved."""
    from kk.media_readiness import transition_media_item_terminal
    from kk.models import CarImage, CarMediaItem, db

    _live(monkeypatch, app)
    uid, _ = _trusted_seller(app)
    c = _car(app, uid, media="processing")
    assert _moderate(app, "listing", c["car_id"])["decision"] == "HOLD"
    with app.app_context():
        item = CarMediaItem.query.filter_by(car_id=c["car_id"], status="processing").one()
        cid = item.client_media_id

        def attach(car):
            db.session.add(
                CarImage(car_id=car.id, image_url=f"{_CDN}/late.jpg", is_primary=False, order=9,
                         kind="listing", source_media_id=cid, image_width=1600, image_height=1200)
            )

        assert transition_media_item_terminal(car_id=c["car_id"], client_media_id=cid,
                                              to_status="attached", attach_fn=attach) == "applied"
    r = _moderate(app, "listing", c["car_id"])
    assert r["outcome"] == "published"
    assert len(_runs(app, c["car_id"])) == 2  # one HOLD row, one decision row


def test_media_terminal_transition_requests_moderation(app, monkeypatch, clean):
    from kk.media_readiness import transition_media_item_terminal
    from kk.models import CarImage, CarMediaItem, db

    uid, _ = _trusted_seller(app)
    c = _car(app, uid, media="processing")
    with app.app_context():
        item = CarMediaItem.query.filter_by(car_id=c["car_id"], status="processing").one()
        cid = item.client_media_id

        def attach(car):
            db.session.add(CarImage(car_id=car.id, image_url=f"{_CDN}/x.jpg", is_primary=False, order=9,
                                    kind="listing", source_media_id=cid))

        transition_media_item_terminal(car_id=c["car_id"], client_media_id=cid, to_status="attached",
                                       attach_fn=attach)
    assert any(tuple(k["args"][:2]) == ("listing", c["car_id"]) for kind, k in clean if kind == "job")


def test_wrong_cover_is_never_published(app, monkeypatch):
    from kk.models import CarImage, db

    _live(monkeypatch, app)
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)
    with app.app_context():  # declared cover is image 0; make image 1 the stored cover
        imgs = CarImage.query.filter_by(car_id=c["car_id"]).order_by(CarImage.order).all()
        imgs[0].is_primary, imgs[1].is_primary = False, True
        db.session.commit()
    r = _moderate(app, "listing", c["car_id"])
    assert r["decision"] == "NEEDS_REVIEW"
    assert "cover_mismatch" in _runs(app, c["car_id"])[0]["codes"]
    assert _car_state(app, c["car_id"])["status"] == "pending"


def test_attached_item_without_photo_row_is_never_published(app, monkeypatch):
    from kk.models import CarImage, db

    _live(monkeypatch, app)
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)
    with app.app_context():
        CarImage.query.filter_by(id=c["image_ids"][2]).delete()
        db.session.commit()
    assert _moderate(app, "listing", c["car_id"])["decision"] == "NEEDS_REVIEW"
    assert "media_missing" in _runs(app, c["car_id"])[0]["codes"]


# ---------------------------------------------------------------------------
# Idempotency / duplicate jobs / resume
# ---------------------------------------------------------------------------


def test_duplicate_jobs_decide_and_approve_once(app, monkeypatch):
    _live(monkeypatch, app)
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)
    first = _moderate(app, "listing", c["car_id"])
    assert first["outcome"] == "published"
    # the subject is no longer pending: a duplicate / re-delivered job is inert
    again = _moderate(app, "listing", c["car_id"])
    assert again["outcome"] == "ineligible"
    assert len(_runs(app, c["car_id"])) == 1
    assert _notifications(app, uid) == 1


def test_duplicate_job_for_same_decision_is_done_not_redecided(app):
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)
    assert _moderate(app, "listing", c["car_id"])["outcome"] == "shadow_would_approve"
    assert _moderate(app, "listing", c["car_id"])["outcome"] == "done"
    assert len(_runs(app, c["car_id"])) == 1


def test_fresh_claim_by_another_worker_is_busy_and_expired_claim_is_taken_over(app):
    from kk.auto_moderation.engine import _claim
    from kk.auto_moderation.config import load_settings
    from kk.auto_moderation.subjects import resolve_subject
    from kk.models import ListingModerationRun, db
    from kk.time_utils import utcnow

    uid, _ = _trusted_seller(app)
    c = _car(app, uid)
    with app.app_context():
        subj = resolve_subject("listing", c["car_id"])
        run, state = _claim(subj, "shadow", load_settings(), "event")
        assert state == "new" and run.attempts == 1
        run2, state2 = _claim(subj, "shadow", load_settings(), "event")
        assert state2 == "busy" and run2.id == run.id
        run.claimed_at = utcnow() - timedelta(hours=1)  # crashed worker
        db.session.commit()
        run3, state3 = _claim(subj, "shadow", load_settings(), "event")
        assert state3 == "retry" and run3.attempts == 2
        assert ListingModerationRun.query.count() == 1


def test_crash_between_decision_and_apply_resumes_and_applies_once(app, monkeypatch):
    from kk.auto_moderation import engine

    _live(monkeypatch, app)
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)
    real_apply = engine._apply
    monkeypatch.setattr(engine, "_apply", lambda *a, **k: (_ for _ in ()).throw(RuntimeError("worker died")))
    with pytest.raises(RuntimeError):
        _moderate(app, "listing", c["car_id"])
    assert _runs(app, c["car_id"])[0]["outcome"] == "pending_apply"
    assert _car_state(app, c["car_id"])["status"] == "pending"
    monkeypatch.setattr(engine, "_apply", real_apply)
    assert _moderate(app, "listing", c["car_id"])["outcome"] == "published"
    assert _notifications(app, uid) == 1
    assert len(_runs(app, c["car_id"])) == 1


def test_expired_decision_is_never_applied(app, monkeypatch):
    from kk.auto_moderation import engine
    from kk.models import ListingModerationRun, db
    from kk.time_utils import utcnow

    _live(monkeypatch, app)
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)
    real_apply = engine._apply
    monkeypatch.setattr(engine, "_apply", lambda *a, **k: {"outcome": "deferred"})
    _moderate(app, "listing", c["car_id"])
    monkeypatch.setattr(engine, "_apply", real_apply)
    with app.app_context():
        r = ListingModerationRun.query.first()
        r.decided_at = utcnow() - timedelta(hours=3)
        db.session.commit()
    out = _moderate(app, "listing", c["car_id"])
    assert out["outcome"] == "held"
    assert _car_state(app, c["car_id"])["status"] == "pending"


# ---------------------------------------------------------------------------
# Seller edits during moderation / stale results
# ---------------------------------------------------------------------------


def test_seller_edit_during_moderation_discards_stale_result(app, monkeypatch, clean):
    from kk.auto_moderation import ai
    from kk.models import Car, db

    _live(monkeypatch, app)
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)

    def edit_while_ai_runs(title, desc, urls):
        c_ = Car.query.get(c["car_id"])
        c_.description = "western union only, guaranteed profit"
        db.session.commit()
        return {
            "text": {"ok": True, "flags": []},
            "images": [{"index": i, "is_car_photo": True, "flags": []} for i in range(len(urls))],
            "confidence": 0.95,
        }

    ai.STUB_RESPONSE = edit_while_ai_runs
    r = _moderate(app, "listing", c["car_id"])
    assert r["outcome"] == "stale" and r["reenqueue"] is True
    assert _car_state(app, c["car_id"])["status"] == "pending"  # the stale approval was dropped
    runs = _runs(app, c["car_id"])
    assert runs[0]["status"] == "stale" and not runs[0]["applied"]

    # the new content is judged on its own merits
    ai.STUB_RESPONSE = None
    r = _moderate(app, "listing", c["car_id"])
    assert r["decision"] == "NEEDS_REVIEW"
    assert "scam_language" in _runs(app, c["car_id"])[-1]["codes"]


def test_seller_edit_between_decision_and_apply_is_stale(app, monkeypatch):
    from kk.auto_moderation import engine
    from kk.models import Car, db

    _live(monkeypatch, app)
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)
    real_apply = engine._apply
    monkeypatch.setattr(engine, "_apply", lambda *a, **k: {"outcome": "deferred"})
    _moderate(app, "listing", c["car_id"])
    monkeypatch.setattr(engine, "_apply", real_apply)
    with app.app_context():
        Car.query.get(c["car_id"]).price = 1
        db.session.commit()
    rid = _runs(app, c["car_id"])[0]["id"]
    with app.app_context():
        out = real_apply(rid, "listing", c["car_id"])
    assert out["outcome"] == "stale"
    assert _car_state(app, c["car_id"])["status"] == "pending"


def test_admin_approving_first_wins_and_automation_does_nothing(app, client, monkeypatch):
    from kk.auto_moderation import engine

    _live(monkeypatch, app)
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)
    real_apply = engine._apply
    monkeypatch.setattr(engine, "_apply", lambda *a, **k: {"outcome": "deferred"})
    _moderate(app, "listing", c["car_id"])
    monkeypatch.setattr(engine, "_apply", real_apply)

    tok = _admin_token(app, client)
    r = client.patch(f"/api/admin/cars/{c['public_id']}/status",
                     json={"is_active": True, "status": "active"}, headers=_auth(tok))
    assert r.status_code == 200
    assert _notifications(app, uid) == 1
    rid = _runs(app, c["car_id"])[0]["id"]
    with app.app_context():
        out = real_apply(rid, "listing", c["car_id"])
    assert out["outcome"] == "superseded"  # no second approval, no second notification
    assert _notifications(app, uid) == 1
    assert _car_state(app, c["car_id"])["status"] == "active"


def test_admin_hiding_first_is_not_overridden(app, client, monkeypatch):
    from kk.auto_moderation import engine

    _live(monkeypatch, app)
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)
    real_apply = engine._apply
    monkeypatch.setattr(engine, "_apply", lambda *a, **k: {"outcome": "deferred"})
    _moderate(app, "listing", c["car_id"])
    monkeypatch.setattr(engine, "_apply", real_apply)
    tok = _admin_token(app, client)
    assert client.patch(f"/api/admin/cars/{c['public_id']}/status",
                        json={"status": "hidden"}, headers=_auth(tok)).status_code == 200
    rid = _runs(app, c["car_id"])[0]["id"]
    with app.app_context():
        assert real_apply(rid, "listing", c["car_id"])["outcome"] == "superseded"
    assert _car_state(app, c["car_id"])["status"] == "hidden"


def test_deleted_listing_is_never_approved(app, monkeypatch):
    from kk.auto_moderation import engine
    from kk.models import Car, db

    _live(monkeypatch, app)
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)
    # already deleted by the seller (soft delete = is_active False, status unchanged)
    with app.app_context():
        Car.query.get(c["car_id"]).is_active = False
        db.session.commit()
    assert _moderate(app, "listing", c["car_id"])["outcome"] == "ineligible"
    assert _runs(app) == []

    # deleted between decision and apply
    c2 = _car(app, uid, price=16000)
    real_apply = engine._apply
    monkeypatch.setattr(engine, "_apply", lambda *a, **k: {"outcome": "deferred"})
    _moderate(app, "listing", c2["car_id"])
    monkeypatch.setattr(engine, "_apply", real_apply)
    with app.app_context():
        Car.query.get(c2["car_id"]).is_active = False
        db.session.commit()
        out = real_apply(_runs(app, c2["car_id"])[0]["id"], "listing", c2["car_id"])
    assert out["outcome"] == "superseded"
    assert _car_state(app, c2["car_id"])["status"] == "pending"


def test_state_changes_between_decision_and_apply_downgrade_instead_of_publish(app, monkeypatch):
    """Seller restricted / a report arrives after the decision: the apply step
    re-runs every deterministic rule and refuses."""
    from kk.auto_moderation import engine
    from kk.models import User, db

    _live(monkeypatch, app)
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)
    real_apply = engine._apply
    monkeypatch.setattr(engine, "_apply", lambda *a, **k: {"outcome": "deferred"})
    _moderate(app, "listing", c["car_id"])
    monkeypatch.setattr(engine, "_apply", real_apply)
    with app.app_context():
        User.query.get(uid).is_active = False
        db.session.commit()
        out = real_apply(_runs(app, c["car_id"])[0]["id"], "listing", c["car_id"])
    assert out["outcome"] == "downgraded"
    assert _car_state(app, c["car_id"])["status"] == "pending"
    assert _runs(app, c["car_id"])[0]["decision"] == "NEEDS_REVIEW"


def test_double_apply_is_a_noop(app, monkeypatch):
    from kk.auto_moderation import engine

    _live(monkeypatch, app)
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)
    assert _moderate(app, "listing", c["car_id"])["outcome"] == "published"
    rid = _runs(app, c["car_id"])[0]["id"]
    with app.app_context():
        again = engine._apply(rid, "listing", c["car_id"])
    assert again.get("outcome") in ("superseded", "published")
    assert _notifications(app, uid) == 1
    assert len([e for e in _events(app, c["car_id"]) if e == "published"]) == 1


# ---------------------------------------------------------------------------
# Pending revisions (edits of Active listings)
# ---------------------------------------------------------------------------


def test_revision_shadow_mode_keeps_old_version_and_publishes_nothing(app, client):
    uid, _ = _trusted_seller(app)
    c = _published_car(app, uid)
    rid, shadow_id, _pub = _revision(app, c["car_id"], description="Updated: new tyres fitted, service done.")
    r = _moderate(app, "revision", rid)
    assert r["decision"] == "AUTO_APPROVE" and r["outcome"] == "shadow_would_approve"
    assert _car_state(app, c["car_id"])["description"].startswith("Clean car")  # old version still live
    assert client.get(f"/api/cars/{c['public_id']}").get_json()["car"]["description"].startswith("Clean car")


def test_revision_live_publishes_atomically_and_clears_revision(app, monkeypatch):
    from kk.models import Car, CarRevision

    _live(monkeypatch, app)
    uid, _ = _trusted_seller(app)
    c = _published_car(app, uid)
    rid, shadow_id, _pub = _revision(app, c["car_id"], description="Updated: new tyres fitted, service done.")
    r = _moderate(app, "revision", rid)
    assert r["outcome"] == "published"
    assert _car_state(app, c["car_id"])["description"].startswith("Updated")
    with app.app_context():
        assert CarRevision.query.get(rid) is None and Car.query.get(shadow_id) is None
    assert _notifications(app, uid) == 1


def test_only_submitted_edits_are_eligible_drafts_never_approved(app, monkeypatch):
    _live(monkeypatch, app)
    uid, _ = _trusted_seller(app)
    for status in ("editing", "editing_legacy", "rejected"):
        c = _published_car(app, uid, price=15000 + len(status))
        rid, _s, _p = _revision(app, c["car_id"], status=status, description="Changed text for the listing here.")
        assert _moderate(app, "revision", rid)["outcome"] == "ineligible", status
        assert _car_state(app, c["car_id"])["description"].startswith("Clean car")
    assert _runs(app) == []


def test_revision_seller_edit_during_moderation_is_stale(app, monkeypatch):
    from kk.auto_moderation import ai
    from kk.models import Car, CarRevision, db

    _live(monkeypatch, app)
    uid, _ = _trusted_seller(app)
    c = _published_car(app, uid)
    rid, shadow_id, _p = _revision(app, c["car_id"], description="Updated: new tyres fitted, service done.")

    def edit(title, desc, urls):
        Car.query.get(shadow_id).description = "Now with guaranteed profit, western union"
        db.session.commit()
        return {"text": {"ok": True, "flags": []},
                "images": [{"index": i, "is_car_photo": True, "flags": []} for i in range(len(urls))],
                "confidence": 0.9}

    ai.STUB_RESPONSE = edit
    r = _moderate(app, "revision", rid)
    assert r["outcome"] == "stale"
    assert _car_state(app, c["car_id"])["description"].startswith("Clean car")
    with app.app_context():
        assert CarRevision.query.get(rid).status == "pending"  # preserved for review
    ai.STUB_RESPONSE = None
    assert _moderate(app, "revision", rid)["decision"] == "NEEDS_REVIEW"


def test_revision_stale_between_decision_and_apply(app, monkeypatch):
    from kk.auto_moderation import engine
    from kk.models import Car, db

    _live(monkeypatch, app)
    uid, _ = _trusted_seller(app)
    c = _published_car(app, uid)
    rid, shadow_id, _p = _revision(app, c["car_id"], description="Updated: new tyres fitted, service done.")
    real_apply = engine._apply
    monkeypatch.setattr(engine, "_apply", lambda *a, **k: {"outcome": "deferred"})
    _moderate(app, "revision", rid)
    monkeypatch.setattr(engine, "_apply", real_apply)
    with app.app_context():
        Car.query.get(shadow_id).description = "Something else entirely, edited later."
        db.session.commit()
        out = real_apply(_runs(app, c["car_id"])[0]["id"], "revision", rid)
    assert out["outcome"] == "stale"
    assert _car_state(app, c["car_id"])["description"].startswith("Clean car")


def test_revision_with_unfinished_or_failed_media_is_held_and_not_published(app, monkeypatch):
    from kk.models import CarMediaItem, Car, db

    _live(monkeypatch, app)
    uid, _ = _trusted_seller(app)
    for state in ("processing", "failed"):
        c = _published_car(app, uid, price=15100 if state == "failed" else 15200)
        rid, shadow_id, _p = _revision(app, c["car_id"], description="Updated: new photos and details here.")
        with app.app_context():
            db.session.add(CarMediaItem(car_id=shadow_id, kind="image", client_media_id=f"new-{state}",
                                        status=state, phase_a_completed_at=None))
            Car.query.get(shadow_id).media_status = state
            db.session.commit()
        r = _moderate(app, "revision", rid)
        assert r["decision"] == "HOLD", state
        assert _car_state(app, c["car_id"])["description"].startswith("Clean car")


def test_revision_identity_and_big_price_change_need_review(app, monkeypatch):
    _live(monkeypatch, app)
    uid, _ = _trusted_seller(app)
    c = _published_car(app, uid)
    rid, _s, _p = _revision(app, c["car_id"], brand="bmw", price=3000)
    r = _moderate(app, "revision", rid)
    assert r["decision"] == "NEEDS_REVIEW"
    codes = _runs(app, c["car_id"])[0]["codes"]
    assert "identity_changed" in codes and "large_price_change" in codes
    assert _car_state(app, c["car_id"])["brand"] == "toyota"


def test_revision_review_then_admin_reject_preserves_previous_version(app, client, monkeypatch):
    from kk.models import CarRevision

    uid, _ = _trusted_seller(app)
    c = _published_car(app, uid)
    rid, shadow_id, rev_public = _revision(app, c["car_id"], description="Updated: guaranteed profit western union")
    assert _moderate(app, "revision", rid)["decision"] == "NEEDS_REVIEW"
    tok = _admin_token(app, client)
    detail = client.get(f"/api/admin/listing-revisions/{rev_public}", headers=_auth(tok)).get_json()
    token = detail["revision"]["revision_token"]
    r = client.post(f"/api/admin/listing-revisions/{rev_public}/reject",
                    json={"revision_token": token, "reason": "Scam wording"}, headers=_auth(tok))
    assert r.status_code == 200
    assert _car_state(app, c["car_id"])["description"].startswith("Clean car")
    with app.app_context():
        assert CarRevision.query.get(rid).status == "rejected"
    assert _runs(app, c["car_id"])[0]["admin_outcome"] == "rejected"


def test_admin_approves_revision_first_then_automation_is_inert(app, client, monkeypatch):
    from kk.auto_moderation import engine

    _live(monkeypatch, app)
    uid, _ = _trusted_seller(app)
    c = _published_car(app, uid)
    rid, _s, rev_public = _revision(app, c["car_id"], description="Updated: new tyres fitted, service done.")
    real_apply = engine._apply
    monkeypatch.setattr(engine, "_apply", lambda *a, **k: {"outcome": "deferred"})
    _moderate(app, "revision", rid)
    monkeypatch.setattr(engine, "_apply", real_apply)
    tok = _admin_token(app, client)
    detail = client.get(f"/api/admin/listing-revisions/{rev_public}", headers=_auth(tok)).get_json()
    assert client.post(f"/api/admin/listing-revisions/{rev_public}/approve",
                       json={"revision_token": detail["revision"]["revision_token"]},
                       headers=_auth(tok)).status_code == 200
    with app.app_context():
        out = real_apply(_runs(app, c["car_id"])[0]["id"], "revision", rid)
    assert out["outcome"] == "superseded"
    assert _notifications(app, uid) == 1


# ---------------------------------------------------------------------------
# Admin outcomes / shadow comparison / live gate
# ---------------------------------------------------------------------------


def test_admin_decisions_are_recorded_next_to_shadow_decisions(app, client):
    uid, _ = _trusted_seller(app)
    ok = _car(app, uid, price=15001)
    bad = _car(app, uid, price=19002, brand="nissan", model="altima", title="Nissan Altima 2021",
               description="Different car, different words: one owner, all service records available.")
    _moderate(app, "listing", ok["car_id"])
    _moderate(app, "listing", bad["car_id"])
    tok = _admin_token(app, client)
    assert client.patch(f"/api/admin/cars/{ok['public_id']}/status",
                        json={"is_active": True, "status": "active"}, headers=_auth(tok)).status_code == 200
    assert client.patch(f"/api/admin/cars/{bad['public_id']}/status",
                        json={"status": "hidden"}, headers=_auth(tok)).status_code == 200
    assert _runs(app, ok["car_id"])[0]["admin_outcome"] == "approved"
    assert _runs(app, bad["car_id"])[0]["admin_outcome"] == "rejected"

    from kk.auto_moderation import config, stats

    with app.app_context():
        rep = stats.shadow_report(config.load_settings())
    assert rep["compared"] == 2 and rep["would_auto_approve"] == 2
    assert rep["unsafe_approvals"] == 1 and rep["unsafe_approve_rate"] == 0.5
    assert rep["gate"]["passed"] is False


def test_shadow_gate_requires_samples_and_threshold(app):
    from kk.auto_moderation import config, stats
    from kk.models import ListingModerationRun, db

    s = config.load_settings()
    s["gate"] = dict(s["gate"], min_samples=3, max_unsafe_approve_rate=0.5)
    with app.app_context():
        for i, outcome in enumerate(["approved", "approved", "approved", "rejected"]):
            db.session.add(ListingModerationRun(
                subject_key=f"listing:9{i}", subject_type="listing", content_token=f"t{i}", mode="shadow",
                status="completed", decision="AUTO_APPROVE", admin_outcome=outcome))
        db.session.commit()
        rep = stats.shadow_report(s)
    assert rep["gate"]["passed"] is True and rep["unsafe_approve_rate"] == 0.25
    s["gate"]["min_samples"] = 10
    with app.app_context():
        rep = stats.shadow_report(s)
    assert rep["gate"]["passed"] is False and "only 4" in rep["gate"]["problems"][0]


def test_post_approval_reversal_is_tracked_in_live_mode(app, client, monkeypatch):
    _live(monkeypatch, app)
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)
    assert _moderate(app, "listing", c["car_id"])["outcome"] == "published"
    tok = _admin_token(app, client)
    assert client.patch(f"/api/admin/cars/{c['public_id']}/status",
                        json={"status": "hidden"}, headers=_auth(tok)).status_code == 200
    assert _runs(app, c["car_id"])[0]["admin_outcome"] == "hidden"
    from kk.auto_moderation import stats

    with app.app_context():
        s = stats.summary(30)
    assert s["auto_approved"] == 1 and s["post_approval_reversals"] == 1
    assert s["post_approval_reversal_rate"] == 1.0


# ---------------------------------------------------------------------------
# Admin API: permissions, settings gate, kill switch, lists, overrides
# ---------------------------------------------------------------------------

BASE = "/api/admin/auto-moderation"


def test_permissions_per_role(app, client):
    sup = _admin_token(app, client, "super_admin")
    mod = _admin_token(app, client, "moderator")
    support = _admin_token(app, client, "support")
    marketing = _admin_token(app, client, "marketing")
    for tok, expected in ((sup, 200), (mod, 200), (support, 403), (marketing, 403)):
        assert client.get(f"{BASE}/settings", headers=_auth(tok)).status_code == expected
        assert client.get(f"{BASE}/runs", headers=_auth(tok)).status_code == expected
        assert client.get(f"{BASE}/stats", headers=_auth(tok)).status_code == expected
    assert client.put(f"{BASE}/settings", json={"min_photos": 2}, headers=_auth(mod)).status_code == 403
    assert client.put(f"{BASE}/settings", json={"min_photos": 2}, headers=_auth(sup)).status_code == 200
    # unauthenticated / ordinary user
    assert client.get(f"{BASE}/settings").status_code in (401, 422)
    _uid, uname = _user(app)
    utok = _login(client, uname)
    assert client.get(f"{BASE}/settings", headers=_auth(utok)).status_code == 403


def test_kill_switch_endpoint_engage_by_moderator_release_by_super_admin(app, client, monkeypatch):
    _live(monkeypatch, app)
    mod = _admin_token(app, client, "moderator")
    sup = _admin_token(app, client, "super_admin")
    r = client.post(f"{BASE}/kill-switch", json={"enabled": True, "reason": "bad batch"}, headers=_auth(mod))
    assert r.status_code == 200
    j = r.get_json()
    assert j["kill_switch_active"] is True and j["effective_mode"] == "shadow"
    assert j["settings"]["kill_switch_reason"] == "bad batch"
    # takes effect immediately for the engine
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)
    assert _moderate(app, "listing", c["car_id"])["outcome"] == "shadow_would_approve"
    assert client.post(f"{BASE}/kill-switch", json={"enabled": False}, headers=_auth(mod)).status_code == 403
    assert client.post(f"{BASE}/kill-switch", json={"enabled": "no"}, headers=_auth(sup)).status_code == 400
    r = client.post(f"{BASE}/kill-switch", json={"enabled": False}, headers=_auth(sup))
    assert r.status_code == 200 and r.get_json()["effective_mode"] == "live"


def test_env_kill_switch_cannot_be_released_from_dashboard(app, client, monkeypatch):
    _live(monkeypatch, app)
    monkeypatch.setenv("AUTO_MODERATION_KILL_SWITCH", "1")
    sup = _admin_token(app, client, "super_admin")
    r = client.post(f"{BASE}/kill-switch", json={"enabled": False}, headers=_auth(sup))
    assert r.status_code == 200
    assert r.get_json()["effective_mode"] == "shadow" and "warning" in r.get_json()


def test_live_mode_is_gated_by_environment_gate_ai_and_confirmation(app, client, monkeypatch):
    from kk.models import ListingModerationRun, db

    sup = _admin_token(app, client, "super_admin")
    # 1. environment does not allow live
    r = client.put(f"{BASE}/settings", json={"mode": "live", "confirm_live": True}, headers=_auth(sup))
    assert r.status_code == 409 and r.get_json()["code"] == "live_not_allowed_by_environment"
    monkeypatch.setenv("AUTO_MODERATION_ALLOW_LIVE", "1")
    # 2. shadow results do not meet the gate
    r = client.put(f"{BASE}/settings", json={"mode": "live", "confirm_live": True}, headers=_auth(sup))
    assert r.status_code == 409 and r.get_json()["code"] == "shadow_gate_not_passed"
    # loosening the gate in the SAME request does not help
    r = client.put(f"{BASE}/settings",
                   json={"mode": "live", "confirm_live": True, "gate": {"min_samples": 1}}, headers=_auth(sup))
    assert r.status_code == 409 and r.get_json()["code"] == "shadow_gate_not_passed"
    with app.app_context():
        for i in range(3):
            db.session.add(ListingModerationRun(
                subject_key=f"listing:8{i}", subject_type="listing", content_token=f"g{i}", mode="shadow",
                status="completed", decision="AUTO_APPROVE", admin_outcome="approved"))
        db.session.commit()
    assert client.put(f"{BASE}/settings", json={"gate": {"min_samples": 3}}, headers=_auth(sup)).status_code == 200
    # 3. explicit confirmation required
    r = client.put(f"{BASE}/settings", json={"mode": "live"}, headers=_auth(sup))
    assert r.status_code == 400 and r.get_json()["code"] == "confirmation_required"
    # 4. AI required but no provider configured
    monkeypatch.setenv("AUTO_MODERATION_AI_PROVIDER", "none")
    r = client.put(f"{BASE}/settings", json={"mode": "live", "confirm_live": True}, headers=_auth(sup))
    assert r.status_code == 409 and r.get_json()["code"] == "ai_not_configured"
    monkeypatch.setenv("AUTO_MODERATION_AI_PROVIDER", "stub")
    # 5. all satisfied
    r = client.put(f"{BASE}/settings", json={"mode": "live", "confirm_live": True}, headers=_auth(sup))
    assert r.status_code == 200 and r.get_json()["effective_mode"] == "live"
    # going back to shadow never needs a gate
    r = client.put(f"{BASE}/settings", json={"mode": "shadow"}, headers=_auth(sup))
    assert r.status_code == 200 and r.get_json()["effective_mode"] == "shadow"


def test_live_cannot_be_enabled_while_kill_switch_is_on(app, client, monkeypatch):
    monkeypatch.setenv("AUTO_MODERATION_ALLOW_LIVE", "1")
    sup = _admin_token(app, client, "super_admin")
    client.post(f"{BASE}/kill-switch", json={"enabled": True}, headers=_auth(sup))
    r = client.put(f"{BASE}/settings", json={"mode": "live", "confirm_live": True}, headers=_auth(sup))
    assert r.status_code == 409 and r.get_json()["code"] == "kill_switch_active"


def test_settings_validation_and_no_secrets_in_response(app, client, monkeypatch):
    monkeypatch.setenv("AUTO_MODERATION_TELEGRAM_BOT_TOKEN", "123:TOPSECRET")
    monkeypatch.setenv("AUTO_MODERATION_TELEGRAM_CHAT_ID", "-1001")
    monkeypatch.setenv("AUTO_MODERATION_OPENAI_API_KEY", "sk-TOPSECRET")
    sup = _admin_token(app, client, "super_admin")
    assert client.put(f"{BASE}/settings", json={"min_photos": 999}, headers=_auth(sup)).status_code == 400
    assert client.put(f"{BASE}/settings", json={"telegram_bot_token": "x"}, headers=_auth(sup)).status_code == 400
    r = client.get(f"{BASE}/settings", headers=_auth(sup))
    assert "TOPSECRET" not in r.get_data(as_text=True)
    j = r.get_json()
    assert j["settings"]["mode"] == "shadow" and j["environment"]["live_allowed"] is False
    assert j["environment"]["telegram_configured"] is True


def test_runs_lists_views_detail_and_history(app, client, monkeypatch):
    _live(monkeypatch, app)
    uid, _ = _trusted_seller(app)
    auto = _car(app, uid, price=15010)
    _moderate(app, "listing", auto["car_id"])  # published
    flagged = _car(app, uid, price=15020, description="western union guaranteed profit")
    _moderate(app, "listing", flagged["car_id"])
    held = _car(app, uid, price=15030, media="failed")
    _moderate(app, "listing", held["car_id"])
    tok = _admin_token(app, client, "moderator")

    def ids(view):
        j = client.get(f"{BASE}/runs?view={view}", headers=_auth(tok)).get_json()
        return {r["listing"]["id"] for r in j["runs"]}

    assert ids("auto_approved") == {auto["public_id"]}
    assert ids("flagged") == {flagged["public_id"]}
    assert ids("held") == {held["public_id"]}
    assert ids("all") == {auto["public_id"], flagged["public_id"], held["public_id"]}
    assert client.get(f"{BASE}/runs?view=nope", headers=_auth(tok)).status_code == 400

    run = client.get(f"{BASE}/runs?view=flagged", headers=_auth(tok)).get_json()["runs"][0]
    assert "scam_language" in run["reason_codes"] and run["suspicious"] is True
    d = client.get(f"{BASE}/runs/{run['id']}", headers=_auth(tok)).get_json()["run"]
    assert d["checks"]["text"] == "fail" and [e["type"] for e in d["events"]] == ["claimed", "decision"]
    assert any(r["code"] == "scam_language" for r in d["reasons"])
    h = client.get(f"{BASE}/listings/{auto['public_id']}/history", headers=_auth(tok)).get_json()
    assert [e["type"] for e in h["runs"][0]["events"]] == ["claimed", "decision", "published"]
    assert client.get(f"{BASE}/runs/does-not-exist", headers=_auth(tok)).status_code == 404

    st = client.get(f"{BASE}/stats?days=7", headers=_auth(tok)).get_json()
    assert st["evaluated"] == 3 and st["auto_approved"] == 1
    assert st["by_mode_decision"]["live:NEEDS_REVIEW"] == 1 and st["by_mode_decision"]["live:HOLD"] == 1
    assert st["error_rate"] == 0.0


def test_stats_error_rate_counts_provider_and_engine_failures(app, client, monkeypatch):
    from kk.auto_moderation import ai

    uid, _ = _trusted_seller(app)
    c1 = _car(app, uid, price=15040)
    ai.STUB_RESPONSE = ConnectionError("down")
    _moderate(app, "listing", c1["car_id"])
    ai.STUB_RESPONSE = None
    c2 = _car(app, uid, price=15050)
    _moderate(app, "listing", c2["car_id"])
    tok = _admin_token(app, client, "moderator")
    st = client.get(f"{BASE}/stats", headers=_auth(tok)).get_json()
    assert st["evaluated"] == 2 and st["failed_evaluations"] == 1 and st["error_rate"] == 0.5
    assert st["ai"]["unavailable"] == 1


def test_override_approve_publishes_via_manual_mechanism_and_logs(app, client):
    uid, _ = _user(app)  # unproven -> NEEDS_REVIEW
    c = _car(app, uid)
    _moderate(app, "listing", c["car_id"])
    tok = _admin_token(app, client, "moderator")
    rid = client.get(f"{BASE}/runs?view=flagged", headers=_auth(tok)).get_json()["runs"][0]["id"]
    r = client.post(f"{BASE}/runs/{rid}/override", json={"action": "approve", "note": "known dealer"},
                    headers=_auth(tok))
    assert r.status_code == 200
    assert _car_state(app, c["car_id"])["status"] == "active"
    assert _notifications(app, uid) == 1
    d = client.get(f"{BASE}/runs/{rid}", headers=_auth(tok)).get_json()["run"]
    assert d["override_action"] == "approve" and d["admin_outcome"] == "approved"
    assert "admin_override_approve" in [e["type"] for e in d["events"]]
    # repeat is refused (nothing awaits approval any more) -- no double approval
    r = client.post(f"{BASE}/runs/{rid}/override", json={"action": "approve"}, headers=_auth(tok))
    assert r.status_code == 409 and _notifications(app, uid) == 1


def test_override_approve_refuses_content_changed_since_decision(app, client):
    from kk.models import Car, db

    uid, _ = _user(app)
    c = _car(app, uid)
    _moderate(app, "listing", c["car_id"])
    with app.app_context():
        Car.query.get(c["car_id"]).description = "completely different text now, please review again"
        db.session.commit()
    tok = _admin_token(app, client, "moderator")
    rid = client.get(f"{BASE}/runs?view=flagged", headers=_auth(tok)).get_json()["runs"][0]["id"]
    r = client.post(f"{BASE}/runs/{rid}/override", json={"action": "approve"}, headers=_auth(tok))
    assert r.status_code == 409 and r.get_json()["code"] == "stale_run"
    assert _car_state(app, c["car_id"])["status"] == "pending"


def test_override_revoke_hides_auto_approved_listing(app, client, monkeypatch):
    _live(monkeypatch, app)
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)
    _moderate(app, "listing", c["car_id"])
    tok = _admin_token(app, client, "moderator")
    rid = client.get(f"{BASE}/runs?view=auto_approved", headers=_auth(tok)).get_json()["runs"][0]["id"]
    r = client.post(f"{BASE}/runs/{rid}/override", json={"action": "revoke", "note": "wrong category"},
                    headers=_auth(tok))
    assert r.status_code == 200
    assert _car_state(app, c["car_id"])["status"] == "hidden"
    assert _notifications(app, uid) == 2  # approved, then hidden
    assert client.post(f"{BASE}/runs/{rid}/override", json={"action": "revoke"}, headers=_auth(tok)).status_code == 409


def test_override_revoke_not_supported_for_edits_or_unapproved_runs(app, client):
    uid, _ = _trusted_seller(app)
    c = _published_car(app, uid)
    rid_rev, _s, _p = _revision(app, c["car_id"], description="Updated: new tyres fitted, service done.")
    _moderate(app, "revision", rid_rev)
    tok = _admin_token(app, client, "moderator")
    run = client.get(f"{BASE}/runs?subject_type=revision", headers=_auth(tok)).get_json()["runs"][0]
    r = client.post(f"{BASE}/runs/{run['id']}/override", json={"action": "revoke"}, headers=_auth(tok))
    assert r.status_code == 409 and r.get_json()["code"] == "revoke_not_supported"


def test_override_require_review_pins_listing_and_blocks_pending_apply(app, client, monkeypatch):
    from kk.auto_moderation import engine

    _live(monkeypatch, app)
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)
    real_apply = engine._apply
    monkeypatch.setattr(engine, "_apply", lambda *a, **k: {"outcome": "deferred"})
    _moderate(app, "listing", c["car_id"])
    monkeypatch.setattr(engine, "_apply", real_apply)
    tok = _admin_token(app, client, "moderator")
    rid = client.get(f"{BASE}/runs", headers=_auth(tok)).get_json()["runs"][0]["id"]
    assert client.post(f"{BASE}/runs/{rid}/override", json={"action": "require_review"},
                       headers=_auth(tok)).status_code == 200
    assert _runs(app, c["car_id"])[0]["outcome"] == "queued_for_review"
    # even a fresh evaluation will not auto-approve a pinned listing
    from kk.models import Car, db

    with app.app_context():
        Car.query.get(c["car_id"]).price = 15555
        db.session.commit()
    r = _moderate(app, "listing", c["car_id"])
    assert r["decision"] == "NEEDS_REVIEW"
    assert "pinned_manual_review" in _runs(app, c["car_id"])[-1]["codes"]
    assert _car_state(app, c["car_id"])["status"] == "pending"
    assert client.post(f"{BASE}/runs/{rid}/override", json={"action": "clear_review_pin"},
                       headers=_auth(tok)).status_code == 200
    assert _moderate(app, "listing", c["car_id"])["outcome"] in ("published", "done")


def test_override_requires_listings_write_and_valid_action(app, client):
    uid, _ = _user(app)
    c = _car(app, uid)
    _moderate(app, "listing", c["car_id"])
    mod = _admin_token(app, client, "moderator")
    rid = client.get(f"{BASE}/runs", headers=_auth(mod)).get_json()["runs"][0]["id"]
    support = _admin_token(app, client, "support")
    assert client.post(f"{BASE}/runs/{rid}/override", json={"action": "approve"},
                       headers=_auth(support)).status_code == 403
    assert client.post(f"{BASE}/runs/{rid}/override", json={"action": "nuke"},
                       headers=_auth(mod)).status_code == 400
    assert _car_state(app, c["car_id"])["status"] == "pending"


def test_reevaluate_enqueues_manual_job(app, client, clean):
    uid, _ = _user(app)
    c = _car(app, uid)
    _moderate(app, "listing", c["car_id"])
    tok = _admin_token(app, client, "moderator")
    rid = client.get(f"{BASE}/runs", headers=_auth(tok)).get_json()["runs"][0]["id"]
    r = client.post(f"{BASE}/runs/{rid}/reevaluate", headers=_auth(tok))
    assert r.status_code == 202
    assert clean[-1][0] == "job" and clean[-1][1]["args"][2] == "manual"


# ---------------------------------------------------------------------------
# Alerts
# ---------------------------------------------------------------------------


def _alert_setup(app, monkeypatch, **alerts):
    monkeypatch.setenv("ADMIN_WEB_BASE_URL", "https://admin.example.com")
    _settings(app, alerts={"enabled": True, "include_shadow": True, "email_recipients": ["ops@example.com"],
                           **alerts})


def test_alert_contains_no_personal_data_and_is_sent_once(app, monkeypatch):
    import kk.email_service as es
    from kk.auto_moderation.alerts import send_alert_for_run

    sent = []
    monkeypatch.setattr(es, "send_email", lambda to, subject, text_body, html_body=None: sent.append((to, subject, text_body)) or True)
    _alert_setup(app, monkeypatch)
    uid, uname = _trusted_seller(app)
    c = _car(app, uid, description="western union only 07501234567 secret@example.com")
    _moderate(app, "listing", c["car_id"])
    rid = _runs(app, c["car_id"])[0]["id"]
    with app.app_context():
        assert send_alert_for_run(rid)["sent"] is True
        assert send_alert_for_run(rid) == {"sent": False, "reason": "already_alerted"}
    assert len(sent) == 1
    to, subject, body = sent[0]
    assert to == "ops@example.com"
    for secret in (uname, "07501234567", "secret@example.com", "Toyota", "Camry", "15000", "Erbil", c["public_id"][:0] or "xx"):
        if secret != "xx":
            assert secret not in body and secret not in subject
    assert "possible scam wording" in body
    assert f"https://admin.example.com/listings/{c['public_id']}" in body
    assert "alert_sent" in _events(app, c["car_id"])


def test_alert_for_revision_links_to_edit_review(app, monkeypatch):
    import kk.email_service as es
    from kk.auto_moderation.alerts import send_alert_for_run

    sent = []
    monkeypatch.setattr(es, "send_email", lambda to, subject, text_body, html_body=None: sent.append(text_body) or True)
    _alert_setup(app, monkeypatch)
    uid, _ = _trusted_seller(app)
    c = _published_car(app, uid)
    rid, _s, rev_public = _revision(app, c["car_id"], brand="bmw")
    _moderate(app, "revision", rid)
    run_id = _runs(app, c["car_id"])[0]["id"]
    with app.app_context():
        assert send_alert_for_run(run_id)["sent"] is True
    assert f"https://admin.example.com/listing-edits/{rev_public}" in sent[0]
    assert "edit to a published listing" in sent[0]


def test_alerts_are_off_by_default_and_skip_shadow_and_routine(app, monkeypatch):
    import kk.email_service as es
    from kk.auto_moderation.alerts import send_alert_for_run

    sent = []
    monkeypatch.setattr(es, "send_email", lambda *a, **k: sent.append(1) or True)
    uid, _ = _user(app)  # unproven seller -> routine NEEDS_REVIEW only
    c = _car(app, uid)
    _moderate(app, "listing", c["car_id"])
    rid = _runs(app, c["car_id"])[0]["id"]
    with app.app_context():
        assert send_alert_for_run(rid)["reason"] == "disabled"
    _settings(app, alerts={"enabled": True, "email_recipients": ["ops@example.com"]})
    with app.app_context():
        assert send_alert_for_run(rid)["reason"] == "shadow"
    _settings(app, alerts={"include_shadow": True})
    with app.app_context():
        assert send_alert_for_run(rid)["reason"] == "routine_only"
    _settings(app, alerts={"alert_on_routine": True})
    with app.app_context():
        assert send_alert_for_run(rid)["sent"] is True
    assert sent == [1]


def test_alert_rate_cap_suppresses_excess(app, monkeypatch):
    import kk.email_service as es
    from kk.auto_moderation.alerts import send_alert_for_run

    sent = []
    monkeypatch.setattr(es, "send_email", lambda *a, **k: sent.append(1) or True)
    _alert_setup(app, monkeypatch, max_per_hour=1)
    uid, _ = _trusted_seller(app)
    ids = []
    for p in (15101, 15102):
        c = _car(app, uid, price=p, description="western union only")
        _moderate(app, "listing", c["car_id"])
        ids.append((c["car_id"], _runs(app, c["car_id"])[0]["id"]))
    with app.app_context():
        assert send_alert_for_run(ids[0][1])["sent"] is True
        assert send_alert_for_run(ids[1][1])["reason"] == "rate_capped"
    assert len(sent) == 1 and "alert_suppressed" in _events(app, ids[1][0])


def test_telegram_alert_uses_env_secret_and_never_logs_it(app, monkeypatch, caplog):
    import requests

    import kk.auto_moderation.alerts as alerts_mod

    posted = []

    def fake_post(url, json=None, timeout=None):
        posted.append((url, json))

        class R:
            status_code = 200

        return R()

    monkeypatch.setattr(alerts_mod.requests, "post", fake_post)
    monkeypatch.setenv("AUTO_MODERATION_TELEGRAM_BOT_TOKEN", "123:SECRETTOKEN")
    monkeypatch.setenv("AUTO_MODERATION_TELEGRAM_CHAT_ID", "-1001")
    _alert_setup(app, monkeypatch, channels=["telegram"], email_recipients=[])
    uid, _ = _trusted_seller(app)
    c = _car(app, uid, description="western union only")
    _moderate(app, "listing", c["car_id"])
    with app.app_context():
        assert alerts_mod.send_alert_for_run(_runs(app, c["car_id"])[0]["id"])["channels"] == {"telegram": True}
    assert posted[0][0].endswith("/bot123:SECRETTOKEN/sendMessage") and posted[0][1]["chat_id"] == "-1001"
    assert "SECRETTOKEN" not in posted[0][1]["text"]
    # failure path: exception text (which can contain the URL) is never logged
    def boom(url, json=None, timeout=None):
        raise requests.ConnectionError(f"failed for {url}")

    monkeypatch.setattr(alerts_mod.requests, "post", boom)
    with app.app_context():
        assert alerts_mod._send_telegram("x") is False
    assert "SECRETTOKEN" not in caplog.text


def test_engine_enqueues_alert_only_for_needs_review(app, monkeypatch, clean):
    from kk.tasks.moderation_tasks import moderate_listing_task

    uid, _ = _trusted_seller(app)
    ok = _car(app, uid, price=15201)
    bad = _car(app, uid, price=15202, description="western union only")
    with app.app_context():
        moderate_listing_task.run("listing", ok["car_id"])
        assert not [e for e in clean if e[0] == "alert"]
        moderate_listing_task.run("listing", bad["car_id"])
    assert [e for e in clean if e[0] == "alert"]


# ---------------------------------------------------------------------------
# Tasks, sweep, outages, old-app compatibility
# ---------------------------------------------------------------------------


def test_task_reenqueues_after_stale_and_schedules_retry_after_hold(app, monkeypatch, clean):
    from kk.auto_moderation import ai
    from kk.tasks.moderation_tasks import moderate_listing_task

    uid, _ = _trusted_seller(app)
    c = _car(app, uid)
    ai.STUB_RESPONSE = {"_status": "unavailable", "error": "timeout"}
    with app.app_context():
        out = moderate_listing_task.run("listing", c["car_id"])
    assert out["outcome"] == "held"
    jobs = [k for kind, k in clean if kind == "job"]
    assert jobs and jobs[-1].get("countdown") == 60 and jobs[-1]["ignore_result"] is True
    assert jobs[-1]["retry"] is False  # fail-fast enqueue (retention_dispatch pattern)


def _make_listing_via_api(app, client, monkeypatch, headers_extra=None):
    monkeypatch.setenv("LISTING_REQUIRE_APPROVAL", "1")
    uid, uname = _user(app)
    token = _login(client, uname)
    body = {"brand": "toyota", "model": "camry", "year": 2021, "mileage": 45000, "price": 15000,
            "location": "Erbil", "description": "Clean car, regularly serviced."}
    headers = {**_auth(token), **(headers_extra or {})}
    return uid, client.post("/api/cars", json=body, headers=headers)


def test_old_app_create_listing_is_unchanged_and_triggers_moderation(app, client, monkeypatch, clean):
    uid, r = _make_listing_via_api(app, client, monkeypatch)  # no review-aware header, no expected_media
    assert r.status_code == 201, r.data
    car = r.get_json()["car"]
    assert car["status"] == "pending" and car["is_active"] is True
    assert set(car) >= {"id", "brand", "model", "price", "status", "images", "videos"}
    assert not any(k.startswith("auto_moderation") or k == "moderation" for k in car)
    jobs = [k for kind, k in clean if kind == "job"]
    assert len(jobs) == 1 and jobs[0]["args"][0] == "listing"  # moderation requested for the media-less listing
    # the public cannot see it, exactly as before
    assert client.get(f"/api/cars/{car['id']}").status_code in (403, 404)


def test_create_listing_survives_broker_outage(app, client, monkeypatch):
    from celery.exceptions import OperationalError

    import kk.tasks.moderation_tasks as mt

    def down(*a, **k):
        raise OperationalError("redis down")

    monkeypatch.setattr(mt.moderate_listing_task, "apply_async", down)
    _uid, r = _make_listing_via_api(app, client, monkeypatch)
    assert r.status_code == 201


def test_create_listing_survives_moderation_tables_missing(app, client, monkeypatch):
    """Code deployed before the migration: the hook must never break creation."""
    import kk.auto_moderation.subjects as subjects

    def broken(*a, **k):
        raise RuntimeError("no such table: listing_moderation_run")

    monkeypatch.setattr(subjects, "subject_for_car_id", broken)
    _uid, r = _make_listing_via_api(app, client, monkeypatch)
    assert r.status_code == 201


def test_listing_with_media_waits_for_media_before_moderation(app, client, monkeypatch, clean):
    monkeypatch.setenv("LISTING_REQUIRE_APPROVAL", "1")
    uid, uname = _user(app)
    token = _login(client, uname)
    body = {"brand": "toyota", "model": "camry", "year": 2021, "mileage": 45000, "price": 15000,
            "location": "Erbil", "expected_media": [{"client_media_id": "img-1", "kind": "image", "is_cover": True}]}
    r = client.post("/api/cars", json=body, headers=_auth(token))
    assert r.status_code == 201, r.data
    assert [k for kind, k in clean if kind == "job"] == []


def _quiesce(app):
    """Take every pre-existing listing / edit out of the moderation queue so a
    test can assert exactly what the sweep picks up."""
    from kk.models import Car, CarRevision, db

    with app.app_context():
        Car.query.filter(Car.status == "pending").update({"status": "hidden"})
        CarRevision.query.filter(CarRevision.status == "pending").update({"status": "rejected"})
        db.session.commit()


def test_sweep_enqueues_only_subjects_without_a_current_decision(app, monkeypatch):
    _quiesce(app)
    import kk.auto_moderation.sweep as sweep_mod

    enq = []
    monkeypatch.setattr(sweep_mod, "request_moderation", lambda t, i, **k: enq.append((t, i)) or True)
    uid, _ = _trusted_seller(app)
    fresh = _car(app, uid, price=15301)
    done = _car(app, uid, price=15302)
    processing = _car(app, uid, price=15303, media="processing")
    _moderate(app, "listing", done["car_id"])
    with app.app_context():
        res = sweep_mod.sweep()
    assert ("listing", fresh["car_id"]) in enq
    assert ("listing", done["car_id"]) not in enq  # already has a current decision
    assert ("listing", processing["car_id"]) not in enq  # media still processing
    assert res["enqueued"] == 1


def test_sweep_recovers_lost_trigger_and_edited_content_and_due_retries(app, monkeypatch):
    _quiesce(app)
    import kk.auto_moderation.sweep as sweep_mod
    from kk.auto_moderation import ai
    from kk.models import Car, ListingModerationRun, db
    from kk.time_utils import utcnow

    enq = []
    monkeypatch.setattr(sweep_mod, "request_moderation", lambda t, i, **k: enq.append((t, i)) or True)
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)
    _moderate(app, "listing", c["car_id"])
    with app.app_context():
        sweep_mod.sweep()
    assert enq == []
    # seller edits after the decision -> sweep asks for a fresh evaluation
    with app.app_context():
        Car.query.get(c["car_id"]).description = "edited after the decision was made"
        Car.query.get(c["car_id"]).updated_at = utcnow() + timedelta(seconds=5)
        db.session.commit()
        sweep_mod.sweep()
    assert enq == [("listing", c["car_id"])]
    # HOLD due for retry is re-enqueued; one in back-off is not
    enq.clear()
    ai.STUB_RESPONSE = {"_status": "unavailable", "error": "timeout"}
    c2 = _car(app, uid, price=15400)
    _moderate(app, "listing", c2["car_id"])
    with app.app_context():
        sweep_mod.sweep()
    assert ("listing", c2["car_id"]) not in enq
    with app.app_context():
        run = ListingModerationRun.query.filter_by(car_id=c2["car_id"]).one()
        run.next_retry_at = utcnow() - timedelta(seconds=1)
        db.session.commit()
        sweep_mod.sweep()
    assert ("listing", c2["car_id"]) in enq


def test_sweep_is_inert_when_off(app, monkeypatch):
    import kk.auto_moderation.sweep as sweep_mod

    enq = []
    monkeypatch.setattr(sweep_mod, "request_moderation", lambda t, i, **k: enq.append((t, i)) or True)
    uid, _ = _trusted_seller(app)
    _car(app, uid)
    _settings(app, mode="off")
    with app.app_context():
        assert sweep_mod.sweep()["enqueued"] == 0
    assert enq == []


def test_legacy_draft_edits_are_not_moderated_until_submitted(app, monkeypatch):
    """An older app creates an `editing_legacy` draft and never submits. The
    existing 30-minute sweeper submits only a COMPLETE one; until it does,
    automation must not look at it, and afterwards it is a normal pending edit."""
    from kk import listing_revisions as lr
    from kk.models import CarRevision, db
    from kk.time_utils import utcnow

    _live(monkeypatch, app)
    uid, _ = _trusted_seller(app)
    c = _published_car(app, uid)
    rid, shadow_id, _p = _revision(app, c["car_id"], status="editing_legacy",
                                   description="Updated: new tyres fitted, service done.")
    assert _moderate(app, "revision", rid)["outcome"] == "ineligible"
    with app.app_context():
        CarRevision.query.get(rid).updated_at = utcnow() - timedelta(hours=2)
        db.session.commit()
        assert lr.sweep_idle_editing_revisions()["submitted"] == 1
    assert _moderate(app, "revision", rid)["outcome"] == "published"


def test_hooks_do_not_break_admin_actions_when_outcome_recording_fails(app, client, monkeypatch):
    import kk.auto_moderation.outcomes as outcomes

    def boom(**k):
        raise RuntimeError("table missing")

    monkeypatch.setattr(outcomes, "record_admin_outcome", boom)
    uid, _ = _user(app)
    c = _car(app, uid)
    tok = _admin_token(app, client)
    r = client.patch(f"/api/admin/cars/{c['public_id']}/status",
                     json={"is_active": True, "status": "active"}, headers=_auth(tok))
    assert r.status_code == 200 and _car_state(app, c["car_id"])["status"] == "active"


def test_manual_admin_listing_actions_unchanged_without_any_run(app, client):
    """Admin approval of a listing automation never evaluated works exactly as
    before and does not fail for lack of a run."""
    uid, _ = _user(app)
    c = _car(app, uid)
    tok = _admin_token(app, client)
    r = client.patch(f"/api/admin/cars/{c['public_id']}/status",
                     json={"is_active": True, "status": "active"}, headers=_auth(tok))
    assert r.status_code == 200
    assert _runs(app) == []


def test_media_not_ready_still_blocks_manual_activation_unchanged(app, client):
    uid, _ = _user(app)
    c = _car(app, uid, media="processing")
    tok = _admin_token(app, client)
    r = client.patch(f"/api/admin/cars/{c['public_id']}/status",
                     json={"is_active": True, "status": "active"}, headers=_auth(tok))
    assert r.status_code == 409


# ---------------------------------------------------------------------------
# Migration
# ---------------------------------------------------------------------------


def test_migration_is_additive_single_head_and_reversible():
    import importlib.util

    import sqlalchemy as sa
    from alembic.config import Config
    from alembic.operations import Operations
    from alembic.runtime.migration import MigrationContext
    from alembic.script import ScriptDirectory

    cfg = Config()
    cfg.set_main_option("script_location", str(_REPO_ROOT / "migrations"))
    script = ScriptDirectory.from_config(cfg)
    assert script.get_heads() == ["v0w1x2y3z4a5"]
    path = _REPO_ROOT / "migrations" / "versions" / "v0w1x2y3z4a5_add_listing_moderation_tables.py"
    src = path.read_text(encoding="utf-8")
    up = src.split("def upgrade()")[1].split("def downgrade()")[0]
    # the only statement besides create_table / create_index is the bounded
    # lock wait (PostgreSQL only, transaction-local)
    assert up.count("op.execute(") == 1 and "SET LOCAL lock_timeout" in up
    up = up.replace('op.execute("SET LOCAL lock_timeout = \'5s\'")', "")
    for forbidden in ("drop_", "alter_column", "add_column", "batch_alter_table", "execute("):
        assert forbidden not in up
    assert src.count("op.create_table(") == 2

    spec = importlib.util.spec_from_file_location("mig_v0w1", path)
    mig = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mig)
    engine = sa.create_engine("sqlite://")
    md = sa.MetaData()
    for t in ("car", "user", "car_revision"):
        sa.Table(t, md, sa.Column("id", sa.Integer, primary_key=True))
    md.create_all(engine)
    with engine.begin() as conn:
        with Operations.context(MigrationContext.configure(conn)):
            mig.upgrade()
        names = set(sa.inspect(conn).get_table_names())
        assert {"listing_moderation_run", "listing_moderation_event"} <= names
        with Operations.context(MigrationContext.configure(conn)):
            mig.downgrade()
        names = set(sa.inspect(conn).get_table_names())
        assert not ({"listing_moderation_run", "listing_moderation_event"} & names)
        assert {"car", "user", "car_revision"} <= names  # nothing else touched


def test_stub_ai_provider_is_unusable_outside_testing(app, monkeypatch):
    """The test double approves everything; a misconfigured production
    environment must not be able to use it as a real provider."""
    from kk.auto_moderation import config

    assert config.ai_provider_configured() is True  # APP_ENV=testing in this suite
    monkeypatch.setenv("APP_ENV", "production")
    assert config.ai_provider_configured() is False
    _live(monkeypatch, app)
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)
    r = _moderate(app, "listing", c["car_id"])
    assert r["decision"] == "NEEDS_REVIEW"
    assert "ai_not_configured" in _runs(app, c["car_id"])[0]["codes"]
    assert _car_state(app, c["car_id"])["status"] == "pending"


# ===========================================================================
# Release-blocker hardening: payment integrity, complete image coverage,
# mandatory AI check, shadow-mode clarity
# ===========================================================================


@pytest.fixture
def payment_hook():
    from kk.auto_moderation import payment

    payment.register_payment_verifier(None)
    yield payment
    payment.register_payment_verifier(None)


def _ai_ok_for(urls):
    return {
        "text": {"ok": True, "flags": []},
        "images": [{"index": i, "is_car_photo": True, "flags": []} for i in range(len(urls))],
        "confidence": 0.95,
    }


def _set_ai(calls=None, overrides=None):
    """Install a recording stub provider. `overrides` may map call number ->
    a raw response / exception / callable(urls)."""
    from kk.auto_moderation import ai

    overrides = overrides or {}

    def stub(title, desc, urls):
        n = len(calls) if calls is not None else 0
        if calls is not None:
            calls.append({"desc": desc, "urls": list(urls)})
        spec = overrides.get(n)
        if isinstance(spec, Exception):
            raise spec
        if callable(spec):
            return spec(urls)
        return spec if spec is not None else _ai_ok_for(urls)

    ai.STUB_RESPONSE = stub


# ---- payment --------------------------------------------------------------


def test_free_deployment_has_no_payment_gate_and_approves(app, monkeypatch):
    """Today CarNet charges nothing: default settings never invent a payment
    requirement, and never record a payment either."""
    _live(monkeypatch, app)
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)
    assert _moderate(app, "listing", c["car_id"])["outcome"] == "published"
    assert "payment_verified" not in _runs(app, c["car_id"])[0]["codes"]


def test_required_payment_without_ledger_is_never_approved(app, monkeypatch, payment_hook):
    _live(monkeypatch, app, listing_payment_required=True)
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)
    assert _moderate(app, "listing", c["car_id"])["decision"] == "NEEDS_REVIEW"
    assert "payment_unverifiable" in _runs(app, c["car_id"])[0]["codes"]
    from kk.auto_moderation import config

    with app.app_context():
        assert "payment_verifier_not_registered" in config.readiness()["blockers"]


@pytest.mark.parametrize("kind", ["paid", "free_allowance"])
def test_verified_payment_or_free_allowance_can_be_auto_approved(app, monkeypatch, payment_hook, kind):
    _live(monkeypatch, app, listing_payment_required=True)
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)
    seen = []

    def verifier(car_id, seller_id):
        seen.append((car_id, seller_id))
        return {"status": kind, "car_id": car_id, "reference": "ledger-42"}

    payment_hook.register_payment_verifier(verifier)
    assert _moderate(app, "listing", c["car_id"])["outcome"] == "published"
    assert (c["car_id"], uid) in seen
    run = _runs(app, c["car_id"])[0]
    assert run["decision"] == "AUTO_APPROVE"
    from kk.models import ListingModerationRun

    with app.app_context():
        reasons = ListingModerationRun.query.first().reasons
    assert any(r["code"] == "payment_verified" and r["detail"] == f"{kind}:ledger-42" for r in reasons)


@pytest.mark.parametrize(
    "proof",
    [
        None,
        {},
        True,
        "paid",
        {"status": "paid"},  # no car binding / reference
        {"status": "pending", "car_id": "SELF", "reference": "x"},
        {"status": "paid", "car_id": 999999, "reference": "x"},  # proof for another listing
        {"status": "paid", "car_id": "SELF", "reference": "  "},
        {"status": "refunded", "car_id": "SELF", "reference": "x"},
    ],
)
def test_malformed_or_foreign_payment_proof_never_approves(app, monkeypatch, payment_hook, proof):
    _live(monkeypatch, app, listing_payment_required=True)
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)

    def verifier(car_id, seller_id):
        if isinstance(proof, dict):
            return {k: (car_id if v == "SELF" else v) for k, v in proof.items()}
        return proof

    payment_hook.register_payment_verifier(verifier)
    assert _moderate(app, "listing", c["car_id"])["decision"] == "NEEDS_REVIEW"
    assert _car_state(app, c["car_id"])["status"] == "pending"


def test_payment_verifier_outage_holds_and_never_approves(app, monkeypatch, payment_hook):
    _live(monkeypatch, app, listing_payment_required=True)
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)

    def boom(car_id, seller_id):
        raise ConnectionError("ledger down")

    payment_hook.register_payment_verifier(boom)
    r = _moderate(app, "listing", c["car_id"])
    assert r["decision"] == "HOLD" and r["retry_in"]
    assert "payment_check_unavailable" in _runs(app, c["car_id"])[0]["codes"]
    assert _car_state(app, c["car_id"])["status"] == "pending"


def test_refund_between_decision_and_publication_blocks_the_approval(app, monkeypatch, payment_hook):
    from kk.auto_moderation import engine

    _live(monkeypatch, app, listing_payment_required=True)
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)
    state = {"paid": True}
    payment_hook.register_payment_verifier(
        lambda car_id, seller_id: {"status": "paid", "car_id": car_id, "reference": "r1"} if state["paid"] else None
    )
    real_apply = engine._apply
    monkeypatch.setattr(engine, "_apply", lambda *a, **k: {"outcome": "deferred"})
    _moderate(app, "listing", c["car_id"])
    monkeypatch.setattr(engine, "_apply", real_apply)
    state["paid"] = False  # refunded / allowance revoked
    with app.app_context():
        out = real_apply(_runs(app, c["car_id"])[0]["id"], "listing", c["car_id"])
    assert out["outcome"] == "downgraded"
    assert _car_state(app, c["car_id"])["status"] == "pending"


def test_payment_requirement_does_not_apply_to_edits_of_published_listings(app, monkeypatch, payment_hook):
    _live(monkeypatch, app, listing_payment_required=True)
    uid, _ = _trusted_seller(app)
    c = _published_car(app, uid)
    rid, _s, _p = _revision(app, c["car_id"], description="Updated: new tyres fitted, service done.")
    assert _moderate(app, "revision", rid)["outcome"] == "published"


def test_client_cannot_assert_payment(app, client, monkeypatch, payment_hook, clean):
    """There is no client-writable payment field on create: extra JSON keys are
    ignored, and with payment required the listing still needs a human."""
    monkeypatch.setenv("LISTING_REQUIRE_APPROVAL", "1")
    _live(monkeypatch, app, listing_payment_required=True)
    uid, uname = _trusted_seller(app)
    token = _login(client, uname)
    body = {"brand": "toyota", "model": "camry", "year": 2022, "mileage": 5, "price": 20000,
            "location": "Erbil", "payment_status": "paid", "is_paid": True, "paid": True,
            "payment": {"status": "paid", "reference": "forged"}}
    r = client.post("/api/cars", json=body, headers=_auth(token))
    assert r.status_code == 201
    from kk.models import Car

    pid = r.get_json()["car"]["id"]
    with app.app_context():
        car_id = Car.query.filter_by(public_id=pid).one().id
    _moderate(app, "listing", car_id)
    assert "payment_unverifiable" in _runs(app, car_id)[0]["codes"]
    assert _car_state(app, car_id)["status"] == "pending"


# ---- complete image coverage ----------------------------------------------


def test_every_image_is_inspected_in_batches_cover_first(app, monkeypatch):
    from kk.models import CarImage, db

    _live(monkeypatch, app)
    _settings(app, ai={"max_images": 2})
    calls = []
    _set_ai(calls=calls)
    uid, _ = _trusted_seller(app)
    c = _car(app, uid, photos=5)
    with app.app_context():  # make the LAST photo the stored (and declared) cover
        imgs = CarImage.query.filter_by(car_id=c["car_id"]).order_by(CarImage.order).all()
        from kk.models import CarMediaItem

        for i in imgs:
            i.is_primary = False
        imgs[-1].is_primary = True
        for it in CarMediaItem.query.filter_by(car_id=c["car_id"]).all():
            it.is_cover = (it.client_media_id == imgs[-1].source_media_id)
        db.session.commit()
        cover_url = imgs[-1].image_url
        all_urls = {i.image_url for i in imgs}
    r = _moderate(app, "listing", c["car_id"])
    assert r["outcome"] == "published", _runs(app, c["car_id"])[0]["codes"]
    sent = [u for call in calls for u in call["urls"]]
    assert len(calls) == 3 and set(sent) == all_urls and len(sent) == 5  # 2 + 2 + 1, none twice
    assert calls[0]["urls"][0] == cover_url  # the final cover is judged first
    assert calls[0]["desc"] is not None and all(c_["desc"] is None for c_ in calls[1:])  # text judged once
    from kk.models import ListingModerationRun

    with app.app_context():
        ai = ListingModerationRun.query.first().ai
    assert ai["images_expected"] == 5 and ai["images_checked"] == 5 and ai["cover_checked"] is True


def test_more_photos_than_the_limit_go_to_review_without_calling_the_provider(app, monkeypatch):
    _live(monkeypatch, app)
    _settings(app, ai={"max_total_images": 3})
    calls = []
    _set_ai(calls=calls)
    uid, _ = _trusted_seller(app)
    c = _car(app, uid, photos=4)
    r = _moderate(app, "listing", c["car_id"])
    assert r["decision"] == "NEEDS_REVIEW"
    assert "ai_image_coverage_incomplete" in _runs(app, c["car_id"])[0]["codes"]
    assert calls == []  # bounded spend: nothing is sent for a gallery we will not fully inspect
    assert _car_state(app, c["car_id"])["status"] == "pending"


def test_exactly_at_the_limit_is_fully_inspected(app, monkeypatch):
    _live(monkeypatch, app)
    _settings(app, ai={"max_total_images": 4, "max_images": 4})
    calls = []
    _set_ai(calls=calls)
    uid, _ = _trusted_seller(app)
    c = _car(app, uid, photos=4)
    assert _moderate(app, "listing", c["car_id"])["outcome"] == "published"
    assert len(calls) == 1 and len(calls[0]["urls"]) == 4


def test_non_https_photo_cannot_be_inspected_so_it_is_never_auto_approved(app, monkeypatch):
    from kk.models import CarImage, db

    _live(monkeypatch, app)
    calls = []
    _set_ai(calls=calls)
    uid, _ = _trusted_seller(app)
    c = _car(app, uid, photos=3)
    with app.app_context():
        img = CarImage.query.filter_by(id=c["image_ids"][2]).one()
        img.image_url = img.image_url.replace("https://", "http://")
        db.session.commit()
    r = _moderate(app, "listing", c["car_id"])
    assert r["decision"] == "NEEDS_REVIEW"
    assert "ai_image_coverage_incomplete" in _runs(app, c["car_id"])[0]["codes"]
    assert len([u for call in calls for u in call["urls"]]) == 2  # the https ones were still checked


def test_damage_and_other_photo_kinds_are_inspected_too(app, monkeypatch):
    from kk.models import CarImage, db

    _live(monkeypatch, app)
    calls = []
    _set_ai(calls=calls)
    uid, _ = _trusted_seller(app)
    c = _car(app, uid, photos=3)
    with app.app_context():
        img = CarImage.query.filter_by(id=c["image_ids"][2]).one()
        img.kind = "damage"
        db.session.commit()
        damage_url = img.image_url
    _moderate(app, "listing", c["car_id"])
    assert damage_url in [u for call in calls for u in call["urls"]]


def test_text_only_provider_configuration_cannot_approve_a_listing_with_photos(app, monkeypatch):
    _live(monkeypatch, app)
    _settings(app, ai={"send_images": False})
    calls = []
    _set_ai(calls=calls)
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)
    r = _moderate(app, "listing", c["car_id"])
    assert r["decision"] == "NEEDS_REVIEW"
    assert "ai_image_coverage_incomplete" in _runs(app, c["car_id"])[0]["codes"]
    assert all(call["urls"] == [] for call in calls)


def test_provider_failure_or_flag_in_a_later_batch_is_never_ignored(app, monkeypatch):
    _live(monkeypatch, app)
    _settings(app, ai={"max_images": 1})
    uid, _ = _trusted_seller(app)
    # 3 photos -> 3 requests; the third fails
    calls = []
    _set_ai(calls=calls, overrides={2: ConnectionError("down")})
    c = _car(app, uid, photos=3)
    r = _moderate(app, "listing", c["car_id"])
    assert r["decision"] == "HOLD" and "ai_unavailable" in _runs(app, c["car_id"])[0]["codes"]
    assert _car_state(app, c["car_id"])["status"] == "pending"
    # the third request flags its photo
    calls2 = []
    flagged_batch = lambda urls: {  # noqa: E731
        "text": {"ok": True, "flags": []},
        "images": [{"index": 0, "is_car_photo": False, "flags": ["explicit"]}],
        "confidence": 0.9,
    }
    _set_ai(calls=calls2, overrides={2: flagged_batch})
    c2 = _car(app, uid, photos=3, price=16111, brand="kia", model="rio", title="Kia Rio 2021",
              description="Different words about a different car for this one.")
    r = _moderate(app, "listing", c2["car_id"])
    assert r["decision"] == "NEEDS_REVIEW" and "ai_flagged" in _runs(app, c2["car_id"])[0]["codes"]
    assert _car_state(app, c2["car_id"])["status"] == "pending"


def test_partial_verdicts_from_the_provider_are_uncertain_not_ok(app, monkeypatch):
    _live(monkeypatch, app)
    _settings(app, ai={"max_images": 4})
    partial = lambda urls: {  # noqa: E731
        "text": {"ok": True, "flags": []},
        "images": [{"index": 0, "is_car_photo": True, "flags": []}],  # 3 photos, 1 verdict
        "confidence": 0.9,
    }
    _set_ai(overrides={0: partial})
    uid, _ = _trusted_seller(app)
    c = _car(app, uid, photos=3)
    r = _moderate(app, "listing", c["car_id"])
    assert r["decision"] == "NEEDS_REVIEW" and "ai_uncertain" in _runs(app, c["car_id"])[0]["codes"]


def test_videos_are_never_auto_approved_unreviewed(app, monkeypatch):
    from kk.models import CarVideo, db

    _live(monkeypatch, app)
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)
    with app.app_context():
        db.session.add(CarVideo(car_id=c["car_id"], video_url=f"{_CDN}/v.mp4", thumbnail_url=f"{_CDN}/v.jpg"))
        db.session.commit()
    assert _moderate(app, "listing", c["car_id"])["decision"] == "NEEDS_REVIEW"
    assert "videos_not_inspected" in _runs(app, c["car_id"])[0]["codes"]


def test_title_is_moderated_like_the_description(app, monkeypatch):
    _live(monkeypatch, app)
    uid, _ = _trusted_seller(app)
    c = _car(app, uid, title="Camry - western union only, guaranteed profit")
    assert _moderate(app, "listing", c["car_id"])["decision"] == "NEEDS_REVIEW"
    assert "scam_language" in _runs(app, c["car_id"])[0]["codes"]


def test_revision_inspects_only_new_photos_and_title_only_edits_are_judged(app, monkeypatch):
    from kk.models import Car, CarImage, CarMediaItem, db

    _live(monkeypatch, app)
    calls = []
    _set_ai(calls=calls)
    uid, _ = _trusted_seller(app)
    c = _published_car(app, uid)
    rid, shadow_id, _p = _revision(app, c["car_id"], title="Toyota Camry 2021 - one owner")
    r = _moderate(app, "revision", rid)
    assert r["outcome"] == "published"
    assert len(calls) == 1 and calls[0]["urls"] == []  # a title change is judged; no new photos to send
    # an edit that adds one photo (and makes it the cover) sends exactly that photo, first
    calls.clear()
    c2 = _published_car(app, uid, price=15321, brand="kia", model="rio", title="Kia Rio 2021",
                        description="Yet another listing with entirely different content here.")
    rid2, shadow2, _p2 = _revision(app, c2["car_id"], description="Updated: refreshed text for the ad.")
    with app.app_context():
        for im in CarImage.query.filter_by(car_id=shadow2).all():
            im.is_primary = False
        db.session.add(CarImage(car_id=shadow2, image_url=f"{_CDN}/new-cover.jpg", is_primary=True, order=0,
                                kind="listing", source_media_id="newc", image_width=1600, image_height=1200))
        db.session.add(CarMediaItem(car_id=shadow2, kind="image", client_media_id="newc", status="attached",
                                    is_cover=True, sort_order=0))
        db.session.commit()
    r = _moderate(app, "revision", rid2)
    assert len(calls) == 1 and calls[0]["urls"] == [f"{_CDN}/new-cover.jpg"]
    assert r["outcome"] in ("published", "queued_for_review")


# ---- no approval without the required AI check -----------------------------


def test_no_ai_provider_means_shadow_records_review_and_nothing_publishes(app, client, monkeypatch):
    monkeypatch.setenv("AUTO_MODERATION_AI_PROVIDER", "none")
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)
    r = _moderate(app, "listing", c["car_id"])
    assert r["decision"] == "NEEDS_REVIEW" and r["outcome"] == "queued_for_review"
    assert "ai_not_configured" in _runs(app, c["car_id"])[0]["codes"]
    sup = _admin_token(app, client, "super_admin")
    j = client.get(f"{BASE}/settings", headers=_auth(sup)).get_json()
    rd = j["readiness"]
    assert rd["auto_approval_possible"] is False and "ai_provider_not_configured" in rd["blockers"]
    assert any("No AI provider is configured" in n for n in rd["notes"])
    assert j["effective_mode"] == "shadow"


@pytest.mark.parametrize("provider_state", ["none", "outage", "uncertain", "disabled_by_missing_key"])
def test_no_approval_path_exists_without_a_clean_ai_check(app, monkeypatch, provider_state):
    from kk.auto_moderation import ai

    _live(monkeypatch, app)
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)
    if provider_state == "none":
        monkeypatch.setenv("AUTO_MODERATION_AI_PROVIDER", "none")
    elif provider_state == "outage":
        ai.STUB_RESPONSE = ConnectionError("x")
    elif provider_state == "uncertain":
        ai.STUB_RESPONSE = {"_status": "uncertain", "error": "invalid_response"}
    else:
        monkeypatch.setenv("AUTO_MODERATION_AI_PROVIDER", "openai")
        monkeypatch.delenv("AUTO_MODERATION_OPENAI_API_KEY", raising=False)
        monkeypatch.delenv("OPENAI_API_KEY", raising=False)
    r = _moderate(app, "listing", c["car_id"])
    assert r["decision"] in ("NEEDS_REVIEW", "HOLD")
    assert _car_state(app, c["car_id"])["status"] == "pending"
    assert _notifications(app, uid) == 0


def test_apply_refuses_when_the_stored_ai_evidence_is_missing_or_partial(app, monkeypatch):
    """Even a run that somehow reached pending_apply cannot publish without a
    complete, clean advisory check for the content as it is now."""
    from kk.auto_moderation import engine
    from kk.models import ListingModerationRun, db

    _live(monkeypatch, app)
    uid, _ = _trusted_seller(app)
    real_apply = engine._apply
    words = ["alpha", "bravo", "charlie", "delta", "echo", "foxtrot"]
    tampers = (
        {"status": "disabled"},
        None,
        {"status": "ok", "images_expected": 2, "images_checked": 2},  # gallery has 3
        {"status": "ok", "images_expected": 3, "images_checked": 1},
        {"status": "skipped"},
        {"status": "not_needed"},
    )
    for n, tamper in enumerate(tampers):
        uid, _ = _trusted_seller(app)
        c = _car(app, uid, price=15500 + n, brand=words[n], model="roadster",
                 title=f"{words[n].title()} Roadster 2021",
                 description=f"A distinctive {words[n]} listing text, written specially for case {words[n]} here.")
        monkeypatch.setattr(engine, "_apply", lambda *a, **k: {"outcome": "deferred"})
        _moderate(app, "listing", c["car_id"])
        monkeypatch.setattr(engine, "_apply", real_apply)
        with app.app_context():
            run = ListingModerationRun.query.filter_by(car_id=c["car_id"]).one()
            assert run.outcome == "pending_apply"
            run.ai = tamper
            db.session.commit()
            out = real_apply(run.id, "listing", c["car_id"])
        assert out["outcome"] in ("downgraded", "held"), tamper
        assert _car_state(app, c["car_id"])["status"] == "pending", tamper


def test_raised_confidence_bar_applies_to_an_already_decided_run(app, monkeypatch):
    from kk.auto_moderation import engine

    _live(monkeypatch, app)
    uid, _ = _trusted_seller(app)
    c = _car(app, uid)
    real_apply = engine._apply
    monkeypatch.setattr(engine, "_apply", lambda *a, **k: {"outcome": "deferred"})
    _moderate(app, "listing", c["car_id"])
    monkeypatch.setattr(engine, "_apply", real_apply)
    _settings(app, ai={"min_confidence": 0.99})  # stub answered 0.95
    with app.app_context():
        out = real_apply(_runs(app, c["car_id"])[0]["id"], "listing", c["car_id"])
    assert out["outcome"] == "downgraded"
    assert _car_state(app, c["car_id"])["status"] == "pending"
