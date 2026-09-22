"""Google Play reviewer OTP login bypass.

Google Play review requires a login that (a) never expires and (b) never
depends on receiving a real SMS. Real phone-OTP login cannot satisfy
either, so a single, narrowly-scoped account can authenticate with a fixed
phone number + code pulled from THREE environment variables:

    GOOGLE_REVIEW_LOGIN_ENABLED  - master on/off switch
    GOOGLE_REVIEW_PHONE          - the exact phone number this applies to
    GOOGLE_REVIEW_OTP            - the fixed code accepted for that phone

See `kk/routes/auth.py` (`_is_google_review_phone`, `_google_review_otp_matches`,
`_google_review_phone_start_response`, `_google_review_login_success_response`)
for the implementation and full design-invariant comments.

IMPORTANT: `_TEST_REVIEW_PHONE` / `_TEST_REVIEW_OTP` below are synthetic,
throwaway values used ONLY to drive this test suite's own isolated app
instance (via `GOOGLE_REVIEW_PHONE`/`GOOGLE_REVIEW_OTP` env vars set for this
process only). They are NOT, and must never become, the real Render
production values -- those are configured only in the Render dashboard and
never appear in source control.

Covers:
  * reviewer phone + reviewer OTP succeeds (real access/refresh tokens,
    normal `User` row, usable for ordinary authenticated requests).
  * reviewer phone + wrong OTP fails with the exact same generic message as
    any other wrong code (no leak that this phone number is special).
  * a normal (non-reviewer) phone number submitting the reviewer OTP fails.
  * disabling GOOGLE_REVIEW_LOGIN_ENABLED fully disables the bypass on both
    /phone/start and /phone/verify -- the reviewer phone number falls back
    to the completely ordinary OTP flow.
  * normal OTP login for an unrelated phone number is completely unchanged.
  * /phone/start for the reviewer phone never triggers an SMS send and
    never returns a `dev_code` (so nothing about the response reveals that
    this is a review account).
  * repeated reviewer logins never create a duplicate `User` row.
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

# Synthetic, test-only values -- see module docstring. Never the real
# production GOOGLE_REVIEW_PHONE / GOOGLE_REVIEW_OTP.
_TEST_REVIEW_PHONE = "07799990000"
_TEST_REVIEW_OTP = "913579"


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(
        prefix="carlist_google_review_", ignore_cleanup_errors=True
    )
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ["DB_PATH"] = os.path.join(tmp.name, "google_review.db")
    # ALLOW_DEV_CODE_IN_RESPONSE lets tests distinguish "went through the
    # real per-user OTP path" (dev_code present) from "went through the
    # review bypass" (dev_code deliberately never present) -- see
    # test_disabled_flag_start_falls_back_to_normal_flow_with_dev_code.
    os.environ["ALLOW_DEV_CODE_IN_RESPONSE"] = "1"
    os.environ["GOOGLE_REVIEW_LOGIN_ENABLED"] = "1"
    os.environ["GOOGLE_REVIEW_PHONE"] = _TEST_REVIEW_PHONE
    os.environ["GOOGLE_REVIEW_OTP"] = _TEST_REVIEW_OTP

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
    for key in (
        "ALLOW_DEV_CODE_IN_RESPONSE",
        "GOOGLE_REVIEW_LOGIN_ENABLED",
        "GOOGLE_REVIEW_PHONE",
        "GOOGLE_REVIEW_OTP",
    ):
        os.environ.pop(key, None)


@pytest.fixture
def client(app_ctx):
    return app_ctx[1]


def _unique_phone() -> str:
    return f"078{uuid.uuid4().int % 10**8:08d}"


def _start(client, phone: str, **extra):
    body = {"phone_number": phone, "create_if_missing": True}
    body.update(extra)
    return client.post("/api/auth/phone/start", json=body)


def _verify(client, phone: str, code: str, **extra):
    body = {"phone_number": phone, "code": code, "create_if_missing": True}
    body.update(extra)
    return client.post("/api/auth/phone/verify", json=body)


# ---------------------------------------------------------------------------
# 1. /phone/start for the reviewer phone: normal response, no SMS, no leak.
# ---------------------------------------------------------------------------


def test_reviewer_phone_start_returns_normal_response_without_sms(
    app_ctx, client, monkeypatch
):
    import kk.sms_service as sms_module

    def _fail_if_called(*_a, **_k):
        raise AssertionError("SMS must never be sent for the reviewer phone")

    monkeypatch.setattr(sms_module, "send_verification_sms_result", _fail_if_called)

    r = _start(client, _TEST_REVIEW_PHONE)
    assert r.status_code == 200, r.data
    body = r.get_json()
    # Identical to the real success shape; no dev_code, no review-specific
    # field of any kind -- indistinguishable from an ordinary successful send.
    assert body == {"message": "OTP sent"}


# ---------------------------------------------------------------------------
# 2. reviewer phone + reviewer OTP succeeds through the normal JWT flow.
# ---------------------------------------------------------------------------


def test_reviewer_phone_and_reviewer_otp_succeeds(app_ctx, client):
    start = _start(client, _TEST_REVIEW_PHONE)
    assert start.status_code == 200, start.data

    r = _verify(client, _TEST_REVIEW_PHONE, _TEST_REVIEW_OTP)
    assert r.status_code == 200, r.data
    body = r.get_json()
    assert body.get("access_token")
    assert body.get("refresh_token")
    user = body.get("user") or {}
    assert user.get("phone_number") == _TEST_REVIEW_PHONE
    # No field anywhere in the response signals this is a review account.
    assert "review" not in str(body).lower()


def test_reviewer_account_has_full_ordinary_access(app_ctx, client):
    """The token issued to the reviewer account works exactly like a real
    user's token against an ordinary authenticated endpoint."""
    r = _verify(client, _TEST_REVIEW_PHONE, _TEST_REVIEW_OTP)
    assert r.status_code == 200, r.data
    access_token = r.get_json()["access_token"]

    me = client.get(
        "/api/auth/me", headers={"Authorization": f"Bearer {access_token}"}
    )
    assert me.status_code == 200, me.data
    profile = me.get_json()
    assert profile.get("phone_number") == _TEST_REVIEW_PHONE
    assert profile.get("is_verified") is True


def test_reviewer_login_never_creates_a_duplicate_account(app_ctx, client):
    app, _client, db, User = app_ctx

    for _ in range(3):
        r = _verify(client, _TEST_REVIEW_PHONE, _TEST_REVIEW_OTP)
        assert r.status_code == 200, r.data

    with app.app_context():
        count = User.query.filter_by(phone_number=_TEST_REVIEW_PHONE).count()
    assert count == 1


def test_reviewer_login_is_never_permanently_locked_out(app_ctx, client):
    """Repeated correct-OTP logins must keep succeeding -- the bypass never
    touches the real per-user OTP lockout counters, so there is no way for
    the reviewer to accumulate a lockout from using it."""
    for _ in range(10):
        r = _verify(client, _TEST_REVIEW_PHONE, _TEST_REVIEW_OTP)
        assert r.status_code == 200, r.data


# ---------------------------------------------------------------------------
# 3. reviewer phone + wrong OTP fails (generic message, no leak).
# ---------------------------------------------------------------------------


def test_reviewer_phone_with_wrong_otp_fails(app_ctx, client):
    r = _verify(client, _TEST_REVIEW_PHONE, "000000")
    assert r.status_code == 400, r.data
    body = r.get_json()
    assert body.get("message") == "Invalid or expired verification code"
    assert "access_token" not in body
    assert body.get("code") != "account_deactivated"


def test_reviewer_phone_wrong_otp_does_not_block_the_real_otp_afterwards(
    app_ctx, client
):
    """A wrong guess against the reviewer phone must not lock out the real
    bypass code afterwards (no shared attempt counter)."""
    for _ in range(5):
        bad = _verify(client, _TEST_REVIEW_PHONE, "111111")
        assert bad.status_code == 400, bad.data

    good = _verify(client, _TEST_REVIEW_PHONE, _TEST_REVIEW_OTP)
    assert good.status_code == 200, good.data


# ---------------------------------------------------------------------------
# 4. normal phone + reviewer OTP fails.
# ---------------------------------------------------------------------------


def test_normal_phone_with_reviewer_otp_fails(app_ctx, client):
    phone = _unique_phone()
    start = _start(client, phone)
    assert start.status_code == 200, start.data

    r = _verify(client, phone, _TEST_REVIEW_OTP)
    assert r.status_code == 400, r.data
    assert r.get_json().get("message") == "Invalid or expired verification code"
    assert "access_token" not in r.get_json()


# ---------------------------------------------------------------------------
# 5. feature disabled -> reviewer bypass does not work.
# ---------------------------------------------------------------------------


def test_disabled_flag_blocks_verify_bypass(app_ctx, client, monkeypatch):
    monkeypatch.setenv("GOOGLE_REVIEW_LOGIN_ENABLED", "0")

    r = _verify(client, _TEST_REVIEW_PHONE, _TEST_REVIEW_OTP)
    assert r.status_code != 200, r.data
    assert "access_token" not in (r.get_json() or {})


def test_disabled_flag_start_falls_back_to_normal_flow_with_dev_code(
    app_ctx, client, monkeypatch
):
    """With the flag off, /phone/start for the (now-ordinary) reviewer
    phone number must go through the real random-OTP path -- proven by the
    presence of `dev_code`, which the bypass path never returns."""
    monkeypatch.setenv("GOOGLE_REVIEW_LOGIN_ENABLED", "0")

    r = _start(client, _TEST_REVIEW_PHONE)
    assert r.status_code == 200, r.data
    body = r.get_json()
    assert "dev_code" in body, "expected the normal OTP flow, not the bypass"


def test_missing_review_env_vars_disables_bypass_even_if_flag_enabled(
    app_ctx, client, monkeypatch
):
    """Enabling the flag alone (without GOOGLE_REVIEW_PHONE/OTP configured)
    must never accidentally open a universal bypass."""
    monkeypatch.setenv("GOOGLE_REVIEW_LOGIN_ENABLED", "1")
    monkeypatch.delenv("GOOGLE_REVIEW_PHONE", raising=False)
    monkeypatch.delenv("GOOGLE_REVIEW_OTP", raising=False)

    r = _verify(client, _TEST_REVIEW_PHONE, _TEST_REVIEW_OTP)
    assert r.status_code != 200, r.data
    assert "access_token" not in (r.get_json() or {})


# ---------------------------------------------------------------------------
# 6. normal OTP behavior is unchanged.
# ---------------------------------------------------------------------------


def test_normal_otp_signup_and_login_flow_is_unchanged(app_ctx, client):
    phone = _unique_phone()

    start = _start(client, phone)
    assert start.status_code == 200, start.data
    code = start.get_json().get("dev_code")
    assert code and len(code) == 6 and code.isdigit()

    wrong = f"{(int(code) + 1) % 1_000_000:06d}"
    bad = _verify(client, phone, wrong)
    assert bad.status_code == 400, bad.data
    assert bad.get_json().get("message") == "Invalid or expired verification code"

    good = _verify(client, phone, code)
    assert good.status_code == 200, good.data
    body = good.get_json()
    assert body.get("access_token")
    assert body.get("refresh_token")
    assert body["user"]["phone_number"] == phone


def test_normal_otp_lockout_after_five_wrong_attempts_is_unchanged(app_ctx, client):
    phone = _unique_phone()
    start = _start(client, phone)
    code = start.get_json().get("dev_code")
    wrong = f"{(int(code) + 1) % 1_000_000:06d}"

    for _ in range(5):
        r = _verify(client, phone, wrong)
        assert r.status_code == 400, r.data

    locked = _verify(client, phone, code)
    assert locked.status_code == 429, locked.data
    assert "too many attempts" in locked.get_json()["message"].lower()
