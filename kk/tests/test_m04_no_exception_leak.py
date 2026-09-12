"""M-04 regression tests: internal exception text must never reach the
client on ``GET /api/cars`` (``get_cars``) or ``GET /cars``
(``get_cars_alias``).

Bug (PRODUCTION_AUDIT.md M-04): both routes' outer ``except Exception as e``
handler returned ``f"Failed to get cars: {str(e)}"`` directly to the caller.
Because both routes are public and unauthenticated, any internal exception
raised while building the listing (a DB connectivity/auth failure, an
unexpected driver error, a schema issue, etc.) had its raw ``str(e)`` text
-- which can contain hostnames, ports, credentials-adjacent driver messages,
SQL fragments, or other internals -- echoed verbatim to an anonymous client.

The fix reuses the pre-existing, already-tested ``_listing_db_error_response``
helper (already used by ``create_car``/``update_car``/``delete_car``) so both
routes now roll back, log the real exception server-side, and return only a
generic ``{"message": "Failed to get cars"}`` body.

These tests force a fabricated, sensitive-looking exception via
``unittest.mock.patch`` on an internal helper (``_with_media_compat``) that
both routes call while rendering a non-empty result set, and assert:

- the client still receives HTTP 500
- the response body is exactly the new generic message
- none of the injected "sensitive" substrings appear anywhere in the
  response body
- the real exception is still captured server-side via logging (i.e. the
  fix only changes the client-facing response, not observability)

The auth.py signup exception-leak path (M-04's other named location) is
already fixed and covered by the pre-existing
``kk/tests/test_signup_otp_required.py``; it is intentionally not touched or
re-tested here.
"""

from __future__ import annotations

import logging
import os
import sys
import tempfile
import uuid
from pathlib import Path
from unittest import mock

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

# Fabricated, sensitive-looking exception text. None of these substrings may
# ever reach the client.
_LEAK_SUBSTRINGS = (
    "internal-db-host.prod.local",
    "password authentication failed",
    "secret-schema-fragment",
)
_FAKE_EXC = RuntimeError(
    'connection to server at "internal-db-host.prod.local" (10.0.4.12), '
    'port 5432 failed: FATAL: password authentication failed for user '
    '"carr_app" while reading secret-schema-fragment'
)

_GENERIC_MESSAGE = "Failed to get cars"


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(
        prefix="carlist_m04_", ignore_cleanup_errors=True
    )
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "m04.db")

    from kk.app_factory import create_app

    app, _socketio, *_ = create_app()
    from kk.models import Car, User, db

    with app.app_context():
        db.drop_all()
        db.create_all()

    # Test-harness-only accommodation (NOT a production change, same as the
    # pre-existing BE-10 test suite): on a fresh DB, `create_app()`'s
    # auto-migrate path runs `flask_migrate.upgrade()`, whose
    # `migrations/env.py` calls `logging.config.fileConfig(...)` with its
    # default `disable_existing_loggers=True`. That disables the
    # already-created Flask `app.logger` ("kk.app_factory") as an incidental
    # side effect, unrelated to M-04. Undo it here so these tests observe
    # the real behavior of the `current_app.logger.exception(...)` call
    # inside `_listing_db_error_response` this suite exists to verify.
    app.logger.disabled = False

    yield app, app.test_client(), db, User, Car

    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    tmp.cleanup()


@pytest.fixture(scope="module")
def seeded_car(app_ctx):
    """At least one active, public listing so both routes reach the
    per-row ``_with_media_compat`` call where the exception is injected."""
    app, _client, db, User, Car = app_ctx
    with app.app_context():
        seller = User(
            username=f"m04_seller_{uuid.uuid4().hex[:8]}",
            phone_number=f"+1555{uuid.uuid4().int % 10_000_000:07d}",
            first_name="M04",
            last_name="Seller",
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id=f"pub-{uuid.uuid4().hex[:12]}",
        )
        seller.set_password("Aa123456!")
        db.session.add(seller)
        db.session.commit()

        car = Car(
            seller_id=seller.id,
            title="M04 Probe Car",
            brand="Toyota",
            model="Corolla",
            trim="base",
            year=2020,
            mileage=10000,
            engine_type="gas",
            transmission="auto",
            drive_type="fwd",
            condition="used",
            body_type="sedan",
            price=10000,
            location="Erbil",
            is_active=True,
            status="active",
        )
        db.session.add(car)
        db.session.commit()
        return car.id


class _CaptureHandler(logging.Handler):
    """Collects log records so tests can assert an exception was logged
    server-side, mirroring `kk/tests/test_be10_route_exception_logging.py`."""

    def __init__(self):
        super().__init__(level=logging.DEBUG)
        self.records: list[logging.LogRecord] = []

    def emit(self, record: logging.LogRecord) -> None:
        self.records.append(record)

    def has_exception_record(self) -> bool:
        return any(r.exc_info is not None for r in self.records)

    def exception_text(self) -> str:
        parts = []
        for r in self.records:
            parts.append(r.getMessage())
            if r.exc_info and r.exc_info[1] is not None:
                parts.append(str(r.exc_info[1]))
        return "\n".join(parts)


@pytest.fixture
def log_capture():
    handler = _CaptureHandler()
    root = logging.getLogger()
    prev_level = root.level
    root.addHandler(handler)
    root.setLevel(logging.DEBUG)
    try:
        yield handler
    finally:
        root.removeHandler(handler)
        root.setLevel(prev_level)


def _assert_no_leak(body_text: str) -> None:
    for substring in _LEAK_SUBSTRINGS:
        assert substring not in body_text, (
            f"Leaked internal exception text found in response: {substring!r}"
        )


class TestGetCarsNoExceptionLeak:
    """GET /api/cars (get_cars)."""

    def test_forced_exception_returns_generic_500(
        self, app_ctx, seeded_car, log_capture
    ):
        _app, client, _db, _User, _Car = app_ctx
        import kk.routes.cars as cars_mod

        log_capture.records.clear()
        with mock.patch.object(
            cars_mod, "_with_media_compat", side_effect=_FAKE_EXC
        ):
            response = client.get("/api/cars")

        assert response.status_code == 500, response.data
        body = response.get_json() or {}
        assert body.get("message") == _GENERIC_MESSAGE
        _assert_no_leak(response.get_data(as_text=True))

        # The real exception must still be captured server-side (logging is
        # unaffected by the fix -- only the client-facing body changed).
        assert log_capture.has_exception_record()
        assert "password authentication failed" in log_capture.exception_text()


class TestGetCarsAliasNoExceptionLeak:
    """GET /cars (get_cars_alias)."""

    def test_forced_exception_returns_generic_500(
        self, app_ctx, seeded_car, log_capture
    ):
        _app, client, _db, _User, _Car = app_ctx
        import kk.routes.cars as cars_mod

        log_capture.records.clear()
        with mock.patch.object(
            cars_mod, "_with_media_compat", side_effect=_FAKE_EXC
        ):
            response = client.get("/cars")

        assert response.status_code == 500, response.data
        body = response.get_json() or {}
        assert body.get("message") == _GENERIC_MESSAGE
        _assert_no_leak(response.get_data(as_text=True))

        assert log_capture.has_exception_record()
        assert "password authentication failed" in log_capture.exception_text()


class TestGetCarsAliasSingleCarNoExceptionLeak:
    """GET /cars?id=<id> (get_cars_alias' single-car branch) shares the same
    outer ``except Exception`` and must not leak either."""

    def test_forced_exception_on_single_car_lookup_returns_generic_500(
        self, app_ctx, seeded_car
    ):
        _app, client, _db, _User, _Car = app_ctx
        import kk.routes.cars as cars_mod

        with mock.patch.object(
            cars_mod, "_with_media_compat", side_effect=_FAKE_EXC
        ):
            response = client.get(f"/cars?id={seeded_car}")

        assert response.status_code == 500, response.data
        body = response.get_json() or {}
        assert body.get("message") == _GENERIC_MESSAGE
        _assert_no_leak(response.get_data(as_text=True))


class TestSuccessPathsUnaffected:
    """Sanity check that the fix did not touch success-path behavior,
    status codes, or response shapes."""

    def test_get_cars_success_shape_unchanged(self, app_ctx, seeded_car):
        _app, client, _db, _User, _Car = app_ctx
        response = client.get("/api/cars")
        assert response.status_code == 200
        body = response.get_json() or {}
        assert "cars" in body
        assert "pagination" in body
        assert isinstance(body["cars"], list)

    def test_get_cars_alias_success_shape_unchanged(self, app_ctx, seeded_car):
        _app, client, _db, _User, _Car = app_ctx
        response = client.get("/cars")
        assert response.status_code == 200
        body = response.get_json()
        assert isinstance(body, list)
