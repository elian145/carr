"""CarNet V1 feature-completeness batch 2 -- item 4 (localize
backend-generated notifications for Arabic/Kurdish).

Investigation: `kk/localization.py` (`translate` / `get_background_locale`,
closed under MI-03/U-01) is already wired into every current
Notification-creating call site in the backend -- dealer-application
lifecycle (`kk/routes/user.py::_save_dealer_application`, `kk/routes/
admin.py::_review_dealer_application`) and chat message notifications
(`kk/chat_realtime.py::deliver_message`, `kk/socketio_handlers.py`'s
`send_message` handler). There is no admin/moderation notification type
that exists today for listing status changes (`update_car_status` /
`bulk_update_car_status` / `delete_car` in `kk/routes/admin.py` mutate
`Car.status`/`is_active` directly and never construct a `Notification` row),
so there is nothing hardcoded left to localize there; per the batch-2
instructions this file does not invent a new notification flow for that
case.

What WAS actually missing was test coverage: `test_mi03_locale.py` covers
`translate()` itself plus auth/force-update/saved-search/price-drop/email/
SMS strings, but never exercised the dealer-application or chat-message
paths end-to-end per recipient locale. This file closes that gap:

  1. `_review_dealer_application()` (admin decision on a dealer application)
     -- title localized for every action (under_review/needs_changes/
     approved/rejected); default body localized when the admin supplies no
     free-text reason; a supplied `reason` (needs_changes/rejected) is
     always the admin's own words verbatim, in ANY locale -- never
     translated/altered/dropped.
  2. `_save_dealer_application()` (submission confirmation notification)
     -- title/body localized by the *applicant's* own stored locale.
  3. `chat_realtime.deliver_message()` -- in-app Notification title and FCM
     push title (with the sender's name interpolated) localized by the
     *receiver's* stored locale, independent of the sender's locale.
  4. `kk/socketio_handlers.py`'s realtime `send_message` socket event --
     same in-app Notification title localization as (3), via the other
     code path (C-02 socket path vs. REST fallback path).

All four localize by recipient locale: 'ar' -> Arabic, 'ku' -> Kurdish,
unknown/missing/unsupported locale -> English (the existing `translate()`
fallback), and English itself stays byte-for-byte the existing copy.
"""

from __future__ import annotations

import os
import sys
import tempfile
import uuid
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

os.environ.setdefault("APP_ENV", "testing")
os.environ.setdefault("SECRET_KEY", "test-secret-key-for-carnet-v1-batch2-notif-i18n")
os.environ.setdefault("JWT_SECRET_KEY", "test-jwt-secret-key-for-carnet-v1-batch2-notif-i18n")

_PASSWORD = "Aa123456!"


# ---------------------------------------------------------------------------
# Part A: chat_realtime.deliver_message() -- fast, fully mocked (mirrors
# test_chat_deliver_message.py's style), no DB/app context needed.
# ---------------------------------------------------------------------------


def _make_msg(content: str = "hello there", car_public_id: str | None = "car-pub-1"):
    car = SimpleNamespace(public_id=car_public_id) if car_public_id is not None else None
    msg = SimpleNamespace(id=99, public_id="msg-pub-1", content=content, car=car)
    msg.to_dict = lambda: {"id": msg.public_id, "content": msg.content}
    return msg


def _make_sender(first_name: str = "Sen", last_name: str = "Der"):
    return SimpleNamespace(
        id=1, public_id="sender-pub", first_name=first_name, last_name=last_name
    )


def _make_receiver(locale: str | None, fcm_token: str | None = "fcm-token-123"):
    return SimpleNamespace(
        id=2, public_id="receiver-pub", firebase_token=fcm_token, locale=locale
    )


def _patched_deliver_message():
    from kk import chat_realtime

    return (
        patch.object(chat_realtime, "emit_message_to_participants"),
        patch.object(chat_realtime, "Notification"),
        patch.object(chat_realtime, "db"),
        patch.object(chat_realtime, "send_push"),
    )


@pytest.mark.parametrize(
    "locale, expected_title",
    [
        ("ar", "رسالة جديدة"),
        ("ku", "پەیامی نوێ"),
        ("en", "New message"),
        (None, "New message"),
        ("fr", "New message"),  # unsupported -> English fallback, never raises
    ],
)
def test_deliver_message_notification_title_localized_by_receiver_locale(locale, expected_title):
    from kk import chat_realtime

    msg = _make_msg()
    sender = _make_sender()
    receiver = _make_receiver(locale)

    p_emit, p_notif, p_db, p_push = _patched_deliver_message()
    with p_emit, p_notif as notif_cls, p_db, p_push:
        chat_realtime.deliver_message(msg, sender=sender, receiver=receiver)

    notif_cls.assert_called_once()
    _, kwargs = notif_cls.call_args
    assert kwargs["title"] == expected_title


@pytest.mark.parametrize(
    "locale, sender_name, expected_title",
    [
        ("ar", "Karzan", "رسالة جديدة من Karzan"),
        ("ku", "Karzan", "پەیامی نوێ لە Karzan"),
        ("en", "Karzan", "New message from Karzan"),
        (None, "Karzan", "New message from Karzan"),
    ],
)
def test_deliver_message_push_title_localized_with_sender_name(locale, sender_name, expected_title):
    from kk import chat_realtime

    first, last = sender_name, ""
    msg = _make_msg()
    sender = _make_sender(first_name=first, last_name=last)
    receiver = _make_receiver(locale)

    p_emit, p_notif, p_db, p_push = _patched_deliver_message()
    with p_emit, p_notif, p_db, p_push as push_mock:
        chat_realtime.deliver_message(msg, sender=sender, receiver=receiver)

    push_mock.assert_called_once()
    _, push_kwargs = push_mock.call_args
    assert push_kwargs["title"] == expected_title


def test_deliver_message_never_localizes_by_senders_locale():
    """Regression guard: it is the RECEIVER's locale that must drive the
    notification language, never the sender's -- a Kurdish-speaking buyer
    messaging an Arabic-speaking seller must not get an Arabic in-app
    notification themselves; the SELLER (receiver) does."""
    from kk import chat_realtime

    msg = _make_msg()
    sender = SimpleNamespace(
        id=1, public_id="sender-pub", first_name="S", last_name="", locale="ku"
    )
    receiver = _make_receiver("ar")

    p_emit, p_notif, p_db, p_push = _patched_deliver_message()
    with p_emit, p_notif as notif_cls, p_db, p_push:
        chat_realtime.deliver_message(msg, sender=sender, receiver=receiver)

    _, kwargs = notif_cls.call_args
    assert kwargs["title"] == "رسالة جديدة"  # receiver's (ar), not sender's (ku)


# ---------------------------------------------------------------------------
# Part B: real Flask app + DB fixture for the dealer-application lifecycle
# (admin decision + applicant submission) and the socketio chat path.
# ---------------------------------------------------------------------------


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_batch2_notif_i18n_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "batch2_notif_i18n.db")

    from kk.app_factory import create_app

    app, socketio, *_ = create_app()
    from kk.models import Car, DealerApplication, Notification, User, db

    with app.app_context():
        db.drop_all()
        db.create_all()

    yield app, socketio, app.test_client(), db, User, Car, Notification, DealerApplication

    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    tmp.cleanup()


def _phone() -> str:
    return f"077{uuid.uuid4().int % 10**8:08d}"


def _make_user(app_ctx, *, tag: str, locale: str | None = None, is_admin: bool = False):
    app, _socketio, _client, db, User, *_ = app_ctx
    with app.app_context():
        user = User(
            username=f"b2ni_{tag}_{uuid.uuid4().hex[:10]}",
            phone_number=_phone(),
            first_name="B2",
            last_name="Notif",
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id=f"b2ni-{tag}-{uuid.uuid4().hex[:12]}",
            is_admin=is_admin,
            locale=locale,
        )
        user.set_password(_PASSWORD)
        db.session.add(user)
        db.session.commit()
        return user.id


# --- B1: admin dealer-application decisions (_review_dealer_application) ---


@pytest.mark.parametrize(
    "locale, expected_title, expected_default_body",
    [
        ("ar", "طلب المعرض قيد المراجعة", "بدأ أحد المسؤولين بمراجعة طلب معرضك."),
        ("ku", "داواکاری شوکە لە ژێر پێداچوونەوەدایە", "بەڕێوەبەرێک دەستی کرد بە پێداچوونەوە بە داواکاری شوکەکەت."),
        ("en", "Dealer application under review", "An administrator has started reviewing your dealer application."),
        (None, "Dealer application under review", "An administrator has started reviewing your dealer application."),
    ],
)
def test_dealer_decision_under_review_localized_by_applicant_locale(
    app_ctx, locale, expected_title, expected_default_body
):
    app, _socketio, _client, db, User, _Car, Notification, DealerApplication = app_ctx
    admin_id = _make_user(app_ctx, tag="admin_ur", is_admin=True)
    applicant_id = _make_user(app_ctx, tag="applicant_ur", locale=locale)

    with app.app_context():
        db.session.add(
            DealerApplication(
                user_id=applicant_id,
                status="submitted",
                dealership_name="Batch2 Motors",
                dealership_phone="07700000001",
                dealership_location="Erbil",
            )
        )
        db.session.commit()

        from kk.routes.admin import _review_dealer_application

        admin_user = db.session.get(User, admin_id)
        target = db.session.get(User, applicant_id)
        _application, notification = _review_dealer_application(target, admin_user, "under_review")
        db.session.commit()

        assert notification.title == expected_title
        assert notification.message == expected_default_body


@pytest.mark.parametrize(
    "locale, expected_title",
    [
        ("ar", "طلب المعرض يحتاج إلى تعديلات"),
        ("ku", "داواکاری شوکە پێویستی بە گۆڕانکاری هەیە"),
        ("en", "Dealer application needs changes"),
    ],
)
def test_dealer_decision_needs_changes_reason_passed_through_verbatim_any_locale(
    app_ctx, locale, expected_title
):
    """The title is localized, but the admin's own free-text `reason` must
    reach the applicant byte-for-byte in every locale -- it is never run
    through `translate()` (there is nothing to translate; it's the admin's
    own words)."""
    app, _socketio, _client, db, User, _Car, Notification, DealerApplication = app_ctx
    admin_id = _make_user(app_ctx, tag="admin_nc", is_admin=True)
    applicant_id = _make_user(app_ctx, tag="applicant_nc", locale=locale)

    with app.app_context():
        db.session.add(
            DealerApplication(
                user_id=applicant_id,
                status="submitted",
                dealership_name="Batch2 Motors",
                dealership_phone="07700000002",
                dealership_location="Erbil",
            )
        )
        db.session.commit()

        from kk.routes.admin import _review_dealer_application

        admin_user = db.session.get(User, admin_id)
        target = db.session.get(User, applicant_id)
        admin_reason = "Please re-upload a clearer verification photo."
        _application, notification = _review_dealer_application(
            target, admin_user, "needs_changes", admin_reason
        )
        db.session.commit()

        assert notification.title == expected_title
        assert notification.message == admin_reason  # untouched, not translated


@pytest.mark.parametrize(
    "locale, expected_title",
    [
        ("ar", "تم رفض طلب المعرض"),
        ("ku", "داواکاری شوکە ڕەتکرایەوە"),
        ("en", "Dealer application declined"),
    ],
)
def test_dealer_decision_rejected_title_localized_reason_verbatim(app_ctx, locale, expected_title):
    """The route requires an admin-supplied `reason` for `rejected` (see
    `dealers_reject()`), so the localized default fallback body is
    unreachable via any real caller -- assert the reachable behavior
    instead: the title is localized, and the admin's own written reason
    reaches the applicant untouched in every locale."""
    app, _socketio, _client, db, User, _Car, Notification, DealerApplication = app_ctx
    admin_id = _make_user(app_ctx, tag="admin_rej", is_admin=True)
    applicant_id = _make_user(app_ctx, tag="applicant_rej", locale=locale)

    with app.app_context():
        db.session.add(
            DealerApplication(
                user_id=applicant_id,
                status="submitted",
                dealership_name="Batch2 Motors",
                dealership_phone="07700000003",
                dealership_location="Erbil",
            )
        )
        db.session.commit()

        from kk.routes.admin import _review_dealer_application

        admin_user = db.session.get(User, admin_id)
        target = db.session.get(User, applicant_id)
        admin_reason = "Business registration document was invalid."
        _application, notification = _review_dealer_application(
            target, admin_user, "rejected", admin_reason
        )
        db.session.commit()

        assert notification.title == expected_title
        assert notification.message == admin_reason  # untouched, not translated


def test_dealer_decision_approved_localized_via_full_admin_route(app_ctx):
    """End-to-end through the real HTTP route (not just the helper), proving
    the applicant's locale reaches the Notification row created by
    `POST /api/admin/dealers/<id>/approve`."""
    app, _socketio, client, db, User, _Car, Notification, DealerApplication = app_ctx
    admin_id = _make_user(app_ctx, tag="admin_appr", is_admin=True)
    applicant_id = _make_user(app_ctx, tag="applicant_appr", locale="ku")

    with app.app_context():
        db.session.add(
            DealerApplication(
                user_id=applicant_id,
                status="submitted",
                dealership_name="Batch2 Motors",
                dealership_phone="07700000004",
                dealership_location="Erbil",
            )
        )
        db.session.commit()
        admin_user = db.session.get(User, admin_id)
        admin_username = admin_user.username
        applicant_pub = db.session.get(User, applicant_id).public_id

    login = client.post(
        "/api/auth/login", json={"username": admin_username, "password": _PASSWORD}
    )
    assert login.status_code == 200, login.data
    token = login.get_json()["access_token"]

    resp = client.post(
        f"/api/admin/dealers/{applicant_pub}/approve",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert resp.status_code == 200, resp.data

    with app.app_context():
        notif = Notification.query.filter_by(
            user_id=applicant_id, notification_type="dealer_application"
        ).first()
        assert notif is not None
        assert notif.title == "داواکاری شوکە پەسەند کرا"
        assert notif.message != ""
        assert "شوکەکەت" in notif.message  # Kurdish approved body, not English


# --- B2: applicant's own dealer-application-submitted confirmation --------


@pytest.mark.parametrize(
    "locale, expected_title, expected_body",
    [
        ("ar", "تم إرسال طلب المعرض", "تم استلام بيانات معرضك وهي جاهزة للمراجعة."),
        ("ku", "داواکاری شوکە نێردرا", "زانیارییەکانی شوکەکەت وەرگیران و ئامادەن بۆ پێداچوونەوە."),
        ("en", "Dealer application submitted", "Your dealership details were received and are ready for review."),
        (None, "Dealer application submitted", "Your dealership details were received and are ready for review."),
    ],
)
def test_dealer_application_submitted_notification_localized_by_applicant_locale(
    app_ctx, locale, expected_title, expected_body
):
    app, _socketio, _client, db, User, _Car, Notification, DealerApplication = app_ctx
    applicant_id = _make_user(app_ctx, tag="submitter", locale=locale)

    with app.app_context():
        # Pre-satisfy the verification-photo precondition so `submit=True`
        # succeeds without exercising the unrelated upload flow.
        application = DealerApplication(
            user_id=applicant_id,
            status="draft",
            dealership_name="Draft Motors",
            dealership_phone="07700000005",
            dealership_location="Erbil",
            verification_photo_filename="already-uploaded.jpg",
        )
        db.session.add(application)
        db.session.commit()

        from kk.routes.user import _save_dealer_application

        user = db.session.get(User, applicant_id)
        _save_dealer_application(
            user,
            {
                "dealership_name": "Draft Motors Updated",
                "dealership_phone": "07700000005",
                "dealership_location": "Erbil",
                "submit": True,
            },
        )
        db.session.commit()

        notif = Notification.query.filter_by(
            user_id=applicant_id, notification_type="dealer_application"
        ).first()
        assert notif is not None
        assert notif.title == expected_title
        assert notif.message == expected_body


# --- B3: realtime socket send_message -> receiver-localized in-app title --


def test_socketio_send_message_notification_localized_by_receiver_locale(app_ctx):
    app, socketio, client, db, User, Car, Notification, _DA = app_ctx
    buyer_id = _make_user(app_ctx, tag="sio_buyer", locale="en")
    seller_id = _make_user(app_ctx, tag="sio_seller", locale="ar")

    with app.app_context():
        buyer = db.session.get(User, buyer_id)
        buyer_username = buyer.username
        seller = db.session.get(User, seller_id)
        seller_pub = seller.public_id

        car = Car(
            seller_id=seller_id,
            public_id=f"b2ni-car-{uuid.uuid4().hex[:10]}",
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
        car_pub = car.public_id

    login = client.post(
        "/api/auth/login", json={"username": buyer_username, "password": _PASSWORD}
    )
    assert login.status_code == 200, login.data
    buyer_token = login.get_json()["access_token"]

    sio_client = socketio.test_client(app, flask_test_client=client, query_string=f"token={buyer_token}")
    assert sio_client.is_connected(), sio_client.get_received()
    sio_client.get_received()  # drain "connected"

    with patch("kk.socketio_handlers.send_push", return_value=True):
        sio_client.emit(
            "send_message",
            {"car_id": car_pub, "content": "Is this still available?", "receiver_id": seller_pub},
        )
        sio_client.get_received()
    sio_client.disconnect()

    with app.app_context():
        notif = Notification.query.filter_by(
            user_id=seller_id, notification_type="message"
        ).first()
        assert notif is not None
        assert notif.title == "رسالة جديدة"  # seller's (ar) locale, not buyer's (en)
