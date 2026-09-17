"""A-03 regression tests.

PRODUCTION_AUDIT.md A-03 (MEDIUM): "No blueprint URL prefixes... Route
collisions are possible and undetectable." Archaeology (2026-09-17) found
the audit's literal "all 13 blueprints have no prefix" claim stale
(``kk/routes/admin.py`` already uses ``url_prefix="/api/admin"``), but
confirmed a concrete, currently-existing route collision:

  - Flask auto-registers a built-in ``static`` endpoint for
    ``/static/<path:filename>`` whenever ``static_folder`` is left at its
    default (as ``kk/app_factory.py::create_app()`` did).
  - ``kk/routes/misc.py`` also registers ``/static/<path:filename>`` as
    ``misc.static_files``, whose whole purpose is to additionally serve
    ``UPLOAD_FOLDER``-backed persistent-disk uploads (e.g. a Render disk
    mounted outside ``kk/static`` -- see ``kk/docs/UPLOAD_PERSISTENCE.md``
    "Option B") and a repo-root ``static/`` fallback.
  - Because both rules matched the exact same ``(rule, method)`` pair,
    Flask's built-in handler silently won every match, making
    ``misc.static_files()`` (and its ``UPLOAD_FOLDER`` fallback) dead code.
    Production currently uses R2 (not disk mode), so this was dormant, not
    actively firing -- but it would silently 404 real listing photos the
    moment an operator followed the repo's own documented disk-mode setup.

Fix: ``kk/app_factory.py`` now constructs ``Flask(__name__, static_folder=None)``
so Flask never registers its own competing ``static`` endpoint. The public
URL (``/static/<path:filename>``) is unchanged; only which handler serves it
changes.

These tests use the real ``create_app()`` factory (per repo test convention --
see e.g. ``kk/tests/test_m05_bcrypt_init_app.py``, ``test_m06_image_cap_and_pixel_bomb.py``)
and only temporary directories/files; nothing is written into the repository.
"""

from __future__ import annotations

import os
import tempfile
import uuid

import pytest


def _make_app(tmp_dir_name: str, *, upload_folder: str | None):
    """Build a fresh app via the real ``create_app()`` factory.

    Mirrors the fixture pattern used by ``test_m05_bcrypt_init_app.py`` /
    ``test_m06_image_cap_and_pixel_bomb.py``: real env vars, real
    ``create_app()``, a throwaway SQLite DB under a temp dir.
    """
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp_dir_name, f"a03_{uuid.uuid4().hex[:8]}.db")
    if upload_folder is not None:
        os.environ["UPLOAD_FOLDER"] = upload_folder
    else:
        os.environ.pop("UPLOAD_FOLDER", None)

    from kk.app_factory import create_app

    app, _socketio, *_ = create_app()
    return app


@pytest.fixture
def tmp_dir():
    d = tempfile.TemporaryDirectory(prefix="carlist_a03_", ignore_cleanup_errors=True)
    yield d.name
    d.cleanup()


class TestNoDuplicateUrlMapRules:
    """A. The real create_app() URL map must contain no duplicate
    (rule, method) pairs -- i.e. no two endpoints (built-in or blueprint)
    silently shadow each other for the same path."""

    def test_url_map_has_no_duplicate_rule_method_pairs(self, tmp_dir):
        app = _make_app(tmp_dir, upload_folder=None)

        seen: dict[tuple[str, str], list[str]] = {}
        for rule in app.url_map.iter_rules():
            for method in rule.methods - {"HEAD", "OPTIONS"}:
                seen.setdefault((rule.rule, method), []).append(rule.endpoint)

        duplicates = {key: endpoints for key, endpoints in seen.items() if len(endpoints) > 1}
        assert duplicates == {}, (
            "Found duplicate (rule, method) registrations -- one endpoint "
            f"silently shadows another: {duplicates}"
        )

    def test_static_rule_registered_exactly_once(self, tmp_dir):
        """Specifically pin the A-03 collision: exactly one rule handles
        GET /static/<path:filename>, and it is misc.static_files, not
        Flask's built-in `static` endpoint."""
        app = _make_app(tmp_dir, upload_folder=None)

        static_rules = [r for r in app.url_map.iter_rules() if r.rule == "/static/<path:filename>"]
        assert len(static_rules) == 1, (
            "Expected exactly one rule for /static/<path:filename>, found "
            f"{len(static_rules)}: {[r.endpoint for r in static_rules]}"
        )
        assert static_rules[0].endpoint == "misc.static_files"

        # Flask's own built-in `static` endpoint must not exist at all now
        # that static_folder=None is passed to Flask(__name__, ...).
        endpoint_names = {r.endpoint for r in app.url_map.iter_rules()}
        assert "static" not in endpoint_names, (
            "Flask's built-in `static` endpoint is still registered; "
            "static_folder=None should have removed it."
        )


class TestCustomStaticHandlerIsAuthoritative:
    """B. The custom misc.static_files route is actually the one Flask
    dispatches to for /static/<path:filename>."""

    def test_url_map_match_resolves_to_misc_static_files(self, tmp_dir):
        app = _make_app(tmp_dir, upload_folder=None)

        adapter = app.url_map.bind("localhost")
        endpoint, _args = adapter.match("/static/somefile.txt", method="GET")
        assert endpoint == "misc.static_files"


class TestUploadFolderOutsideStaticIsServable:
    """C. A file located outside kk/static, under a temporary UPLOAD_FOLDER,
    can be requested through the /static/... route and returns the expected
    content. This is exactly the documented persistent-disk (Render disk)
    upload-serving path from kk/docs/UPLOAD_PERSISTENCE.md Option B, which
    was silently unreachable before the static_folder=None fix."""

    def test_file_outside_kk_static_served_via_static_route(self, tmp_dir):
        upload_root = os.path.join(tmp_dir, "persistent-disk-uploads")
        app = _make_app(tmp_dir, upload_folder=upload_root)

        # create_app() must have resolved UPLOAD_FOLDER to this absolute,
        # outside-kk/static temp path (sanity check on the fixture itself).
        assert app.config["UPLOAD_FOLDER"] == os.path.abspath(upload_root)
        kk_static_dir = os.path.join(app.root_path, "static")
        assert not app.config["UPLOAD_FOLDER"].startswith(os.path.abspath(kk_static_dir))

        # create_app() already created car_photos/ under UPLOAD_FOLDER.
        car_photos_dir = os.path.join(app.config["UPLOAD_FOLDER"], "car_photos")
        assert os.path.isdir(car_photos_dir)

        filename = f"a03_probe_{uuid.uuid4().hex[:8]}.jpg"
        expected_bytes = b"not-a-real-jpeg-just-a-probe-payload"
        with open(os.path.join(car_photos_dir, filename), "wb") as f:
            f.write(expected_bytes)

        client = app.test_client()
        resp = client.get(f"/static/uploads/car_photos/{filename}")

        assert resp.status_code == 200, (
            f"Expected the UPLOAD_FOLDER-backed file to be served via "
            f"/static/uploads/car_photos/{filename}, got {resp.status_code}. "
            "This is the exact A-03 regression: Flask's built-in static "
            "endpoint (which only looks inside kk/static) would 404 here "
            "instead of falling through to misc.static_files()'s "
            "UPLOAD_FOLDER-aware handling."
        )
        assert resp.data == expected_bytes
