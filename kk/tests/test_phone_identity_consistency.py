"""Phone identity consistency for the profile / phone-change flows.

``kk/routes/auth.py`` stores ONE canonical form of an Iraqi mobile (10 digits,
``7XXXXXXXXX``). Before this change ``kk/routes/user.py`` still used its own
normaliser and an exact-string uniqueness check, so

* a number typed as ``07...`` / ``+964...`` / Arabic digits was stored in that
  spelling (a second identity for the same SIM), and
* a number already owned by another account in a different spelling (e.g. a
  legacy ``07...`` row) was NOT detected as a duplicate.

Covered here: ownership, collision in every spelling (canonical + legacy rows),
canonical storage, cross-spelling OTP, idempotent re-save, negative inputs and
the commit-time race.
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

_PASSWORD = "Aa123456!"
_EXISTS = "Phone number already exists"
_ARABIC = str.maketrans("0123456789", "٠١٢٣٤٥٦٧٨٩")
_PERSIAN = str.maketrans("0123456789", "۰۱۲۳۴۵۶۷۸۹")


def _canonical() -> str:
    """A fresh canonical Iraqi mobile (10 digits, starts with 7)."""
    return f"7{uuid.uuid4().int % 10**9:09d}"


def _spellings(c: str) -> list[str]:
    """Every way the same subscriber can be typed."""
    return [
        c,
        "0" + c,
        "+964" + c,
        "964" + c,
        "00964" + c,
        "+9640" + c,
        f"+964 {c[:3]} {c[3:6]} {c[6:]}",
        f"0{c[:3]}-{c[3:6]}-{c[6:]}",
        ("0" + c).translate(_ARABIC),
        ("+964" + c).translate(_PERSIAN),
    ]


# Stored spellings an old row can have.
_LEGACY_STORED = ["0{c}", "+964{c}", "964{c}", "00964{c}", "+9640{c}", "9640{c}"]


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_phone_identity_", ignore_cleanup_errors=True)
    for key in ("DATABASE_URL", "AUTO_MIGRATE"):
        os.environ.pop(key, None)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ["ALLOW_DEV_CODE_IN_RESPONSE"] = "1"
    os.environ["DB_PATH"] = os.path.join(tmp.name, "phone_identity.db")

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


def _make_user(app_ctx, stored_phone: str | None = None):
    """Returns (id, public_id, username, stored_phone)."""
    app, _client, db, User = app_ctx
    stored_phone = stored_phone or _canonical()
    username = f"phoneid_{uuid.uuid4().hex[:10]}"
    with app.app_context():
        user = User(
            username=username,
            phone_number=stored_phone,
            first_name="Phone",
            last_name="Identity",
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id=f"pub-{uuid.uuid4().hex[:12]}",
        )
        user.set_password(_PASSWORD)
        db.session.add(user)
        db.session.commit()
        return user.id, user.public_id, username, stored_phone


def _login(client, username: str) -> dict:
    r = client.post("/api/auth/login", json={"username": username, "password": _PASSWORD})
    assert r.status_code == 200, r.data
    return {"Authorization": f"Bearer {r.get_json()['access_token']}"}


def _row(app_ctx, user_id: int):
    app, _client, db, User = app_ctx
    with app.app_context():
        u = db.session.get(User, user_id)
        return {
            "phone": u.phone_number,
            "hash": u.phone_verification_code_hash,
            "verified": u.phone_verified,
        }


def _phone_rows(app_ctx, variants: list[str]) -> int:
    app, _client, db, User = app_ctx
    with app.app_context():
        return User.query.filter(User.phone_number.in_(variants)).count()


def _send(client, headers, phone):
    return client.post("/api/user/phone-change/send-code", json={"phone_number": phone}, headers=headers)


def _put(client, headers, **body):
    return client.put("/api/user/profile", json=body, headers=headers)


# --------------------------------------------------------------------------
# Collision: another account owns the number in ANY spelling
# --------------------------------------------------------------------------
@pytest.mark.parametrize("stored_tpl", ["{c}"] + _LEGACY_STORED)
def test_send_code_rejects_every_spelling_of_a_number_owned_by_another_account(
    app_ctx, client, stored_tpl
):
    c = _canonical()
    b_id, _pub, _u, b_phone = _make_user(app_ctx, stored_tpl.format(c=c))
    a_id, _pub_a, a_user, a_phone = _make_user(app_ctx)
    headers = _login(client, a_user)

    for typed in _spellings(c):
        r = _send(client, headers, typed)
        assert r.status_code == 400, (typed, r.data)
        assert r.get_json()["message"] == _EXISTS, typed

    a = _row(app_ctx, a_id)
    assert a["phone"] == a_phone
    assert a["hash"] is None  # no OTP was minted / SMS burnt for a taken number
    assert _row(app_ctx, b_id)["phone"] == b_phone


@pytest.mark.parametrize("stored_tpl", ["{c}"] + _LEGACY_STORED)
def test_profile_update_rejects_every_spelling_before_otp(app_ctx, client, stored_tpl):
    c = _canonical()
    b_id, _pub, _u, b_phone = _make_user(app_ctx, stored_tpl.format(c=c))
    a_id, _pub_a, a_user, a_phone = _make_user(app_ctx)
    headers = _login(client, a_user)

    for typed in _spellings(c):
        r = _put(client, headers, phone_number=typed, verification_code="123456")
        assert r.status_code == 400, (typed, r.data)
        assert r.get_json()["message"] == _EXISTS, typed
        r2 = _put(client, headers, phone_number=typed)  # no code at all: same answer
        assert r2.status_code == 400 and r2.get_json()["message"] == _EXISTS, typed

    assert _row(app_ctx, a_id)["phone"] == a_phone
    assert _row(app_ctx, b_id)["phone"] == b_phone


def test_spelling_collision_answer_is_identical_to_exact_duplicate(app_ctx, client):
    """No new existence oracle: a different spelling gets the very same status
    and body as the exact duplicate (which already leaked before this change)."""
    c = _canonical()
    _make_user(app_ctx, "0" + c)
    _a, _p, a_user, _ph = _make_user(app_ctx)
    headers = _login(client, a_user)
    exact = _send(client, headers, "0" + c)
    other = _send(client, headers, "+964" + c)
    assert (exact.status_code, exact.get_json()) == (other.status_code, other.get_json())
    exact_put = _put(client, headers, phone_number="0" + c)
    other_put = _put(client, headers, phone_number="+964" + c)
    assert (exact_put.status_code, exact_put.get_json()) == (other_put.status_code, other_put.get_json())


def test_apply_time_recheck_catches_a_different_spelling_claimed_meanwhile(app_ctx, client):
    c = _canonical()
    a_id, _pub, a_user, a_phone = _make_user(app_ctx)
    headers = _login(client, a_user)
    r = _send(client, headers, c)
    assert r.status_code == 200, r.data
    code = r.get_json()["dev_code"]

    _make_user(app_ctx, "0" + c)  # someone claims it as a legacy 07... row

    r2 = _put(client, headers, phone_number="+964" + c, verification_code=code)
    assert r2.status_code == 400, r2.data
    assert r2.get_json()["message"] == _EXISTS
    assert _row(app_ctx, a_id)["phone"] == a_phone


def test_commit_time_unique_violation_is_a_duplicate_answer_not_a_500(app_ctx, client, monkeypatch):
    """Both users pass the pre-check, the second commit hits the UNIQUE column."""
    from kk.routes import user as user_routes

    c = _canonical()
    a_id, _pub, a_user, a_phone = _make_user(app_ctx)
    headers = _login(client, a_user)
    r = _send(client, headers, c)
    code = r.get_json()["dev_code"]
    _make_user(app_ctx, c)  # B owns the canonical number now

    real = user_routes._account_phone_owner

    def blind_precheck(canonical, exclude_user_id=None):
        return None if exclude_user_id is not None else real(canonical, exclude_user_id)

    monkeypatch.setattr(user_routes, "_account_phone_owner", blind_precheck)
    r2 = _put(client, headers, phone_number=c, verification_code=code)
    assert r2.status_code == 400, r2.data
    assert r2.get_json()["message"] == _EXISTS
    assert _row(app_ctx, a_id)["phone"] == a_phone


# --------------------------------------------------------------------------
# Canonical storage + OTP across spellings
# --------------------------------------------------------------------------
@pytest.mark.parametrize("typed_idx", range(10))
def test_phone_change_stores_the_canonical_form_whatever_was_typed(app_ctx, client, typed_idx):
    c = _canonical()
    a_id, _pub, a_user, _old = _make_user(app_ctx)
    headers = _login(client, a_user)
    typed = _spellings(c)[typed_idx]

    r = _send(client, headers, typed)
    assert r.status_code == 200, (typed, r.data)
    code = r.get_json()["dev_code"]
    r2 = _put(client, headers, phone_number=typed, verification_code=code)
    assert r2.status_code == 200, (typed, r2.data)
    assert r2.get_json()["user"]["phone_number"] == c
    assert _row(app_ctx, a_id)["phone"] == c
    assert _row(app_ctx, a_id)["verified"] is True


def test_otp_sent_for_one_spelling_applies_for_another(app_ctx, client):
    c = _canonical()
    a_id, _pub, a_user, _old = _make_user(app_ctx)
    headers = _login(client, a_user)
    code = _send(client, headers, "0" + c).get_json()["dev_code"]
    r = _put(client, headers, phone_number="+964" + c, verification_code=code)
    assert r.status_code == 200, r.data
    assert _row(app_ctx, a_id)["phone"] == c


def test_wrong_code_does_not_change_phone_in_any_spelling(app_ctx, client):
    c = _canonical()
    a_id, _pub, a_user, a_phone = _make_user(app_ctx)
    headers = _login(client, a_user)
    code = _send(client, headers, c).get_json()["dev_code"]
    wrong = f"{(int(code) + 1) % 1_000_000:06d}"
    r = _put(client, headers, phone_number="0" + c, verification_code=wrong)
    assert r.status_code == 400
    assert _row(app_ctx, a_id)["phone"] == a_phone


def test_changing_phone_requires_otp_in_any_spelling(app_ctx, client):
    c = _canonical()
    a_id, _pub, a_user, a_phone = _make_user(app_ctx)
    headers = _login(client, a_user)
    for typed in (c, "0" + c, "+964" + c):
        r = _put(client, headers, phone_number=typed)
        assert r.status_code == 400, typed
        assert r.get_json().get("code") == "phone_change_verification_required"
    assert _row(app_ctx, a_id)["phone"] == a_phone


# --------------------------------------------------------------------------
# Idempotent re-save of one's own number
# --------------------------------------------------------------------------
@pytest.mark.parametrize("own_tpl", ["{c}"] + _LEGACY_STORED)
def test_resaving_own_number_in_any_spelling_is_a_noop(app_ctx, client, own_tpl):
    c = _canonical()
    a_id, _pub, a_user, stored = _make_user(app_ctx, own_tpl.format(c=c))
    headers = _login(client, a_user)
    for typed in _spellings(c):
        r = _put(client, headers, phone_number=typed, first_name="Same")
        assert r.status_code == 200, (typed, r.data)  # no OTP, no duplicate error
        assert _row(app_ctx, a_id)["phone"] == stored  # untouched (no silent rewrite)
        r2 = _send(client, headers, typed)
        assert r2.status_code == 400
        assert "already your phone number" in r2.get_json()["message"].lower()
    assert _phone_rows(app_ctx, [own_tpl.format(c=c), c]) == 1


# --------------------------------------------------------------------------
# Ownership
# --------------------------------------------------------------------------
def test_user_cannot_change_another_users_phone(app_ctx, client):
    c = _canonical()
    b_id, b_pub, _bu, b_phone = _make_user(app_ctx)
    a_id, _pub_a, a_user, a_phone = _make_user(app_ctx)
    headers = _login(client, a_user)
    code = _send(client, headers, c).get_json()["dev_code"]

    # Attacker-controlled identifiers in the body must not redirect the write.
    r = _put(
        client,
        headers,
        phone_number=c,
        verification_code=code,
        id=b_id,
        user_id=b_id,
        public_id=b_pub,
    )
    assert r.status_code == 200, r.data
    assert _row(app_ctx, a_id)["phone"] == c
    assert _row(app_ctx, b_id)["phone"] == b_phone


def test_other_users_pending_code_cannot_be_used_to_take_a_number(app_ctx, client):
    c = _canonical()
    _a, _pa, a_user, _ap = _make_user(app_ctx)
    b_id, _pb, b_user, b_phone = _make_user(app_ctx)
    a_headers, b_headers = _login(client, a_user), _login(client, b_user)
    code_a = _send(client, a_headers, c).get_json()["dev_code"]
    for typed in (c, "0" + c, "+964" + c):
        r = _put(client, b_headers, phone_number=typed, verification_code=code_a)
        assert r.status_code == 400, typed
    assert _row(app_ctx, b_id)["phone"] == b_phone


def test_phone_change_endpoints_require_authentication(app_ctx, client):
    c = _canonical()
    assert client.post("/api/user/phone-change/send-code", json={"phone_number": c}).status_code == 401
    assert client.put("/api/user/profile", json={"phone_number": c}).status_code == 401


# --------------------------------------------------------------------------
# Negative inputs
# --------------------------------------------------------------------------
@pytest.mark.parametrize("bad", ["abc", "!!!", "12345", "+96470", "0770", "٧٧٠"])
def test_garbage_and_too_short_numbers_are_rejected_or_ignored(app_ctx, client, bad):
    a_id, _pub, a_user, a_phone = _make_user(app_ctx)
    headers = _login(client, a_user)

    r = _send(client, headers, bad)
    assert r.status_code == 400, (bad, r.data)
    assert r.get_json()["message"] == "Enter a valid phone number"
    assert _row(app_ctx, a_id)["hash"] is None

    r2 = _put(client, headers, phone_number=bad, verification_code="123456")
    assert r2.status_code in (200, 400), (bad, r2.data)  # digit-less input is "no phone given"
    assert r2.status_code != 500
    assert _row(app_ctx, a_id)["phone"] == a_phone
