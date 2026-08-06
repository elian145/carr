"""Serve CarNet Terms of Service and Privacy Policy as public HTML pages."""

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
    try:
        from .app_settings import get_platform_settings

        email = (get_platform_settings().get("support_email") or "").strip()
        if email:
            return email
    except Exception:
        pass
    return (os.environ.get("SUPPORT_EMAIL") or "support@carzo.app").strip()


def _effective_date() -> str:
    try:
        from .app_settings import get_platform_settings

        raw = (get_platform_settings().get("legal_effective_date") or "").strip()
        if raw:
            return raw
    except Exception:
        pass
    raw = (os.environ.get("LEGAL_EFFECTIVE_DATE") or "").strip()
    if raw:
        return raw
    return date.today().strftime("%B %d, %Y")


def _operator_name() -> str:
    return (
        os.environ.get("LEGAL_OPERATOR_NAME") or "CarNet (Carzo)"
    ).strip() or "CarNet (Carzo)"


def _operator_address() -> str:
    return (os.environ.get("LEGAL_OPERATOR_ADDRESS") or "").strip()


def _jurisdiction() -> str:
    return (
        os.environ.get("LEGAL_JURISDICTION") or "Iraq"
    ).strip() or "Iraq"


def _operator_address_block() -> str:
    """HTML snippet: optional address line under the operator name."""
    addr = _operator_address()
    if not addr:
        return ""
    return f"<br>{escape(addr)}"


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
    operator = escape(_operator_name())
    jurisdiction = escape(_jurisdiction())
    address_block = _operator_address_block()

    body = path.read_text(encoding="utf-8")
    body = (
        body.replace("{{SUPPORT_EMAIL}}", support)
        .replace("{{EFFECTIVE_DATE}}", effective)
        .replace("{{TERMS_URL}}", terms_url)
        .replace("{{PRIVACY_URL}}", privacy_url)
        .replace("{{SUPPORT_MAILTO}}", support_mailto)
        .replace("{{OPERATOR_NAME}}", operator)
        .replace("{{OPERATOR_ADDRESS_BLOCK}}", address_block)
        .replace("{{JURISDICTION}}", jurisdiction)
    )
    return Response(body, 200, {"Content-Type": "text/html; charset=utf-8"})


def terms_response() -> Response:
    return _render_legal_html("terms")


def privacy_response() -> Response:
    return _render_legal_html("privacy")
