"""Security Batch 1B — listing/media ownership must not trust User.is_admin.

Mobile JWTs (password or phone OTP) must never edit another seller's listing,
view private media summaries, or self-approve moderated listings merely because
``User.is_admin`` is true. Dashboard AdminAccount sessions retain intended
cross-listing moderation via privileged JWT claims.
"""

from __future__ import annotations

import os
import sys
import tempfile
import uuid
from pathlib import Path

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

_PASSWORD = "Aa123456!"


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(
        prefix="carlist_sec_b1b_", ignore_cleanup_errors=True
    )
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ["LISTING_REQUIRE_APPROVAL"] = "1"
    os.environ.pop("REDIS_URL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "sec_b1b.db")

    from kk.app_factory import create_app

    app, *_ = create_app()
    from kk.models import User, db

    with app.app_context():
        db.drop_all()
        db.create_all()

    yield app, app.test_client(), db, User

    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    tmp.cleanup()
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)


@pytest.fixture
def client(app_ctx):
    return app_ctx[1]


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _phone() -> str:
    return f"077{uuid.uuid4().int % 10**8:08d}"


def _make_user(app_ctx, *, is_admin: bool = False, username: str | None = None):
    app, _client, db, User = app_ctx
    username = username or f"u_{uuid.uuid4().hex[:10]}"
    with app.app_context():
        user = User(
            username=username,
            phone_number=_phone(),
            first_name="Sec",
            last_name="B1B",
            is_active=True,
            is_verified=True,
            phone_verified=True,
            is_admin=is_admin,
            public_id=f"pub-{uuid.uuid4().hex[:12]}",
        )
        user.set_password(_PASSWORD)
        db.session.add(user)
        db.session.commit()
        return {
            "id": user.id,
            "public_id": user.public_id,
            "username": username,
            "phone": user.phone_number,
        }


def _make_dashboard_admin(app_ctx):
    from kk.tests.admin_auth_helpers import attach_admin_account

    app, _client, db, User = app_ctx
    username = f"dash_{uuid.uuid4().hex[:10]}"
    with app.app_context():
        principal = User(
            username=f"{username}_p",
            phone_number=_phone(),
            first_name="Dash",
            last_name="Admin",
            is_active=True,
            is_verified=True,
            phone_verified=True,
            is_admin=True,
            public_id=f"pub-{uuid.uuid4().hex[:12]}",
        )
        principal.set_password(uuid.uuid4().hex)
        db.session.add(principal)
        db.session.commit()
        attach_admin_account(db, principal, password=_PASSWORD, username=username)
    return {"username": username, "password": _PASSWORD}


def _make_car(app_ctx, seller_id: int, *, status: str = "active", is_active: bool = True):
    app, _client, db, _User = app_ctx
    from kk.models import Car

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
            contact_phone="07701112233",
            is_active=is_active,
            status=status,
            title="Batch1B Test Car",
            # Ready so dashboard activation is not blocked by media gate.
            media_status="ready",
        )
        db.session.add(car)
        db.session.commit()
        return {"id": car.id, "public_id": car.public_id, "status": car.status}


def _mobile_login(client, username: str) -> str:
    resp = client.post(
        "/api/auth/login",
        json={"username": username, "password": _PASSWORD},
    )
    assert resp.status_code == 200, resp.data
    return resp.get_json()["access_token"]


def _dashboard_login(client, username: str, password: str = _PASSWORD) -> str:
    from kk.tests.admin_auth_helpers import login_with_admin_scope

    return login_with_admin_scope(client, username, password)


# ---------------------------------------------------------------------------
# Ownership: sellers vs other sellers vs mobile is_admin
# ---------------------------------------------------------------------------


def test_b1b_owner_can_update_own_listing(app_ctx, client):
    owner = _make_user(app_ctx)
    car = _make_car(app_ctx, owner["id"], status="active")
    token = _mobile_login(client, owner["username"])

    resp = client.put(
        f"/api/cars/{car['public_id']}",
        headers=_auth(token),
        json={"price": 16000, "location": "Sulaymaniyah"},
    )
    assert resp.status_code == 200, resp.data
    assert float(resp.get_json()["car"]["price"]) == 16000


def test_b1b_seller_cannot_update_other_sellers_listing(app_ctx, client):
    owner = _make_user(app_ctx)
    other = _make_user(app_ctx)
    car = _make_car(app_ctx, owner["id"], status="active")
    token = _mobile_login(client, other["username"])

    resp = client.put(
        f"/api/cars/{car['public_id']}",
        headers=_auth(token),
        json={"price": 1},
    )
    assert resp.status_code == 403, resp.data


def test_b1b_mobile_is_admin_cannot_update_other_sellers_listing(app_ctx, client):
    owner = _make_user(app_ctx)
    mobile_admin = _make_user(app_ctx, is_admin=True)
    car = _make_car(app_ctx, owner["id"], status="active")
    token = _mobile_login(client, mobile_admin["username"])

    resp = client.put(
        f"/api/cars/{car['public_id']}",
        headers=_auth(token),
        json={"price": 1},
    )
    assert resp.status_code == 403, resp.data


def test_b1b_mobile_is_admin_cannot_delete_other_sellers_listing(app_ctx, client):
    owner = _make_user(app_ctx)
    mobile_admin = _make_user(app_ctx, is_admin=True)
    car = _make_car(app_ctx, owner["id"], status="active")
    token = _mobile_login(client, mobile_admin["username"])

    resp = client.delete(
        f"/api/cars/{car['public_id']}",
        headers=_auth(token),
    )
    assert resp.status_code == 403, resp.data


def test_b1b_mobile_is_admin_cannot_view_other_sellers_media_summary(app_ctx, client):
    owner = _make_user(app_ctx)
    mobile_admin = _make_user(app_ctx, is_admin=True)
    car = _make_car(app_ctx, owner["id"], status="active")
    token = _mobile_login(client, mobile_admin["username"])

    resp = client.get(
        f"/api/cars/{car['public_id']}/media-summary",
        headers=_auth(token),
    )
    assert resp.status_code == 403, resp.data


def test_b1b_mobile_is_admin_cannot_delete_other_sellers_image(app_ctx, client):
    app, _c, db, _User = app_ctx
    from kk.models import CarImage

    owner = _make_user(app_ctx)
    mobile_admin = _make_user(app_ctx, is_admin=True)
    car = _make_car(app_ctx, owner["id"], status="active")
    with app.app_context():
        img = CarImage(
            car_id=car["id"],
            image_url="https://cdn.example.test/owner-only.jpg",
            is_primary=True,
            kind="listing",
        )
        db.session.add(img)
        db.session.commit()
        image_id = img.id
    token = _mobile_login(client, mobile_admin["username"])

    resp = client.delete(
        f"/api/cars/{car['public_id']}/images/{image_id}",
        headers=_auth(token),
    )
    assert resp.status_code == 403, resp.data


def test_b1b_mobile_is_admin_does_not_get_private_seller_fields(app_ctx, client):
    owner = _make_user(app_ctx)
    mobile_admin = _make_user(app_ctx, is_admin=True)
    car = _make_car(app_ctx, owner["id"], status="active")
    token = _mobile_login(client, mobile_admin["username"])

    resp = client.get(f"/api/cars/{car['public_id']}", headers=_auth(token))
    assert resp.status_code == 200, resp.data
    body = resp.get_json()["car"]
    # Public listing view may expose contact_phone for the listing, but must
    # not escalate to owner-private seller payload via include_private.
    seller = body.get("seller") or {}
    assert "phone_number" not in seller
    assert "email" not in seller or seller.get("email") in (None, "")


def test_b1b_mobile_is_admin_cannot_self_approve_pending_listing(app_ctx, client):
    mobile_admin = _make_user(app_ctx, is_admin=True)
    car = _make_car(app_ctx, mobile_admin["id"], status="pending")
    token = _mobile_login(client, mobile_admin["username"])

    resp = client.put(
        f"/api/cars/{car['public_id']}",
        headers=_auth(token),
        json={"status": "active"},
    )
    assert resp.status_code == 403, resp.data
    assert "review" in (resp.get_json() or {}).get("message", "").lower()


def test_b1b_ordinary_seller_cannot_self_approve_pending_listing(app_ctx, client):
    owner = _make_user(app_ctx)
    car = _make_car(app_ctx, owner["id"], status="pending")
    token = _mobile_login(client, owner["username"])

    resp = client.put(
        f"/api/cars/{car['public_id']}",
        headers=_auth(token),
        json={"status": "active"},
    )
    assert resp.status_code == 403, resp.data


def test_b1b_mobile_is_admin_cannot_see_other_sellers_pending_listing(
    app_ctx, client
):
    owner = _make_user(app_ctx)
    mobile_admin = _make_user(app_ctx, is_admin=True)
    car = _make_car(app_ctx, owner["id"], status="pending")
    token = _mobile_login(client, mobile_admin["username"])

    resp = client.get(f"/api/cars/{car['public_id']}", headers=_auth(token))
    assert resp.status_code == 404, resp.data


# ---------------------------------------------------------------------------
# Dashboard AdminAccount retains intended moderation
# ---------------------------------------------------------------------------


def test_b1b_dashboard_admin_can_moderate_listing_status_via_admin_api(
    app_ctx, client
):
    owner = _make_user(app_ctx)
    car = _make_car(app_ctx, owner["id"], status="pending")
    admin = _make_dashboard_admin(app_ctx)
    token = _dashboard_login(client, admin["username"])

    resp = client.patch(
        f"/api/admin/cars/{car['public_id']}/status",
        headers=_auth(token),
        json={"status": "active"},
    )
    assert resp.status_code == 200, resp.data


def test_b1b_dashboard_admin_can_inspect_private_listing_via_admin_api(
    app_ctx, client
):
    owner = _make_user(app_ctx)
    car = _make_car(app_ctx, owner["id"], status="pending")
    admin = _make_dashboard_admin(app_ctx)
    token = _dashboard_login(client, admin["username"])

    resp = client.get(
        f"/api/admin/cars/{car['public_id']}",
        headers=_auth(token),
    )
    assert resp.status_code == 200, resp.data
    assert resp.get_json()["car"]["id"] == car["public_id"]


def test_b1b_dashboard_admin_can_view_pending_listing_on_public_detail(
    app_ctx, client
):
    """Privileged dashboard JWT may use GET /api/cars for inspect paths."""
    owner = _make_user(app_ctx)
    car = _make_car(app_ctx, owner["id"], status="pending")
    admin = _make_dashboard_admin(app_ctx)
    token = _dashboard_login(client, admin["username"])

    resp = client.get(f"/api/cars/{car['public_id']}", headers=_auth(token))
    assert resp.status_code == 200, resp.data


# ---------------------------------------------------------------------------
# Batch 1 protections remain
# ---------------------------------------------------------------------------


def test_b1b_batch1_mobile_is_admin_still_cannot_hit_admin_api(app_ctx, client):
    mobile_admin = _make_user(app_ctx, is_admin=True)
    token = _mobile_login(client, mobile_admin["username"])
    resp = client.get("/api/admin/users", headers=_auth(token))
    assert resp.status_code == 403, resp.data
