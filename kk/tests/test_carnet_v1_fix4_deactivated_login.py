"""CarNet V1 release-candidate fix 4 -- deactivated-account OTP login gives a
real answer instead of a misleading "Invalid or expired verification code".

Bug: `POST /api/auth/phone/verify` looked the user up with
`_get_active_user_by_phone()` (`is_active=True` filter). A deactivated
account's phone number still receives a perfectly real OTP from
`POST /api/auth/phone/start` (`_get_or_create_user_for_phone()` does not
filter on `is_active`, by design, so requesting a code looks identical
whether or not the account is active). But once that correct code reached
`phone_verify()`, the `is_active`-filtered lookup found nobody, and the
Flutter client's default `create_if_missing=True` request body routed it
into the exact same "Invalid or expired verification code" branch used for
a genuinely wrong/expired code -- so a deactivated user could never learn
their account was deactivated; login just looked broken.

Fix: `kk/routes/auth.py::_deactivated_account_otp_response()` -- reachable
only from inside `phone_verify()`'s `not user` branch -- separately looks up
an *inactive* user with this phone number and, only if the submitted code is
genuinely correct and unexpired for THAT row, returns a dedicated
`403 {"code": "account_deactivated"}` response instead. A wrong code, an
expired code, or a phone number with no account at all (active or not)
still fall through unchanged to the pre-existing generic responses, so this
cannot be used to enumerate arbitrary phone numbers -- it only reveals
anything to someone who already possesses a live, correct code for that
exact number (i.e. someone with control of the phone).

Covers:
  * active user + valid OTP -> normal login (tokens issued), unaffected.
  * deactivated user + valid OTP -> 403 account_deactivated, no tokens.
  * deactivated user + wrong OTP -> generic "Invalid or expired..." (no leak).
  * deactivated user + expired OTP -> generic "Invalid or expired..." (no leak).
  * unknown phone number entirely -> unchanged generic behavior (no leak).
  * a deactivated account's OTP code cannot be reused after being consumed
    by the 403 response (no replay).
  * repeated wrong codes against a deactivated account's OTP still lock out,
    exactly like the active-account path (no weaker brute-force posture).
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


def _unique_phone() -> str:
    return f"075{uuid.uuid4().int % 10**8:08d}"


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(
        prefix="carlist_cnv1fix4_deactivated_login_", ignore_cleanup_errors=True
    )
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ["ALLOW_DEV_CODE_IN_RESPONSE"] = "1"
    os.environ["DB_PATH"] = os.path.join(tmp.name, "deactivated_login.db")

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


def _make_user(app_ctx, *, is_active: bool) -> tuple[int, str]:
    app, _client, db, User = app_ctx
    phone = _unique_phone()
    with app.app_context():
        user = User(
            username=f"cnv1fix4_{uuid.uuid4().hex[:10]}",
            phone_number=phone,
            first_name="Deact",
            last_name="Test",
            is_active=is_active,
            is_verified=True,
            phone_verified=True,
            public_id=f"pub-{uuid.uuid4().hex[:12]}",
        )
        user.set_password("Aa123456!")
        db.session.add(user)
        db.session.commit()
        return user.id, phone


def _start_and_get_code(client, phone: str) -> str:
    r = client.post(
        "/api/auth/phone/start",
        json={"phone_number": phone, "create_if_missing": True},
    )
    assert r.status_code == 200, r.data
    code = r.get_json().get("dev_code")
    assert code and len(code) == 6
    return code


def _verify(client, phone: str, code: str):
    return client.post(
        "/api/auth/phone/verify",
        json={"phone_number": phone, "code": code, "create_if_missing": True},
    )


def test_active_user_valid_otp_logs_in_normally(app_ctx, client):
    _uid, phone = _make_user(app_ctx, is_active=True)
    code = _start_and_get_code(client, phone)

    r = _verify(client, phone, code)
    assert r.status_code == 200, r.data
    body = r.get_json()
    assert "access_token" in body
    assert "refresh_token" in body


def test_deactivated_user_valid_otp_gets_deactivated_response_not_generic_invalid(
    app_ctx, client
):
    _uid, phone = _make_user(app_ctx, is_active=False)
    code = _start_and_get_code(client, phone)

    r = _verify(client, phone, code)
    assert r.status_code == 403, r.data
    body = r.get_json()
    assert body.get("code") == "account_deactivated"
    assert "deactivated" in body["message"].lower()
    assert "access_token" not in body
    assert "invalid" not in body["message"].lower()
    assert "expired" not in body["message"].lower()


def test_deactivated_user_valid_code_cannot_be_replayed(app_ctx, client):
    _uid, phone = _make_user(app_ctx, is_active=False)
    code = _start_and_get_code(client, phone)

    r1 = _verify(client, phone, code)
    assert r1.status_code == 403, r1.data

    # The code was consumed by the first (correct) attempt -- replaying it
    # must NOT succeed a second time, and must NOT match the special
    # deactivated-account branch again (that requires a live, unconsumed
    # code), falling back to the generic invalid-code response.
    r2 = _verify(client, phone, code)
    assert r2.status_code == 400, r2.data
    assert r2.get_json().get("code") != "account_deactivated"


def test_deactivated_user_wrong_otp_gives_generic_invalid_message(app_ctx, client):
    _uid, phone = _make_user(app_ctx, is_active=False)
    real_code = _start_and_get_code(client, phone)
    wrong_code = f"{(int(real_code) + 1) % 1_000_000:06d}"

    r = _verify(client, phone, wrong_code)
    # Must look exactly like the pre-existing generic branch: no
    # `account_deactivated` leak for a wrong code.
    assert r.status_code == 400, r.data
    body = r.get_json()
    assert body.get("code") != "account_deactivated"
    assert "invalid" in body["message"].lower() or "expired" in body["message"].lower()


def test_deactivated_user_expired_otp_gives_generic_invalid_message(app_ctx, client):
    app, _client, db, User = app_ctx
    uid, phone = _make_user(app_ctx, is_active=False)
    code = _start_and_get_code(client, phone)

    with app.app_context():
        user = db.session.get(User, uid)
        user.phone_verification_expires_at = user.phone_verification_expires_at - timedelta(
            minutes=20
        )
        db.session.commit()

    r = _verify(client, phone, code)
    assert r.status_code == 400, r.data
    assert r.get_json().get("code") != "account_deactivated"


def test_unknown_phone_number_behaves_exactly_as_before(app_ctx, client):
    """A phone number with NO account at all (active or not) must produce
    the same response as before this fix -- proves the new deactivated
    check never fires for numbers that were never registered."""
    unknown_phone = _unique_phone()

    r = client.post(
        "/api/auth/phone/verify",
        json={
            "phone_number": unknown_phone,
            "code": "123456",
            "create_if_missing": True,
        },
    )
    assert r.status_code == 400, r.data
    body = r.get_json()
    assert body.get("code") != "account_deactivated"
    assert "invalid" in body["message"].lower() or "expired" in body["message"].lower()


def test_unknown_phone_with_create_if_missing_false_gives_account_not_found(
    app_ctx, client
):
    unknown_phone = _unique_phone()

    r = client.post(
        "/api/auth/phone/verify",
        json={
            "phone_number": unknown_phone,
            "code": "123456",
            "create_if_missing": False,
            "purpose": "login",
        },
    )
    assert r.status_code == 404, r.data
    assert r.get_json().get("code") == "account_not_found"


def test_deactivated_account_otp_still_locks_out_after_repeated_wrong_codes(
    app_ctx, client
):
    """Brute-forcing a deactivated account's OTP must be exactly as hard as
    brute-forcing an active account's -- this new branch must not weaken
    the existing 5-attempt lockout."""
    _uid, phone = _make_user(app_ctx, is_active=False)
    real_code = _start_and_get_code(client, phone)
    wrong_code = f"{(int(real_code) + 1) % 1_000_000:06d}"

    for _ in range(5):
        r = _verify(client, phone, wrong_code)
        assert r.status_code == 400, r.data

    # 6th attempt (even with the CORRECT code) must now be locked out.
    r_locked = _verify(client, phone, real_code)
    assert r_locked.status_code == 429, r_locked.data
    assert "too many attempts" in r_locked.get_json()["message"].lower()
