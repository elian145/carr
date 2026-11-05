"""F-07 -- every API timestamp is ISO-8601 UTC with an explicit offset (``Z``).

Root cause: DB columns hold naive UTC datetimes and ``to_dict`` used a bare
``datetime.isoformat()``, i.e. ``2026-03-04T05:06:07.123456`` with no zone
designator. Dart's ``DateTime.parse`` reads such a string as *device-local*
time, so on a UTC+3 phone (Iraq) every listing/message looked 3 hours old.

Fix under test: ONE serializer, ``kk.time_utils.iso_utc`` (naive == UTC, aware
-> UTC, ``Z`` suffix, precision unchanged), used by every model/route that
sends timestamps to clients, plus ``parse_api_datetime`` for the one place the
server parses a client-supplied timestamp back (chat ``before`` cursor) which
must accept ``Z``, explicit offsets and the legacy offset-less form.
"""

from __future__ import annotations

import os
import re
import sys
import tempfile
import uuid
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from kk.time_utils import iso_utc, parse_api_datetime  # noqa: E402

_PASSWORD = "Aa123456!"
_OFFSET_RE = re.compile(r"(Z|[+-]\d{2}:\d{2})$")
_NAIVE_ISO_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?$")
_ANY_ISO_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}")

# ---------------------------------------------------------------------------
# Helper unit tests
# ---------------------------------------------------------------------------


def test_iso_utc_none_is_none():
    assert iso_utc(None) is None


def test_iso_utc_naive_is_treated_as_utc_and_gets_z():
    assert iso_utc(datetime(2026, 3, 4, 5, 6, 7, 123456)) == "2026-03-04T05:06:07.123456Z"


def test_iso_utc_whole_seconds_keeps_existing_precision():
    # Same precision policy as isoformat(): no fractional part when it is 0.
    assert iso_utc(datetime(2026, 3, 4, 5, 6, 7)) == "2026-03-04T05:06:07Z"


@pytest.mark.parametrize("micro", [1, 999, 123456, 999999])
def test_iso_utc_preserves_microseconds_exactly(micro):
    dt = datetime(2026, 3, 4, 5, 6, 7, micro)
    out = iso_utc(dt)
    assert out == dt.isoformat() + "Z"
    assert parse_api_datetime(out) == dt


def test_iso_utc_aware_is_converted_to_utc():
    baghdad = timezone(timedelta(hours=3))
    dt = datetime(2026, 3, 4, 8, 6, 7, 5, tzinfo=baghdad)
    assert iso_utc(dt) == "2026-03-04T05:06:07.000005Z"
    assert iso_utc(datetime(2026, 3, 4, 5, 6, 7, tzinfo=timezone.utc)) == "2026-03-04T05:06:07Z"
    ny = timezone(timedelta(hours=-5))
    assert iso_utc(datetime(2026, 3, 3, 23, 0, 0, tzinfo=ny)) == "2026-03-04T04:00:00Z"


def test_iso_utc_has_no_dst_dependence():
    # Fixed UTC inputs on both sides of common DST transitions are never shifted.
    for dt in (
        datetime(2026, 3, 8, 7, 59, 59),
        datetime(2026, 3, 29, 0, 59, 59),
        datetime(2026, 10, 25, 0, 30, 0),
        datetime(2026, 11, 1, 6, 30, 0),
    ):
        assert iso_utc(dt) == dt.isoformat() + "Z"


@pytest.mark.parametrize(
    "dt",
    [datetime(1, 1, 1, 0, 0, 0), datetime(1970, 1, 1), datetime(2038, 1, 19, 3, 14, 8),
     datetime(2999, 12, 31, 23, 59, 59, 999999), datetime(9999, 12, 31, 23, 59, 59)],
)
def test_iso_utc_far_past_and_future_round_trip(dt):
    out = iso_utc(dt)
    assert out.endswith("Z")
    assert parse_api_datetime(out) == dt


def test_iso_utc_non_datetime_values_do_not_crash():
    assert iso_utc(date(2026, 3, 4)) == "2026-03-04"
    assert iso_utc("already-a-string") == "already-a-string"


def test_iso_utc_is_idempotent_after_parse():
    dt = datetime(2026, 3, 4, 5, 6, 7, 123456)
    assert iso_utc(parse_api_datetime(iso_utc(dt))) == iso_utc(dt)


@pytest.mark.parametrize(
    "raw,expected",
    [
        ("2026-03-04T05:06:07.123456Z", datetime(2026, 3, 4, 5, 6, 7, 123456)),
        ("2026-03-04T05:06:07Z", datetime(2026, 3, 4, 5, 6, 7)),
        ("2026-03-04T05:06:07z", datetime(2026, 3, 4, 5, 6, 7)),
        ("2026-03-04T05:06:07.123456", datetime(2026, 3, 4, 5, 6, 7, 123456)),  # legacy
        ("2026-03-04T05:06:07", datetime(2026, 3, 4, 5, 6, 7)),  # legacy
        ("2026-03-04T08:06:07.123456+03:00", datetime(2026, 3, 4, 5, 6, 7, 123456)),
        ("2026-03-04T00:06:07-05:00", datetime(2026, 3, 4, 5, 6, 7)),
        ("2026-03-04T05:06:07+00:00", datetime(2026, 3, 4, 5, 6, 7)),
        ("2026-03-04T05:06:07.123Z", datetime(2026, 3, 4, 5, 6, 7, 123000)),
        ("2026-03-04T05:06:07.1234567Z", datetime(2026, 3, 4, 5, 6, 7, 123456)),
        ("  2026-03-04T05:06:07Z  ", datetime(2026, 3, 4, 5, 6, 7)),
        # "+" arrives as a space when a client forgets to percent-encode it.
        ("2026-03-04T08:06:07 03:00", datetime(2026, 3, 4, 5, 6, 7)),
    ],
)
def test_parse_api_datetime_accepts_z_offset_and_legacy(raw, expected):
    got = parse_api_datetime(raw)
    assert got == expected
    assert got.tzinfo is None  # always naive UTC, comparable with DB columns


@pytest.mark.parametrize("raw", [None, "", "   ", "garbage", "2026-13-45T00:00:00Z", "Z"])
def test_parse_api_datetime_rejects_garbage_with_none(raw):
    assert parse_api_datetime(raw) is None


def test_parse_api_datetime_normalises_aware_datetime_objects():
    aware = datetime(2026, 3, 4, 8, 0, 0, tzinfo=timezone(timedelta(hours=3)))
    assert parse_api_datetime(aware) == datetime(2026, 3, 4, 5, 0, 0)


# ---------------------------------------------------------------------------
# Model serializers
# ---------------------------------------------------------------------------

_INSTANT = datetime(2026, 3, 4, 5, 6, 7, 123456)


@pytest.fixture(scope="module")
def models_app():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_f07_models_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ["DB_PATH"] = os.path.join(tmp.name, "f07_models.db")
    from kk.app_factory import create_app

    app, _socketio, *_ = create_app()
    from kk.models import db

    with app.app_context():
        db.drop_all()
        db.create_all()
    yield app
    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    tmp.cleanup()


# (model name, serializer method, kwargs, minimum #timestamp keys it must emit)
_SERIALIZERS = [
    ("User", "to_dict", {"include_private": True}, 3),
    ("DealerApplication", "to_dict", {}, 4),
    ("DealerProfile", "to_dict", {}, 2),
    ("DealerDecision", "to_dict", {}, 1),
    ("Car", "to_dict", {"include_private": True}, 4),
    ("ListingAnalytics", "to_dict", {}, 2),
    ("Message", "to_dict", {}, 2),
    ("Notification", "to_dict", {}, 1),
    ("ScheduledNotification", "to_admin_dict", {}, 4),
    ("UserAction", "to_dict", {}, 1),
    ("SavedSearch", "to_dict", {}, 2),
    ("UserReport", "to_admin_dict", {}, 2),
    ("ListingReport", "to_admin_dict", {}, 2),
    ("AppSetting", "to_dict", {}, 1),
    ("CatalogBrand", "to_dict", {}, 2),
    ("CatalogVehicleModel", "to_dict", {}, 2),
]


def _timestamp_strings(payload) -> list[str]:
    out: list[str] = []
    if isinstance(payload, dict):
        for v in payload.values():
            out.extend(_timestamp_strings(v))
    elif isinstance(payload, (list, tuple)):
        for v in payload:
            out.extend(_timestamp_strings(v))
    elif isinstance(payload, str) and _ANY_ISO_RE.match(payload):
        out.append(payload)
    return out


@pytest.mark.parametrize("name,method,kwargs,min_keys", _SERIALIZERS, ids=[s[0] for s in _SERIALIZERS])
def test_model_serializers_emit_offset_bearing_utc_timestamps(models_app, name, method, kwargs, min_keys):
    from sqlalchemy import DateTime

    from kk import models as models_mod

    cls = getattr(models_mod, name)
    cols = [c.key for c in cls.__mapper__.columns if isinstance(c.type, DateTime)]
    assert cols, f"{name} has no DateTime column?"
    with models_app.app_context():
        obj = cls()
        for col in cols:
            setattr(obj, col, _INSTANT)
        payload = getattr(obj, method)(**kwargs)

    stamps = _timestamp_strings(payload)
    assert len(stamps) >= min_keys, (name, stamps)
    for s in stamps:
        assert not _NAIVE_ISO_RE.match(s), f"{name} emitted an offset-less timestamp: {s}"
        assert _OFFSET_RE.search(s), f"{name} emitted a timestamp without an offset: {s}"
        # The emitted string round-trips to exactly the stored UTC instant.
        assert parse_api_datetime(s) == _INSTANT
        assert datetime.fromisoformat(s.replace("Z", "+00:00")).astimezone(timezone.utc).replace(
            tzinfo=None
        ) == _INSTANT


# ---------------------------------------------------------------------------
# Chat: emitted timestamps + `before` cursor round-trip
# ---------------------------------------------------------------------------


@pytest.fixture(scope="module")
def chat_ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_f07_chat_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "f07_chat.db")
    from kk.app_factory import create_app

    app, _socketio, *_ = create_app()
    from kk.models import Car, Message, User, db
    from kk.time_utils import utcnow

    with app.app_context():
        db.drop_all()
        db.create_all()
    yield app, app.test_client(), db, User, Car, Message, utcnow
    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    tmp.cleanup()


def _make_user(chat_ctx) -> tuple[int, str]:
    app, _c, db, User, *_ = chat_ctx
    username = f"f07_{uuid.uuid4().hex[:10]}"
    with app.app_context():
        user = User(
            username=username,
            phone_number=f"079{uuid.uuid4().int % 10**8:08d}",
            first_name="F",
            last_name="Seven",
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id=f"pub-{uuid.uuid4().hex[:12]}",
        )
        user.set_password(_PASSWORD)
        db.session.add(user)
        db.session.commit()
        return user.id, username


def _login(client, username: str) -> dict:
    r = client.post("/api/auth/login", json={"username": username, "password": _PASSWORD})
    assert r.status_code == 200, r.data
    return {"Authorization": f"Bearer {r.get_json()['access_token']}"}


def _make_car(chat_ctx, seller_id: int) -> str:
    app, _c, db, _U, Car, *_ = chat_ctx
    with app.app_context():
        car = Car(
            seller_id=seller_id,
            public_id=f"car-{uuid.uuid4().hex[:12]}",
            brand="toyota",
            model="corolla",
            year=2021,
            mileage=10,
            engine_type="gas",
            transmission="auto",
            drive_type="fwd",
            condition="used",
            body_type="sedan",
            price=15000,
            location="Erbil",
            is_active=True,
        )
        db.session.add(car)
        db.session.commit()
        return car.public_id


def _seed(chat_ctx, car_pid: str, seller_id: int, buyer_id: int, n: int, *, same_second_pairs=False):
    app, _c, db, _U, Car, Message, utcnow = chat_ctx
    contents = [f"msg-{i:04d}" for i in range(n)]
    with app.app_context():
        car = Car.query.filter_by(public_id=car_pid).first()
        base = utcnow().replace(microsecond=654321)
        for i, text in enumerate(contents):
            from_seller = i % 2 == 0
            db.session.add(
                Message(
                    car_id=car.id,
                    sender_id=seller_id if from_seller else buyer_id,
                    receiver_id=buyer_id if from_seller else seller_id,
                    content=text,
                    created_at=base + timedelta(minutes=i),
                )
            )
        db.session.commit()
    return contents


def _get(client, headers, car_pid, **qs):
    r = client.get(f"/api/chat/{car_pid}/messages", query_string=qs, headers=headers)
    assert r.status_code == 200, r.data
    return r.get_json()


def _texts(body):
    return [m["content"] for m in body["messages"]]


@pytest.fixture(scope="module")
def convo(chat_ctx):
    _a, client, *_ = chat_ctx
    seller_id, seller_name = _make_user(chat_ctx)
    buyer_id, _bn = _make_user(chat_ctx)
    car_pid = _make_car(chat_ctx, seller_id)
    contents = _seed(chat_ctx, car_pid, seller_id, buyer_id, 120)
    headers = _login(client, seller_name)
    return client, headers, car_pid, contents


def test_chat_messages_emit_z_timestamps(convo):
    client, headers, car_pid, _contents = convo
    body = _get(client, headers, car_pid)
    assert body["messages"]
    for m in body["messages"]:
        assert m["created_at"].endswith("Z"), m["created_at"]
        assert not _NAIVE_ISO_RE.match(m["created_at"])


def test_chat_before_cursor_round_trips_with_z(convo):
    client, headers, car_pid, contents = convo
    page1 = _get(client, headers, car_pid)
    assert _texts(page1) == contents[70:120]
    cursor = page1["messages"][0]["created_at"]
    assert cursor.endswith("Z")

    page2 = _get(client, headers, car_pid, before=cursor)
    assert _texts(page2) == contents[20:70]
    page3 = _get(client, headers, car_pid, before=page2["messages"][0]["created_at"])
    assert _texts(page3) == contents[0:20]
    assert page3["has_more"] is False
    rebuilt = _texts(page3) + _texts(page2) + _texts(page1)
    assert rebuilt == contents and len(set(rebuilt)) == 120  # no skip, no duplicate


@pytest.mark.parametrize("variant", ["legacy_naive", "plus_zero", "plus_three", "minus_five", "lowercase_z"])
def test_chat_before_cursor_accepts_every_offset_form_identically(convo, variant):
    client, headers, car_pid, contents = convo
    page1 = _get(client, headers, car_pid)
    z_cursor = page1["messages"][0]["created_at"]
    reference = _get(client, headers, car_pid, before=z_cursor)

    utc = parse_api_datetime(z_cursor)
    if variant == "legacy_naive":
        cursor = z_cursor[:-1]  # what pre-F-07 servers emitted/clients echoed
    elif variant == "plus_zero":
        cursor = utc.isoformat() + "+00:00"
    elif variant == "plus_three":
        cursor = (utc + timedelta(hours=3)).isoformat() + "+03:00"
    elif variant == "minus_five":
        cursor = (utc - timedelta(hours=5)).isoformat() + "-05:00"
    else:
        cursor = z_cursor[:-1] + "z"

    got = _get(client, headers, car_pid, before=cursor)
    assert _texts(got) == _texts(reference) == contents[20:70]
    assert got["has_more"] == reference["has_more"]
    assert got["total"] == reference["total"]


def test_chat_before_cursor_is_exclusive_of_cursor_message(convo):
    client, headers, car_pid, contents = convo
    oldest = _get(client, headers, car_pid)["messages"][0]
    got = _get(client, headers, car_pid, before=oldest["created_at"])
    assert oldest["content"] not in _texts(got)
    assert got["messages"][-1]["content"] == contents[69]


def test_chat_garbage_before_cursor_is_ignored_like_before(convo):
    client, headers, car_pid, contents = convo
    assert _texts(_get(client, headers, car_pid, before="not-a-date")) == contents[70:120]


def test_chat_list_last_message_timestamp_is_z(chat_ctx, convo):
    client, headers, _car_pid, _contents = convo
    r = client.get("/api/chats", headers=headers)
    assert r.status_code == 200, r.data
    stamps = _timestamp_strings(r.get_json())
    assert stamps, r.get_json()
    assert all(s.endswith("Z") for s in stamps), stamps


def test_listing_detail_route_emits_z(chat_ctx, convo):
    client, headers, car_pid, _contents = convo
    r = client.get(f"/api/cars/{car_pid}", headers=headers)
    assert r.status_code == 200, r.data
    stamps = _timestamp_strings(r.get_json())
    assert stamps, r.get_json()
    assert all(_OFFSET_RE.search(s) for s in stamps), stamps


# ---------------------------------------------------------------------------
# Repo guard: no raw naive ``.isoformat()`` in API serializers again
# ---------------------------------------------------------------------------

# Files whose timestamp serialization was converted to iso_utc (F-07).
_GUARDED_FILES = [
    "kk/models.py",
    "kk/routes/cars.py",
    "kk/routes/chat.py",
    "kk/routes/admin.py",
    "kk/routes/admin_auto_moderation.py",
    "kk/routes/favorites.py",
    "kk/routes/user.py",
    "kk/app_settings.py",
    "kk/auto_moderation/config.py",
    "kk/auto_moderation/stats.py",
    "kk/listing_revisions.py",
    "kk/notification_broadcast.py",
    "kk/security.py",
    "kk/socketio_handlers.py",
    "kk/chat_realtime.py",
]

# Intentional, NON-API ``.isoformat()`` uses: (file, exact stripped source line, why).
_ALLOWED_RAW_ISOFORMAT = {
    ("kk/routes/admin.py", '"scheduled_at": scheduled_at.isoformat(),'):
        "audit-log metadata persisted in UserAction (storage, not a response)",
    ("kk/security.py", "'timestamp': utcnow().isoformat()"):
        "security audit-log metadata persisted in UserAction (storage)",
    ("kk/listing_revisions.py", "return value.isoformat()"):
        "_norm(): comparison/signature input, never sent to clients",
    ("kk/listing_revisions.py", "revision.submitted_at.isoformat() if revision.submitted_at else None"):
        "revision-signature hash input (must stay stable), not a response",
    ("kk/auto_moderation/stats.py", 'day = r.created_at.date().isoformat() if r.created_at else "unknown"'):
        "calendar-day bucket key (a date, not an instant)",
}

_ISO_CALL = re.compile(r"\.isoformat\(")


def test_guard_no_raw_isoformat_in_api_serializers():
    offenders = []
    for rel in _GUARDED_FILES:
        path = _REPO_ROOT / rel
        for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if _ISO_CALL.search(line) and (rel, line.strip()) not in _ALLOWED_RAW_ISOFORMAT:
                offenders.append(f"{rel}:{lineno}: {line.strip()}")
    assert not offenders, (
        "API timestamps must go through kk.time_utils.iso_utc (UTC, 'Z' suffix). "
        "Raw naive .isoformat() found; use iso_utc() or add a justified allow-list entry:\n"
        + "\n".join(offenders)
    )


def test_guard_allow_list_has_no_stale_entries():
    seen = set()
    for rel in _GUARDED_FILES:
        for line in (_REPO_ROOT / rel).read_text(encoding="utf-8").splitlines():
            if _ISO_CALL.search(line):
                seen.add((rel, line.strip()))
    assert set(_ALLOWED_RAW_ISOFORMAT) <= seen, set(_ALLOWED_RAW_ISOFORMAT) - seen


def test_guard_chat_cursor_uses_the_tolerant_parser():
    src = (_REPO_ROOT / "kk/routes/chat.py").read_text(encoding="utf-8")
    assert "fromisoformat" not in src
    assert "parse_api_datetime(before_raw)" in src
