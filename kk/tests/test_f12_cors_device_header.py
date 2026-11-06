"""F-12: browser (web/admin) origins may send ``X-Device-Id``.

``kk/app_factory.py`` calls ``CORS(app, origins=...)`` without ``allow_headers``;
flask-cors then defaults to ``allow_headers='*'`` and reflects the headers named
in ``Access-Control-Request-Headers``. This test pins that behaviour so a future
tightening of the CORS config (an explicit header allow-list) cannot silently
make the preflight for ``X-Device-Id`` fail in browsers, and checks that the
allow-list of ORIGINS still applies (no wildcard opening).
"""

from __future__ import annotations

import os
import sys
import tempfile
from pathlib import Path

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

_ALLOWED = "https://admin.carnet.example"


@pytest.fixture(scope="module")
def client():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_f12cors_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ["DB_PATH"] = os.path.join(tmp.name, "f12cors.db")
    os.environ["CORS_ORIGINS"] = _ALLOWED

    from kk.app_factory import create_app

    app, *_ = create_app()
    yield app.test_client()
    tmp.cleanup()


def _preflight(client, origin, headers):
    return client.options(
        "/api/auth/login",
        headers={
            "Origin": origin,
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": headers,
        },
    )


def test_preflight_allows_x_device_id_for_the_admin_origin(client):
    resp = _preflight(client, _ALLOWED, "content-type, x-device-id, authorization")
    assert resp.status_code in (200, 204)
    assert resp.headers.get("Access-Control-Allow-Origin") == _ALLOWED
    allowed = (resp.headers.get("Access-Control-Allow-Headers") or "").lower()
    assert "*" in allowed or "x-device-id" in allowed


def test_unlisted_origin_is_still_not_allowed(client):
    resp = _preflight(client, "https://evil.example", "x-device-id")
    assert resp.headers.get("Access-Control-Allow-Origin") in (None, "")
