"""Outbound email helpers (Resend → SendGrid → SMTP)."""

from __future__ import annotations

import json
import logging
import os
import urllib.error
import urllib.request
from typing import Any

from flask import current_app

logger = logging.getLogger(__name__)


def _from_address() -> str:
    return (
        (os.environ.get("RESEND_FROM_EMAIL") or "").strip()
        or (os.environ.get("SENDGRID_FROM_EMAIL") or "").strip()
        or (current_app.config.get("MAIL_DEFAULT_SENDER") or "").strip()
        or (current_app.config.get("MAIL_USERNAME") or "").strip()
        or "noreply@carzo.app"
    )


def _send_via_resend(to_email: str, subject: str, text_body: str, html_body: str | None) -> bool:
    api_key = (os.environ.get("RESEND_API_KEY") or "").strip()
    if not api_key:
        return False
    payload: dict[str, Any] = {
        "from": _from_address(),
        "to": [to_email],
        "subject": subject,
        "text": text_body,
    }
    if html_body:
        payload["html"] = html_body
    req = urllib.request.Request(
        "https://api.resend.com/emails",
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            return 200 <= getattr(resp, "status", 200) < 300
    except urllib.error.HTTPError as exc:
        detail = ""
        try:
            detail = exc.read().decode("utf-8", errors="replace")
        except Exception:
            detail = str(exc)
        logger.warning("Resend email failed (%s): %s", exc.code, detail)
        return False
    except Exception:
        logger.exception("Resend email failed")
        return False


def _send_via_sendgrid(to_email: str, subject: str, text_body: str, html_body: str | None) -> bool:
    api_key = (os.environ.get("SENDGRID_API_KEY") or "").strip()
    if not api_key:
        return False
    content = [{"type": "text/plain", "value": text_body}]
    if html_body:
        content.append({"type": "text/html", "value": html_body})
    payload = {
        "personalizations": [{"to": [{"email": to_email}]}],
        "from": {"email": _from_address()},
        "subject": subject,
        "content": content,
    }
    req = urllib.request.Request(
        "https://api.sendgrid.com/v3/mail/send",
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            # SendGrid returns 202 on success.
            return 200 <= getattr(resp, "status", 202) < 300
    except urllib.error.HTTPError as exc:
        detail = ""
        try:
            detail = exc.read().decode("utf-8", errors="replace")
        except Exception:
            detail = str(exc)
        logger.warning("SendGrid email failed (%s): %s", getattr(exc, "code", "?"), detail)
        return False
    except Exception:
        logger.exception("SendGrid email failed")
        return False


def _send_via_smtp(to_email: str, subject: str, text_body: str, html_body: str | None) -> bool:
    username = (current_app.config.get("MAIL_USERNAME") or "").strip()
    password = (current_app.config.get("MAIL_PASSWORD") or "").strip()
    if not username or not password:
        return False
    try:
        from flask_mail import Message

        from .extensions import mail

        msg = Message(
            subject=subject,
            recipients=[to_email],
            body=text_body,
            html=html_body,
            sender=_from_address(),
        )
        mail.send(msg)
        return True
    except Exception:
        logger.exception("SMTP email failed")
        return False


def send_email(
    to_email: str,
    *,
    subject: str,
    text_body: str,
    html_body: str | None = None,
) -> bool:
    """Send an email using the first configured provider."""
    dest = (to_email or "").strip().lower()
    if not dest or "@" not in dest:
        return False
    subject = (subject or "").strip() or "Carzo"
    text_body = text_body or ""
    if (os.environ.get("RESEND_API_KEY") or "").strip():
        return _send_via_resend(dest, subject, text_body, html_body)
    if (os.environ.get("SENDGRID_API_KEY") or "").strip():
        return _send_via_sendgrid(dest, subject, text_body, html_body)
    return _send_via_smtp(dest, subject, text_body, html_body)


def send_dealer_email_verification_code(to_email: str, code: str) -> bool:
    subject = "Your Carzo verification code"
    text_body = (
        f"Your Carzo verification code is: {code}\n\n"
        "Enter this code in the app to verify your dealership contact email. "
        "It expires in 10 minutes."
    )
    html_body = (
        f"<p>Your Carzo verification code is:</p>"
        f"<p style='font-size:24px;font-weight:700;letter-spacing:2px'>{code}</p>"
        f"<p>Enter this code in the app to verify your dealership contact email. "
        f"It expires in 10 minutes.</p>"
    )
    return send_email(to_email, subject=subject, text_body=text_body, html_body=html_body)


def send_account_email_verification(to_email: str, token: str) -> bool:
    """Send the account email verification magic link."""
    public_base = (os.environ.get("PUBLIC_BASE_URL") or "").strip().rstrip("/")
    if public_base:
        link = f"{public_base}/verify-email?token={token}"
    else:
        link = f"carzo://verify-email?token={token}"
    subject = "Verify your Carzo email"
    text_body = (
        "Verify your Carzo email address by opening this link:\n\n"
        f"{link}\n\n"
        "If you did not request this, you can ignore this email."
    )
    html_body = (
        "<p>Verify your Carzo email address:</p>"
        f"<p><a href=\"{link}\">Verify email</a></p>"
        "<p>If you did not request this, you can ignore this email.</p>"
    )
    return send_email(to_email, subject=subject, text_body=text_body, html_body=html_body)
