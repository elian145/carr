"""SUPPORT_EMAIL: single support/contact email source, required in production,
with NO hardcoded fake fallback (support@carzo.app / support@carnetiq.app).

Mirrors the setup/teardown pattern used by
``kk/tests/test_c10_chat_media_privacy.py::TestChatMediaConfigValidation``.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

_FAKE_ADDRESSES = ("support@carzo.app", "support@carnetiq.app")

# Other production-required secrets validate_required_secrets() checks --
# kept present+valid so SUPPORT_EMAIL is isolated as the only variable under
# test (see kk/config.py::validate_required_secrets).
_OTHER_REQUIRED_SECRETS = {
    "SECRET_KEY": "a-strong-production-secret",
    "JWT_SECRET_KEY": "a-strong-production-jwt-secret",
    "DATABASE_URL": "postgresql://user:pass@host/db",
}

_ENV_KEYS = (
    "SUPPORT_EMAIL",
    "SECRET_KEY",
    "JWT_SECRET_KEY",
    "DATABASE_URL",
    "REDIS_URL",
    "ALLOW_INMEMORY_RATE_LIMITS",
    "ALLOW_EPHEMERAL_UPLOADS",
    "R2_ACCOUNT_ID",
    "R2_BUCKET_NAME",
    "R2_ACCESS_KEY_ID",
    "R2_SECRET_ACCESS_KEY",
    "R2_PUBLIC_URL",
    "UPLOAD_FOLDER",
    "R2_CHAT_BUCKET_NAME",
    "R2_CHAT_ACCESS_KEY_ID",
    "R2_CHAT_SECRET_ACCESS_KEY",
)


class TestSupportEmailProductionValidation:
    def setup_method(self):
        self._saved = {k: os.environ.get(k) for k in _ENV_KEYS}
        for k in self._saved:
            os.environ.pop(k, None)
        os.environ.update(_OTHER_REQUIRED_SECRETS)
        # Make the *other* production validators (upload persistence, chat
        # media, redis) pass-through so only SUPPORT_EMAIL is under test.
        os.environ["ALLOW_EPHEMERAL_UPLOADS"] = "1"
        os.environ["ALLOW_INMEMORY_RATE_LIMITS"] = "1"

    def teardown_method(self):
        for k, v in self._saved.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v

    def test_missing_support_email_fails_production_boot(self):
        """No SUPPORT_EMAIL in production must raise clearly -- never fall
        back to a fake mailbox."""
        from kk.config import validate_required_secrets

        os.environ.pop("SUPPORT_EMAIL", None)
        with pytest.raises(RuntimeError, match="SUPPORT_EMAIL"):
            validate_required_secrets("production")

    def test_blank_support_email_fails_production_boot(self):
        from kk.config import validate_required_secrets

        os.environ["SUPPORT_EMAIL"] = "   "
        with pytest.raises(RuntimeError, match="SUPPORT_EMAIL"):
            validate_required_secrets("production")

    def test_configured_support_email_boots_cleanly(self):
        from kk.config import validate_required_secrets

        os.environ["SUPPORT_EMAIL"] = "carzo@mycarzoiq.com"
        validate_required_secrets("production")  # must not raise

    def test_missing_support_email_skipped_outside_production(self):
        """development/testing must NOT require SUPPORT_EMAIL (matches the
        existing SECRET_KEY/JWT_SECRET_KEY/DATABASE_URL behavior)."""
        from kk.config import validate_required_secrets

        os.environ.pop("SUPPORT_EMAIL", None)
        validate_required_secrets("development")  # must not raise
        validate_required_secrets("testing")  # must not raise


class TestSupportEmailNoFakeFallback:
    def setup_method(self):
        self._saved = os.environ.get("SUPPORT_EMAIL")
        os.environ.pop("SUPPORT_EMAIL", None)

    def teardown_method(self):
        if self._saved is None:
            os.environ.pop("SUPPORT_EMAIL", None)
        else:
            os.environ["SUPPORT_EMAIL"] = self._saved

    def test_default_platform_settings_support_email_is_blank_not_fake(self):
        from kk.app_settings import default_platform_settings

        value = default_platform_settings()["support_email"]
        assert value == ""
        for fake in _FAKE_ADDRESSES:
            assert value != fake

    def test_legal_pages_support_email_is_blank_not_fake_when_unset(self):
        from kk.legal_pages import _support_email

        value = _support_email()
        for fake in _FAKE_ADDRESSES:
            assert value != fake

    def test_legal_pages_support_email_reflects_env_when_set(self):
        from kk.legal_pages import _support_email

        os.environ["SUPPORT_EMAIL"] = "carzo@mycarzoiq.com"
        assert _support_email() == "carzo@mycarzoiq.com"

    def test_trust_config_payload_has_no_fake_fallback(self):
        from kk.routes.misc import _trust_config_payload

        payload = _trust_config_payload()
        for fake in _FAKE_ADDRESSES:
            assert payload.get("support_email") != fake

    def test_trust_config_payload_reflects_env_when_set(self):
        from kk.routes.misc import _trust_config_payload

        os.environ["SUPPORT_EMAIL"] = "carzo@mycarzoiq.com"
        payload = _trust_config_payload()
        assert payload.get("support_email") == "carzo@mycarzoiq.com"


def test_no_fake_support_addresses_anywhere_in_backend_source():
    """Static guard: the retired support@carzo.app / support@carnetiq.app
    addresses must not appear as live code (a documentation comment
    explicitly telling developers not to use them is fine)."""
    backend_dir = _REPO_ROOT / "kk"
    offenders: list[str] = []
    for path in backend_dir.rglob("*.py"):
        if "tests" in path.parts or "__pycache__" in path.parts:
            continue
        text = path.read_text(encoding="utf-8", errors="ignore")
        for fake in _FAKE_ADDRESSES:
            if fake in text:
                offenders.append(f"{path}: {fake}")
    assert not offenders, f"Fake support address(es) found: {offenders}"
