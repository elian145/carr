"""Safe moderation of listing edits (pending revisions).

Product rules pinned here:

* A listing that is Under Review (pending/hidden/draft) can be edited and
  deleted by its owner; edits apply directly and it stays Under Review.
* Editing an ACTIVE listing never changes what the public sees. The edit is
  saved as a pending revision of the SAME listing; the approved data (fields,
  photos, cover, order) stays public until an admin approves; no second
  listing exists.
* Approval atomically publishes the revision (listing keeps its id, new
  photos / order / cover appear, the revision is cleared); rejection keeps
  the old listing public and shows the owner the reason; the owner can
  resubmit or discard.
* An admin cannot approve an outdated revision (content token) nor one whose
  new media is still processing.
* Deleting a listing cleans up its pending revision; late background media
  jobs cannot recreate anything; storage still used by the approved version
  is never deleted.
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

_PASSWORD = "Aa123456!"
_CDN = "https://cdn.example.com/car_photos"


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(
        prefix="carlist_listing_revisions_", ignore_cleanup_errors=True
    )
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "revisions.db")
    os.environ["UPLOAD_FOLDER"] = os.path.join(tmp.name, "uploads")
    os.environ["R2_PUBLIC_URL"] = "https://cdn.example.com"
    os.environ["R2_ACCOUNT_ID"] = "test-account"
    os.environ["R2_BUCKET_NAME"] = "test-bucket"
    os.environ["R2_ACCESS_KEY_ID"] = "test-key"
    os.environ["R2_SECRET_ACCESS_KEY"] = "test-secret"

    from kk.app_factory import create_app

    app, _socketio, *_ = create_app()
    for key in (
        "R2_PUBLIC_URL",
        "R2_ACCOUNT_ID",
        "R2_BUCKET_NAME",
        "R2_ACCESS_KEY_ID",
        "R2_SECRET_ACCESS_KEY",
    ):
        app.config[key] = os.environ[key]

    from kk.models import db

    with app.app_context():
        db.drop_all()
        db.create_all()

    yield app, app.test_client()

    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    tmp.cleanup()


@pytest.fixture
def client(app_ctx):
    return app_ctx[1]


@pytest.fixture
def r2_calls(monkeypatch):
    """Record every storage-object deletion (nothing real is touched)."""
    import kk.r2_ops as r2_ops_module

    calls: list[str] = []
    monkeypatch.setattr(
        r2_ops_module, "r2_delete_object", lambda **kw: calls.append(kw["key"])
    )
    return calls


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _login(client, username: str) -> str:
    from kk.tests.admin_auth_helpers import login_preferring_admin_scope

    return login_preferring_admin_scope(client, username, _PASSWORD)


def _make_user(app_ctx, *, is_admin: bool = False, locale: str | None = None):
    from kk.models import User, db
    from kk.tests.admin_auth_helpers import attach_admin_account

    app, _client = app_ctx
    username = f"rev_{uuid.uuid4().hex[:10]}"
    with app.app_context():
        user = User(
            username=username,
            phone_number=f"075{uuid.uuid4().int % 10**8:08d}",
            first_name="Rev",
            last_name="Test",
            is_active=True,
            is_verified=True,
            phone_verified=True,
            is_admin=is_admin,
            locale=locale,
            public_id=f"rev-{uuid.uuid4().hex[:12]}",
        )
        user.set_password(_PASSWORD)
        db.session.add(user)
        db.session.commit()
        if is_admin:
            attach_admin_account(db, user, password=_PASSWORD, username=username)
        return user.id, username


def _admin(app_ctx, client) -> str:
    _uid, username = _make_user(app_ctx, is_admin=True)
    return _login(client, username)


def _published_listing(
    app_ctx,
    client,
    *,
    status: str = "active",
    photos: int = 3,
    locale: str | None = None,
) -> dict:
    """An approved listing with `photos` photos (the first is the cover),
    created directly in the DB. Returns ids + the owner's token."""
    from kk.models import Car, CarImage, db

    app, _c = app_ctx
    uid, username = _make_user(app_ctx, locale=locale)
    token = _login(client, username)
    with app.app_context():
        car = Car(
            seller_id=uid,
            public_id=f"car-{uuid.uuid4().hex[:12]}",
            title="Toyota Camry 2021",
            brand="toyota",
            model="camry",
            trim="base",
            year=2021,
            mileage=1000,
            engine_type="gasoline",
            fuel_type="gasoline",
            transmission="automatic",
            drive_type="fwd",
            condition="used",
            body_type="sedan",
            price=15000,
            currency="USD",
            location="Erbil",
            description="Original description",
            is_active=True,
            status=status,
        )
        db.session.add(car)
        db.session.flush()
        image_ids = []
        for i in range(photos):
            img = CarImage(
                car_id=car.id,
                image_url=f"{_CDN}/orig_{car.id}_{i}.jpg",
                is_primary=(i == 0),
                order=i,
                kind="listing",
            )
            db.session.add(img)
            db.session.flush()
            image_ids.append(img.id)
        db.session.commit()
        return {
            "uid": uid,
            "token": token,
            "car_id": car.id,
            "public_id": car.public_id,
            "image_ids": image_ids,
            "urls": [f"{_CDN}/orig_{car.id}_{i}.jpg" for i in range(photos)],
        }


def _owner_get(client, listing) -> dict:
    r = client.get(f"/api/cars/{listing['public_id']}", headers=_auth(listing["token"]))
    assert r.status_code == 200, r.data
    return r.get_json()["car"]


def _public_get(client, listing):
    return client.get(f"/api/cars/{listing['public_id']}")


def _put(client, listing, body: dict):
    return client.put(
        f"/api/cars/{listing['public_id']}", json=body, headers=_auth(listing["token"])
    )


def _revision_ids(app_ctx, listing):
    from kk.models import CarRevision

    app, _c = app_ctx
    with app.app_context():
        rev = CarRevision.query.filter_by(car_id=listing["car_id"]).first()
        if rev is None:
            return None
        return rev.public_id, rev.shadow_car_id


def _admin_detail(client, admin_token, revision_public_id) -> dict:
    r = client.get(
        f"/api/admin/listing-revisions/{revision_public_id}", headers=_auth(admin_token)
    )
    assert r.status_code == 200, r.data
    return r.get_json()


def _approve(client, admin_token, revision_public_id, token):
    return client.post(
        f"/api/admin/listing-revisions/{revision_public_id}/approve",
        json={"revision_token": token},
        headers=_auth(admin_token),
    )


def _submit_edit(client, app_ctx, listing, body=None) -> str:
    """Owner saves an edit; returns the revision's public id."""
    r = _put(client, listing, body or {"price": 12000, "description": "Edited"})
    assert r.status_code == 200, r.data
    ids = _revision_ids(app_ctx, listing)
    assert ids is not None
    return ids[0]


def _count(app_ctx, model, **filters) -> int:
    app, _c = app_ctx
    with app.app_context():
        return model.query.filter_by(**filters).count()


def _simulate_worker_attach(app_ctx, car_db_id: int, cmid: str, *, kind="listing"):
    """The Celery worker's Phase B for one manifest item (as in the media
    readiness tests): returns the transition outcome."""
    from kk.media_readiness import (
        mark_item_phase_a_accepted,
        transition_media_item_terminal,
    )
    from kk.routes.media import attach_processed_car_image

    app, _c = app_ctx
    with app.app_context():
        mark_item_phase_a_accepted(
            car_id=car_db_id, client_media_id=cmid, job_task_id=f"t-{cmid}"
        )
        return transition_media_item_terminal(
            car_id=car_db_id,
            client_media_id=cmid,
            to_status="attached",
            attach_fn=lambda car_obj: attach_processed_car_image(
                car_obj,
                kind=kind,
                rel_path=f"{_CDN}/{cmid}.jpg",
                source_media_id=cmid,
            ),
        )


def _public_image_urls(client, listing) -> list[str]:
    r = _public_get(client, listing)
    assert r.status_code == 200, r.data
    return [i["image_url"] for i in r.get_json()["car"]["images"]]


# ---------------------------------------------------------------------------
# A. Under Review listings: edit + delete
# ---------------------------------------------------------------------------


class TestUnderReviewListings:
    def test_owner_edit_applies_directly_and_stays_under_review(self, app_ctx, client):
        from kk.models import CarRevision

        listing = _published_listing(app_ctx, client, status="pending")
        r = _put(client, listing, {"price": 12345, "description": "New text"})
        assert r.status_code == 200, r.data
        body = r.get_json()
        assert not body.get("submitted_for_review")
        assert body["car"]["price"] == 12345
        assert body["car"]["status"] == "pending"  # still Under Review

        car = _owner_get(client, listing)
        assert car["price"] == 12345 and car["description"] == "New text"
        assert car["status"] == "pending"
        assert "pending_revision" not in car
        assert _count(app_ctx, CarRevision, car_id=listing["car_id"]) == 0
        # ...and it is still not public.
        assert _public_get(client, listing).status_code == 404

    def test_owner_can_edit_photos_of_under_review_listing_directly(
        self, app_ctx, client, r2_calls
    ):
        from kk.models import CarImage

        listing = _published_listing(app_ctx, client, status="pending")
        victim = listing["image_ids"][1]
        r = client.delete(
            f"/api/cars/{listing['public_id']}/images/{victim}",
            headers=_auth(listing["token"]),
        )
        assert r.status_code == 200, r.data
        assert _count(app_ctx, CarImage, id=victim) == 0
        assert r2_calls == [f"car_photos/orig_{listing['car_id']}_1.jpg"]

    def test_owner_can_delete_under_review_listing(self, app_ctx, client):
        listing = _published_listing(app_ctx, client, status="pending")
        r = client.delete(
            f"/api/cars/{listing['public_id']}", headers=_auth(listing["token"])
        )
        assert r.status_code == 200, r.data
        assert (
            client.get(
                f"/api/cars/{listing['public_id']}", headers=_auth(listing["token"])
            ).status_code
            == 404
        )
        mine = client.get("/api/user/my-listings", headers=_auth(listing["token"]))
        assert mine.get_json()["cars"] == []


# ---------------------------------------------------------------------------
# B. Editing an ACTIVE listing
# ---------------------------------------------------------------------------


class TestActiveListingEdit:
    def test_edit_is_pending_and_public_version_unchanged(self, app_ctx, client):
        listing = _published_listing(app_ctx, client)
        r = _put(
            client,
            listing,
            {"price": 12000, "description": "Edited", "mileage": 2222, "color": "red"},
        )
        assert r.status_code == 200, r.data
        body = r.get_json()
        assert body["message"] == "Your changes have been submitted for review."
        assert body["submitted_for_review"] is True
        assert body["pending_revision"]["status"] == "pending"
        # The response's `car` is the APPROVED listing, not the proposal.
        assert body["car"]["price"] == 15000

        public = _public_get(client, listing).get_json()["car"]
        assert public["price"] == 15000
        assert public["description"] == "Original description"
        assert public["mileage"] == 1000
        assert "pending_revision" not in public
        assert _public_image_urls(client, listing) == listing["urls"]

        owner = _owner_get(client, listing)
        assert owner["price"] == 15000  # approved data stays `car`
        pending = owner["pending_revision"]
        assert pending["status"] == "pending"
        assert pending["car"]["price"] == 12000
        assert pending["car"]["description"] == "Edited"
        assert pending["car"]["id"] == listing["public_id"]
        assert set(pending["changed_fields"]) >= {"price", "description", "mileage"}

    def test_other_users_never_see_the_pending_revision(self, app_ctx, client):
        listing = _published_listing(app_ctx, client)
        _submit_edit(client, app_ctx, listing)
        _uid, other = _make_user(app_ctx)
        other_token = _login(client, other)
        r = client.get(
            f"/api/cars/{listing['public_id']}", headers=_auth(other_token)
        )
        assert r.status_code == 200
        assert "pending_revision" not in r.get_json()["car"]
        assert r.get_json()["car"]["price"] == 15000

    def test_no_second_listing_and_my_listings_shows_pending_edit(
        self, app_ctx, client
    ):
        from kk.models import Car

        listing = _published_listing(app_ctx, client)
        before = _count(app_ctx, Car, seller_id=listing["uid"], is_active=True)
        _submit_edit(client, app_ctx, listing)
        _submit_edit(client, app_ctx, listing, {"price": 11000})  # edit again
        assert _count(app_ctx, Car, seller_id=listing["uid"], is_active=True) == before

        mine = client.get("/api/user/my-listings", headers=_auth(listing["token"]))
        cars = mine.get_json()["cars"]
        assert [c["id"] for c in cars] == [listing["public_id"]]
        assert mine.get_json()["pagination"]["total"] == 1
        assert cars[0]["price"] == 15000
        assert cars[0]["pending_revision"]["status"] == "pending"
        assert cars[0]["pending_revision"]["car"]["price"] == 11000

        compat = client.get("/api/my_listings", headers=_auth(listing["token"]))
        assert [c["id"] for c in compat.get_json()] == [listing["public_id"]]
        assert compat.get_json()[0]["pending_revision"]["status"] == "pending"

        # Never visible as a separate public listing / in search.
        search = client.get("/api/cars")
        ids = [c["id"] for c in search.get_json()["cars"]]
        assert ids.count(listing["public_id"]) == 1

    def test_second_edit_updates_the_same_revision(self, app_ctx, client):
        from kk.models import CarRevision

        listing = _published_listing(app_ctx, client)
        first = _submit_edit(client, app_ctx, listing, {"price": 12000})
        second = _submit_edit(client, app_ctx, listing, {"price": 11000})
        assert first == second
        assert _count(app_ctx, CarRevision, car_id=listing["car_id"]) == 1
        assert _owner_get(client, listing)["pending_revision"]["car"]["price"] == 11000

    def test_status_only_change_is_not_a_reviewable_edit(self, app_ctx, client):
        from kk.models import CarRevision

        listing = _published_listing(app_ctx, client)
        r = _put(client, listing, {"status": "sold"})
        assert r.status_code == 200, r.data
        assert _owner_get(client, listing)["status"] == "sold"
        assert _count(app_ctx, CarRevision, car_id=listing["car_id"]) == 0

    def test_validation_errors_leave_no_revision(self, app_ctx, client):
        from kk.models import CarRevision, Car

        listing = _published_listing(app_ctx, client)
        shadows_before = _count(app_ctx, Car, status="revision")
        r = _put(client, listing, {"title_status": "damaged"})  # needs damaged_parts
        assert r.status_code == 400
        assert _count(app_ctx, CarRevision, car_id=listing["car_id"]) == 0
        assert _count(app_ctx, Car, status="revision") == shadows_before
        assert _owner_get(client, listing)["title_status"] != "damaged"


# ---------------------------------------------------------------------------
# C. Admin approval / rejection
# ---------------------------------------------------------------------------


class TestAdminDecision:
    def test_admin_sees_current_vs_proposed_and_approval_publishes_atomically(
        self, app_ctx, client
    ):
        from kk.models import Car, CarRevision

        listing = _published_listing(app_ctx, client, locale="ar")
        rev_id = _submit_edit(
            client, app_ctx, listing, {"price": 12000, "description": "Edited"}
        )
        shadow_id = _revision_ids(app_ctx, listing)[1]
        admin = _admin(app_ctx, client)

        # queue
        q = client.get("/api/admin/listing-revisions", headers=_auth(admin))
        assert q.status_code == 200, q.data
        queued = [i for i in q.get_json()["revisions"] if i["id"] == rev_id]
        assert len(queued) == 1
        assert queued[0]["listing"]["id"] == listing["public_id"]
        assert "car" not in queued[0]  # list is a summary

        detail = _admin_detail(client, admin, rev_id)
        assert detail["current"]["price"] == 15000  # old version
        assert detail["revision"]["car"]["price"] == 12000  # proposed
        assert "price" in detail["revision"]["changed_fields"]

        r = _approve(client, admin, rev_id, detail["revision"]["revision_token"])
        assert r.status_code == 200, r.data

        public = _public_get(client, listing).get_json()["car"]
        assert public["id"] == listing["public_id"]  # same listing
        assert public["price"] == 12000
        assert public["description"] == "Edited"
        assert public["status"] == "active"
        # revision + working copy are gone
        assert _count(app_ctx, CarRevision, car_id=listing["car_id"]) == 0
        app, _c = app_ctx
        with app.app_context():
            assert Car.query.filter_by(id=shadow_id).first() is None
        assert "pending_revision" not in _owner_get(client, listing)

        # Seller notified (localized, deep-linked)
        from kk.models import Notification

        with app.app_context():
            notif = (
                Notification.query.filter_by(
                    user_id=listing["uid"], notification_type="listing_status"
                )
                .order_by(Notification.id.desc())
                .first()
            )
            assert notif.data["status"] == "revision_approved"
            assert notif.data["car_id"] == listing["public_id"]
            assert notif.title == "تمت الموافقة على التعديلات"

    def test_rejection_keeps_old_listing_shows_reason_and_allows_resubmit(
        self, app_ctx, client
    ):
        listing = _published_listing(app_ctx, client)
        rev_id = _submit_edit(client, app_ctx, listing, {"price": 100})
        admin = _admin(app_ctx, client)
        token = _admin_detail(client, admin, rev_id)["revision"]["revision_token"]

        # a reason is mandatory
        no_reason = client.post(
            f"/api/admin/listing-revisions/{rev_id}/reject",
            json={"revision_token": token},
            headers=_auth(admin),
        )
        assert no_reason.status_code == 400

        r = client.post(
            f"/api/admin/listing-revisions/{rev_id}/reject",
            json={"revision_token": token, "reason": "Price looks wrong"},
            headers=_auth(admin),
        )
        assert r.status_code == 200, r.data

        assert _public_get(client, listing).get_json()["car"]["price"] == 15000
        pending = _owner_get(client, listing)["pending_revision"]
        assert pending["status"] == "rejected"
        assert pending["rejection_reason"] == "Price looks wrong"
        assert pending["car"]["price"] == 100  # their edit is kept for fixing

        # A rejected revision can no longer be approved...
        again = _approve(client, admin, rev_id, token)
        assert again.status_code == 409

        # ...but the owner can correct + resubmit.
        _put(client, listing, {"price": 14000})
        pending = _owner_get(client, listing)["pending_revision"]
        assert pending["status"] == "pending"
        assert pending["rejection_reason"] is None
        new_token = _admin_detail(client, admin, rev_id)["revision"]["revision_token"]
        assert _approve(client, admin, rev_id, new_token).status_code == 200
        assert _public_get(client, listing).get_json()["car"]["price"] == 14000

    def test_rejection_notifies_owner_with_the_admins_reason(self, app_ctx, client):
        from kk.models import Notification

        listing = _published_listing(app_ctx, client)
        rev_id = _submit_edit(client, app_ctx, listing)
        admin = _admin(app_ctx, client)
        token = _admin_detail(client, admin, rev_id)["revision"]["revision_token"]
        client.post(
            f"/api/admin/listing-revisions/{rev_id}/reject",
            json={"revision_token": token, "reason": "Photos are blurry"},
            headers=_auth(admin),
        )
        app, _c = app_ctx
        with app.app_context():
            notif = (
                Notification.query.filter_by(
                    user_id=listing["uid"], notification_type="listing_status"
                )
                .order_by(Notification.id.desc())
                .first()
            )
            assert notif.data["status"] == "revision_rejected"
            assert notif.message == "Photos are blurry"

    def test_stale_approval_is_refused(self, app_ctx, client):
        listing = _published_listing(app_ctx, client)
        rev_id = _submit_edit(client, app_ctx, listing, {"price": 12000})
        admin = _admin(app_ctx, client)
        reviewed = _admin_detail(client, admin, rev_id)["revision"]["revision_token"]

        # The owner changes the edit AFTER the admin opened it.
        _put(client, listing, {"price": 1})

        stale = _approve(client, admin, rev_id, reviewed)
        assert stale.status_code == 409, stale.data
        assert stale.get_json()["code"] == "stale_revision"
        assert _public_get(client, listing).get_json()["car"]["price"] == 15000

        fresh = _admin_detail(client, admin, rev_id)["revision"]["revision_token"]
        assert fresh != reviewed
        assert _approve(client, admin, rev_id, fresh).status_code == 200
        assert _public_get(client, listing).get_json()["car"]["price"] == 1

    def test_approval_requires_the_reviewed_token(self, app_ctx, client):
        listing = _published_listing(app_ctx, client)
        rev_id = _submit_edit(client, app_ctx, listing)
        admin = _admin(app_ctx, client)
        r = client.post(
            f"/api/admin/listing-revisions/{rev_id}/approve",
            json={},
            headers=_auth(admin),
        )
        assert r.status_code == 400
        assert r.get_json()["code"] == "revision_token_required"
        r = _approve(client, admin, rev_id, "not-the-token")
        assert r.status_code == 409
        assert _public_get(client, listing).get_json()["car"]["price"] == 15000

    def test_double_approval_is_idempotently_refused(self, app_ctx, client):
        listing = _published_listing(app_ctx, client)
        rev_id = _submit_edit(client, app_ctx, listing)
        admin = _admin(app_ctx, client)
        token = _admin_detail(client, admin, rev_id)["revision"]["revision_token"]
        assert _approve(client, admin, rev_id, token).status_code == 200
        second = _approve(client, admin, rev_id, token)
        assert second.status_code == 404  # revision no longer exists

    def test_approval_of_discarded_revision_fails_cleanly(self, app_ctx, client):
        listing = _published_listing(app_ctx, client)
        rev_id = _submit_edit(client, app_ctx, listing)
        admin = _admin(app_ctx, client)
        token = _admin_detail(client, admin, rev_id)["revision"]["revision_token"]
        d = client.delete(
            f"/api/cars/{listing['public_id']}/pending-revision",
            headers=_auth(listing["token"]),
        )
        assert d.status_code == 200
        assert _approve(client, admin, rev_id, token).status_code == 404
        assert _public_get(client, listing).get_json()["car"]["price"] == 15000

    def test_cannot_approve_while_listing_is_not_published(self, app_ctx, client):
        listing = _published_listing(app_ctx, client)
        rev_id = _submit_edit(client, app_ctx, listing)
        admin = _admin(app_ctx, client)
        token = _admin_detail(client, admin, rev_id)["revision"]["revision_token"]
        client.patch(
            f"/api/admin/cars/{listing['public_id']}/status",
            json={"status": "hidden"},
            headers=_auth(admin),
        )
        r = _approve(client, admin, rev_id, token)
        assert r.status_code == 409
        assert r.get_json()["code"] == "listing_not_published"

    def test_only_admins_can_decide(self, app_ctx, client):
        listing = _published_listing(app_ctx, client)
        rev_id = _submit_edit(client, app_ctx, listing)
        r = _approve(client, listing["token"], rev_id, "x")
        assert r.status_code in (401, 403)
        r = client.get(
            "/api/admin/listing-revisions", headers=_auth(listing["token"])
        )
        assert r.status_code in (401, 403)

    def test_listing_status_changes_by_admin_do_not_touch_the_revision(
        self, app_ctx, client
    ):
        from kk.models import CarRevision

        listing = _published_listing(app_ctx, client)
        _submit_edit(client, app_ctx, listing)
        admin = _admin(app_ctx, client)
        r = client.patch(
            f"/api/admin/cars/{listing['public_id']}/status",
            json={"is_featured": True},
            headers=_auth(admin),
        )
        assert r.status_code == 200, r.data
        assert _count(app_ctx, CarRevision, car_id=listing["car_id"]) == 1


# ---------------------------------------------------------------------------
# D. Photos: cover, order, new media, readiness, storage safety
# ---------------------------------------------------------------------------


class TestMedia:
    def test_photo_changes_stay_pending_until_approved_and_ids_are_stable(
        self, app_ctx, client, r2_calls
    ):
        listing = _published_listing(app_ctx, client, photos=3)
        a1, a2, a3 = listing["image_ids"]

        # The client still holds the APPROVED ids and deletes photo #2.
        r = client.delete(
            f"/api/cars/{listing['public_id']}/images/{a2}",
            headers=_auth(listing["token"]),
        )
        assert r.status_code == 200, r.data
        # ...no storage object is deleted (the approved listing still uses it)
        assert r2_calls == []
        # ...and the public gallery is untouched.
        assert _public_image_urls(client, listing) == listing["urls"]

        pending = _owner_get(client, listing)["pending_revision"]
        assert pending["status"] == "editing"  # saved media, not yet submitted
        assert [i["image_url"] for i in pending["car"]["images"]] == [
            listing["urls"][0],
            listing["urls"][2],
        ]

        # Owner submits the edit (as the app does right after).
        assert _put(client, listing, {"price": 14500}).status_code == 200
        admin = _admin(app_ctx, client)
        rev_id = _revision_ids(app_ctx, listing)[0]
        detail = _admin_detail(client, admin, rev_id)
        assert "images" in detail["revision"]["changed_fields"]
        assert (
            _approve(
                client, admin, rev_id, detail["revision"]["revision_token"]
            ).status_code
            == 200
        )

        public = _public_get(client, listing).get_json()["car"]
        assert [i["image_url"] for i in public["images"]] == [
            listing["urls"][0],
            listing["urls"][2],
        ]
        # unchanged photos kept their ids; the removed one is gone
        assert [i["id"] for i in public["images"]] == [a1, a3]
        # storage: the removed photo's object is deleted only now
        assert r2_calls == [f"car_photos/orig_{listing['car_id']}_1.jpg"]

    def test_cover_and_order_changes_publish_only_on_approval(self, app_ctx, client):
        listing = _published_listing(app_ctx, client, photos=3)
        a1, a2, a3 = listing["image_ids"]
        # New order [a3 (cover), a1, a2], expressed with the approved ids.
        r = client.put(
            f"/api/cars/{listing['public_id']}/images/layout",
            json={
                "images": [
                    {"id": a3, "order": 0, "is_primary": True},
                    {"id": a1, "order": 1},
                    {"id": a2, "order": 2},
                ]
            },
            headers=_auth(listing["token"]),
        )
        assert r.status_code == 200, r.data
        assert _put(client, listing, {"price": 14000}).status_code == 200

        # Still the old cover/order publicly.
        public = _public_get(client, listing).get_json()["car"]
        assert [i["id"] for i in public["images"]] == [a1, a2, a3]
        assert public["images"][0]["is_primary"] is True
        assert public["image_url"] == listing["urls"][0]

        admin = _admin(app_ctx, client)
        rev_id = _revision_ids(app_ctx, listing)[0]
        token = _admin_detail(client, admin, rev_id)["revision"]["revision_token"]
        assert _approve(client, admin, rev_id, token).status_code == 200

        public = _public_get(client, listing).get_json()["car"]
        assert [i["id"] for i in public["images"]] == [a3, a1, a2]
        assert public["image_url"] == listing["urls"][2]
        assert [i["is_primary"] for i in public["images"]] == [True, False, False]

    def test_new_photo_is_invisible_until_approved_then_published_with_cover(
        self, app_ctx, client
    ):
        listing = _published_listing(app_ctx, client, photos=2)
        r = _put(
            client,
            listing,
            {
                "price": 14000,
                "expected_media": [
                    {
                        "client_media_id": "rev_new_cover",
                        "kind": "image",
                        "is_cover": True,
                        "sort_order": 0,
                    }
                ],
            },
        )
        assert r.status_code == 200, r.data
        rev_id, shadow_id = _revision_ids(app_ctx, listing)
        admin = _admin(app_ctx, client)

        # New media still processing -> cannot be approved.
        token = _admin_detail(client, admin, rev_id)["revision"]["revision_token"]
        blocked = _approve(client, admin, rev_id, token)
        assert blocked.status_code == 409, blocked.data
        assert blocked.get_json()["code"] == "media_not_ready"
        summary = client.get(
            f"/api/cars/{listing['public_id']}/media-summary",
            headers=_auth(listing["token"]),
        ).get_json()
        assert summary["media_status"] == "processing"
        assert [it["client_media_id"] for it in summary["items"]] == ["rev_new_cover"]

        # Background job completes -> lands on the pending copy only.
        assert _simulate_worker_attach(app_ctx, shadow_id, "rev_new_cover") == "applied"
        assert _public_image_urls(client, listing) == listing["urls"]
        pending_urls = [
            i["image_url"]
            for i in _owner_get(client, listing)["pending_revision"]["car"]["images"]
        ]
        assert f"{_CDN}/rev_new_cover.jpg" in pending_urls

        # The completed upload changed what the admin must review.
        stale = _approve(client, admin, rev_id, token)
        assert stale.status_code == 409
        assert stale.get_json()["code"] == "stale_revision"

        token = _admin_detail(client, admin, rev_id)["revision"]["revision_token"]
        assert _approve(client, admin, rev_id, token).status_code == 200
        public_urls = _public_image_urls(client, listing)
        assert f"{_CDN}/rev_new_cover.jpg" in public_urls
        assert sorted(public_urls) == sorted(
            listing["urls"] + [f"{_CDN}/rev_new_cover.jpg"]
        )
        public = _public_get(client, listing).get_json()["car"]
        primaries = [i for i in public["images"] if i["is_primary"]]
        assert len(primaries) == 1  # exactly one cover

    @staticmethod
    def _fail_new_item(app_ctx, shadow_id, cmid):
        from kk.media_readiness import (
            mark_item_phase_a_accepted,
            transition_media_item_terminal,
        )

        app, _c = app_ctx
        with app.app_context():
            mark_item_phase_a_accepted(
                car_id=shadow_id, client_media_id=cmid, job_task_id="t"
            )
            transition_media_item_terminal(
                car_id=shadow_id, client_media_id=cmid, to_status="failed"
            )

    def test_failed_new_photo_blocks_approval_and_changes_nothing_public(
        self, app_ctx, client
    ):
        listing = _published_listing(app_ctx, client, photos=1)
        _put(
            client,
            listing,
            {
                "price": 14000,
                "expected_media": [{"client_media_id": "rev_bad", "kind": "image"}],
            },
        )
        rev_id, shadow_id = _revision_ids(app_ctx, listing)
        self._fail_new_item(app_ctx, shadow_id, "rev_bad")
        admin = _admin(app_ctx, client)
        detail = _admin_detail(client, admin, rev_id)
        media = detail["revision"]["media"]
        assert media["failed"] == 1 and media["approvable"] is False
        blocked = _approve(client, admin, rev_id, detail["revision"]["revision_token"])
        assert blocked.status_code == 409, blocked.data
        assert blocked.get_json()["code"] == "media_failed"
        # nothing was published
        public = _public_get(client, listing).get_json()["car"]
        assert public["price"] == 15000
        assert _public_image_urls(client, listing) == listing["urls"]

    def test_failed_new_cover_never_silently_publishes_another_cover(
        self, app_ctx, client
    ):
        """The seller declared a NEW photo as the cover; it fails. The
        working copy has promoted a different photo, but the approval must
        be refused rather than publishing that wrong cover."""
        listing = _published_listing(app_ctx, client, photos=3)
        _put(
            client,
            listing,
            {
                "price": 14000,
                "expected_media": [
                    {
                        "client_media_id": "rev_cover_bad",
                        "kind": "image",
                        "is_cover": True,
                        "sort_order": 0,
                    }
                ],
            },
        )
        rev_id, shadow_id = _revision_ids(app_ctx, listing)
        self._fail_new_item(app_ctx, shadow_id, "rev_cover_bad")
        admin = _admin(app_ctx, client)
        detail = _admin_detail(client, admin, rev_id)
        assert detail["revision"]["media"]["failed_cover"] is True
        blocked = _approve(client, admin, rev_id, detail["revision"]["revision_token"])
        assert blocked.status_code == 409
        assert blocked.get_json()["code"] == "media_failed"
        public = _public_get(client, listing).get_json()["car"]
        assert public["image_url"] == listing["urls"][0]
        assert [i["id"] for i in public["images"]] == listing["image_ids"]

        # The admin can still reject: previous cover preserved, owner told why.
        rej = client.post(
            f"/api/admin/listing-revisions/{rev_id}/reject",
            json={
                "revision_token": detail["revision"]["revision_token"],
                "reason": "Cover photo failed",
            },
            headers=_auth(admin),
        )
        assert rej.status_code == 200, rej.data
        public = _public_get(client, listing).get_json()["car"]
        assert public["image_url"] == listing["urls"][0]
        pending = _owner_get(client, listing)["pending_revision"]
        assert pending["status"] == "rejected"
        assert pending["rejection_reason"] == "Cover photo failed"

        # ...and the owner can discard the broken edit, keeping the listing.
        d = client.delete(
            f"/api/cars/{listing['public_id']}/pending-revision",
            headers=_auth(listing["token"]),
        )
        assert d.status_code == 200
        public = _public_get(client, listing).get_json()["car"]
        assert public["image_url"] == listing["urls"][0]
        assert public["price"] == 15000

    def test_unfinished_new_photo_cannot_be_approved_even_if_others_are_ready(
        self, app_ctx, client
    ):
        listing = _published_listing(app_ctx, client, photos=1)
        _put(
            client,
            listing,
            {
                "price": 14000,
                "expected_media": [
                    {"client_media_id": "rev_ok", "kind": "image"},
                    {"client_media_id": "rev_never_uploaded", "kind": "image"},
                ],
            },
        )
        rev_id, shadow_id = _revision_ids(app_ctx, listing)
        _simulate_worker_attach(app_ctx, shadow_id, "rev_ok")
        admin = _admin(app_ctx, client)
        detail = _admin_detail(client, admin, rev_id)
        assert detail["revision"]["media"]["approvable"] is False
        blocked = _approve(client, admin, rev_id, detail["revision"]["revision_token"])
        assert blocked.status_code == 409
        assert blocked.get_json()["code"] == "media_not_ready"
        assert _public_image_urls(client, listing) == listing["urls"]

    def test_publish_aborts_atomically_if_the_cover_would_change(
        self, app_ctx, client, monkeypatch
    ):
        """Defence in depth: whatever goes wrong inside the publication, the
        published cover is the reviewed one or nothing is published."""
        import kk.listing_revisions as lr
        from kk.models import CarImage, db

        listing = _published_listing(app_ctx, client, photos=3)
        a1, _a2, a3 = listing["image_ids"]
        client.put(
            f"/api/cars/{listing['public_id']}/images/layout",
            json={
                "images": [
                    {"id": a3, "order": 0, "is_primary": True},
                    {"id": a1, "order": 1},
                    {"id": listing["image_ids"][1], "order": 2},
                ]
            },
            headers=_auth(listing["token"]),
        )
        assert _put(client, listing, {"price": 14000}).status_code == 200

        real = lr._publish_gallery

        def sabotaged(car, shadow):
            removed = real(car, shadow)
            # simulate a bug that flips the cover during publication
            for img in CarImage.query.filter_by(car_id=car.id).all():
                img.is_primary = img.id == a1
            db.session.flush()
            return removed

        monkeypatch.setattr(lr, "_publish_gallery", sabotaged)
        admin = _admin(app_ctx, client)
        rev_id = _revision_ids(app_ctx, listing)[0]
        token = _admin_detail(client, admin, rev_id)["revision"]["revision_token"]
        r = _approve(client, admin, rev_id, token)
        assert r.status_code == 409 and r.get_json()["code"] == "cover_mismatch"

        monkeypatch.undo()
        public = _public_get(client, listing).get_json()["car"]
        assert public["price"] == 15000  # nothing published
        assert public["image_url"] == listing["urls"][0]  # previous cover kept
        # the revision is still pending and approvable afterwards
        token = _admin_detail(client, admin, rev_id)["revision"]["revision_token"]
        assert _approve(client, admin, rev_id, token).status_code == 200
        assert _public_get(client, listing).get_json()["car"]["image_url"] == (
            listing["urls"][2]
        )

    def test_discard_removes_new_media_only_and_keeps_approved_files(
        self, app_ctx, client, r2_calls
    ):
        from kk.models import Car, CarMediaItem, CarRevision

        listing = _published_listing(app_ctx, client, photos=2)
        _put(
            client,
            listing,
            {
                "price": 14000,
                "expected_media": [{"client_media_id": "rev_tmp", "kind": "image"}],
            },
        )
        _rev_id, shadow_id = _revision_ids(app_ctx, listing)
        _simulate_worker_attach(app_ctx, shadow_id, "rev_tmp")

        d = client.delete(
            f"/api/cars/{listing['public_id']}/pending-revision",
            headers=_auth(listing["token"]),
        )
        assert d.status_code == 200, d.data
        # approved listing intact and still active
        public = _public_get(client, listing).get_json()["car"]
        assert public["price"] == 15000 and public["status"] == "active"
        assert _public_image_urls(client, listing) == listing["urls"]
        assert "pending_revision" not in d.get_json()["car"]
        # working copy + manifest gone; only the NEW file was removed
        app, _c = app_ctx
        with app.app_context():
            assert Car.query.filter_by(id=shadow_id).first() is None
            assert CarMediaItem.query.filter_by(car_id=shadow_id).count() == 0
        assert _count(app_ctx, CarRevision, car_id=listing["car_id"]) == 0
        assert r2_calls == ["car_photos/rev_tmp.jpg"]
        # idempotent
        assert (
            client.delete(
                f"/api/cars/{listing['public_id']}/pending-revision",
                headers=_auth(listing["token"]),
            ).status_code
            == 200
        )

    def test_late_background_job_after_discard_is_a_noop_and_cleans_itself_up(
        self, app_ctx, client, r2_calls, monkeypatch
    ):
        import kk.tasks.image_tasks as image_tasks_module
        from kk.models import Car, CarImage

        listing = _published_listing(app_ctx, client, photos=1)
        _put(
            client,
            listing,
            {
                "expected_media": [{"client_media_id": "rev_late", "kind": "image"}],
                "price": 14000,
            },
        )
        _rev_id, shadow_id = _revision_ids(app_ctx, listing)
        client.delete(
            f"/api/cars/{listing['public_id']}/pending-revision",
            headers=_auth(listing["token"]),
        )

        app, _c = app_ctx
        with app.app_context():
            cars_before = Car.query.count()
            images_before = CarImage.query.count()
        monkeypatch.setattr(
            image_tasks_module,
            "_process_image_path",
            lambda **kw: {"rel_path": f"{_CDN}/rev_late_processed.jpg"},
        )
        with app.app_context():
            out = image_tasks_module.process_car_image_file.run(
                None,
                "photo.jpg",
                False,
                False,
                owner_public_id="x",
                source_r2_key=None,
                car_id=shadow_id,
                kind="listing",
                client_media_id="rev_late",
            )
            assert out["ok"] is True
            assert Car.query.count() == cars_before
            assert CarImage.query.count() == images_before
        # the worker removed the file it had just produced (nothing owns it)
        assert r2_calls == ["car_photos/rev_late_processed.jpg"]

    def test_late_background_job_after_publish_cannot_resurrect_the_working_copy(
        self, app_ctx, client
    ):
        from kk.models import Car

        listing = _published_listing(app_ctx, client, photos=1)
        _put(client, listing, {"price": 14000})
        rev_id, shadow_id = _revision_ids(app_ctx, listing)
        admin = _admin(app_ctx, client)
        token = _admin_detail(client, admin, rev_id)["revision"]["revision_token"]
        assert _approve(client, admin, rev_id, token).status_code == 200

        assert _simulate_worker_attach(app_ctx, shadow_id, "never_registered") in (
            "car_missing",
            "item_missing",
        )
        app, _c = app_ctx
        with app.app_context():
            assert Car.query.filter_by(id=shadow_id).first() is None

    def test_deleting_an_image_never_deletes_a_file_the_approved_version_uses(
        self, app_ctx, client, r2_calls
    ):
        listing = _published_listing(app_ctx, client, photos=2)
        working_copy_image = None
        client.delete(
            f"/api/cars/{listing['public_id']}/images/{listing['image_ids'][1]}",
            headers=_auth(listing["token"]),
        )
        assert r2_calls == []
        # a brand-new (working-copy-only) photo IS deleted from storage
        _put(
            client,
            listing,
            {"expected_media": [{"client_media_id": "rev_gone", "kind": "image"}]},
        )
        _rev, shadow_id = _revision_ids(app_ctx, listing)
        _simulate_worker_attach(app_ctx, shadow_id, "rev_gone")
        pending = _owner_get(client, listing)["pending_revision"]["car"]["images"]
        new_img = [i for i in pending if i["image_url"].endswith("rev_gone.jpg")][0]
        assert working_copy_image is None
        r = client.delete(
            f"/api/cars/{listing['public_id']}/images/{new_img['id']}",
            headers=_auth(listing["token"]),
        )
        assert r.status_code == 200, r.data
        assert r2_calls == ["car_photos/rev_gone.jpg"]

    def test_removing_the_last_photo_is_still_refused_on_a_pending_edit(
        self, app_ctx, client
    ):
        listing = _published_listing(app_ctx, client, photos=1)
        r = client.delete(
            f"/api/cars/{listing['public_id']}/images/{listing['image_ids'][0]}",
            headers=_auth(listing["token"]),
        )
        assert r.status_code == 400
        assert _public_image_urls(client, listing) == listing["urls"]


# ---------------------------------------------------------------------------
# E. Deleting an ACTIVE listing with a pending edit
# ---------------------------------------------------------------------------


class TestDeletion:
    def test_deleting_active_listing_cleans_up_revision_and_new_media(
        self, app_ctx, client, r2_calls
    ):
        from kk.models import Car, CarRevision

        listing = _published_listing(app_ctx, client, photos=2)
        _put(
            client,
            listing,
            {
                "price": 14000,
                "expected_media": [{"client_media_id": "rev_del", "kind": "image"}],
            },
        )
        _rev, shadow_id = _revision_ids(app_ctx, listing)
        _simulate_worker_attach(app_ctx, shadow_id, "rev_del")

        r = client.delete(
            f"/api/cars/{listing['public_id']}", headers=_auth(listing["token"])
        )
        assert r.status_code == 200, r.data
        assert _public_get(client, listing).status_code == 404
        app, _c = app_ctx
        with app.app_context():
            assert Car.query.filter_by(id=shadow_id).first() is None
        assert _count(app_ctx, CarRevision, car_id=listing["car_id"]) == 0
        # soft delete keeps the approved files; only the pending-only file goes
        assert r2_calls == ["car_photos/rev_del.jpg"]

    def test_admin_delete_and_purge_also_clean_up_the_revision(
        self, app_ctx, client
    ):
        from kk.models import Car

        admin = _admin(app_ctx, client)
        for endpoint in ("delete", "purge"):
            listing = _published_listing(app_ctx, client)
            _put(client, listing, {"price": 14000})
            _rev, shadow_id = _revision_ids(app_ctx, listing)
            if endpoint == "delete":
                r = client.delete(
                    f"/api/admin/cars/{listing['public_id']}", headers=_auth(admin)
                )
            else:
                r = client.delete(
                    f"/api/admin/cars/{listing['public_id']}/purge",
                    headers=_auth(admin),
                )
            assert r.status_code == 200, (endpoint, r.data)
            app, _c = app_ctx
            with app.app_context():
                assert Car.query.filter_by(id=shadow_id).first() is None

    def test_owner_edit_after_delete_is_not_found(self, app_ctx, client):
        listing = _published_listing(app_ctx, client)
        client.delete(
            f"/api/cars/{listing['public_id']}", headers=_auth(listing["token"])
        )
        assert _put(client, listing, {"price": 1}).status_code == 404


# ---------------------------------------------------------------------------
# F. Permissions
# ---------------------------------------------------------------------------


class TestPermissions:
    def test_non_owner_cannot_edit_discard_or_touch_media(self, app_ctx, client):
        from kk.models import Car, CarRevision

        listing = _published_listing(app_ctx, client)
        _submit_edit(client, app_ctx, listing)
        _uid, other = _make_user(app_ctx)
        stranger = _login(client, other)

        put = client.put(
            f"/api/cars/{listing['public_id']}",
            json={"price": 1},
            headers=_auth(stranger),
        )
        assert put.status_code == 403
        assert (
            client.get(
                f"/api/cars/{listing['public_id']}/pending-revision",
                headers=_auth(stranger),
            ).status_code
            == 403
        )
        assert (
            client.delete(
                f"/api/cars/{listing['public_id']}/pending-revision",
                headers=_auth(stranger),
            ).status_code
            == 403
        )
        media = client.delete(
            f"/api/cars/{listing['public_id']}/images/{listing['image_ids'][0]}",
            headers=_auth(stranger),
        )
        assert media.status_code == 403
        # nothing changed
        assert _count(app_ctx, CarRevision, car_id=listing["car_id"]) == 1
        assert _public_get(client, listing).get_json()["car"]["price"] == 15000
        assert _public_image_urls(client, listing) == listing["urls"]
        _ = Car

    def test_non_owner_cannot_start_a_revision_via_media_routes(
        self, app_ctx, client
    ):
        from kk.models import CarRevision

        listing = _published_listing(app_ctx, client)
        _uid, other = _make_user(app_ctx)
        stranger = _login(client, other)
        r = client.put(
            f"/api/cars/{listing['public_id']}/images/layout",
            json={"images": [{"id": listing["image_ids"][0], "order": 0}]},
            headers=_auth(stranger),
        )
        assert r.status_code == 403
        assert _count(app_ctx, CarRevision, car_id=listing["car_id"]) == 0

    def test_unauthenticated_requests_are_rejected(self, app_ctx, client):
        listing = _published_listing(app_ctx, client)
        assert (
            client.put(
                f"/api/cars/{listing['public_id']}", json={"price": 1}
            ).status_code
            == 401
        )
        assert (
            client.delete(
                f"/api/cars/{listing['public_id']}/pending-revision"
            ).status_code
            == 401
        )

    def test_pending_revision_endpoint_404_when_none(self, app_ctx, client):
        listing = _published_listing(app_ctx, client)
        r = client.get(
            f"/api/cars/{listing['public_id']}/pending-revision",
            headers=_auth(listing["token"]),
        )
        assert r.status_code == 404

    def test_get_pending_revision_returns_working_copy(self, app_ctx, client):
        listing = _published_listing(app_ctx, client)
        _submit_edit(client, app_ctx, listing, {"price": 9999})
        r = client.get(
            f"/api/cars/{listing['public_id']}/pending-revision",
            headers=_auth(listing["token"]),
        )
        assert r.status_code == 200
        assert r.get_json()["pending_revision"]["car"]["price"] == 9999


# ---------------------------------------------------------------------------
# G. Concurrency / invariants / isolation
# ---------------------------------------------------------------------------


class TestInvariants:
    def test_ensure_revision_is_idempotent_and_unique_per_listing(self, app_ctx, client):
        from sqlalchemy.exc import IntegrityError

        from kk.listing_revisions import ensure_revision
        from kk.models import Car, CarRevision, db

        listing = _published_listing(app_ctx, client)
        app, _c = app_ctx
        with app.app_context():
            car = db.session.get(Car, listing["car_id"])
            first = ensure_revision(car)
            db.session.commit()
            second = ensure_revision(db.session.get(Car, listing["car_id"]))
            assert first.id == second.id
            assert CarRevision.query.filter_by(car_id=listing["car_id"]).count() == 1
            # The database itself forbids a second revision for a listing.
            db.session.add(
                CarRevision(car_id=listing["car_id"], shadow_car_id=first.shadow_car_id)
            )
            with pytest.raises(IntegrityError):
                db.session.flush()
            db.session.rollback()

    def test_working_copy_is_hidden_everywhere_public(self, app_ctx, client):
        from kk.models import Car

        listing = _published_listing(app_ctx, client)
        _submit_edit(client, app_ctx, listing)
        _rev, shadow_id = _revision_ids(app_ctx, listing)
        app, _c = app_ctx
        with app.app_context():
            shadow_public = Car.query.get(shadow_id).public_id
        # direct fetch by its own id: 404 for everyone, including the owner
        for headers in ({}, _auth(listing["token"])):
            assert client.get(f"/api/cars/{shadow_public}", headers=headers).status_code == 404
            assert client.get(f"/api/cars/{shadow_id}", headers=headers).status_code in (404,)
        ids = [c["id"] for c in client.get("/api/cars").get_json()["cars"]]
        assert shadow_public not in ids
        # nor is it editable/deletable as a listing
        assert (
            client.put(
                f"/api/cars/{shadow_public}",
                json={"price": 1},
                headers=_auth(listing["token"]),
            ).status_code
            == 404
        )

    def test_admin_listing_endpoints_exclude_working_copies(self, app_ctx, client):
        listing = _published_listing(app_ctx, client)
        _submit_edit(client, app_ctx, listing)
        _rev, shadow_id = _revision_ids(app_ctx, listing)
        admin = _admin(app_ctx, client)

        from kk.models import Car

        app, _c = app_ctx
        with app.app_context():
            shadow_public = Car.query.get(shadow_id).public_id
            real = Car.query.filter(Car.status != "revision").count()
        r = client.get("/api/admin/cars?per_page=100", headers=_auth(admin))
        body = r.get_json()
        assert body["pagination"]["total"] == real
        assert shadow_public not in [c["id"] for c in body["cars"]]
        assert (
            client.get(f"/api/admin/cars/{shadow_public}", headers=_auth(admin)).status_code
            == 404
        )
        stats = client.get("/api/admin/dashboard", headers=_auth(admin)).get_json()["stats"]
        assert stats["total_cars"] == real
        assert stats["pending_listing_revisions"] >= 1
        badges = client.get("/api/admin/meta/badges", headers=_auth(admin)).get_json()
        assert badges["pending_listing_revisions"] >= 1
        imgs = client.get("/api/admin/images?per_page=100", headers=_auth(admin)).get_json()
        assert all(i["car"]["status"] != "revision" for i in imgs["images"])

    def test_existing_listing_behaviour_unchanged_for_other_listings(
        self, app_ctx, client
    ):
        """A listing with no revision behaves exactly as before."""
        listing = _published_listing(app_ctx, client)
        other = _published_listing(app_ctx, client)
        _submit_edit(client, app_ctx, listing)
        assert _public_get(client, other).get_json()["car"]["price"] == 15000
        assert "pending_revision" not in _owner_get(client, other)

    def test_working_copy_is_a_full_clone_of_the_approved_listing(self, app_ctx, client):
        listing = _published_listing(app_ctx, client, photos=3)
        _submit_edit(client, app_ctx, listing, {"mileage": 5})
        pending = _owner_get(client, listing)["pending_revision"]["car"]
        assert pending["mileage"] == 5
        assert pending["brand"] == "toyota" and pending["year"] == 2021
        assert [i["image_url"] for i in pending["images"]] == listing["urls"]
        assert [i["is_primary"] for i in pending["images"]] == [True, False, False]
        # carried photos are reported with their client ids for the overlay
        assert all("client_media_id" in i for i in pending["images"])


# ---------------------------------------------------------------------------
# H. Migration
# ---------------------------------------------------------------------------


def test_migration_is_single_head_additive_and_reversible(tmp_path):
    from alembic.config import Config
    from alembic.script import ScriptDirectory

    cfg = Config()
    cfg.set_main_option("script_location", str(_REPO_ROOT / "migrations"))
    script = ScriptDirectory.from_config(cfg)
    heads = script.get_heads()
    assert heads == ["u9v0w1x2y3z4"]
    rev = script.get_revision("u9v0w1x2y3z4")
    assert rev.down_revision == "t8u9v0w1x2y3"

    src = (
        _REPO_ROOT / "migrations" / "versions" / "u9v0w1x2y3z4_add_car_revision_table.py"
    ).read_text(encoding="utf-8")
    # purely additive: creates one table, alters/drops nothing that exists
    assert src.count("op.create_table(") == 1
    upgrade_body = src.split("def upgrade()")[1].split("def downgrade()")[0]
    for forbidden in ("drop_", "alter_column", "add_column", "batch_alter_table"):
        assert forbidden not in upgrade_body


# ---------------------------------------------------------------------------
# Account deletion
# ---------------------------------------------------------------------------


def test_account_deletion_scrubs_pending_edit_without_listing_it_as_hidden(
    app_ctx, client
):
    """The working copy of a pending edit belongs to the deleted account, so
    it is scrubbed (media rows dropped, PII cleared, inactive) -- but it must
    keep its `revision` marker so it never turns into a second, 'hidden'
    listing in admin views."""
    from kk.models import Car, CarImage, db
    from kk.routes.auth import _delete_and_scrub_user_listings

    app, _c = app_ctx
    listing = _published_listing(app_ctx, client)
    _submit_edit(client, app_ctx, listing, {"description": "My phone 0770"})
    _rev_id, shadow_id = _revision_ids(app_ctx, listing)

    with app.app_context():
        table_names = set(db.inspect(db.engine).get_table_names())
        _delete_and_scrub_user_listings(listing["uid"], table_names)
        db.session.commit()
        shadow = db.session.get(Car, shadow_id)
        approved = db.session.get(Car, listing["car_id"])
        assert shadow.status == "revision"
        assert shadow.is_active is False
        assert shadow.description is None
        assert CarImage.query.filter_by(car_id=shadow_id).count() == 0
        assert approved.status == "hidden"
        assert approved.is_active is False

# ---------------------------------------------------------------------------
# Release hardening: old installed apps, abandoned edits, shadow protection
# ---------------------------------------------------------------------------


def _age_revision(app_ctx, listing, *, seconds: int):
    """Pretend the owner last touched the revision `seconds` ago."""
    from datetime import timedelta

    from kk.models import CarRevision, db
    from kk.time_utils import utcnow

    app, _c = app_ctx
    with app.app_context():
        rev = CarRevision.query.filter_by(car_id=listing["car_id"]).one()
        rev.updated_at = utcnow() - timedelta(seconds=seconds)
        db.session.commit()


def _revision_status(app_ctx, listing):
    from kk.models import CarRevision

    app, _c = app_ctx
    with app.app_context():
        rev = CarRevision.query.filter_by(car_id=listing["car_id"]).first()
        return rev.status if rev else None


def _queue(client, admin) -> list[str]:
    r = client.get("/api/admin/listing-revisions", headers=_auth(admin))
    assert r.status_code == 200, r.data
    return [x["id"] for x in r.get_json()["revisions"]]


class TestOldInstalledApps:
    """An installed app that predates review never sends the submit call (it
    just calls the media routes). It must not be able to publish anything,
    replace approved media, or leave its change silently stuck."""

    def _old_app_photo_edit(self, client, listing):
        """What an old build does to an Active listing: delete photo #2 and
        make photo #3 the cover, straight through the media routes."""
        a1, a2, a3 = listing["image_ids"]
        r = client.delete(
            f"/api/cars/{listing['public_id']}/images/{a2}",
            headers=_auth(listing["token"]),
        )
        assert r.status_code == 200, r.data
        r = client.put(
            f"/api/cars/{listing['public_id']}/images/primary",
            json={"image_url": listing["urls"][2]},
            headers=_auth(listing["token"]),
        )
        assert r.status_code == 200, r.data

    def test_old_app_media_edit_cannot_change_public_media_or_delete_files(
        self, app_ctx, client, r2_calls
    ):
        listing = _published_listing(app_ctx, client, photos=3)
        self._old_app_photo_edit(client, listing)
        public = _public_get(client, listing).get_json()["car"]
        assert [i["id"] for i in public["images"]] == listing["image_ids"]
        assert public["image_url"] == listing["urls"][0]  # approved cover kept
        assert r2_calls == []  # approved files untouched
        # held privately, never in the admin queue until submitted
        assert _revision_status(app_ctx, listing) == "editing_legacy"
        assert (
            _owner_get(client, listing)["pending_revision"]["status"] == "editing"
        )  # the internal marker is never exposed
        admin = _admin(app_ctx, client)
        rev_id = _revision_ids(app_ctx, listing)[0]
        assert rev_id not in _queue(client, admin)

    def test_unsubmitted_edit_cannot_be_approved(self, app_ctx, client):
        listing = _published_listing(app_ctx, client, photos=3)
        self._old_app_photo_edit(client, listing)
        admin = _admin(app_ctx, client)
        rev_id = _revision_ids(app_ctx, listing)[0]
        # not even shown to admins while unsubmitted...
        assert (
            client.get(
                f"/api/admin/listing-revisions/{rev_id}", headers=_auth(admin)
            ).status_code
            == 404
        )
        # ...and a direct approve (any token) is refused.
        r = _approve(client, admin, rev_id, "whatever")
        assert r.status_code == 409
        assert r.get_json()["code"] == "revision_not_pending"
        assert _public_image_urls(client, listing) == listing["urls"]

    def test_idle_old_app_edit_is_submitted_for_review_not_lost(
        self, app_ctx, client, r2_calls
    ):
        from kk.listing_revisions import sweep_idle_editing_revisions

        listing = _published_listing(app_ctx, client, photos=3)
        self._old_app_photo_edit(client, listing)
        app, _c = app_ctx
        admin = _admin(app_ctx, client)
        rev_id = _revision_ids(app_ctx, listing)[0]

        # Still being worked on: left alone.
        with app.app_context():
            sweep_idle_editing_revisions()
        assert _revision_status(app_ctx, listing) == "editing_legacy"

        _age_revision(app_ctx, listing, seconds=3600)
        with app.app_context():
            out = sweep_idle_editing_revisions()
        assert out["submitted"] >= 1
        assert _revision_status(app_ctx, listing) == "pending"
        # Public is STILL the approved version: submitting is not publishing.
        assert _public_image_urls(client, listing) == listing["urls"]
        assert rev_id in _queue(client, admin)

        token = _admin_detail(client, admin, rev_id)["revision"]["revision_token"]
        assert _approve(client, admin, rev_id, token).status_code == 200
        public = _public_get(client, listing).get_json()["car"]
        assert [i["image_url"] for i in public["images"]] == [
            listing["urls"][2],
            listing["urls"][0],
        ]
        assert public["image_url"] == listing["urls"][2]

    def test_idle_edit_that_changes_nothing_is_discarded_without_touching_files(
        self, app_ctx, client, r2_calls
    ):
        from kk.listing_revisions import sweep_idle_editing_revisions
        from kk.models import Car, CarRevision

        listing = _published_listing(app_ctx, client, photos=2)
        # An old app opens a revision by touching media, then restores it.
        a1, _a2 = listing["image_ids"]
        client.put(
            f"/api/cars/{listing['public_id']}/images/primary",
            json={"image_url": listing["urls"][0]},
            headers=_auth(listing["token"]),
        )
        _rev_id, shadow_id = _revision_ids(app_ctx, listing)
        _age_revision(app_ctx, listing, seconds=3600)
        app, _c = app_ctx
        with app.app_context():
            out = sweep_idle_editing_revisions()
            assert out["discarded"] >= 1
            assert Car.query.filter_by(id=shadow_id).first() is None
            assert CarRevision.query.filter_by(car_id=listing["car_id"]).count() == 0
        assert r2_calls == []  # shared approved files were never deleted
        assert _public_image_urls(client, listing) == listing["urls"]

    # -- legacy auto-finalization is limited to complete drafts ------------

    def _legacy_draft_with_item(self, app_ctx, client, *, item_status: str):
        """An old-app draft (no review-aware header) that also declared one
        new upload which is stuck / failed."""
        from kk.models import CarMediaItem, db

        listing = _published_listing(app_ctx, client, photos=2)
        self._old_app_photo_edit_primary(client, listing)
        _rev_id, shadow_id = _revision_ids(app_ctx, listing)
        app, _c = app_ctx
        with app.app_context():
            db.session.add(
                CarMediaItem(
                    car_id=shadow_id,
                    kind="image",
                    client_media_id=f"item_{item_status}",
                    status=item_status,
                )
            )
            db.session.commit()
        assert _revision_status(app_ctx, listing) == "editing_legacy"
        return listing

    def _old_app_photo_edit_primary(self, client, listing):
        r = client.put(
            f"/api/cars/{listing['public_id']}/images/primary",
            json={"image_url": listing["urls"][1]},
            headers=_auth(listing["token"]),
        )
        assert r.status_code == 200, r.data

    @pytest.mark.parametrize("item_status", ["awaiting_upload", "processing", "failed"])
    def test_legacy_draft_with_unfinished_or_failed_upload_is_never_submitted(
        self, app_ctx, client, r2_calls, item_status
    ):
        from kk.listing_revisions import sweep_idle_editing_revisions

        listing = self._legacy_draft_with_item(app_ctx, client, item_status=item_status)
        app, _c = app_ctx
        admin = _admin(app_ctx, client)
        rev_id = _revision_ids(app_ctx, listing)[0]
        # Idle for an hour, a day, a month: still never auto-submitted.
        for seconds in (3600, 24 * 3600, 30 * 24 * 3600):
            _age_revision(app_ctx, listing, seconds=seconds)
            with app.app_context():
                sweep_idle_editing_revisions()
            assert _revision_status(app_ctx, listing) == "editing_legacy"
        assert rev_id not in _queue(client, admin)
        # ...kept (not destroyed), and the public listing is untouched.
        assert _revision_ids(app_ctx, listing) is not None
        assert _public_image_urls(client, listing) == listing["urls"]
        assert _public_get(client, listing).get_json()["car"]["image_url"] == (
            listing["urls"][0]
        )
        assert r2_calls == []

    def test_legacy_draft_with_empty_gallery_is_not_complete(self, app_ctx, client):
        from kk.listing_revisions import sweep_idle_editing_revisions
        from kk.models import CarImage, db

        listing = _published_listing(app_ctx, client, photos=2)
        self._old_app_photo_edit_primary(client, listing)
        _rev_id, shadow_id = _revision_ids(app_ctx, listing)
        app, _c = app_ctx
        with app.app_context():
            CarImage.query.filter_by(car_id=shadow_id).delete()
            db.session.commit()
        _age_revision(app_ctx, listing, seconds=3600)
        with app.app_context():
            assert sweep_idle_editing_revisions()["submitted"] == 0
        assert _revision_status(app_ctx, listing) == "editing_legacy"
        assert _public_image_urls(client, listing) == listing["urls"]

    def test_complete_legacy_draft_is_only_submitted_never_published(
        self, app_ctx, client, r2_calls
    ):
        from kk.listing_revisions import sweep_idle_editing_revisions

        listing = _published_listing(app_ctx, client, photos=3)
        self._old_app_photo_edit(client, listing)
        _age_revision(app_ctx, listing, seconds=3600)
        app, _c = app_ctx
        with app.app_context():
            assert sweep_idle_editing_revisions()["submitted"] == 1
        assert _revision_status(app_ctx, listing) == "pending"
        # Waiting for an admin: public media and cover are exactly as approved.
        assert _public_image_urls(client, listing) == listing["urls"]
        assert _public_get(client, listing).get_json()["car"]["image_url"] == (
            listing["urls"][0]
        )
        assert r2_calls == []

    # -- review-aware (current) builds: drafts are the seller's ------------

    def _aware(self, listing):
        return {**_auth(listing["token"]), "X-Carnet-Review-Aware": "1"}

    def _modern_draft(self, client, listing, *, change: bool = True):
        r = client.put(
            f"/api/cars/{listing['public_id']}/images/primary",
            json={"image_url": listing["urls"][1 if change else 0]},
            headers=self._aware(listing),
        )
        assert r.status_code == 200, r.data

    @pytest.mark.parametrize("change", [True, False])
    def test_review_aware_draft_is_never_auto_submitted_or_discarded(
        self, app_ctx, client, r2_calls, change
    ):
        from kk.listing_revisions import sweep_idle_editing_revisions

        listing = _published_listing(app_ctx, client, photos=2)
        self._modern_draft(client, listing, change=change)
        assert _revision_status(app_ctx, listing) == "editing"
        app, _c = app_ctx
        admin = _admin(app_ctx, client)
        rev_id = _revision_ids(app_ctx, listing)[0]
        for seconds in (3600, 8 * 24 * 3600, 90 * 24 * 3600):
            _age_revision(app_ctx, listing, seconds=seconds)
            with app.app_context():
                sweep_idle_editing_revisions()  # (other tests' legacy drafts may be swept)
            assert _revision_status(app_ctx, listing) == "editing"
            assert _revision_ids(app_ctx, listing) is not None  # not discarded
        assert rev_id not in _queue(client, admin)
        assert _public_image_urls(client, listing) == listing["urls"]
        assert r2_calls == []
        # The seller can still finish it: an explicit save submits it.
        r = client.put(
            f"/api/cars/{listing['public_id']}",
            json={"price": 12000},
            headers=self._aware(listing),
        )
        assert r.status_code == 200 and r.get_json()["submitted_for_review"] is True
        assert _revision_status(app_ctx, listing) == "pending"

    def test_review_aware_put_creates_a_normal_draft_and_submits(self, app_ctx, client):
        listing = _published_listing(app_ctx, client, photos=1)
        r = client.put(
            f"/api/cars/{listing['public_id']}",
            json={"price": 12000},
            headers=self._aware(listing),
        )
        assert r.status_code == 200
        assert _revision_status(app_ctx, listing) == "pending"

    def test_review_aware_request_turns_a_legacy_draft_into_the_sellers_draft(
        self, app_ctx, client
    ):
        from kk.listing_revisions import sweep_idle_editing_revisions

        listing = _published_listing(app_ctx, client, photos=2)
        self._old_app_photo_edit_primary(client, listing)
        assert _revision_status(app_ctx, listing) == "editing_legacy"
        # The seller then opens the new app on the same listing.
        self._modern_draft(client, listing)
        assert _revision_status(app_ctx, listing) == "editing"
        _age_revision(app_ctx, listing, seconds=30 * 24 * 3600)
        app, _c = app_ctx
        with app.app_context():
            assert sweep_idle_editing_revisions()["submitted"] == 0
        assert _revision_status(app_ctx, listing) == "editing"

    def test_legacy_request_never_downgrades_a_review_aware_draft(
        self, app_ctx, client
    ):
        listing = _published_listing(app_ctx, client, photos=2)
        self._modern_draft(client, listing)
        self._old_app_photo_edit_primary(client, listing)  # e.g. an old device
        assert _revision_status(app_ctx, listing) == "editing"

    def test_rejected_edit_touched_by_an_old_app_is_not_auto_submittable(
        self, app_ctx, client
    ):
        from kk.listing_revisions import sweep_idle_editing_revisions

        listing = _published_listing(app_ctx, client, photos=2)
        rev_id = _submit_edit(client, app_ctx, listing)
        admin = _admin(app_ctx, client)
        token = _admin_detail(client, admin, rev_id)["revision"]["revision_token"]
        r = client.post(
            f"/api/admin/listing-revisions/{rev_id}/reject",
            json={"revision_token": token, "reason": "blurry"},
            headers=_auth(admin),
        )
        assert r.status_code == 200, r.data
        self._old_app_photo_edit_primary(client, listing)
        assert _revision_status(app_ctx, listing) == "editing"
        _age_revision(app_ctx, listing, seconds=30 * 24 * 3600)
        app, _c = app_ctx
        with app.app_context():
            assert sweep_idle_editing_revisions()["submitted"] == 0

    def test_old_app_put_response_is_compatible(self, app_ctx, client):
        """The old app only reads message/car from the PUT response."""
        listing = _published_listing(app_ctx, client)
        body = _put(client, listing, {"price": 12000}).get_json()
        assert body["car"]["price"] == 15000  # approved value, as before: a car
        assert body["car"]["id"] == listing["public_id"]
        assert body["message"]


class TestShadowListingProtection:
    """The hidden working copy (status='revision') is not a listing: it must
    not appear in search, counts, favorites, chat, metrics, notifications or
    My Listings, and must not be reachable by id."""

    def _setup(self, app_ctx, client):
        from kk.models import Car

        listing = _published_listing(app_ctx, client)
        _submit_edit(client, app_ctx, listing, {"price": 12000, "description": "Edited"})
        _rev_id, shadow_id = _revision_ids(app_ctx, listing)
        app, _c = app_ctx
        with app.app_context():
            shadow_public = Car.query.get(shadow_id).public_id
        _uid, uname = _make_user(app_ctx)
        other = _login(client, uname)
        return listing, shadow_id, shadow_public, other

    def test_not_in_search_lists_or_counts(self, app_ctx, client):
        from kk.models import Car, User

        listing, shadow_id, shadow_public, _other = self._setup(app_ctx, client)
        app, _c = app_ctx
        with app.app_context():
            expected = (
                Car.query.join(User, Car.seller_id == User.id)
                .filter(
                    Car.is_active.is_(True),
                    Car.status.in_(("active", "sold")),
                )
                .count()
            )
        for url in (
            "/api/cars?per_page=100",
            "/cars?per_page=100",
            "/api/cars?per_page=100&brand=toyota",
            "/api/cars?per_page=100&q=camry",
            "/api/cars?per_page=100&sort_by=price_asc",
            "/api/cars?per_page=100&sort_by=newest",
        ):
            r = client.get(url)
            assert r.status_code == 200, (url, r.data)
            body = r.get_json()
            cars = body if isinstance(body, list) else body["cars"]
            ids = {str(c["id"]) for c in cars}
            assert shadow_public not in ids and str(shadow_id) not in ids, url
        total = (client.get("/api/cars?per_page=1").get_json().get("pagination") or {}).get(
            "total"
        )
        if total is not None:
            assert total == expected

    def test_not_reachable_by_id_for_anyone(self, app_ctx, client):
        listing, shadow_id, shadow_public, other = self._setup(app_ctx, client)
        for ident in (shadow_public, str(shadow_id)):
            for headers in ({}, _auth(other), _auth(listing["token"])):
                assert client.get(f"/api/cars/{ident}", headers=headers).status_code == 404
                assert (
                    client.get(f"/api/cars/{ident}/contact", headers=headers).status_code
                    in (401, 404)
                )
            assert client.get(f"/listing/{ident}").status_code == 404
            # favorites
            r = client.post(f"/api/cars/{ident}/favorite", headers=_auth(other))
            assert r.status_code == 404, r.data
            # report
            r = client.post(
                f"/api/cars/{ident}/report",
                json={"reason": "spam"},
                headers=_auth(other),
            )
            assert r.status_code == 404, r.data
            # owner actions that must apply to the real listing only
            for action in ("mark-sold", "mark-active"):
                r = client.post(
                    f"/api/cars/{ident}/{action}", headers=_auth(listing["token"])
                )
                assert r.status_code == 404, (action, r.data)
        favs = client.get("/api/user/favorites", headers=_auth(other)).get_json()
        assert "cars" in favs or "favorites" in favs or isinstance(favs, (list, dict))

    def test_not_in_chat_metrics_or_view_history(self, app_ctx, client):
        from kk.models import Car, Message

        listing, shadow_id, shadow_public, other = self._setup(app_ctx, client)
        app, _c = app_ctx
        for ident in (shadow_public, str(shadow_id)):
            assert (
                client.get(
                    f"/api/chat/{ident}/messages", headers=_auth(other)
                ).status_code
                == 404
            )
            r = client.post(
                f"/api/chat/{ident}/send",
                json={"content": "hello", "receiver_id": listing["public_id"]},
                headers=_auth(other),
            )
            assert r.status_code == 404, r.data
            for path in (
                "/api/analytics/track/view",
                "/api/analytics/track/share",
                "/api/analytics/track/favorite",
            ):
                r = client.post(path, json={"listing_id": ident}, headers=_auth(other))
                assert r.status_code == 404, (path, r.data)
            r = client.post(
                "/api/user/recently-viewed",
                json={"listing_id": ident},
                headers=_auth(other),
            )
            assert r.status_code in (400, 404), r.data
        with app.app_context():
            assert Message.query.filter_by(car_id=shadow_id).count() == 0
            assert Car.query.get(shadow_id).views_count == 0
        rv = client.get("/api/user/recently-viewed", headers=_auth(other)).get_json()
        assert shadow_public not in str(rv)

    def test_not_in_my_listings(self, app_ctx, client):
        listing, shadow_id, shadow_public, _other = self._setup(app_ctx, client)
        for url in ("/api/user/my-listings", "/api/my_listings"):
            r = client.get(url, headers=_auth(listing["token"]))
            assert r.status_code == 200, (url, r.data)
            body = r.get_json()
            cars = body if isinstance(body, list) else (body.get("cars") or body.get("listings") or [])
            ids = [str(c["id"]) for c in cars]
            assert ids == [listing["public_id"]], (url, ids)
            assert cars[0]["pending_revision"]["status"] == "pending"

    def test_edit_and_approval_send_no_listing_notifications(
        self, app_ctx, client, monkeypatch
    ):
        import kk.routes.cars as cars_routes
        from kk.models import Notification

        calls = []
        monkeypatch.setattr(
            cars_routes, "dispatch_saved_search_alerts", lambda *a, **k: calls.append(a)
        )
        app, _c = app_ctx
        listing = _published_listing(app_ctx, client)
        other_uid, _n = _make_user(app_ctx)
        with app.app_context():
            before = Notification.query.filter(Notification.user_id == other_uid).count()
        _submit_edit(client, app_ctx, listing, {"price": 12000})
        admin = _admin(app_ctx, client)
        rev_id = _revision_ids(app_ctx, listing)[0]
        token = _admin_detail(client, admin, rev_id)["revision"]["revision_token"]
        assert _approve(client, admin, rev_id, token).status_code == 200
        assert calls == []  # an edit is never a "new listing" alert
        with app.app_context():
            assert (
                Notification.query.filter(Notification.user_id == other_uid).count()
                == before
            )
