"""MI-03/U-01 focused tests: User.locale + Accept-Language, the localized
auth/background strings, and the force-update gate's localized message.

Bug (PRODUCTION_AUDIT.md MI-03/U-01): ``User`` had no ``language``/``locale``
column, there was no ``Accept-Language`` handling anywhere in the backend,
and every backend-generated user-facing string (login errors, push/alert/
email/SMS templates, the force-update message) was English-only.

Scope of this file (deliberately narrow -- see PRODUCTION_AUDIT.md MI-03/
U-01 and the investigation notes):
  * kk/localization.py's small set of helpers (normalize/parse/precedence/
    translate) -- unit tests, no Flask app needed.
  * User.locale persistence via the existing PUT/GET /api/user/profile
    (own-account only; never part of the public/listing-embedded shape).
  * The one cited auth.py path ("Invalid credentials").
  * GET /api/config/app's localized force_update_message/soft_update_message
    (anonymous-safe; admin-override precedence).
  * The specific MI-03-cited background templates: alert_tasks' saved-search/
    price-drop push titles, email_service's dealer verification code, and
    sms_service's password-reset SMS (console/Twilio-shaped path only --
    OTPIQ is intentionally untouched, see kk/sms_service.py).

NOT covered here (out of scope for MI-03/U-01, see kk/localization.py and
the investigation notes): every English string in the repo, OTPIQ SMS text,
phone-verification OTP SMS/email, or a full localization framework.
"""

from __future__ import annotations

import os
import sys
import tempfile
import uuid
from pathlib import Path
from unittest import mock

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

os.environ.setdefault("APP_ENV", "testing")
os.environ.setdefault("SECRET_KEY", "test-secret-key-for-mi03")
os.environ.setdefault("JWT_SECRET_KEY", "test-jwt-secret-key-for-mi03")

_PASSWORD = "Aa123456!"


# ---------------------------------------------------------------------------
# Section 1 -- kk/localization.py unit tests (no Flask app needed).
# ---------------------------------------------------------------------------


def test_normalize_locale_accepts_bare_supported_codes():
    from kk.localization import normalize_locale

    assert normalize_locale("en") == "en"
    assert normalize_locale("ar") == "ar"
    assert normalize_locale("ku") == "ku"


def test_normalize_locale_reduces_regional_forms():
    from kk.localization import normalize_locale

    assert normalize_locale("en-US") == "en"
    assert normalize_locale("AR-iq") == "ar"
    assert normalize_locale("ku-IQ") == "ku"
    assert normalize_locale("ar_IQ") == "ar"


def test_normalize_locale_rejects_unsupported_and_empty():
    from kk.localization import normalize_locale

    assert normalize_locale("ckb") is None  # tracked separately (U-07)
    assert normalize_locale("fr") is None
    assert normalize_locale("") is None
    assert normalize_locale(None) is None


def test_parse_accept_language_orders_by_qvalue():
    from kk.localization import parse_accept_language

    assert parse_accept_language("ar;q=0.5, en;q=0.9, ku;q=0.1") == ["en", "ar", "ku"]


def test_parse_accept_language_ties_keep_header_order():
    from kk.localization import parse_accept_language

    assert parse_accept_language("ku, ar, en") == ["ku", "ar", "en"]


def test_parse_accept_language_skips_unsupported_tags():
    from kk.localization import parse_accept_language

    assert parse_accept_language("fr-FR, ar;q=0.8, ckb") == ["ar"]


def test_parse_accept_language_handles_regional_and_missing_header():
    from kk.localization import parse_accept_language

    assert parse_accept_language("ar-IQ,en;q=0.8") == ["ar", "en"]
    assert parse_accept_language(None) == []
    assert parse_accept_language("") == []


def test_get_request_locale_header_wins_over_stored_user_locale():
    from kk.localization import get_request_locale

    # Accept-Language reflects the CURRENT device/session and must win over
    # a stored account preference from a different device (MI-03 design).
    assert get_request_locale("ar", user_locale="ku") == "ar"


def test_get_request_locale_falls_back_to_user_locale_when_header_absent():
    from kk.localization import get_request_locale

    assert get_request_locale(None, user_locale="ar") == "ar"
    assert get_request_locale("", user_locale="ku") == "ku"


def test_get_request_locale_falls_back_to_english_when_neither_present():
    from kk.localization import get_request_locale

    assert get_request_locale(None, user_locale=None) == "en"
    assert get_request_locale("fr-FR", user_locale=None) == "en"


def test_get_background_locale_ignores_request_context_entirely():
    from kk.localization import get_background_locale

    assert get_background_locale("ar") == "ar"
    assert get_background_locale(None) == "en"
    assert get_background_locale("ckb") == "en"  # unsupported -> fallback


def test_translate_returns_locale_text_and_falls_back_to_english():
    from kk.localization import translate

    assert translate("invalid_credentials", "en") == "Invalid credentials"
    assert translate("invalid_credentials", "ar") != "Invalid credentials"
    assert translate("invalid_credentials", "ku") != "Invalid credentials"
    # Unsupported/None locale -> English.
    assert translate("invalid_credentials", None) == "Invalid credentials"
    assert translate("invalid_credentials", "fr") == "Invalid credentials"


def test_translate_formats_kwargs_and_handles_unknown_key():
    from kk.localization import translate

    text = translate("password_reset_sms_body", "en", code="123456")
    assert "123456" in text
    # Unknown key never raises -- returns the key itself.
    assert translate("no_such_key", "en") == "no_such_key"


# ---------------------------------------------------------------------------
# Section 2 -- app fixture (User.locale persistence, auth, force-update,
# background templates).
# ---------------------------------------------------------------------------


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_mi03_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ["DB_PATH"] = os.path.join(tmp.name, "mi03.db")

    from kk.app_factory import create_app

    app, *_ = create_app()
    from kk.models import Car, Notification, SavedSearch, User, db

    with app.app_context():
        db.drop_all()
        db.create_all()

    yield app, app.test_client(), db, User, Car, Notification, SavedSearch

    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    tmp.cleanup()


@pytest.fixture
def client(app_ctx):
    return app_ctx[1]


def _phone() -> str:
    return f"079{uuid.uuid4().int % 10**8:08d}"


def _make_user(app_ctx, *, locale: str | None = None) -> tuple[int, str, str]:
    """Returns (id, public_id, username)."""
    app, _client, db, User, *_ = app_ctx
    username = f"mi03_{uuid.uuid4().hex[:10]}"
    with app.app_context():
        user = User(
            username=username,
            phone_number=_phone(),
            first_name="Mi03",
            last_name="Test",
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id=f"mi03-{uuid.uuid4().hex[:12]}",
            locale=locale,
        )
        user.set_password(_PASSWORD)
        db.session.add(user)
        db.session.commit()
        return user.id, user.public_id, username


def _login(client, username: str, password: str = _PASSWORD, *, accept_language: str | None = None):
    headers = {"Accept-Language": accept_language} if accept_language else {}
    return client.post(
        "/api/auth/login",
        json={"username": username, "password": password},
        headers=headers,
    )


def _auth_header(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


# --- LOCALE MODEL/API -------------------------------------------------------


def test_new_user_locale_defaults_to_null(app_ctx):
    app, _client, db, User, *_ = app_ctx
    _uid, _pub, username = _make_user(app_ctx)
    with app.app_context():
        user = User.query.filter_by(username=username).first()
        assert user.locale is None


def test_profile_put_accepts_en_ar_ku(client, app_ctx):
    _uid, _pub, username = _make_user(app_ctx)
    r = _login(client, username)
    assert r.status_code == 200, r.data
    token = r.get_json()["access_token"]

    for code in ("en", "ar", "ku"):
        r = client.put(
            "/api/user/profile", json={"locale": code}, headers=_auth_header(token)
        )
        assert r.status_code == 200, r.data
        assert r.get_json()["user"]["locale"] == code


def test_profile_put_rejects_unsupported_locale(client, app_ctx):
    _uid, _pub, username = _make_user(app_ctx)
    r = _login(client, username)
    token = r.get_json()["access_token"]

    r = client.put(
        "/api/user/profile", json={"locale": "fr"}, headers=_auth_header(token)
    )
    assert r.status_code == 400, r.data
    body = r.get_json()
    assert "locale" in (body.get("errors") or {})


def test_profile_put_null_locale_clears_preference(client, app_ctx):
    _uid, _pub, username = _make_user(app_ctx, locale="ar")
    r = _login(client, username)
    token = r.get_json()["access_token"]

    r = client.put(
        "/api/user/profile", json={"locale": None}, headers=_auth_header(token)
    )
    assert r.status_code == 200, r.data
    assert r.get_json()["user"]["locale"] is None


def test_get_profile_includes_locale_for_own_account(client, app_ctx):
    _uid, _pub, username = _make_user(app_ctx, locale="ku")
    r = _login(client, username)
    token = r.get_json()["access_token"]

    r = client.get("/api/user/profile", headers=_auth_header(token))
    assert r.status_code == 200, r.data
    assert r.get_json()["user"]["locale"] == "ku"


def test_public_user_dict_never_includes_locale(app_ctx):
    app, _client, db, User, *_ = app_ctx
    _uid, _pub, username = _make_user(app_ctx, locale="ar")
    with app.app_context():
        user = User.query.filter_by(username=username).first()
        assert "locale" not in user.to_dict()
        assert user.to_dict(include_private=True)["locale"] == "ar"


# --- AUTH MESSAGE (kk/routes/auth.py -- MI-03 cited path) ------------------


def test_invalid_credentials_localized_by_accept_language(client, app_ctx):
    _uid, _pub, username = _make_user(app_ctx)

    r_en = _login(client, username, password="wrong", accept_language="en")
    assert r_en.status_code == 401
    assert r_en.get_json() == {"message": "Invalid credentials"}

    r_ar = _login(client, username, password="wrong", accept_language="ar")
    assert r_ar.status_code == 401
    ar_message = r_ar.get_json()["message"]
    assert ar_message != "Invalid credentials"

    r_ku = _login(client, username, password="wrong", accept_language="ku")
    assert r_ku.status_code == 401
    ku_message = r_ku.get_json()["message"]
    assert ku_message not in ("Invalid credentials", ar_message)


def test_invalid_credentials_defaults_to_english_without_header(client, app_ctx):
    """M-09 regression guard: the existing generic body must be unchanged
    for callers that never send Accept-Language (the overwhelming majority
    of existing tests/clients)."""
    _uid, _pub, username = _make_user(app_ctx)

    r = _login(client, username, password="wrong")
    assert r.status_code == 401
    assert r.get_json() == {"message": "Invalid credentials"}


def test_invalid_credentials_response_shape_unchanged(client, app_ctx):
    """Only the message text may vary by locale -- no new/renamed keys."""
    _uid, _pub, username = _make_user(app_ctx)

    r = _login(client, username, password="wrong", accept_language="ar")
    assert r.status_code == 401
    assert set(r.get_json().keys()) == {"message"}


# --- FORCE UPDATE (GET /api/config/app -- anonymous) -----------------------


def test_force_update_config_works_anonymously_and_english_by_default(client):
    r = client.get("/api/config/app")
    assert r.status_code == 200, r.data
    body = r.get_json()
    assert body["force_update_message"] == "Please update CarNet to continue."
    assert body["soft_update_message"] == "A newer version of CarNet is available."
    # Field names unchanged.
    for key in (
        "min_app_version",
        "min_android_build",
        "min_ios_build",
        "force_update_message",
        "recommended_app_version",
        "recommended_android_build",
        "recommended_ios_build",
        "soft_update_message",
        "android_store_url",
        "ios_store_url",
        "feature_flags",
    ):
        assert key in body


def test_force_update_config_arabic_and_kurdish_built_in_fallback(client):
    r_ar = client.get("/api/config/app", headers={"Accept-Language": "ar"})
    assert r_ar.status_code == 200
    ar_body = r_ar.get_json()
    assert ar_body["force_update_message"] != "Please update CarNet to continue."

    r_ku = client.get("/api/config/app", headers={"Accept-Language": "ku"})
    assert r_ku.status_code == 200
    ku_body = r_ku.get_json()
    assert ku_body["force_update_message"] not in (
        "Please update CarNet to continue.",
        ar_body["force_update_message"],
    )


def test_force_update_config_prefers_admin_override_for_locale(client, app_ctx):
    app, *_ = app_ctx
    from kk.app_settings import update_platform_settings

    with app.app_context():
        update_platform_settings({"force_update_message_ar": "رسالة مخصصة من الإدارة"})
    try:
        r = client.get("/api/config/app", headers={"Accept-Language": "ar"})
        assert r.status_code == 200
        assert r.get_json()["force_update_message"] == "رسالة مخصصة من الإدارة"

        # Kurdish is untouched by the Arabic-only override -- still the
        # built-in fallback.
        r_ku = client.get("/api/config/app", headers={"Accept-Language": "ku"})
        assert r_ku.get_json()["force_update_message"] != "رسالة مخصصة من الإدارة"
    finally:
        with app.app_context():
            update_platform_settings({"force_update_message_ar": ""})


def test_force_update_config_english_key_unaffected_by_locale_overrides(client, app_ctx):
    app, *_ = app_ctx
    from kk.app_settings import update_platform_settings

    with app.app_context():
        update_platform_settings({"force_update_message_ar": "رسالة مخصصة"})
    try:
        r = client.get("/api/config/app")  # no Accept-Language -> English
        assert r.get_json()["force_update_message"] == "Please update CarNet to continue."
    finally:
        with app.app_context():
            update_platform_settings({"force_update_message_ar": ""})


# --- BACKGROUND (MI-03-cited templates only) --------------------------------


def test_saved_search_alert_title_localized_via_recipient_locale(app_ctx):
    app, _client, db, User, Car, Notification, SavedSearch = app_ctx
    seller_id, _pub, _name = _make_user(app_ctx)
    recipient_id, _pub2, _name2 = _make_user(app_ctx, locale="ar")

    with app.app_context():
        car = Car(
            seller_id=seller_id,
            public_id=f"mi03-car-{uuid.uuid4().hex[:10]}",
            brand="toyota",
            model="corolla",
            year=2021,
            mileage=10,
            engine_type="gas",
            transmission="auto",
            drive_type="fwd",
            condition="used",
            body_type="sedan",
            price=15.0,
            location="Erbil",
            is_active=True,
        )
        db.session.add(car)
        db.session.commit()
        car_id = car.id

        search = SavedSearch(user_id=recipient_id, name="", filters={}, notify=True)
        db.session.add(search)
        db.session.commit()

        from kk.localization import translate
        from kk.tasks.alert_tasks import notify_saved_searches_for_car

        notify_saved_searches_for_car(car_id)

        notif = Notification.query.filter_by(
            user_id=recipient_id, notification_type="saved_search"
        ).first()
        assert notif is not None
        assert notif.title == translate("saved_search_default_title", "ar")
        assert notif.title != "Saved search"


def test_price_drop_alert_title_localized_per_recipient(app_ctx):
    app, _client, db, User, Car, Notification, _SavedSearch = app_ctx
    seller_id, _pub, _name = _make_user(app_ctx)
    buyer_en_id, _pub2, _name2 = _make_user(app_ctx, locale=None)
    buyer_ku_id, _pub3, _name3 = _make_user(app_ctx, locale="ku")

    with app.app_context():
        car = Car(
            seller_id=seller_id,
            public_id=f"mi03-pd-car-{uuid.uuid4().hex[:10]}",
            brand="toyota",
            model="corolla",
            year=2021,
            mileage=10,
            engine_type="gas",
            transmission="auto",
            drive_type="fwd",
            condition="used",
            body_type="sedan",
            price=20.0,
            location="Erbil",
            is_active=True,
        )
        db.session.add(car)
        db.session.commit()
        car_id = car.id

        from kk.models import user_favorites

        db.session.execute(
            user_favorites.insert().values(
                user_id=buyer_en_id, car_id=car_id, price_at_favorite=20.0
            )
        )
        db.session.execute(
            user_favorites.insert().values(
                user_id=buyer_ku_id, car_id=car_id, price_at_favorite=20.0
            )
        )
        db.session.commit()

        from kk.localization import translate
        from kk.tasks.alert_tasks import notify_price_drop_for_car

        notify_price_drop_for_car(car_id, old_price=20.0, new_price=15.0)

        notif_en = Notification.query.filter_by(
            user_id=buyer_en_id, notification_type="price_drop"
        ).first()
        notif_ku = Notification.query.filter_by(
            user_id=buyer_ku_id, notification_type="price_drop"
        ).first()
        assert notif_en is not None and notif_ku is not None
        assert notif_en.title == "Price drop"
        assert notif_ku.title == translate("price_drop_title", "ku")
        assert notif_ku.title != notif_en.title
        # The numeric/brand body is locale-neutral and identical for both.
        assert notif_en.message == notif_ku.message


def test_dealer_email_verification_code_localized_subject_and_body():
    from kk.email_service import send_dealer_email_verification_code

    captured = {}

    def _fake_send_email(to_email, *, subject, text_body, html_body=None):
        captured["subject"] = subject
        captured["text_body"] = text_body
        return True

    with mock.patch("kk.email_service.send_email", side_effect=_fake_send_email):
        ok = send_dealer_email_verification_code(
            "dealer@example.com", "123456", locale="ar"
        )
    assert ok is True
    assert captured["subject"] != "Your Carzo verification code"
    assert "123456" in captured["text_body"]


def test_dealer_email_verification_code_defaults_to_english():
    from kk.email_service import send_dealer_email_verification_code

    captured = {}

    def _fake_send_email(to_email, *, subject, text_body, html_body=None):
        captured["subject"] = subject
        return True

    with mock.patch("kk.email_service.send_email", side_effect=_fake_send_email):
        send_dealer_email_verification_code("dealer@example.com", "654321")
    assert captured["subject"] == "Your Carzo verification code"


def test_password_reset_console_sms_localized(monkeypatch, capsys):
    from kk.sms_service import sms_service

    monkeypatch.setenv("APP_ENV", "testing")
    monkeypatch.delenv("FLASK_ENV", raising=False)

    ok, _detail = sms_service.send_password_reset_code(
        "07701234567", "999888", locale="ar"
    )
    assert ok is True
    out = capsys.readouterr().out
    assert "999888" in out
    assert "Your password reset code is" not in out  # localized, not English

    ok, _detail = sms_service.send_password_reset_code("07701234567", "111222")
    assert ok is True
    out = capsys.readouterr().out
    assert "Your password reset code is: 111222" in out  # default English unchanged
