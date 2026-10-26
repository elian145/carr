"""Pre-launch audit F-01 / F-03: nothing an unauthenticated caller sends to the
phone-OTP *start* endpoints may take effect before OTP ownership is proven.

F-01 (pre-signup account takeover)
    ``POST /api/auth/phone/start`` for an unknown phone number created an
    unverified account and stored the caller-supplied ``password``.
    ``POST /api/auth/login`` never checked phone verification, so the
    attacker could (a) log in immediately and (b) keep the password after the
    real owner later proved the number with their OTP. Fixed by:
      * never accepting a password at account creation (random credential),
      * refusing password login for accounts whose phone was never verified,
      * rotating the password + revoking every token issued before the first
        successful OTP verification (covers rows planted before the fix).

F-03 (unauthenticated dealer tampering)
    ``phone/start`` with ``is_dealer`` + dealership fields flipped an
    EXISTING user's ``dealer_status`` to ``pending`` (creating a
    ``DealerApplication``) before any OTP check, and then locked that user out
    of personal login (409 ``dealer_account_exists``). Fixed by never touching
    an existing row, and never persisting dealer data for a new row, until the
    OTP is verified (``phone/verify`` and ``/auth/signup`` already apply it
    after the code is consumed).

Every user in this module is disposable, lives in a per-module temporary
SQLite file, and uses a fake phone number. SMS_PROVIDER=console: nothing is
ever sent.
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

ATTACKER_PW = "Attacker#Pass1"
OWNER_PW = "Owner#Pass123"

DEALER_FIELDS = {
    "is_dealer": True,
    "dealership_name": "Evil Motors",
    "dealership_phone": "07700000001",
    "dealership_location": "Erbil",
}


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
        prefix="carlist_sec_f01_f03_", ignore_cleanup_errors=True
    )
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ["ALLOW_DEV_CODE_IN_RESPONSE"] = "1"
    prev_db_url = os.environ.pop("DATABASE_URL", None)
    pg_url = _local_pg_url()
    if pg_url:
        os.environ["DATABASE_URL"] = pg_url
    os.environ.pop("REDIS_URL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "sec_f01_f03.db")

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
    os.environ.pop("ALLOW_DEV_CODE_IN_RESPONSE", None)
    os.environ.pop("DATABASE_URL", None)
    if prev_db_url is not None:
        os.environ["DATABASE_URL"] = prev_db_url


@pytest.fixture
def client(app_ctx):
    return app_ctx[1]


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------


def _phone() -> str:
    return f"075{uuid.uuid4().int % 10**8:08d}"


def _make_user(
    app_ctx,
    *,
    verified: bool,
    password: str = OWNER_PW,
    dealer_status: str = "none",
    account_type: str = "user",
) -> dict:
    app, _c, db, User = app_ctx
    phone = _phone()
    with app.app_context():
        user = User(
            username=f"sec_{uuid.uuid4().hex[:10]}",
            phone_number=phone,
            first_name="Disposable",
            last_name="User",
            is_active=True,
            is_verified=verified,
            phone_verified=verified,
            public_id=f"pub-{uuid.uuid4().hex[:12]}",
            account_type=account_type,
            dealer_status=dealer_status,
        )
        user.set_password(password)
        db.session.add(user)
        db.session.commit()
        return {"id": user.id, "phone": phone, "username": user.username}


def _expire_resend_cooldown(app_ctx, phone: str) -> None:
    """Skip the 60s OTP resend cooldown (never sleep in tests)."""
    app, _c, db, User = app_ctx
    with app.app_context():
        u = User.query.filter_by(phone_number=phone).one()
        u.phone_verification_last_sent_at = u.phone_verification_last_sent_at and (
            u.phone_verification_last_sent_at - timedelta(minutes=5)
        )
        db.session.commit()


def _start(client, phone: str, **extra):
    body = {"phone_number": phone}
    body.update(extra)
    return client.post("/api/auth/phone/start", json=body)


def _start_code(client, phone: str, **extra) -> str:
    r = _start(client, phone, **extra)
    assert r.status_code == 200, r.data
    code = r.get_json().get("dev_code")
    assert code and len(code) == 6
    return code


def _verify(client, phone: str, code: str, **extra):
    body = {"phone_number": phone, "code": code}
    body.update(extra)
    return client.post("/api/auth/phone/verify", json=body)


def _pw_login(client, ident: str, password: str):
    return client.post(
        "/api/auth/login", json={"username": ident, "password": password}
    )


def _row(app_ctx, phone: str) -> dict | None:
    app, _c, db, User = app_ctx
    with app.app_context():
        u = User.query.filter_by(phone_number=phone).first()
        if u is None:
            return None
        from kk.models import DealerApplication

        return {
            "id": u.id,
            "phone_verified": bool(u.phone_verified),
            "is_verified": bool(u.is_verified),
            "dealer_status": u.dealer_status,
            "account_type": u.account_type,
            "dealership_name": u.dealership_name,
            "dealership_phone": u.dealership_phone,
            "dealership_location": u.dealership_location,
            "applications": DealerApplication.query.filter_by(user_id=u.id).count(),
            "tokens_invalid_before": u.tokens_invalid_before,
        }


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


# ---------------------------------------------------------------------------
# F-01 -- pre-signup account takeover
# ---------------------------------------------------------------------------


def test_f01_unknown_phone_start_with_password_grants_no_password_login(
    app_ctx, client
):
    """The exact attack: plant an account for a phone you do not own, then log
    in with the password you chose. Must not yield tokens."""
    phone = _phone()
    _start_code(client, phone, password=ATTACKER_PW, create_if_missing=True)

    r = _pw_login(client, phone, ATTACKER_PW)
    assert r.status_code == 401, r.data
    assert "access_token" not in (r.get_json() or {})


def test_f01_attacker_password_does_not_survive_owner_otp_verification(
    app_ctx, client
):
    """Full takeover chain: attacker plants -> real owner verifies by OTP ->
    attacker's password must not open the (now verified) account."""
    phone = _phone()
    _start_code(client, phone, password=ATTACKER_PW)
    pre = _pw_login(client, phone, ATTACKER_PW)  # on the vulnerable build: 200
    pre_token = (pre.get_json() or {}).get("access_token")

    _expire_resend_cooldown(app_ctx, phone)
    owner_code = _start_code(client, phone)  # real owner asks for a code
    v = _verify(client, phone, owner_code)
    assert v.status_code == 200, v.data
    assert _row(app_ctx, phone)["phone_verified"] is True

    post = _pw_login(client, phone, ATTACKER_PW)
    assert post.status_code == 401, post.data

    if pre_token:  # only reachable on a vulnerable build
        me = client.get("/api/auth/me", headers=_auth(pre_token))
        assert me.status_code == 401, "pre-verification token must be revoked"


def test_f01_unverified_account_cannot_password_login_even_with_right_password(
    app_ctx, client
):
    """Defence in depth + rows already planted before the fix: a never-
    verified account refuses password login, with the same generic 401 a wrong
    password gets (no signal that the row exists / is unverified)."""
    u = _make_user(app_ctx, verified=False, password=ATTACKER_PW)
    good = _pw_login(client, u["phone"], ATTACKER_PW)
    bad = _pw_login(client, u["phone"], "definitely-wrong-pw")
    assert good.status_code == 401, good.data
    assert bad.status_code == 401
    assert good.get_json() == bad.get_json()


def test_f01_preplanted_password_and_token_are_revoked_on_first_verification(
    app_ctx, client
):
    """Simulates a row planted BEFORE this fix shipped (unverified, attacker
    password, attacker token). The real owner's first OTP verification must
    invalidate both."""
    from kk.routes.auth import _access_token_for_user

    u = _make_user(app_ctx, verified=False, password=ATTACKER_PW)
    app, _c, _db, User = app_ctx
    with app.app_context():
        user = User.query.filter_by(id=u["id"]).one()
        planted_token = _access_token_for_user(user, auth_method="password")
    # Make sure the planted token is strictly older than the verification
    # second (JWT iat has 1s resolution).
    import time

    time.sleep(1.1)

    code = _start_code(client, u["phone"])
    v = _verify(client, u["phone"], code)
    assert v.status_code == 200, v.data
    new_token = v.get_json()["access_token"]

    assert _pw_login(client, u["phone"], ATTACKER_PW).status_code == 401
    assert (
        client.get("/api/auth/me", headers=_auth(planted_token)).status_code == 401
    ), "token issued before ownership was proven must be rejected"
    assert (
        client.get("/api/auth/me", headers=_auth(new_token)).status_code == 200
    ), "the owner's own fresh session must keep working"


def test_f01_legacy_verify_phone_endpoint_also_revokes_planted_password(
    app_ctx, client
):
    """`/api/auth/verify-phone` (authenticated-gate flow) is another first
    proof of ownership and must apply the same invalidation."""
    u = _make_user(app_ctx, verified=False, password=ATTACKER_PW)
    r = client.post("/api/auth/send-verification", json={"phone_number": u["phone"]})
    assert r.status_code == 200, r.data
    # send-verification does not echo the OTP on success; read the stored
    # hash's preimage by re-issuing through the helper the route uses.
    app, _c, db, User = app_ctx
    from kk.routes import auth as auth_routes

    with app.app_context():
        user = User.query.filter_by(id=u["id"]).one()
        user.phone_verification_code_hash = auth_routes._hash_phone_verification_code(
            u["phone"], "123456"
        )
        from kk.time_utils import utcnow

        user.phone_verification_expires_at = utcnow() + timedelta(minutes=10)
        db.session.commit()

    v = client.post(
        "/api/auth/verify-phone",
        json={"phone_number": u["phone"], "verification_code": "123456"},
    )
    assert v.status_code == 200, v.data
    assert _pw_login(client, u["phone"], ATTACKER_PW).status_code == 401


def test_f01_dealer_purpose_signup_also_ignores_password(app_ctx, client):
    phone = _phone()
    _start_code(client, phone, password=ATTACKER_PW, purpose="dealer")
    assert _pw_login(client, phone, ATTACKER_PW).status_code == 401


def test_f01_existing_verified_user_password_is_untouched_by_start(app_ctx, client):
    """Existing-account compatibility: an attacker's start() with a password
    must not alter a verified user's credentials, and the owner's own password
    login keeps working."""
    u = _make_user(app_ctx, verified=True, password=OWNER_PW)
    _start_code(client, u["phone"], password=ATTACKER_PW)

    assert _pw_login(client, u["phone"], ATTACKER_PW).status_code == 401
    ok = _pw_login(client, u["phone"], OWNER_PW)
    assert ok.status_code == 200, ok.data
    assert ok.get_json()["access_token"]


def test_f01_verified_user_otp_login_keeps_password_and_sessions(app_ctx, client):
    """Rotation must fire ONLY on the first verification, never on later OTP
    logins of an established account."""
    u = _make_user(app_ctx, verified=True, password=OWNER_PW)
    before = _pw_login(client, u["phone"], OWNER_PW).get_json()["access_token"]

    code = _start_code(client, u["phone"])
    v = _verify(client, u["phone"], code)
    assert v.status_code == 200, v.data

    assert _pw_login(client, u["phone"], OWNER_PW).status_code == 200
    assert client.get("/api/auth/me", headers=_auth(before)).status_code == 200
    assert _row(app_ctx, u["phone"])["tokens_invalid_before"] is None


def test_f01_legit_new_user_otp_signup_and_relogin(app_ctx, client):
    """Mobile app flow: start (no password) -> verify -> authenticated; then a
    later OTP login for the same number works."""
    phone = _phone()
    code = _start_code(client, phone, purpose="signup")
    v = _verify(client, phone, code, purpose="signup")
    assert v.status_code == 200, v.data
    body = v.get_json()
    assert body["access_token"] and body["refresh_token"]
    assert body["user"]["phone_verified"] is True
    assert (
        client.get("/api/auth/me", headers=_auth(body["access_token"])).status_code
        == 200
    )

    _expire_resend_cooldown(app_ctx, phone)
    code2 = _start_code(client, phone, purpose="login", create_if_missing=False)
    assert _verify(client, phone, code2, purpose="login").status_code == 200


def test_f01_legacy_otp_plus_signup_with_password_still_works(app_ctx, client):
    """send_otp -> /auth/signup(password, otp_code): the password is set AFTER
    the OTP is consumed, so password login must work for the owner."""
    phone = _phone()
    r = client.post("/api/auth/send_otp", json={"phone": phone})
    assert r.status_code == 200, r.data
    app, _c, db, User = app_ctx
    from kk.routes import auth as auth_routes
    from kk.time_utils import utcnow

    with app.app_context():
        user = User.query.filter_by(phone_number=phone).one()
        user.phone_verification_code_hash = auth_routes._hash_phone_verification_code(
            phone, "654321"
        )
        user.phone_verification_expires_at = utcnow() + timedelta(minutes=10)
        db.session.commit()

    s = client.post(
        "/api/auth/signup",
        json={
            "phone": phone,
            "otp_code": "654321",
            "password": OWNER_PW,
            "username": f"legit_{uuid.uuid4().hex[:8]}",
            "first_name": "Legit",
            "last_name": "Owner",
        },
    )
    assert s.status_code == 201, s.data
    login = _pw_login(client, phone, OWNER_PW)
    assert login.status_code == 200, login.data


def test_f01_signup_revokes_token_planted_before_ownership(app_ctx, client):
    """`/auth/signup` is a first proof of ownership too: a token an attacker
    obtained from a pre-fix planted row must die when the owner signs up."""
    from kk.routes.auth import _access_token_for_user
    from kk.routes import auth as auth_routes
    from kk.time_utils import utcnow
    import time

    u = _make_user(app_ctx, verified=False, password=ATTACKER_PW)
    app, _c, db, User = app_ctx
    with app.app_context():
        user = User.query.filter_by(id=u["id"]).one()
        planted = _access_token_for_user(user, auth_method="password")
    time.sleep(1.1)
    with app.app_context():
        user = User.query.filter_by(id=u["id"]).one()
        user.phone_verification_code_hash = auth_routes._hash_phone_verification_code(
            u["phone"], "111222"
        )
        user.phone_verification_expires_at = utcnow() + timedelta(minutes=10)
        db.session.commit()

    s = client.post(
        "/api/auth/signup",
        json={"phone": u["phone"], "otp_code": "111222", "password": OWNER_PW},
    )
    assert s.status_code == 201, s.data
    assert client.get("/api/auth/me", headers=_auth(planted)).status_code == 401
    assert _pw_login(client, u["phone"], ATTACKER_PW).status_code == 401
    assert _pw_login(client, u["phone"], OWNER_PW).status_code == 200


# ---------------------------------------------------------------------------
# F-03 -- unauthenticated dealer-account tampering
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("purpose", [None, "signup", "dealer"])
def test_f03_start_with_dealer_fields_does_not_touch_existing_personal_user(
    app_ctx, client, purpose
):
    u = _make_user(app_ctx, verified=(purpose != "dealer"))
    extra = dict(DEALER_FIELDS)
    if purpose:
        extra["purpose"] = purpose
    before = _row(app_ctx, u["phone"])

    r = _start(client, u["phone"], **extra)
    # The request itself may succeed (it only sends a code) or be refused;
    # either way no dealer state may change.
    assert r.status_code in (200, 409), r.data

    after = _row(app_ctx, u["phone"])
    assert after == before
    assert after["dealer_status"] == "none"
    assert after["applications"] == 0
    assert after["dealership_name"] is None


def test_f03_victim_can_still_log_in_personally_after_tampering_attempt(
    app_ctx, client
):
    u = _make_user(app_ctx, verified=True)
    _start(client, u["phone"], **DEALER_FIELDS)  # attacker, unauthenticated
    _expire_resend_cooldown(app_ctx, u["phone"])

    code = _start_code(client, u["phone"])  # the real owner, plain login
    v = _verify(client, u["phone"], code)
    assert v.status_code == 200, v.data
    assert v.get_json()["user"].get("account_type", "user") == "user"
    assert _row(app_ctx, u["phone"])["dealer_status"] == "none"


def test_f03_existing_approved_dealer_is_not_modified_by_start(app_ctx, client):
    u = _make_user(
        app_ctx, verified=True, dealer_status="approved", account_type="dealer"
    )
    before = _row(app_ctx, u["phone"])
    _start(client, u["phone"], purpose="dealer", **DEALER_FIELDS)
    assert _row(app_ctx, u["phone"]) == before


def test_f03_start_for_unknown_phone_persists_no_dealer_data_before_otp(
    app_ctx, client
):
    phone = _phone()
    _start_code(client, phone, **DEALER_FIELDS)

    row = _row(app_ctx, phone)
    assert row is not None and row["phone_verified"] is False
    assert row["dealer_status"] in ("none", "", None)
    assert row["applications"] == 0
    assert row["dealership_name"] is None


def test_f03_dealer_registration_is_applied_after_successful_otp(app_ctx, client):
    """Legitimate dealer registration is preserved: dealer data supplied to
    start/verify becomes a pending application once the OTP is proven."""
    phone = _phone()
    code = _start_code(client, phone, **DEALER_FIELDS)
    v = _verify(client, phone, code, **DEALER_FIELDS)
    assert v.status_code == 200, v.data

    row = _row(app_ctx, phone)
    assert row["phone_verified"] is True
    assert row["dealer_status"] == "pending"
    assert row["applications"] == 1
    assert row["dealership_name"] == DEALER_FIELDS["dealership_name"]
    assert row["account_type"] == "user"  # never auto-approved


def test_f03_wrong_otp_does_not_apply_dealer_fields(app_ctx, client):
    u = _make_user(app_ctx, verified=True)
    _start_code(client, u["phone"])
    before = _row(app_ctx, u["phone"])
    v = _verify(client, u["phone"], "000000", **DEALER_FIELDS)
    assert v.status_code == 400, v.data
    assert _row(app_ctx, u["phone"]) == before


def test_f03_dealer_fields_still_required_for_dealer_start(app_ctx, client):
    r = _start(client, _phone(), is_dealer=True)
    assert r.status_code == 400, r.data
    assert "Dealership name" in r.get_json()["message"]


def test_f03_legacy_signup_flow_applies_dealer_only_after_otp(app_ctx, client):
    """send_otp (+dealer fields) must not create dealer state; /auth/signup
    with the code does."""
    from kk.routes import auth as auth_routes
    from kk.time_utils import utcnow

    phone = _phone()
    r = client.post("/api/auth/send_otp", json={"phone": phone, **DEALER_FIELDS})
    assert r.status_code == 200, r.data
    pre = _row(app_ctx, phone)
    assert pre["applications"] == 0
    assert pre["dealer_status"] in ("none", "", None)

    app, _c, db, User = app_ctx
    with app.app_context():
        user = User.query.filter_by(phone_number=phone).one()
        user.phone_verification_code_hash = auth_routes._hash_phone_verification_code(
            phone, "222333"
        )
        user.phone_verification_expires_at = utcnow() + timedelta(minutes=10)
        db.session.commit()

    s = client.post(
        "/api/auth/signup",
        json={
            "phone": phone,
            "otp_code": "222333",
            "password": OWNER_PW,
            **DEALER_FIELDS,
        },
    )
    assert s.status_code == 201, s.data
    post = _row(app_ctx, phone)
    assert post["dealer_status"] == "pending"
    assert post["applications"] == 1


def test_f03_send_otp_with_dealer_fields_does_not_touch_existing_user(app_ctx, client):
    u = _make_user(app_ctx, verified=False)
    before = _row(app_ctx, u["phone"])
    client.post("/api/auth/send_otp", json={"phone": u["phone"], **DEALER_FIELDS})
    assert _row(app_ctx, u["phone"]) == before


# ---------------------------------------------------------------------------
# Account integrity follow-ups (A: identity fields, B: dealer downgrade,
# D: legitimate/legacy accounts keep working)
# ---------------------------------------------------------------------------


def _user_identity(app_ctx, phone: str) -> dict:
    app, _c, _db, User = app_ctx
    with app.app_context():
        u = User.query.filter_by(phone_number=phone).one()
        return {
            "username": u.username,
            "first_name": u.first_name,
            "last_name": u.last_name,
        }


def test_a_start_ignores_username_and_display_name_before_otp(app_ctx, client):
    """Nobody may pre-assign a username / display name to a number they do
    not own: the row gets a generated username and the placeholder name."""
    phone = _phone()
    wanted = f"squat_{uuid.uuid4().hex[:8]}"
    _start_code(
        client, phone, username=wanted, first_name="Support", last_name="Admin"
    )
    ident = _user_identity(app_ctx, phone)
    assert ident["username"] != wanted
    assert ident["username"].startswith("user_")
    assert ident["first_name"] == "User"
    assert ident["last_name"] in ("", None)


def test_a_start_does_not_reveal_whether_a_username_is_taken(app_ctx, client):
    taken = _make_user(app_ctx, verified=True)
    r = _start(client, _phone(), username=taken["username"])
    assert r.status_code == 200, r.data


def test_a_owner_still_gets_a_working_account_after_verification(app_ctx, client):
    phone = _phone()
    code = _start_code(client, phone, username="whatever", first_name="X")
    v = _verify(client, phone, code)
    assert v.status_code == 200, v.data
    user = v.get_json()["user"]
    assert user["username"] and user["phone_verified"] is True


def _make_dealer(app_ctx, status: str) -> dict:
    u = _make_user(
        app_ctx,
        verified=True,
        dealer_status=status,
        account_type="dealer" if status == "approved" else "user",
    )
    app, _c, db, User = app_ctx
    with app.app_context():
        row = User.query.filter_by(id=u["id"]).one()
        row.dealership_name = "Original Motors"
        row.dealership_phone = "07711111111"
        row.dealership_location = "Duhok"
        db.session.commit()
    return u


@pytest.mark.parametrize("status", ["approved", "pending", "rejected"])
def test_b_dealer_verify_with_dealer_fields_never_resets_existing_dealer(
    app_ctx, client, status
):
    u = _make_dealer(app_ctx, status)
    before = _row(app_ctx, u["phone"])

    code = _start_code(client, u["phone"], purpose="dealer")
    v = _verify(client, u["phone"], code, purpose="dealer", **DEALER_FIELDS)
    assert v.status_code == 200, v.data

    after = _row(app_ctx, u["phone"])
    assert after["dealer_status"] == status
    assert after["account_type"] == before["account_type"]
    assert after["dealership_name"] == "Original Motors"
    assert after["dealership_location"] == "Duhok"
    assert after["applications"] == before["applications"]


def test_b_signup_with_dealer_fields_never_resets_existing_dealer(app_ctx, client):
    from kk.routes import auth as auth_routes
    from kk.time_utils import utcnow

    u = _make_dealer(app_ctx, "approved")
    app, _c, db, User = app_ctx
    with app.app_context():
        row = User.query.filter_by(id=u["id"]).one()
        row.phone_verification_code_hash = auth_routes._hash_phone_verification_code(
            u["phone"], "333444"
        )
        row.phone_verification_expires_at = utcnow() + timedelta(minutes=10)
        db.session.commit()

    s = client.post(
        "/api/auth/signup",
        json={
            "phone": u["phone"],
            "otp_code": "333444",
            "password": OWNER_PW,
            **DEALER_FIELDS,
        },
    )
    assert s.status_code == 201, s.data
    after = _row(app_ctx, u["phone"])
    assert after["dealer_status"] == "approved"
    assert after["dealership_name"] == "Original Motors"


def test_d_grandfathered_verified_and_dealer_accounts_still_password_login(
    app_ctx, client
):
    plain = _make_user(app_ctx, verified=True)
    dealer = _make_dealer(app_ctx, "approved")
    for u in (plain, dealer):
        r = _pw_login(client, u["phone"], OWNER_PW)
        assert r.status_code == 200, r.data
        assert _pw_login(client, u["username"], OWNER_PW).status_code == 200


def test_d_email_verified_only_legacy_account_logs_in_via_otp(app_ctx, client):
    """An account verified only by e-mail (is_verified, never phone) cannot
    password-login (its phone has no proven owner) but regains access through
    the app's normal OTP login, which then makes it a verified account."""
    app, _c, db, User = app_ctx
    u = _make_user(app_ctx, verified=False)
    with app.app_context():
        row = User.query.filter_by(id=u["id"]).one()
        row.is_verified = True  # e-mail verified, phone_verified stays False
        db.session.commit()

    assert _pw_login(client, u["phone"], OWNER_PW).status_code == 401

    code = _start_code(client, u["phone"], purpose="login", create_if_missing=False)
    v = _verify(client, u["phone"], code, purpose="login", create_if_missing=False)
    assert v.status_code == 200, v.data
    assert _row(app_ctx, u["phone"])["phone_verified"] is True
