"""The account email-verification link must use a deep-link host the app
actually claims (S9). See test_verify_email_landing.py for the matching
browser-landing-page assertion.
"""

from __future__ import annotations

from unittest.mock import patch

from kk import email_service


def test_fallback_link_uses_claimed_carzo_host(monkeypatch):
    monkeypatch.delenv("PUBLIC_BASE_URL", raising=False)
    with patch.object(email_service, "send_email") as mock_send:
        mock_send.return_value = True
        email_service.send_account_email_verification("user@example.com", "tok-1")

    _args, kwargs = mock_send.call_args
    assert "carzo://auth/verify-email?token=tok-1" in kwargs["text_body"]
    assert "carzo://verify-email?token=" not in kwargs["text_body"]


def test_public_base_url_link_is_used_when_configured(monkeypatch):
    monkeypatch.setenv("PUBLIC_BASE_URL", "https://api.carzo.app")
    with patch.object(email_service, "send_email") as mock_send:
        mock_send.return_value = True
        email_service.send_account_email_verification("user@example.com", "tok-2")

    _args, kwargs = mock_send.call_args
    assert "https://api.carzo.app/verify-email?token=tok-2" in kwargs["text_body"]
