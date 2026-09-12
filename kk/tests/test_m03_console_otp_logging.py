"""M-03: the console SMS provider must never route the plaintext OTP through
the Python ``logging`` module.

Bug (PRODUCTION_AUDIT.md M-03): ``SMSService._send_via_console()`` and
``SMSService._send_verification_via_console()`` printed the OTP to stdout
(intentional, for local developer visibility) *and* also logged it in full
via ``logger.info(...)``. Anything routed through ``logging`` can end up
persisted in CI logs, forwarded to log aggregation, or captured as a
breadcrumb by monitoring integrations (e.g. ``sentry_sdk``'s default
``LoggingIntegration``, which is active whenever ``SENTRY_DSN`` is set --
see ``kk/monitoring.py``) -- a materially wider exposure surface than "only
visible in a local terminal".

The fix removes the two ``logger.info(...)`` calls but intentionally keeps
the existing ``print(...)`` statements: the console SMS provider is a
developer convenience whose entire purpose is to make the OTP visible in a
local terminal, and that workflow is preserved unchanged.

M-01's separately-fixed production guard (``_app_env() == "production"``
blocking the console provider entirely) is untouched by this fix and is
re-verified here as a regression guard (test D).

These tests exercise ``SMSService`` directly (no Flask app/DB needed --
console SMS sending has no such dependency), matching the narrow-unit-test
convention used elsewhere in this suite for isolated helpers.
"""

from __future__ import annotations

import logging
import sys
from pathlib import Path

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from kk.sms_service import SMSService  # noqa: E402

# Distinct, obviously-fake test values -- never real secrets, tokens, or PII.
_RESET_CODE = "135790"
_VERIFICATION_CODE = "246801"
_PHONE = "07701234567"


def _service() -> SMSService:
    """A fresh SMSService instance (reload_config() reads env at construction
    and again inside each send_* call, so this always reflects current env)."""
    return SMSService()


# ---------------------------------------------------------------------------
# A -- password-reset console path never logs the OTP
# ---------------------------------------------------------------------------


def test_A_console_password_reset_does_not_log_otp(monkeypatch, caplog):
    monkeypatch.setenv("APP_ENV", "testing")
    monkeypatch.delenv("FLASK_ENV", raising=False)

    with caplog.at_level(logging.DEBUG):
        ok, detail = _service()._send_via_console(_PHONE, _RESET_CODE)

    assert ok is True
    assert detail == ""

    for record in caplog.records:
        assert _RESET_CODE not in record.getMessage(), (
            f"plaintext reset OTP leaked into a log record: {record.getMessage()!r}"
        )
    assert _RESET_CODE not in caplog.text


# ---------------------------------------------------------------------------
# B -- phone-verification console path never logs the OTP
# ---------------------------------------------------------------------------


def test_B_console_verification_does_not_log_otp(monkeypatch, caplog):
    monkeypatch.setenv("APP_ENV", "development")
    monkeypatch.delenv("FLASK_ENV", raising=False)

    with caplog.at_level(logging.DEBUG):
        ok, detail = _service()._send_verification_via_console(_PHONE, _VERIFICATION_CODE)

    assert ok is True
    assert detail == ""

    for record in caplog.records:
        assert _VERIFICATION_CODE not in record.getMessage(), (
            f"plaintext verification OTP leaked into a log record: {record.getMessage()!r}"
        )
    assert _VERIFICATION_CODE not in caplog.text


# ---------------------------------------------------------------------------
# C -- the developer-facing print() workflow is preserved unchanged
# ---------------------------------------------------------------------------


def test_C_console_print_still_exposes_otp_to_local_terminal(monkeypatch, capsys):
    monkeypatch.setenv("APP_ENV", "testing")
    monkeypatch.delenv("FLASK_ENV", raising=False)

    ok, _detail = _service()._send_via_console(_PHONE, _RESET_CODE)
    assert ok is True
    out = capsys.readouterr().out
    assert _RESET_CODE in out

    ok, _detail = _service()._send_verification_via_console(_PHONE, _VERIFICATION_CODE)
    assert ok is True
    out = capsys.readouterr().out
    assert _VERIFICATION_CODE in out


# ---------------------------------------------------------------------------
# D -- M-01's production guard regression: still blocked, still no OTP
# anywhere (not in logs, not in the returned detail message).
# ---------------------------------------------------------------------------


def test_D_production_guard_still_blocks_console_and_never_emits_otp(monkeypatch, caplog):
    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.delenv("FLASK_ENV", raising=False)

    with caplog.at_level(logging.DEBUG):
        ok, detail = _service()._send_via_console(_PHONE, _RESET_CODE)
    assert ok is False
    assert "not allowed in production" in detail
    assert _RESET_CODE not in detail
    assert _RESET_CODE not in caplog.text

    caplog.clear()
    with caplog.at_level(logging.DEBUG):
        ok, detail = _service()._send_verification_via_console(_PHONE, _VERIFICATION_CODE)
    assert ok is False
    assert "not allowed in production" in detail
    assert _VERIFICATION_CODE not in detail
    assert _VERIFICATION_CODE not in caplog.text


@pytest.mark.parametrize("unset_env", [True])
def test_D2_unset_app_env_defaults_to_production_and_blocks_console(monkeypatch, caplog, unset_env):
    """Regression guard for the M-01 fail-safe default this fix depends on:
    an unset APP_ENV/FLASK_ENV must resolve to "production" (via
    kk.config.get_app_env()), which keeps the console provider blocked even
    if a deploy simply forgets to set APP_ENV."""
    monkeypatch.delenv("APP_ENV", raising=False)
    monkeypatch.delenv("FLASK_ENV", raising=False)

    with caplog.at_level(logging.DEBUG):
        ok, detail = _service()._send_via_console(_PHONE, _RESET_CODE)
    assert ok is False
    assert "not allowed in production" in detail
    assert _RESET_CODE not in caplog.text


# ---------------------------------------------------------------------------
# E -- behavioral regression guard: sending via console must never produce
# ANY log record (at INFO or above) containing the OTP, exercised through
# the public send_password_reset_code()/send_verification_code() entry
# points (not just the private _send_via_console* helpers), so this also
# covers SMSService.reload_config() being re-invoked on every call.
# ---------------------------------------------------------------------------


def test_E_public_entry_points_do_not_log_otp(monkeypatch, caplog):
    monkeypatch.setenv("APP_ENV", "testing")
    monkeypatch.setenv("SMS_PROVIDER", "console")
    monkeypatch.delenv("FLASK_ENV", raising=False)

    service = _service()

    with caplog.at_level(logging.INFO):
        ok, _detail = service.send_password_reset_code(_PHONE, _RESET_CODE)
    assert ok is True
    assert _RESET_CODE not in caplog.text

    caplog.clear()
    with caplog.at_level(logging.INFO):
        ok, _detail = service.send_verification_code(_PHONE, _VERIFICATION_CODE)
    assert ok is True
    assert _VERIFICATION_CODE not in caplog.text
