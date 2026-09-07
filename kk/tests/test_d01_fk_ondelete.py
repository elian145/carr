"""D-01: explicit ON DELETE policies and the account/listing deletion paths.

SQLite-side coverage. These tests are *not* a substitute for the Postgres
smoke in ``scripts/ci_migration_smoke.py::_d01_fk_ondelete_smoke`` — they
exist for fast local/CI feedback once ``PRAGMA foreign_keys=ON`` is set
by ``kk/app_factory.py``.
"""

from __future__ import annotations

import os
import sys
import tempfile
import uuid
from pathlib import Path

import pytest
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

_PASSWORD = "Aa123456!"


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_d01_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "d01.db")

    from kk.app_factory import create_app

    app, _socketio, *_ = create_app()
    from kk.models import db

    with app.app_context():
        db.drop_all()
        db.create_all()
        # Prove the D-01 pragma actually landed on this engine.
        pragma = db.session.execute(text("PRAGMA foreign_keys")).scalar()
        assert int(pragma or 0) == 1, "SQLite foreign_keys pragma must be ON for D-01"

    yield app, app.test_client(), db

    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    tmp.cleanup()


@pytest.fixture
def client(app_ctx):
    return app_ctx[1]


def _phone() -> str:
    return f"077{uuid.uuid4().int % 10**8:08d}"


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _login(client, username: str) -> str:
    r = client.post("/api/auth/login", json={"username": username, "password": _PASSWORD})
    assert r.status_code == 200, r.data
    return r.get_json()["access_token"]


def _make_user(app, db, *, username=None, is_admin=False, **extra):
    from kk.models import User

    username = username or f"u_{uuid.uuid4().hex[:10]}"
    with app.app_context():
        user = User(
            username=username,
            phone_number=_phone(),
            first_name="First",
            last_name="Last",
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id=f"pub-{uuid.uuid4().hex[:12]}",
            is_admin=is_admin,
            **extra,
        )
        user.set_password(_PASSWORD)
        db.session.add(user)
        db.session.commit()
        return user.id, user.public_id, username


def _make_car(app, db, seller_id: int, **extra):
    from kk.models import Car

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
            **extra,
        )
        db.session.add(car)
        db.session.commit()
        return car.id, car.public_id


class TestSqliteFkPolicies:
    def test_car_seller_restrict_blocks_user_delete(self, app_ctx):
        app, _client, db = app_ctx
        from kk.models import User

        uid, _pub, _name = _make_user(app, db)
        _make_car(app, db, uid)
        with app.app_context():
            user = db.session.get(User, uid)
            db.session.delete(user)
            with pytest.raises(IntegrityError):
                db.session.commit()
            db.session.rollback()
            assert db.session.get(User, uid) is not None

    def test_deleting_car_cascades_media_and_analytics_and_nulls_message_car(
        self, app_ctx
    ):
        app, _client, db = app_ctx
        from kk.models import (
            Car,
            CarImage,
            CarVideo,
            ListingAnalytics,
            ListingReport,
            Message,
            SavedSearch,
            SavedSearchAlert,
        )

        seller_id, _sp, _sn = _make_user(app, db)
        other_id, _op, _on = _make_user(app, db)
        car_id, _cp = _make_car(app, db, seller_id)
        with app.app_context():
            db.session.add(
                CarImage(car_id=car_id, image_url="https://example.com/a.jpg")
            )
            db.session.add(
                CarVideo(car_id=car_id, video_url="https://example.com/a.mp4")
            )
            db.session.add(ListingAnalytics(car_id=car_id))
            report = ListingReport(
                reporter_id=other_id, car_id=car_id, reason="spam"
            )
            db.session.add(report)
            msg = Message(
                sender_id=other_id,
                receiver_id=seller_id,
                car_id=car_id,
                content="hello",
            )
            db.session.add(msg)
            search = SavedSearch(
                user_id=other_id, name="s", filters={"brand": "toyota"}
            )
            db.session.add(search)
            db.session.flush()
            alert = SavedSearchAlert(saved_search_id=search.id, car_id=car_id)
            db.session.add(alert)
            db.session.commit()
            report_id = report.id
            msg_id = msg.id
            search_id = search.id

            # Prove the database ON DELETE policy, not the ORM unit-of-work.
            db.session.execute(text("DELETE FROM car WHERE id = :id"), {"id": car_id})
            db.session.commit()
            db.session.expire_all()

            assert db.session.get(Car, car_id) is None
            assert CarImage.query.filter_by(car_id=car_id).count() == 0
            assert CarVideo.query.filter_by(car_id=car_id).count() == 0
            assert ListingAnalytics.query.filter_by(car_id=car_id).count() == 0
            assert SavedSearchAlert.query.filter_by(car_id=car_id).count() == 0
            assert db.session.get(SavedSearch, search_id) is not None
            kept_report = db.session.get(ListingReport, report_id)
            assert kept_report is not None
            assert kept_report.car_id is None
            kept_msg = db.session.get(Message, msg_id)
            assert kept_msg is not None
            assert kept_msg.car_id is None

    def test_reply_to_set_null_when_parent_deleted(self, app_ctx):
        app, _client, db = app_ctx
        from kk.models import Message

        a_id, _ap, _an = _make_user(app, db)
        b_id, _bp, _bn = _make_user(app, db)
        with app.app_context():
            parent = Message(
                sender_id=a_id, receiver_id=b_id, content="parent"
            )
            db.session.add(parent)
            db.session.flush()
            reply = Message(
                sender_id=b_id,
                receiver_id=a_id,
                content="reply",
                reply_to_id=parent.id,
            )
            db.session.add(reply)
            db.session.commit()
            reply_id = reply.id
            db.session.delete(parent)
            db.session.commit()
            kept = db.session.get(Message, reply_id)
            assert kept is not None
            assert kept.reply_to_id is None
            assert kept._reply_preview() is None

    def test_deleting_carless_user_nulls_messages_reports_and_dealer_rows(
        self, app_ctx
    ):
        app, _client, db = app_ctx
        from kk.models import (
            DealerApplication,
            DealerDecision,
            DealerProfile,
            ListingReport,
            Message,
            Notification,
            ScheduledNotification,
            User,
            UserReport,
        )

        doomed_id, _dp, _dn = _make_user(app, db)
        other_id, _op, _on = _make_user(app, db)
        seller_id, _sp, _sn = _make_user(app, db)
        car_id, _cp = _make_car(app, db, seller_id)
        with app.app_context():
            msg = Message(
                sender_id=doomed_id, receiver_id=other_id, content="hi"
            )
            db.session.add(msg)
            urep = UserReport(
                reporter_id=other_id, reported_id=doomed_id, reason="spam"
            )
            db.session.add(urep)
            lrep = ListingReport(
                reporter_id=doomed_id, car_id=car_id, reason="fake"
            )
            db.session.add(lrep)
            appn = DealerApplication(
                user_id=doomed_id,
                status="submitted",
                dealership_name="Shop",
                dealership_phone="07700000000",
                dealership_location="Erbil",
            )
            db.session.add(appn)
            db.session.flush()
            decision = DealerDecision(
                application_id=appn.id,
                reviewer_id=doomed_id,
                decision="approved",
                application_snapshot={},
            )
            db.session.add(decision)
            profile = DealerProfile(
                user_id=doomed_id,
                dealership_name="Shop",
                dealership_phone="07700000000",
                dealership_location="Erbil",
            )
            db.session.add(profile)
            notif = Notification(
                user_id=doomed_id,
                title="t",
                message="m",
                notification_type="admin",
            )
            db.session.add(notif)
            from kk.time_utils import utcnow

            sched = ScheduledNotification(
                title="blast",
                message="hello",
                scheduled_at=utcnow(),
                created_by_user_id=doomed_id,
            )
            db.session.add(sched)
            db.session.commit()
            ids = {
                "msg": msg.id,
                "urep": urep.id,
                "lrep": lrep.id,
                "app": appn.id,
                "dec": decision.id,
                "prof": profile.id,
                "notif": notif.id,
                "sched": sched.id,
            }

            db.session.delete(db.session.get(User, doomed_id))
            db.session.commit()

            assert db.session.get(User, doomed_id) is None
            assert db.session.get(Notification, ids["notif"]) is None
            kept_msg = db.session.get(Message, ids["msg"])
            assert kept_msg is not None
            assert kept_msg.sender_id is None
            assert kept_msg.receiver_id == other_id
            kept_urep = db.session.get(UserReport, ids["urep"])
            assert kept_urep is not None
            assert kept_urep.reported_id is None
            kept_lrep = db.session.get(ListingReport, ids["lrep"])
            assert kept_lrep is not None
            assert kept_lrep.reporter_id is None
            kept_app = db.session.get(DealerApplication, ids["app"])
            assert kept_app is not None
            assert kept_app.user_id is None
            kept_prof = db.session.get(DealerProfile, ids["prof"])
            assert kept_prof is not None
            assert kept_prof.user_id is None
            kept_dec = db.session.get(DealerDecision, ids["dec"])
            assert kept_dec is not None
            assert kept_dec.reviewer_id is None
            kept_sched = db.session.get(ScheduledNotification, ids["sched"])
            assert kept_sched is not None
            assert kept_sched.created_by_user_id is None

    def test_admin_account_principal_restrict(self, app_ctx):
        app, _client, db = app_ctx
        from kk.models import AdminAccount, User

        uid, pub, name = _make_user(app, db, is_admin=True)
        with app.app_context():
            acct = AdminAccount(
                principal_user_id=uid,
                origin_user_public_id=pub,
                username=f"dash_{name}",
                password_hash="x" * 60,
                admin_role="super_admin",
            )
            db.session.add(acct)
            db.session.commit()
            db.session.delete(db.session.get(User, uid))
            with pytest.raises(IntegrityError):
                db.session.commit()
            db.session.rollback()
            assert db.session.get(User, uid) is not None
            assert AdminAccount.query.filter_by(principal_user_id=uid).first()

    def test_catalog_brand_delete_cascades_models_and_trims(self, app_ctx):
        app, _client, db = app_ctx
        from kk.models import CatalogBrand, CatalogTrim, CatalogVehicleModel

        with app.app_context():
            brand = CatalogBrand(name=f"Brand-{uuid.uuid4().hex[:8]}")
            db.session.add(brand)
            db.session.flush()
            model = CatalogVehicleModel(brand_id=brand.id, name="X")
            db.session.add(model)
            db.session.flush()
            trim = CatalogTrim(model_id=model.id, name="Base")
            db.session.add(trim)
            db.session.commit()
            brand_id, model_id, trim_id = brand.id, model.id, trim.id
            db.session.delete(db.session.get(CatalogBrand, brand_id))
            db.session.commit()
            assert db.session.get(CatalogBrand, brand_id) is None
            assert db.session.get(CatalogVehicleModel, model_id) is None
            assert db.session.get(CatalogTrim, trim_id) is None


class TestDeleteAccountHttp:
    def test_user_with_car_is_anonymized_and_history_survives(self, app_ctx, client):
        app, _c, db = app_ctx
        from kk.models import (
            Car,
            DealerApplication,
            ListingReport,
            Message,
            User,
            UserReport,
        )

        seller_id, seller_pub, seller_name = _make_user(app, db)
        other_id, _op, _on = _make_user(app, db)
        car_id, _cp = _make_car(app, db, seller_id)
        marker = f"keep-{seller_id}"
        with app.app_context():
            db.session.add(
                Message(
                    sender_id=other_id,
                    receiver_id=seller_id,
                    car_id=car_id,
                    content=marker,
                )
            )
            db.session.add(
                UserReport(
                    reporter_id=other_id, reported_id=seller_id, reason=marker
                )
            )
            db.session.add(
                ListingReport(reporter_id=other_id, car_id=car_id, reason=marker)
            )
            shop_name = f"Shop-{seller_id}"
            db.session.add(
                DealerApplication(
                    user_id=seller_id,
                    status="approved",
                    dealership_name=shop_name,
                    dealership_phone="07700000000",
                    dealership_location="Erbil",
                )
            )
            db.session.commit()

        token = _login(client, seller_name)
        resp = client.post(
            "/api/auth/delete-account",
            json={"password": _PASSWORD},
            headers=_auth(token),
        )
        assert resp.status_code == 200, resp.data

        with app.app_context():
            user = db.session.get(User, seller_id)
            assert user is not None
            assert user.is_active is False
            assert user.username.startswith("deleted_")
            car = db.session.get(Car, car_id)
            assert car is not None
            assert car.is_active is False
            assert Message.query.filter_by(content=marker).count() == 1
            assert UserReport.query.filter_by(reason=marker).count() == 1
            assert ListingReport.query.filter_by(reason=marker).count() == 1
            appn = DealerApplication.query.filter_by(user_id=seller_id).first()
            assert appn is not None
            assert appn.dealership_name == f"Shop-{seller_id}"

    def test_carless_user_hard_delete_nulls_messages_and_reports(self, app_ctx, client):
        app, _c, db = app_ctx
        from kk.models import Message, User, UserReport

        doomed_id, doomed_pub, doomed_name = _make_user(app, db)
        other_id, _op, _on = _make_user(app, db)
        with app.app_context():
            msg = Message(
                sender_id=doomed_id, receiver_id=other_id, content="hist"
            )
            db.session.add(msg)
            urep = UserReport(
                reporter_id=doomed_id, reported_id=other_id, reason="abuse"
            )
            db.session.add(urep)
            db.session.commit()
            msg_id, urep_id = msg.id, urep.id

        token = _login(client, doomed_name)
        resp = client.post(
            "/api/auth/delete-account",
            json={"password": _PASSWORD},
            headers=_auth(token),
        )
        assert resp.status_code == 200, resp.data

        with app.app_context():
            assert db.session.get(User, doomed_id) is None
            kept_msg = db.session.get(Message, msg_id)
            assert kept_msg is not None
            assert kept_msg.sender_id is None
            assert kept_msg.receiver_id == other_id
            kept_rep = db.session.get(UserReport, urep_id)
            assert kept_rep is not None
            assert kept_rep.reporter_id is None
            assert kept_rep.reported_id == other_id


class TestAdminListingPaths:
    def test_soft_delete_car_leaves_children(self, app_ctx, client):
        app, _c, db = app_ctx
        from kk.models import Car, ListingAnalytics, ListingReport, Message

        admin_id, _ap, admin_name = _make_user(app, db, is_admin=True)
        seller_id, _sp, _sn = _make_user(app, db)
        other_id, _op, _on = _make_user(app, db)
        car_id, car_pub = _make_car(app, db, seller_id)
        with app.app_context():
            db.session.add(ListingAnalytics(car_id=car_id))
            db.session.add(
                ListingReport(reporter_id=other_id, car_id=car_id, reason="soft")
            )
            db.session.add(
                Message(
                    sender_id=other_id,
                    receiver_id=seller_id,
                    car_id=car_id,
                    content="soft-keep",
                )
            )
            db.session.commit()

        token = _login(client, admin_name)
        resp = client.delete(
            f"/api/admin/cars/{car_pub}", headers=_auth(token)
        )
        assert resp.status_code == 200, resp.data
        with app.app_context():
            car = db.session.get(Car, car_id)
            assert car is not None
            assert car.is_active is False
            assert ListingAnalytics.query.filter_by(car_id=car_id).count() == 1
            assert ListingReport.query.filter_by(car_id=car_id).count() == 1
            assert Message.query.filter_by(content="soft-keep").count() == 1

    def test_purge_car_keeps_listing_report_and_erases_analytics_messages(
        self, app_ctx, client
    ):
        app, _c, db = app_ctx
        from kk.models import Car, ListingAnalytics, ListingReport, Message

        _admin_id, _ap, admin_name = _make_user(app, db, is_admin=True)
        seller_id, _sp, _sn = _make_user(app, db)
        other_id, _op, _on = _make_user(app, db)
        car_id, car_pub = _make_car(app, db, seller_id)
        with app.app_context():
            db.session.add(ListingAnalytics(car_id=car_id))
            report = ListingReport(
                reporter_id=other_id, car_id=car_id, reason="purge-keep"
            )
            db.session.add(report)
            db.session.add(
                Message(
                    sender_id=other_id,
                    receiver_id=seller_id,
                    car_id=car_id,
                    content="purge-gone",
                )
            )
            db.session.commit()
            report_id = report.id

        token = _login(client, admin_name)
        resp = client.delete(
            f"/api/admin/cars/{car_pub}/purge", headers=_auth(token)
        )
        assert resp.status_code == 200, resp.data
        with app.app_context():
            assert db.session.get(Car, car_id) is None
            assert ListingAnalytics.query.filter_by(car_id=car_id).count() == 0
            assert Message.query.filter_by(content="purge-gone").count() == 0
            kept = db.session.get(ListingReport, report_id)
            assert kept is not None
            assert kept.car_id is None
            payload = kept.to_admin_dict()
            assert payload["listing"]["id"] is None

    def test_purge_user_anonymizes_and_does_not_hard_delete(self, app_ctx, client):
        app, _c, db = app_ctx
        from kk.models import Car, User

        _admin_id, _ap, admin_name = _make_user(app, db, is_admin=True)
        seller_id, seller_pub, _sn = _make_user(app, db)
        car_id, _cp = _make_car(app, db, seller_id)

        token = _login(client, admin_name)
        resp = client.delete(
            f"/api/admin/users/{seller_pub}/purge", headers=_auth(token)
        )
        assert resp.status_code == 200, resp.data
        with app.app_context():
            user = db.session.get(User, seller_id)
            assert user is not None
            assert user.is_active is False
            assert user.username.startswith("deleted_")
            car = db.session.get(Car, car_id)
            assert car is not None
            assert car.seller_id == seller_id


class TestChatNullHandling:
    def test_list_chats_survives_deleted_counterpart(self, app_ctx, client):
        app, _c, db = app_ctx
        from kk.models import Message, User

        seller_id, _sp, seller_name = _make_user(app, db)
        other_id, _op, other_name = _make_user(app, db)
        car_id, _cp = _make_car(app, db, seller_id)
        with app.app_context():
            db.session.add(
                Message(
                    sender_id=other_id,
                    receiver_id=seller_id,
                    car_id=car_id,
                    content="from doomed",
                )
            )
            db.session.commit()

        other_token = _login(client, other_name)
        resp = client.post(
            "/api/auth/delete-account",
            json={"password": _PASSWORD},
            headers=_auth(other_token),
        )
        assert resp.status_code == 200, resp.data
        with app.app_context():
            assert db.session.get(User, other_id) is None

        token = _login(client, seller_name)
        chats = client.get("/api/chats", headers=_auth(token))
        assert chats.status_code == 200, chats.data
        rows = chats.get_json()
        assert isinstance(rows, list)
        assert rows, "expected the surviving conversation to remain listed"
        assert rows[0]["other_user"] == {"id": None, "name": "Deleted User"}
        assert rows[0]["last_message"]["content"] == "from doomed"

    def test_emit_message_to_participants_handles_null_ids(self, app_ctx):
        app, _c, db = app_ctx
        from kk.chat_realtime import emit_message_to_participants
        from kk.models import Message

        a_id, _ap, _an = _make_user(app, db)
        b_id, _bp, _bn = _make_user(app, db)
        with app.app_context():
            msg = Message(sender_id=a_id, receiver_id=b_id, content="x")
            db.session.add(msg)
            db.session.commit()
            msg.sender_id = None
            msg.receiver_id = None
            db.session.commit()
            emit_message_to_participants(
                "message_updated", {"id": msg.public_id}, message=msg
            )

    def test_list_chats_collapses_multiple_messages_from_same_deleted_counterpart(
        self, app_ctx, client
    ):
        """A whole historical conversation with ONE deleted counterpart must
        still be ONE chat-list row (the regression this fix addresses),
        not one row per historical message.
        """
        app, _c, db = app_ctx
        from datetime import timedelta

        from kk.models import Message, User
        from kk.time_utils import utcnow

        seller_id, _sp, seller_name = _make_user(app, db)
        buyer_id, _bp, buyer_name = _make_user(app, db)
        car_id, _cp = _make_car(app, db, seller_id)
        t0 = utcnow()
        with app.app_context():
            db.session.add_all(
                [
                    Message(
                        sender_id=buyer_id,
                        receiver_id=seller_id,
                        car_id=car_id,
                        content="buyer-msg-1",
                        created_at=t0,
                    ),
                    Message(
                        sender_id=seller_id,
                        receiver_id=buyer_id,
                        car_id=car_id,
                        content="seller-reply-1",
                        created_at=t0 + timedelta(seconds=1),
                    ),
                    Message(
                        sender_id=buyer_id,
                        receiver_id=seller_id,
                        car_id=car_id,
                        content="buyer-msg-2-latest",
                        created_at=t0 + timedelta(seconds=2),
                    ),
                ]
            )
            db.session.commit()

        buyer_token = _login(client, buyer_name)
        resp = client.post(
            "/api/auth/delete-account",
            json={"password": _PASSWORD},
            headers=_auth(buyer_token),
        )
        assert resp.status_code == 200, resp.data
        with app.app_context():
            assert db.session.get(User, buyer_id) is None
            # Every message this buyer touched must carry the marker.
            marked = Message.query.filter_by(
                deleted_counterpart_marker=buyer_id
            ).count()
            assert marked == 3

        token = _login(client, seller_name)
        chats = client.get("/api/chats", headers=_auth(token))
        assert chats.status_code == 200, chats.data
        rows = [
            r for r in chats.get_json() if r["conversation_id"] == car_id
        ]
        assert len(rows) == 1, f"expected exactly one collapsed row, got {rows!r}"
        assert rows[0]["other_user"] == {"id": None, "name": "Deleted User"}
        assert rows[0]["last_message"]["content"] == "buyer-msg-2-latest"

    def test_list_chats_keeps_two_deleted_counterparts_on_same_car_separate(
        self, app_ctx, client
    ):
        """Two DIFFERENT deleted counterparts who each messaged about the
        SAME car must remain two separate chat-list rows — never merged
        just because both now resolve to a NULL counterpart.
        """
        app, _c, db = app_ctx
        from datetime import timedelta

        from kk.models import Message, User
        from kk.time_utils import utcnow

        seller_id, _sp, seller_name = _make_user(app, db)
        buyer1_id, _b1p, buyer1_name = _make_user(app, db)
        buyer2_id, _b2p, buyer2_name = _make_user(app, db)
        car_id, _cp = _make_car(app, db, seller_id)
        t0 = utcnow()
        with app.app_context():
            db.session.add_all(
                [
                    Message(
                        sender_id=buyer1_id,
                        receiver_id=seller_id,
                        car_id=car_id,
                        content="buyer1-first",
                        created_at=t0,
                    ),
                    Message(
                        sender_id=buyer2_id,
                        receiver_id=seller_id,
                        car_id=car_id,
                        content="buyer2-first",
                        created_at=t0 + timedelta(seconds=1),
                    ),
                    Message(
                        sender_id=buyer1_id,
                        receiver_id=seller_id,
                        car_id=car_id,
                        content="buyer1-latest",
                        created_at=t0 + timedelta(seconds=2),
                    ),
                    Message(
                        sender_id=buyer2_id,
                        receiver_id=seller_id,
                        car_id=car_id,
                        content="buyer2-latest",
                        created_at=t0 + timedelta(seconds=3),
                    ),
                ]
            )
            db.session.commit()

        for name in (buyer1_name, buyer2_name):
            tok = _login(client, name)
            resp = client.post(
                "/api/auth/delete-account",
                json={"password": _PASSWORD},
                headers=_auth(tok),
            )
            assert resp.status_code == 200, resp.data
        with app.app_context():
            assert db.session.get(User, buyer1_id) is None
            assert db.session.get(User, buyer2_id) is None

        token = _login(client, seller_name)
        chats = client.get("/api/chats", headers=_auth(token))
        assert chats.status_code == 200, chats.data
        rows = [
            r for r in chats.get_json() if r["conversation_id"] == car_id
        ]
        assert len(rows) == 2, f"expected two separate rows, got {rows!r}"
        contents = {r["last_message"]["content"] for r in rows}
        assert contents == {"buyer1-latest", "buyer2-latest"}
        for r in rows:
            assert r["other_user"] == {"id": None, "name": "Deleted User"}
