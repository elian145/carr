"""BE-08 regression tests: ``sync_saved_searches()`` must not re-fetch a
user's SavedSearch rows from the database once per sync item.

Bug (PRODUCTION_AUDIT.md BE-08, PARTIALLY VALID per the follow-up
investigation): ``sync_saved_searches()`` (``kk/routes/saved_searches.py``)
already loads the user's existing ``SavedSearch`` rows once into an
in-memory ``existing`` dict, but for every sync item whose ``public_id``
doesn't match an existing row it used to call ``_find_by_filters()``, which
re-queried *all* of that user's ``SavedSearch`` rows from the database again
-- one extra full ``SELECT ... FROM saved_search WHERE user_id = ?`` per
item. On top of that, whenever an item didn't match anything, it ran another
``SELECT count(*) FROM saved_search WHERE user_id = ?`` to re-check the
``_MAX_SAVED_SEARCHES`` cap, instead of using the already-known in-memory
row count. Combined, a worst-case 50-item sync could issue on the order of
150+ SQL statements.

The (in-scope) fix reuses the ``existing`` rows already loaded at the top of
the function to build an in-memory filter-fingerprint lookup (using the
exact same ``_filters_fingerprint()`` semantics as ``_find_by_filters()``),
keeps that lookup updated as the loop progresses (so same-request
dedup/"first match wins" semantics are preserved), and replaces the
per-new-item ``COUNT(*)`` with a running ``current_count`` counter seeded
from ``len(existing)``. No behavior change: ownership, notify/auto_saved/
name handling, public_id handling, timestamps, ordering, response shape,
duplicate prevention, the 50-row cap, and commit behavior are all unchanged.
(Note: the single-item ``POST /api/saved-searches`` create endpoint's
``_find_by_filters()`` call is intentionally NOT touched -- it is already
bounded by the same 50-row cap and cheap by itself; this file only covers
the ``/api/saved-searches/sync`` batch path.)

Tests follow the existing project pattern: ``create_app()`` against a
temp-file SQLite DB (see ``kk/tests/test_saved_search_delete.py`` /
``test_be07_saved_search_filter_bounds.py``), and the project's existing
SQLAlchemy ``before_cursor_execute`` query-counting/inspection approach (see
``kk/tests/test_be02_n_plus_one.py`` / ``test_be17_blocked_users_batch_fetch.py``)
to prove specific SQL statement *patterns* -- not a fragile wall-clock
threshold -- are no longer issued once per sync item.
"""

from __future__ import annotations

import os
import sys
import tempfile
import uuid
from contextlib import contextmanager
from pathlib import Path

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

_PASSWORD = "Aa123456!"


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_be08_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ["DB_PATH"] = os.path.join(tmp.name, "be08.db")

    from kk.app_factory import create_app

    app, _socketio, *_ = create_app()
    from kk.models import SavedSearch, User, db

    with app.app_context():
        db.drop_all()
        db.create_all()

    yield app, app.test_client(), db, User, SavedSearch

    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    tmp.cleanup()


@pytest.fixture
def client(app_ctx):
    return app_ctx[1]


def _phone() -> str:
    return f"077{uuid.uuid4().int % 10**8:08d}"


def _make_user_and_login(app_ctx, client, *, username: str) -> tuple[str, int]:
    """Create an active, verified user and return (auth_token, user_id)."""
    app, _client, db, User, _SavedSearch = app_ctx

    with app.app_context():
        user = User(
            username=username,
            phone_number=_phone(),
            first_name="BE08",
            last_name="Test",
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id=f"pub-{uuid.uuid4().hex[:12]}",
        )
        user.set_password(_PASSWORD)
        db.session.add(user)
        db.session.commit()
        user_id = user.id

    login = client.post("/api/auth/login", json={"username": username, "password": _PASSWORD})
    assert login.status_code == 200, login.data
    token = login.get_json()["access_token"]
    return token, user_id


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _make_existing_row(app_ctx, *, user_id: int, filters: dict, name: str = "Existing", notify: bool = True):
    """Insert a SavedSearch row directly (bypassing the API) so tests fully
    control the pre-existing dataset. Returns the row's public_id."""
    app, _client, db, _User, SavedSearch = app_ctx
    with app.app_context():
        row = SavedSearch(user_id=user_id, name=name, filters=filters, notify=notify, auto_saved=False)
        db.session.add(row)
        db.session.commit()
        return row.public_id


def _count_rows(app_ctx, *, user_id: int) -> int:
    app, _client, db, _User, SavedSearch = app_ctx
    with app.app_context():
        return SavedSearch.query.filter_by(user_id=user_id).count()


def _all_rows(app_ctx, *, user_id: int):
    app, _client, db, _User, SavedSearch = app_ctx
    with app.app_context():
        return SavedSearch.query.filter_by(user_id=user_id).all()


# ---------------------------------------------------------------------------
# SQL statement capture (mirrors the before_cursor_execute pattern used by
# test_be02_n_plus_one.py / test_be17_blocked_users_batch_fetch.py, but keeps
# the raw statement text so we can classify statement *kinds*, not just a
# total count).
# ---------------------------------------------------------------------------


@contextmanager
def _capture_statements(app_ctx):
    from sqlalchemy import event

    app = app_ctx[0]
    db = app_ctx[2]
    statements: list[str] = []

    def _on_execute(_conn, _cursor, statement, _parameters, _context, _executemany):
        statements.append(statement)

    with app.app_context():
        engine = db.engine
    event.listen(engine, "before_cursor_execute", _on_execute)
    try:
        yield statements
    finally:
        event.remove(engine, "before_cursor_execute", _on_execute)


def _is_full_unbounded_saved_search_select(stmt: str) -> bool:
    """A `SELECT ... FROM saved_search WHERE user_id = ?` with no LIMIT and
    no COUNT(*) -- i.e. the "load all of this user's rows" query that used
    to be re-issued by `_find_by_filters()` on every sync item without a
    matching public_id."""
    s = stmt.strip().lower()
    return (
        s.startswith("select")
        and "saved_search" in s
        and "limit" not in s
        and "count(" not in s
    )


def _is_saved_search_count(stmt: str) -> bool:
    s = stmt.strip().lower()
    return "count(" in s and "saved_search" in s


def _sync(client, token, items):
    return client.post("/api/saved-searches/sync", json={"items": items}, headers=_auth(token))


# ---------------------------------------------------------------------------
# A. Query amplification regression
# ---------------------------------------------------------------------------


class TestQueryAmplificationRegression:
    def test_sync_with_no_matching_public_ids_does_not_reselect_per_item(self, app_ctx, client):
        token, user_id = _make_user_and_login(
            app_ctx, client, username=f"be08_a_{uuid.uuid4().hex[:8]}"
        )
        # A handful of realistic pre-existing saved searches.
        for i in range(4):
            _make_existing_row(
                app_ctx, user_id=user_id, filters={"brand": f"brand{i}", "city": "erbil"}, name=f"Existing {i}"
            )

        # Sync items whose public_ids match nothing and whose filters are
        # all brand-new (so none of them short-circuit via public_id AND
        # none of them match an existing row's fingerprint either).
        items = [
            {
                "id": f"stale-{uuid.uuid4().hex[:10]}",
                "name": f"New {i}",
                "filters": {"brand": "unique-brand", "model": f"model-{i}"},
            }
            for i in range(12)
        ]

        with _capture_statements(app_ctx) as statements:
            resp = _sync(client, token, items)
        assert resp.status_code == 200, resp.data

        full_selects = [s for s in statements if _is_full_unbounded_saved_search_select(s)]
        counts = [s for s in statements if _is_saved_search_count(s)]

        # Exactly one unbounded full-row SELECT (the initial `existing` load)
        # -- NOT one per sync item (old behavior would have produced 12 more).
        assert len(full_selects) == 1, (
            f"expected exactly 1 full saved_search SELECT (the initial load), "
            f"got {len(full_selects)}:\n" + "\n---\n".join(full_selects)
        )
        # No COUNT(*) queries at all for this batch of new items.
        assert len(counts) == 0, f"expected no saved_search COUNT(*) queries, got {len(counts)}:\n" + "\n---\n".join(
            counts
        )


# ---------------------------------------------------------------------------
# B. No redundant COUNT(*) loop
# ---------------------------------------------------------------------------


class TestNoRedundantCountLoop:
    def test_sync_creating_several_new_items_issues_zero_count_queries(self, app_ctx, client):
        token, user_id = _make_user_and_login(
            app_ctx, client, username=f"be08_b_{uuid.uuid4().hex[:8]}"
        )
        items = [
            {"name": f"Item {i}", "filters": {"brand": "toyota", "model": f"m{i}"}}
            for i in range(8)
        ]

        with _capture_statements(app_ctx) as statements:
            resp = _sync(client, token, items)
        assert resp.status_code == 200, resp.data

        counts = [s for s in statements if _is_saved_search_count(s)]
        assert counts == [], f"expected zero COUNT(*) queries against saved_search, got: {counts}"
        assert _count_rows(app_ctx, user_id=user_id) == 8


# ---------------------------------------------------------------------------
# C. Deduplication correctness
# ---------------------------------------------------------------------------


class TestDeduplicationCorrectness:
    def test_sync_item_matching_existing_filters_reuses_row(self, app_ctx, client):
        token, user_id = _make_user_and_login(
            app_ctx, client, username=f"be08_c_{uuid.uuid4().hex[:8]}"
        )
        filters = {"brand": "toyota", "city": "erbil"}
        existing_public_id = _make_existing_row(
            app_ctx, user_id=user_id, filters=filters, name="Old name", notify=False
        )

        resp = _sync(
            client,
            token,
            [{"name": "Renamed", "filters": dict(filters), "notify": True}],
        )
        assert resp.status_code == 200, resp.data
        saved = resp.get_json()["saved_searches"]
        assert len(saved) == 1
        assert saved[0]["id"] == existing_public_id
        assert saved[0]["name"] == "Renamed"
        assert saved[0]["notify"] is True

        assert _count_rows(app_ctx, user_id=user_id) == 1


# ---------------------------------------------------------------------------
# D. Same-request deduplication
# ---------------------------------------------------------------------------


class TestSameRequestDeduplication:
    def test_two_new_items_with_identical_filters_dedupe_to_one_row(self, app_ctx, client):
        token, user_id = _make_user_and_login(
            app_ctx, client, username=f"be08_d_{uuid.uuid4().hex[:8]}"
        )
        filters = {"brand": "kia", "model": "sportage"}

        items = [
            {"name": "First", "filters": dict(filters)},
            {"name": "Second", "filters": dict(filters)},
        ]

        with _capture_statements(app_ctx) as statements:
            resp = _sync(client, token, items)
        assert resp.status_code == 200, resp.data
        saved = resp.get_json()["saved_searches"]

        # Same-request dedup: item B must match item A's just-created row
        # (same underlying SavedSearch instance) instead of creating a
        # second row. Since both items mutate the SAME row object in
        # sequence, the row ends up reflecting the LAST item processed
        # ("Second") -- exactly what the pre-existing DB-re-query behavior
        # would also have produced (autoflush would have made item A's
        # pending insert visible to item B's `_find_by_filters()` query).
        assert len(saved) == 1, f"expected same-request dedup to a single row, got {len(saved)}"
        assert saved[0]["name"] == "Second"
        assert _count_rows(app_ctx, user_id=user_id) == 1

        # Still just the one initial full SELECT, no per-item re-query.
        full_selects = [s for s in statements if _is_full_unbounded_saved_search_select(s)]
        assert len(full_selects) == 1


# ---------------------------------------------------------------------------
# E. Stale public_id fallback
# ---------------------------------------------------------------------------


class TestStalePublicIdFallback:
    def test_stale_public_id_with_matching_filters_reuses_existing_row(self, app_ctx, client):
        token, user_id = _make_user_and_login(
            app_ctx, client, username=f"be08_e_{uuid.uuid4().hex[:8]}"
        )
        filters = {"brand": "hyundai", "city": "duhok"}
        existing_public_id = _make_existing_row(app_ctx, user_id=user_id, filters=filters, name="Original")

        resp = _sync(
            client,
            token,
            [
                {
                    "id": "this-public-id-does-not-exist",
                    "name": "Updated via stale id",
                    "filters": dict(filters),
                }
            ],
        )
        assert resp.status_code == 200, resp.data
        saved = resp.get_json()["saved_searches"]
        assert len(saved) == 1
        # The real (existing) public_id is preserved -- the stale
        # client-supplied id is never adopted for a matched row.
        assert saved[0]["id"] == existing_public_id
        assert saved[0]["name"] == "Updated via stale id"
        assert _count_rows(app_ctx, user_id=user_id) == 1


# ---------------------------------------------------------------------------
# F. True new items
# ---------------------------------------------------------------------------


class TestTrueNewItems:
    def test_unique_new_filter_combinations_create_rows(self, app_ctx, client):
        token, user_id = _make_user_and_login(
            app_ctx, client, username=f"be08_f_{uuid.uuid4().hex[:8]}"
        )
        items = [
            {"name": "A", "filters": {"brand": "mazda", "model": "cx5"}},
            {"name": "B", "filters": {"brand": "honda", "model": "civic"}},
            {"name": "C", "filters": {"brand": "ford", "model": "focus"}},
        ]
        resp = _sync(client, token, items)
        assert resp.status_code == 200, resp.data
        saved = resp.get_json()["saved_searches"]
        assert len(saved) == 3
        assert {s["name"] for s in saved} == {"A", "B", "C"}
        assert _count_rows(app_ctx, user_id=user_id) == 3


# ---------------------------------------------------------------------------
# G. 50-row cap
# ---------------------------------------------------------------------------


class TestFiftyRowCap:
    def test_cap_is_still_enforced_exactly(self, app_ctx, client):
        from kk.routes.saved_searches import _MAX_SAVED_SEARCHES

        token, user_id = _make_user_and_login(
            app_ctx, client, username=f"be08_g_{uuid.uuid4().hex[:8]}"
        )

        # Pre-fill 45 existing rows directly.
        preexisting = 45
        for i in range(preexisting):
            _make_existing_row(
                app_ctx, user_id=user_id, filters={"brand": "cap-test", "model": f"pre-{i}"}, name=f"pre-{i}"
            )
        assert _count_rows(app_ctx, user_id=user_id) == preexisting

        # Try to sync 10 more brand-new unique items -- only
        # (_MAX_SAVED_SEARCHES - preexisting) = 5 should be accepted.
        items = [
            {"name": f"new-{i}", "filters": {"brand": "cap-test", "model": f"new-{i}"}}
            for i in range(10)
        ]
        resp = _sync(client, token, items)
        assert resp.status_code == 200, resp.data

        final_count = _count_rows(app_ctx, user_id=user_id)
        assert final_count == _MAX_SAVED_SEARCHES, (
            f"expected cap of {_MAX_SAVED_SEARCHES}, got {final_count}"
        )

        saved = resp.get_json()["saved_searches"]
        assert len(saved) == _MAX_SAVED_SEARCHES


# ---------------------------------------------------------------------------
# H. Response compatibility
# ---------------------------------------------------------------------------


class TestResponseCompatibility:
    def test_response_envelope_and_contents_unchanged(self, app_ctx, client):
        token, user_id = _make_user_and_login(
            app_ctx, client, username=f"be08_h_{uuid.uuid4().hex[:8]}"
        )
        resp = _sync(
            client,
            token,
            [{"name": "Envelope check", "filters": {"brand": "nissan"}, "notify": False, "auto_saved": True}],
        )
        assert resp.status_code == 200, resp.data
        body = resp.get_json()
        assert set(body.keys()) == {"saved_searches"}
        assert isinstance(body["saved_searches"], list)
        entry = body["saved_searches"][0]
        assert set(entry.keys()) == {
            "id",
            "name",
            "filters",
            "notify",
            "auto_saved",
            "created_at",
            "updated_at",
        }
        assert entry["name"] == "Envelope check"
        assert entry["filters"] == {"brand": "nissan"}
        assert entry["notify"] is False
        assert entry["auto_saved"] is True


# ---------------------------------------------------------------------------
# I. Normal existing-public_id sync (fast path unaffected)
# ---------------------------------------------------------------------------


class TestExistingPublicIdFastPath:
    def test_matching_public_id_updates_in_place_without_fingerprint_lookup(self, app_ctx, client):
        token, user_id = _make_user_and_login(
            app_ctx, client, username=f"be08_i_{uuid.uuid4().hex[:8]}"
        )
        created = client.post(
            "/api/saved-searches",
            json={"name": "Original", "filters": {"brand": "bmw"}, "notify": True},
            headers=_auth(token),
        )
        assert created.status_code == 201, created.data
        public_id = created.get_json()["saved_search"]["id"]

        with _capture_statements(app_ctx) as statements:
            resp = _sync(
                client,
                token,
                [
                    {
                        "id": public_id,
                        "name": "Updated via id",
                        "filters": {"brand": "bmw", "model": "x5"},
                        "notify": False,
                    }
                ],
            )
        assert resp.status_code == 200, resp.data
        saved = resp.get_json()["saved_searches"]
        assert len(saved) == 1
        assert saved[0]["id"] == public_id
        assert saved[0]["name"] == "Updated via id"
        assert saved[0]["filters"] == {"brand": "bmw", "model": "x5"}
        assert saved[0]["notify"] is False
        assert _count_rows(app_ctx, user_id=user_id) == 1

        full_selects = [s for s in statements if _is_full_unbounded_saved_search_select(s)]
        counts = [s for s in statements if _is_saved_search_count(s)]
        assert len(full_selects) == 1
        assert len(counts) == 0


# ---------------------------------------------------------------------------
# J. Query-count scaling: small batch vs large batch
# ---------------------------------------------------------------------------


class TestQueryCountScaling:
    def test_full_select_and_count_patterns_do_not_scale_with_batch_size(self, app_ctx, client):
        small_token, small_user_id = _make_user_and_login(
            app_ctx, client, username=f"be08_j_small_{uuid.uuid4().hex[:8]}"
        )
        large_token, large_user_id = _make_user_and_login(
            app_ctx, client, username=f"be08_j_large_{uuid.uuid4().hex[:8]}"
        )

        small_items = [
            {"name": f"s{i}", "filters": {"brand": "scaling-test", "model": f"small-{i}"}}
            for i in range(3)
        ]
        large_items = [
            {"name": f"l{i}", "filters": {"brand": "scaling-test", "model": f"large-{i}"}}
            for i in range(30)
        ]

        with _capture_statements(app_ctx) as small_statements:
            r_small = _sync(client, small_token, small_items)
        assert r_small.status_code == 200, r_small.data
        assert len(r_small.get_json()["saved_searches"]) == 3

        with _capture_statements(app_ctx) as large_statements:
            r_large = _sync(client, large_token, large_items)
        assert r_large.status_code == 200, r_large.data
        assert len(r_large.get_json()["saved_searches"]) == 30

        small_full_selects = [s for s in small_statements if _is_full_unbounded_saved_search_select(s)]
        large_full_selects = [s for s in large_statements if _is_full_unbounded_saved_search_select(s)]
        small_counts = [s for s in small_statements if _is_saved_search_count(s)]
        large_counts = [s for s in large_statements if _is_saved_search_count(s)]

        # The old redundant per-item full-row SELECT and per-new-item
        # COUNT(*) patterns must be gone in both batch sizes -- in
        # particular, the larger batch must NOT have proportionally more of
        # either than the small batch (it would previously have had ~27
        # more full SELECTs and ~27 more COUNT(*) queries).
        assert len(small_full_selects) == 1
        assert len(large_full_selects) == 1
        assert len(small_counts) == 0
        assert len(large_counts) == 0

        # We intentionally do NOT assert the *total* statement count is
        # equal between batches -- legitimate per-row INSERTs during commit
        # naturally scale with the number of genuinely new rows.
