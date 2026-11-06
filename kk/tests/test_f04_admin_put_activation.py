"""F-04: the admin-privileged ``PUT /api/cars/<id>`` activation bypass is closed.

Before: an AdminAccount-scoped JWT could send ``PUT {"status": "active"}`` for a
``pending`` / ``hidden`` / ``draft`` listing. The seller-only availability guard
was skipped for admins, so the listing became public WITHOUT the media-readiness
gate that ``PATCH /api/admin/cars/<id>/status`` enforces and without any alert
hook. Now such a change:

* takes the same row lock as the PATCH, then runs the SAME gate
  (``kk.routes.admin._media_not_ready_block_response``): 409 and NOTHING applied
  (not even other fields of the same request) while media is processing/failed;
* for a genuine first publication (``pending -> active``) records the durable
  alert job in the same transaction and dispatches the post-commit fast path --
  but only while ``SAVED_SEARCH_ALERT_DURABILITY`` is ``record``/``on`` (with the
  flag off this endpoint's alert behaviour is exactly as before: none);
* leaves every other edit unchanged (non-status edits, sold <-> active, status
  changes of an already-public listing).
"""

from __future__ import annotations

import pytest

from kk.tests.test_f04_durable_alert_jobs import (  # noqa: F401  (fixtures + helpers)
    _admin_token,
    _auth,
    _car,
    _job,
    _job_count,
    _patch,
    _set_flag,
    _state,
    _user,
    app,
    app_ctx,
    broker,
    client,
    isolate,
)


def _put(client, token, car, body):
    return client.put(f"/api/cars/{car['public_id']}", json=body, headers=_auth(token))


def _price(app, car_id):
    from kk.models import Car

    with app.app_context():
        return float(Car.query.get(car_id).price)


@pytest.mark.parametrize("mode", ["record", "on"])
def test_admin_put_first_publication_records_job_and_dispatches_once(app, client, broker, monkeypatch, mode):
    _set_flag(monkeypatch, mode)
    uid, _ = _user(app)
    car = _car(app, uid)
    token = _admin_token(app, client)
    r = _put(client, token, car, {"status": "active"})
    assert r.status_code == 200, r.data
    assert _state(app, car["id"]) == ("active", True)
    assert _job(app, car["id"]) is not None and _job_count(app) == 1
    assert broker.car_ids == [car["id"]]
    # repeating it is not a second first-publication
    assert _put(client, token, car, {"status": "active"}).status_code == 200
    assert _job_count(app) == 1 and broker.car_ids == [car["id"]]


def test_admin_put_with_flag_off_publishes_but_adds_no_job_and_no_alert(app, client, broker):
    uid, _ = _user(app)
    car = _car(app, uid)
    token = _admin_token(app, client)
    assert _put(client, token, car, {"status": "active"}).status_code == 200
    assert _state(app, car["id"]) == ("active", True)
    assert _job_count(app) == 0 and broker.calls == []  # unchanged pre-F-04 alert behaviour


@pytest.mark.parametrize("mode", [None, "on"])
@pytest.mark.parametrize("media", ["processing", "failed"])
@pytest.mark.parametrize("start", ["pending", "hidden", "draft"])
def test_admin_put_cannot_activate_a_listing_whose_media_is_not_ready(
    app, client, broker, monkeypatch, start, media, mode
):
    """The validation fix is NOT flag-gated: it applies with the flag off too."""
    if mode:
        _set_flag(monkeypatch, mode)
    uid, _ = _user(app)
    car = _car(app, uid, status=start, media=media)
    token = _admin_token(app, client)
    before_price = _price(app, car["id"])
    r = _put(client, token, car, {"status": "active", "price": 1})
    assert r.status_code == 409, r.data
    body = r.get_json()
    assert body["media_status"] == media and "media" in body["message"].lower()
    assert _state(app, car["id"]) == (start, True)  # still not public
    assert _price(app, car["id"]) == before_price  # nothing else of the request applied
    assert _job_count(app) == 0 and broker.calls == []


def test_put_and_patch_apply_the_same_media_gate(app, client, broker):
    uid, _ = _user(app)
    car = _car(app, uid, media="processing")
    token = _admin_token(app, client)
    via_patch = _patch(client, token, car, {"status": "active"})
    via_put = _put(client, token, car, {"status": "active"})
    assert via_patch.status_code == via_put.status_code == 409
    assert via_patch.get_json() == via_put.get_json()


def test_admin_put_hidden_to_active_with_ready_media_is_allowed_but_never_alerts(
    app, client, broker, monkeypatch
):
    _set_flag(monkeypatch, "on")
    uid, _ = _user(app)
    car = _car(app, uid, status="hidden")
    token = _admin_token(app, client)
    assert _put(client, token, car, {"status": "active"}).status_code == 200
    assert _state(app, car["id"]) == ("active", True)
    assert _job_count(app) == 0 and broker.calls == []  # un-hide is not a first publication


def test_admin_put_activation_of_an_inactive_pending_listing_is_not_public_so_no_job(
    app, client, broker, monkeypatch
):
    _set_flag(monkeypatch, "on")
    uid, _ = _user(app)
    car = _car(app, uid, status="pending", active=False)
    token = _admin_token(app, client)
    assert _put(client, token, car, {"status": "active"}).status_code == 200
    assert _state(app, car["id"]) == ("active", False)
    assert _job_count(app) == 0 and broker.calls == []


def test_non_activation_admin_edits_are_unchanged(app, client, broker, monkeypatch):
    """Non-status edits, sold <-> active and status changes of already-public
    listings keep working exactly as before -- even with media not ready (the
    gate only guards turning a non-public listing public)."""
    _set_flag(monkeypatch, "on")
    uid, _ = _user(app)
    token = _admin_token(app, client)

    pending = _car(app, uid, status="pending", media="processing")
    assert _put(client, token, pending, {"price": 12345}).status_code == 200
    assert _state(app, pending["id"])[0] == "pending" and _price(app, pending["id"]) == 12345.0

    public = _car(app, uid, status="active", media="processing")
    assert _put(client, token, public, {"status": "sold"}).status_code == 200
    assert _state(app, public["id"])[0] == "sold"
    assert _put(client, token, public, {"status": "active"}).status_code == 200
    assert _state(app, public["id"])[0] == "active"
    assert _put(client, token, public, {"status": "bogus"}).status_code == 400
    assert _job_count(app) == 0 and broker.calls == []


def test_seller_still_cannot_publish_a_pending_listing_with_put(app, client, broker, monkeypatch):
    _set_flag(monkeypatch, "on")
    uid, username = _user(app)
    car = _car(app, uid, status="pending")
    r = client.post("/api/auth/login", json={"username": username, "password": "Aa123456!"})
    token = r.get_json()["access_token"]
    resp = _put(client, token, car, {"status": "active"})
    assert resp.status_code == 403
    assert _state(app, car["id"])[0] == "pending" and _job_count(app) == 0
