"""F-37: ``POST /api/cars`` with an Idempotency-Key that is already in flight.

Complements ``test_f37_idem_in_flight_chat.py`` (which exercises a real
overlapping request): here the in-flight claim is held directly so the wiring
of ``create_car`` is verified without building a slow listing pipeline.
"""

from __future__ import annotations

import uuid

# Same app factory / isolated sqlite DB / helpers as the manifest suite.
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


def _post(client, token, key):
    return client.post(
        "/api/cars",
        json=_base_car_payload(),
        headers={**_auth(token), "Idempotency-Key": key},
    )


def test_create_with_key_already_in_flight_is_refused_creates_nothing_then_replays(
    client, app_ctx
):
    from kk.idempotency import claim_in_flight, release_in_flight

    _uid, username, public_id = _make_user(app_ctx, tag="f37c1")
    token = _login(client, username)
    key = f"f37-create-{uuid.uuid4().hex}"
    before = _count_cars(app_ctx)

    # The original create (same user, same key) is still running.
    assert claim_in_flight(scope="create_car", actor_id=str(public_id), idem_key=key)
    try:
        dup = _post(client, token, key)
        assert dup.status_code == 503, dup.data
        assert dup.get_json()["code"] == "request_in_progress"
        assert dup.headers.get("Retry-After")
        assert _count_cars(app_ctx) == before  # nothing created
    finally:
        release_in_flight(scope="create_car", actor_id=str(public_id), idem_key=key)

    created = _post(client, token, key)
    assert created.status_code == 201, created.data
    car_id = created.get_json()["car"]["id"]
    assert _count_cars(app_ctx) == before + 1

    # Completed key -> replay the original, never a second listing.
    replay = _post(client, token, key)
    assert replay.status_code == 201, replay.data
    assert replay.get_json()["car"]["id"] == car_id
    assert _count_cars(app_ctx) == before + 1


def test_create_claim_is_per_user(client, app_ctx):
    from kk.idempotency import claim_in_flight, release_in_flight

    _uid, username, public_id = _make_user(app_ctx, tag="f37c2")
    _uid2, other_name, other_public_id = _make_user(app_ctx, tag="f37c3")
    token = _login(client, other_name)
    key = f"f37-create-{uuid.uuid4().hex}"

    # Another user holding the same key must not block this user.
    assert claim_in_flight(scope="create_car", actor_id=str(public_id), idem_key=key)
    try:
        r = _post(client, token, key)
        assert r.status_code == 201, r.data
    finally:
        release_in_flight(scope="create_car", actor_id=str(public_id), idem_key=key)
