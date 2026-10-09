"""Pre-release Security Batch 1 — SEC-001 / SEC-002 / SEC-005 (ADM-1 / OTP-1).

Regression coverage for three verified release blockers:

  SEC-005 / ADM-1: Mobile phone-OTP JWTs must not satisfy admin_required,
                   even when User.is_admin is True.
  OTP-1 / SEC-002: Requesting another OTP must not clear wrong-attempt
                   counters or unlock an active lockout.
  SEC-001:         When Redis is available but the JTI revocation key is
                   missing, the DB token_blacklist row must still revoke
                   the access token.
"""

from __future__ import annotations

import os
import sys
import tempfile
import uuid
from datetime import timedelta
from pathlib import Path
from unittest.mock import patch

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))


_PASSWORD = "Aa123456!"


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(
        prefix="carlist_sec_b1_", ignore_cleanup_errors=True
    )
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ["ALLOW_DEV_CODE_IN_RESPONSE"] = "1"
    os.environ.pop("REDIS_URL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "sec_b1.db")

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


@pytest.fixture
def client(app_ctx):
    return app_ctx[1]


def _unique_phone() -> str:
    return f"077{uuid.uuid4().int % 10**8:08d}"


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _make_user(app_ctx, *, is_admin: bool = False, username: str | None = None):
    app, _client, db, User = app_ctx
    username = username or f"u_{uuid.uuid4().hex[:10]}"
    phone = _unique_phone()
    with app.app_context():
        user = User(
            username=username,
            phone_number=phone,
            first_name="Sec",
            last_name="Batch",
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
            "phone": phone,
        }


def _make_dashboard_admin(app_ctx, *, password: str = _PASSWORD) -> dict:
    app, _client, db, User = app_ctx
    from kk.models import AdminAccount

    username = f"dash_{uuid.uuid4().hex[:10]}"
    with app.app_context():
        principal = User(
            username=f"{username}_principal",
            phone_number=_unique_phone(),
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

        acct = AdminAccount(
            principal_user_id=principal.id,
            username=username,
            is_active=True,
        )
        acct.set_password(password)
        db.session.add(acct)
        db.session.commit()
    return {"username": username, "password": password}


def _phone_start(client, phone: str, **extra):
    captured: dict[str, str] = {}

    def capture(phone_digits, code):
        captured["phone"] = phone_digits
        captured["code"] = code
        return True, None

    body = {"phone_number": phone, "purpose": "login", **extra}
    with patch("kk.sms_service.send_verification_sms_result", side_effect=capture):
        response = client.post("/api/auth/phone/start", json=body)
    return response, captured.get("code")


def _phone_verify(client, phone: str, code: str, **extra):
    body = {"phone_number": phone, "code": code, "purpose": "login", **extra}
    return client.post("/api/auth/phone/verify", json=body)


def _clear_resend_cooldown(app_ctx, phone: str) -> None:
    app, _client, db, User = app_ctx
    from kk.time_utils import utcnow

    with app.app_context():
        user = User.query.filter_by(phone_number=phone).first()
        user.phone_verification_last_sent_at = utcnow() - timedelta(seconds=120)
        db.session.commit()


def _user_otp_state(app_ctx, phone: str) -> dict:
    app, _client, db, User = app_ctx
    with app.app_context():
        user = User.query.filter_by(phone_number=phone).first()
        return {
            "attempts": int(user.phone_verification_attempts or 0),
            "locked_until": user.phone_verification_locked_until,
            "has_code": bool(user.phone_verification_code_hash),
        }


# ---------------------------------------------------------------------------
# SEC-005 / ADM-1 — phone OTP must not grant admin APIs
# ---------------------------------------------------------------------------


def test_sec005_phone_otp_token_cannot_access_admin_api(app_ctx, client):
    """Promoted mobile admin + successful phone OTP must still get 403 on admin."""
    info = _make_user(app_ctx, is_admin=True)

    start, code = _phone_start(client, info["phone"])
    assert start.status_code == 200, start.data
    assert code and len(code) == 6

    verify = _phone_verify(client, info["phone"], code)
    assert verify.status_code == 200, verify.data
    token = verify.get_json()["access_token"]

    # Ordinary authenticated surface still works.
    me = client.get("/api/auth/me", headers=_auth(token))
    assert me.status_code == 200, me.data
    assert me.get_json().get("is_admin") is True

    admin = client.get("/api/admin/users", headers=_auth(token))
    assert admin.status_code == 403, admin.data
    assert "admin" in (admin.get_json() or {}).get("message", "").lower()


def test_sec005_phone_otp_refresh_does_not_escalate_to_admin(app_ctx, client):
    info = _make_user(app_ctx, is_admin=True)
    start, code = _phone_start(client, info["phone"])
    assert start.status_code == 200, start.data
    verify = _phone_verify(client, info["phone"], code)
    assert verify.status_code == 200, verify.data
    body = verify.get_json()
    refresh = body["refresh_token"]

    rotated = client.post("/api/auth/refresh", headers=_auth(refresh))
    assert rotated.status_code == 200, rotated.data
    new_access = rotated.get_json()["access_token"]

    admin = client.get("/api/admin/users", headers=_auth(new_access))
    assert admin.status_code == 403, admin.data


def test_sec005_dashboard_admin_password_login_still_works(app_ctx, client):
    admin = _make_dashboard_admin(app_ctx)
    login = client.post(
        "/api/auth/login",
        json={
            "username": admin["username"],
            "password": admin["password"],
            "account_scope": "admin",
        },
    )
    assert login.status_code == 200, login.data
    token = login.get_json()["access_token"]

    resp = client.get("/api/admin/users", headers=_auth(token))
    assert resp.status_code == 200, resp.data


def test_sec005_mobile_password_login_for_is_admin_user_cannot_access_admin(
    app_ctx, client
):
    """ADM-1: promoted mobile User password login must not mint admin JWTs."""
    info = _make_user(app_ctx, is_admin=True)
    login = client.post(
        "/api/auth/login",
        json={"username": info["username"], "password": _PASSWORD},
    )
    assert login.status_code == 200, login.data
    token = login.get_json()["access_token"]
    me = client.get("/api/auth/me", headers=_auth(token))
    assert me.status_code == 200, me.data
    assert me.get_json().get("is_admin") is True
    resp = client.get("/api/admin/users", headers=_auth(token))
    assert resp.status_code == 403, resp.data


def test_sec005_mobile_password_refresh_for_is_admin_does_not_escalate(
    app_ctx, client
):
    info = _make_user(app_ctx, is_admin=True)
    login = client.post(
        "/api/auth/login",
        json={"username": info["username"], "password": _PASSWORD},
    )
    assert login.status_code == 200, login.data
    refresh = login.get_json()["refresh_token"]
    rotated = client.post("/api/auth/refresh", headers=_auth(refresh))
    assert rotated.status_code == 200, rotated.data
    new_access = rotated.get_json()["access_token"]
    admin = client.get("/api/admin/users", headers=_auth(new_access))
    assert admin.status_code == 403, admin.data


def test_sec005_legacy_admin_scoped_token_without_principal_is_rejected(
    app_ctx, client
):
    """Forged/legacy account_scope=admin without AdminAccount principal → 403."""
    from flask_jwt_extended import create_access_token

    info = _make_user(app_ctx, is_admin=True)
    app, _c, _db, _User = app_ctx
    with app.app_context():
        token = create_access_token(
            identity=info["public_id"],
            additional_claims={
                "is_admin": True,
                "account_scope": "admin",
                "auth_method": "password",
            },
        )
    resp = client.get("/api/admin/users", headers=_auth(token))
    assert resp.status_code == 403, resp.data


def test_sec005_dashboard_admin_refresh_preserves_admin_access(app_ctx, client):
    admin = _make_dashboard_admin(app_ctx)
    login = client.post(
        "/api/auth/login",
        json={
            "username": admin["username"],
            "password": admin["password"],
            "account_scope": "admin",
        },
    )
    assert login.status_code == 200, login.data
    body = login.get_json()
    assert (
        client.get("/api/admin/users", headers=_auth(body["access_token"])).status_code
        == 200
    )
    rotated = client.post("/api/auth/refresh", headers=_auth(body["refresh_token"]))
    assert rotated.status_code == 200, rotated.data
    new_access = rotated.get_json()["access_token"]
    assert client.get("/api/admin/users", headers=_auth(new_access)).status_code == 200


def test_sec005_ordinary_mobile_password_login_cannot_access_admin(app_ctx, client):
    info = _make_user(app_ctx, is_admin=False)
    login = client.post(
        "/api/auth/login",
        json={"username": info["username"], "password": _PASSWORD},
    )
    assert login.status_code == 200, login.data
    token = login.get_json()["access_token"]
    me = client.get("/api/auth/me", headers=_auth(token))
    assert me.status_code == 200, me.data
    admin = client.get("/api/admin/users", headers=_auth(token))
    assert admin.status_code == 403, admin.data


def test_sec005_admin_account_principal_blocked_from_mobile_password_login(
    app_ctx, client
):
    """Detached dashboard principals must not authenticate via mobile login."""
    admin = _make_dashboard_admin(app_ctx)
    app, _c, db, User = app_ctx
    from kk.models import AdminAccount

    with app.app_context():
        acct = AdminAccount.query.filter_by(username=admin["username"]).first()
        principal = User.query.get(acct.principal_user_id)
        principal_username = principal.username
        principal.set_password(_PASSWORD)
        db.session.commit()

    mobile = client.post(
        "/api/auth/login",
        json={"username": principal_username, "password": _PASSWORD},
    )
    assert mobile.status_code == 401, mobile.data


def test_sec005_inactive_admin_account_principal_cannot_access_admin(
    app_ctx, client
):
    admin = _make_dashboard_admin(app_ctx)
    app, _c, db, _User = app_ctx
    from kk.models import AdminAccount

    login = client.post(
        "/api/auth/login",
        json={
            "username": admin["username"],
            "password": admin["password"],
            "account_scope": "admin",
        },
    )
    assert login.status_code == 200, login.data
    token = login.get_json()["access_token"]

    with app.app_context():
        acct = AdminAccount.query.filter_by(username=admin["username"]).first()
        acct.is_active = False
        db.session.commit()

    resp = client.get("/api/admin/users", headers=_auth(token))
    assert resp.status_code == 403, resp.data


def test_sec005_ordinary_user_phone_otp_still_works(app_ctx, client):
    info = _make_user(app_ctx, is_admin=False)
    start, code = _phone_start(client, info["phone"])
    assert start.status_code == 200, start.data
    verify = _phone_verify(client, info["phone"], code)
    assert verify.status_code == 200, verify.data
    token = verify.get_json()["access_token"]
    me = client.get("/api/auth/me", headers=_auth(token))
    assert me.status_code == 200, me.data
    assert me.get_json().get("is_admin") is False


# ---------------------------------------------------------------------------
# OTP-1 / SEC-002 — resend must not reset attempts / bypass lockout
# ---------------------------------------------------------------------------


def test_sec002_resend_does_not_reset_wrong_attempt_counter(app_ctx, client):
    info = _make_user(app_ctx)
    start, code = _phone_start(client, info["phone"])
    assert start.status_code == 200, start.data
    assert code

    for _ in range(3):
        bad = _phone_verify(client, info["phone"], "000000")
        assert bad.status_code == 400, bad.data

    state = _user_otp_state(app_ctx, info["phone"])
    assert state["attempts"] == 3

    _clear_resend_cooldown(app_ctx, info["phone"])
    resend, new_code = _phone_start(client, info["phone"])
    assert resend.status_code == 200, resend.data
    assert new_code and new_code != code

    state_after = _user_otp_state(app_ctx, info["phone"])
    assert state_after["attempts"] == 3, state_after
    assert state_after["locked_until"] is None

    # Two more wrongs against the new code must lock (3 prior + 2 = 5).
    for _ in range(2):
        bad = _phone_verify(client, info["phone"], "111111")
        assert bad.status_code in (400, 429), bad.data

    locked = _user_otp_state(app_ctx, info["phone"])
    assert locked["locked_until"] is not None, locked


def test_sec002_resend_cannot_unlock_active_lockout(app_ctx, client):
    info = _make_user(app_ctx)
    start, code = _phone_start(client, info["phone"])
    assert start.status_code == 200, start.data

    for _ in range(5):
        bad = _phone_verify(client, info["phone"], "000000")
        assert bad.status_code in (400, 429), bad.data

    locked = _user_otp_state(app_ctx, info["phone"])
    assert locked["locked_until"] is not None, locked

    _clear_resend_cooldown(app_ctx, info["phone"])
    resend, _new = _phone_start(client, info["phone"])
    assert resend.status_code == 429, resend.data

    # Correct guess while locked must still fail closed.
    still = _phone_verify(client, info["phone"], code or "123456")
    assert still.status_code == 429, still.data


def test_sec002_lockout_recovers_after_expiry(app_ctx, client):
    info = _make_user(app_ctx)
    from kk.time_utils import utcnow

    start, _code = _phone_start(client, info["phone"])
    assert start.status_code == 200, start.data
    for _ in range(5):
        _phone_verify(client, info["phone"], "000000")

    app, _c, db, User = app_ctx
    with app.app_context():
        user = User.query.filter_by(phone_number=info["phone"]).first()
        user.phone_verification_locked_until = utcnow() - timedelta(seconds=1)
        user.phone_verification_last_sent_at = utcnow() - timedelta(seconds=120)
        db.session.commit()

    resend, new_code = _phone_start(client, info["phone"])
    assert resend.status_code == 200, resend.data
    assert new_code
    verify = _phone_verify(client, info["phone"], new_code)
    assert verify.status_code == 200, verify.data


def _send_verification(client, phone: str):
    """Legacy /api/auth/send_otp (= send-verification) OTP issuance."""
    captured: dict[str, str] = {}

    def capture(phone_digits, code):
        captured["phone"] = phone_digits
        captured["code"] = code
        return True, None

    with patch("kk.sms_service.send_verification_sms_result", side_effect=capture):
        response = client.post("/api/auth/send_otp", json={"phone": phone})
    return response, captured.get("code")


def test_sec002_send_verification_resend_preserves_attempt_counter(app_ctx, client):
    """Both OTP resend surfaces must preserve attempts (phone/start + send_otp)."""
    phone = _unique_phone()
    app, _c, db, User = app_ctx

    # send-verification only issues codes for unverified accounts.
    with app.app_context():
        user = User(
            username=f"uv_{uuid.uuid4().hex[:10]}",
            phone_number=phone,
            first_name="Unverified",
            last_name="Otp",
            is_active=True,
            is_verified=False,
            phone_verified=False,
            public_id=f"pub-{uuid.uuid4().hex[:12]}",
        )
        user.set_password(_PASSWORD)
        db.session.add(user)
        db.session.commit()

    start, code = _send_verification(client, phone)
    assert start.status_code == 200, start.data
    assert code

    for _ in range(3):
        # Wrong codes via phone/verify increment the shared attempt counter.
        bad = client.post(
            "/api/auth/phone/verify",
            json={"phone_number": phone, "code": "000000", "create_if_missing": True},
        )
        assert bad.status_code == 400, bad.data

    assert _user_otp_state(app_ctx, phone)["attempts"] == 3

    _clear_resend_cooldown(app_ctx, phone)
    resend, new_code = _send_verification(client, phone)
    assert resend.status_code == 200, resend.data
    assert new_code
    assert _user_otp_state(app_ctx, phone)["attempts"] == 3


# ---------------------------------------------------------------------------
# SEC-001 — Redis up + missing JTI key must still honor DB blacklist
# ---------------------------------------------------------------------------


class _RedisUpButEmpty:
    """Redis client that is 'available' but never has the revocation key."""

    def exists(self, key):
        return 0

    def setex(self, key, ttl, value):
        raise RuntimeError("simulated redis setex failure")


def test_sec001_logout_revokes_when_redis_up_but_jti_missing(app_ctx, client, monkeypatch):
    info = _make_user(app_ctx)
    login = client.post(
        "/api/auth/login",
        json={"username": info["username"], "password": _PASSWORD},
    )
    assert login.status_code == 200, login.data
    access = login.get_json()["access_token"]

    assert client.get("/api/auth/me", headers=_auth(access)).status_code == 200

    fake = _RedisUpButEmpty()
    monkeypatch.setattr("kk.routes.auth._redis_client", lambda: fake)

    logout = client.post("/api/auth/logout", headers=_auth(access))
    assert logout.status_code == 200, logout.data

    # DB blacklist row must exist even though Redis write failed.
    app, _c, db, _User = app_ctx
    from flask_jwt_extended import decode_token
    from kk.models import TokenBlacklist

    with app.app_context():
        jti = str(decode_token(access).get("jti") or "")
        assert jti
        assert TokenBlacklist.query.filter_by(jti=jti).first() is not None

    # Redis.exists == 0 must not skip the DB check.
    me = client.get("/api/auth/me", headers=_auth(access))
    assert me.status_code == 401, me.data
    assert "revoked" in (me.get_json() or {}).get("message", "").lower()


def test_sec001_db_only_logout_still_works_without_redis(app_ctx, client, monkeypatch):
    info = _make_user(app_ctx)
    monkeypatch.setattr("kk.routes.auth._redis_client", lambda: None)

    login = client.post(
        "/api/auth/login",
        json={"username": info["username"], "password": _PASSWORD},
    )
    access = login.get_json()["access_token"]
    assert client.post("/api/auth/logout", headers=_auth(access)).status_code == 200
    me = client.get("/api/auth/me", headers=_auth(access))
    assert me.status_code == 401, me.data


def test_sec001_unrevoked_token_still_works_with_redis_up(app_ctx, client, monkeypatch):
    info = _make_user(app_ctx)
    monkeypatch.setattr("kk.routes.auth._redis_client", lambda: _RedisUpButEmpty())

    login = client.post(
        "/api/auth/login",
        json={"username": info["username"], "password": _PASSWORD},
    )
    access = login.get_json()["access_token"]
    me = client.get("/api/auth/me", headers=_auth(access))
    assert me.status_code == 200, me.data
