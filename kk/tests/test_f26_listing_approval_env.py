"""F-26: listing_require_approval() must agree with get_app_env()."""

from __future__ import annotations

import pytest

from kk.config import get_app_env
from kk.listing_moderation import listing_require_approval


def _clear(monkeypatch):
    for k in ("APP_ENV", "FLASK_ENV", "LISTING_REQUIRE_APPROVAL"):
        monkeypatch.delenv(k, raising=False)


def test_unset_env_is_production_and_requires_approval(monkeypatch):
    _clear(monkeypatch)
    assert get_app_env() == "production"
    assert listing_require_approval() is True


@pytest.mark.parametrize("env,expected", [
    ("production", True), ("development", False), ("testing", False),
])
def test_app_env_default(monkeypatch, env, expected):
    _clear(monkeypatch)
    monkeypatch.setenv("APP_ENV", env)
    assert listing_require_approval() is expected


def test_legacy_flask_env_fallback(monkeypatch):
    _clear(monkeypatch)
    monkeypatch.setenv("FLASK_ENV", "development")
    assert listing_require_approval() is False


@pytest.mark.parametrize("val,expected", [("0", False), ("off", False), ("1", True), ("yes", True)])
def test_explicit_flag_wins(monkeypatch, val, expected):
    _clear(monkeypatch)
    monkeypatch.setenv("LISTING_REQUIRE_APPROVAL", val)
    assert listing_require_approval() is expected
    monkeypatch.setenv("APP_ENV", "development")
    assert listing_require_approval() is expected
