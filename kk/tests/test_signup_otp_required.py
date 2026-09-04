"""C-01: `POST /api/auth/signup` must not mint tokens without a verified OTP.

Before this fix `compat_signup` had two branches. The OTP branch verified a
code; execution then fell through to a second branch that required only a
password and *invented* a phone number when none was supplied
(`f"070{secrets.randbelow(10**8):08d}"`), so anyone could obtain a valid access
and refresh token for a brand-new account. The failure handler also returned
`f"Signup failed: {str(e)}"`, leaking SQLAlchemy/driver internals.

These tests pin the fixed contract: phone + OTP are mandatory, wrong codes are
counted and locked out server-side, expiry is enforced server-side, resend is
throttled, and no response ever carries raw exception text.

Note that `check_rate_limit` is a no-op under `APP_ENV=testing`, so the lockout
proven here is the durable per-account one stored on the `User` row, not the
per-IP limiter.
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
from sqlalchemy.exc import IntegrityError

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))


# Substrings that must never reach a client. If one of these shows up in a
# response body, we are leaking internals.
_LEAK_MARKERS = (
    "Traceback",
    "SQL:",
    "sqlalchemy",
    "psycopg2",
    "sqlite3",
    "IntegrityError",
    "OperationalError",
    "ProgrammingError",
    "relation ",
    "no such table",
    "File \"",
    "line 1",
)


def _assert_no_leak(payload) -> None:
    blob = str(payload)
    for marker in _LEAK_MARKERS:
        assert marker.lower() not in blob.lower(), f"leaked {marker!r} in {blob!r}"


@pytest.fixture(scope="module")
def app_ctx():
    # ignore_cleanup_errors: on Windows the SQLite file stays mapped until the
    # engine is disposed, and teardown order is not worth fighting over here.
    tmp = tempfile.TemporaryDirectory(
        prefix="carlist_c01_", ignore_cleanup_errors=True
    )
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ["DB_PATH"] = os.path.join(tmp.name, "c01.db")

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


@pytest.fixture
def client(app_ctx):
    return app_ctx[1]


def _phone() -> str:
    """A unique Iraqi-format mobile number per call."""
    return f"078{uuid.uuid4().int % 10**8:08d}"


def _request_otp(client, phone: str, **extra):
    """Drive the real OTP-issuing endpoint and capture the generated code."""
    captured: dict[str, str] = {}

    def capture(phone_digits, code):
        captured["phone"] = phone_digits
        captured["code"] = code
        return True, None

    with patch("kk.sms_service.send_verification_sms_result", side_effect=capture):
        response = client.post(
            "/api/auth/send_otp", json={"phone": phone, **extra}
        )
    return response, captured.get("code")


def _signup(client, **body):
    return client.post("/api/auth/signup", json=body)


def _user_by_phone(app_ctx, phone: str):
    app, _client, _db, User = app_ctx
    with app.app_context():
        return User.query.filter_by(phone_number=phone).first()


# --- A. OTP is mandatory ----------------------------------------------------

def test_signup_without_otp_is_rejected_and_issues_no_token(app_ctx, client):
    """AT-01. The exact request that used to return 201 + a usable JWT."""
    before = _count_users(app_ctx)

    response = _signup(
        client,
        username=f"noauth_{uuid.uuid4().hex[:8]}",
        password="Aa123456!",
        first_name="No",
        last_name="Otp",
    )

    assert response.status_code == 400, response.data
    body = response.get_json() or {}
    assert body.get("code") == "phone_required"
    assert "token" not in body
    assert "access_token" not in body
    assert "refresh_token" not in body
    assert "user" not in body
    # The old branch invented a phone number and persisted an account.
    assert _count_users(app_ctx) == before


def test_signup_with_phone_but_no_otp_is_rejected(app_ctx, client):
    phone = _phone()
    _request_otp(client, phone)  # account row exists, code issued

    response = _signup(client, phone=phone, password="Aa123456!")

    assert response.status_code == 400, response.data
    body = response.get_json() or {}
    assert body.get("code") == "otp_required"
    assert "access_token" not in body
    # The pending account must not have been promoted to verified.
    user = _user_by_phone(app_ctx, phone)
    assert user is not None
    assert bool(user.is_verified) is False


def test_signup_never_invents_a_phone_number(app_ctx, client):
    """The removed branch minted accounts on `070XXXXXXXX` numbers."""
    app, _client, _db, User = app_ctx
    for _ in range(3):
        _signup(client, password="Aa123456!", username=f"x_{uuid.uuid4().hex[:6]}")
    with app.app_context():
        invented = User.query.filter(User.phone_number.like("070%")).count()
    assert invented == 0


def test_signup_without_password_is_rejected(app_ctx, client):
    phone = _phone()
    _, code = _request_otp(client, phone)

    response = _signup(client, phone=phone, otp_code=code)

    assert response.status_code == 400, response.data
    assert "access_token" not in (response.get_json() or {})
    # A rejected password must not burn the code.
    assert _signup(
        client, phone=phone, otp_code=code, password="Aa123456!"
    ).status_code == 201


def test_signup_with_unknown_phone_is_rejected(client):
    response = _signup(
        client, phone=_phone(), otp_code="123456", password="Aa123456!"
    )
    assert response.status_code == 404, response.data
    body = response.get_json() or {}
    assert body.get("code") == "user_not_found"
    assert "access_token" not in body


def test_signup_with_correct_otp_issues_tokens(app_ctx, client):
    phone = _phone()
    username = f"ok_{uuid.uuid4().hex[:8]}"
    send, code = _request_otp(client, phone)
    assert send.status_code == 200, send.data
    assert code and len(code) == 6

    response = _signup(
        client,
        phone=phone,
        otp_code=code,
        username=username,
        password="Aa123456!",
        first_name="Val",
        last_name="Id",
    )

    assert response.status_code == 201, response.data
    body = response.get_json() or {}
    # Legacy contract: all three token keys plus `user`.
    assert body["message"] == "Signup successful"
    assert body["token"] == body["access_token"]
    assert body["refresh_token"]
    assert body["user"]["username"] == username

    user = _user_by_phone(app_ctx, phone)
    assert bool(user.is_verified) is True
    assert bool(user.phone_verified) is True
    # The code is single-use.
    assert user.phone_verification_code_hash is None
    assert user.phone_verification_expires_at is None


def test_issued_token_is_actually_usable(client):
    """Guards against a fix that returns 201 with a token the API rejects."""
    phone = _phone()
    _, code = _request_otp(client, phone)
    body = _signup(
        client, phone=phone, otp_code=code, password="Aa123456!"
    ).get_json()

    me = client.get(
        "/api/auth/me",
        headers={"Authorization": f"Bearer {body['access_token']}"},
    )
    assert me.status_code == 200, me.data


# --- B. Attempt protection --------------------------------------------------

def test_incorrect_otp_is_rejected(app_ctx, client):
    phone = _phone()
    _request_otp(client, phone)

    response = _signup(
        client, phone=phone, otp_code="000000", password="Aa123456!"
    )

    assert response.status_code == 400, response.data
    body = response.get_json() or {}
    assert body.get("code") == "otp_invalid"
    assert "access_token" not in body
    user = _user_by_phone(app_ctx, phone)
    assert int(user.phone_verification_attempts or 0) == 1
    assert bool(user.is_verified) is False


def test_malformed_otp_is_rejected(client):
    phone = _phone()
    _request_otp(client, phone)
    for bad in ("", "12345", "1234567", "abcdef", "12 456"):
        response = _signup(
            client, phone=phone, otp_code=bad, password="Aa123456!"
        )
        assert response.status_code == 400, (bad, response.data)
        assert "access_token" not in (response.get_json() or {})


def test_repeated_incorrect_otp_locks_the_account(app_ctx, client):
    phone = _phone()
    _, code = _request_otp(client, phone)

    from kk.routes.auth import _OTP_MAX_ATTEMPTS

    # Attempts 1..N-1 are plain rejections that accumulate a counter.
    for attempt in range(1, _OTP_MAX_ATTEMPTS):
        response = _signup(
            client, phone=phone, otp_code="000000", password="Aa123456!"
        )
        assert response.status_code == 400, (attempt, response.data)
        assert (response.get_json() or {}).get("code") == "otp_invalid"
        user = _user_by_phone(app_ctx, phone)
        assert int(user.phone_verification_attempts or 0) == attempt

    # The attempt that trips the limit locks the account out.
    tripped = _signup(
        client, phone=phone, otp_code="000000", password="Aa123456!"
    )
    assert tripped.status_code == 429, tripped.data
    assert (tripped.get_json() or {}).get("code") == "otp_locked"

    user = _user_by_phone(app_ctx, phone)
    assert user.phone_verification_locked_until is not None
    # The live code is destroyed, so brute-force progress is thrown away.
    assert user.phone_verification_code_hash is None

    # Critically: the *correct* code no longer works while locked.
    locked = _signup(client, phone=phone, otp_code=code, password="Aa123456!")
    assert locked.status_code == 429, locked.data
    assert (locked.get_json() or {}).get("code") == "otp_locked"
    assert "access_token" not in (locked.get_json() or {})
    assert bool(_user_by_phone(app_ctx, phone).is_verified) is False


def test_lockout_blocks_resend_so_it_cannot_be_reset(app_ctx, client):
    """A lockout you can clear by asking for a new code is not a lockout."""
    app, _client, db, User = app_ctx
    phone = _phone()
    _request_otp(client, phone)
    from kk.routes.auth import _OTP_MAX_ATTEMPTS

    for _ in range(_OTP_MAX_ATTEMPTS):
        _signup(client, phone=phone, otp_code="000000", password="Aa123456!")

    response, _code = _request_otp(client, phone)
    assert response.status_code == 429, response.data


def test_lockout_expires_after_the_window(app_ctx, client):
    app, _client, db, User = app_ctx
    phone = _phone()
    _request_otp(client, phone)
    from kk.routes.auth import _OTP_MAX_ATTEMPTS

    for _ in range(_OTP_MAX_ATTEMPTS):
        _signup(client, phone=phone, otp_code="000000", password="Aa123456!")

    from kk.routes.auth import _OTP_RESEND_COOLDOWN_SECONDS
    from kk.time_utils import utcnow

    with app.app_context():
        user = User.query.filter_by(phone_number=phone).first()
        user.phone_verification_locked_until = utcnow() - timedelta(seconds=1)
        user.phone_verification_last_sent_at = utcnow() - timedelta(
            seconds=_OTP_RESEND_COOLDOWN_SECONDS + 1
        )
        db.session.commit()

    # Lockout lifted, but there is still no live code to use.
    response = _signup(
        client, phone=phone, otp_code="000000", password="Aa123456!"
    )
    assert response.status_code == 400, response.data
    assert (response.get_json() or {}).get("code") == "otp_invalid"

    # A fresh code is now obtainable and works.
    _, code = _request_otp(client, phone)
    assert _signup(
        client, phone=phone, otp_code=code, password="Aa123456!"
    ).status_code == 201


# --- C. Server-side expiry --------------------------------------------------

def test_expired_otp_is_rejected(app_ctx, client):
    app, _client, db, User = app_ctx
    phone = _phone()
    _, code = _request_otp(client, phone)

    from kk.time_utils import utcnow

    with app.app_context():
        user = User.query.filter_by(phone_number=phone).first()
        user.phone_verification_expires_at = utcnow() - timedelta(seconds=1)
        db.session.commit()

    response = _signup(client, phone=phone, otp_code=code, password="Aa123456!")

    assert response.status_code == 400, response.data
    body = response.get_json() or {}
    assert body.get("code") == "otp_invalid"
    assert "access_token" not in body
    assert bool(_user_by_phone(app_ctx, phone).is_verified) is False


def test_expiry_is_not_client_controllable(app_ctx, client):
    """Expiry comes from the DB row, never from request fields."""
    app, _client, db, User = app_ctx
    phone = _phone()
    _, code = _request_otp(client, phone)

    from kk.time_utils import utcnow

    with app.app_context():
        user = User.query.filter_by(phone_number=phone).first()
        user.phone_verification_expires_at = utcnow() - timedelta(hours=1)
        db.session.commit()

    response = _signup(
        client,
        phone=phone,
        otp_code=code,
        password="Aa123456!",
        phone_verification_expires_at="2099-01-01T00:00:00Z",
        expires_at="2099-01-01T00:00:00Z",
        phone_verification_attempts=0,
        is_verified=True,
        phone_verified=True,
    )
    assert response.status_code == 400, response.data
    assert bool(_user_by_phone(app_ctx, phone).is_verified) is False


def test_otp_cannot_be_replayed(app_ctx, client):
    phone = _phone()
    _, code = _request_otp(client, phone)
    assert _signup(
        client, phone=phone, otp_code=code, password="Aa123456!"
    ).status_code == 201

    replay = _signup(client, phone=phone, otp_code=code, password="Aa123456!")
    assert replay.status_code == 400, replay.data
    assert (replay.get_json() or {}).get("code") == "otp_invalid"


# --- D. Resend throttling ---------------------------------------------------

def test_otp_resend_too_quickly_is_rejected(client):
    phone = _phone()
    first, code = _request_otp(client, phone)
    assert first.status_code == 200, first.data
    assert code

    second, second_code = _request_otp(client, phone)
    assert second.status_code == 429, second.data
    assert second_code is None, "a throttled resend must not send an SMS"


def test_otp_resend_after_allowed_interval_succeeds(app_ctx, client):
    app, _client, db, User = app_ctx
    phone = _phone()
    _request_otp(client, phone)

    from kk.routes.auth import _OTP_RESEND_COOLDOWN_SECONDS
    from kk.time_utils import utcnow

    with app.app_context():
        user = User.query.filter_by(phone_number=phone).first()
        user.phone_verification_last_sent_at = utcnow() - timedelta(
            seconds=_OTP_RESEND_COOLDOWN_SECONDS + 1
        )
        db.session.commit()

    second, second_code = _request_otp(client, phone)
    assert second.status_code == 200, second.data
    assert second_code and len(second_code) == 6

    assert _signup(
        client, phone=phone, otp_code=second_code, password="Aa123456!"
    ).status_code == 201


def test_resending_invalidates_the_previous_code(app_ctx, client):
    app, _client, db, User = app_ctx
    phone = _phone()
    _, first_code = _request_otp(client, phone)

    from kk.routes.auth import _OTP_RESEND_COOLDOWN_SECONDS
    from kk.time_utils import utcnow

    with app.app_context():
        user = User.query.filter_by(phone_number=phone).first()
        user.phone_verification_last_sent_at = utcnow() - timedelta(
            seconds=_OTP_RESEND_COOLDOWN_SECONDS + 1
        )
        db.session.commit()

    _, second_code = _request_otp(client, phone)
    assert second_code != first_code

    stale = _signup(
        client, phone=phone, otp_code=first_code, password="Aa123456!"
    )
    assert stale.status_code == 400, stale.data


# --- Duplicate signup -------------------------------------------------------

def test_duplicate_signup_requires_a_fresh_otp_each_time(app_ctx, client):
    """Signing up twice on one phone cannot be done without SMS control."""
    phone = _phone()
    _, code = _request_otp(client, phone)
    assert _signup(
        client, phone=phone, otp_code=code, password="Aa123456!"
    ).status_code == 201

    # No new code requested -> second signup is refused.
    again = _signup(client, phone=phone, otp_code=code, password="Bb123456!")
    assert again.status_code == 400, again.data
    assert (again.get_json() or {}).get("code") == "otp_invalid"


def test_duplicate_username_is_rejected(app_ctx, client):
    taken = f"taken_{uuid.uuid4().hex[:8]}"
    first_phone = _phone()
    _, code = _request_otp(client, first_phone)
    assert _signup(
        client,
        phone=first_phone,
        otp_code=code,
        username=taken,
        password="Aa123456!",
    ).status_code == 201

    second_phone = _phone()
    _, code2 = _request_otp(client, second_phone)
    response = _signup(
        client,
        phone=second_phone,
        otp_code=code2,
        username=taken,
        password="Aa123456!",
    )
    assert response.status_code == 400, response.data
    assert "already exists" in (response.get_json() or {}).get("message", "")
    _assert_no_leak(response.get_json())


# --- E. No leaked internals -------------------------------------------------

def test_database_exception_during_signup_returns_a_generic_message(client):
    phone = _phone()
    _, code = _request_otp(client, phone)

    boom = RuntimeError(
        'relation "user" does not exist\n'
        "[SQL: UPDATE user SET password_hash=? WHERE user.id = ?]\n"
        "(Background on this error at: https://sqlalche.me/e/20/f405)"
    )
    with patch("kk.routes.auth._apply_dealer_profile", side_effect=boom):
        response = _signup(
            client, phone=phone, otp_code=code, password="Aa123456!"
        )

    assert response.status_code == 500, response.data
    body = response.get_json() or {}
    assert body.get("message") == "Signup failed. Please try again."
    assert body.get("code") == "signup_failed"
    # The old handler returned f"Signup failed: {str(e)}".
    assert 'relation "user"' not in str(body)
    assert "sqlalche.me" not in str(body)
    assert "password_hash" not in str(body)
    _assert_no_leak(body)


def test_integrity_error_during_signup_returns_a_generic_message(client):
    phone = _phone()
    _, code = _request_otp(client, phone)

    boom = IntegrityError(
        "INSERT INTO user (username, phone_number) VALUES (?, ?)",
        {"username": "dupe"},
        Exception("UNIQUE constraint failed: user.username"),
    )
    with patch("kk.routes.auth._apply_dealer_profile", side_effect=boom):
        response = _signup(
            client, phone=phone, otp_code=code, password="Aa123456!"
        )

    assert response.status_code == 409, response.data
    body = response.get_json() or {}
    assert body.get("message") == "Account already exists. Please log in."
    assert "UNIQUE constraint" not in str(body)
    _assert_no_leak(body)


def test_malformed_request_body_does_not_leak(client):
    """The error handlers log `raw_username`/`phone_digits`; they must be bound."""
    for payload in (None, [], "not-a-dict", {"phone": {"nested": 1}}):
        response = client.post(
            "/api/auth/signup",
            data="" if payload is None else str(payload).replace("'", '"'),
            content_type="application/json",
        )
        assert response.status_code in (400, 404, 500), (payload, response.data)
        _assert_no_leak(response.get_json())


def test_send_otp_failure_does_not_leak_provider_detail(client):
    """`sms_detail` is provider internals and used to be returned unconditionally."""
    phone = _phone()

    def fail(phone_digits, code):
        return False, "HTTP 401 from provider acct=ACME_12345 token=sk_live_abcdef"

    with patch("kk.sms_service.send_verification_sms_result", side_effect=fail):
        response = client.post("/api/auth/send_otp", json={"phone": phone})

    body = response.get_json() or {}
    assert "detail" not in body, body
    assert "sk_live" not in str(body)
    assert "ACME_12345" not in str(body)
    _assert_no_leak(body)


def test_phone_start_failure_does_not_leak_provider_detail(client):
    phone = _phone()

    def fail(phone_digits, code):
        return False, "HTTP 401 from provider acct=ACME_12345 token=sk_live_abcdef"

    with patch("kk.sms_service.send_verification_sms_result", side_effect=fail):
        response = client.post(
            "/api/auth/phone/start", json={"phone_number": phone}
        )

    body = response.get_json() or {}
    assert "detail" not in body, body
    assert "sk_live" not in str(body)
    _assert_no_leak(body)


def test_send_otp_internal_error_does_not_leak(client):
    boom = RuntimeError('no such column: user.phone_verification_locked_until')
    with patch(
        "kk.routes.auth._normalize_phone", side_effect=boom
    ):
        response = client.post("/api/auth/send_otp", json={"phone": _phone()})

    assert response.status_code == 500, response.data
    body = response.get_json() or {}
    assert body.get("message") == "Failed to send verification code"
    assert "no such column" not in str(body)
    _assert_no_leak(body)


def test_no_signup_response_leaks_internals(app_ctx, client):
    """Sweep every reachable signup outcome for internals in the body."""
    phone = _phone()
    _, code = _request_otp(client, phone)
    cases = [
        {},
        {"password": "Aa123456!"},
        {"phone": phone},
        {"phone": phone, "password": "short"},
        {"phone": phone, "otp_code": "000000", "password": "Aa123456!"},
        {"phone": _phone(), "otp_code": "123456", "password": "Aa123456!"},
        {"phone": phone, "otp_code": code, "password": "Aa123456!"},
        {"phone": phone, "otp_code": code, "password": "Aa123456!", "is_dealer": True},
    ]
    for body in cases:
        response = _signup(client, **body)
        _assert_no_leak(response.get_json())


# --- helpers ----------------------------------------------------------------

def _count_users(app_ctx) -> int:
    app, _client, _db, User = app_ctx
    with app.app_context():
        return User.query.count()
