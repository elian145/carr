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
        os.environ["DB_PATH"] = os.path.join(self._tmp.name, "t.db")

        from kk.app_factory import create_app

        self.app, self.socketio, *_ = create_app()
        self.client = self.app.test_client()

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

            db.session.add_all([seller, viewer, admin])
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
        self.admin_token = self._login("admin", "Aa123456")

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

    def _login(self, username: str, password: str) -> str:
        r = self.client.post("/api/auth/login", json={"username": username, "password": password})
        self.assertEqual(r.status_code, 200, r.data)
        data = r.get_json()
        self.assertIn("access_token", data)
        return data["access_token"]

    def _auth(self, token: str) -> dict[str, str]:
        return {"Authorization": f"Bearer {token}"}

    def test_analytics_track_and_list(self):
        r = self.client.post(
            "/api/analytics/track/view",
            json={"listing_id": self.car_public},
            headers=self._auth(self.viewer_token),
        )
        self.assertEqual(r.status_code, 200, r.data)

        r2 = self.client.get("/api/analytics/listings", headers=self._auth(self.seller_token))
        self.assertEqual(r2.status_code, 200, r2.data)
        self.assertIsInstance(r2.get_json(), list)

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

    def test_public_dealers_list(self):
        r = self.client.get("/api/dealers?page=1&per_page=5")
        self.assertEqual(r.status_code, 200, r.data)
        body = r.get_json() or {}
        self.assertIn("dealers", body)
        self.assertIn("pagination", body)

    def test_well_known_app_links_require_env(self):
        """Without store env vars, deep-link files must 404 (not serve invalid stubs)."""
        for path in (
            "/.well-known/assetlinks.json",
            "/.well-known/apple-app-site-association",
        ):
            r = self.client.get(path)
            self.assertEqual(r.status_code, 404, (path, r.data))

    def test_trust_config_and_legal_pages(self):
        trust = self.client.get("/api/config/trust")
        self.assertEqual(trust.status_code, 200, trust.data)
        payload = trust.get_json() or {}
        self.assertEqual(payload.get("support_email"), "support@carzo.app")
        self.assertTrue((payload.get("privacy_url") or "").strip())
        self.assertTrue((payload.get("terms_url") or "").strip())

        terms = self.client.get("/terms")
        self.assertEqual(terms.status_code, 200, terms.data)
        self.assertIn(b"CarNet", terms.data)

        privacy = self.client.get("/privacy")
        self.assertEqual(privacy.status_code, 200, privacy.data)
        self.assertIn(b"CarNet", privacy.data)

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

        delete = self.client.delete(
            f"/api/saved-searches/{search_id}",
            headers=self._auth(self.viewer_token),
        )
        self.assertEqual(delete.status_code, 200, delete.data)

if __name__ == "__main__":
    unittest.main(verbosity=2)

