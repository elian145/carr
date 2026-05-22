"""Serve CARZO Terms of Service and Privacy Policy as public HTML pages."""

from __future__ import annotations

import os
from datetime import date
from html import escape
from pathlib import Path

from flask import Response, request

_LEGAL_DIR = Path(__file__).resolve().parent / "legal"


def public_base_url() -> str:
    """Public HTTPS origin for legal links (env override, else current request)."""
    base = (os.environ.get("PUBLIC_BASE_URL") or "").strip().rstrip("/")
    if base:
        return base
    try:
        return request.url_root.rstrip("/")
    except RuntimeError:
        return ""


def default_terms_url() -> str:
    custom = (os.environ.get("TERMS_URL") or "").strip()
    if custom:
        return custom
    base = public_base_url()
    return f"{base}/terms" if base else ""


def default_privacy_url() -> str:
    custom = (os.environ.get("PRIVACY_URL") or "").strip()
    if custom:
        return custom
    base = public_base_url()
    return f"{base}/privacy" if base else ""


def _support_email() -> str:
    return (os.environ.get("SUPPORT_EMAIL") or "support@carzo.app").strip()


def _effective_date() -> str:
    raw = (os.environ.get("LEGAL_EFFECTIVE_DATE") or "").strip()
    if raw:
        return raw
    return date.today().strftime("%B %d, %Y")


def _render_legal_html(slug: str) -> Response:
    path = _LEGAL_DIR / f"{slug}.html"
    if not path.is_file():
        return Response("Not found", status=404, mimetype="text/plain")

    base = public_base_url()
    support = escape(_support_email())
    effective = escape(_effective_date())
    terms_url = escape(f"{base}/terms" if base else "/terms")
    privacy_url = escape(f"{base}/privacy" if base else "/privacy")
    support_mailto = escape(f"mailto:{_support_email()}")

    body = path.read_text(encoding="utf-8")
    body = (
        body.replace("{{SUPPORT_EMAIL}}", support)
        .replace("{{EFFECTIVE_DATE}}", effective)
        .replace("{{TERMS_URL}}", terms_url)
        .replace("{{PRIVACY_URL}}", privacy_url)
        .replace("{{SUPPORT_MAILTO}}", support_mailto)
    )
    return Response(body, 200, {"Content-Type": "text/html; charset=utf-8"})


def terms_response() -> Response:
    return _render_legal_html("terms")


def privacy_response() -> Response:
    return _render_legal_html("privacy")
