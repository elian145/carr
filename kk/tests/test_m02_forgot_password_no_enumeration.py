"""M-02: `forgot_password` must not leak account existence via the client
response when SMS delivery fails.

Prior behavior (fixed by this change, see `kk/routes/auth.py::forgot_password`):

  - unknown phone                    -> 200 {"message": "If the account
                                         exists, a reset code has been sent"}
  - existing phone + SMS send fails  -> 503 {"code": "sms_send_failed", ...}

That asymmetry let an attacker distinguish real accounts from unregistered
phone numbers whenever the SMS provider failed for a given number -- and
during any provider outage/misconfiguration (missing/expired credentials,
etc.), every real account would get the 503 while every fake number kept
getting 200, turning it into a reliable, unlimited-scale enumeration oracle.

The fix removes the distinct failure response entirely: SMS-send failure is
now only logged server-side (no OTP/token/password values), and the client
always receives the exact same generic 200 body used for both the
"unknown phone" and "SMS sent successfully" cases. The M-01 `dev_code`
gate (`kk.config.dev_debug_response_fields_enabled()`) is untouched and
still applies identically regardless of whether the SMS send succeeded or
failed.

These tests drive the real Flask app + SQLite DB via HTTP (same convention
as `test_m01_dev_code_gating.py` / `test_token_revocation.py`). `APP_ENV` is
kept at "testing" for the whole module so the per-IP rate limiter on this
route (`check_rate_limit` short-circuits when `APP_ENV == "testing"`) never
interferes between tests; the M-01 dev_code gate is toggled independently
via the `ALLOW_DEV_CODE_IN_RESPONSE` flag, exactly as `dev_debug_response_
fields_enabled()` expects.
"""

from __future__ import annotations

import logging
import os
import sys
import tempfile
import uuid
from pathlib import Path

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

_GENERIC_BODY = {"message": "If the account exists, a reset code has been sent"}


# ---------------------------------------------------------------------------
# Shared Flask app fixture
# ---------------------------------------------------------------------------


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_m02_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("ALLOW_DEV_CODE_IN_RESPONSE", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "m02.db")

    from kk.app_factory import create_app

    app, socketio, *_ = create_app()
    from kk.models import User, db

    with app.app_context():
        db.drop_all()
        db.create_all()

    # Test-harness-only accommodation (NOT a production change; matches the
    # same fixup in `test_be10_route_exception_logging.py`): on a fresh DB,
    # `create_app()`'s auto-migrate path runs `flask_migrate.upgrade()`,
    # whose `migrations/env.py` calls `logging.config.fileConfig(...)` with
    # `disable_existing_loggers=True`, which disables the already-created
    # Flask `app.logger` ("kk.app_factory") as an incidental side effect.
    # Undo it so test E can observe the real `current_app.logger.warning(...)`
    # call this suite exists to verify.
    app.logger.disabled = False

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
    return f"079{uuid.uuid4().int % 10**8:08d}"


def _new_user(app_ctx) -> str:
    """Create a fresh, verified user with a unique phone number and return
    the phone number. Each test gets its own user so state never collides
    between tests."""
    app, _client, db, User = app_ctx
    phone = _unique_phone()
    with app.app_context():
        user = User(
            username=f"m02_{uuid.uuid4().hex[:10]}",
            phone_number=phone,
            first_name="M02",
            last_name="Test",
            email=None,
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id=f"pub-{uuid.uuid4().hex[:12]}",
        )
        user.set_password("Aa123456!")
        db.session.add(user)
        db.session.commit()
    return phone


# ---------------------------------------------------------------------------
# A -- unknown phone -> 200 + generic body
# ---------------------------------------------------------------------------


def test_A_unknown_phone_returns_generic_200(app_ctx):
    _app, client, _db, _User = app_ctx
    r = client.post("/api/auth/forgot-password", json={"phone_number": _unique_phone()})
    assert r.status_code == 200, r.data
    assert r.get_json() == _GENERIC_BODY


# ---------------------------------------------------------------------------
# B -- existing user, SMS send succeeds -> 200 + generic body
# ---------------------------------------------------------------------------


def test_B_existing_user_sms_success_returns_generic_200(app_ctx, monkeypatch):
    app_, client, _db, _User = app_ctx
    phone = _new_user(app_ctx)
    monkeypatch.setattr("kk.sms_service.send_password_reset_sms", lambda *_a, **_k: True)

    r = client.post("/api/auth/forgot-password", json={"phone_number": phone})
    assert r.status_code == 200, r.data
    assert r.get_json() == _GENERIC_BODY


# ---------------------------------------------------------------------------
# C -- existing user, SMS send FAILS -> still 200 + the SAME generic body as A
# ---------------------------------------------------------------------------


def test_C_existing_user_sms_failure_returns_same_generic_200(app_ctx, monkeypatch):
    app_, client, _db, _User = app_ctx
    phone = _new_user(app_ctx)
    monkeypatch.setattr("kk.sms_service.send_password_reset_sms", lambda *_a, **_k: False)

    r = client.post("/api/auth/forgot-password", json={"phone_number": phone})
    assert r.status_code == 200, r.data
    assert r.get_json() == _GENERIC_BODY

    # Byte-for-byte identical to the unknown-phone response: this is the
    # entire point of the fix -- no observable difference between "account
    # doesn't exist" and "account exists but SMS failed".
    unknown = client.post("/api/auth/forgot-password", json={"phone_number": _unique_phone()})
    assert unknown.status_code == r.status_code
    assert unknown.get_json() == r.get_json()


# ---------------------------------------------------------------------------
# D -- "sms_send_failed" must never reach the client on this endpoint
# ---------------------------------------------------------------------------


def test_D_sms_send_failed_code_not_returned_to_client(app_ctx, monkeypatch):
    app_, client, _db, _User = app_ctx
    phone = _new_user(app_ctx)
    monkeypatch.setattr("kk.sms_service.send_password_reset_sms", lambda *_a, **_k: False)

    r = client.post("/api/auth/forgot-password", json={"phone_number": phone})
    assert r.status_code == 200, r.data
    body = r.get_json() or {}
    assert "code" not in body, body
    assert "sms_send_failed" not in (r.get_data(as_text=True) or "")


# ---------------------------------------------------------------------------
# E -- SMS failure remains observable server-side, without sensitive values
# ---------------------------------------------------------------------------


def test_E_sms_failure_logged_without_sensitive_values(app_ctx, monkeypatch, caplog):
    app_, client, _db, _User = app_ctx
    phone = _new_user(app_ctx)
    monkeypatch.setattr("kk.sms_service.send_password_reset_sms", lambda *_a, **_k: False)

    with caplog.at_level(logging.WARNING):
        r = client.post("/api/auth/forgot-password", json={"phone_number": phone})
    assert r.status_code == 200, r.data

    warnings = [rec.getMessage() for rec in caplog.records if rec.levelno >= logging.WARNING]
    matches = [m for m in warnings if "FORGOT-PASSWORD" in m and "SMS send failed" in m]
    assert matches, f"expected a server-side warning about the SMS failure; got: {warnings}"

    # The log line(s) must not contain the full phone number, and never a
    # reset token/OTP or password value.
    for m in matches:
        assert phone not in m
        assert "Aa123456!" not in m


# ---------------------------------------------------------------------------
# F -- M-01 dev_code gating is preserved exactly (not weakened, not
# expanded/changed by the SMS-failure code path)
# ---------------------------------------------------------------------------


def test_F_dev_code_present_on_success_when_gate_enabled(app_ctx, monkeypatch):
    app_, client, _db, _User = app_ctx
    monkeypatch.setenv("ALLOW_DEV_CODE_IN_RESPONSE", "1")
    monkeypatch.setattr("kk.sms_service.send_password_reset_sms", lambda *_a, **_k: True)
    phone = _new_user(app_ctx)

    r = client.post("/api/auth/forgot-password", json={"phone_number": phone})
    assert r.status_code == 200, r.data
    body = r.get_json() or {}
    assert body.get("message") == _GENERIC_BODY["message"]
    assert body.get("dev_code")


def test_F_dev_code_still_present_on_sms_failure_when_gate_enabled(app_ctx, monkeypatch):
    """SMS failure must not change dev_code visibility either way -- the
    M-01 gate is the ONLY thing that controls it, per M-01's contract."""
    app_, client, _db, _User = app_ctx
    monkeypatch.setenv("ALLOW_DEV_CODE_IN_RESPONSE", "1")
    monkeypatch.setattr("kk.sms_service.send_password_reset_sms", lambda *_a, **_k: False)
    phone = _new_user(app_ctx)

    r = client.post("/api/auth/forgot-password", json={"phone_number": phone})
    assert r.status_code == 200, r.data
    body = r.get_json() or {}
    assert body.get("message") == _GENERIC_BODY["message"]
    assert body.get("dev_code")


def test_F_dev_code_absent_when_gate_disabled_regardless_of_sms_outcome(app_ctx, monkeypatch):
    app_, client, _db, _User = app_ctx
    monkeypatch.delenv("ALLOW_DEV_CODE_IN_RESPONSE", raising=False)

    monkeypatch.setattr("kk.sms_service.send_password_reset_sms", lambda *_a, **_k: True)
    phone_ok = _new_user(app_ctx)
    r_ok = client.post("/api/auth/forgot-password", json={"phone_number": phone_ok})
    assert r_ok.status_code == 200, r_ok.data
    assert r_ok.get_json() == _GENERIC_BODY

    monkeypatch.setattr("kk.sms_service.send_password_reset_sms", lambda *_a, **_k: False)
    phone_fail = _new_user(app_ctx)
    r_fail = client.post("/api/auth/forgot-password", json={"phone_number": phone_fail})
    assert r_fail.status_code == 200, r_fail.data
    assert r_fail.get_json() == _GENERIC_BODY
