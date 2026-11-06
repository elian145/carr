"""Force-update hardening (server side).

* admin write validation of ``min_app_version`` & friends (400 + clear message,
  nothing stored, floor above ``latest_app_version`` rejected, whitespace
  normalised);
* read-side sanitising: a bad value ALREADY stored in the DB is served by
  ``GET /api/config/app`` as *unset*, never as garbage;
* response shape unchanged for old clients (additive ``latest_app_version``
  only, same field names / types);
* ``X-App-Version`` / ``X-App-Platform`` are diagnostics only (no enforcement).
"""

from __future__ import annotations

import logging
import os
import sys
import tempfile
import uuid
from pathlib import Path

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

os.environ.setdefault("APP_ENV", "testing")
os.environ.setdefault("SECRET_KEY", "test-secret-key-for-fu")
os.environ.setdefault("JWT_SECRET_KEY", "test-jwt-secret-key-for-fu")

# The exact field set + JSON types old builds parse (pre-change contract).
_OLD_FIELDS = {
    "min_app_version": str,
    "min_android_build": (int, type(None)),
    "min_ios_build": (int, type(None)),
    "force_update_message": str,
    "recommended_app_version": str,
    "recommended_android_build": (int, type(None)),
    "recommended_ios_build": (int, type(None)),
    "soft_update_message": str,
    "android_store_url": str,
    "ios_store_url": str,
    "listing_require_approval": bool,
    "feature_flags": dict,
}
_PLAY_URL = "https://play.google.com/store/apps/details?id=com.carnetiq.app"

_GATE_KEYS = (
    "min_app_version",
    "min_android_build",
    "min_ios_build",
    "recommended_app_version",
    "recommended_android_build",
    "recommended_ios_build",
    "latest_app_version",
    "android_store_url",
    "ios_store_url",
)


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_fu_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ["DB_PATH"] = os.path.join(tmp.name, "fu.db")
    for key in (
        "MIN_APP_VERSION",
        "MIN_ANDROID_BUILD",
        "MIN_IOS_BUILD",
        "RECOMMENDED_APP_VERSION",
        "LATEST_APP_VERSION",
    ):
        os.environ.pop(key, None)

    from kk.app_factory import create_app

    app, *_ = create_app()
    from kk.models import User, db

    with app.app_context():
        db.drop_all()
        db.create_all()

    yield app, app.test_client(), db, User

    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    tmp.cleanup()


@pytest.fixture
def client(app_ctx):
    return app_ctx[1]


@pytest.fixture(autouse=True)
def _clean_settings(app_ctx):
    """Each test starts (and ends) with no stored overrides for the gate."""
    app = app_ctx[0]
    from kk.app_settings import update_platform_settings

    def _reset():
        with app.app_context():
            update_platform_settings({k: "" for k in _GATE_KEYS})

    _reset()
    yield
    _reset()


_ADMIN_HEADERS_CACHE: dict = {}


def _admin_headers(app_ctx) -> dict:
    """One admin principal per module (password hashing is slow)."""
    key = id(app_ctx[0])
    if key not in _ADMIN_HEADERS_CACHE:
        _ADMIN_HEADERS_CACHE[key] = _make_admin_headers(app_ctx)
    return dict(_ADMIN_HEADERS_CACHE[key])


def _make_admin_headers(app_ctx) -> dict:
    from flask_jwt_extended import create_access_token

    from kk.tests.admin_auth_helpers import attach_admin_account

    app, _client, db, User = app_ctx
    with app.app_context():
        user = User(
            username=f"fu_admin_{uuid.uuid4().hex[:8]}",
            phone_number=f"077{uuid.uuid4().int % 10**8:08d}",
            first_name="Fu",
            last_name="Admin",
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id=f"pub-{uuid.uuid4().hex[:12]}",
            is_admin=True,
        )
        user.set_password("Aa123456!")
        db.session.add(user)
        db.session.commit()
        attach_admin_account(db, user, password="Aa123456!", username=user.username)
        token = create_access_token(
            identity=str(user.id),
            additional_claims={
                "is_admin": True,
                "account_scope": "admin",
                "auth_method": "password",
            },
        )
    return {"Authorization": f"Bearer {token}"}


def _put(client, headers, body):
    return client.put("/api/admin/settings", json=body, headers=headers)


def _store_raw(app_ctx, **values):
    """Write values straight into the DB row, bypassing write validation
    (simulates a bad value stored by an older build / manual DB edit)."""
    from kk.app_settings import PLATFORM_KEY
    from kk.models import AppSetting
    from kk.time_utils import utcnow

    app, _client, db, _User = app_ctx
    with app.app_context():
        row = AppSetting.query.filter_by(key=PLATFORM_KEY).first()
        current = dict(row.value) if row and isinstance(row.value, dict) else {}
        current.update(values)
        if row is None:
            db.session.add(AppSetting(key=PLATFORM_KEY, value=current, updated_at=utcnow()))
        else:
            row.value = current
            row.updated_at = utcnow()
        db.session.commit()


def _config(client, **headers):
    r = client.get("/api/config/app", headers=headers)
    assert r.status_code == 200, r.data
    return r.get_json()


# --------------------------------------------------------------------------
# Unit tests of the strict parsers
# --------------------------------------------------------------------------


@pytest.mark.parametrize(
    "value, expected",
    [
        ("1.2.3", (1, 2, 3)),
        ("  1.2.3  ", (1, 2, 3)),
        ("2", (2,)),
        ("2.0", (2, 0)),
        ("1.2.3.4", (1, 2, 3, 4)),
        ("0.0.0", (0, 0, 0)),
        ("99.0.0", (99, 0, 0)),
        ("01.02", (1, 2)),
    ],
)
def test_parse_version_accepts(value, expected):
    from kk.app_settings import parse_version

    assert parse_version(value) == expected


@pytest.mark.parametrize(
    "value",
    [
        "",
        "   ",
        None,
        "v2.0.0",
        "1.x",
        "1..2",
        "-1.0.0",
        "1.0.0-beta",
        "1.0.0+7",
        "100.0.0",
        "999.0.0",
        "1.2.3.4.5",
        "12345.0",
        "1,2",
        "abc",
        "١.٢",  # non-ASCII digits
        2,
        1.5,
        True,
        ["1.0.0"],
        {"v": "1.0.0"},
    ],
)
def test_parse_version_rejects(value):
    from kk.app_settings import parse_version

    assert parse_version(value) is None


def test_parse_build_number_bounds():
    from kk.app_settings import parse_build_number as p

    assert p("0", 100) == 0
    assert p(" 42 ", 100) == 42
    assert p(42, 100) == 42
    assert p("100", 100) == 100
    for bad in ("-1", -1, "101", 101, "1.5", 1.5, "abc", "", None, True, [1], "+5"):
        assert p(bad, 100) is None, bad


def test_sanitize_store_url():
    from kk.app_settings import sanitize_store_url as s

    assert s(" https://apps.apple.com/app/id1 ") == "https://apps.apple.com/app/id1"
    assert s("market://details?id=com.carnetiq.app").startswith("market://")
    assert s("itms-apps://apps.apple.com/app/id1")
    for bad in (
        "",
        "javascript:alert(1)",
        "ftp://x.example/a",
        "https://",
        "https://a b.example",
        "not a url",
        "file:///etc/passwd",
        None,
        42,
        "https://x.example/" + "a" * 3000,
    ):
        assert s(bad) == "", bad


# --------------------------------------------------------------------------
# Admin write validation
# --------------------------------------------------------------------------


@pytest.mark.parametrize(
    "key, bad",
    [
        ("min_app_version", "v2.0.0"),
        ("min_app_version", "1.x"),
        ("min_app_version", "-1.0"),
        ("min_app_version", "999.0.0"),
        ("min_app_version", "1.0.0-beta"),
        ("min_app_version", 2),
        ("min_app_version", ["1.0.0"]),
        ("min_app_version", True),
        ("recommended_app_version", "soon"),
        ("latest_app_version", "9999.1"),
        ("min_android_build", "-5"),
        ("min_android_build", "abc"),
        ("min_android_build", 2_100_000_001),
        ("min_android_build", 1.5),
        ("min_ios_build", "1" * 19),
        ("recommended_android_build", True),
        ("android_store_url", "javascript:alert(1)"),
        ("ios_store_url", "not a url"),
    ],
)
def test_admin_write_rejects_malformed_values(app_ctx, client, key, bad):
    headers = _admin_headers(app_ctx)
    r = _put(client, headers, {key: bad})
    assert r.status_code == 400, (key, bad, r.data)
    body = r.get_json()
    assert body["field"] == key
    assert key in body["message"]
    # Nothing stored: the endpoint serves the default (unset) value.
    cfg = _config(client)
    assert cfg["min_app_version"] == ""
    if key in cfg:
        assert cfg[key] in ("", None, _PLAY_URL)


def test_rejected_write_is_atomic(app_ctx, client):
    """One bad field rejects the whole request: the good field is not stored."""
    headers = _admin_headers(app_ctx)
    r = _put(
        client,
        headers,
        {"force_update_message": "Hello there", "min_app_version": "v9"},
    )
    assert r.status_code == 400
    assert _config(client)["force_update_message"] == "Please update CarNet to continue."


def test_admin_write_accepts_valid_and_normalises(app_ctx, client):
    headers = _admin_headers(app_ctx)
    r = _put(
        client,
        headers,
        {
            "min_app_version": "  1.2  ",
            "min_android_build": " 8 ",
            "min_ios_build": 12345,
            "recommended_app_version": "01.3.0",
            "latest_app_version": "1.3.0",
            "android_store_url": "  https://play.google.com/store/apps/details?id=x  ",
        },
    )
    assert r.status_code == 200, r.data
    overrides = r.get_json()["overrides"]
    assert overrides["min_app_version"] == "1.2"
    assert overrides["min_android_build"] == "8"
    assert overrides["min_ios_build"] == "12345"
    assert overrides["recommended_app_version"] == "1.3.0"
    assert overrides["android_store_url"] == "https://play.google.com/store/apps/details?id=x"
    cfg = _config(client)
    assert cfg["min_app_version"] == "1.2"
    assert cfg["min_android_build"] == 8
    assert cfg["min_ios_build"] == 12345
    assert cfg["latest_app_version"] == "1.3.0"


def test_admin_write_edge_values(app_ctx, client):
    headers = _admin_headers(app_ctx)
    # "0.0.0" / "0" are valid explicit "no gate" markers.
    r = _put(client, headers, {"min_app_version": "0.0.0", "min_android_build": "0"})
    assert r.status_code == 200, r.data
    cfg = _config(client)
    assert cfg["min_app_version"] == "0.0.0"
    assert cfg["min_android_build"] == 0
    # Major 99 is the largest accepted; 100 is not.
    assert _put(client, headers, {"min_app_version": "99.0.0"}).status_code == 200
    assert _put(client, headers, {"min_app_version": "100.0.0"}).status_code == 400


def test_empty_and_null_clear_the_override(app_ctx, client):
    headers = _admin_headers(app_ctx)
    assert _put(client, headers, {"min_app_version": "1.1.0"}).status_code == 200
    assert _config(client)["min_app_version"] == "1.1.0"
    assert _put(client, headers, {"min_app_version": ""}).status_code == 200
    assert _config(client)["min_app_version"] == ""
    assert _put(client, headers, {"min_app_version": "1.1.0"}).status_code == 200
    assert _put(client, headers, {"min_app_version": None}).status_code == 200
    assert _config(client)["min_app_version"] == ""


def test_floor_above_latest_is_rejected(app_ctx, client):
    headers = _admin_headers(app_ctx)
    assert _put(client, headers, {"latest_app_version": "1.4.0"}).status_code == 200

    r = _put(client, headers, {"min_app_version": "1.5.0"})
    assert r.status_code == 400
    assert "latest_app_version" in r.get_json()["message"]
    assert r.get_json()["field"] == "min_app_version"
    assert _config(client)["min_app_version"] == ""

    # equal is fine
    assert _put(client, headers, {"min_app_version": "1.4.0"}).status_code == 200
    # lowering `latest` below the stored floor is rejected too (and reported
    # on latest_app_version)
    r = _put(client, headers, {"latest_app_version": "1.3.0"})
    assert r.status_code == 400
    assert r.get_json()["field"] == "latest_app_version"
    assert _config(client)["latest_app_version"] == "1.4.0"
    # same request may lower both coherently
    assert (
        _put(
            client, headers, {"latest_app_version": "1.3.0", "min_app_version": "1.2.0"}
        ).status_code
        == 200
    )


def test_floor_without_latest_is_allowed(app_ctx, client):
    """`latest_app_version` is optional: unset => nothing to cross-check."""
    headers = _admin_headers(app_ctx)
    assert _put(client, headers, {"min_app_version": "3.0.0"}).status_code == 200
    assert _config(client)["min_app_version"] == "3.0.0"


def test_unrelated_write_not_blocked_by_previously_stored_garbage(app_ctx, client):
    """An admin must still be able to fix settings when the stored floor is bad."""
    _store_raw(app_ctx, min_app_version="garbage")
    headers = _admin_headers(app_ctx)
    assert _put(client, headers, {"support_phone": "+9647700000000"}).status_code == 200
    assert _put(client, headers, {"min_app_version": ""}).status_code == 200


# --------------------------------------------------------------------------
# Read-side sanitising
# --------------------------------------------------------------------------


@pytest.mark.parametrize(
    "stored",
    [
        "garbage",
        "v2.0.0",
        "999.0.0",
        "-3.0.0",
        "1.0.0-beta",
        "   ",
        "10,0,0",
        2,
        1.5,
        True,
        ["9.9.9"],
        {"a": 1},
    ],
)
def test_bad_stored_floor_is_served_as_unset(app_ctx, client, stored):
    _store_raw(app_ctx, min_app_version=stored)
    cfg = _config(client)
    assert cfg["min_app_version"] == ""
    assert isinstance(cfg["min_app_version"], str)


@pytest.mark.parametrize(
    "key", ["min_android_build", "min_ios_build", "recommended_android_build", "recommended_ios_build"]
)
@pytest.mark.parametrize("stored", ["-1", "abc", 1.5, "1" * 25, True, ["1"], {"x": 1}, -7])
def test_bad_stored_build_is_served_as_null(app_ctx, client, key, stored):
    _store_raw(app_ctx, **{key: stored})
    assert _config(client)[key] is None


def test_bad_stored_recommended_and_latest_served_unset(app_ctx, client):
    _store_raw(app_ctx, recommended_app_version="soon", latest_app_version="??")
    cfg = _config(client)
    assert cfg["recommended_app_version"] == ""
    assert cfg["latest_app_version"] == ""


def test_stored_floor_above_stored_latest_is_served_as_unset(app_ctx, client):
    _store_raw(app_ctx, min_app_version="9.0.0", latest_app_version="1.2.0")
    cfg = _config(client)
    assert cfg["min_app_version"] == ""
    assert cfg["latest_app_version"] == "1.2.0"


def test_bad_stored_store_urls_fall_back_safely(app_ctx, client):
    _store_raw(app_ctx, android_store_url="javascript:alert(1)", ios_store_url="oops")
    cfg = _config(client)
    assert cfg["android_store_url"] == _PLAY_URL
    assert cfg["ios_store_url"] == ""


def test_valid_stored_values_are_served_unchanged(app_ctx, client):
    _store_raw(
        app_ctx,
        min_app_version="1.4.0",
        latest_app_version="1.5.0",
        min_android_build="9",
        min_ios_build="123456789012345678",
        recommended_app_version="1.5.0",
        ios_store_url="https://apps.apple.com/app/id1",
    )
    cfg = _config(client)
    assert cfg["min_app_version"] == "1.4.0"
    assert cfg["latest_app_version"] == "1.5.0"
    assert cfg["min_android_build"] == 9
    assert cfg["min_ios_build"] == 123456789012345678
    assert cfg["recommended_app_version"] == "1.5.0"
    assert cfg["ios_store_url"] == "https://apps.apple.com/app/id1"


def test_env_default_floor_is_also_sanitised(app_ctx, client, monkeypatch):
    monkeypatch.setenv("MIN_APP_VERSION", "10.0.0.0.0")
    assert _config(client)["min_app_version"] == ""
    monkeypatch.setenv("MIN_APP_VERSION", "1.0.1")
    assert _config(client)["min_app_version"] == "1.0.1"


def test_sanitiser_never_raises_on_hostile_settings():
    from kk.app_settings import public_version_gate_settings

    hostile = {
        k: object()
        for k in (
            "min_app_version",
            "min_android_build",
            "min_ios_build",
            "recommended_app_version",
            "latest_app_version",
            "android_store_url",
            "ios_store_url",
        )
    }
    out = public_version_gate_settings(hostile)
    assert out["min_app_version"] == ""
    assert out["min_android_build"] is None
    assert out["android_store_url"] == _PLAY_URL
    assert public_version_gate_settings({})["min_app_version"] == ""


# --------------------------------------------------------------------------
# Old-client compatibility + diagnostics headers
# --------------------------------------------------------------------------


def test_response_shape_for_old_clients_is_unchanged(app_ctx, client):
    cfg = _config(client)
    for key, types in _OLD_FIELDS.items():
        assert key in cfg, key
        assert isinstance(cfg[key], types), (key, type(cfg[key]))
    # Additive only: the one new key.
    assert set(cfg) - set(_OLD_FIELDS) == {"latest_app_version"}
    assert cfg["latest_app_version"] == ""


def test_defaults_mean_no_gate(app_ctx, client):
    cfg = _config(client)
    assert cfg["min_app_version"] == ""
    assert cfg["min_android_build"] is None
    assert cfg["min_ios_build"] is None
    assert cfg["recommended_app_version"] == ""
    assert cfg["android_store_url"] == _PLAY_URL


def test_valid_floor_still_served_to_old_clients_in_old_shape(app_ctx, client):
    headers = _admin_headers(app_ctx)
    assert _put(client, headers, {"min_app_version": "1.0.1", "min_android_build": "8"}).status_code == 200
    cfg = _config(client)
    assert cfg["min_app_version"] == "1.0.1"
    assert cfg["min_android_build"] == 8
    for key, types in _OLD_FIELDS.items():
        assert isinstance(cfg[key], types), key


def test_client_version_headers_are_diagnostic_only(app_ctx, client):
    class _Collect(logging.Handler):
        def __init__(self):
            super().__init__(logging.INFO)
            self.records: list[logging.LogRecord] = []

        def emit(self, record):
            self.records.append(record)

    collector = _Collect()
    misc_logger = logging.getLogger("kk.routes.misc")
    old_level = misc_logger.level
    # Other modules' logging.config.dictConfig(disable_existing_loggers=True)
    # may have disabled this already-created logger (see test_m04/test_be10).
    old_disabled = misc_logger.disabled
    misc_logger.disabled = False
    misc_logger.addHandler(collector)
    misc_logger.setLevel(logging.INFO)
    try:
        baseline = _config(client)
        _store_raw(app_ctx, min_app_version="2.0.0")
        with_headers = _config(
            client,
            **{"X-App-Version": "1.0.0;DROP%0A<b>", "X-App-Platform": "android"},
        )
    finally:
        misc_logger.removeHandler(collector)
        misc_logger.setLevel(old_level)
        misc_logger.disabled = old_disabled
    without = _config(client)
    # No enforcement / no per-version response differences.
    assert with_headers == without
    assert with_headers["min_app_version"] == "2.0.0"
    assert baseline["min_app_version"] == ""
    msgs = [r.getMessage() for r in collector.records if "config/app client" in r.getMessage()]
    assert msgs, "diagnostic log line missing"
    assert all(c not in msgs[0] for c in ";<>%")
    assert "platform=android" in msgs[0]
