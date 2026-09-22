"""Public /terms page: must be reachable with NO authentication and reflect
current Android production branding (CarNet published by CarNetiq), matching
kk/legal/terms.html + kk/legal_pages.py.

Mirrors the lightweight pattern used by test_privacy_policy_page.py: a bare
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


def test_terms_returns_200_without_authentication():
    """No Authorization header, no session/cookies -- must still succeed."""
    resp = _client().get("/terms")
    assert resp.status_code == 200, resp.data


def test_terms_returns_html_not_json_or_pdf():
    resp = _client().get("/terms")
    content_type = resp.headers.get("Content-Type", "")
    assert "text/html" in content_type, content_type
    body = resp.get_data(as_text=True)
    assert "<!DOCTYPE html>" in body or "<!doctype html>" in body.lower()
    assert "<html" in body.lower()


def test_terms_page_identifies_carnet_and_carnetiq():
    resp = _client().get("/terms")
    body = resp.get_data(as_text=True)
    assert "CarNet" in body
    assert "CarNetiq" in body


def test_terms_page_has_effective_date_september_22_2026(monkeypatch):
    monkeypatch.setenv("LEGAL_EFFECTIVE_DATE", "September 22, 2026")
    resp = _client().get("/terms")
    body = resp.get_data(as_text=True)
    assert "Effective: September 22, 2026" in body


def test_terms_page_does_not_show_old_android_package_wording():
    """Old public Android/iOS package references must not leak onto the
    public Terms page (S/BRAND-01: only CarNet, no com.carzo.app)."""
    resp = _client().get("/terms")
    body = resp.get_data(as_text=True)
    assert "com.carzo.app" not in body
    assert "com.carnetiq.app" not in body


def test_terms_page_operator_is_carnetiq_by_default(monkeypatch):
    monkeypatch.delenv("LEGAL_OPERATOR_NAME", raising=False)
    resp = _client().get("/terms")
    body = resp.get_data(as_text=True)
    assert "Operator: CarNetiq" in body


def test_terms_page_get_only():
    """POST must not be treated as an alternate way to fetch the page (route
    is GET-only; this also documents current API behavior is unchanged)."""
    resp = _client().post("/terms")
    assert resp.status_code == 405
