"""Personal account email changes must be proven, not just accepted (S7).

Before this fix, `PUT /api/user/profile` set `User.email` to whatever the
client sent after only a uniqueness check -- no proof the caller owns that
address. `resolve_profile_email_change` is what the route now consults to
decide whether to apply the change directly or demand an OTP first.
"""

from __future__ import annotations

from flask import Flask

from kk.routes.user import _hash_account_email_change_code, resolve_profile_email_change
from kk.routes.user import _hash_dealer_email_code


def test_setting_a_new_email_requires_a_code():
    is_change, requires_code = resolve_profile_email_change(
        "old@example.com", "new@example.com"
    )
    assert is_change is True
    assert requires_code is True


def test_resubmitting_the_same_email_is_a_noop():
    is_change, requires_code = resolve_profile_email_change(
        "same@example.com", "same@example.com"
    )
    assert is_change is False
    assert requires_code is False


def test_clearing_email_to_blank_does_not_require_a_code():
    is_change, requires_code = resolve_profile_email_change("old@example.com", "")
    assert is_change is True
    assert requires_code is False


def test_placeholder_phone_email_is_treated_as_blank():
    # Phone-OTP signups get a stable `<phone>@phone.local` placeholder; setting
    # a real email for the first time must still require proof.
    is_change, requires_code = resolve_profile_email_change(
        "0770123456@phone.local", "new@example.com"
    )
    assert is_change is True
    assert requires_code is True


def test_resubmitting_blank_over_placeholder_is_a_noop():
    is_change, requires_code = resolve_profile_email_change(
        "0770123456@phone.local", ""
    )
    assert is_change is False
    assert requires_code is False


def test_account_email_change_code_hash_is_namespaced_from_dealer_email_hash():
    # A code intended to confirm a personal account email must never be
    # replayable as a dealer contact-email verification code (or vice versa).
    app = Flask(__name__)
    app.config["SECRET_KEY"] = "test-secret"
    with app.app_context():
        assert _hash_account_email_change_code(
            "a@example.com", "123456"
        ) != _hash_dealer_email_code("a@example.com", "123456")
