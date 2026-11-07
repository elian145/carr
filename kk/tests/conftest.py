"""Shared pytest isolation for the backend suite (audit finding F-08).

Most test modules configure the Flask app by writing ``os.environ`` (APP_ENV,
DB_PATH, DATABASE_URL, SMS_PROVIDER, ...) and several of them only partially
undo it. Left alone, whatever one module forgets to clean up silently changes
the behaviour of every module collected after it, so results depended on test
order. This file adds three guard rails and nothing else; it never touches
production code and never changes an assertion.

1. Ambient ``DATABASE_URL`` / ``REDIS_URL`` are removed before collection so a
   developer's real (Neon/Redis) credentials can never be reached by the
   suite. Tests that need a database set their own (temp SQLite file, or an
   explicit disposable PostgreSQL opted in via ``CARNET_*_PG_URL``).
2. Every test module runs inside a snapshot/restore of ``os.environ`` and the
   current working directory, so a leak in one module cannot reach the next.
3. ``CARNET_REQUIRE_PG_TESTS=1`` (set by the CI PostgreSQL job) turns the
   "no PostgreSQL configured" skips into failures, so that job cannot be green
   without actually running the PostgreSQL-only tests.
"""

from __future__ import annotations

import os

import pytest

# (1) Never let ambient production-like connection strings leak into tests.
for _key in ("DATABASE_URL", "REDIS_URL"):
    os.environ.pop(_key, None)

# C-1 (socket resource caps): Flask-SocketIO test clients are almost never
# disconnected, so the production caps (kk/realtime_limits.py) would count
# every leaked client from earlier tests and refuse later ones. Lift them for
# the suite; the C-1 tests exercise the caps with explicit limits instead.
for _key in (
    "SOCKETIO_MAX_CONNECTIONS",
    "SOCKETIO_MAX_GUEST_CONNECTIONS",
    "SOCKETIO_MAX_GUESTS_PER_IP",
    "SOCKETIO_MAX_CONNECTIONS_PER_USER",
):
    os.environ.setdefault(_key, "1000000")
# ... and never start the idle sweeper (it would release long-lived test clients).
for _key in ("SOCKETIO_IDLE_RELEASE_SECONDS", "SOCKETIO_GUEST_IDLE_SECONDS"):
    os.environ.setdefault(_key, "0")

# Skip reasons emitted by the PostgreSQL-only modules when no server is wired.
_PG_SKIP_MARKERS = (
    "CARNET_PG_TEST_URL not set",
    "No disposable Postgres",
    "PHONE_INVENTORY_TEST_PG_URL not set",
)


@pytest.fixture(scope="module", autouse=True)
def _restore_process_state_per_module():
    """(2) Undo any os.environ / cwd changes a test module leaves behind."""
    saved_env = dict(os.environ)
    saved_cwd = os.getcwd()
    try:
        yield
    finally:
        os.environ.clear()
        os.environ.update(saved_env)
        try:
            os.chdir(saved_cwd)
        except OSError:
            pass


@pytest.hookimpl(hookwrapper=True)
def pytest_runtest_makereport(item, call):
    """(3) Fail (instead of skip) PostgreSQL-only tests when they are required."""
    outcome = yield
    if os.environ.get("CARNET_REQUIRE_PG_TESTS") != "1":
        return
    report = outcome.get_result()
    if not report.skipped or hasattr(report, "wasxfail"):
        return
    longrepr = report.longrepr
    reason = longrepr[2] if isinstance(longrepr, tuple) and len(longrepr) == 3 else str(longrepr)
    if any(marker in reason for marker in _PG_SKIP_MARKERS):
        report.outcome = "failed"
        report.longrepr = (
            "CARNET_REQUIRE_PG_TESTS=1 but a PostgreSQL-only test was skipped: " + reason
        )
