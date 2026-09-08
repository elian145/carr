"""BE-17 regression tests: ``GET /api/users/blocked`` (``list_blocked_users``)
must resolve blocked-user ``public_id``s via a single batched query instead
of one ``User`` lookup per ``BlockedUser`` row (N+1).

Bug (PRODUCTION_AUDIT.md BE-17): the original implementation was::

    blocks = BlockedUser.query.filter_by(blocker_id=me.id).all()
    blocked_ids = []
    for b in blocks:
        u = db.session.get(User, b.blocked_id)   # <-- one query per row
        if u:
            blocked_ids.append(u.public_id)

For N blocked users this issued ``1 + N`` queries. The fix batches the
``User`` lookup with a single ``User.query.filter(User.id.in_(...))`` call
(mirroring the ``users_by_id`` pattern already used in ``list_chats()`` in
the same file), while preserving:

  - the exact response shape (``{"blocked_users": [public_id, ...]}``),
  - the original ordering (the order of the underlying ``BlockedUser`` rows,
    not dict/set iteration order),
  - silently skipping a ``blocked_id`` whose ``User`` row no longer exists,
  - an empty result (``[]``) — with no ``IN ()`` query ever issued — when
    there are no blocks.

These tests verify the above behavior and include a lightweight SQLAlchemy
query-count assertion (via the ``before_cursor_execute`` engine event, no
new test dependency) proving the endpoint issues a constant, small number of
queries regardless of how many users are blocked.
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


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(
        prefix="carlist_be17_", ignore_cleanup_errors=True
    )
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "be17.db")

    from kk.app_factory import create_app

    app, _socketio, *_ = create_app()
    from kk.models import BlockedUser, User, db

    with app.app_context():
        db.drop_all()
        db.create_all()

    yield app, app.test_client(), db, User, BlockedUser

    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    tmp.cleanup()


def _unique_phone() -> str:
    return f"077{uuid.uuid4().int % 10**8:08d}"


def _make_user(app_ctx, *, username: str) -> str:
    """Create an active, verified user and return their public_id."""
    app, _client, db, User, _BlockedUser = app_ctx
    with app.app_context():
        user = User(
            username=username,
            phone_number=_unique_phone(),
            first_name=username.title(),
            last_name="Test",
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id=f"pub-{uuid.uuid4().hex[:12]}",
        )
        user.set_password("Aa123456!")
        db.session.add(user)
        db.session.commit()
        return user.public_id


def _login(client, username: str, password: str = "Aa123456!") -> str:
    r = client.post(
        "/api/auth/login", json={"username": username, "password": password}
    )
    assert r.status_code == 200, r.data
    return r.get_json()["access_token"]


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _block(app_ctx, *, blocker_public: str, blocked_public: str) -> None:
    app, _client, db, User, BlockedUser = app_ctx
    with app.app_context():
        blocker = User.query.filter_by(public_id=blocker_public).first()
        blocked = User.query.filter_by(public_id=blocked_public).first()
        db.session.add(
            BlockedUser(blocker_id=blocker.id, blocked_id=blocked.id)
        )
        db.session.commit()


def _delete_user(app_ctx, *, public_id: str) -> None:
    """Hard-delete a user row directly, bypassing FK cascade handling in the
    real account-deletion flow, purely to simulate a dangling blocked_id for
    this test (the BlockedUser row's blocked_id then points at a row that no
    longer exists, which is exactly the case list_blocked_users() must keep
    tolerating)."""
    app, _client, db, User, _BlockedUser = app_ctx
    with app.app_context():
        u = User.query.filter_by(public_id=public_id).first()
        db.session.delete(u)
        db.session.commit()


@contextmanager
def _count_queries(app_ctx):
    """Count SQL statements executed against the app's engine while the
    context is active. Uses the standard SQLAlchemy ``before_cursor_execute``
    engine event -- no extra test dependency needed."""
    from sqlalchemy import event

    app, _client, db, _User, _BlockedUser = app_ctx
    counter = {"n": 0}

    def _on_execute(*_args, **_kwargs):
        counter["n"] += 1

    with app.app_context():
        engine = db.engine
    event.listen(engine, "before_cursor_execute", _on_execute)
    try:
        yield counter
    finally:
        event.remove(engine, "before_cursor_execute", _on_execute)


def test_get_blocked_users_unauthorized_without_token(app_ctx):
    _app, client, *_ = app_ctx
    r = client.get("/api/users/blocked")
    assert r.status_code == 401


def test_get_blocked_users_empty_list_when_no_blocks(app_ctx):
    app, client, *_ = app_ctx
    username = f"be17_lonely_{uuid.uuid4().hex[:8]}"
    _make_user(app_ctx, username=username)
    token = _login(client, username)

    r = client.get("/api/users/blocked", headers=_auth(token))
    assert r.status_code == 200, r.data
    assert r.get_json() == {"blocked_users": []}


def test_get_blocked_users_returns_all_expected_public_ids_in_order(app_ctx):
    app, client, *_ = app_ctx
    blocker_username = f"be17_blocker_{uuid.uuid4().hex[:8]}"
    blocker_public = _make_user(app_ctx, username=blocker_username)

    blocked_publics = [
        _make_user(app_ctx, username=f"be17_target_{i}_{uuid.uuid4().hex[:6]}")
        for i in range(5)
    ]
    for target_public in blocked_publics:
        _block(app_ctx, blocker_public=blocker_public, blocked_public=target_public)

    token = _login(client, blocker_username)
    r = client.get("/api/users/blocked", headers=_auth(token))
    assert r.status_code == 200, r.data
    body = r.get_json()

    # All expected public_ids are present.
    assert set(body["blocked_users"]) == set(blocked_publics)
    # Order matches the order the BlockedUser rows were created in (i.e. the
    # order BlockedUser.query.filter_by(...).all() returns them, not a
    # dict/set-scrambled order from the batch fetch).
    assert body["blocked_users"] == blocked_publics


def test_get_blocked_users_skips_deleted_user_but_keeps_others_in_order(app_ctx):
    app, client, *_ = app_ctx
    blocker_username = f"be17_blocker2_{uuid.uuid4().hex[:8]}"
    blocker_public = _make_user(app_ctx, username=blocker_username)

    first_public = _make_user(app_ctx, username=f"be17_first_{uuid.uuid4().hex[:6]}")
    doomed_public = _make_user(app_ctx, username=f"be17_doomed_{uuid.uuid4().hex[:6]}")
    last_public = _make_user(app_ctx, username=f"be17_last_{uuid.uuid4().hex[:6]}")

    _block(app_ctx, blocker_public=blocker_public, blocked_public=first_public)
    _block(app_ctx, blocker_public=blocker_public, blocked_public=doomed_public)
    _block(app_ctx, blocker_public=blocker_public, blocked_public=last_public)

    # Simulate a dangling blocked_id: the User row is gone but the
    # BlockedUser row (per BE-17's stated scope) is left pointing at it.
    _delete_user(app_ctx, public_id=doomed_public)

    token = _login(client, blocker_username)
    r = client.get("/api/users/blocked", headers=_auth(token))
    assert r.status_code == 200, r.data
    body = r.get_json()

    assert doomed_public not in body["blocked_users"]
    assert body["blocked_users"] == [first_public, last_public]


def test_get_blocked_users_query_count_is_constant_not_linear_in_block_count(
    app_ctx,
):
    """Regression guard for the N+1: querying with many blocked users must
    not issue one extra SQL statement per block. Fails under the old
    per-row ``db.session.get(User, ...)`` implementation, whose statement
    count grows linearly with the number of blocks."""
    app, client, *_ = app_ctx
    blocker_username = f"be17_counter_{uuid.uuid4().hex[:8]}"
    blocker_public = _make_user(app_ctx, username=blocker_username)

    few_targets = [
        _make_user(app_ctx, username=f"be17_few_{i}_{uuid.uuid4().hex[:6]}")
        for i in range(2)
    ]
    many_targets = [
        _make_user(app_ctx, username=f"be17_many_{i}_{uuid.uuid4().hex[:6]}")
        for i in range(10)
    ]

    blocker_few_username = f"be17_counter_few_{uuid.uuid4().hex[:8]}"
    blocker_few_public = _make_user(app_ctx, username=blocker_few_username)
    for target_public in few_targets:
        _block(app_ctx, blocker_public=blocker_few_public, blocked_public=target_public)
    for target_public in many_targets:
        _block(app_ctx, blocker_public=blocker_public, blocked_public=target_public)

    few_token = _login(client, blocker_few_username)
    many_token = _login(client, blocker_username)

    with _count_queries(app_ctx) as counter:
        r_few = client.get("/api/users/blocked", headers=_auth(few_token))
    assert r_few.status_code == 200, r_few.data
    few_query_count = counter["n"]

    with _count_queries(app_ctx) as counter:
        r_many = client.get("/api/users/blocked", headers=_auth(many_token))
    assert r_many.status_code == 200, r_many.data
    many_query_count = counter["n"]

    assert len(r_few.get_json()["blocked_users"]) == 2
    assert len(r_many.get_json()["blocked_users"]) == 10

    # The old N+1 implementation would issue 10 extra queries (one per
    # blocked user) for the "many" case vs. the "few" case (2 blocks). The
    # batched implementation issues the same, constant number of queries
    # regardless of how many users are blocked.
    assert many_query_count == few_query_count, (
        f"expected a constant query count independent of block count, "
        f"got {few_query_count} queries for 2 blocks vs {many_query_count} "
        f"queries for 10 blocks"
    )
