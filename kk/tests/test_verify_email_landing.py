"""The email-verification landing page must deep-link to a host this app
actually claims (S9): `carzo://verify-email` is unclaimed on Android and
silently does nothing, while `carzo://auth/...` matches the app's registered
intent-filter (see android/app/src/main/AndroidManifest.xml).
"""

from __future__ import annotations

from flask import Flask

from kk.routes.misc import bp as misc_bp


def _client():
    app = Flask(__name__)
    app.register_blueprint(misc_bp)
    return app.test_client()


def test_verify_email_landing_links_to_claimed_deep_link_host():
    resp = _client().get("/verify-email?token=abc123")
    assert resp.status_code == 200
    body = resp.get_data(as_text=True)
    assert "carzo://auth/verify-email?token=abc123" in body
    # Unclaimed host must never appear, even as a leftover reference.
    assert "carzo://verify-email?" not in body


def test_verify_email_landing_shows_pasteable_token_fallback():
    resp = _client().get("/verify-email?token=abc123")
    body = resp.get_data(as_text=True)
    assert "abc123" in body


def test_verify_email_landing_requires_token():
    resp = _client().get("/verify-email")
    assert resp.status_code == 404
