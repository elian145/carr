"""Cover-photo selection must be server-owned.

Real-device bug: the seller starred photo N (not the first) on the Sell page,
but the published listing still used another photo as its cover. Root cause:
the cover/order lived only in the Flutter client; the backend's self-attach
(`attach_processed_car_image`) made the cover whichever photo finished
processing first and never set `order`, and `Car.images` had no `order_by`.

The create-time `expected_media` manifest now declares `is_cover` /
`sort_order`; these tests pin the server half of the contract:

  * validation (at most one cover, images only, tolerant ordering),
  * the manifest persists the choice atomically with the car,
  * the cover wins regardless of the order uploads/processing complete in,
  * legacy manifests (no cover declared) behave exactly as before,
  * a permanently failed cover falls back safely,
  * the serialized `images` / `image_url` put the cover first,
  * editing the cover afterwards (layout / primary endpoints) sticks,
  * deleting the cover promotes a safe fallback.
"""

from __future__ import annotations

import os
import sys
import tempfile
from pathlib import Path

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from kk.tests.test_media_readiness_manifest import (  # noqa: E402
    _auth,
    _base_car_payload,
    _login,
    _make_user,
)

_R2_KEYS = (
    "R2_ACCOUNT_ID",
    "R2_BUCKET_NAME",
    "R2_ACCESS_KEY_ID",
    "R2_SECRET_ACCESS_KEY",
)


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(
        prefix="carlist_cover_selection_", ignore_cleanup_errors=True
    )
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "cover_selection.db")
    os.environ["UPLOAD_FOLDER"] = os.path.join(tmp.name, "uploads")
    for key in _R2_KEYS + ("R2_PUBLIC_URL",):
        os.environ.pop(key, None)

    from kk.app_factory import create_app

    app, socketio, *_ = create_app()
    from kk.models import Car, CarImage, CarMediaItem, CarVideo, User, db

    with app.app_context():
        db.drop_all()
        db.create_all()

    yield app, socketio, app.test_client(), db, User, Car, CarImage, CarVideo, CarMediaItem

    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    tmp.cleanup()


@pytest.fixture
def client(app_ctx):
    return app_ctx[2]


_IDS = [f"img_cover_{n}" for n in range(1, 6)]


def _manifest(cover_index: int | None, ids=_IDS) -> list[dict]:
    """What the Flutter client sends: grid order in the array, `sort_order` =
    position in the cover-first display order, `is_cover` on the starred one."""
    display = list(range(len(ids)))
    if cover_index is not None:
        display.remove(cover_index)
        display.insert(0, cover_index)
    out = []
    for grid_i, cmid in enumerate(ids):
        entry = {"client_media_id": cmid, "kind": "image"}
        if cover_index is not None:
            entry["sort_order"] = display.index(grid_i)
            if grid_i == cover_index:
                entry["is_cover"] = True
        out.append(entry)
    return out


def _create(client, token, app_ctx, manifest) -> dict:
    r = client.post(
        "/api/cars",
        json=_base_car_payload(expected_media=manifest),
        headers=_auth(token),
    )
    assert r.status_code == 201, r.data
    car = r.get_json()["car"]
    app, *_rest = app_ctx
    Car = app_ctx[5]
    with app.app_context():
        car["db_id"] = Car.query.filter_by(public_id=car["id"]).one().id
    return car


def _attach(app_ctx, car, cmid: str, *, kind: str = "listing") -> None:
    """The worker's terminal transition (lock + self-attach) for one item."""
    from kk.media_readiness import (
        mark_item_phase_a_accepted,
        transition_media_item_terminal,
    )
    from kk.routes.media import attach_processed_car_image

    app = app_ctx[0]
    with app.app_context():
        mark_item_phase_a_accepted(
            car_id=car["db_id"], client_media_id=cmid, job_task_id=f"t-{cmid}"
        )
        transition_media_item_terminal(
            car_id=car["db_id"],
            client_media_id=cmid,
            to_status="attached",
            attach_fn=lambda car_obj: attach_processed_car_image(
                car_obj,
                kind=kind,
                rel_path=f"https://cdn.example.com/uploads/{cmid}.jpg",
                source_media_id=cmid,
            ),
        )


def _get(client, token, car) -> dict:
    r = client.get(f"/api/cars/{car['id']}", headers=_auth(token))
    assert r.status_code == 200, r.data
    return r.get_json()["car"]


def _url(cmid: str) -> str:
    return f"https://cdn.example.com/uploads/{cmid}.jpg"


def _owner_cmid_order(car_json: dict) -> list[str]:
    return [img["client_media_id"] for img in car_json["images"]]


@pytest.fixture
def seller(client, app_ctx):
    _uid, username, _pub = _make_user(app_ctx, tag="cover")
    return _login(client, username)


# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------


class TestManifestValidation:
    def test_accepts_one_cover_and_sort_order(self):
        from kk.media_readiness import validate_expected_media

        out = validate_expected_media(_manifest(2))
        covers = [e for e in out if e.get("is_cover")]
        assert [e["client_media_id"] for e in covers] == [_IDS[2]]
        assert [e["sort_order"] for e in out] == [1, 2, 0, 3, 4]

    def test_string_encodings_are_tolerated(self):
        from kk.media_readiness import validate_expected_media

        out = validate_expected_media(
            [
                {"client_media_id": "a1", "kind": "image", "is_cover": "true", "sort_order": "0"},
                {"client_media_id": "a2", "kind": "image", "is_cover": "false", "sort_order": "1"},
            ]
        )
        assert out[0]["is_cover"] is True and out[0]["sort_order"] == 0
        assert "is_cover" not in out[1] and out[1]["sort_order"] == 1

    def test_two_covers_rejected(self):
        from kk.media_readiness import ExpectedMediaValidationError, validate_expected_media

        with pytest.raises(ExpectedMediaValidationError):
            validate_expected_media(
                [
                    {"client_media_id": "a1", "kind": "image", "is_cover": True},
                    {"client_media_id": "a2", "kind": "image", "is_cover": True},
                ]
            )

    def test_video_cover_rejected(self):
        from kk.media_readiness import ExpectedMediaValidationError, validate_expected_media

        with pytest.raises(ExpectedMediaValidationError):
            validate_expected_media(
                [{"client_media_id": "v1", "kind": "video", "is_cover": True}]
            )

    def test_garbled_sort_order_is_ignored_not_rejected(self):
        from kk.media_readiness import validate_expected_media

        out = validate_expected_media(
            [
                {"client_media_id": "a1", "kind": "image", "sort_order": "nope"},
                {"client_media_id": "a2", "kind": "image", "sort_order": -4},
                {"client_media_id": "a3", "kind": "image", "sort_order": 10**9},
            ]
        )
        assert all("sort_order" not in e for e in out)

    def test_legacy_manifest_unchanged(self):
        from kk.media_readiness import validate_expected_media

        out = validate_expected_media([{"client_media_id": "a1", "kind": "image"}])
        assert out == [{"client_media_id": "a1", "kind": "image"}]


# ---------------------------------------------------------------------------
# create_car persists the declaration atomically with the manifest
# ---------------------------------------------------------------------------


class TestCreatePersistsCover:
    def test_create_car_stores_cover_and_order_on_manifest_rows(
        self, client, app_ctx, seller
    ):
        car = _create(client, seller, app_ctx, _manifest(2))
        app, *_r = app_ctx
        CarMediaItem = app_ctx[8]
        with app.app_context():
            rows = {
                r.client_media_id: r
                for r in CarMediaItem.query.filter_by(car_id=car["db_id"]).all()
            }
        assert [rows[i].is_cover for i in _IDS] == [False, False, True, False, False]
        assert [rows[i].sort_order for i in _IDS] == [1, 2, 0, 3, 4]

    def test_two_covers_in_request_is_a_400(self, client, app_ctx, seller):
        bad = _manifest(1)
        bad[3]["is_cover"] = True
        r = client.post(
            "/api/cars",
            json=_base_car_payload(expected_media=bad),
            headers=_auth(seller),
        )
        assert r.status_code == 400, r.data

    def test_legacy_create_without_cover_still_201(self, client, app_ctx, seller):
        car = _create(client, seller, app_ctx, _manifest(None))
        CarMediaItem = app_ctx[8]
        app, *_r = app_ctx
        with app.app_context():
            rows = CarMediaItem.query.filter_by(car_id=car["db_id"]).all()
        assert rows and not any(r.is_cover for r in rows)
        assert all(r.sort_order is None for r in rows)


# ---------------------------------------------------------------------------
# Cover wins regardless of completion order
# ---------------------------------------------------------------------------


class TestCoverIndependentOfCompletionOrder:
    # Photo 3 of 5 (index 2) starred. Completion orders include the cover
    # finishing first, last, and in the middle, plus a fully reversed run.
    @pytest.mark.parametrize(
        "completion",
        [
            [0, 1, 2, 3, 4],
            [4, 3, 2, 1, 0],
            [2, 0, 1, 3, 4],
            [0, 1, 3, 4, 2],
            [3, 0, 4, 2, 1],
        ],
    )
    def test_photo_3_of_5_is_cover_for_any_completion_order(
        self, client, app_ctx, seller, completion
    ):
        car = _create(client, seller, app_ctx, _manifest(2))
        for idx in completion:
            _attach(app_ctx, car, _IDS[idx])

        got = _get(client, seller, car)
        # Cover is first, and is the card/hero image.
        assert got["images"][0]["client_media_id"] == _IDS[2]
        assert got["images"][0]["is_primary"] is True
        assert got["image_url"] == _url(_IDS[2])
        # Exactly one cover.
        assert sum(1 for i in got["images"] if i["is_primary"]) == 1
        # Remaining photos keep their grid order after the cover.
        assert _owner_cmid_order(got) == [
            _IDS[2],
            _IDS[0],
            _IDS[1],
            _IDS[3],
            _IDS[4],
        ]
        # No duplicates, none lost.
        assert len(got["images"]) == 5

    def test_restaring_before_submit_uses_only_the_latest_cover(
        self, client, app_ctx, seller
    ):
        """Client sends one manifest per submit; star photo 3 then photo 2 ->
        the manifest declares only photo 2, so photo 2 is the only cover."""
        car = _create(client, seller, app_ctx, _manifest(1))
        for idx in (2, 1, 0, 4, 3):
            _attach(app_ctx, car, _IDS[idx])
        got = _get(client, seller, car)
        assert got["images"][0]["client_media_id"] == _IDS[1]
        assert [i["client_media_id"] for i in got["images"] if i["is_primary"]] == [
            _IDS[1]
        ]

    def test_interim_state_has_no_wrong_primary(self, client, app_ctx, seller):
        """While the cover is still processing, an earlier-finishing non-cover
        photo must NOT be stamped primary (it used to be, permanently)."""
        car = _create(client, seller, app_ctx, _manifest(2))
        _attach(app_ctx, car, _IDS[0])
        _attach(app_ctx, car, _IDS[4])
        got = _get(client, seller, car)
        assert not any(i["is_primary"] for i in got["images"])
        _attach(app_ctx, car, _IDS[2])
        got = _get(client, seller, car)
        assert got["images"][0]["client_media_id"] == _IDS[2]
        assert got["images"][0]["is_primary"] is True

    def test_damage_photos_never_become_cover(self, client, app_ctx, seller):
        manifest = _manifest(0, ids=["img_d_1", "img_d_2", "img_dmg_1"])
        car = _create(client, seller, app_ctx, manifest)
        _attach(app_ctx, car, "img_dmg_1", kind="damage")
        _attach(app_ctx, car, "img_d_2")
        _attach(app_ctx, car, "img_d_1")
        got = _get(client, seller, car)
        by_id = {i["client_media_id"]: i for i in got["images"]}
        assert by_id["img_d_1"]["is_primary"] is True
        assert by_id["img_dmg_1"]["is_primary"] is False
        assert got["image_url"] == _url("img_d_1")


# ---------------------------------------------------------------------------
# Legacy compatibility
# ---------------------------------------------------------------------------


class TestLegacyBehaviorUnchanged:
    def test_no_cover_declared_first_attached_is_cover(self, client, app_ctx, seller):
        car = _create(client, seller, app_ctx, _manifest(None))
        for idx in (3, 0, 1, 2, 4):
            _attach(app_ctx, car, _IDS[idx])
        got = _get(client, seller, car)
        assert sum(1 for i in got["images"] if i["is_primary"]) == 1
        assert got["images"][0]["client_media_id"] == _IDS[3]
        assert got["image_url"] == _url(_IDS[3])
        assert len(got["images"]) == 5

    def test_pre_existing_rows_with_default_order_keep_id_order(
        self, client, app_ctx, seller
    ):
        """Rows from before this change: all order == 0, no manifest. The
        serializer must keep id order (stored primary first)."""
        from kk.models import Car, CarImage, db

        app, *_r = app_ctx
        uid = None
        with app.app_context():
            from kk.models import User

            uid = User.query.filter(User.username.like("mr_cover_%")).first().id
            car = Car(
                seller_id=uid,
                title="Legacy",
                brand="toyota",
                model="corolla",
                year=2020,
                mileage=1,
                engine_type="gas",
                transmission="auto",
                drive_type="fwd",
                condition="used",
                body_type="sedan",
                price=1.0,
                location="Erbil",
                is_active=True,
            )
            db.session.add(car)
            db.session.commit()
            for n in range(3):
                db.session.add(
                    CarImage(
                        car_id=car.id,
                        image_url=f"https://cdn.example.com/uploads/legacy{n}.jpg",
                        is_primary=(n == 0),
                        order=0,
                    )
                )
            db.session.commit()
            public_id = car.public_id
        r = client.get(f"/api/cars/{public_id}", headers=_auth(seller))
        urls = [i["image_url"] for i in r.get_json()["car"]["images"]]
        assert urls == [
            "https://cdn.example.com/uploads/legacy0.jpg",
            "https://cdn.example.com/uploads/legacy1.jpg",
            "https://cdn.example.com/uploads/legacy2.jpg",
        ]


# ---------------------------------------------------------------------------
# Failed cover -> safe fallback
# ---------------------------------------------------------------------------


class TestFailedCoverFallback:
    def test_permanently_failed_cover_falls_back_to_first_attached(
        self, client, app_ctx, seller
    ):
        from kk.media_readiness import transition_media_item_terminal

        car = _create(client, seller, app_ctx, _manifest(2))
        app = app_ctx[0]
        with app.app_context():
            transition_media_item_terminal(
                car_id=car["db_id"],
                client_media_id=_IDS[2],
                to_status="failed",
            )
        _attach(app_ctx, car, _IDS[4])
        _attach(app_ctx, car, _IDS[0])
        got = _get(client, seller, car)
        assert sum(1 for i in got["images"] if i["is_primary"]) == 1
        assert got["images"][0]["client_media_id"] == _IDS[4]
        assert got["image_url"] == _url(_IDS[4])


# ---------------------------------------------------------------------------
# Editing the cover afterwards + deleting the cover
# ---------------------------------------------------------------------------


class TestEditAndDeleteCover:
    def _published(self, client, app_ctx, seller, cover_index=2):
        car = _create(client, seller, app_ctx, _manifest(cover_index))
        for idx in (1, 3, 0, 2, 4):
            _attach(app_ctx, car, _IDS[idx])
        return car

    def test_layout_edit_changes_cover_and_persists(self, client, app_ctx, seller):
        car = self._published(client, app_ctx, seller)
        before = _get(client, seller, car)
        ids_by_cmid = {i["client_media_id"]: i["id"] for i in before["images"]}

        # Seller edits the listing and stars photo 5 (cover-first order).
        new_order = [_IDS[4], _IDS[2], _IDS[0], _IDS[1], _IDS[3]]
        r = client.put(
            f"/api/cars/{car['id']}/images/layout",
            json={
                "images": [
                    {"id": ids_by_cmid[c], "order": n, "is_primary": n == 0}
                    for n, c in enumerate(new_order)
                ]
            },
            headers=_auth(seller),
        )
        assert r.status_code == 200, r.data
        got = _get(client, seller, car)
        assert _owner_cmid_order(got) == new_order
        assert got["image_url"] == _url(_IDS[4])
        assert sum(1 for i in got["images"] if i["is_primary"]) == 1
        # Persisted: a fresh read (new request) still agrees.
        again = _get(client, seller, car)
        assert _owner_cmid_order(again) == new_order

    def test_set_primary_endpoint_changes_cover(self, client, app_ctx, seller):
        car = self._published(client, app_ctx, seller)
        r = client.put(
            f"/api/cars/{car['id']}/images/primary",
            json={"image_url": _url(_IDS[1])},
            headers=_auth(seller),
        )
        assert r.status_code == 200, r.data
        got = _get(client, seller, car)
        assert got["images"][0]["client_media_id"] == _IDS[1]
        assert got["image_url"] == _url(_IDS[1])
        assert sum(1 for i in got["images"] if i["is_primary"]) == 1

    def test_deleting_the_cover_promotes_a_fallback(self, client, app_ctx, seller):
        car = self._published(client, app_ctx, seller)
        got = _get(client, seller, car)
        cover = got["images"][0]
        assert cover["client_media_id"] == _IDS[2]
        r = client.delete(
            f"/api/cars/{car['id']}/images/{cover['id']}", headers=_auth(seller)
        )
        assert r.status_code == 200, r.data
        after = _get(client, seller, car)
        assert len(after["images"]) == 4
        assert sum(1 for i in after["images"] if i["is_primary"]) == 1
        assert after["images"][0]["is_primary"] is True
        assert after["image_url"] == after["images"][0]["image_url"]
        assert after["image_url"] != cover["image_url"]


# ---------------------------------------------------------------------------
# Exactly one primary -- across failures, retries, redelivery and edits
# ---------------------------------------------------------------------------


def _primaries(app_ctx, car) -> list[str]:
    """Primary listing images straight from the DB (not via serialization)."""
    app = app_ctx[0]
    CarImage = app_ctx[6]
    with app.app_context():
        return sorted(
            i.source_media_id
            for i in CarImage.query.filter_by(car_id=car["db_id"]).all()
            if i.is_primary and (i.kind or "listing") != "damage"
        )


def _fail(app_ctx, car, cmid: str) -> None:
    from kk.media_readiness import transition_media_item_terminal

    with app_ctx[0].app_context():
        transition_media_item_terminal(
            car_id=car["db_id"], client_media_id=cmid, to_status="failed"
        )


class TestExactlyOnePrimary:
    def test_cover_fails_after_siblings_attached_promotes_one(
        self, client, app_ctx, seller
    ):
        """The hole: siblings attach as non-primary while the cover is pending;
        when the cover then fails permanently nobody was primary."""
        car = _create(client, seller, app_ctx, _manifest(2))
        for idx in (1, 3, 0):
            _attach(app_ctx, car, _IDS[idx])
        assert _primaries(app_ctx, car) == []  # cover still pending
        _fail(app_ctx, car, _IDS[2])
        # first in display order (cover-first sort_order: 2,0,1,3,4) wins
        assert _primaries(app_ctx, car) == [_IDS[0]]
        _attach(app_ctx, car, _IDS[4])  # a late sibling must not add a 2nd
        assert _primaries(app_ctx, car) == [_IDS[0]]
        got = _get(client, seller, car)
        assert got["images"][0]["client_media_id"] == _IDS[0]
        assert got["image_url"] == _url(_IDS[0])

    def test_cover_rejected_in_phase_a_after_siblings_attached(
        self, client, app_ctx, seller
    ):
        from kk.media_readiness import remove_expected_media_item_locked

        car = _create(client, seller, app_ctx, _manifest(2))
        for idx in (4, 3):
            _attach(app_ctx, car, _IDS[idx])
        app, Car = app_ctx[0], app_ctx[5]
        with app.app_context():
            locked = Car.query.filter_by(id=car["db_id"]).with_for_update().one()
            res = remove_expected_media_item_locked(
                car=locked, client_media_id=_IDS[2]
            )
            app_ctx[3].session.commit()
        assert res["removed"] is True
        assert _primaries(app_ctx, car) == [_IDS[3]]
        _attach(app_ctx, car, _IDS[0])
        assert len(_primaries(app_ctx, car)) == 1

    def test_non_cover_failure_never_touches_the_cover(self, client, app_ctx, seller):
        car = _create(client, seller, app_ctx, _manifest(2))
        _attach(app_ctx, car, _IDS[2])
        _fail(app_ctx, car, _IDS[0])
        _attach(app_ctx, car, _IDS[4])
        assert _primaries(app_ctx, car) == [_IDS[2]]

    def test_redelivered_and_duplicate_attaches_are_noops(
        self, client, app_ctx, seller
    ):
        car = _create(client, seller, app_ctx, _manifest(2))
        for idx in (3, 2, 2, 3, 0, 2, 0):
            _attach(app_ctx, car, _IDS[idx])
        got = _get(client, seller, car)
        assert len(got["images"]) == 3
        assert _primaries(app_ctx, car) == [_IDS[2]]

    def test_transient_attach_failure_then_retry_keeps_one_primary(
        self, client, app_ctx, seller
    ):
        from kk.media_readiness import (
            mark_item_phase_a_accepted,
            transition_media_item_terminal,
        )
        from kk.routes.media import attach_processed_car_image

        car = _create(client, seller, app_ctx, _manifest(2))
        _attach(app_ctx, car, _IDS[0])

        def boom(car_obj):
            attach_processed_car_image(
                car_obj,
                kind="listing",
                rel_path=_url(_IDS[2]),
                source_media_id=_IDS[2],
            )
            raise RuntimeError("worker died after the insert, before commit")

        with app_ctx[0].app_context():
            mark_item_phase_a_accepted(
                car_id=car["db_id"], client_media_id=_IDS[2], job_task_id="t-x"
            )
            with pytest.raises(RuntimeError):
                transition_media_item_terminal(
                    car_id=car["db_id"],
                    client_media_id=_IDS[2],
                    to_status="attached",
                    attach_fn=boom,
                )
        # rolled back: no half-attached cover, no stray primary
        assert _primaries(app_ctx, car) == []
        _attach(app_ctx, car, _IDS[2])  # the Celery retry
        assert _primaries(app_ctx, car) == [_IDS[2]]
        assert len(_get(client, seller, car)["images"]) == 2

    def test_seller_edit_while_cover_processing_is_not_overridden(
        self, client, app_ctx, seller
    ):
        """Edit sets primary on photo 2 while the declared cover (photo 3) is
        still processing. The late cover must not become a SECOND primary."""
        car = _create(client, seller, app_ctx, _manifest(2))
        _attach(app_ctx, car, _IDS[1])
        _attach(app_ctx, car, _IDS[3])
        r = client.put(
            f"/api/cars/{car['id']}/images/primary",
            json={"image_url": _url(_IDS[1])},
            headers=_auth(seller),
        )
        assert r.status_code == 200, r.data
        assert _primaries(app_ctx, car) == [_IDS[1]]
        _attach(app_ctx, car, _IDS[2])  # the declared cover finally lands
        _attach(app_ctx, car, _IDS[0])
        assert _primaries(app_ctx, car) == [_IDS[1]]
        got = _get(client, seller, car)
        assert got["images"][0]["client_media_id"] == _IDS[1]
        assert sum(1 for i in got["images"] if i["is_primary"]) == 1

    def test_edit_after_publish_then_redelivery_keeps_one(
        self, client, app_ctx, seller
    ):
        car = _create(client, seller, app_ctx, _manifest(2))
        for idx in (0, 1, 2, 3, 4):
            _attach(app_ctx, car, _IDS[idx])
        client.put(
            f"/api/cars/{car['id']}/images/primary",
            json={"image_url": _url(_IDS[4])},
            headers=_auth(seller),
        )
        for idx in (2, 4, 0):  # redelivered worker tasks after the edit
            _attach(app_ctx, car, _IDS[idx])
        assert _primaries(app_ctx, car) == [_IDS[4]]

    def test_every_completion_order_and_failure_keeps_at_most_one(
        self, client, app_ctx, seller
    ):
        """Exhaustive: 4 photos, cover = #2, EVERY order of 4 completions where
        any single photo (cover or not) fails instead of attaching. At no
        intermediate step more than one primary; at the end exactly one."""
        from itertools import permutations

        ids = [f"img_x_{n}" for n in range(4)]
        for fail_idx in (None, 0, 1, 2, 3):
            for order in permutations(range(4)):
                car = _create(client, seller, app_ctx, _manifest(1, ids=ids))
                for idx in order:
                    if idx == fail_idx:
                        _fail(app_ctx, car, ids[idx])
                    else:
                        _attach(app_ctx, car, ids[idx])
                    assert len(_primaries(app_ctx, car)) <= 1, (fail_idx, order)
                assert len(_primaries(app_ctx, car)) == 1, (fail_idx, order)
                if fail_idx != 1:
                    assert _primaries(app_ctx, car) == [ids[1]], (fail_idx, order)
