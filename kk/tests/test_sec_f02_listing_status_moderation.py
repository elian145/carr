"""Pre-launch audit F-02: a seller must not be able to make an unapproved or
admin-hidden listing publicly visible by changing its availability status.

``active`` and ``sold`` are the only PUBLIC listing statuses. ``pending`` /
``hidden`` / ``draft`` are owner-or-admin only. Before the fix:

  * ``POST /api/cars/<id>/mark-sold`` had no status guard, so any seller could
    move a pending/hidden/draft listing straight to ``sold`` (public), and
    ``mark-active`` (which accepts ``sold``) then made it ``active``;
  * ``PUT /api/cars/<id>`` with ``{"status": "sold"}`` did the same -- its
    "sellers cannot self-approve" guard only blocked the literal ``active``.

Availability changes (active <-> sold) are legitimate for APPROVED listings
and must keep working. Dashboard admins keep their moderation powers.

All data below is disposable (per-module temp SQLite, fake phones).
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
_UNAPPROVED = ("pending", "hidden", "draft")


def _local_pg_url() -> str | None:
    """``CARNET_SEC_PG_URL`` opts this module into a disposable LOCAL
    PostgreSQL (tables are dropped and re-created). Anything non-local is
    refused so ambient production/Neon credentials can never be used."""
    from urllib.parse import urlparse

    url = (os.environ.get("CARNET_SEC_PG_URL") or "").strip()
    if not url:
        return None
    if urlparse(url).hostname not in ("127.0.0.1", "localhost"):
        raise RuntimeError("CARNET_SEC_PG_URL must point at a local server")
    return url


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(
        prefix="carlist_sec_f02_", ignore_cleanup_errors=True
    )
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ["LISTING_REQUIRE_APPROVAL"] = "1"
    prev_db_url = os.environ.pop("DATABASE_URL", None)
    pg_url = _local_pg_url()
    if pg_url:
        os.environ["DATABASE_URL"] = pg_url
    os.environ.pop("REDIS_URL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "sec_f02.db")

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
    os.environ.pop("DATABASE_URL", None)
    if prev_db_url is not None:
        os.environ["DATABASE_URL"] = prev_db_url


@pytest.fixture
def client(app_ctx):
    return app_ctx[1]


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _phone() -> str:
    return f"077{uuid.uuid4().int % 10**8:08d}"


def _make_user(app_ctx, *, is_admin: bool = False) -> dict:
    app, _c, db, User = app_ctx
    username = f"u_{uuid.uuid4().hex[:10]}"
    with app.app_context():
        user = User(
            username=username,
            phone_number=_phone(),
            first_name="Sec",
            last_name="F02",
            is_active=True,
            is_verified=True,
            phone_verified=True,
            is_admin=is_admin,
            public_id=f"pub-{uuid.uuid4().hex[:12]}",
        )
        user.set_password(_PASSWORD)
        db.session.add(user)
        db.session.commit()
        return {"id": user.id, "username": username}


def _make_car(app_ctx, seller_id: int, *, status: str | None, is_active: bool = True):
    app, _c, db, _U = app_ctx
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
            title="F02 Test Car",
            media_status="ready",
        )
        db.session.add(car)
        db.session.commit()
        return car.public_id


def _db_status(app_ctx, public_id: str) -> str | None:
    app, _c, db, _U = app_ctx
    from kk.models import Car

    with app.app_context():
        return Car.query.filter_by(public_id=public_id).one().status


def _login(client, username: str) -> str:
    r = client.post(
        "/api/auth/login", json={"username": username, "password": _PASSWORD}
    )
    assert r.status_code == 200, r.data
    return r.get_json()["access_token"]


def _dashboard_token(app_ctx, client) -> str:
    from kk.tests.admin_auth_helpers import attach_admin_account, login_with_admin_scope

    app, _c, db, User = app_ctx
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
    return login_with_admin_scope(client, username, _PASSWORD)


def _publicly_visible(client, public_id: str) -> bool:
    """Anonymous detail fetch AND anonymous browse listing."""
    detail = client.get(f"/api/cars/{public_id}")
    browse = client.get("/api/cars?per_page=200")
    in_browse = False
    if browse.status_code == 200:
        body = browse.get_json()
        items = body.get("cars", body) if isinstance(body, dict) else body
        in_browse = any(
            (c.get("id") == public_id or c.get("public_id") == public_id)
            for c in (items or [])
        )
    return detail.status_code == 200 or in_browse


# ---------------------------------------------------------------------------
# The bypass, every route
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("status", _UNAPPROVED)
def test_f02_mark_sold_is_refused_for_unapproved_listing(app_ctx, client, status):
    owner = _make_user(app_ctx)
    car = _make_car(app_ctx, owner["id"], status=status)
    token = _login(client, owner["username"])

    r = client.post(f"/api/cars/{car}/mark-sold", headers=_auth(token))
    assert r.status_code == 403, r.data
    assert _db_status(app_ctx, car) == status
    assert not _publicly_visible(client, car)


@pytest.mark.parametrize("status", _UNAPPROVED)
def test_f02_put_status_sold_is_refused_for_unapproved_listing(
    app_ctx, client, status
):
    owner = _make_user(app_ctx)
    car = _make_car(app_ctx, owner["id"], status=status)
    token = _login(client, owner["username"])

    r = client.put(
        f"/api/cars/{car}", headers=_auth(token), json={"status": "sold"}
    )
    assert r.status_code == 403, r.data
    assert _db_status(app_ctx, car) == status
    assert not _publicly_visible(client, car)


@pytest.mark.parametrize("status", _UNAPPROVED)
def test_f02_put_status_active_is_refused_for_unapproved_listing(
    app_ctx, client, status
):
    owner = _make_user(app_ctx)
    car = _make_car(app_ctx, owner["id"], status=status)
    token = _login(client, owner["username"])

    r = client.put(
        f"/api/cars/{car}", headers=_auth(token), json={"status": "active"}
    )
    assert r.status_code == 403, r.data
    assert _db_status(app_ctx, car) == status


@pytest.mark.parametrize("status", _UNAPPROVED)
def test_f02_mark_active_is_refused_for_unapproved_listing(app_ctx, client, status):
    owner = _make_user(app_ctx)
    car = _make_car(app_ctx, owner["id"], status=status)
    token = _login(client, owner["username"])

    r = client.post(f"/api/cars/{car}/mark-active", headers=_auth(token))
    assert r.status_code == 403, r.data
    assert _db_status(app_ctx, car) == status


@pytest.mark.parametrize("status", _UNAPPROVED)
def test_f02_full_sold_then_active_chain_cannot_publish(app_ctx, client, status):
    """The reported chain: mark-sold, then mark-active, then check public."""
    owner = _make_user(app_ctx)
    car = _make_car(app_ctx, owner["id"], status=status)
    token = _login(client, owner["username"])

    client.post(f"/api/cars/{car}/mark-sold", headers=_auth(token))
    client.post(f"/api/cars/{car}/mark-active", headers=_auth(token))
    client.put(f"/api/cars/{car}", headers=_auth(token), json={"status": "sold"})
    client.put(f"/api/cars/{car}", headers=_auth(token), json={"status": "active"})

    assert _db_status(app_ctx, car) == status
    assert not _publicly_visible(client, car)


def test_f02_mixed_content_and_status_put_cannot_publish_hidden_listing(
    app_ctx, client
):
    """A PUT mixing an edit with status=sold must not publish either."""
    owner = _make_user(app_ctx)
    car = _make_car(app_ctx, owner["id"], status="hidden")
    token = _login(client, owner["username"])

    r = client.put(
        f"/api/cars/{car}",
        headers=_auth(token),
        json={"status": "sold", "price": 1},
    )
    assert r.status_code == 403, r.data
    assert _db_status(app_ctx, car) == "hidden"
    assert not _publicly_visible(client, car)


def test_f02_mobile_user_is_admin_flag_does_not_bypass(app_ctx, client):
    """`User.is_admin` on a mobile login is not a dashboard admin (Batch 1B)."""
    owner = _make_user(app_ctx, is_admin=True)
    car = _make_car(app_ctx, owner["id"], status="pending")
    token = _login(client, owner["username"])

    assert (
        client.post(f"/api/cars/{car}/mark-sold", headers=_auth(token)).status_code
        == 403
    )
    assert _db_status(app_ctx, car) == "pending"


def test_f02_other_seller_cannot_change_status_at_all(app_ctx, client):
    owner = _make_user(app_ctx)
    other = _make_user(app_ctx)
    car = _make_car(app_ctx, owner["id"], status="active")
    token = _login(client, other["username"])

    assert (
        client.post(f"/api/cars/{car}/mark-sold", headers=_auth(token)).status_code
        == 403
    )
    assert _db_status(app_ctx, car) == "active"


# ---------------------------------------------------------------------------
# Legitimate behaviour is preserved
# ---------------------------------------------------------------------------


def test_f02_approved_listing_can_be_marked_sold_then_active(app_ctx, client):
    owner = _make_user(app_ctx)
    car = _make_car(app_ctx, owner["id"], status="active")
    token = _login(client, owner["username"])

    sold = client.post(f"/api/cars/{car}/mark-sold", headers=_auth(token))
    assert sold.status_code == 200, sold.data
    assert _db_status(app_ctx, car) == "sold"
    assert _publicly_visible(client, car)  # sold is a public status

    back = client.post(f"/api/cars/{car}/mark-active", headers=_auth(token))
    assert back.status_code == 200, back.data
    assert _db_status(app_ctx, car) == "active"
    assert _publicly_visible(client, car)


def test_f02_approved_listing_status_via_put_still_works(app_ctx, client):
    owner = _make_user(app_ctx)
    car = _make_car(app_ctx, owner["id"], status="active")
    token = _login(client, owner["username"])

    r = client.put(f"/api/cars/{car}", headers=_auth(token), json={"status": "sold"})
    assert r.status_code == 200, r.data
    assert _db_status(app_ctx, car) == "sold"
    r = client.put(
        f"/api/cars/{car}", headers=_auth(token), json={"status": "active"}
    )
    assert r.status_code == 200, r.data
    assert _db_status(app_ctx, car) == "active"


def test_f02_legacy_null_status_listing_is_treated_as_active(app_ctx, client):
    owner = _make_user(app_ctx)
    car = _make_car(app_ctx, owner["id"], status=None)
    token = _login(client, owner["username"])

    r = client.post(f"/api/cars/{car}/mark-sold", headers=_auth(token))
    assert r.status_code == 200, r.data
    assert _db_status(app_ctx, car) == "sold"


def test_f02_invalid_status_values_still_rejected(app_ctx, client):
    owner = _make_user(app_ctx)
    car = _make_car(app_ctx, owner["id"], status="active")
    token = _login(client, owner["username"])

    for bad in ("hidden", "pending", "draft", "revision", "bogus"):
        r = client.put(
            f"/api/cars/{car}", headers=_auth(token), json={"status": bad}
        )
        assert r.status_code == 400, (bad, r.data)
    assert _db_status(app_ctx, car) == "active"


def test_f02_seller_regains_control_after_admin_approval(app_ctx, client):
    owner = _make_user(app_ctx)
    car = _make_car(app_ctx, owner["id"], status="pending")
    token = _login(client, owner["username"])
    admin = _dashboard_token(app_ctx, client)

    assert (
        client.post(f"/api/cars/{car}/mark-sold", headers=_auth(token)).status_code
        == 403
    )
    approve = client.patch(
        f"/api/admin/cars/{car}/status",
        headers=_auth(admin),
        json={"status": "active"},
    )
    assert approve.status_code == 200, approve.data
    assert (
        client.post(f"/api/cars/{car}/mark-sold", headers=_auth(token)).status_code
        == 200
    )
    assert _db_status(app_ctx, car) == "sold"


def test_f02_admin_hiding_a_sold_listing_blocks_the_seller_from_republishing(
    app_ctx, client
):
    owner = _make_user(app_ctx)
    car = _make_car(app_ctx, owner["id"], status="sold")
    token = _login(client, owner["username"])
    admin = _dashboard_token(app_ctx, client)

    hide = client.patch(
        f"/api/admin/cars/{car}/status",
        headers=_auth(admin),
        json={"status": "hidden"},
    )
    assert hide.status_code == 200, hide.data
    assert not _publicly_visible(client, car)

    for call in (
        lambda: client.post(f"/api/cars/{car}/mark-active", headers=_auth(token)),
        lambda: client.post(f"/api/cars/{car}/mark-sold", headers=_auth(token)),
        lambda: client.put(
            f"/api/cars/{car}", headers=_auth(token), json={"status": "active"}
        ),
        lambda: client.put(
            f"/api/cars/{car}", headers=_auth(token), json={"status": "sold"}
        ),
    ):
        assert call().status_code == 403
    assert _db_status(app_ctx, car) == "hidden"
    assert not _publicly_visible(client, car)


def test_f02_dashboard_admin_moderation_powers_are_unchanged(app_ctx, client):
    owner = _make_user(app_ctx)
    car = _make_car(app_ctx, owner["id"], status="hidden")
    admin = _dashboard_token(app_ctx, client)

    r = client.patch(
        f"/api/admin/cars/{car}/status",
        headers=_auth(admin),
        json={"status": "active"},
    )
    assert r.status_code == 200, r.data
    assert _db_status(app_ctx, car) == "active"
    assert _publicly_visible(client, car)


# ---------------------------------------------------------------------------
# Legacy status edge cases: only a value the public queries already treat as
# approved may ever be toggled by the seller.
# ---------------------------------------------------------------------------


class _Stub:
    def __init__(self, status):
        self.status = status


def test_f02_legacy_null_status_is_public_and_toggleable():
    """The DB column is NOT NULL on PostgreSQL (alembic initial revision);
    old SQLite instance DBs could hold NULL. Python and SQL public filters
    already treat NULL as active, so allowing the toggle cannot expose
    anything that was hidden."""
    from kk.listing_visibility import listing_is_public
    from kk.routes.cars import _availability_change_blocked

    stub = _Stub(None)
    assert listing_is_public(stub)
    assert _availability_change_blocked(stub) is None


@pytest.mark.parametrize("status", ["active", "sold"])
def test_f02_public_statuses_are_toggleable(status):
    from kk.routes.cars import _availability_change_blocked

    assert _availability_change_blocked(_Stub(status)) is None


@pytest.mark.parametrize(
    "status", ["pending", "hidden", "draft", "revision", "", "Active", " active", "SOLD", "rejected"]
)
def test_f02_every_other_or_malformed_status_is_not_seller_toggleable(app_ctx, status):
    """Exact comparison: anything the public SQL filter would not show as
    public (empty string, odd casing, unknown values) must not be promotable
    to a public status by the seller."""
    from kk.routes.cars import _availability_change_blocked

    app = app_ctx[0]
    with app.app_context():
        blocked = _availability_change_blocked(_Stub(status))
    assert blocked is not None
    assert blocked[1] in (400, 403)
