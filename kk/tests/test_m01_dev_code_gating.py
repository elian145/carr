"""M-01: `dev_code` (OTP/reset-token echo) must be gated by exactly ONE shared
mechanism, `kk.config.dev_debug_response_fields_enabled()`, and by nothing
else.

Before this fix, `dev_code` was gated by three different, duplicated pieces
of logic scattered across `kk/routes/auth.py` and `kk/routes/user.py`:

  - `_is_dev_environment()` / `_is_dev_email_payload()` — `DEBUG` OR
    `APP_ENV == "development"`, with NO other check. `APP_ENV=development`
    alone (e.g. a misconfigured deploy) was sufficient to leak an OTP.
  - Two bespoke inline blocks (`forgot_password`, `phone_start`) requiring
    `APP_ENV in ("development", "testing") AND SMS_PROVIDER == "console"`,
    duplicated rather than shared, and not applied to email dev_code paths.

The fix replaces all of that with one function:

    dev_debug_response_fields_enabled() =
        get_app_env() in ("development", "testing")
        AND _env_flag("ALLOW_DEV_CODE_IN_RESPONSE")

which is now the ONLY thing gating `dev_code` at all 8 emission functions
(13 call sites) across both files, for both SMS- and email-based codes.

These tests drive the real Flask app + SQLite DB via HTTP (matching the
convention in `test_token_revocation.py` / `test_h06_rate_limit_fail_closed.py`),
so the actual endpoint behavior is exercised end to end, not just the helper
in isolation.
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


# ---------------------------------------------------------------------------
# Shared Flask app fixture
# ---------------------------------------------------------------------------


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_m01_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ["ALLOW_DEV_CODE_IN_RESPONSE"] = "1"
    os.environ["DB_PATH"] = os.path.join(tmp.name, "m01.db")

    from kk.app_factory import create_app

    app, socketio, *_ = create_app()
    from kk.models import User, db

    with app.app_context():
        db.drop_all()
        db.create_all()

    yield app, app.test_client(), db, User

    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    tmp.cleanup()
    # Avoid leaking these into other test modules running later in the same
    # pytest process (each test in this module sets its own env explicitly
    # via monkeypatch, which auto-restores -- but the module-level values
    # set above are NOT monkeypatched, so they must be cleaned up here).
    os.environ.pop("ALLOW_DEV_CODE_IN_RESPONSE", None)


@pytest.fixture
def client(app_ctx):
    return app_ctx[1]


def _unique_phone() -> str:
    return f"077{uuid.uuid4().int % 10**8:08d}"


def _login(client, username: str, password: str = "Aa123456!") -> str:
    r = client.post("/api/auth/login", json={"username": username, "password": password})
    assert r.status_code == 200, r.data
    return r.get_json()["access_token"]


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _new_user_token(app_ctx) -> str:
    """Create a fresh, verified, non-admin user with a phone number and log
    in. Each test gets its OWN user so the 60s resend-cooldown on the
    delete-account-send-code / email-change-send-code endpoints can never
    collide between tests."""
    app, client, db, User = app_ctx
    username = f"m01_{uuid.uuid4().hex[:10]}"
    with app.app_context():
        user = User(
            username=username,
            phone_number=_unique_phone(),
            first_name="M01",
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
    return _login(client, username)


def _clean_env(monkeypatch) -> None:
    """Start each test from a clean slate for the vars under test; each is
    then set explicitly by the test itself. monkeypatch auto-restores the
    original process env after the test."""
    for key in ("APP_ENV", "FLASK_ENV", "ALLOW_DEV_CODE_IN_RESPONSE", "SMS_PROVIDER"):
        monkeypatch.delenv(key, raising=False)


# ---------------------------------------------------------------------------
# A / B — DEBUG=true must NEVER be sufficient, even combined with the flag
# ---------------------------------------------------------------------------


def test_A_production_debug_true_flag_unset_no_dev_code(app_ctx, monkeypatch):
    app, client, db, User = app_ctx
    _clean_env(monkeypatch)
    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.setenv("SMS_PROVIDER", "console")
    # ALLOW_DEV_CODE_IN_RESPONSE left unset.
    monkeypatch.setitem(app.config, "DEBUG", True)  # simulate a misconfigured DEBUG flag

    token = _new_user_token(app_ctx)
    r = client.post("/api/auth/delete-account/send-code", headers=_auth(token))
    body = r.get_json() or {}
    assert "dev_code" not in body, body


def test_B_production_debug_true_flag_set_no_dev_code(app_ctx, monkeypatch):
    app, client, db, User = app_ctx
    _clean_env(monkeypatch)
    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.setenv("SMS_PROVIDER", "console")
    monkeypatch.setenv("ALLOW_DEV_CODE_IN_RESPONSE", "1")
    monkeypatch.setitem(app.config, "DEBUG", True)

    token = _new_user_token(app_ctx)
    r = client.post("/api/auth/delete-account/send-code", headers=_auth(token))
    body = r.get_json() or {}
    assert "dev_code" not in body, body


# ---------------------------------------------------------------------------
# C / D — APP_ENV=development or testing ALONE (flag unset) must NOT be enough
# ---------------------------------------------------------------------------


def test_C_development_flag_unset_no_dev_code(app_ctx, monkeypatch):
    _clean_env(monkeypatch)
    monkeypatch.setenv("APP_ENV", "development")
    monkeypatch.setenv("SMS_PROVIDER", "console")
    # ALLOW_DEV_CODE_IN_RESPONSE left unset — this is the exact scenario the
    # original M-01 finding warned about.

    token = _new_user_token(app_ctx)
    r = app_ctx[1].post("/api/auth/delete-account/send-code", headers=_auth(token))
    body = r.get_json() or {}
    assert "dev_code" not in body, body


def test_D_testing_flag_unset_no_dev_code(app_ctx, monkeypatch):
    _clean_env(monkeypatch)
    monkeypatch.setenv("APP_ENV", "testing")
    monkeypatch.setenv("SMS_PROVIDER", "console")

    token = _new_user_token(app_ctx)
    r = app_ctx[1].post("/api/auth/delete-account/send-code", headers=_auth(token))
    body = r.get_json() or {}
    assert "dev_code" not in body, body


# ---------------------------------------------------------------------------
# E / F — env + explicit flag together DOES allow dev_code (usable workflow)
# ---------------------------------------------------------------------------


def test_E_development_flag_set_dev_code_allowed(app_ctx, monkeypatch):
    _clean_env(monkeypatch)
    monkeypatch.setenv("APP_ENV", "development")
    monkeypatch.setenv("SMS_PROVIDER", "console")
    monkeypatch.setenv("ALLOW_DEV_CODE_IN_RESPONSE", "1")

    token = _new_user_token(app_ctx)
    r = app_ctx[1].post("/api/auth/delete-account/send-code", headers=_auth(token))
    body = r.get_json() or {}
    assert "dev_code" in body, body
    assert len(str(body["dev_code"])) == 6


def test_F_testing_flag_set_dev_code_allowed(app_ctx, monkeypatch):
    _clean_env(monkeypatch)
    monkeypatch.setenv("APP_ENV", "testing")
    monkeypatch.setenv("SMS_PROVIDER", "console")
    monkeypatch.setenv("ALLOW_DEV_CODE_IN_RESPONSE", "1")

    token = _new_user_token(app_ctx)
    r = app_ctx[1].post("/api/auth/delete-account/send-code", headers=_auth(token))
    body = r.get_json() or {}
    assert "dev_code" in body, body


# ---------------------------------------------------------------------------
# G — APP_ENV unset must resolve to production-safe, even with the flag set
# ---------------------------------------------------------------------------


def test_G_app_env_unset_flag_set_no_dev_code(app_ctx, monkeypatch):
    _clean_env(monkeypatch)
    # APP_ENV and FLASK_ENV both deliberately left unset.
    monkeypatch.setenv("SMS_PROVIDER", "console")
    monkeypatch.setenv("ALLOW_DEV_CODE_IN_RESPONSE", "1")

    from kk.config import get_app_env

    assert get_app_env() == "production"  # sanity: safe default still holds

    token = _new_user_token(app_ctx)
    r = app_ctx[1].post("/api/auth/delete-account/send-code", headers=_auth(token))
    body = r.get_json() or {}
    assert "dev_code" not in body, body


# ---------------------------------------------------------------------------
# H / I — SMS_PROVIDER must be IRRELEVANT to the security gate
# ---------------------------------------------------------------------------


def test_H_development_non_console_provider_flag_set_dev_code_allowed(app_ctx, monkeypatch):
    _clean_env(monkeypatch)
    monkeypatch.setenv("APP_ENV", "development")
    # A real, non-console provider with NO credentials configured, so the
    # actual SMS send fails -> exercises the failure-branch dev_code path.
    monkeypatch.setenv("SMS_PROVIDER", "twilio")
    for key in ("TWILIO_ACCOUNT_SID", "TWILIO_AUTH_TOKEN", "TWILIO_PHONE_NUMBER"):
        monkeypatch.delenv(key, raising=False)
    monkeypatch.setenv("ALLOW_DEV_CODE_IN_RESPONSE", "1")

    token = _new_user_token(app_ctx)
    r = app_ctx[1].post("/api/auth/delete-account/send-code", headers=_auth(token))
    assert r.status_code == 502, r.data  # SMS send genuinely failed (no Twilio creds)
    body = r.get_json() or {}
    assert "dev_code" in body, body  # gate does not care which provider is configured


def test_I_production_any_provider_flag_set_no_dev_code(app_ctx, monkeypatch):
    _clean_env(monkeypatch)
    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.setenv("SMS_PROVIDER", "twilio")
    for key in ("TWILIO_ACCOUNT_SID", "TWILIO_AUTH_TOKEN", "TWILIO_PHONE_NUMBER"):
        monkeypatch.delenv(key, raising=False)
    monkeypatch.setenv("ALLOW_DEV_CODE_IN_RESPONSE", "1")  # flag cannot override production

    token = _new_user_token(app_ctx)
    r = app_ctx[1].post("/api/auth/delete-account/send-code", headers=_auth(token))
    body = r.get_json() or {}
    assert "dev_code" not in body, body


# ---------------------------------------------------------------------------
# J — email-based dev_code paths must obey EXACTLY the same gate as SMS
# ---------------------------------------------------------------------------


def test_J_email_dev_code_same_gate_allowed(app_ctx, monkeypatch):
    _clean_env(monkeypatch)
    monkeypatch.setenv("APP_ENV", "development")
    monkeypatch.setenv("ALLOW_DEV_CODE_IN_RESPONSE", "1")

    token = _new_user_token(app_ctx)
    r = app_ctx[1].post(
        "/api/user/email-change/send-code",
        headers=_auth(token),
        json={"email": f"m01_{uuid.uuid4().hex[:8]}@example.com"},
    )
    body = r.get_json() or {}
    assert "dev_code" in body, body


def test_J_email_dev_code_same_gate_blocked_in_production(app_ctx, monkeypatch):
    _clean_env(monkeypatch)
    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.setenv("ALLOW_DEV_CODE_IN_RESPONSE", "1")  # must not matter in production

    token = _new_user_token(app_ctx)
    r = app_ctx[1].post(
        "/api/user/email-change/send-code",
        headers=_auth(token),
        json={"email": f"m01_{uuid.uuid4().hex[:8]}@example.com"},
    )
    body = r.get_json() or {}
    assert "dev_code" not in body, body


def test_J_email_dev_code_blocked_when_flag_unset(app_ctx, monkeypatch):
    _clean_env(monkeypatch)
    monkeypatch.setenv("APP_ENV", "development")
    # ALLOW_DEV_CODE_IN_RESPONSE left unset.

    token = _new_user_token(app_ctx)
    r = app_ctx[1].post(
        "/api/user/email-change/send-code",
        headers=_auth(token),
        json={"email": f"m01_{uuid.uuid4().hex[:8]}@example.com"},
    )
    body = r.get_json() or {}
    assert "dev_code" not in body, body


# ---------------------------------------------------------------------------
# K — the sms_service console-SMS "not allowed in production" guard must
# stay fail-closed when APP_ENV/FLASK_ENV are unset (the independently
# discovered _app_env() unsafe-default bug, now fixed by delegating to
# kk.config.get_app_env()).
# ---------------------------------------------------------------------------


def test_K_sms_service_console_guard_fail_closed_when_app_env_unset(monkeypatch):
    _clean_env(monkeypatch)
    monkeypatch.setenv("SMS_PROVIDER", "console")
    # APP_ENV and FLASK_ENV both deliberately left unset.

    from kk.config import get_app_env
    from kk.sms_service import SMSService, _app_env

    assert get_app_env() == "production"
    assert _app_env() == "production"  # now delegates to get_app_env(), not its own copy

    svc = SMSService()
    ok, detail = svc.send_verification_code(_unique_phone(), "123456")
    assert ok is False, (ok, detail)
    assert "not allowed in production" in detail.lower(), detail


def test_K_sms_service_console_guard_still_works_in_dev(monkeypatch):
    """Regression check: the fix must not break the legitimate dev/test path."""
    _clean_env(monkeypatch)
    monkeypatch.setenv("APP_ENV", "testing")
    monkeypatch.setenv("SMS_PROVIDER", "console")

    from kk.sms_service import SMSService

    svc = SMSService()
    ok, detail = svc.send_verification_code(_unique_phone(), "123456")
    assert ok is True, (ok, detail)


# ---------------------------------------------------------------------------
# L — static regression protection: the old fragile mechanisms must be gone
# ---------------------------------------------------------------------------


def test_L_old_helpers_and_inline_gates_removed():
    auth_src = (_REPO_ROOT / "kk" / "routes" / "auth.py").read_text(encoding="utf-8")
    user_src = (_REPO_ROOT / "kk" / "routes" / "user.py").read_text(encoding="utf-8")
    sms_src = (_REPO_ROOT / "kk" / "sms_service.py").read_text(encoding="utf-8")

    # The old per-file helpers must be gone entirely (not merely unused).
    assert "_is_dev_environment" not in auth_src
    assert "_is_dev_email_payload" not in user_src

    # The old bespoke inline "env in (...) and sms_provider == 'console'"
    # gate (forgot_password / phone_start) must be gone.
    assert 'sms_provider == "console"' not in auth_src
    assert 'sms_provider == "console"' not in user_src

    # The old raw "DEBUG or APP_ENV==development" inline duplicates
    # (send_dealer_phone_verification / send_contact_phone_verification)
    # must be gone.
    assert 'current_app.config.get("DEBUG")' not in user_src

    # The new shared helper must be the thing actually used at every site.
    # auth.py: 5 sites that gate `dev_code` itself, plus 1 extra call in
    # phone_start()'s failure branch that gates only the internal `detail`
    # field (not `dev_code`) using the same shared helper -- 6 total calls.
    assert auth_src.count("dev_debug_response_fields_enabled()") == 6
    assert user_src.count("dev_debug_response_fields_enabled()") == 8

    # sms_service must delegate rather than re-implement env resolution.
    assert "get_app_env()" in sms_src
    assert 'or "development"' not in sms_src  # the old unsafe default


def test_L_dev_code_still_emitted_from_exactly_the_expected_sites():
    """Sanity companion to test_L above: `dev_code` itself must still be
    reachable from exactly the 8 known functions (not fewer -> feature
    silently dropped; not more -> new, unreviewed leak site introduced)."""
    auth_src = (_REPO_ROOT / "kk" / "routes" / "auth.py").read_text(encoding="utf-8")
    user_src = (_REPO_ROOT / "kk" / "routes" / "user.py").read_text(encoding="utf-8")

    # 5 literal `dev_code` key assignments/refs in auth.py (delete_account
    # x2, send_phone_verification x1, forgot_password x1, phone_start x1),
    # plus comment lines mentioning it are fine -- assert the KEY form.
    assert auth_src.count('"dev_code"') == 5
    assert user_src.count('"dev_code"') == 8
