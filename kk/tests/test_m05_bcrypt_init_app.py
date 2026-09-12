"""M-05 regression tests: the shared Flask-Bcrypt singleton (``kk.models.bcrypt``)
must be initialized with ``bcrypt.init_app(app)`` inside ``create_app()`` so that
``BCRYPT_LOG_ROUNDS`` (configured in ``kk/config.py``) actually drives the bcrypt
cost factor used to hash new passwords, instead of Flask-Bcrypt silently falling
back to its own hardcoded library defaults.

Bug (PRODUCTION_AUDIT.md M-05): ``bcrypt = Bcrypt()`` in ``kk/models.py`` was
never wired up via ``bcrypt.init_app(app)`` anywhere in ``kk/app_factory.py``.
The configured ``BCRYPT_LOG_ROUNDS = 12`` therefore had zero effect at runtime
-- the actual work factor used (12) matched only by coincidence with
Flask-Bcrypt 1.0.1's own hardcoded ``_log_rounds = 12`` class default.

The wiring-sensitive tests below deliberately override ``BCRYPT_LOG_ROUNDS`` to
a value that cannot coincidentally match Flask-Bcrypt's own hardcoded default
(6, and separately 4), create a real app via the real ``create_app()`` factory,
and assert that a freshly generated password hash actually carries the
overridden cost segment (e.g. ``$06$``). These tests FAIL against the pre-fix
code (the hash would still be ``$12$``, Flask-Bcrypt's own default, regardless
of the config override) and PASS once ``bcrypt.init_app(app)`` is wired into
``create_app()``.

A separate set of tests confirms existing ``$2b$12$`` hashes still verify
correctly for both ``User`` and ``AdminAccount`` after the wiring change.
"""

from __future__ import annotations

import os
import sys
import tempfile
import uuid
from pathlib import Path

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))


def _make_app(tmp_dir_name: str, *, bcrypt_log_rounds: int | None = None):
    """Build a fresh app via the real ``create_app()`` factory.

    When ``bcrypt_log_rounds`` is given, ``kk.config.Config.BCRYPT_LOG_ROUNDS``
    is monkeypatched to that value for the duration of the call (restored
    immediately after) so ``app.config.from_object(...)`` picks it up exactly
    the way a real deployment's config would. This proves the value is read
    at app-creation time, not just that generate_password_hash() works.
    """
    import kk.config as config_module

    original_rounds = config_module.Config.BCRYPT_LOG_ROUNDS
    if bcrypt_log_rounds is not None:
        config_module.Config.BCRYPT_LOG_ROUNDS = bcrypt_log_rounds
    try:
        os.environ["APP_ENV"] = "testing"
        os.environ["SMS_PROVIDER"] = "console"
        os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
        os.environ["DB_PATH"] = os.path.join(
            tmp_dir_name, f"m05_{uuid.uuid4().hex[:8]}.db"
        )

        from kk.app_factory import create_app

        app, _socketio, *_ = create_app()
        from kk.models import db as _db

        with app.app_context():
            _db.drop_all()
            _db.create_all()
        return app
    finally:
        config_module.Config.BCRYPT_LOG_ROUNDS = original_rounds


@pytest.fixture
def tmp_dir():
    d = tempfile.TemporaryDirectory(prefix="carlist_m05_", ignore_cleanup_errors=True)
    yield d.name
    d.cleanup()


@pytest.fixture(autouse=True)
def _restore_shared_bcrypt_singleton():
    """``kk.models.bcrypt`` is a process-wide singleton shared by every app
    instance created in this test session, including other test modules'
    apps that may run before/after this file. Snapshot/restore its private
    state around every test in this file so the deliberate cost-factor
    overrides used here can never leak into other tests.
    """
    from kk.models import bcrypt as shared_bcrypt

    prev_rounds = shared_bcrypt._log_rounds
    prev_prefix = shared_bcrypt._prefix
    prev_long = shared_bcrypt._handle_long_passwords
    try:
        yield
    finally:
        shared_bcrypt._log_rounds = prev_rounds
        shared_bcrypt._prefix = prev_prefix
        shared_bcrypt._handle_long_passwords = prev_long


class TestBcryptConfigIsWired:
    """Proves ``bcrypt.init_app(app)`` is actually called by ``create_app()``,
    i.e. that ``BCRYPT_LOG_ROUNDS`` is no longer dead configuration."""

    def test_overridden_log_rounds_changes_generated_hash_cost(self, tmp_dir):
        app = _make_app(tmp_dir, bcrypt_log_rounds=6)
        from kk.models import bcrypt as shared_bcrypt

        assert app.config["BCRYPT_LOG_ROUNDS"] == 6

        with app.app_context():
            new_hash = shared_bcrypt.generate_password_hash(
                "Probe-Password-1!"
            ).decode("utf-8")

        # bcrypt hash format: $<version>$<cost>$<salt+digest>
        cost_segment = new_hash.split("$")[2]
        assert cost_segment == "06", (
            "Expected the overridden BCRYPT_LOG_ROUNDS=6 to produce a "
            f"'$06$' cost segment, got hash {new_hash!r} (cost {cost_segment!r}). "
            "This means app.config['BCRYPT_LOG_ROUNDS'] is NOT wired into "
            "the shared bcrypt instance -- bcrypt.init_app(app) is missing "
            "from kk/app_factory.py::create_app()."
        )

    def test_create_app_updates_shared_singleton_state(self, tmp_dir):
        """Minimal initialization/smoke assertion that create_app() actually
        initializes the shared bcrypt singleton's internal state (not just
        that hashing happens to still work). Uses 4, a value that cannot
        coincidentally match Flask-Bcrypt's own hardcoded default (12)."""
        from kk.models import bcrypt as shared_bcrypt

        _make_app(tmp_dir, bcrypt_log_rounds=4)
        assert shared_bcrypt._log_rounds == 4, (
            "kk.models.bcrypt._log_rounds was not updated by create_app() -- "
            "bcrypt.init_app(app) was not called."
        )

    def test_default_config_still_produces_cost_12(self, tmp_dir):
        """Sanity check: without an override, production's configured
        BCRYPT_LOG_ROUNDS = 12 is what actually gets used (unchanged
        observable behavior for the real deployed config value)."""
        app = _make_app(tmp_dir)
        from kk.models import bcrypt as shared_bcrypt

        assert app.config["BCRYPT_LOG_ROUNDS"] == 12
        with app.app_context():
            new_hash = shared_bcrypt.generate_password_hash(
                "Probe-Password-2!"
            ).decode("utf-8")
        assert new_hash.split("$")[2] == "12"


class TestExistingHashesStillVerify:
    """Confirms wiring the singleton did not break verification of
    already-stored $2b$12$-style hashes for either password-owning model."""

    def test_user_password_round_trip(self, tmp_dir):
        app = _make_app(tmp_dir)
        from kk.models import User, db as _db

        with app.app_context():
            user = User(
                username=f"m05_user_{uuid.uuid4().hex[:8]}",
                phone_number=f"+1555{uuid.uuid4().int % 10_000_000:07d}",
                first_name="M05",
                last_name="User",
                is_active=True,
                is_verified=True,
                phone_verified=True,
                public_id=f"pub-{uuid.uuid4().hex[:12]}",
            )
            user.set_password("Correct-Horse-1!")
            _db.session.add(user)
            _db.session.commit()

            assert user.password_hash.startswith("$2b$12$")
            assert user.check_password("Correct-Horse-1!") is True
            assert user.check_password("wrong-password") is False

    def test_admin_account_password_round_trip(self, tmp_dir):
        app = _make_app(tmp_dir)
        from kk.models import AdminAccount, User, db as _db

        with app.app_context():
            principal = User(
                username=f"m05_principal_{uuid.uuid4().hex[:8]}",
                phone_number=f"+1555{uuid.uuid4().int % 10_000_000:07d}",
                first_name="M05",
                last_name="Principal",
                is_active=True,
                is_verified=True,
                phone_verified=True,
                public_id=f"pub-{uuid.uuid4().hex[:12]}",
            )
            principal.set_password("Principal-Placeholder-1!")
            _db.session.add(principal)
            _db.session.commit()

            admin = AdminAccount(
                principal_user_id=principal.id,
                username=f"m05_admin_{uuid.uuid4().hex[:8]}",
                password_hash="placeholder",
                admin_role="super_admin",
            )
            admin.set_password("Admin-Horse-1!")
            _db.session.add(admin)
            _db.session.commit()

            assert admin.password_hash.startswith("$2b$12$")
            assert admin.check_password("Admin-Horse-1!") is True
            assert admin.check_password("wrong-password") is False


class TestUnrelatedBcryptConfigUntouched:
    """Guards against accidental scope creep: BCRYPT_HASH_PREFIX and
    BCRYPT_HANDLE_LONG_PASSWORDS remain unset/default even after wiring."""

    def test_prefix_and_long_password_handling_stay_default(self, tmp_dir):
        app = _make_app(tmp_dir)
        from kk.models import bcrypt as shared_bcrypt

        assert app.config.get("BCRYPT_HASH_PREFIX") is None
        assert app.config.get("BCRYPT_HANDLE_LONG_PASSWORDS") is None
        assert shared_bcrypt._prefix == "2b"
        assert shared_bcrypt._handle_long_passwords is False
