"""Public /privacy page: must be reachable with NO authentication and return
a normal, browser-readable HTML page (not JSON/PDF), per the CarNet privacy
policy requirements.

Mirrors the lightweight pattern used by test_verify_email_landing.py: a bare
Flask app with only the ``misc`` blueprint registered, no DB/app-factory
needed, since kk.legal_pages already falls back to env defaults when no DB
session is available.
"""

from __future__ import annotations

import sys
from pathlib import Path

from flask import Flask

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from kk.routes.misc import bp as misc_bp  # noqa: E402


def _client():
    app = Flask(__name__)
    app.register_blueprint(misc_bp)
    return app.test_client()


def test_privacy_returns_200_without_authentication():
    """No Authorization header, no session/cookies -- must still succeed."""
    resp = _client().get("/privacy")
    assert resp.status_code == 200, resp.data


def test_privacy_returns_html_not_json_or_pdf():
    resp = _client().get("/privacy")
    content_type = resp.headers.get("Content-Type", "")
    assert "text/html" in content_type, content_type
    assert "application/json" not in content_type
    assert "application/pdf" not in content_type
    # Must be parseable as a normal HTML document, not a JSON payload.
    assert resp.get_json(silent=True) is None
    body = resp.get_data(as_text=True)
    assert "<!DOCTYPE html>" in body or "<!doctype html>" in body.lower()
    assert "<html" in body.lower()


def test_privacy_page_title_is_carnet_privacy_policy():
    resp = _client().get("/privacy")
    body = resp.get_data(as_text=True)
    assert "<title>CarNet Privacy Policy</title>" in body


def test_privacy_page_identifies_carnet_and_carnetiq():
    resp = _client().get("/privacy")
    body = resp.get_data(as_text=True)
    assert "CarNet" in body
    assert "CarNetiq" in body


def test_privacy_page_covers_required_data_categories():
    resp = _client().get("/privacy")
    body = resp.get_data(as_text=True).lower()

    required_snippets = [
        "phone number",  # phone number / account information
        "profile",  # profile information
        "vehicle",  # vehicle listing information
        "photos",  # uploaded vehicle/listing photos
        "videos",  # uploaded vehicle/listing videos
        "chat messages",  # buyer/seller chat messages
        "favorites",  # favorites
        "push notification",  # notifications / device push token
        "location",  # location for listings/maps/search
        "diagnostics",  # analytics/diagnostic info
        "security",  # security information
    ]
    for snippet in required_snippets:
        assert snippet in body, f"Missing expected privacy category text: {snippet!r}"


def test_privacy_page_states_no_sale_of_personal_information():
    resp = _client().get("/privacy")
    body = resp.get_data(as_text=True)
    assert "We do not sell your personal information." in body


def test_privacy_page_has_contact_retention_deletion_and_rights_sections():
    resp = _client().get("/privacy")
    body = resp.get_data(as_text=True)
    assert "Contact" in body
    assert "Retention" in body
    assert "Delete account" in body
    assert "Your choices and rights" in body
    assert "Security" in body


def test_privacy_page_has_effective_date():
    resp = _client().get("/privacy")
    body = resp.get_data(as_text=True)
    assert "Effective:" in body


def test_privacy_page_does_not_leak_secrets_or_credentials():
    """Sanity guard: the rendered page must never contain obvious secret
    material, even if env vars happen to be set to something sensitive in
    the running process (defense-in-depth, not a substitute for not putting
    secrets in the template)."""
    resp = _client().get("/privacy")
    body = resp.get_data(as_text=True).lower()
    forbidden = [
        "secret_key",
        "api_key=",
        "private_key",
        "password=",
        "sk_live_",
        "aws_secret",
    ]
    for token in forbidden:
        assert token not in body, f"Unexpected secret-looking token in /privacy: {token!r}"


def test_privacy_page_get_only():
    """POST must not be treated as an alternate way to fetch the page (route
    is GET-only; this also documents current API behavior is unchanged)."""
    resp = _client().post("/privacy")
    assert resp.status_code == 405
