"""D-03: production SQLAlchemy engine / connection-pool configuration.

Proves that create_app()'s production-Postgres engine-options decision
(kk/app_factory.py: _apply_psycopg_driver + _production_postgres_engine_options)
actually activates SQLAlchemy's NullPool + pool_pre_ping for a real
production DATABASE_URL shape -- including the verified production shape,
Neon's "-pooler" pooled-endpoint hostname -- and does NOT activate it for
non-production environments or non-Postgres URLs.

These tests call the real, extracted decision functions directly (no
network I/O, no Flask app boot) rather than re-implementing the logic
inline, so they fail if the actual create_app() code path regresses.

Deliberately NOT covered here (by design, per the D-03 investigation):
QueuePool tuning, pool_size/max_overflow, or "fixing" the known bare
`postgres://` (no "ql") scheme gap -- see TestKnownBarePostgresSchemeGap
below, which documents that gap without fixing it.
"""
from __future__ import annotations

import sys
from pathlib import Path

from sqlalchemy.pool import NullPool

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from kk.app_factory import (  # noqa: E402
    _apply_psycopg_driver,
    _normalize_database_url,
    _production_postgres_engine_options,
)

# A realistic (fake credentials) Neon POOLED-endpoint connection string, in
# the exact shape Neon's dashboard gives you: "-pooler" in the hostname,
# sslmode already present. This is the verified current production shape.
_NEON_POOLED_URL = (
    "postgresql://fakeuser:fakepass@ep-cool-river-a1b2c3d4-pooler"
    ".us-east-2.aws.neon.tech/neondb?sslmode=require"
)

# Same logical endpoint, but the DIRECT (non-pooled) hostname -- no "-pooler".
# Included only to prove NullPool activation depends on the postgresql://
# prefix, not on pooled-vs-direct (that distinction is an architecture
# question tracked separately, not asserted here).
_NEON_DIRECT_URL = (
    "postgresql://fakeuser:fakepass@ep-cool-river-a1b2c3d4"
    ".us-east-2.aws.neon.tech/neondb?sslmode=require"
)

# Legacy short scheme (no "ql"). Known, NOT-fixed-here gap -- see the D-03
# investigation notes. Kept as a regression marker so nobody "fixes" the
# scheme rewrite silently without updating this test and the docs.
_BARE_POSTGRES_SCHEME_URL = "postgres://fakeuser:fakepass@example.com/db"


def _resolved_uri(raw_url: str) -> str:
    """Replicate exactly what create_app() does to a raw DATABASE_URL
    before computing SQLALCHEMY_DATABASE_URI."""
    return _apply_psycopg_driver(_normalize_database_url(raw_url))


class TestNullPoolActivatesInProduction:
    def test_generic_postgresql_url_activates_nullpool_and_pre_ping(self):
        uri = _resolved_uri("postgresql://fakeuser:fakepass@db.example.com:5432/fakedb")
        opts = _production_postgres_engine_options("production", uri.lower())
        assert opts is not None
        assert opts["poolclass"] is NullPool
        assert opts["pool_pre_ping"] is True

    def test_neon_pooler_hostname_activates_nullpool_and_pre_ping(self):
        """The exact verified production shape: Neon's `-pooler` endpoint."""
        uri = _resolved_uri(_NEON_POOLED_URL)
        # Guard the fixture itself: this must actually model a pooled
        # endpoint, or the test below would pass for the wrong reason.
        assert "-pooler" in uri

        opts = _production_postgres_engine_options("production", uri.lower())
        assert opts is not None
        assert opts["poolclass"] is NullPool
        assert opts["pool_pre_ping"] is True

    def test_neon_direct_hostname_also_resolves_the_postgresql_dialect(self):
        uri = _resolved_uri(_NEON_DIRECT_URL)
        assert "-pooler" not in uri
        opts = _production_postgres_engine_options("production", uri.lower())
        assert opts is not None
        assert opts["poolclass"] is NullPool
        assert opts["pool_pre_ping"] is True

    def test_psycopg_v3_driver_is_selected_for_the_neon_pooled_url(self):
        """D-03 also depends on the psycopg v3 driver rewrite firing for
        this URL shape (kk/requirements.txt has psycopg, not psycopg2)."""
        uri = _resolved_uri(_NEON_POOLED_URL)
        assert uri.startswith("postgresql+psycopg://")

    def test_neon_sslmode_is_preserved_not_duplicated(self):
        uri = _resolved_uri(_NEON_POOLED_URL)
        assert uri.count("sslmode=") == 1

    def test_existing_engine_options_are_preserved_not_clobbered(self):
        uri = _resolved_uri(_NEON_POOLED_URL)
        opts = _production_postgres_engine_options(
            "production", uri.lower(), existing_options={"echo": True}
        )
        assert opts is not None
        assert opts["echo"] is True
        assert opts["poolclass"] is NullPool
        assert opts["pool_pre_ping"] is True

    def test_explicit_engine_options_are_not_overridden(self):
        """setdefault() semantics: an explicitly-configured poolclass or
        pool_pre_ping must win over the D-03 default, not be clobbered."""
        uri = _resolved_uri(_NEON_POOLED_URL)
        opts = _production_postgres_engine_options(
            "production",
            uri.lower(),
            existing_options={"pool_pre_ping": False},
        )
        assert opts is not None
        assert opts["pool_pre_ping"] is False


class TestNullPoolDoesNotActivateOutsideProduction:
    def test_development_env_does_not_activate_nullpool(self):
        uri = _resolved_uri(_NEON_POOLED_URL)
        assert _production_postgres_engine_options("development", uri.lower()) is None

    def test_testing_env_does_not_activate_nullpool(self):
        uri = _resolved_uri(_NEON_POOLED_URL)
        assert _production_postgres_engine_options("testing", uri.lower()) is None

    def test_sqlite_url_in_production_does_not_activate_nullpool(self):
        opts = _production_postgres_engine_options(
            "production", "sqlite:///car_listings.db"
        )
        assert opts is None


class TestKnownBarePostgresSchemeGap:
    """Documents a known, NOT-fixed-by-D-03 gap (see the D-03 investigation
    notes): a literal `postgres://` (no "ql") DATABASE_URL is never
    rewritten to `postgresql://`, so it never activates NullPool here.
    Separately (outside the scope of these pure functions),
    Flask-SQLAlchemy's db.init_app() would raise NoSuchModuleError for such
    a URL -- this test only pins the NullPool-activation half.

    This test is intentionally a "known gap" pin, not a correctness
    assertion: if it starts failing because someone added the
    postgres:// -> postgresql:// rewrite, that's a real, deliberate fix --
    update this docstring instead of just deleting the test.
    """

    def test_bare_postgres_scheme_does_not_activate_nullpool(self):
        uri = _resolved_uri(_BARE_POSTGRES_SCHEME_URL)
        opts = _production_postgres_engine_options("production", uri.lower())
        assert opts is None, (
            "postgres:// (no 'ql') is not rewritten to postgresql:// and "
            "therefore does not activate NullPool -- this is a known, "
            "tracked gap, not something D-03 fixes."
        )
