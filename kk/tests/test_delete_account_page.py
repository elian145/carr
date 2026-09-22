"""Public /delete-account page + POST /api/account-deletion-request: must be
reachable and submittable with NO authentication (Google Play / App Store
account-deletion requirement), and must no longer frame this as a store
policy requirement to end users. Matches kk/legal/delete_account.html +
kk/routes/misc.py::account_deletion_request().

Mirrors the lightweight pattern used by test_privacy_policy_page.py: a bare
Flask app with only the ``misc`` blueprint registered, no DB/app-factory
needed. ``TESTING=True`` makes ``check_rate_limit`` a no-op (see
kk/security.py::check_rate_limit), and ``send_email`` is patched so the test
never attempts a real network call.
"""

from __future__ import annotations

import sys
from pathlib import Path
from unittest.mock import patch

from flask import Flask

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from kk import email_service  # noqa: E402
from kk.routes.misc import bp as misc_bp  # noqa: E402


def _client():
    app = Flask(__name__)
    app.config["TESTING"] = True
    app.register_blueprint(misc_bp)
    return app.test_client()


def test_delete_account_page_returns_200_without_authentication():
    resp = _client().get("/delete-account")
    assert resp.status_code == 200, resp.data


def test_delete_account_page_returns_html():
    resp = _client().get("/delete-account")
    content_type = resp.headers.get("Content-Type", "")
    assert "text/html" in content_type, content_type
    body = resp.get_data(as_text=True)
    assert "<!DOCTYPE html>" in body or "<!doctype html>" in body.lower()


def test_delete_account_page_no_longer_cites_store_requirement():
    """The page must speak to users directly, not frame deletion as
    something Google Play/App Store force us to offer."""
    resp = _client().get("/delete-account")
    body = resp.get_data(as_text=True)
    assert "Google Play and App Store require" not in body
    assert "CarNet lets you request deletion of your account" in body


def test_delete_account_page_has_deletion_form_with_required_fields():
    resp = _client().get("/delete-account")
    body = resp.get_data(as_text=True)
    assert 'action="/api/account-deletion-request"' in body
    assert 'method="post"' in body.lower()
    assert 'name="phone"' in body
    assert 'id="phone"' in body


def test_delete_account_page_keeps_in_app_instructions():
    resp = _client().get("/delete-account")
    body = resp.get_data(as_text=True)
    assert "Profile" in body and "Delete account" in body


def test_delete_account_page_identifies_carnetiq_operator(monkeypatch):
    monkeypatch.delenv("LEGAL_OPERATOR_NAME", raising=False)
    resp = _client().get("/delete-account")
    body = resp.get_data(as_text=True)
    assert "CarNetiq" in body


def test_delete_account_page_states_what_is_retained_and_why():
    """Must not promise blanket deletion of listings/messages it doesn't
    actually perform -- explain the de-identify-and-retain behavior instead
    (matches kk/routes/auth.py::delete_account() / _delete_and_scrub_user_listings())."""
    resp = _client().get("/delete-account")
    body = resp.get_data(as_text=True)
    assert "de-identified" in body.lower()
    assert "disassociated from your identity" in body
    assert "Retention period" in body


def test_delete_account_page_does_not_overpromise_listing_or_message_deletion():
    """The old, inaccurate blanket promise must be gone."""
    resp = _client().get("/delete-account")
    body = resp.get_data(as_text=True)
    assert (
        "This deletes your account and associated data (listings, messages, "
        "favorites, saved searches)."
    ) not in body


def test_account_deletion_request_requires_no_authentication_and_succeeds():
    """A user who is NOT signed into the app must be able to submit the web
    deletion request form, with no secrets sent back and no real email/SMS
    sent (send_email is mocked)."""
    with patch.object(email_service, "send_email") as mock_send:
        mock_send.return_value = True
        resp = _client().post(
            "/api/account-deletion-request",
            json={"phone": "+9647701234567", "email": "user@example.com", "details": "test"},
        )
    assert resp.status_code == 200, resp.data
    data = resp.get_json()
    assert "message" in data
    assert isinstance(data["message"], str) and data["message"]
    # No secrets/credentials should ever appear in the response body.
    body_text = resp.get_data(as_text=True).lower()
    for token in ("secret_key", "api_key=", "private_key", "password=", "sk_live_"):
        assert token not in body_text


def test_account_deletion_request_rejects_missing_phone():
    with patch.object(email_service, "send_email") as mock_send:
        mock_send.return_value = True
        resp = _client().post(
            "/api/account-deletion-request",
            json={"email": "user@example.com"},
        )
    assert resp.status_code == 400
    mock_send.assert_not_called()


def test_account_deletion_request_accepts_form_encoded_submission():
    """The page's <form> posts JSON via fetch(), but the endpoint should also
    accept a plain form submission (progressive enhancement / no-JS)."""
    with patch.object(email_service, "send_email") as mock_send:
        mock_send.return_value = True
        resp = _client().post(
            "/api/account-deletion-request",
            data={"phone": "07701234567"},
        )
    assert resp.status_code == 200, resp.data


def test_account_deletion_request_does_not_require_auth_header():
    """Sanity check: no Authorization header is sent, and the endpoint must
    not 401/403 -- this must work for users who cannot sign into the app."""
    with patch.object(email_service, "send_email") as mock_send:
        mock_send.return_value = True
        resp = _client().post(
            "/api/account-deletion-request",
            json={"phone": "07701234567"},
        )
    assert resp.status_code not in (401, 403)
