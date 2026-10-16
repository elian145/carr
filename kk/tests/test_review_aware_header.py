"""``X-Carnet-Review-Aware`` is accepted everywhere the app sends it.

The Flutter client adds this header to every API request (JSON and multipart).
Pre-push check: it must not be rejected or ignored by any listing-edit /
media route, a browser (Flutter Web) preflight must allow it, and native
clients (Android/iOS, which never preflight) must be able to send it in any
header case (HTTP/2 lower-cases header names).
"""

from __future__ import annotations

import io
import uuid

import pytest

# Fixtures + helpers of the listing-edit suite (same app/db setup).
from kk.tests.test_listing_revisions import (  # noqa: F401
    _CDN,
    _auth,
    _public_image_urls,
    _published_listing,
    _revision_ids,
    _revision_status,
    app_ctx,
    client,
)

HEADER = "X-Carnet-Review-Aware"
ORIGIN = "https://admin.example.com"
WRITE_METHODS = {"POST", "PUT", "DELETE", "PATCH"}


def _aware(listing, name: str = HEADER, value: str = "1") -> dict:
    return {**_auth(listing["token"]), name: value}


def _is_relevant(rule: str) -> bool:
    return rule.startswith(("/api/cars", "/api/media/", "/api/config/app"))


class TestCorsPreflight:
    """Flutter Web sends an OPTIONS preflight because of the custom header."""

    def test_every_listing_and_media_route_allows_the_header(self, app_ctx):
        app, client_ = app_ctx
        checked = []
        failures = []
        for rule in app.url_map.iter_rules():
            if not _is_relevant(rule.rule):
                continue
            for method in sorted((rule.methods or set()) & (WRITE_METHODS | {"GET"})):
                url = (
                    rule.rule.replace("<int:image_id>", "1")
                    .replace("<int:video_id>", "1")
                    .replace("<car_id>", "some-car")
                    .replace("<client_media_id>", "cm1")
                )
                if "<" in url:
                    continue
                resp = client_.options(
                    url,
                    headers={
                        "Origin": ORIGIN,
                        "Access-Control-Request-Method": method,
                        "Access-Control-Request-Headers": (
                            "authorization,content-type,accept-language,"
                            "x-carnet-review-aware"
                        ),
                    },
                )
                allowed = (resp.headers.get("Access-Control-Allow-Headers") or "").lower()
                if (
                    resp.status_code not in (200, 204)
                    or "x-carnet-review-aware" not in allowed
                    or not resp.headers.get("Access-Control-Allow-Origin")
                    or method not in (resp.headers.get("Access-Control-Allow-Methods") or "")
                ):
                    failures.append((method, url, resp.status_code, allowed))
                checked.append((method, rule.rule))
        assert not failures, failures
        # sanity: the routes we care about were really exercised
        seen = set(checked)
        for expected in (
            ("PUT", "/api/cars/<car_id>"),
            ("DELETE", "/api/cars/<car_id>"),
            ("POST", "/api/cars/<car_id>/images"),
            ("POST", "/api/cars/<car_id>/images/attach"),
            ("POST", "/api/cars/<car_id>/videos"),
            ("PUT", "/api/cars/<car_id>/images/primary"),
            ("PUT", "/api/cars/<car_id>/images/layout"),
            ("DELETE", "/api/cars/<car_id>/images/<int:image_id>"),
            ("DELETE", "/api/cars/<car_id>/videos/<int:video_id>"),
            ("DELETE", "/api/cars/<car_id>/pending-revision"),
            ("GET", "/api/cars/<car_id>/pending-revision"),
            ("POST", "/api/media/r2/sign-upload"),
            ("POST", "/api/cars"),
        ):
            assert expected in seen, expected


class TestHeaderOnRealRequests:
    @pytest.fixture(autouse=True)
    def _fake_storage(self, monkeypatch):
        """No real image pipeline / storage: only the request handling is
        under test."""
        import kk.routes.media as media

        monkeypatch.setattr(media, "validate_file_upload", lambda *a, **k: (True, ""))
        monkeypatch.setattr(
            media,
            "process_and_store_image",
            lambda fs, **k: (f"{_CDN}/up_{uuid.uuid4().hex[:8]}.jpg", None),
        )

    def _multipart_upload(self, client, listing, headers):
        return client.post(
            f"/api/cars/{listing['public_id']}/images",
            data={"images": (io.BytesIO(b"\xff\xd8\xff fake"), "new.jpg")},
            headers=headers,
            content_type="multipart/form-data",
        )

    @pytest.mark.parametrize("name", [HEADER, HEADER.lower(), HEADER.upper()])
    def test_multipart_upload_with_header_in_any_case(self, app_ctx, client, name):
        """Android/iOS/Dart: header names reach the server in any case (and the
        multipart Content-Type/boundary is untouched by the extra header)."""
        listing = _published_listing(app_ctx, client, photos=2)
        r = self._multipart_upload(client, listing, _aware(listing, name))
        assert r.status_code == 201, r.get_data(as_text=True)
        # routed to the hidden draft, recognised as a review-aware draft
        assert _revision_status(app_ctx, listing) == "editing"
        assert _public_image_urls(client, listing) == listing["urls"]  # public untouched

    def test_multipart_upload_without_header_is_a_legacy_draft(self, app_ctx, client):
        listing = _published_listing(app_ctx, client, photos=2)
        r = self._multipart_upload(client, listing, _auth(listing["token"]))
        assert r.status_code == 201, r.get_data(as_text=True)
        assert _revision_status(app_ctx, listing) == "editing_legacy"

    def test_every_edit_route_accepts_the_header(self, app_ctx, client):
        listing = _published_listing(app_ctx, client, photos=3)
        h = _aware(listing)
        pub = listing["public_id"]
        a1, a2, a3 = listing["image_ids"]

        assert self._multipart_upload(client, listing, h).status_code == 201

        r = client.put(
            f"/api/cars/{pub}/images/primary",
            json={"image_url": listing["urls"][2]},
            headers=h,
        )
        assert r.status_code == 200, r.data

        r = client.put(
            f"/api/cars/{pub}/images/layout",
            json={"images": [{"image_url": u, "order": i} for i, u in enumerate(listing["urls"])]},
            headers=h,
        )
        assert r.status_code in (200, 400), r.data  # accepted + processed (body shape is not the point)
        assert r.status_code != 403

        r = client.delete(f"/api/cars/{pub}/images/{a2}", headers=h)
        assert r.status_code == 200, r.data

        r = client.get(f"/api/cars/{pub}/pending-revision", headers=h)
        assert r.status_code == 200, r.data
        assert r.get_json()["pending_revision"]["status"] == "editing"

        r = client.put(f"/api/cars/{pub}", json={"price": 12000}, headers=h)
        assert r.status_code == 200, r.data
        assert r.get_json()["submitted_for_review"] is True
        assert _revision_status(app_ctx, listing) == "pending"
        assert _public_image_urls(client, listing) == listing["urls"]

        r = client.delete(f"/api/cars/{pub}/pending-revision", headers=h)
        assert r.status_code == 200, r.data
        assert _revision_ids(app_ctx, listing) is None

    def test_header_on_a_non_edit_request_is_harmless(self, app_ctx, client):
        listing = _published_listing(app_ctx, client, photos=1)
        r = client.get(f"/api/cars/{listing['public_id']}", headers=_aware(listing))
        assert r.status_code == 200
        r = client.get("/api/cars?per_page=5", headers={HEADER: "1"})
        assert r.status_code == 200
        assert _revision_ids(app_ctx, listing) is None  # reading never creates a draft
