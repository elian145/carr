"""Listing-contact phone flows end to end (SQLite, real routes, stubbed SMS).

Before: ``parse_listing_contact_phones`` stored ``+964`` + the typed digits, so a
number typed with its national leading ``0`` became the invalid
``+96407701234567``; the OTP hash / ``contact_verified_phones`` used the typed
spelling, so one SIM typed ``07...`` vs ``7...`` was two different numbers (even a
user's OWN account phone typed as ``07...`` failed "Verify each contact phone").

Now every spelling collapses to one canonical key ``7XXXXXXXXX``; the stored
listing phone is always ``+9647XXXXXXXXX``; invalid input is a 400 and never
reaches the SMS sender; legacy rows keep working without any data migration.
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

_PASSWORD = "Aa123456!"
_VERIFY_FIRST = "Verify each contact phone with a code before publishing"
_INVALID = "Enter a valid phone number"
_ARABIC = str.maketrans("0123456789", "٠١٢٣٤٥٦٧٨٩")
_PERSIAN = str.maketrans("0123456789", "۰۱۲۳۴۵۶۷۸۹")


def _canonical() -> str:
    return f"7{uuid.uuid4().int % 10**9:09d}"


def _spellings(c: str) -> list[str]:
    return [
        "0" + c,
        c,
        "+964" + c,
        "009647" + c[1:],
        "964" + c,
        "+9640" + c,  # the app's "+964" + a number typed with its national 0
        "009640" + c,
        f"+964 {c[:3]} {c[3:6]} {c[6:]}",
        f"0{c[:3]}-{c[3:6]}-{c[6:]}",
        ("0" + c).translate(_ARABIC),
        ("+964" + c).translate(_PERSIAN),
    ]


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_contact_phone_", ignore_cleanup_errors=True)
    saved = {k: os.environ.get(k) for k in ("DATABASE_URL", "AUTO_MIGRATE", "ALLOW_DEV_CODE_IN_RESPONSE")}
    for key in ("DATABASE_URL", "AUTO_MIGRATE"):
        os.environ.pop(key, None)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ["ALLOW_DEV_CODE_IN_RESPONSE"] = "1"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "contact_phone.db")
    os.environ["UPLOAD_FOLDER"] = os.path.join(tmp.name, "uploads")

    from kk.app_factory import create_app

    app, _socketio, *_ = create_app()
    from kk.models import Car, User, db

    with app.app_context():
        db.drop_all()
        db.create_all()

    yield app, app.test_client(), db, User, Car

    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    tmp.cleanup()
    for key, value in saved.items():
        if value is None:
            os.environ.pop(key, None)
        else:
            os.environ[key] = value


@pytest.fixture
def client(app_ctx):
    return app_ctx[1]


@pytest.fixture(autouse=True)
def sms(monkeypatch):
    """Stub the SMS sender; ``sms`` is the list of ``(phone, code)`` calls."""
    calls: list[tuple[str, str]] = []

    def fake(phone, code):
        calls.append((phone, code))
        return True, None

    monkeypatch.setattr("kk.sms_service.send_verification_sms_result", fake)
    return calls


# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------
def _headers(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _make_user(app_ctx, stored_phone: str | None = None, contact_verified=None) -> dict:
    app, _client, db, User, _Car = app_ctx
    stored_phone = stored_phone or _canonical()
    with app.app_context():
        user = User(
            username=f"cp_{uuid.uuid4().hex[:10]}",
            phone_number=stored_phone,
            first_name="Contact",
            last_name="Phone",
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id=f"cp-{uuid.uuid4().hex[:12]}",
        )
        user.set_password(_PASSWORD)
        if contact_verified is not None:
            user.contact_verified_phones = list(contact_verified)
        db.session.add(user)
        db.session.commit()
        uid, username = user.id, user.username
    return {"id": uid, "username": username, "phone": stored_phone, "headers": _login(app_ctx, username)}


def _login(app_ctx, username: str) -> dict:
    client = app_ctx[1]
    r = client.post("/api/auth/login", json={"username": username, "password": _PASSWORD})
    assert r.status_code == 200, r.data
    return _headers(r.get_json()["access_token"])


def _register(app_ctx, sms, typed: str) -> dict:
    """Real registration: send_otp -> signup, with the phone typed as ``typed``."""
    client = app_ctx[1]
    sent = client.post("/api/auth/send_otp", json={"phone": typed})
    assert sent.status_code == 200, sent.data
    code = sms[-1][1]
    username = f"reg_{uuid.uuid4().hex[:10]}"
    r = client.post(
        "/api/auth/signup",
        json={
            "phone": typed,
            "otp_code": code,
            "username": username,
            "password": _PASSWORD,
            "first_name": "Reg",
            "last_name": "User",
        },
    )
    assert r.status_code == 201, r.data
    return {"username": username, "headers": _headers(r.get_json()["access_token"])}


def _user_row(app_ctx, username: str) -> dict:
    app, _client, db, User, _Car = app_ctx
    with app.app_context():
        u = User.query.filter_by(username=username).first()
        return {
            "id": u.id,
            "phone": u.phone_number,
            "contact_verified": list(u.contact_verified_phones or []),
            "hash": u.phone_verification_code_hash,
            "attempts": u.phone_verification_attempts,
            "locked": u.phone_verification_locked_until,
            "expires": u.phone_verification_expires_at,
        }


def _expire_cooldown(app_ctx, username: str) -> None:
    app, _client, db, User, _Car = app_ctx
    with app.app_context():
        u = User.query.filter_by(username=username).first()
        u.phone_verification_last_sent_at = None
        db.session.commit()


def _send(app_ctx, headers, username, typed):
    _expire_cooldown(app_ctx, username)
    return app_ctx[1].post(
        "/api/user/contact-phone/send-verification", json={"phone_number": typed}, headers=headers
    )


def _verify(client, headers, typed, code):
    return client.post(
        "/api/user/contact-phone/verify",
        json={"phone_number": typed, "verification_code": code},
        headers=headers,
    )


def _payload(**overrides) -> dict:
    payload = {
        "brand": "toyota",
        "model": "camry",
        "year": 2021,
        "mileage": 1000,
        "price": 15000,
        "location": "Erbil",
        "condition": "used",
        "body_type": "sedan",
        "transmission": "automatic",
        "drive_type": "fwd",
    }
    payload.update(overrides)
    return payload


def _publish(client, headers, **overrides):
    return client.post("/api/cars", json=_payload(**overrides), headers=headers)


def _stored_listing(app_ctx, public_id: str) -> dict:
    app, _client, db, _User, Car = app_ctx
    with app.app_context():
        car = Car.query.filter_by(public_id=public_id).first()
        return {"contact_phone": car.contact_phone, "contact_phones": car.contact_phones}


def _set_listing_phones(app_ctx, public_id: str, phone: str) -> None:
    app, _client, db, _User, Car = app_ctx
    with app.app_context():
        car = Car.query.filter_by(public_id=public_id).first()
        car.contact_phone = phone
        car.contact_phones = [phone]
        db.session.commit()


def _car_count(app_ctx, seller_id: int) -> int:
    app, _client, db, _User, Car = app_ctx
    with app.app_context():
        return Car.query.filter_by(seller_id=seller_id).count()


def _make_car(app_ctx, seller_id: int, status: str = "pending", **extra) -> str:
    app, _client, db, _User, Car = app_ctx
    with app.app_context():
        car = Car(
            seller_id=seller_id,
            public_id=f"car-{uuid.uuid4().hex[:12]}",
            brand="toyota",
            model="corolla",
            year=2021,
            mileage=10,
            engine_type="gas",
            transmission="auto",
            drive_type="fwd",
            condition="used",
            body_type="sedan",
            price=15000,
            location="Erbil",
            is_active=True,
            status=status,
            **extra,
        )
        db.session.add(car)
        db.session.commit()
        return car.public_id


def _assert_well_formed(phones):
    for phone in phones or []:
        assert phone.startswith("+9647") and len(phone) == 14 and phone[1:].isdigit(), phone
        assert "+9640" not in phone


# --------------------------------------------------------------------------
# 1. registration -> profile phone -> listing contact, every spelling
# --------------------------------------------------------------------------
@pytest.mark.parametrize("reg_idx", range(11))
def test_registration_profile_and_listing_contact_flow_for_each_spelling(app_ctx, client, sms, reg_idx):
    c = _canonical()
    typed_at_signup = _spellings(c)[reg_idx]
    reg = _register(app_ctx, sms, typed_at_signup)
    username, headers = reg["username"], reg["headers"]
    assert _user_row(app_ctx, username)["phone"] == c  # profile phone is canonical
    sms_before = len(sms)

    # profile re-save of the same SIM in any spelling is a no-op (Phone agent's contract)
    # (the profile route has its own input validator, owned by the Phone work: it
    # rejects a few exotic spellings such as ``009640...``; use the app's own forms)
    for profile_typed in ("+964" + c, "0" + c, c):
        r = client.put("/api/user/profile", json={"phone_number": profile_typed, "first_name": "Same"}, headers=headers)
        assert r.status_code == 200, (profile_typed, r.data)
        assert _user_row(app_ctx, username)["phone"] == c

    # the account's OWN phone, typed in ANY spelling, is a valid listing contact
    # without an OTP, is "already verified" and sends no SMS
    for typed in _spellings(c):
        s = client.post(
            "/api/user/contact-phone/send-verification", json={"phone_number": typed}, headers=headers
        )
        assert s.status_code == 200 and s.get_json()["verified"] is True, (typed, s.data)
        v = _verify(client, headers, typed, "123456")
        assert v.status_code == 200, (typed, v.data)
        assert v.get_json()["verified_phone"] == c

        r = _publish(client, headers, contact_phones=[typed])
        assert r.status_code == 201, (typed, r.data)
        stored = _stored_listing(app_ctx, r.get_json()["car"]["id"])
        assert stored["contact_phones"] == ["+964" + c], typed
        assert stored["contact_phone"] == "+964" + c
        _assert_well_formed(stored["contact_phones"])
    assert len(sms) == sms_before  # not one SMS for the own number


# --------------------------------------------------------------------------
# 2. listing-contact OTP: send + verify + publish across spellings
# --------------------------------------------------------------------------
@pytest.mark.parametrize("idx", range(11))
def test_contact_otp_send_verify_publish_are_spelling_independent(app_ctx, client, sms, idx):
    me = _make_user(app_ctx)
    other = _canonical()
    forms = _spellings(other)
    send_as, verify_as, publish_as = forms[idx], forms[(idx + 3) % len(forms)], forms[(idx + 5) % len(forms)]

    # not verified yet: publishing is refused (in any spelling)
    r = _publish(client, me["headers"], contact_phones=[publish_as])
    assert r.status_code == 400 and r.get_json()["message"] == _VERIFY_FIRST

    s = _send(app_ctx, me["headers"], me["username"], send_as)
    assert s.status_code == 200 and s.get_json()["sent"] is True, s.data
    assert len(sms) == 1
    assert sms[0][0] == other  # the SMS sender receives the canonical key
    code = sms[0][1]
    row = _user_row(app_ctx, me["username"])
    assert row["hash"]

    # a code requested for one spelling verifies for another
    v = _verify(client, me["headers"], verify_as, code)
    assert v.status_code == 200, v.data
    assert v.get_json()["verified_phone"] == other
    assert other in v.get_json()["contact_verified_phones"]
    row = _user_row(app_ctx, me["username"])
    assert row["contact_verified"] == [other]  # canonical key stored (never typed spelling)
    assert row["hash"] is None and row["expires"] is None and row["attempts"] == 0

    for spelling in (send_as, verify_as, publish_as):
        r = _publish(client, me["headers"], contact_phones=[spelling])
        assert r.status_code == 201, (spelling, r.data)
        stored = _stored_listing(app_ctx, r.get_json()["car"]["id"])
        assert stored["contact_phones"] == ["+964" + other]
        assert stored["contact_phone"] == "+964" + other
        _assert_well_formed(stored["contact_phones"])

    # verifying again in yet another spelling does not duplicate the entry
    v2 = _verify(client, me["headers"], forms[(idx + 1) % len(forms)], code)
    assert v2.status_code == 200
    assert _user_row(app_ctx, me["username"])["contact_verified"] == [other]


@pytest.mark.parametrize("typed", ["07701234567", "7701234567", "+9647701234567", "009647701234567"])
def test_the_four_documented_spellings_publish_end_to_end(app_ctx, client, sms, typed):
    me = _make_user(app_ctx)
    s = _send(app_ctx, me["headers"], me["username"], typed)
    assert s.status_code == 200, s.data
    assert _verify(client, me["headers"], typed, sms[-1][1]).status_code == 200
    r = _publish(client, me["headers"], contact_phone=typed)  # single-field form
    assert r.status_code == 201, r.data
    stored = _stored_listing(app_ctx, r.get_json()["car"]["id"])
    assert stored == {"contact_phone": "+9647701234567", "contact_phones": ["+9647701234567"]}


def test_the_app_payload_with_a_typed_national_zero_is_repaired_not_stored_malformed(app_ctx, client, sms):
    """The Flutter sell page sends '+964' + the typed digits: a user typing 0770...
    produced +96407701234567 before."""
    me = _make_user(app_ctx)
    s = _send(app_ctx, me["headers"], me["username"], "+9640" + "7701234567")
    assert s.status_code == 200, s.data
    assert sms[-1][0] == "7701234567"
    assert _verify(client, me["headers"], "+96407701234567", sms[-1][1]).status_code == 200
    r = _publish(client, me["headers"], contact_phones=["+96407701234567"])
    assert r.status_code == 201, r.data
    assert _stored_listing(app_ctx, r.get_json()["car"]["id"])["contact_phones"] == ["+9647701234567"]


def test_up_to_three_distinct_phones_deduped_across_spellings(app_ctx, client):
    a, b, c3, d = _canonical(), _canonical(), _canonical(), _canonical()
    me = _make_user(app_ctx, contact_verified=[a, "0" + b, "+964" + c3, d])
    r = _publish(client, me["headers"], contact_phones=["0" + a, a, "+964" + b, c3, "00964" + c3, d])
    assert r.status_code == 201, r.data
    stored = _stored_listing(app_ctx, r.get_json()["car"]["id"])
    assert stored["contact_phones"] == ["+964" + a, "+964" + b, "+964" + c3]
    assert stored["contact_phone"] == "+964" + a


def test_publish_without_contact_phone_is_unchanged(app_ctx, client):
    me = _make_user(app_ctx)
    for extra in ({}, {"contact_phones": []}, {"contact_phone": ""}, {"contact_phone": None}, {"contact_phones": ["", "  "]}):
        r = _publish(client, me["headers"], **extra)
        assert r.status_code == 201, (extra, r.data)
        stored = _stored_listing(app_ctx, r.get_json()["car"]["id"])
        assert stored == {"contact_phone": None, "contact_phones": None}


# --------------------------------------------------------------------------
# 3. ambiguous / invalid input: 400 and NO SMS
# --------------------------------------------------------------------------
_BAD = [
    "2025550123",  # 10 digits, not a 7-mobile (used to get +964 glued on)
    "1234567890",
    "0112345678",  # landline
    "06612345678",
    "+9641 2345678",
    "+12025550123",  # foreign
    "+447911123456",
    "447911123456",
    "77012345",  # short
    "770123456",
    "770123456789",  # long
    "0770123456",
    "+96407",
    "+964770123456789",
    "abc",
    "!!!",
    "07701abc234",
    "٧٧٠",
    "07701234567 07701234568",
]


@pytest.mark.parametrize("bad", _BAD + [""])
def test_send_verification_rejects_invalid_numbers_without_sending_sms(app_ctx, client, sms, bad):
    me = _make_user(app_ctx)
    r = _send(app_ctx, me["headers"], me["username"], bad)
    assert r.status_code == 400, (bad, r.data)
    assert r.get_json()["message"] == _INVALID
    assert sms == []  # the SMS sender was never called
    row = _user_row(app_ctx, me["username"])
    assert row["hash"] is None and row["expires"] is None


def test_send_verification_without_any_phone_field_is_rejected(app_ctx, client, sms):
    me = _make_user(app_ctx)
    _expire_cooldown(app_ctx, me["username"])
    for body in ({}, {"phone_number": None}, {"phone": ""}):
        r = client.post("/api/user/contact-phone/send-verification", json=body, headers=me["headers"])
        assert r.status_code == 400 and r.get_json()["message"] == _INVALID, body
    assert sms == []


@pytest.mark.parametrize("bad", _BAD)
def test_verify_rejects_invalid_numbers(app_ctx, client, sms, bad):
    me = _make_user(app_ctx)
    r = _verify(client, me["headers"], bad, "123456")
    assert r.status_code == 400 and r.get_json()["message"] == _INVALID, (bad, r.data)
    assert _user_row(app_ctx, me["username"])["contact_verified"] == []
    assert sms == []


def test_verify_still_requires_a_six_digit_code(app_ctx, client):
    me = _make_user(app_ctx)
    for code in ("", "12345", "1234567", "abcdef"):
        r = _verify(client, me["headers"], "07701234567", code)
        assert r.status_code == 400
        assert r.get_json()["message"] == "Phone number and a six-digit code are required"


@pytest.mark.parametrize("bad", _BAD)
def test_publish_with_an_invalid_contact_phone_is_a_400_and_creates_nothing(app_ctx, client, bad):
    own = _canonical()
    me = _make_user(app_ctx, stored_phone=own)
    before = _car_count(app_ctx, me["id"])
    for body in (
        {"contact_phones": [bad]},
        {"contact_phone": bad},
        {"contact_phones": ["0" + own, bad]},  # one good (own), one bad
        {"contact_phones": [bad, "0" + own]},
    ):
        r = _publish(client, me["headers"], **body)
        assert r.status_code == 400, (body, r.data)
        assert r.get_json()["message"] == _INVALID
    assert _car_count(app_ctx, me["id"]) == before
    # an invalid phone must never silently pass as "no phone"
    ok = _publish(client, me["headers"])
    assert ok.status_code == 201


@pytest.mark.parametrize("bad", ["2025550123", "0112345678", "+12025550123", "abc", "770123456"])
def test_edit_with_an_invalid_contact_phone_is_a_400_and_keeps_the_stored_phone(app_ctx, client, bad):
    own = _canonical()
    me = _make_user(app_ctx, stored_phone=own)
    pub = _make_car(app_ctx, me["id"], contact_phone="+964" + own, contact_phones=["+964" + own])
    for body in ({"contact_phones": [bad]}, {"contact_phone": bad}, {"contact_phones": ["0" + own, bad]}):
        r = client.put(f"/api/cars/{pub}", json=body, headers=me["headers"])
        assert r.status_code == 400, (body, r.data)
        assert r.get_json()["message"] == _INVALID
    assert _stored_listing(app_ctx, pub) == {"contact_phone": "+964" + own, "contact_phones": ["+964" + own]}


def test_edit_can_still_clear_the_contact_phones_explicitly(app_ctx, client):
    own = _canonical()
    me = _make_user(app_ctx, stored_phone=own)
    pub = _make_car(app_ctx, me["id"], contact_phone="+964" + own, contact_phones=["+964" + own])
    r = client.put(f"/api/cars/{pub}", json={"contact_phones": []}, headers=me["headers"])
    assert r.status_code == 200, r.data
    assert _stored_listing(app_ctx, pub) == {"contact_phone": None, "contact_phones": None}


def test_edit_stores_the_canonical_e164_for_any_spelling(app_ctx, client):
    own = _canonical()
    me = _make_user(app_ctx, stored_phone=own)
    pub = _make_car(app_ctx, me["id"])
    for typed in _spellings(own):
        r = client.put(f"/api/cars/{pub}", json={"contact_phones": [typed]}, headers=me["headers"])
        assert r.status_code == 200, (typed, r.data)
        assert _stored_listing(app_ctx, pub) == {"contact_phone": "+964" + own, "contact_phones": ["+964" + own]}


def test_unverified_other_number_is_still_refused_on_edit(app_ctx, client):
    me = _make_user(app_ctx)
    pub = _make_car(app_ctx, me["id"])
    r = client.put(f"/api/cars/{pub}", json={"contact_phones": ["07701234599"]}, headers=me["headers"])
    assert r.status_code == 400 and r.get_json()["message"] == _VERIFY_FIRST
    assert _stored_listing(app_ctx, pub) == {"contact_phone": None, "contact_phones": None}


# --------------------------------------------------------------------------
# 4. legacy compatibility (no data migration, no rewriting)
# --------------------------------------------------------------------------
_LEGACY_VERIFIED_TPL = ["0{c}", "{c}", "+964{c}", "+9640{c}", "964{c}", "00964{c}"]


@pytest.mark.parametrize("tpl", _LEGACY_VERIFIED_TPL)
def test_legacy_verified_spellings_still_count_as_verified_in_any_spelling(app_ctx, client, sms, tpl):
    c = _canonical()
    me = _make_user(app_ctx, contact_verified=[tpl.format(c=c)])
    for typed in _spellings(c):
        r = _publish(client, me["headers"], contact_phones=[typed])
        assert r.status_code == 201, (tpl, typed, r.data)
        _assert_well_formed(_stored_listing(app_ctx, r.get_json()["car"]["id"])["contact_phones"])
        s = _send(app_ctx, me["headers"], me["username"], typed)
        assert s.status_code == 200 and s.get_json()["verified"] is True
    assert sms == []
    # the stored legacy entry is left exactly as it was (no rewrite)
    assert _user_row(app_ctx, me["username"])["contact_verified"] == [tpl.format(c=c)]


@pytest.mark.parametrize("own_tpl", ["{c}", "0{c}", "+964{c}", "+9640{c}", "964{c}", "00964{c}", "0964{c}"])
def test_legacy_stored_account_phone_spellings_are_acceptable_for_contact(app_ctx, client, sms, own_tpl):
    c = _canonical()
    me = _make_user(app_ctx, stored_phone=own_tpl.format(c=c))
    for typed in _spellings(c):
        r = _publish(client, me["headers"], contact_phones=[typed])
        assert r.status_code == 201, (own_tpl, typed, r.data)
    assert sms == []


def test_listing_with_malformed_legacy_phone_loads_displays_fixed_and_is_editable(app_ctx, client, sms):
    c = _canonical()
    me = _make_user(app_ctx, contact_verified=["0" + c])
    bad = f"+9640{c}"  # 15 chars: what the old code stored for a typed 07...
    pub = _make_car(app_ctx, me["id"], contact_phone=bad, contact_phones=[bad])

    # loads: reveal endpoint shows the repaired number, flags stay correct
    r = client.get(f"/api/cars/{pub}/contact", headers=me["headers"])
    assert r.status_code == 200, r.data
    body = r.get_json()
    assert body["contact_phones"] == ["+964" + c] and body["contact_phone"] == "+964" + c
    assert body["has_contact_phone"] is True

    app, _client, db, _User, Car = app_ctx
    with app.app_context():
        car = Car.query.filter_by(public_id=pub).first()
        public = car.to_dict()
        private = car.to_dict(include_private=True)
    assert public["has_contact_phone"] is True
    assert public["contact_phone_masked"].endswith(c[-4:])
    assert public["contact_phone"] is None and public["contact_phones"] == []
    assert private["contact_phones"] == ["+964" + c] and private["contact_phone"] == "+964" + c

    # nothing was rewritten behind the owner's back
    assert _stored_listing(app_ctx, pub) == {"contact_phone": bad, "contact_phones": [bad]}
    # an unrelated edit does not touch the phones
    r = client.put(f"/api/cars/{pub}", json={"description": "clean car"}, headers=me["headers"])
    assert r.status_code == 200, r.data
    assert _stored_listing(app_ctx, pub) == {"contact_phone": bad, "contact_phones": [bad]}

    # re-saving the same phone (as the app does) maps it to the correct +9647...
    for resubmit in ([bad], [f"+964{c}"], ["0" + c]):
        _set_listing_phones(app_ctx, pub, bad)  # back to the legacy malformed row
        r = client.put(f"/api/cars/{pub}", json={"contact_phones": resubmit}, headers=me["headers"])
        assert r.status_code == 200, (resubmit, r.data)
        assert _stored_listing(app_ctx, pub) == {"contact_phone": "+964" + c, "contact_phones": ["+964" + c]}
    assert sms == []


def test_legacy_malformed_phone_resave_still_needs_verification_for_another_user(app_ctx, client):
    c = _canonical()
    owner = _make_user(app_ctx)
    bad = f"+9640{c}"
    pub = _make_car(app_ctx, owner["id"], contact_phone=bad, contact_phones=[bad])
    # the owner never verified this number: the repaired value is refused like any other
    r = client.put(f"/api/cars/{pub}", json={"contact_phones": [bad]}, headers=owner["headers"])
    assert r.status_code == 400 and r.get_json()["message"] == _VERIFY_FIRST
    assert _stored_listing(app_ctx, pub) == {"contact_phone": bad, "contact_phones": [bad]}


def test_legacy_unnormalisable_stored_phone_still_loads_untouched(app_ctx, client):
    me = _make_user(app_ctx)
    pub = _make_car(app_ctx, me["id"], contact_phone="12345", contact_phones=["12345", "+12025550123"])
    r = client.get(f"/api/cars/{pub}/contact", headers=me["headers"])
    assert r.status_code == 200
    assert r.get_json()["contact_phones"] == ["12345", "+12025550123"]
    assert r.get_json()["has_contact_phone"] is True


# --------------------------------------------------------------------------
# 5. in-flight codes issued before this deploy (hash over the typed digits)
# --------------------------------------------------------------------------
def _plant_pending_code(app_ctx, username: str, hash_digits: str, code: str, minutes: int = 10) -> None:
    from kk.routes.user import _hash_contact_phone_code
    from kk.time_utils import utcnow

    app, _client, db, User, _Car = app_ctx
    with app.app_context():
        u = User.query.filter_by(username=username).first()
        u.phone_verification_code_hash = _hash_contact_phone_code(hash_digits, code)  # old formula == typed digits
        u.phone_verification_expires_at = utcnow() + timedelta(minutes=minutes)
        u.phone_verification_attempts = 0
        u.phone_verification_locked_until = None
        db.session.commit()


@pytest.mark.parametrize("legacy_digits_tpl", ["0{c}", "{c}"])
@pytest.mark.parametrize("verify_idx", [0, 1, 2, 3, 5, 9])
def test_in_flight_legacy_hash_code_verifies_once(app_ctx, client, legacy_digits_tpl, verify_idx):
    c = _canonical()
    me = _make_user(app_ctx)
    _plant_pending_code(app_ctx, me["username"], legacy_digits_tpl.format(c=c), "246810")
    typed = _spellings(c)[verify_idx]

    v = _verify(client, me["headers"], typed, "246810")
    assert v.status_code == 200, (typed, v.data)
    row = _user_row(app_ctx, me["username"])
    assert row["contact_verified"] == [c]
    assert row["hash"] is None and row["expires"] is None  # consumed: single use

    # a second user holding no pending code cannot replay it
    other = _make_user(app_ctx)
    v2 = _verify(client, other["headers"], typed, "246810")
    assert v2.status_code == 400
    assert _user_row(app_ctx, other["username"])["contact_verified"] == []


def test_in_flight_legacy_code_for_one_number_never_verifies_another(app_ctx, client):
    c, other = _canonical(), _canonical()
    me = _make_user(app_ctx)
    _plant_pending_code(app_ctx, me["username"], "0" + c, "246810")
    r = _verify(client, me["headers"], other, "246810")
    assert r.status_code == 400
    assert _user_row(app_ctx, me["username"])["contact_verified"] == []
    assert _user_row(app_ctx, me["username"])["attempts"] == 1


# --------------------------------------------------------------------------
# 6. wrong code / lockout / expiry are unchanged
# --------------------------------------------------------------------------
def test_wrong_codes_count_attempts_in_every_spelling_then_lock_out(app_ctx, client, sms):
    me = _make_user(app_ctx)
    c = _canonical()
    forms = _spellings(c)
    assert _send(app_ctx, me["headers"], me["username"], forms[0]).status_code == 200
    code = sms[-1][1]
    wrong = f"{(int(code) + 1) % 1_000_000:06d}"

    for n in range(1, 5):
        r = _verify(client, me["headers"], forms[n], wrong)
        assert r.status_code == 400 and r.get_json()["message"] == "Invalid or expired verification code"
        assert _user_row(app_ctx, me["username"])["attempts"] == n
    r = _verify(client, me["headers"], forms[5], wrong)  # 5th failure -> lockout
    assert r.status_code == 400
    row = _user_row(app_ctx, me["username"])
    assert row["locked"] is not None and row["hash"] is None and row["attempts"] == 0

    # the correct code no longer works while locked, resend is refused too
    assert _verify(client, me["headers"], forms[0], code).status_code == 429
    assert _send(app_ctx, me["headers"], me["username"], forms[0]).status_code == 429
    assert _user_row(app_ctx, me["username"])["contact_verified"] == []


def test_expired_code_is_rejected(app_ctx, client, sms):
    from kk.time_utils import utcnow

    app, _client, db, User, _Car = app_ctx
    me = _make_user(app_ctx)
    c = _canonical()
    assert _send(app_ctx, me["headers"], me["username"], "0" + c).status_code == 200
    code = sms[-1][1]
    with app.app_context():
        u = User.query.filter_by(username=me["username"]).first()
        u.phone_verification_expires_at = utcnow() - timedelta(seconds=1)
        db.session.commit()
    r = _verify(client, me["headers"], c, code)
    assert r.status_code == 400 and r.get_json()["message"] == "Invalid or expired verification code"
    row = _user_row(app_ctx, me["username"])
    assert row["contact_verified"] == [] and row["hash"] is None


def test_resend_cooldown_is_unchanged(app_ctx, client, sms):
    me = _make_user(app_ctx)
    c = _canonical()
    assert _send(app_ctx, me["headers"], me["username"], c).status_code == 200
    r = client.post(
        "/api/user/contact-phone/send-verification", json={"phone_number": "0" + c}, headers=me["headers"]
    )
    assert r.status_code == 429  # within 60 s, whatever the spelling
    assert len(sms) == 1


def test_sms_provider_failure_discards_the_code(app_ctx, client, monkeypatch):
    monkeypatch.setattr("kk.sms_service.send_verification_sms_result", lambda p, c: (False, "boom"))
    me = _make_user(app_ctx)
    r = _send(app_ctx, me["headers"], me["username"], "07701234567")
    assert r.status_code == 502 and r.get_json()["code"] == "sms_send_failed"
    assert _user_row(app_ctx, me["username"])["hash"] is None


# --------------------------------------------------------------------------
# 7. verification is per user
# --------------------------------------------------------------------------
def test_another_user_cannot_use_my_verified_phones(app_ctx, client, sms):
    c = _canonical()
    a = _make_user(app_ctx)
    b = _make_user(app_ctx)
    assert _send(app_ctx, a["headers"], a["username"], "0" + c).status_code == 200
    code = sms[-1][1]
    assert _verify(client, a["headers"], c, code).status_code == 200
    assert _publish(client, a["headers"], contact_phones=["+964" + c]).status_code == 201

    for typed in _spellings(c):
        r = _publish(client, b["headers"], contact_phones=[typed])
        assert r.status_code == 400 and r.get_json()["message"] == _VERIFY_FIRST, typed
    assert _car_count(app_ctx, b["id"]) == 0

    # B gets no "already verified" shortcut: an SMS is sent
    n = len(sms)
    s = _send(app_ctx, b["headers"], b["username"], c)
    assert s.status_code == 200 and s.get_json().get("verified") is None
    assert len(sms) == n + 1

    # A's code (a different user's pending hash) cannot verify the number for B
    sms.clear()
    b2 = _make_user(app_ctx)
    r = _verify(client, b2["headers"], c, code)
    assert r.status_code == 400
    assert _user_row(app_ctx, b2["username"])["contact_verified"] == []


def test_a_user_cannot_use_another_users_account_phone_as_contact(app_ctx, client):
    a = _make_user(app_ctx)
    b = _make_user(app_ctx)
    r = _publish(client, b["headers"], contact_phones=["0" + a["phone"]])
    assert r.status_code == 400 and r.get_json()["message"] == _VERIFY_FIRST


def test_legacy_verified_entries_of_one_user_do_not_leak_to_another(app_ctx, client):
    c = _canonical()
    _make_user(app_ctx, contact_verified=["0" + c])
    b = _make_user(app_ctx)
    r = _publish(client, b["headers"], contact_phones=[c])
    assert r.status_code == 400 and r.get_json()["message"] == _VERIFY_FIRST


def test_existing_legacy_entries_are_kept_when_a_new_number_is_verified(app_ctx, client, sms):
    old, new = _canonical(), _canonical()
    me = _make_user(app_ctx, contact_verified=["0" + old])
    assert _send(app_ctx, me["headers"], me["username"], "+964" + new).status_code == 200
    assert _verify(client, me["headers"], "0" + new, sms[-1][1]).status_code == 200
    assert _user_row(app_ctx, me["username"])["contact_verified"] == ["0" + old, new]
    # the profile payload (client reads it) still lists both
    for p in (old, new):
        r = _publish(client, me["headers"], contact_phones=[p])
        assert r.status_code == 201


# --------------------------------------------------------------------------
# 8. authentication
# --------------------------------------------------------------------------
def test_contact_phone_endpoints_require_authentication(client):
    assert client.post("/api/user/contact-phone/send-verification", json={"phone_number": "07701234567"}).status_code == 401
    assert client.post(
        "/api/user/contact-phone/verify", json={"phone_number": "07701234567", "verification_code": "123456"}
    ).status_code == 401
    assert client.post("/api/cars", json=_payload(contact_phones=["07701234567"])).status_code == 401
