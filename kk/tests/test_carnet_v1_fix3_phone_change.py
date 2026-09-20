"""CarNet V1 release-candidate fix 3 -- account phone-number change actually
works end-to-end.

Bug: ``PUT /api/user/profile`` (``phone_number`` + ``verification_code``)
checked a verification code hashed as ``HMAC(SECRET_KEY, "<new_digits>:<code>")``,
but no existing OTP-send endpoint ever populated
``current_user.phone_verification_code_hash`` in that exact unprefixed
format for a NEW phone number the user doesn't already own -- the two
existing phone-OTP send endpoints in ``kk/routes/user.py``
(``dealer-phone``/``contact-phone``) deliberately namespace their hash with
a prefix (so they can never be replayed here), and the signup/delete-account
flows only ever verify the user's *own already-registered* number. So there
was no real way, through any endpoint, to successfully change an account's
primary phone number.

Fix: a new ``POST /api/user/phone-change/send-code`` endpoint
(``kk/routes/user.py::send_account_phone_change_code``) sends an OTP for the
NEW phone number, hashed with the exact same
``_hash_phone_verification_code()`` (``kk/routes/auth.py``) that
``update_profile()`` already checks -- and ``update_profile()`` itself was
switched from a hand-rolled inline HMAC to calling that same shared
function, so the two sides are now guaranteed to agree by construction, not
by coincidence.

Covers:
  * send-code -> profile-update verifies and actually changes the phone.
  * a wrong code is rejected and does not change the phone.
  * an expired code is rejected.
  * new-phone uniqueness is enforced at send-time (no wasted SMS) and is
    still re-checked at apply-time.
  * requesting a code for the user's own current number is rejected.
  * resend cooldown (60s) is enforced, reusing the existing OTP protection.
  * one user's pending code can never be applied to a DIFFERENT user's
    account (no cross-account OTP replay) -- proven by storing the
    verification state per-user, not globally.
  * normal login OTP (`/api/auth/phone/verify`) is unaffected by this change.
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


def _unique_phone() -> str:
    return f"075{uuid.uuid4().int % 10**8:08d}"


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(
        prefix="carlist_cnv1fix3_phone_change_", ignore_cleanup_errors=True
    )
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ["ALLOW_DEV_CODE_IN_RESPONSE"] = "1"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "phone_change.db")

    from kk.app_factory import create_app

    app, _socketio, *_ = create_app()
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


@pytest.fixture
def client(app_ctx):
    return app_ctx[1]


def _make_user(app_ctx) -> tuple[str, int, str, str]:
    """Returns (public_id, id, username, phone_number)."""
    app, _client, db, User = app_ctx
    username = f"cnv1fix3_{uuid.uuid4().hex[:10]}"
    phone = _unique_phone()
    with app.app_context():
        user = User(
            username=username,
            phone_number=phone,
            first_name="Phone",
            last_name="Change",
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id=f"pub-{uuid.uuid4().hex[:12]}",
        )
        user.set_password(_PASSWORD)
        db.session.add(user)
        db.session.commit()
        return user.public_id, user.id, username, phone


def _login(client, username: str) -> str:
    r = client.post(
        "/api/auth/login", json={"username": username, "password": _PASSWORD}
    )
    assert r.status_code == 200, r.data
    return r.get_json()["access_token"]


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _get_phone(app_ctx, user_id: int) -> str:
    app, _client, db, User = app_ctx
    with app.app_context():
        return db.session.get(User, user_id).phone_number


def test_send_code_then_profile_update_verifies_and_changes_phone(app_ctx, client):
    _pub, uid, username, _old_phone = _make_user(app_ctx)
    token = _login(client, username)
    new_phone = _unique_phone()

    r_send = client.post(
        "/api/user/phone-change/send-code",
        json={"phone_number": new_phone},
        headers=_auth(token),
    )
    assert r_send.status_code == 200, r_send.data
    body = r_send.get_json()
    assert body["sent"] is True
    code = body["dev_code"]
    assert len(code) == 6

    r_update = client.put(
        "/api/user/profile",
        json={"phone_number": new_phone, "verification_code": code},
        headers=_auth(token),
    )
    assert r_update.status_code == 200, r_update.data
    assert r_update.get_json()["user"]["phone_number"] == new_phone
    assert _get_phone(app_ctx, uid) == new_phone


def test_wrong_code_is_rejected_and_phone_unchanged(app_ctx, client):
    _pub, uid, username, old_phone = _make_user(app_ctx)
    token = _login(client, username)
    new_phone = _unique_phone()

    r_send = client.post(
        "/api/user/phone-change/send-code",
        json={"phone_number": new_phone},
        headers=_auth(token),
    )
    assert r_send.status_code == 200, r_send.data
    real_code = r_send.get_json()["dev_code"]
    wrong_code = f"{(int(real_code) + 1) % 1_000_000:06d}"

    r_update = client.put(
        "/api/user/profile",
        json={"phone_number": new_phone, "verification_code": wrong_code},
        headers=_auth(token),
    )
    assert r_update.status_code == 400, r_update.data
    assert "Invalid or expired" in r_update.get_json()["message"]
    assert _get_phone(app_ctx, uid) == old_phone


def test_expired_code_is_rejected(app_ctx, client):
    app, _client, db, User = app_ctx
    _pub, uid, username, old_phone = _make_user(app_ctx)
    token = _login(client, username)
    new_phone = _unique_phone()

    r_send = client.post(
        "/api/user/phone-change/send-code",
        json={"phone_number": new_phone},
        headers=_auth(token),
    )
    assert r_send.status_code == 200, r_send.data
    code = r_send.get_json()["dev_code"]

    # Force the stored code to have already expired.
    with app.app_context():
        user = db.session.get(User, uid)
        user.phone_verification_expires_at = user.phone_verification_expires_at - timedelta(
            minutes=20
        )
        db.session.commit()

    r_update = client.put(
        "/api/user/profile",
        json={"phone_number": new_phone, "verification_code": code},
        headers=_auth(token),
    )
    assert r_update.status_code == 400, r_update.data
    assert _get_phone(app_ctx, uid) == old_phone


def test_new_phone_uniqueness_enforced_at_send_time(app_ctx, client):
    _pub_a, _uid_a, username_a, _phone_a = _make_user(app_ctx)
    _pub_b, _uid_b, _username_b, phone_b = _make_user(app_ctx)
    token_a = _login(client, username_a)

    r_send = client.post(
        "/api/user/phone-change/send-code",
        json={"phone_number": phone_b},
        headers=_auth(token_a),
    )
    assert r_send.status_code == 400, r_send.data
    assert "already exists" in r_send.get_json()["message"].lower()


def test_new_phone_uniqueness_re_enforced_at_apply_time(app_ctx, client):
    """Even if the number was free at send-time, a race where someone else
    claims it before verification completes must still be rejected."""
    app, _client, db, User = app_ctx
    _pub_a, uid_a, username_a, old_phone_a = _make_user(app_ctx)
    token_a = _login(client, username_a)
    new_phone = _unique_phone()

    r_send = client.post(
        "/api/user/phone-change/send-code",
        json={"phone_number": new_phone},
        headers=_auth(token_a),
    )
    assert r_send.status_code == 200, r_send.data
    code = r_send.get_json()["dev_code"]

    # Someone else claims the exact same number in the meantime.
    with app.app_context():
        other = User(
            username=f"cnv1fix3_race_{uuid.uuid4().hex[:8]}",
            phone_number=new_phone,
            first_name="Race",
            last_name="Claimer",
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id=f"pub-{uuid.uuid4().hex[:12]}",
        )
        other.set_password(_PASSWORD)
        db.session.add(other)
        db.session.commit()

    r_update = client.put(
        "/api/user/profile",
        json={"phone_number": new_phone, "verification_code": code},
        headers=_auth(token_a),
    )
    assert r_update.status_code == 400, r_update.data
    assert "already exists" in r_update.get_json()["message"].lower()
    assert _get_phone(app_ctx, uid_a) == old_phone_a


def test_requesting_code_for_own_current_number_is_rejected(app_ctx, client):
    _pub, _uid, username, old_phone = _make_user(app_ctx)
    token = _login(client, username)

    r_send = client.post(
        "/api/user/phone-change/send-code",
        json={"phone_number": old_phone},
        headers=_auth(token),
    )
    assert r_send.status_code == 400, r_send.data
    assert "already your phone number" in r_send.get_json()["message"].lower()


def test_resend_cooldown_is_enforced(app_ctx, client):
    _pub, _uid, username, _old_phone = _make_user(app_ctx)
    token = _login(client, username)
    new_phone = _unique_phone()

    r1 = client.post(
        "/api/user/phone-change/send-code",
        json={"phone_number": new_phone},
        headers=_auth(token),
    )
    assert r1.status_code == 200, r1.data

    r2 = client.post(
        "/api/user/phone-change/send-code",
        json={"phone_number": new_phone},
        headers=_auth(token),
    )
    assert r2.status_code == 429, r2.data
    assert "wait" in r2.get_json()["message"].lower()


def test_otp_cannot_be_applied_to_a_different_users_account(app_ctx, client):
    """User A requests a code for a new number; user B (a completely
    different, unrelated account) must not be able to use A's code to
    change B's own phone number -- proves the verification state is
    per-user, not globally replayable."""
    _pub_a, _uid_a, username_a, _phone_a = _make_user(app_ctx)
    _pub_b, uid_b, username_b, old_phone_b = _make_user(app_ctx)
    token_a = _login(client, username_a)
    token_b = _login(client, username_b)
    new_phone = _unique_phone()

    r_send = client.post(
        "/api/user/phone-change/send-code",
        json={"phone_number": new_phone},
        headers=_auth(token_a),
    )
    assert r_send.status_code == 200, r_send.data
    code_from_a = r_send.get_json()["dev_code"]

    # B never requested a code at all -- B's own row has no pending hash.
    r_update_b = client.put(
        "/api/user/profile",
        json={"phone_number": new_phone, "verification_code": code_from_a},
        headers=_auth(token_b),
    )
    assert r_update_b.status_code == 400, r_update_b.data
    assert _get_phone(app_ctx, uid_b) == old_phone_b


def test_normal_login_otp_flow_is_unaffected(app_ctx, client):
    """The primary account-creation/login OTP verify endpoint
    (`/api/auth/phone/verify`) must still behave exactly as before -- this
    fix only adds a new send endpoint, it does not touch login OTP."""
    phone = _unique_phone()
    r_start = client.post("/api/auth/phone/start", json={"phone_number": phone})
    assert r_start.status_code == 200, r_start.data
    code = r_start.get_json().get("dev_code")
    assert code and len(code) == 6

    r_verify = client.post(
        "/api/auth/phone/verify",
        json={"phone_number": phone, "verification_code": code},
    )
    assert r_verify.status_code == 200, r_verify.data
    assert "access_token" in r_verify.get_json()
