#!/usr/bin/env python3
"""
Factory-backed backend smoke tests (no server required).

Run (from repo root):
  python scripts/smoke_tests/test_backend_factory_smoke.py
"""

from __future__ import annotations

import io
import os
import sys
import tempfile
import unittest
import uuid
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))


class BackendFactorySmokeTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory(prefix="carlist_backend_smoke_")
        os.environ["APP_ENV"] = "testing"
        os.environ["SMS_PROVIDER"] = "console"
        os.environ["LISTING_REQUIRE_APPROVAL"] = "0"
        os.environ["DB_PATH"] = os.path.join(self._tmp.name, "t.db")

        from kk.app_factory import create_app

        self.app, self.socketio, *_ = create_app()
        self.client = self.app.test_client()

        from kk.admin_identity import ensure_detached_admin_account
        from kk.models import Car, User, db

        self._db = db
        self._User = User
        self._Car = Car

        with self.app.app_context():
            db.drop_all()
            db.create_all()

            seller = User(
                username="seller",
                phone_number="07000000001",
                first_name="S",
                last_name="L",
                email=None,
                is_active=True,
                is_verified=True,
                public_id="ps",
            )
            seller.set_password("Aa123456")

            viewer = User(
                username="viewer",
                phone_number="07000000002",
                first_name="V",
                last_name="W",
                email=None,
                is_active=True,
                is_verified=True,
                public_id="pv",
            )
            viewer.set_password("Aa123456")

            admin = User(
                username="admin",
                phone_number="07000000003",
                first_name="A",
                last_name="D",
                email="admin@test.example",
                is_active=True,
                is_admin=True,
                is_verified=True,
                public_id="pa",
            )
            admin.set_password("Aa123456")

            dealer = User(
                username="dealer",
                phone_number="07000000004",
                first_name="D",
                last_name="R",
                email="dealer@test.example",
                is_active=True,
                is_verified=True,
                account_type="dealer",
                dealer_status="approved",
                dealership_name="Dealer Test",
                dealership_phone="07000000004",
                dealership_phones=["07000000004"],
                dealership_verified_phones=["07000000004"],
                dealership_location="Erbil",
                public_id="pd",
            )
            dealer.set_password("Aa123456")

            db.session.add_all([seller, viewer, admin, dealer])
            db.session.commit()
            ensure_detached_admin_account(admin)
            db.session.commit()

            car = Car(
                seller_id=seller.id,
                brand="toyota",
                model="camry",
                year=2020,
                mileage=1,
                engine_type="gas",
                transmission="auto",
                drive_type="fwd",
                condition="used",
                body_type="sedan",
                price=10.0,
                location="Erbil",
                is_active=True,
            )
            db.session.add(car)
            db.session.commit()

            self.seller_public = seller.public_id
            self.viewer_public = viewer.public_id
            self.car_public = car.public_id
            self.car_id = car.id

        self.seller_token = self._login("seller", "Aa123456")
        self.viewer_token = self._login("viewer", "Aa123456")
        self.admin_app_token = self._login("admin", "Aa123456")
        self.admin_token = self._login("admin", "Aa123456", account_scope="admin")
        self.dealer_token = self._login("dealer", "Aa123456")

    def tearDown(self):
        try:
            with self.app.app_context():
                try:
                    self._db.session.remove()
                except Exception:
                    pass
                try:
                    self._db.engine.dispose()
                except Exception:
                    pass
        finally:
            self._tmp.cleanup()

    def _login(self, username: str, password: str, account_scope: str | None = None) -> str:
        payload = {"username": username, "password": password}
        if account_scope:
            payload["account_scope"] = account_scope
        r = self.client.post("/api/auth/login", json=payload)
        self.assertEqual(r.status_code, 200, r.data)
        data = r.get_json()
        self.assertIn("access_token", data)
        return data["access_token"]

    def _auth(self, token: str) -> dict[str, str]:
        return {"Authorization": f"Bearer {token}"}

    def test_dealer_phone_must_be_verified_before_profile_save(self):
        from unittest.mock import patch

        new_phone = "07500000005"
        rejected = self.client.put(
            "/api/user/dealer-profile",
            json={
                "dealership_phone": new_phone,
                "dealership_phones": [new_phone],
            },
            headers=self._auth(self.dealer_token),
        )
        self.assertEqual(rejected.status_code, 400, rejected.data)
        self.assertEqual(
            rejected.get_json().get("code"),
            "dealer_phone_verification_required",
        )

        captured = {}

        def capture_sms(phone, code):
            captured["phone"] = phone
            captured["code"] = code
            return True

        with patch("kk.sms_service.send_verification_sms", side_effect=capture_sms):
            sent = self.client.post(
                "/api/user/dealer-phone/send-verification",
                json={"phone_number": new_phone},
                headers=self._auth(self.dealer_token),
            )
        self.assertEqual(sent.status_code, 200, sent.data)
        self.assertEqual(captured["phone"], new_phone)

        invalid = self.client.post(
            "/api/user/dealer-phone/verify",
            json={"phone_number": new_phone, "verification_code": "000000"},
            headers=self._auth(self.dealer_token),
        )
        self.assertEqual(invalid.status_code, 400, invalid.data)

        verified = self.client.post(
            "/api/user/dealer-phone/verify",
            json={
                "phone_number": new_phone,
                "verification_code": captured["code"],
            },
            headers=self._auth(self.dealer_token),
        )
        self.assertEqual(verified.status_code, 200, verified.data)

        saved = self.client.put(
            "/api/user/dealer-profile",
            json={
                "dealership_phone": new_phone,
                "dealership_phones": [new_phone],
            },
            headers=self._auth(self.dealer_token),
        )
        self.assertEqual(saved.status_code, 200, saved.data)
        self.assertEqual(
            saved.get_json()["user"]["dealership_verified_phones"],
            [new_phone],
        )

    def test_non_dealer_cannot_verify_dealership_phone(self):
        response = self.client.post(
            "/api/user/dealer-phone/send-verification",
            json={"phone_number": "07500000006"},
            headers=self._auth(self.viewer_token),
        )
        self.assertEqual(response.status_code, 403, response.data)

    def test_expired_dealer_phone_code_is_rejected(self):
        from datetime import timedelta

        with self.app.app_context():
            from kk.routes.user import _hash_dealer_phone_code
            from kk.time_utils import utcnow

            dealer = self._User.query.filter_by(username="dealer").first()
            dealer.phone_verification_code_hash = _hash_dealer_phone_code(
                "07500000007",
                "123456",
            )
            dealer.phone_verification_expires_at = utcnow() - timedelta(seconds=1)
            dealer.phone_verification_attempts = 0
            self._db.session.commit()

        response = self.client.post(
            "/api/user/dealer-phone/verify",
            json={
                "phone_number": "07500000007",
                "verification_code": "123456",
            },
            headers=self._auth(self.dealer_token),
        )
        self.assertEqual(response.status_code, 400, response.data)
        self.assertIn("expired", response.get_json()["message"].lower())

    def test_analytics_track_and_list(self):
        from kk.listing_metrics import clear_engagement_claims_for_tests
        from kk.models import ListingAnalytics

        clear_engagement_claims_for_tests()

        r = self.client.post(
            "/api/analytics/track/view",
            json={"listing_id": self.car_public},
            headers=self._auth(self.viewer_token),
        )
        self.assertEqual(r.status_code, 200, r.data)
        body = r.get_json() or {}
        self.assertTrue(body.get("success"))
        self.assertTrue(body.get("counted"), body)

        # Second view by same user must not increment again.
        r_dup = self.client.post(
            "/api/analytics/track/view",
            json={"listing_id": self.car_public},
            headers=self._auth(self.viewer_token),
        )
        self.assertEqual(r_dup.status_code, 200, r_dup.data)
        self.assertFalse((r_dup.get_json() or {}).get("counted"))

        # Client track/message is a no-op (counted on real chat send).
        r_msg = self.client.post(
            "/api/analytics/track/message",
            json={"listing_id": self.car_public},
            headers=self._auth(self.viewer_token),
        )
        self.assertEqual(r_msg.status_code, 200, r_msg.data)
        self.assertFalse((r_msg.get_json() or {}).get("counted"))

        with self.app.app_context():
            a = ListingAnalytics.query.filter_by(car_id=self.car_id).first()
            self.assertIsNotNone(a)
            self.assertEqual(int(a.views or 0), 1)
            self.assertEqual(int(a.messages or 0), 0)

        # Real chat send bumps messages.
        send = self.client.post(
            f"/api/chat/{self.car_id}/send",
            json={"content": "analytics inquiry"},
            headers=self._auth(self.viewer_token),
        )
        self.assertEqual(send.status_code, 201, send.data)

        with self.app.app_context():
            a = ListingAnalytics.query.filter_by(car_id=self.car_id).first()
            self.assertEqual(int(a.messages or 0), 1)

        # Call dedupe: first counts, second same day does not.
        c1 = self.client.post(
            "/api/analytics/track/call",
            json={"listing_id": self.car_public},
            headers=self._auth(self.viewer_token),
        )
        self.assertEqual(c1.status_code, 200, c1.data)
        self.assertTrue((c1.get_json() or {}).get("counted"))
        c2 = self.client.post(
            "/api/analytics/track/call",
            json={"listing_id": self.car_public},
            headers=self._auth(self.viewer_token),
        )
        self.assertEqual(c2.status_code, 200, c2.data)
        self.assertFalse((c2.get_json() or {}).get("counted"))

        r2 = self.client.get("/api/analytics/listings", headers=self._auth(self.seller_token))
        self.assertEqual(r2.status_code, 200, r2.data)
        self.assertIsInstance(r2.get_json(), list)

    def test_analytics_favorite_bound_to_toggle(self):
        from kk.models import ListingAnalytics

        hint = self.client.post(
            "/api/analytics/track/favorite",
            json={"listing_id": self.car_public},
            headers=self._auth(self.viewer_token),
        )
        self.assertEqual(hint.status_code, 200, hint.data)
        self.assertFalse((hint.get_json() or {}).get("counted"))

        with self.app.app_context():
            before = ListingAnalytics.query.filter_by(car_id=self.car_id).first()
            fav_before = int(before.favorites or 0) if before else 0

        fav = self.client.post(
            f"/api/cars/{self.car_public}/favorite",
            headers=self._auth(self.viewer_token),
        )
        self.assertEqual(fav.status_code, 200, fav.data)
        self.assertTrue((fav.get_json() or {}).get("is_favorited"))

        with self.app.app_context():
            a = ListingAnalytics.query.filter_by(car_id=self.car_id).first()
            self.assertIsNotNone(a)
            self.assertEqual(int(a.favorites or 0), fav_before + 1)

    def test_chat_send_and_unread(self):
        r = self.client.post(
            f"/api/chat/{self.car_id}/send",
            json={"content": "hi"},
            headers=self._auth(self.viewer_token),
        )
        self.assertEqual(r.status_code, 201, r.data)

        u = self.client.get("/api/chat/unread_count", headers=self._auth(self.seller_token))
        self.assertEqual(u.status_code, 200, u.data)
        self.assertGreaterEqual(u.get_json().get("unread_count", 0), 1)

        m = self.client.get(f"/api/chat/{self.car_id}/messages", headers=self._auth(self.seller_token))
        self.assertEqual(m.status_code, 200, m.data)
        self.assertGreaterEqual(len(m.get_json() or []), 1)

    def test_chats_list_after_message(self):
        send = self.client.post(
            f"/api/chat/{self.car_id}/send",
            json={"content": "list me"},
            headers=self._auth(self.viewer_token),
        )
        self.assertEqual(send.status_code, 201, send.data)

        seller_chats = self.client.get("/api/chats", headers=self._auth(self.seller_token))
        self.assertEqual(seller_chats.status_code, 200, seller_chats.data)
        rows = seller_chats.get_json()
        self.assertIsInstance(rows, list)
        self.assertGreaterEqual(len(rows), 1)
        first = rows[0]
        self.assertIn("conversation_id", first)
        self.assertIn("car_id", first)
        self.assertIn("last_message", first)
        self.assertEqual(first.get("car_id"), self.car_public)

        viewer_chats = self.client.get("/api/chats", headers=self._auth(self.viewer_token))
        self.assertEqual(viewer_chats.status_code, 200, viewer_chats.data)
        self.assertGreaterEqual(len(viewer_chats.get_json() or []), 1)

        anon = self.client.get("/api/chats")
        self.assertEqual(anon.status_code, 401, anon.data)

    def test_upload_and_process_images(self):
        # minimal jpeg bytes (not necessarily decodable); pipeline must not crash
        jpeg = b"\xff\xd8\xff\xdb" + b"0" * 100 + b"\xff\xd9"

        up = self.client.post(
            f"/api/cars/{self.car_public}/images?skip_blur=1",
            headers=self._auth(self.seller_token),
            data={"images": (io.BytesIO(jpeg), "t.jpg")},
            content_type="multipart/form-data",
        )
        self.assertEqual(up.status_code, 201, up.data)

        proc = self.client.post(
            "/api/process-car-images",
            headers=self._auth(self.seller_token),
            data={"images": (io.BytesIO(jpeg), "t.jpg")},
            content_type="multipart/form-data",
        )
        self.assertEqual(proc.status_code, 200, proc.data)

    def test_phone_otp_start_and_verify(self):
        phone = "07000001000"
        start = self.client.post(
            "/api/auth/phone/start",
            json={
                "phone_number": phone,
                "username": f"p_{uuid.uuid4().hex[:8]}",
                "first_name": "P",
                "last_name": "O",
            },
        )
        self.assertEqual(start.status_code, 200, start.data)
        payload = start.get_json() or {}
        self.assertIn("dev_code", payload, payload)
        code = str(payload["dev_code"])
        self.assertEqual(len(code), 6)

        verify = self.client.post(
            "/api/auth/phone/verify",
            json={"phone_number": phone, "code": code},
        )
        self.assertEqual(verify.status_code, 200, verify.data)
        data = verify.get_json() or {}
        self.assertIn("access_token", data)
        self.assertIn("refresh_token", data)
        self.assertIn("user", data)

    def test_phone_otp_login_rejects_unknown_number(self):
        phone = "07000009999"
        start = self.client.post(
            "/api/auth/phone/start",
            json={"phone_number": phone, "create_if_missing": False},
        )
        self.assertEqual(start.status_code, 404, start.data)
        payload = start.get_json() or {}
        self.assertEqual(payload.get("code"), "account_not_found")

    def test_admin_endpoints_require_admin(self):
        dash = self.client.get("/api/admin/dashboard", headers=self._auth(self.viewer_token))
        self.assertEqual(dash.status_code, 403, dash.data)

        dash_ok = self.client.get("/api/admin/dashboard", headers=self._auth(self.admin_token))
        self.assertEqual(dash_ok.status_code, 200, dash_ok.data)
        self.assertIn("stats", dash_ok.get_json() or {})

        pending = self.client.get(
            "/api/admin/dealers/pending",
            headers=self._auth(self.admin_token),
        )
        self.assertEqual(pending.status_code, 200, pending.data)
        self.assertIn("dealers", pending.get_json() or {})

        reports = self.client.get(
            "/api/admin/reports?status=pending&type=all",
            headers=self._auth(self.admin_token),
        )
        self.assertEqual(reports.status_code, 200, reports.data)
        body = reports.get_json() or {}
        self.assertIn("reports", body)

    def test_admin_dealer_approve_and_reject(self):
        from unittest.mock import patch

        with self.app.app_context():
            from kk.models import DealerApplication

            pending_approve = self._User(
                username="dealer_pending_ok",
                phone_number="07000000091",
                first_name="P",
                last_name="A",
                email="pending_ok@test.example",
                is_active=True,
                is_verified=True,
                account_type="user",
                dealer_status="pending",
                dealership_name="Approve Motors",
                dealership_location="Erbil",
                firebase_token="test-fcm-token",
                public_id="pd_appr",
            )
            pending_approve.set_password("Aa123456")

            pending_reject = self._User(
                username="dealer_pending_no",
                phone_number="07000000092",
                first_name="P",
                last_name="R",
                email="pending_no@test.example",
                is_active=True,
                is_verified=True,
                account_type="user",
                dealer_status="pending",
                dealership_name="Reject Motors",
                dealership_location="Baghdad",
                public_id="pd_rej",
            )
            pending_reject.set_password("Aa123456")
            self._db.session.add_all([pending_approve, pending_reject])
            self._db.session.flush()
            self._db.session.add_all(
                [
                    DealerApplication(
                        user=pending_approve,
                        status="submitted",
                        dealership_name="Approve Motors",
                        dealership_phone="07000000091",
                        dealership_location="Erbil",
                        verification_photo_filename="approve.jpg",
                    ),
                    DealerApplication(
                        user=pending_reject,
                        status="submitted",
                        dealership_name="Reject Motors",
                        dealership_phone="07000000092",
                        dealership_location="Baghdad",
                        verification_photo_filename="reject.jpg",
                    ),
                ]
            )
            self._db.session.commit()
            approve_id = pending_approve.public_id
            reject_id = pending_reject.public_id
        approve_token = self._login("dealer_pending_ok", "Aa123456")

        pending = self.client.get(
            "/api/admin/dealers/pending",
            headers=self._auth(self.admin_token),
        )
        self.assertEqual(pending.status_code, 200, pending.data)
        rows = (pending.get_json() or {}).get("dealers") or []
        public_ids = {row.get("id") for row in rows}
        self.assertIn(approve_id, public_ids)
        self.assertIn(reject_id, public_ids)

        with patch("kk.routes.admin.send_push", return_value=True) as push_mock:
            approved = self.client.post(
                f"/api/admin/dealers/{approve_id}/approve",
                headers=self._auth(self.admin_token),
            )
        push_mock.assert_called_once()
        push_payload = push_mock.call_args.kwargs
        self.assertEqual(push_payload["data"]["type"], "dealer_application")
        self.assertEqual(push_payload["data"]["status"], "approved")
        self.assertEqual(approved.status_code, 200, approved.data)
        approved_body = approved.get_json() or {}
        self.assertEqual(
            (approved_body.get("user") or {}).get("dealer_status"),
            "approved",
        )
        notifications = self.client.get(
            "/api/user/notifications?unread_only=true&type=dealer_application",
            headers=self._auth(approve_token),
        )
        self.assertEqual(notifications.status_code, 200, notifications.data)
        approval_rows = (notifications.get_json() or {}).get("notifications") or []
        self.assertEqual(len(approval_rows), 1)
        self.assertEqual(
            (approval_rows[0].get("data") or {}).get("status"),
            "approved",
        )
        notification_id = approval_rows[0]["id"]
        forbidden_read = self.client.patch(
            f"/api/user/notifications/{notification_id}/read",
            headers=self._auth(self.viewer_token),
        )
        self.assertEqual(forbidden_read.status_code, 404, forbidden_read.data)
        marked_read = self.client.patch(
            f"/api/user/notifications/{notification_id}/read",
            headers=self._auth(approve_token),
        )
        self.assertEqual(marked_read.status_code, 200, marked_read.data)

        rejected = self.client.post(
            f"/api/admin/dealers/{reject_id}/reject",
            headers=self._auth(self.admin_token),
            json={"reason": "Incomplete paperwork"},
        )
        self.assertEqual(rejected.status_code, 200, rejected.data)
        rejected_body = rejected.get_json() or {}
        self.assertEqual(
            (rejected_body.get("user") or {}).get("dealer_status"),
            "rejected",
        )

    def test_public_dealers_list(self):
        r = self.client.get("/api/dealers?page=1&per_page=5")
        self.assertEqual(r.status_code, 200, r.data)
        body = r.get_json() or {}
        self.assertIn("dealers", body)
        self.assertIn("pagination", body)

    def test_get_dealer_by_public_id(self):
        with self.app.app_context():
            dealer = self._User(
                username="dealer1",
                phone_number="07000000088",
                first_name="D",
                last_name="1",
                email="dealer@test.example",
                is_active=True,
                is_verified=True,
                account_type="dealer",
                dealership_name="Smoke Test Dealer",
                dealership_location="Erbil",
                public_id="pd_smoke_dealer",
            )
            dealer.set_password("Aa123456")
            self._db.session.add(dealer)
            self._db.session.commit()
            dealer_public = dealer.public_id

        r = self.client.get(f"/api/dealers/{dealer_public}")
        self.assertEqual(r.status_code, 200, r.data)
        body = r.get_json() or {}
        self.assertEqual(
            (body.get("dealer") or {}).get("dealership_name"),
            "Smoke Test Dealer",
        )
        self.assertIn("listings", body)
        self.assertIn("stats", body)

    def test_verify_email_with_token(self):
        with self.app.app_context():
            from kk.auth import create_email_verification_token

            user = self._User(
                username="emailverify",
                phone_number="07000000099",
                first_name="E",
                last_name="V",
                email="verify@test.example",
                is_active=True,
                is_verified=False,
                public_id="pv_email_verify",
            )
            user.set_password("Aa123456")
            self._db.session.add(user)
            self._db.session.commit()
            token = create_email_verification_token(user)

        missing = self.client.post("/api/auth/verify-email", json={})
        self.assertEqual(missing.status_code, 400, missing.data)

        r = self.client.post("/api/auth/verify-email", json={"token": token})
        self.assertEqual(r.status_code, 200, r.data)

        with self.app.app_context():
            user = self._User.query.filter_by(email="verify@test.example").first()
            self.assertIsNotNone(user)
            self.assertTrue(user.is_verified)

    def test_change_password(self):
        r = self.client.post(
            "/api/auth/change-password",
            headers=self._auth(self.viewer_token),
            json={"current_password": "Aa123456", "new_password": "Cc123456!"},
        )
        self.assertEqual(r.status_code, 200, r.data)

        login = self.client.post(
            "/api/auth/login",
            json={"username": "viewer", "password": "Cc123456!"},
        )
        self.assertEqual(login.status_code, 200, login.data)

    def test_update_profile_first_name(self):
        r = self.client.put(
            "/api/user/profile",
            headers=self._auth(self.viewer_token),
            json={"first_name": "UpdatedName"},
        )
        self.assertEqual(r.status_code, 200, r.data)

        me = self.client.get("/api/auth/me", headers=self._auth(self.viewer_token))
        self.assertEqual(me.status_code, 200, me.data)
        self.assertEqual((me.get_json() or {}).get("first_name"), "UpdatedName")

    def test_register_confirm_creates_user(self):
        with self.app.app_context():
            from datetime import timedelta

            from kk.models import PendingSignup
            from kk.time_utils import utcnow

            token = f"confirm_{uuid.uuid4().hex}"
            temp = self._User(
                username="tmp_hash",
                phone_number="07000000111",
                first_name="T",
                last_name="H",
                email=None,
                is_active=True,
                is_verified=True,
                public_id="ph",
            )
            temp.set_password("Aa123456!")
            pending = PendingSignup(
                email="confirm@test.example",
                username=f"confirm_{uuid.uuid4().hex[:8]}",
                password_hash=temp.password_hash,
                first_name="C",
                last_name="U",
                phone_number="07000000112",
                token=token,
                expires_at=utcnow() + timedelta(days=1),
            )
            self._db.session.add(pending)
            self._db.session.commit()

        missing = self.client.post("/api/auth/register-confirm", json={})
        self.assertEqual(missing.status_code, 400, missing.data)

        r = self.client.post("/api/auth/register-confirm", json={"token": token})
        self.assertIn(r.status_code, (200, 201), r.data)
        body = r.get_json() or {}
        self.assertIn("access_token", body)

        with self.app.app_context():
            user = self._User.query.filter_by(email="confirm@test.example").first()
            self.assertIsNotNone(user)
            self.assertTrue(user.is_verified)

    def test_report_user_listing_and_block_flow(self):
        user_report = self.client.post(
            f"/api/users/{self.seller_public}/report",
            headers=self._auth(self.viewer_token),
            json={"reason": "Spam", "details": "Smoke test report"},
        )
        self.assertEqual(user_report.status_code, 201, user_report.data)

        listing_report = self.client.post(
            f"/api/cars/{self.car_public}/report",
            headers=self._auth(self.viewer_token),
            json={"reason": "Misleading listing"},
        )
        self.assertEqual(listing_report.status_code, 201, listing_report.data)

        pending = self.client.get(
            "/api/admin/reports?status=pending&type=all",
            headers=self._auth(self.admin_token),
        )
        self.assertEqual(pending.status_code, 200, pending.data)
        rows = (pending.get_json() or {}).get("reports") or []
        self.assertGreaterEqual(len(rows), 2)

        block = self.client.post(
            f"/api/users/{self.seller_public}/block",
            headers=self._auth(self.viewer_token),
        )
        self.assertIn(block.status_code, (200, 201), block.data)

        blocked = self.client.get(
            "/api/users/blocked",
            headers=self._auth(self.viewer_token),
        )
        self.assertEqual(blocked.status_code, 200, blocked.data)
        blocked_ids = (blocked.get_json() or {}).get("blocked_users") or []
        self.assertIn(self.seller_public, blocked_ids)

        unblock = self.client.post(
            f"/api/users/{self.seller_public}/unblock",
            headers=self._auth(self.viewer_token),
        )
        self.assertEqual(unblock.status_code, 200, unblock.data)

    def test_health_and_push_status(self):
        r = self.client.get("/health")
        self.assertEqual(r.status_code, 200)
        body = r.get_json()
        self.assertEqual(body.get("status"), "ok")
        push = self.client.get("/health/push")
        self.assertEqual(push.status_code, 200)
        self.assertIn("credentials_present", push.get_json())

    def test_well_known_app_links_require_env(self):
        """Without store env vars, deep-link files must 404 (not serve invalid stubs)."""
        for path in (
            "/.well-known/assetlinks.json",
            "/.well-known/apple-app-site-association",
        ):
            r = self.client.get(path)
            self.assertEqual(r.status_code, 404, (path, r.data))

    def test_assetlinks_served_when_sha_env_set(self):
        """Render ANDROID_SHA256_CERT_FINGERPRINTS enables assetlinks.json."""
        fp = "9E:7A:AC:CF:0B:CE:7E:A3:0E:B9:9D:AF:DF:37:8E:1D:3E:6C:F6:C5:E8:C8:22:41:1E:53:F5:A5:72:40:97:E8"
        # Lowercase + spaces should normalize to uppercase colon form.
        messy = " 9e:7a:ac:cf:0b:ce:7e:a3:0e:b9:9d:af:df:37:8e:1d:3e:6c:f6:c5:e8:c8:22:41:1e:53:f5:a5:72:40:97:e8 "
        prev = os.environ.get("ANDROID_SHA256_CERT_FINGERPRINTS")
        os.environ["ANDROID_SHA256_CERT_FINGERPRINTS"] = messy
        try:
            r = self.client.get("/.well-known/assetlinks.json")
            self.assertEqual(r.status_code, 200, r.data)
            body = r.get_json()
            self.assertIsInstance(body, list)
            self.assertGreaterEqual(len(body), 1)
            target = (body[0] or {}).get("target") or {}
            self.assertEqual(target.get("package_name"), "com.carzo.app")
            self.assertIn(fp, target.get("sha256_cert_fingerprints") or [])
        finally:
            if prev is None:
                os.environ.pop("ANDROID_SHA256_CERT_FINGERPRINTS", None)
            else:
                os.environ["ANDROID_SHA256_CERT_FINGERPRINTS"] = prev

    def test_trust_config_and_legal_pages(self):
        trust = self.client.get("/api/config/trust")
        self.assertEqual(trust.status_code, 200, trust.data)
        payload = trust.get_json() or {}
        self.assertEqual(payload.get("support_email"), "support@carzo.app")
        self.assertTrue((payload.get("privacy_url") or "").strip())
        self.assertTrue((payload.get("terms_url") or "").strip())

        app_cfg = self.client.get("/api/config/app")
        self.assertEqual(app_cfg.status_code, 200, app_cfg.data)
        app_body = app_cfg.get_json() or {}
        self.assertIn("min_app_version", app_body)
        self.assertIn("android_store_url", app_body)
        self.assertIn("listing_require_approval", app_body)
        self.assertFalse(app_body.get("listing_require_approval"))

        terms = self.client.get("/terms")
        self.assertEqual(terms.status_code, 200, terms.data)
        self.assertIn(b"CarNet", terms.data)

        privacy = self.client.get("/privacy")
        self.assertEqual(privacy.status_code, 200, privacy.data)
        self.assertIn(b"CarNet", privacy.data)

    def test_delete_account_requires_password(self):
        missing = self.client.delete(
            "/api/auth/delete-account",
            headers=self._auth(self.viewer_token),
            json={},
        )
        self.assertEqual(missing.status_code, 400, missing.data)

    def test_delete_account(self):
        r = self.client.delete(
            "/api/auth/delete-account",
            headers=self._auth(self.viewer_token),
            json={"password": "Aa123456"},
        )
        self.assertEqual(r.status_code, 200, r.data)
        body = r.get_json() or {}
        self.assertIn("message", body)

        me = self.client.get("/api/auth/me", headers=self._auth(self.viewer_token))
        self.assertIn(me.status_code, (401, 404, 422))

    def test_deleting_mobile_account_preserves_dashboard_admin(self):
        deleted = self.client.delete(
            "/api/auth/delete-account",
            headers=self._auth(self.admin_app_token),
            json={"password": "Aa123456"},
        )
        self.assertEqual(deleted.status_code, 200, deleted.data)

        mobile_me = self.client.get(
            "/api/auth/me",
            headers=self._auth(self.admin_app_token),
        )
        self.assertIn(mobile_me.status_code, (401, 404, 422))

        dashboard_token = self._login(
            "admin",
            "Aa123456",
            account_scope="admin",
        )
        dashboard = self.client.get(
            "/api/admin/dashboard",
            headers=self._auth(dashboard_token),
        )
        self.assertEqual(dashboard.status_code, 200, dashboard.data)

        protected = self.client.delete(
            "/api/auth/delete-account",
            headers=self._auth(dashboard_token),
            json={"password": "Aa123456"},
        )
        self.assertEqual(protected.status_code, 403, protected.data)

    def test_create_car_requires_phone_verification(self):
        with self.app.app_context():
            unverified = self._User(
                username="unverified",
                phone_number="07000000099",
                first_name="U",
                last_name="V",
                email=None,
                is_active=True,
                is_verified=False,
                public_id="puv",
            )
            unverified.set_password("Aa123456")
            self._db.session.add(unverified)
            self._db.session.commit()

        token = self._login("unverified", "Aa123456")
        r = self.client.post(
            "/api/cars",
            headers=self._auth(token),
            json={
                "brand": "toyota",
                "model": "camry",
                "year": 2020,
                "mileage": 1000,
                "price": 15000,
                "location": "Erbil",
            },
        )
        self.assertEqual(r.status_code, 403, r.data)
        body = r.get_json() or {}
        self.assertEqual(body.get("code"), "phone_verification_required")

    def test_chat_send_requires_phone_verification(self):
        with self.app.app_context():
            unverified = self._User(
                username="unverified_chat",
                phone_number="07000000098",
                first_name="U",
                last_name="C",
                email=None,
                is_active=True,
                is_verified=False,
                public_id="puvc",
            )
            unverified.set_password("Aa123456")
            self._db.session.add(unverified)
            self._db.session.commit()

        token = self._login("unverified_chat", "Aa123456")
        r = self.client.post(
            f"/api/chat/{self.car_id}/send",
            headers=self._auth(token),
            json={"content": "hello"},
        )
        self.assertEqual(r.status_code, 403, r.data)
        body = r.get_json() or {}
        self.assertEqual(body.get("code"), "phone_verification_required")

    def test_socket_send_requires_phone_verification(self):
        with self.app.app_context():
            unverified = self._User(
                username="unverified_socket",
                phone_number="07000000097",
                first_name="U",
                last_name="S",
                email=None,
                is_active=True,
                is_verified=False,
                public_id="pusv",
            )
            unverified.set_password("Aa123456")
            self._db.session.add(unverified)
            self._db.session.commit()

        token = self._login("unverified_socket", "Aa123456")
        client = self.socketio.test_client(
            self.app,
            flask_test_client=self.client,
            query_string=f"token={token}",
        )
        self.assertTrue(client.is_connected(), client.get_received())
        client.get_received()  # drain connect event
        client.emit(
            "send_message",
            {
                "car_id": self.car_public,
                "content": "hello via socket",
                "receiver_id": self.seller_public,
            },
        )
        received = client.get_received()
        errors = [evt for evt in received if evt.get("name") == "error"]
        self.assertTrue(errors, received)
        payload = errors[-1]["args"][0]
        self.assertEqual(payload.get("code"), "phone_verification_required")
        client.disconnect()

    def test_upload_images_requires_phone_verification(self):
        with self.app.app_context():
            unverified = self._User(
                username="unverified_upload",
                phone_number="07000000096",
                first_name="U",
                last_name="U",
                email=None,
                is_active=True,
                is_verified=False,
                public_id="puvu",
            )
            unverified.set_password("Aa123456")
            self._db.session.add(unverified)
            self._db.session.commit()

        token = self._login("unverified_upload", "Aa123456")
        jpeg = b"\xff\xd8\xff\xdb" + b"0" * 100 + b"\xff\xd9"
        r = self.client.post(
            f"/api/cars/{self.car_public}/images?skip_blur=1",
            headers=self._auth(token),
            data={"images": (io.BytesIO(jpeg), "t.jpg")},
            content_type="multipart/form-data",
        )
        self.assertEqual(r.status_code, 403, r.data)
        body = r.get_json() or {}
        self.assertEqual(body.get("code"), "phone_verification_required")

    def test_process_car_images_requires_phone_verification(self):
        with self.app.app_context():
            unverified = self._User(
                username="unverified_ai",
                phone_number="07000000095",
                first_name="U",
                last_name="A",
                email=None,
                is_active=True,
                is_verified=False,
                public_id="puva",
            )
            unverified.set_password("Aa123456")
            self._db.session.add(unverified)
            self._db.session.commit()

        token = self._login("unverified_ai", "Aa123456")
        jpeg = b"\xff\xd8\xff\xdb" + b"0" * 100 + b"\xff\xd9"
        r = self.client.post(
            "/api/process-car-images",
            headers=self._auth(token),
            data={"images": (io.BytesIO(jpeg), "t.jpg")},
            content_type="multipart/form-data",
        )
        self.assertEqual(r.status_code, 403, r.data)
        body = r.get_json() or {}
        self.assertEqual(body.get("code"), "phone_verification_required")

    def test_r2_sign_upload_requires_phone_verification(self):
        with self.app.app_context():
            unverified = self._User(
                username="unverified_r2",
                phone_number="07000000094",
                first_name="U",
                last_name="R",
                email=None,
                is_active=True,
                is_verified=False,
                public_id="puvr",
            )
            unverified.set_password("Aa123456")
            self._db.session.add(unverified)
            self._db.session.commit()

        token = self._login("unverified_r2", "Aa123456")
        r = self.client.post(
            "/api/media/r2/sign-upload",
            headers=self._auth(token),
            json={"filename": "photo.jpg", "content_type": "image/jpeg"},
        )
        self.assertEqual(r.status_code, 403, r.data)
        body = r.get_json() or {}
        self.assertEqual(body.get("code"), "phone_verification_required")

    def test_email_signup_and_login(self):
        u = f"e_{uuid.uuid4().hex[:8]}"
        signup = self.client.post(
            "/api/auth/signup",
            json={
                "username": u,
                "email": f"{u}@example.com",
                "phone": "07000002000",
                "password": "Aa123456!",
                "first_name": "E",
                "last_name": "S",
            },
        )
        self.assertEqual(signup.status_code, 201, signup.data)
        body = signup.get_json() or {}
        self.assertIn("access_token", body)

        login = self.client.post("/api/auth/login", json={"username": u, "password": "Aa123456!"})
        self.assertEqual(login.status_code, 200, login.data)
        self.assertIn("access_token", login.get_json() or {})

    def test_auth_me_returns_bare_user(self):
        me = self.client.get("/api/auth/me", headers=self._auth(self.viewer_token))
        self.assertEqual(me.status_code, 200, me.data)
        body = me.get_json() or {}
        self.assertIn("username", body)
        self.assertIn("id", body)

    def test_auth_refresh_rotates_tokens(self):
        login = self.client.post(
            "/api/auth/login",
            json={"username": "viewer", "password": "Aa123456"},
        )
        self.assertEqual(login.status_code, 200, login.data)
        refresh_token = (login.get_json() or {}).get("refresh_token")
        self.assertTrue(refresh_token)

        refreshed = self.client.post(
            "/api/auth/refresh",
            headers={"Authorization": f"Bearer {refresh_token}"},
        )
        self.assertEqual(refreshed.status_code, 200, refreshed.data)
        body = refreshed.get_json() or {}
        self.assertIn("access_token", body)
        self.assertIn("refresh_token", body)

        me = self.client.get(
            "/api/auth/me",
            headers=self._auth(body["access_token"]),
        )
        self.assertEqual(me.status_code, 200, me.data)

    def test_access_token_ttl_is_short(self):
        """H-03: access JWTs expire in 15–60 minutes (default 30)."""
        import base64
        import json
        from datetime import timedelta

        from kk.config import _access_token_expires

        # Default / clamped helper.
        self.assertEqual(_access_token_expires(), timedelta(minutes=30))
        previous = os.environ.get("JWT_ACCESS_TOKEN_MINUTES")
        try:
            os.environ["JWT_ACCESS_TOKEN_MINUTES"] = "15"
            self.assertEqual(_access_token_expires(), timedelta(minutes=15))
            os.environ["JWT_ACCESS_TOKEN_MINUTES"] = "120"
            self.assertEqual(_access_token_expires(), timedelta(minutes=60))
            os.environ["JWT_ACCESS_TOKEN_MINUTES"] = "5"
            self.assertEqual(_access_token_expires(), timedelta(minutes=15))
        finally:
            if previous is None:
                os.environ.pop("JWT_ACCESS_TOKEN_MINUTES", None)
            else:
                os.environ["JWT_ACCESS_TOKEN_MINUTES"] = previous

        login = self.client.post(
            "/api/auth/login",
            json={"username": "viewer", "password": "Aa123456"},
        )
        self.assertEqual(login.status_code, 200, login.data)
        access = (login.get_json() or {}).get("access_token") or ""
        self.assertTrue(access)
        payload_b64 = access.split(".")[1]
        pad = "=" * ((4 - len(payload_b64) % 4) % 4)
        payload = json.loads(base64.urlsafe_b64decode(payload_b64 + pad))
        lifetime = int(payload["exp"]) - int(payload["iat"])
        self.assertGreaterEqual(lifetime, 15 * 60)
        self.assertLessEqual(lifetime, 60 * 60)

    def test_auth_logout(self):
        logout = self.client.post(
            "/api/auth/logout",
            headers=self._auth(self.viewer_token),
        )
        self.assertEqual(logout.status_code, 200, logout.data)
        body = logout.get_json() or {}
        self.assertIn("message", body)

    def test_my_listings_compat_returns_array(self):
        r = self.client.get("/api/my_listings", headers=self._auth(self.seller_token))
        self.assertEqual(r.status_code, 200, r.data)
        body = r.get_json()
        self.assertIsInstance(body, list)
        self.assertGreaterEqual(len(body), 1)

    def test_get_car_by_public_id(self):
        r = self.client.get(f"/api/cars/{self.car_public}")
        self.assertEqual(r.status_code, 200, r.data)
        body = r.get_json() or {}
        self.assertIn("car", body)
        self.assertEqual((body.get("car") or {}).get("brand"), "toyota")

    def test_create_car_as_verified_seller(self):
        r = self.client.post(
            "/api/cars",
            headers=self._auth(self.seller_token),
            json={
                "brand": "honda",
                "model": "civic",
                "year": 2019,
                "mileage": 5000,
                "price": 14000,
                "location": "Erbil",
            },
        )
        self.assertEqual(r.status_code, 201, r.data)
        body = r.get_json() or {}
        self.assertIn("car", body)
        self.assertEqual((body.get("car") or {}).get("brand"), "honda")

    def test_mark_listing_sold_and_active(self):
        sold = self.client.post(
            f"/api/cars/{self.car_public}/mark-sold",
            headers=self._auth(self.seller_token),
        )
        self.assertEqual(sold.status_code, 200, sold.data)
        sold_body = sold.get_json() or {}
        self.assertEqual((sold_body.get("car") or {}).get("status"), "sold")

        active = self.client.post(
            f"/api/cars/{self.car_public}/mark-active",
            headers=self._auth(self.seller_token),
        )
        self.assertEqual(active.status_code, 200, active.data)
        active_body = active.get_json() or {}
        self.assertEqual((active_body.get("car") or {}).get("status"), "active")

    def test_user_my_listings_paginated(self):
        r = self.client.get(
            "/api/user/my-listings?page=1&per_page=10",
            headers=self._auth(self.seller_token),
        )
        self.assertEqual(r.status_code, 200, r.data)
        body = r.get_json() or {}
        self.assertIn("cars", body)
        self.assertIn("pagination", body)
        self.assertGreaterEqual(len(body.get("cars") or []), 1)

    def test_user_my_listings_filters_by_status(self):
        sold = self.client.post(
            f"/api/cars/{self.car_public}/mark-sold",
            headers=self._auth(self.seller_token),
        )
        self.assertEqual(sold.status_code, 200, sold.data)

        sold_listings = self.client.get(
            "/api/user/my-listings?status=sold",
            headers=self._auth(self.seller_token),
        )
        self.assertEqual(sold_listings.status_code, 200, sold_listings.data)
        sold_cars = (sold_listings.get_json() or {}).get("cars") or []
        self.assertIn(self.car_public, {car.get("id") for car in sold_cars})
        self.assertTrue(all(car.get("status") == "sold" for car in sold_cars))

        active_listings = self.client.get(
            "/api/user/my-listings?status=active",
            headers=self._auth(self.seller_token),
        )
        self.assertEqual(active_listings.status_code, 200, active_listings.data)
        active_cars = (active_listings.get_json() or {}).get("cars") or []
        self.assertNotIn(self.car_public, {car.get("id") for car in active_cars})
        self.assertTrue(all(car.get("status") == "active" for car in active_cars))

    def test_socket_send_success_for_verified_user(self):
        client = self.socketio.test_client(
            self.app,
            flask_test_client=self.client,
            query_string=f"token={self.viewer_token}",
        )
        self.assertTrue(client.is_connected(), client.get_received())
        client.get_received()
        client.emit(
            "send_message",
            {
                "car_id": self.car_public,
                "content": "hello via socket",
                "receiver_id": self.seller_public,
            },
        )
        received = client.get_received()
        errors = [evt for evt in received if evt.get("name") == "error"]
        self.assertFalse(errors, received)
        success_events = [
            evt
            for evt in received
            if evt.get("name") in ("new_message", "message_sent")
        ]
        self.assertTrue(success_events, received)
        joined = [evt for evt in received if evt.get("name") == "joined_chat"]
        self.assertTrue(joined, received)
        self.assertEqual(joined[-1]["args"][0].get("ok"), True)
        client.disconnect()

    def test_join_chat_denied_for_non_participant(self):
        """Strangers must not join listing chat rooms (C-01)."""
        client = self.socketio.test_client(
            self.app,
            flask_test_client=self.client,
            query_string=f"token={self.dealer_token}",
        )
        self.assertTrue(client.is_connected(), client.get_received())
        client.get_received()
        client.emit("join_chat", {"car_id": self.car_public})
        received = client.get_received()
        joined = [evt for evt in received if evt.get("name") == "joined_chat"]
        self.assertTrue(joined, received)
        payload = joined[-1]["args"][0]
        self.assertEqual(payload.get("ok"), False)
        self.assertEqual(payload.get("code"), "chat_access_denied")
        self.assertIsNone(payload.get("room"))
        client.disconnect()

    def test_join_chat_allowed_for_seller(self):
        client = self.socketio.test_client(
            self.app,
            flask_test_client=self.client,
            query_string=f"token={self.seller_token}",
        )
        self.assertTrue(client.is_connected(), client.get_received())
        client.get_received()
        client.emit("join_chat", {"car_id": self.car_public})
        received = client.get_received()
        joined = [evt for evt in received if evt.get("name") == "joined_chat"]
        self.assertTrue(joined, received)
        payload = joined[-1]["args"][0]
        self.assertEqual(payload.get("ok"), True)
        self.assertEqual(payload.get("car_id"), self.car_public)
        self.assertEqual(payload.get("room"), f"chat:{self.car_public}")
        client.disconnect()

    def test_join_chat_allowed_after_becoming_participant(self):
        client = self.socketio.test_client(
            self.app,
            flask_test_client=self.client,
            query_string=f"token={self.viewer_token}",
        )
        self.assertTrue(client.is_connected(), client.get_received())
        client.get_received()

        client.emit("join_chat", {"car_id": self.car_public})
        denied = client.get_received()
        denied_join = [evt for evt in denied if evt.get("name") == "joined_chat"]
        self.assertTrue(denied_join, denied)
        self.assertEqual(denied_join[-1]["args"][0].get("ok"), False)

        send = self.client.post(
            f"/api/chat/{self.car_public}/send",
            headers=self._auth(self.viewer_token),
            json={"content": "hi seller", "receiver_id": self.seller_public},
        )
        self.assertEqual(send.status_code, 201, send.data)

        client.emit("join_chat", {"car_id": self.car_public})
        allowed = client.get_received()
        allowed_join = [evt for evt in allowed if evt.get("name") == "joined_chat"]
        self.assertTrue(allowed_join, allowed)
        self.assertEqual(allowed_join[-1]["args"][0].get("ok"), True)
        client.disconnect()

    def test_update_and_delete_car_as_owner(self):
        create = self.client.post(
            "/api/cars",
            headers=self._auth(self.seller_token),
            json={
                "brand": "mazda",
                "model": "cx5",
                "year": 2018,
                "mileage": 2000,
                "price": 18000,
                "location": "Erbil",
            },
        )
        self.assertEqual(create.status_code, 201, create.data)
        created = create.get_json() or {}
        car = created.get("car") or {}
        car_public = car.get("public_id") or car.get("id")
        self.assertTrue(car_public)

        update = self.client.put(
            f"/api/cars/{car_public}",
            headers=self._auth(self.seller_token),
            json={"price": 17500},
        )
        self.assertEqual(update.status_code, 200, update.data)
        updated = (update.get_json() or {}).get("car") or {}
        self.assertEqual(float(updated.get("price", 0)), 17500.0)

        delete = self.client.delete(
            f"/api/cars/{car_public}",
            headers=self._auth(self.seller_token),
        )
        self.assertEqual(delete.status_code, 200, delete.data)

    def test_update_car_forbidden_for_non_owner(self):
        update = self.client.put(
            f"/api/cars/{self.car_public}",
            headers=self._auth(self.viewer_token),
            json={"price": 9999},
        )
        self.assertEqual(update.status_code, 403, update.data)
        body = update.get_json() or {}
        self.assertIn("Not authorized", body.get("message", ""))

    def test_user_recently_viewed_get(self):
        empty = self.client.get(
            "/api/user/recently-viewed",
            headers=self._auth(self.viewer_token),
        )
        self.assertEqual(empty.status_code, 200, empty.data)
        empty_body = empty.get_json() or {}
        self.assertEqual(empty_body.get("cars") or [], [])

        record = self.client.post(
            "/api/user/recently-viewed",
            headers=self._auth(self.viewer_token),
            json={"listing_id": self.car_public},
        )
        self.assertEqual(record.status_code, 200, record.data)

        listed = self.client.get(
            "/api/user/recently-viewed",
            headers=self._auth(self.viewer_token),
        )
        self.assertEqual(listed.status_code, 200, listed.data)
        payload = listed.get_json() or {}
        cars = payload.get("cars") or []
        self.assertGreaterEqual(len(cars), 1)
        ids = {
            (c.get("public_id") or c.get("id"))
            for c in cars
            if isinstance(c, dict)
        }
        self.assertIn(self.car_public, ids)

    def test_chat_send_by_public_car_id(self):
        send = self.client.post(
            f"/api/chat/{self.car_public}/send",
            headers=self._auth(self.viewer_token),
            json={
                "content": "hi via public id",
                "receiver_id": self.seller_public,
            },
        )
        self.assertEqual(send.status_code, 201, send.data)
        body = send.get_json() or {}
        message = body.get("message") or {}
        self.assertEqual(message.get("content"), "hi via public id")

    def test_clear_recently_viewed(self):
        record = self.client.post(
            "/api/user/recently-viewed",
            headers=self._auth(self.viewer_token),
            json={"listing_id": self.car_public},
        )
        self.assertEqual(record.status_code, 200, record.data)

        clear = self.client.delete(
            "/api/user/recently-viewed",
            headers=self._auth(self.viewer_token),
        )
        self.assertEqual(clear.status_code, 200, clear.data)

        listed = self.client.get(
            "/api/user/recently-viewed",
            headers=self._auth(self.viewer_token),
        )
        self.assertEqual(listed.status_code, 200, listed.data)
        payload = listed.get_json() or {}
        self.assertEqual(payload.get("cars") or [], [])

    def test_forgot_password_requires_identifier(self):
        r = self.client.post("/api/auth/forgot-password", json={})
        self.assertEqual(r.status_code, 400, r.data)

    def test_forgot_and_reset_password_via_phone(self):
        forgot = self.client.post(
            "/api/auth/forgot-password",
            json={"phone_number": "07000000002"},
        )
        self.assertEqual(forgot.status_code, 200, forgot.data)
        body = forgot.get_json() or {}
        dev_code = body.get("dev_code")
        self.assertTrue(dev_code, body)

        reset = self.client.post(
            "/api/auth/reset-password",
            json={"token": dev_code, "password": "Bb123456!"},
        )
        self.assertEqual(reset.status_code, 200, reset.data)

        login = self.client.post(
            "/api/auth/login",
            json={"username": "viewer", "password": "Bb123456!"},
        )
        self.assertEqual(login.status_code, 200, login.data)

    def test_list_cars_with_brand_filter(self):
        r = self.client.get("/api/cars?brand=toyota&page=1&per_page=10")
        self.assertEqual(r.status_code, 200, r.data)
        body = r.get_json() or {}
        self.assertIn("cars", body)
        self.assertIn("pagination", body)
        self.assertIsInstance(body.get("cars"), list)

    def test_favorite_status_get(self):
        r = self.client.get(
            f"/api/cars/{self.car_public}/favorite",
            headers=self._auth(self.viewer_token),
        )
        self.assertEqual(r.status_code, 200, r.data)
        body = r.get_json() or {}
        self.assertIn("is_favorited", body)

    def test_favorites_toggle_and_list(self):
        fav = self.client.post(
            f"/api/cars/{self.car_public}/favorite",
            headers=self._auth(self.viewer_token),
        )
        self.assertEqual(fav.status_code, 200, fav.data)
        body = fav.get_json() or {}
        self.assertTrue(body.get("is_favorited") or body.get("favorited"))

        listed = self.client.get(
            "/api/user/favorites",
            headers=self._auth(self.viewer_token),
        )
        self.assertEqual(listed.status_code, 200, listed.data)
        payload = listed.get_json() or {}
        cars = payload.get("cars") or []
        self.assertGreaterEqual(len(cars), 1)

    def test_saved_searches_crud(self):
        create = self.client.post(
            "/api/saved-searches",
            headers=self._auth(self.viewer_token),
            json={
                "name": "Camry under 15k",
                "filters": {"brand": "toyota", "model": "camry", "max_price": 15000},
                "notify": True,
            },
        )
        self.assertEqual(create.status_code, 201, create.data)
        created = create.get_json() or {}
        search_id = (created.get("saved_search") or {}).get("id")
        self.assertTrue(search_id)

        listed = self.client.get(
            "/api/saved-searches",
            headers=self._auth(self.viewer_token),
        )
        self.assertEqual(listed.status_code, 200, listed.data)
        rows = (listed.get_json() or {}).get("saved_searches") or []
        self.assertGreaterEqual(len(rows), 1)

        update = self.client.put(
            f"/api/saved-searches/{search_id}",
            headers=self._auth(self.viewer_token),
            json={"name": "Camry under 12k", "notify": False},
        )
        self.assertEqual(update.status_code, 200, update.data)
        updated = update.get_json() or {}
        self.assertEqual(
            (updated.get("saved_search") or {}).get("name"),
            "Camry under 12k",
        )

        delete = self.client.delete(
            f"/api/saved-searches/{search_id}",
            headers=self._auth(self.viewer_token),
        )
        self.assertEqual(delete.status_code, 200, delete.data)

    def test_job_status_requires_owner(self):
        """C-04: strangers cannot poll another user's Celery job."""
        from kk.job_ownership import clear_job_owners_for_tests, register_job_owner

        clear_job_owners_for_tests()
        task_id = "c04test-job-aaaaaaaa-bbbb-cccc-dddd"

        # Unregistered / foreign jobs look like 404 (no existence leak).
        missing = self.client.get(
            f"/api/jobs/{task_id}",
            headers=self._auth(self.viewer_token),
        )
        self.assertEqual(missing.status_code, 404, missing.data)

        register_job_owner(task_id, self.viewer_public)

        denied = self.client.get(
            f"/api/jobs/{task_id}",
            headers=self._auth(self.seller_token),
        )
        self.assertEqual(denied.status_code, 404, denied.data)

        allowed = self.client.get(
            f"/api/jobs/{task_id}",
            headers=self._auth(self.viewer_token),
        )
        self.assertIn(allowed.status_code, (200, 503), allowed.data)
        body = allowed.get_json() or {}
        self.assertEqual(body.get("task_id"), task_id)
        self.assertIn("state", body)
        clear_job_owners_for_tests()

    def test_job_status_rejects_invalid_task_id(self):
        bad = self.client.get(
            "/api/jobs/../etc/passwd",
            headers=self._auth(self.viewer_token),
        )
        self.assertEqual(bad.status_code, 404, bad.data)

    def test_signup_rate_limit_aligned_with_register(self):
        """C-05: mobile signup must not use the old 1000/hr unlimited-style cap."""
        from kk.routes import auth as auth_routes

        self.assertEqual(auth_routes._SIGNUP_MAX_REQUESTS, 5)
        self.assertEqual(auth_routes._SIGNUP_WINDOW_MINUTES, 60)
        previous = os.environ.get("RATE_LIMIT_SIGNUP")
        try:
            os.environ["RATE_LIMIT_SIGNUP"] = "12"
            self.assertEqual(auth_routes._signup_max_requests(), 12)
            os.environ["RATE_LIMIT_SIGNUP"] = "not-a-number"
            self.assertEqual(auth_routes._signup_max_requests(), 5)
        finally:
            if previous is None:
                os.environ.pop("RATE_LIMIT_SIGNUP", None)
            else:
                os.environ["RATE_LIMIT_SIGNUP"] = previous

    def test_analyze_car_image_unavailable_by_default(self):
        """C-02: never return fake Camry specs when analysis is gated off."""
        jpeg = b"\xff\xd8\xff\xdb" + b"0" * 100 + b"\xff\xd9"
        previous = os.environ.pop("ALLOW_PLACEHOLDER_CAR_ANALYSIS", None)
        try:
            r = self.client.post(
                "/api/analyze-car-image",
                headers=self._auth(self.viewer_token),
                data={"image": (io.BytesIO(jpeg), "car.jpg")},
                content_type="multipart/form-data",
            )
            self.assertEqual(r.status_code, 501, r.data)
            body = r.get_json() or {}
            self.assertEqual(body.get("code"), "car_image_analysis_unavailable")
            self.assertFalse(body.get("available", True))
            self.assertNotIn("analysis", body)
        finally:
            if previous is None:
                os.environ.pop("ALLOW_PLACEHOLDER_CAR_ANALYSIS", None)
            else:
                os.environ["ALLOW_PLACEHOLDER_CAR_ANALYSIS"] = previous

    def test_analyze_car_image_placeholder_opt_in_dev_only(self):
        """C-02: placeholder only when explicitly enabled in non-production."""
        from kk.ai_service import car_image_analysis_enabled

        jpeg = b"\xff\xd8\xff\xdb" + b"0" * 100 + b"\xff\xd9"
        previous = os.environ.get("ALLOW_PLACEHOLDER_CAR_ANALYSIS")
        os.environ["ALLOW_PLACEHOLDER_CAR_ANALYSIS"] = "1"
        try:
            self.assertTrue(car_image_analysis_enabled())
            r = self.client.post(
                "/api/analyze-car-image",
                headers=self._auth(self.viewer_token),
                data={"image": (io.BytesIO(jpeg), "car.jpg")},
                content_type="multipart/form-data",
            )
            self.assertEqual(r.status_code, 200, r.data)
            body = r.get_json() or {}
            self.assertTrue(body.get("success"))
            analysis = body.get("analysis") or {}
            self.assertEqual(analysis.get("source"), "placeholder")
            brand_model = analysis.get("brand_model") or {}
            self.assertEqual(brand_model.get("brand"), "toyota")
        finally:
            if previous is None:
                os.environ.pop("ALLOW_PLACEHOLDER_CAR_ANALYSIS", None)
            else:
                os.environ["ALLOW_PLACEHOLDER_CAR_ANALYSIS"] = previous

    def test_car_image_analysis_disabled_in_production_env(self):
        """C-02: production never enables placeholder even if flag is set."""
        from kk import ai_service

        previous_env = os.environ.get("APP_ENV")
        previous_flag = os.environ.get("ALLOW_PLACEHOLDER_CAR_ANALYSIS")
        os.environ["APP_ENV"] = "production"
        os.environ["ALLOW_PLACEHOLDER_CAR_ANALYSIS"] = "1"
        try:
            self.assertFalse(ai_service.car_image_analysis_enabled())
            result = ai_service.car_analysis_service.analyze_car_image("/tmp/x.jpg")
            self.assertEqual(result.get("code"), "car_image_analysis_unavailable")
            self.assertNotIn("brand_model", result)
        finally:
            if previous_env is None:
                os.environ.pop("APP_ENV", None)
            else:
                os.environ["APP_ENV"] = previous_env
            if previous_flag is None:
                os.environ.pop("ALLOW_PLACEHOLDER_CAR_ANALYSIS", None)
            else:
                os.environ["ALLOW_PLACEHOLDER_CAR_ANALYSIS"] = previous_flag
            # Restore testing env used by this suite.
            os.environ["APP_ENV"] = "testing"

    def test_upload_persistence_mode_and_production_validation(self):
        """C-06: production requires R2+public URL or absolute UPLOAD_FOLDER."""
        from kk import config as cfg

        keys = (
            "R2_ACCOUNT_ID",
            "R2_BUCKET_NAME",
            "R2_ACCESS_KEY_ID",
            "R2_SECRET_ACCESS_KEY",
            "R2_PUBLIC_URL",
            "UPLOAD_FOLDER",
            "ALLOW_EPHEMERAL_UPLOADS",
            "APP_ENV",
        )
        previous = {k: os.environ.get(k) for k in keys}

        def _clear():
            for k in keys:
                os.environ.pop(k, None)

        def _restore():
            for k, v in previous.items():
                if v is None:
                    os.environ.pop(k, None)
                else:
                    os.environ[k] = v
            os.environ["APP_ENV"] = "testing"

        try:
            _clear()
            os.environ["APP_ENV"] = "production"
            self.assertEqual(cfg.upload_persistence_mode(), "ephemeral")
            with self.assertRaises(RuntimeError):
                cfg.validate_upload_persistence("production")

            os.environ["ALLOW_EPHEMERAL_UPLOADS"] = "1"
            cfg.validate_upload_persistence("production")  # escape hatch
            del os.environ["ALLOW_EPHEMERAL_UPLOADS"]

            os.environ["R2_ACCOUNT_ID"] = "acc"
            os.environ["R2_BUCKET_NAME"] = "bucket"
            os.environ["R2_ACCESS_KEY_ID"] = "key"
            os.environ["R2_SECRET_ACCESS_KEY"] = "secret"
            self.assertEqual(cfg.upload_persistence_mode(), "r2_incomplete")
            with self.assertRaises(RuntimeError):
                cfg.validate_upload_persistence("production")

            os.environ["R2_PUBLIC_URL"] = "https://pub.example.r2.dev"
            self.assertEqual(cfg.upload_persistence_mode(), "r2")
            cfg.validate_upload_persistence("production")

            for k in (
                "R2_ACCOUNT_ID",
                "R2_BUCKET_NAME",
                "R2_ACCESS_KEY_ID",
                "R2_SECRET_ACCESS_KEY",
                "R2_PUBLIC_URL",
            ):
                del os.environ[k]
            os.environ["UPLOAD_FOLDER"] = "/data/uploads"
            self.assertEqual(cfg.upload_persistence_mode(), "disk")
            cfg.validate_upload_persistence("production")

            # Relative path is treated as ephemeral (not a volume mount).
            os.environ["UPLOAD_FOLDER"] = "static/uploads"
            self.assertEqual(cfg.upload_persistence_mode(), "ephemeral")
        finally:
            _restore()

    def test_redis_required_in_production_validation(self):
        """H-02: production requires reachable REDIS_URL (or escape hatch)."""
        from kk import config as cfg

        keys = ("REDIS_URL", "ALLOW_INMEMORY_RATE_LIMITS", "APP_ENV")
        previous = {k: os.environ.get(k) for k in keys}

        def _restore():
            for k, v in previous.items():
                if v is None:
                    os.environ.pop(k, None)
                else:
                    os.environ[k] = v
            os.environ["APP_ENV"] = "testing"

        try:
            for k in keys:
                os.environ.pop(k, None)
            os.environ["APP_ENV"] = "production"
            with self.assertRaises(RuntimeError):
                cfg.validate_redis_required("production")

            os.environ["ALLOW_INMEMORY_RATE_LIMITS"] = "1"
            cfg.validate_redis_required("production")
            del os.environ["ALLOW_INMEMORY_RATE_LIMITS"]

            # Unreachable port → fail (URL alone is not enough).
            os.environ["REDIS_URL"] = "redis://127.0.0.1:1/0"
            with self.assertRaises(RuntimeError):
                cfg.validate_redis_required("production")
        finally:
            _restore()

    def test_car_listing_filter_composite_indexes_exist(self):
        """H-04: composite indexes for common /api/cars filter shapes."""
        from sqlalchemy import inspect

        expected = {
            "ix_car_active_status_created_at",
            "ix_car_active_brand_price",
            "ix_car_active_location_created_at",
            "ix_car_active_year_price",
            "ix_car_active_featured_created_at",
            "ix_car_seller_active_created_at",
        }
        with self.app.app_context():
            names = {ix["name"] for ix in inspect(self._db.engine).get_indexes("car")}
        missing = expected - names
        self.assertFalse(missing, f"missing car indexes: {sorted(missing)}")

        # Smoke: filtered browse still returns 200 with composites present.
        r = self.client.get(
            f"/api/cars?brand=Toyota&min_price=1000&max_price=999999&sort_by=newest"
        )
        self.assertEqual(r.status_code, 200, r.data)
        self.assertIn("cars", r.get_json() or {})


if __name__ == "__main__":
    unittest.main(verbosity=2)

