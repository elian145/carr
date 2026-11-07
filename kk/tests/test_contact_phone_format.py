"""Strict Iraqi-mobile normalisation for listing contact phones (pure unit tests).

``kk/phone_format.py`` maps every accepted spelling of an Iraqi mobile to ONE
canonical key ``7XXXXXXXXX`` and rejects everything else. No app / database is
needed except for the OTP-hash helpers, which only need a ``SECRET_KEY``.
"""

from __future__ import annotations

import hmac
import hashlib
import sys
import uuid
from pathlib import Path
from types import SimpleNamespace

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from kk.phone_format import (  # noqa: E402
    normalize_iraqi_mobile,
    normalize_stored_iraqi_mobile,
    to_e164_iraq,
)

_ARABIC = str.maketrans("0123456789", "٠١٢٣٤٥٦٧٨٩")
_PERSIAN = str.maketrans("0123456789", "۰۱۲۳۴۵۶۷۸۹")
C = "7701234567"  # canonical key used by the table


def _spellings(c: str) -> list[str]:
    return [
        c,
        "0" + c,
        "+964" + c,
        "964" + c,
        "00964" + c,
        # typo: trunk zero after the country code
        "+9640" + c,
        "9640" + c,
        "009640" + c,
        "009640 " + c[:3] + " " + c[3:],
        "+964 0" + c,
        # formatting noise
        f"0{c[:3]} {c[3:6]} {c[6:]}",
        f"0{c[:3]}-{c[3:6]}-{c[6:]}",
        f"(0{c[:3]}) {c[3:6]}-{c[6:]}",
        f"+964 ({c[:3]}) {c[3:6]}.{c[6:]}",
        f"  {c}  ",
        "\u200e+964" + c,
        # non-ASCII digits
        ("0" + c).translate(_ARABIC),
        ("+964" + c).translate(_PERSIAN),
        c.translate(_ARABIC),
        ("009640" + c).translate(_PERSIAN),
    ]


@pytest.mark.parametrize("typed", _spellings(C))
def test_every_accepted_spelling_gives_the_canonical_key(typed):
    assert normalize_iraqi_mobile(typed) == C
    assert to_e164_iraq(typed) == "+964" + C


@pytest.mark.parametrize("c", ["7501234567", "7701234567", "7801234567", "7901234567", "7000000000"])
def test_any_7_prefixed_mobile_is_accepted_no_operator_prefix_table(c):
    # Evidence: Flutter normaliser + sms_service only require "7" + 9 digits.
    for typed in _spellings(c):
        assert normalize_iraqi_mobile(typed) == c


def test_canonical_form_is_idempotent_and_e164_round_trips():
    assert normalize_iraqi_mobile(C) == C
    assert normalize_iraqi_mobile(to_e164_iraq(C)) == C
    assert to_e164_iraq(to_e164_iraq(C)) == "+964" + C


@pytest.mark.parametrize(
    "bad",
    [
        None,
        "",
        "   ",
        "abc",
        "!!!",
        True,
        # wrong lengths
        "7",
        "77012345",  # 8
        "770123456",  # 9
        "77012345678",  # 11 not starting with 0
        "770123456789",  # 12
        "0770123456",  # 10 starting with 0
        "077012345678",  # 12 starting with 0
        "07701234",  # short national
        # 10 digits that are not a 7-mobile (ambiguous: used to get +964 glued on)
        "2025550123",
        "1234567890",
        "6701234567",
        "8701234567",
        "9701234567",
        "0000000000",
        # landline-looking (Baghdad 01, Erbil 066, ...)
        "0112345678",
        "01234567",
        "06612345678",
        "+9641 2345678",
        "9641 2345678",
        "+96466 1234567",
        "009641 234 5678",
        # foreign numbers
        "+12025550123",
        "+447911123456",
        "447911123456",
        "+201001234567",
        "00201001234567",
        "+79161234567",
        "+7701234567",  # explicit '+' with a non-964 country: never Iraq
        "0044 7911 123456",
        # wrong Iraq forms
        "+964",
        "964",
        "9647",
        "+96477012345",  # short
        "+964770123456789",  # long
        "+96400770123456",  # two trunk zeros
        "+9641234567890",  # 964 + non-7 national
        "+96407",
        "+0964" + C,
        "+00964" + C,
        # letters / symbols inside
        "07701abc234",
        "0770-123-45x7",
        "07701234567ext1",
        "077#0123456",
        # plus not at the start
        "770+1234567",
        "07+701234567",
        "++9647701234567",
        # zero-width / unsupported digit-like characters
        "7\u00b2" + "01234567",  # superscript two is not a decimal digit
        # two numbers glued together
        "07701234567 07701234568",
        "07701234567,07701234568",
    ],
)
def test_invalid_inputs_are_rejected(bad):
    assert normalize_iraqi_mobile(bad) is None
    assert to_e164_iraq(bad) is None


def test_dots_are_separators_not_garbage():
    assert normalize_iraqi_mobile("77.01234567.") == "7701234567"


def test_non_string_values_never_raise():
    for value in (12345, 7701234567, 0.5, [], {}, b"7701234567", object()):
        normalize_iraqi_mobile(value)  # must not raise
    assert normalize_iraqi_mobile(7701234567) == "7701234567"


def test_stored_normaliser_adds_only_the_old_0964_spelling():
    assert normalize_stored_iraqi_mobile("09647701234567") == "7701234567"
    assert normalize_stored_iraqi_mobile("+96407701234567") == "7701234567"
    assert normalize_stored_iraqi_mobile("07701234567") == "7701234567"
    # fresh-input normaliser does NOT accept the odd 0964 spelling
    assert normalize_iraqi_mobile("09647701234567") is None
    for bad in ("", None, "garbage", "+12025550123", "0964123456789"):
        assert normalize_stored_iraqi_mobile(bad) is None


# --------------------------------------------------------------------------
# parse_listing_contact_phones / invalid_listing_contact_phones / assert_*
# --------------------------------------------------------------------------
from kk.routes import user as user_routes  # noqa: E402


def test_parse_stores_only_valid_e164_and_never_a_plus_9640_form():
    for typed in _spellings(C):
        out = user_routes.parse_listing_contact_phones({"contact_phones": [typed]})
        assert out == ["+964" + C], typed
        assert "+9640" not in out[0]
        single = user_routes.parse_listing_contact_phones({"contact_phone": typed})
        assert single == ["+964" + C], typed


def test_parse_dedupes_by_subscriber_and_caps_at_three():
    data = {"contact_phones": ["07701234567", "7701234567", "+9647701234567", "009647701234567"]}
    assert user_routes.parse_listing_contact_phones(data) == ["+9647701234567"]
    many = {"contact_phones": [f"770123456{i}" for i in range(6)]}
    assert user_routes.parse_listing_contact_phones(many) == [
        "+9647701234560",
        "+9647701234561",
        "+9647701234562",
    ]


def test_parse_drops_invalid_entries_and_flags_them():
    data = {"contact_phones": ["07701234567", "2025550123", "0112345678"]}
    assert user_routes.parse_listing_contact_phones(data) == ["+9647701234567"]
    assert user_routes.invalid_listing_contact_phones(data) == ["2025550123", "0112345678"]
    assert user_routes.invalid_listing_contact_phones({"contact_phones": ["07701234567"]}) == []
    assert user_routes.invalid_listing_contact_phones({}) == []
    assert user_routes.invalid_listing_contact_phones({"contact_phones": []}) == []
    assert user_routes.invalid_listing_contact_phones({"contact_phone": ""}) == []
    assert user_routes.invalid_listing_contact_phones({"contact_phone": None}) == []
    assert user_routes.invalid_listing_contact_phones({"contact_phone": "abc"}) == ["abc"]
    assert user_routes.invalid_listing_contact_phones({"contact_phone": 12345}) == ["12345"]


def test_parse_accepts_a_numeric_contact_phone_without_crashing():
    assert user_routes.parse_listing_contact_phones({"contact_phone": 7701234567}) == ["+9647701234567"]


def test_contact_phones_list_wins_over_single_contact_phone():
    data = {"contact_phones": ["07701234567"], "contact_phone": "garbage"}
    assert user_routes.invalid_listing_contact_phones(data) == []
    assert user_routes.parse_listing_contact_phones(data) == ["+9647701234567"]


_LEGACY_VERIFIED = ["07701234567", "7701234567", "+9647701234567", "+96407701234567", "9647701234567"]


@pytest.mark.parametrize("stored", _LEGACY_VERIFIED)
@pytest.mark.parametrize("typed", _spellings(C))
def test_legacy_verified_spellings_verify_the_same_number_in_any_spelling(stored, typed):
    user = SimpleNamespace(contact_verified_phones=[stored], phone_number="7999999999")
    assert user_routes._verified_contact_phone_digits(user) == [C, "7999999999"]
    assert user_routes.assert_listing_phones_verified(user, [typed]) is None


@pytest.mark.parametrize("own", [C, "0" + C, "+964" + C, "00964" + C, "+9640" + C, "0964" + C])
@pytest.mark.parametrize("typed", _spellings(C))
def test_own_account_phone_is_acceptable_in_any_spelling(own, typed):
    user = SimpleNamespace(contact_verified_phones=None, phone_number=own)
    assert user_routes.assert_listing_phones_verified(user, [typed]) is None


def test_assert_rejects_unverified_other_and_invalid_phones():
    user = SimpleNamespace(contact_verified_phones=["7701234567"], phone_number="7711111111")
    msg = "Verify each contact phone with a code before publishing"
    assert user_routes.assert_listing_phones_verified(user, ["07701234568"]) == msg
    assert user_routes.assert_listing_phones_verified(user, ["07701234567", "07701234568"]) == msg
    assert user_routes.assert_listing_phones_verified(user, ["2025550123"]) == "Enter a valid phone number"
    assert user_routes.assert_listing_phones_verified(user, ["+9647701234567", "07711111111"]) is None
    # non-iraqi / garbage legacy values in the verified list never verify anything
    junk = SimpleNamespace(contact_verified_phones=["2025550123", "abc", None, 5], phone_number="")
    assert user_routes._verified_contact_phone_digits(junk) == []


# --------------------------------------------------------------------------
# OTP hash: canonical key + legacy typed-spelling hash
# --------------------------------------------------------------------------
@pytest.fixture
def flask_ctx():
    from flask import Flask

    app = Flask(__name__)
    app.config["SECRET_KEY"] = "unit-test-secret-" + uuid.uuid4().hex
    with app.app_context():
        yield app


def _legacy_hash(app, typed_digits: str, code: str) -> str:
    return hmac.new(
        app.config["SECRET_KEY"].encode(),
        f"contact-phone:{typed_digits}:{code}".encode(),
        hashlib.sha256,
    ).hexdigest()


def test_hash_is_namespaced_and_bound_to_key_and_code(flask_ctx):
    h = user_routes._hash_contact_phone_code(C, "123456")
    assert h == _legacy_hash(flask_ctx, C, "123456")
    assert h != user_routes._hash_contact_phone_code(C, "123457")
    assert h != user_routes._hash_contact_phone_code("7701234568", "123456")
    assert h != user_routes._hash_dealer_phone_code(C, "123456")


def test_code_matches_canonical_and_both_legacy_typed_spellings_only(flask_ctx):
    code = "654321"
    assert user_routes._contact_phone_code_matches(user_routes._hash_contact_phone_code(C, code), C, code)
    # legacy: issued over the typed 11-digit spelling 07XXXXXXXXX
    assert user_routes._contact_phone_code_matches(_legacy_hash(flask_ctx, "0" + C, code), C, code)
    # legacy: issued over the typed 10-digit spelling (== canonical hash)
    assert user_routes._contact_phone_code_matches(_legacy_hash(flask_ctx, C, code), C, code)
    # wrong code / other number / other namespace never match
    assert not user_routes._contact_phone_code_matches(_legacy_hash(flask_ctx, "0" + C, code), C, "000000")
    assert not user_routes._contact_phone_code_matches(_legacy_hash(flask_ctx, "0" + C, code), "7701234568", code)
    assert not user_routes._contact_phone_code_matches(user_routes._hash_dealer_phone_code(C, code), C, code)
    assert not user_routes._contact_phone_code_matches("", C, code)
    assert not user_routes._contact_phone_code_matches(None, C, code)


# --------------------------------------------------------------------------
# read-time display normalisation of stored (legacy) listing phones
# --------------------------------------------------------------------------
def _car(**kw):
    return SimpleNamespace(contact_phone=kw.get("contact_phone"), contact_phones=kw.get("contact_phones"))


def test_display_list_repairs_malformed_legacy_values_and_dedupes():
    from kk.models import _listing_contact_phone_list

    car = _car(contact_phone="+96407701234567", contact_phones=["+96407701234567", "07701234567", "7701234567"])
    assert _listing_contact_phone_list(car) == ["+9647701234567"]
    car = _car(contact_phone="07701234567", contact_phones=None)
    assert _listing_contact_phone_list(car) == ["+9647701234567"]
    car = _car(contact_phone="+9647701234567", contact_phones=["+9647709999999"])
    assert _listing_contact_phone_list(car) == ["+9647709999999", "+9647701234567"]


def test_display_list_leaves_unnormalisable_values_untouched():
    from kk.models import _listing_contact_phone_list

    car = _car(contact_phone="+12025550123", contact_phones=["2025550123", " 0112345678 ", "n/a"])
    assert _listing_contact_phone_list(car) == ["2025550123", "0112345678", "n/a", "+12025550123"]
    assert _listing_contact_phone_list(_car()) == []
    assert _listing_contact_phone_list(_car(contact_phone="  ", contact_phones=[None, ""])) == []
