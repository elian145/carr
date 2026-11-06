"""Twilio destination formatting (``sms_service._normalize_phone_twilio``).

Formats actually used by the app (evidence, see the F-phone report):

* Flutter sends ``"+964" + <digits typed after a fixed +964 prefix>``
  (``lib/pages/production_login_page.dart`` ``_formattedPhone``,
  ``lib/pages/edit_profile_page_load.dart`` ``'+964$newPhoneDigits'``); there is no
  country picker, Iraq is the only supported country.
* The backend stores ONE canonical form: 10 digits ``7XXXXXXXXX``
  (``kk.routes.auth._normalize_phone``) and passes that stored value to the SMS
  layer.
* Before the fix a stored ``7XXXXXXXXX`` was sent to Twilio as ``+7XXXXXXXXX``
  (Russia/Kazakhstan country code) -- the OTP went to the wrong country.

No real Twilio call is made: ``twilio.rest.Client`` is replaced by a stub.
"""

from __future__ import annotations

import sys
import types

import pytest

from kk import sms_service
from kk.sms_service import SMSService, _normalize_phone_twilio

_ARABIC = "٧٧٠١٢٣٤٥٦٧"  # 7701234567

TABLE = [
    # canonical stored Iraqi mobile
    ("7701234567", "+9647701234567"),
    ("7501234567", "+9647501234567"),
    # national / international spellings of the same subscriber
    ("07701234567", "+9647701234567"),
    ("9647701234567", "+9647701234567"),
    ("009647701234567", "+9647701234567"),
    ("+9647701234567", "+9647701234567"),  # already E.164: unchanged
    ("+964 770 123 4567", "+9647701234567"),
    ("+96407701234567", "+9647701234567"),  # "+964" + number typed with its 0
    (_ARABIC, "+9647701234567"),
    ("0" + _ARABIC, "+9647701234567"),
    # Iraqi landline in E.164 stays as it is
    ("+96418123456", "+96418123456"),
    # E.164 of other countries is never touched
    ("+12025550123", "+12025550123"),
    ("+447911123456", "+447911123456"),
    ("+971501234567", "+971501234567"),
    # foreign numbers without "+" that carry a country code
    ("447911123456", "+447911123456"),
    ("12025550123", "+12025550123"),
    ("00447911123456", "+447911123456"),
    # unknown / ambiguous: returned as typed (Twilio rejects, nothing is mis-sent)
    ("2025550123", "2025550123"),  # bare 10-digit non-Iraqi-mobile
    ("1234567890", "1234567890"),
    ("0123456789", "0123456789"),
    ("12345", "12345"),
    ("abc", "abc"),
    ("", ""),
    (None, ""),
]


@pytest.mark.parametrize("raw,expected", TABLE)
def test_twilio_destination_formatting(raw, expected):
    assert _normalize_phone_twilio(raw) == expected


def test_canonical_iraqi_number_is_never_prefixed_with_plus_seven():
    # Regression for the reported bug: +7701234567 is a Russian number.
    out = _normalize_phone_twilio("7701234567")
    assert out == "+9647701234567"
    assert not out.startswith("+77")


@pytest.mark.parametrize("raw", [e164 for raw, e164 in TABLE if e164.startswith("+") and raw == e164])
def test_e164_is_idempotent_and_unchanged(raw):
    assert _normalize_phone_twilio(raw) == raw
    assert _normalize_phone_twilio(_normalize_phone_twilio(raw)) == raw


@pytest.mark.parametrize("raw,expected", [r for r in TABLE if r[0]])
def test_normalisation_is_idempotent(raw, expected):
    once = _normalize_phone_twilio(raw)
    assert _normalize_phone_twilio(once) == once


def test_canonical_form_from_auth_routes_is_sent_as_plus_964(monkeypatch):
    """End to end over the SAME canonicaliser the app stores with."""
    from kk.routes.auth import _normalize_phone

    for typed in ("07701234567", "+9647701234567", "009647701234567", _ARABIC):
        stored = _normalize_phone(typed)
        assert stored == "7701234567"
        assert _normalize_phone_twilio(stored) == "+9647701234567"


class _StubMessages:
    def __init__(self, sink):
        self.sink = sink

    def create(self, **kwargs):
        self.sink.append(kwargs)
        return types.SimpleNamespace(sid="SMSTUB")


def _install_stub_twilio(monkeypatch, sink):
    class Client:
        def __init__(self, sid, token):
            assert (sid, token) == ("ACstub", "tokstub")
            self.messages = _StubMessages(sink)

    twilio = types.ModuleType("twilio")
    rest = types.ModuleType("twilio.rest")
    rest.Client = Client
    twilio.rest = rest
    monkeypatch.setitem(sys.modules, "twilio", twilio)
    monkeypatch.setitem(sys.modules, "twilio.rest", rest)


def _service(monkeypatch):
    monkeypatch.setenv("SMS_PROVIDER", "twilio")
    monkeypatch.setenv("TWILIO_ACCOUNT_SID", "ACstub")
    monkeypatch.setenv("TWILIO_AUTH_TOKEN", "tokstub")
    monkeypatch.setenv("TWILIO_PHONE_NUMBER", "+15005550006")
    return SMSService()


def test_verification_sms_uses_normalised_destination_with_stubbed_client(monkeypatch):
    sent: list[dict] = []
    _install_stub_twilio(monkeypatch, sent)
    svc = _service(monkeypatch)
    ok, detail = svc.send_verification_code("7701234567", "123456")
    assert ok is True, detail
    assert [m["to"] for m in sent] == ["+9647701234567"]
    assert sent[0]["from_"] == "+15005550006"  # provider config untouched


def test_password_reset_sms_uses_normalised_destination_with_stubbed_client(monkeypatch):
    sent: list[dict] = []
    _install_stub_twilio(monkeypatch, sent)
    svc = _service(monkeypatch)
    ok, detail = svc.send_password_reset_code("07701234567", "654321")
    assert ok is True, detail
    assert [m["to"] for m in sent] == ["+9647701234567"]


def test_foreign_e164_reaches_the_stubbed_client_unchanged(monkeypatch):
    sent: list[dict] = []
    _install_stub_twilio(monkeypatch, sent)
    svc = _service(monkeypatch)
    ok, _detail = svc.send_verification_code("+12025550123", "123456")
    assert ok is True
    assert sent[0]["to"] == "+12025550123"


def test_provider_selection_is_unchanged(monkeypatch):
    monkeypatch.setenv("SMS_PROVIDER", "console")
    assert SMSService().provider == "console"
    monkeypatch.setenv("SMS_PROVIDER", "twilio")
    assert SMSService().provider == "twilio"
    assert sms_service._normalize_phone_otpiq("7701234567") == "9647701234567"  # untouched path
