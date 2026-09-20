"""CarNet V1 feature-completeness batch 3 -- item 1 (seller-facing
listing-moderation notifications).

Bug: admin actions that change a listing's public-visibility state --
`PATCH /api/admin/cars/<id>/status`, `POST /api/admin/cars/bulk-status`,
and `DELETE /api/admin/cars/<id>` (soft-delete) -- silently mutated
`Car.is_active`/`Car.status` without ever notifying the seller. A seller
had no way to learn their listing was approved, hidden, or removed except
by noticing it themselves in "My Listings".

Fix (`kk/routes/admin.py`): `_car_moderation_state()` classifies a listing's
(is_active, status) into "active" / "hidden" / `None` (out-of-scope buckets
like sold/pending/draft are never notified). All three routes snapshot the
bucket before mutating and only queue a `Notification` (+ best-effort push
+ realtime emit, mirroring `dealers_approve()`) when the bucket actually
changes -- never on a no-op resend (dedup requirement). `delete_car` always
reports "removed" (a distinct wording/notification from "hidden", with NO
`car_id` in its payload so the client never deep-links to a gone listing),
skipped only if the listing was already hidden/inactive (nothing actually
changed). Reuses `kk/localization.py::translate`/`get_background_locale`
(MI-03) for en/ar/ku; an admin-supplied `reason` is passed through
verbatim (never machine-translated, never fabricated when absent).
"""

from __future__ import annotations

import os
import sys
import tempfile
import uuid
from pathlib import Path
from unittest import mock

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

os.environ.setdefault("APP_ENV", "testing")
os.environ.setdefault("SECRET_KEY", "test-secret-key-for-carnet-v1-batch3-moderation")
os.environ.setdefault("JWT_SECRET_KEY", "test-jwt-secret-key-for-carnet-v1-batch3-moderation")

from firebase_admin import messaging as fcm_messaging  # noqa: E402

_PASSWORD = "Aa123456!"


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_batch3_mod_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "batch3_mod.db")

    from kk.app_factory import create_app

    app, socketio, *_ = create_app()
    from kk.models import Car, Notification, User, db

    with app.app_context():
        db.drop_all()
        db.create_all()

    yield app, socketio, app.test_client(), db, User, Car, Notification

    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    tmp.cleanup()


@pytest.fixture(autouse=True)
def _stub_firebase_ready(monkeypatch):
    """Every test in this module reaches `send_push()`'s real body (mirrors
    test_be05_push_token_cleanup.py) without needing real Firebase creds."""
    import kk.push as push_module

    monkeypatch.setattr(push_module, "_ensure_firebase", lambda: object())
    monkeypatch.setattr(push_module, "_service_account_oauth_ok", lambda: True)
    yield


def _phone() -> str:
    return f"076{uuid.uuid4().int % 10**8:08d}"


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _make_user(app_ctx, *, tag: str, locale: str | None = None, is_admin: bool = False, firebase_token: str | None = None):
    app, _socketio, _client, db, User, *_ = app_ctx
    with app.app_context():
        user = User(
            username=f"b3mod_{tag}_{uuid.uuid4().hex[:10]}",
            phone_number=_phone(),
            first_name="B3",
            last_name="Mod",
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id=f"b3mod-{tag}-{uuid.uuid4().hex[:12]}",
            is_admin=is_admin,
            locale=locale,
            firebase_token=firebase_token,
        )
        user.set_password(_PASSWORD)
        db.session.add(user)
        db.session.commit()
        return user.id, user.username, user.public_id


def _make_car(app_ctx, *, seller_id: int, tag: str, status: str = "active", is_active: bool = True):
    app, _socketio, _client, db, _User, Car, *_ = app_ctx
    with app.app_context():
        car = Car(
            seller_id=seller_id,
            public_id=f"b3mod-car-{tag}-{uuid.uuid4().hex[:10]}",
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
            is_active=is_active,
            status=status,
        )
        db.session.add(car)
        db.session.commit()
        return car.id, car.public_id


def _login(client, username: str) -> str:
    r = client.post("/api/auth/login", json={"username": username, "password": _PASSWORD})
    assert r.status_code == 200, r.data
    return r.get_json()["access_token"]


def _latest_notification(app_ctx, user_id: int, notification_type: str = "listing_status"):
    app, _socketio, _client, db, _User, _Car, Notification = app_ctx
    with app.app_context():
        return (
            Notification.query.filter_by(user_id=user_id, notification_type=notification_type)
            .order_by(Notification.id.desc())
            .first()
        )


def _notification_count(app_ctx, user_id: int, notification_type: str = "listing_status") -> int:
    app, _socketio, _client, db, _User, _Car, Notification = app_ctx
    with app.app_context():
        return Notification.query.filter_by(user_id=user_id, notification_type=notification_type).count()


# ---------------------------------------------------------------------------
# PATCH /api/admin/cars/<id>/status
# ---------------------------------------------------------------------------


def test_patch_hide_active_listing_notifies_seller_localized(app_ctx):
    app, _socketio, client, db, User, Car, Notification = app_ctx
    admin_id, admin_username, _ap = _make_user(app_ctx, tag="admin1", is_admin=True)
    seller_id, _sn, _sp = _make_user(app_ctx, tag="seller1", locale="ar")
    _car_id, car_pub = _make_car(app_ctx, seller_id=seller_id, tag="hide1", status="active", is_active=True)

    token = _login(client, admin_username)
    resp = client.patch(
        f"/api/admin/cars/{car_pub}/status",
        json={"is_active": False, "status": "hidden"},
        headers=_auth(token),
    )
    assert resp.status_code == 200, resp.data

    notif = _latest_notification(app_ctx, seller_id)
    assert notif is not None
    assert notif.title == "تم إخفاء الإعلان"
    assert notif.message == "تم إخفاء إعلانك من قبل فريق المراجعة لدينا."
    assert notif.data["status"] == "hidden"
    assert notif.data["car_id"] == car_pub  # still exists -> safe to deep-link


def test_patch_approve_pending_listing_notifies_seller_english_default(app_ctx):
    app, _socketio, client, db, User, Car, Notification = app_ctx
    admin_id, admin_username, _ap = _make_user(app_ctx, tag="admin2", is_admin=True)
    seller_id, _sn, _sp = _make_user(app_ctx, tag="seller2")  # no locale -> English
    _car_id, car_pub = _make_car(app_ctx, seller_id=seller_id, tag="appr1", status="pending", is_active=True)

    token = _login(client, admin_username)
    resp = client.patch(
        f"/api/admin/cars/{car_pub}/status",
        json={"is_active": True, "status": "active"},
        headers=_auth(token),
    )
    assert resp.status_code == 200, resp.data

    notif = _latest_notification(app_ctx, seller_id)
    assert notif is not None
    assert notif.title == "Listing approved"
    assert notif.message == "Your listing is now live and visible to buyers."
    assert notif.data["status"] == "active"
    assert notif.data["car_id"] == car_pub


def test_patch_hide_with_admin_reason_passed_through_verbatim_kurdish_locale(app_ctx):
    app, _socketio, client, db, User, Car, Notification = app_ctx
    admin_id, admin_username, _ap = _make_user(app_ctx, tag="admin3", is_admin=True)
    seller_id, _sn, _sp = _make_user(app_ctx, tag="seller3", locale="ku")
    _car_id, car_pub = _make_car(app_ctx, seller_id=seller_id, tag="hide2", status="active", is_active=True)

    token = _login(client, admin_username)
    admin_reason = "Duplicate listing of car-xyz."
    resp = client.patch(
        f"/api/admin/cars/{car_pub}/status",
        json={"is_active": False, "status": "hidden", "reason": admin_reason},
        headers=_auth(token),
    )
    assert resp.status_code == 200, resp.data

    notif = _latest_notification(app_ctx, seller_id)
    assert notif is not None
    assert notif.title == "ڕێکلامەکە شاردرایەوە"  # title still localized (Kurdish)
    assert notif.message == admin_reason  # body is the admin's own words, untouched


def test_patch_no_visibility_change_does_not_duplicate_notification(app_ctx):
    """Only touching is_featured (no is_active/status change) must not
    notify -- and resending the exact same status must not notify again."""
    app, _socketio, client, db, User, Car, Notification = app_ctx
    admin_id, admin_username, _ap = _make_user(app_ctx, tag="admin4", is_admin=True)
    seller_id, _sn, _sp = _make_user(app_ctx, tag="seller4")
    _car_id, car_pub = _make_car(app_ctx, seller_id=seller_id, tag="nodup1", status="active", is_active=True)

    token = _login(client, admin_username)

    # is_featured-only patch: no notification at all.
    resp1 = client.patch(
        f"/api/admin/cars/{car_pub}/status",
        json={"is_featured": True},
        headers=_auth(token),
    )
    assert resp1.status_code == 200, resp1.data
    assert _notification_count(app_ctx, seller_id) == 0

    # Resending the same already-active state: still no notification.
    resp2 = client.patch(
        f"/api/admin/cars/{car_pub}/status",
        json={"is_active": True, "status": "active"},
        headers=_auth(token),
    )
    assert resp2.status_code == 200, resp2.data
    assert _notification_count(app_ctx, seller_id) == 0

    # Now actually hide it: exactly one notification.
    resp3 = client.patch(
        f"/api/admin/cars/{car_pub}/status",
        json={"is_active": False, "status": "hidden"},
        headers=_auth(token),
    )
    assert resp3.status_code == 200, resp3.data
    assert _notification_count(app_ctx, seller_id) == 1

    # Resending the same "hidden" state again: still exactly one.
    resp4 = client.patch(
        f"/api/admin/cars/{car_pub}/status",
        json={"is_active": False, "status": "hidden"},
        headers=_auth(token),
    )
    assert resp4.status_code == 200, resp4.data
    assert _notification_count(app_ctx, seller_id) == 1


def test_patch_transition_to_sold_is_out_of_scope_no_notification(app_ctx):
    """"sold"/"pending"/"draft" are not moderation buckets this batch
    covers -- no notification should fire for them."""
    app, _socketio, client, db, User, Car, Notification = app_ctx
    admin_id, admin_username, _ap = _make_user(app_ctx, tag="admin5", is_admin=True)
    seller_id, _sn, _sp = _make_user(app_ctx, tag="seller5")
    _car_id, car_pub = _make_car(app_ctx, seller_id=seller_id, tag="sold1", status="active", is_active=True)

    token = _login(client, admin_username)
    resp = client.patch(
        f"/api/admin/cars/{car_pub}/status",
        json={"status": "sold"},
        headers=_auth(token),
    )
    assert resp.status_code == 200, resp.data
    assert _notification_count(app_ctx, seller_id) == 0


def test_patch_hide_only_correct_seller_notified_not_admin(app_ctx):
    app, _socketio, client, db, User, Car, Notification = app_ctx
    admin_id, admin_username, _ap = _make_user(app_ctx, tag="admin6", is_admin=True)
    seller_id, _sn, _sp = _make_user(app_ctx, tag="seller6")
    other_seller_id, _osn, _osp = _make_user(app_ctx, tag="otherseller6")
    _car_id, car_pub = _make_car(app_ctx, seller_id=seller_id, tag="idor1", status="active", is_active=True)

    token = _login(client, admin_username)
    resp = client.patch(
        f"/api/admin/cars/{car_pub}/status",
        json={"is_active": False, "status": "hidden"},
        headers=_auth(token),
    )
    assert resp.status_code == 200, resp.data

    assert _notification_count(app_ctx, seller_id) == 1
    assert _notification_count(app_ctx, other_seller_id) == 0
    assert _notification_count(app_ctx, admin_id) == 0


def test_patch_hide_sends_fcm_push_with_car_id(app_ctx):
    app, _socketio, client, db, User, Car, Notification = app_ctx
    admin_id, admin_username, _ap = _make_user(app_ctx, tag="admin7", is_admin=True)
    seller_id, _sn, _sp = _make_user(app_ctx, tag="seller7", firebase_token="tok-b3mod-1")
    _car_id, car_pub = _make_car(app_ctx, seller_id=seller_id, tag="push1", status="active", is_active=True)

    token = _login(client, admin_username)
    with mock.patch("firebase_admin.messaging.send", return_value="projects/test/messages/fake") as send_mock:
        resp = client.patch(
            f"/api/admin/cars/{car_pub}/status",
            json={"is_active": False, "status": "hidden"},
            headers=_auth(token),
        )
    assert resp.status_code == 200, resp.data
    send_mock.assert_called_once()
    sent_message = send_mock.call_args[0][0]
    assert sent_message.token == "tok-b3mod-1"
    assert sent_message.data["car_id"] == car_pub
    assert sent_message.data["type"] == "listing_status"
    assert sent_message.data["status"] == "hidden"


# ---------------------------------------------------------------------------
# POST /api/admin/cars/bulk-status
# ---------------------------------------------------------------------------


def test_bulk_hide_notifies_each_affected_seller_only(app_ctx):
    app, _socketio, client, db, User, Car, Notification = app_ctx
    admin_id, admin_username, _ap = _make_user(app_ctx, tag="admin8", is_admin=True)
    seller_a_id, _san, _sap = _make_user(app_ctx, tag="bulkA")
    seller_b_id, _sbn, _sbp = _make_user(app_ctx, tag="bulkB")
    _car_a_id, car_a_pub = _make_car(app_ctx, seller_id=seller_a_id, tag="bulkcarA", status="active", is_active=True)
    _car_b_id, car_b_pub = _make_car(app_ctx, seller_id=seller_b_id, tag="bulkcarB", status="active", is_active=True)

    token = _login(client, admin_username)
    resp = client.post(
        "/api/admin/cars/bulk-status",
        json={"ids": [car_a_pub, car_b_pub], "is_active": False, "status": "hidden"},
        headers=_auth(token),
    )
    assert resp.status_code == 200, resp.data

    assert _notification_count(app_ctx, seller_a_id) == 1
    assert _notification_count(app_ctx, seller_b_id) == 1
    notif_a = _latest_notification(app_ctx, seller_a_id)
    notif_b = _latest_notification(app_ctx, seller_b_id)
    assert notif_a.data["car_id"] == car_a_pub
    assert notif_b.data["car_id"] == car_b_pub


def test_bulk_hide_with_reason_applies_verbatim_to_all(app_ctx):
    app, _socketio, client, db, User, Car, Notification = app_ctx
    admin_id, admin_username, _ap = _make_user(app_ctx, tag="admin9", is_admin=True)
    seller_a_id, _san, _sap = _make_user(app_ctx, tag="bulkreasonA")
    _car_a_id, car_a_pub = _make_car(app_ctx, seller_id=seller_a_id, tag="bulkreasoncarA", status="active", is_active=True)

    token = _login(client, admin_username)
    reason = "Bulk moderation sweep: incomplete VIN info."
    resp = client.post(
        "/api/admin/cars/bulk-status",
        json={"ids": [car_a_pub], "is_active": False, "status": "hidden", "reason": reason},
        headers=_auth(token),
    )
    assert resp.status_code == 200, resp.data

    notif = _latest_notification(app_ctx, seller_a_id)
    assert notif.message == reason


def test_bulk_no_visibility_change_does_not_notify(app_ctx):
    app, _socketio, client, db, User, Car, Notification = app_ctx
    admin_id, admin_username, _ap = _make_user(app_ctx, tag="admin10", is_admin=True)
    seller_id, _sn, _sp = _make_user(app_ctx, tag="bulknodup")
    _car_id, car_pub = _make_car(app_ctx, seller_id=seller_id, tag="bulknodupcar", status="active", is_active=True)

    token = _login(client, admin_username)
    resp = client.post(
        "/api/admin/cars/bulk-status",
        json={"ids": [car_pub], "is_featured": True},
        headers=_auth(token),
    )
    assert resp.status_code == 200, resp.data
    assert _notification_count(app_ctx, seller_id) == 0


# ---------------------------------------------------------------------------
# DELETE /api/admin/cars/<id> (soft-delete / "removed")
# ---------------------------------------------------------------------------


def test_delete_active_listing_notifies_removed_without_car_id(app_ctx):
    app, _socketio, client, db, User, Car, Notification = app_ctx
    admin_id, admin_username, _ap = _make_user(app_ctx, tag="admin11", is_admin=True)
    seller_id, _sn, _sp = _make_user(app_ctx, tag="deleteA", locale="ar")
    _car_id, car_pub = _make_car(app_ctx, seller_id=seller_id, tag="deletecarA", status="active", is_active=True)

    token = _login(client, admin_username)
    resp = client.delete(f"/api/admin/cars/{car_pub}", headers=_auth(token))
    assert resp.status_code == 200, resp.data

    notif = _latest_notification(app_ctx, seller_id)
    assert notif is not None
    assert notif.title == "تمت إزالة الإعلان"
    assert notif.message == "تمت إزالة إعلانك من قبل فريق المراجعة لدينا."
    assert notif.data["status"] == "removed"
    # Never deep-link into a now-gone listing.
    assert "car_id" not in notif.data


def test_delete_already_hidden_listing_does_not_duplicate_notification(app_ctx):
    """Deleting a listing that was already hidden by a prior moderation
    action changes nothing about its visibility -- no 'removed'
    notification should fire on top of the earlier 'hidden' one."""
    app, _socketio, client, db, User, Car, Notification = app_ctx
    admin_id, admin_username, _ap = _make_user(app_ctx, tag="admin12", is_admin=True)
    seller_id, _sn, _sp = _make_user(app_ctx, tag="deleteB")
    _car_id, car_pub = _make_car(app_ctx, seller_id=seller_id, tag="deletecarB", status="hidden", is_active=False)

    token = _login(client, admin_username)
    resp = client.delete(f"/api/admin/cars/{car_pub}", headers=_auth(token))
    assert resp.status_code == 200, resp.data

    # The car was already hidden -- no notification of any kind (hidden or
    # removed) is expected from this delete call.
    assert _notification_count(app_ctx, seller_id) == 0


def test_delete_pending_listing_notifies_removed(app_ctx):
    """A never-yet-approved listing being deleted still counts as
    "removed" -- it goes from a non-hidden bucket to gone."""
    app, _socketio, client, db, User, Car, Notification = app_ctx
    admin_id, admin_username, _ap = _make_user(app_ctx, tag="admin13", is_admin=True)
    seller_id, _sn, _sp = _make_user(app_ctx, tag="deleteC")
    _car_id, car_pub = _make_car(app_ctx, seller_id=seller_id, tag="deletecarC", status="pending", is_active=True)

    token = _login(client, admin_username)
    resp = client.delete(f"/api/admin/cars/{car_pub}", headers=_auth(token))
    assert resp.status_code == 200, resp.data

    notif = _latest_notification(app_ctx, seller_id)
    assert notif is not None
    assert notif.data["status"] == "removed"
    assert "car_id" not in notif.data
