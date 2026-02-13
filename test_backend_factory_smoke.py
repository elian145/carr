#!/usr/bin/env python3
"""
Factory-backed backend smoke tests (no server required).

Run:
  python test_backend_factory_smoke.py
"""

from __future__ import annotations

import io
import os
import tempfile
import unittest
import uuid


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
                public_id="pv",
            )
            viewer.set_password("Aa123456")

            db.session.add_all([seller, viewer])
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

if __name__ == "__main__":
    unittest.main(verbosity=2)

