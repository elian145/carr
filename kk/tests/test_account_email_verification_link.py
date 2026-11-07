"""The account email-verification link must be an https link (F-28).

A custom-scheme (`carzo://`) link can be claimed by any other app on the
device, which would then receive the verification token. When PUBLIC_BASE_URL
is not an https URL the email is refused instead of silently downgraded.
See test_verify_email_landing.py for the browser-landing-page assertion.
"""

from __future__ import annotations

from unittest.mock import patch

import pytest

from kk import email_service


def test_unset_public_base_url_refuses_to_send(monkeypatch):
    monkeypatch.delenv("PUBLIC_BASE_URL", raising=False)
    with patch.object(email_service, "send_email") as mock_send:
        assert email_service.send_account_email_verification("user@example.com", "tok-1") is False
    mock_send.assert_not_called()


@pytest.mark.parametrize("base", ["http://api.carzo.app", "carzo://auth", "api.carzo.app", "ftp://x.y"])
def test_non_https_public_base_url_refuses_to_send(monkeypatch, base):
    monkeypatch.setenv("PUBLIC_BASE_URL", base)
    with patch.object(email_service, "send_email") as mock_send:
        assert email_service.send_account_email_verification("user@example.com", "tok-1") is False
    mock_send.assert_not_called()


def test_https_public_base_url_link_is_used(monkeypatch):
    monkeypatch.setenv("PUBLIC_BASE_URL", "https://api.carzo.app/")
    with patch.object(email_service, "send_email") as mock_send:
        mock_send.return_value = True
        assert email_service.send_account_email_verification("user@example.com", "tok-2") is True

    _args, kwargs = mock_send.call_args
    assert "https://api.carzo.app/verify-email?token=tok-2" in kwargs["text_body"]
    assert "carzo://" not in kwargs["text_body"]
    assert "carzo://" not in kwargs["html_body"]


def test_token_is_url_encoded(monkeypatch):
    monkeypatch.setenv("PUBLIC_BASE_URL", "https://api.carzo.app")
    with patch.object(email_service, "send_email") as mock_send:
        mock_send.return_value = True
        email_service.send_account_email_verification("user@example.com", "a b&c=d")
    assert "token=a%20b%26c%3Dd" in mock_send.call_args.kwargs["text_body"]


def test_local_http_allowed_for_development(monkeypatch):
    monkeypatch.setenv("PUBLIC_BASE_URL", "http://localhost:5000")
    with patch.object(email_service, "send_email") as mock_send:
        mock_send.return_value = True
        assert email_service.send_account_email_verification("user@example.com", "t") is True
