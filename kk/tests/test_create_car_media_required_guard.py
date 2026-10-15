"""create_car `media_required_count` data-integrity backstop.

Regression: the client could (via a silently dropped durable-copy step)
submit a listing whose `expected_media` was EMPTY although the seller
selected photos. The server cannot tell that from a deliberate media-less
listing, so it published the car `active` / `media_status=ready` with ZERO
images. A client that knows N>0 files were selected now declares
`media_required_count`; an empty manifest alongside it is refused (400) so
nothing is created.

Additive/optional: requests without the field behave exactly as before.
"""

from __future__ import annotations

# Re-use the module-scoped app/test-client fixtures and helpers of the
# media-readiness manifest suite (same app factory, isolated sqlite DB).
from kk.tests.test_media_readiness_manifest import (  # noqa: F401
    _auth,
    _base_car_payload,
    _login,
    _make_user,
    app_ctx,
    client,
)


def _count_cars(app_ctx) -> int:
    app, _socketio, _client, db, _User, Car, *_ = app_ctx
    with app.app_context():
        return db.session.query(Car).count()


def test_empty_manifest_with_required_count_is_refused_and_creates_nothing(
    client, app_ctx
):
    _uid, username, _pub = _make_user(app_ctx, tag="mrg1")
    token = _login(client, username)
    before = _count_cars(app_ctx)

    payload = _base_car_payload(expected_media=[], media_required_count=3)
    r = client.post("/api/cars", json=payload, headers=_auth(token))

    assert r.status_code == 400, r.data
    assert r.get_json().get("code") == "expected_media_missing"
    assert _count_cars(app_ctx) == before


def test_missing_manifest_with_required_count_is_refused(client, app_ctx):
    _uid, username, _pub = _make_user(app_ctx, tag="mrg2")
    token = _login(client, username)
    before = _count_cars(app_ctx)

    payload = _base_car_payload(media_required_count=1)
    r = client.post("/api/cars", json=payload, headers=_auth(token))

    assert r.status_code == 400, r.data
    assert _count_cars(app_ctx) == before


def test_declared_manifest_with_required_count_is_created_pending(client, app_ctx):
    _uid, username, _pub = _make_user(app_ctx, tag="mrg3")
    token = _login(client, username)

    payload = _base_car_payload(
        expected_media=[
            {"client_media_id": "mrg3-a", "kind": "image"},
            {"client_media_id": "mrg3-b", "kind": "image"},
        ],
        media_required_count=2,
    )
    r = client.post("/api/cars", json=payload, headers=_auth(token))

    assert r.status_code == 201, r.data
    car = r.get_json()["car"]
    # Never public before its media is verified.
    assert car["status"] == "pending"


def test_no_required_count_keeps_legacy_media_less_behaviour(client, app_ctx):
    _uid, username, _pub = _make_user(app_ctx, tag="mrg4")
    token = _login(client, username)

    r = client.post("/api/cars", json=_base_car_payload(), headers=_auth(token))
    assert r.status_code == 201, r.data

    r0 = client.post(
        "/api/cars",
        json=_base_car_payload(media_required_count=0),
        headers=_auth(token),
    )
    assert r0.status_code == 201, r0.data


def test_garbage_required_count_is_ignored(client, app_ctx):
    _uid, username, _pub = _make_user(app_ctx, tag="mrg5")
    token = _login(client, username)

    r = client.post(
        "/api/cars",
        json=_base_car_payload(media_required_count="abc"),
        headers=_auth(token),
    )
    assert r.status_code == 201, r.data
