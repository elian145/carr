"""Launch blockers from the pre-release audit: SEC-003 / SEC-004 / SEC-008 / SEC-009.

  SEC-003: one Iraqi SIM written as ``07715000015`` and ``7715000015`` must map
           to ONE account (and pre-fix accounts stored as ``07...`` must keep
           working without a data migration).
  SEC-004: the fixed Google-review OTP must never authenticate an admin or an
           admin principal, even if GOOGLE_REVIEW_PHONE is mis-set.
  SEC-008: failed-login message must not reveal whether the account exists
           (it used the account's stored locale).
  SEC-009: a non-ASCII review code must be a plain 400, never a 500.
"""

from __future__ import annotations

import os
import sys
import tempfile
import uuid
from pathlib import Path
from unittest.mock import patch

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

_PASSWORD = "Aa123456!"
_REVIEW_OTP = "913579"


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_sec_b2_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ["ALLOW_DEV_CODE_IN_RESPONSE"] = "1"
    os.environ.pop("REDIS_URL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "sec_b2.db")

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


def _digits10() -> str:
    """A fresh 10-digit Iraqi-style mobile without the leading zero."""
    return "77" + f"{uuid.uuid4().int % 10**8:08d}"


def _make_user(app_ctx, *, stored_phone: str, is_admin: bool = False, locale: str | None = None):
    app, _client, db, User = app_ctx
    with app.app_context():
        user = User(
            username=f"u_{uuid.uuid4().hex[:10]}",
            phone_number=stored_phone,
            first_name="Sec",
            last_name="B2",
            is_active=True,
            is_verified=True,
            phone_verified=True,
            is_admin=is_admin,
            public_id=f"pub-{uuid.uuid4().hex[:12]}",
        )
        user.set_password(_PASSWORD)
        if locale:
            user.locale = locale
        db.session.add(user)
        db.session.commit()
        return {"id": user.id, "username": user.username}


def _count_users_for(app_ctx, digits10: str) -> int:
    app, _client, _db, User = app_ctx
    with app.app_context():
        return User.query.filter(User.phone_number.in_([digits10, "0" + digits10])).count()


def _phone_start(client, phone: str, purpose: str = "signup"):
    captured: dict[str, str] = {}

    def capture(phone_digits, code):
        captured["code"] = code
        return True, None

    body = {"phone_number": phone, "purpose": purpose}
    with patch("kk.sms_service.send_verification_sms_result", side_effect=capture):
        response = client.post("/api/auth/phone/start", json=body)
    return response, captured.get("code")


# ---------------------------------------------------------------------------
# SEC-003
# ---------------------------------------------------------------------------


def test_sec003_normalize_phone_collapses_every_spelling():
    from kk.routes.auth import _normalize_phone

    d = _digits10()
    spellings = [d, "0" + d, "+964" + d, "964" + d, "+9640" + d, "00964" + d, f"0{d[:3]} {d[3:]}"]
    assert {_normalize_phone(s) for s in spellings} == {d}


def test_sec003_normalize_phone_leaves_unrelated_numbers_alone():
    from kk.routes.auth import _normalize_phone

    assert _normalize_phone("") == ""
    assert _normalize_phone("abc") == ""
    # A 10-digit number is already canonical; a 9-digit one is not padded.
    assert _normalize_phone("1234567890") == "1234567890"
    assert _normalize_phone("123456789") == "123456789"


def test_sec003_two_spellings_create_one_account(app_ctx, client):
    d = _digits10()
    from kk.routes.auth import _normalize_phone  # noqa: F401  (import check)

    app, _c, db, User = app_ctx
    for spelling in ("0" + d, d, "+964" + d, "+9640" + d):
        resp, _code = _phone_start(client, spelling)
        # Resend cooldown (429-ish) is fine for repeats; the point is the row count.
        assert resp.status_code in (200, 429), resp.data
        with app.app_context():  # clear cooldown so the next spelling is processed
            from kk.time_utils import utcnow
            from datetime import timedelta

            u = User.query.filter(User.phone_number.in_([d, "0" + d])).first()
            if u is not None:
                u.phone_verification_last_sent_at = utcnow() - timedelta(seconds=300)
                db.session.commit()
    assert _count_users_for(app_ctx, d) == 1


def test_sec003_new_account_is_stored_in_canonical_form(app_ctx, client):
    d = _digits10()
    resp, _code = _phone_start(client, "0" + d)
    assert resp.status_code == 200, resp.data
    app, _c, _db, User = app_ctx
    with app.app_context():
        assert User.query.filter_by(phone_number=d).count() == 1
        assert User.query.filter_by(phone_number="0" + d).count() == 0


def test_sec003_legacy_leading_zero_account_still_logs_in_without_duplicate(app_ctx, client):
    """Accounts stored as ``07...`` before the fix must keep working."""
    d = _digits10()
    info = _make_user(app_ctx, stored_phone="0" + d)

    resp, code = _phone_start(client, "+964" + d)  # what the app sends
    assert resp.status_code == 200, resp.data
    verify = client.post(
        "/api/auth/phone/verify",
        json={"phone_number": "+964" + d, "code": code, "purpose": "login"},
    )
    assert verify.status_code == 200, verify.data
    assert verify.get_json()["user"]["username"] == info["username"]
    assert _count_users_for(app_ctx, d) == 1


# ---------------------------------------------------------------------------
# SEC-008
# ---------------------------------------------------------------------------


def test_sec008_wrong_password_message_matches_unknown_user(app_ctx, client):
    d = _digits10()
    info = _make_user(app_ctx, stored_phone=d, locale="ar")

    # The oracle only exists when the request carries NO usable Accept-Language
    # (the stored account locale used to fill the gap): so cover no header, an
    # unsupported one, and explicit ones. An explicit header must still be
    # honoured (MI-03) and must be identical for a real and an unknown account.
    for headers in ({}, {"Accept-Language": "fr-FR"}, {"Accept-Language": "en"}, {"Accept-Language": "ku"}):
        known = client.post(
            "/api/auth/login",
            json={"username": info["username"], "password": "definitely-wrong-1"},
            headers=headers,
        )
        unknown = client.post(
            "/api/auth/login",
            json={"username": f"nobody_{uuid.uuid4().hex[:8]}", "password": "definitely-wrong-1"},
            headers=headers,
        )
        assert known.status_code == unknown.status_code == 401, headers
        assert known.get_json() == unknown.get_json(), headers

    # the stored locale ("ar") must NOT leak into the response when the request has none
    no_header = client.post(
        "/api/auth/login",
        json={"username": info["username"], "password": "definitely-wrong-1"},
    )
    assert no_header.get_json() == {"message": "Invalid credentials"}


# ---------------------------------------------------------------------------
# SEC-004 / SEC-009 (Google review login)
# ---------------------------------------------------------------------------


@pytest.fixture
def review_env(monkeypatch):
    def _set(phone: str):
        monkeypatch.setenv("GOOGLE_REVIEW_LOGIN_ENABLED", "1")
        monkeypatch.setenv("GOOGLE_REVIEW_PHONE", phone)
        monkeypatch.setenv("GOOGLE_REVIEW_OTP", _REVIEW_OTP)

    return _set


def test_sec009_non_ascii_review_code_is_400_not_500(app_ctx, client, review_env):
    d = _digits10()
    review_env(d)
    for bad in ("٩١٣٥٧٩", "91357é", "9135\u202e79", "\u0000\u0001"):
        resp = client.post(
            "/api/auth/phone/verify",
            json={"phone_number": "+964" + d, "code": bad, "purpose": "login"},
        )
        assert resp.status_code == 400, (bad, resp.status_code, resp.data)


def test_sec009_correct_review_code_still_works(app_ctx, client, review_env):
    d = _digits10()
    review_env(d)
    resp = client.post(
        "/api/auth/phone/verify",
        json={"phone_number": "+964" + d, "code": _REVIEW_OTP, "purpose": "login"},
    )
    assert resp.status_code == 200, resp.data
    assert resp.get_json()["access_token"]


def test_sec004_review_otp_never_logs_into_an_admin_user(app_ctx, client, review_env):
    d = _digits10()
    _make_user(app_ctx, stored_phone=d, is_admin=True)
    review_env(d)
    resp = client.post(
        "/api/auth/phone/verify",
        json={"phone_number": "+964" + d, "code": _REVIEW_OTP, "purpose": "login"},
    )
    assert resp.status_code == 400, resp.data
    body = resp.get_json()
    assert "access_token" not in body and "refresh_token" not in body


def test_sec004_review_otp_never_logs_into_an_admin_principal(app_ctx, client, review_env):
    app, _c, db, _User = app_ctx
    from kk.models import AdminAccount

    d = _digits10()
    info = _make_user(app_ctx, stored_phone="0" + d, is_admin=False)
    with app.app_context():
        acct = AdminAccount(
            principal_user_id=info["id"],
            username=f"dash_{uuid.uuid4().hex[:8]}",
            is_active=True,
        )
        acct.set_password(_PASSWORD)
        db.session.add(acct)
        db.session.commit()

    review_env(d)  # legacy 07... row must still be found via variants
    resp = client.post(
        "/api/auth/phone/verify",
        json={"phone_number": "+964" + d, "code": _REVIEW_OTP, "purpose": "login"},
    )
    assert resp.status_code == 400, resp.data
    assert "access_token" not in resp.get_json()
