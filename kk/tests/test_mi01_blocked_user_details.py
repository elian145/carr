"""MI-01 regression tests: ``GET /api/users/blocked`` must additively expose
``blocked_user_details`` (id/name/profile_picture) alongside the pre-existing,
unchanged ``blocked_users`` list of public ids, using the same single batched
``User`` lookup BE-17 already established (no extra per-user queries).

Covers:

  - ``blocked_users`` (list[str] of public_ids) is byte-for-byte unchanged
    from the pre-MI-01 contract.
  - ``blocked_user_details`` contains exactly ``{id, name, profile_picture}``
    per entry, with ``id`` matching the corresponding ``blocked_users`` entry
    and ``name`` built from ``first_name``/``last_name``.
  - ``profile_picture`` is ``null`` when the user has none set.
  - A blocked account that no longer exists (deleted user) is silently
    skipped from *both* lists, exactly like the pre-existing behavior.
  - The batched-query property (BE-17) is preserved: issuing the request for
    many blocked users does not issue more SQL statements than for few.
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
        prefix="carlist_mi01_", ignore_cleanup_errors=True
    )
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "mi01.db")

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


def _make_user(
    app_ctx,
    *,
    username: str,
    first_name: str | None = None,
    last_name: str = "Test",
    profile_picture: str | None = None,
) -> str:
    """Create an active, verified user and return their public_id."""
    app, _client, db, User, _BlockedUser = app_ctx
    with app.app_context():
        user = User(
            username=username,
            phone_number=_unique_phone(),
            first_name=first_name or username.title(),
            last_name=last_name,
            profile_picture=profile_picture,
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
        db.session.add(BlockedUser(blocker_id=blocker.id, blocked_id=blocked.id))
        db.session.commit()


def _delete_user(app_ctx, *, public_id: str) -> None:
    """Hard-delete a user row directly, bypassing FK cascade handling in the
    real account-deletion flow, purely to simulate a dangling blocked_id."""
    app, _client, db, User, _BlockedUser = app_ctx
    with app.app_context():
        u = User.query.filter_by(public_id=public_id).first()
        db.session.delete(u)
        db.session.commit()


@contextmanager
def _count_queries(app_ctx):
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


def test_blocked_users_field_unchanged_and_details_added(app_ctx):
    app, client, *_ = app_ctx
    blocker_username = f"mi01_blocker_{uuid.uuid4().hex[:8]}"
    blocker_public = _make_user(app_ctx, username=blocker_username)

    target_public = _make_user(
        app_ctx,
        username=f"mi01_target_{uuid.uuid4().hex[:6]}",
        first_name="Jane",
        last_name="Doe",
        profile_picture="uploads/avatars/jane.jpg",
    )
    _block(app_ctx, blocker_public=blocker_public, blocked_public=target_public)

    token = _login(client, blocker_username)
    r = client.get("/api/users/blocked", headers=_auth(token))
    assert r.status_code == 200, r.data
    body = r.get_json()

    # Pre-existing contract: unchanged.
    assert body["blocked_users"] == [target_public]

    # Additive MI-01 field.
    assert "blocked_user_details" in body
    details = body["blocked_user_details"]
    assert len(details) == 1
    assert set(details[0].keys()) == {"id", "name", "profile_picture"}
    assert details[0]["id"] == target_public
    assert details[0]["name"] == "Jane Doe"
    assert details[0]["profile_picture"] == "uploads/avatars/jane.jpg"


def test_blocked_user_details_profile_picture_is_null_when_absent(app_ctx):
    app, client, *_ = app_ctx
    blocker_username = f"mi01_blocker2_{uuid.uuid4().hex[:8]}"
    blocker_public = _make_user(app_ctx, username=blocker_username)

    target_public = _make_user(
        app_ctx,
        username=f"mi01_nopic_{uuid.uuid4().hex[:6]}",
        first_name="No",
        last_name="Pic",
        profile_picture=None,
    )
    _block(app_ctx, blocker_public=blocker_public, blocked_public=target_public)

    token = _login(client, blocker_username)
    r = client.get("/api/users/blocked", headers=_auth(token))
    assert r.status_code == 200, r.data
    body = r.get_json()

    assert body["blocked_user_details"][0]["profile_picture"] is None


def test_blocked_user_details_skips_deleted_user_but_keeps_others(app_ctx):
    app, client, *_ = app_ctx
    blocker_username = f"mi01_blocker3_{uuid.uuid4().hex[:8]}"
    blocker_public = _make_user(app_ctx, username=blocker_username)

    first_public = _make_user(
        app_ctx, username=f"mi01_first_{uuid.uuid4().hex[:6]}", first_name="First"
    )
    doomed_public = _make_user(
        app_ctx, username=f"mi01_doomed_{uuid.uuid4().hex[:6]}", first_name="Doomed"
    )
    last_public = _make_user(
        app_ctx, username=f"mi01_last_{uuid.uuid4().hex[:6]}", first_name="Last"
    )

    _block(app_ctx, blocker_public=blocker_public, blocked_public=first_public)
    _block(app_ctx, blocker_public=blocker_public, blocked_public=doomed_public)
    _block(app_ctx, blocker_public=blocker_public, blocked_public=last_public)

    _delete_user(app_ctx, public_id=doomed_public)

    token = _login(client, blocker_username)
    r = client.get("/api/users/blocked", headers=_auth(token))
    assert r.status_code == 200, r.data
    body = r.get_json()

    # Skipped from both lists, others preserved in order.
    assert body["blocked_users"] == [first_public, last_public]
    detail_ids = [d["id"] for d in body["blocked_user_details"]]
    assert detail_ids == [first_public, last_public]


def test_blocked_user_details_query_count_is_constant_not_linear(app_ctx):
    """Regression guard: adding blocked_user_details must not reintroduce an
    N+1 (e.g. by fetching profile_picture with a separate per-user query)."""
    app, client, *_ = app_ctx
    blocker_few_username = f"mi01_counter_few_{uuid.uuid4().hex[:8]}"
    blocker_few_public = _make_user(app_ctx, username=blocker_few_username)
    blocker_many_username = f"mi01_counter_many_{uuid.uuid4().hex[:8]}"
    blocker_many_public = _make_user(app_ctx, username=blocker_many_username)

    few_targets = [
        _make_user(app_ctx, username=f"mi01_few_{i}_{uuid.uuid4().hex[:6]}")
        for i in range(2)
    ]
    many_targets = [
        _make_user(app_ctx, username=f"mi01_many_{i}_{uuid.uuid4().hex[:6]}")
        for i in range(10)
    ]
    for target_public in few_targets:
        _block(
            app_ctx, blocker_public=blocker_few_public, blocked_public=target_public
        )
    for target_public in many_targets:
        _block(
            app_ctx, blocker_public=blocker_many_public, blocked_public=target_public
        )

    few_token = _login(client, blocker_few_username)
    many_token = _login(client, blocker_many_username)

    with _count_queries(app_ctx) as counter:
        r_few = client.get("/api/users/blocked", headers=_auth(few_token))
    assert r_few.status_code == 200, r_few.data
    few_query_count = counter["n"]

    with _count_queries(app_ctx) as counter:
        r_many = client.get("/api/users/blocked", headers=_auth(many_token))
    assert r_many.status_code == 200, r_many.data
    many_query_count = counter["n"]

    assert len(r_few.get_json()["blocked_user_details"]) == 2
    assert len(r_many.get_json()["blocked_user_details"]) == 10

    assert many_query_count == few_query_count, (
        f"expected a constant query count independent of block count, "
        f"got {few_query_count} queries for 2 blocks vs {many_query_count} "
        f"queries for 10 blocks"
    )
