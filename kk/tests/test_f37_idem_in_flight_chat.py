"""F-37: a keyed write that is re-sent while the original is still executing.

``replay_response`` only replays a request that already COMPLETED. The client
re-sends a timed-out write (carrying the same ``Idempotency-Key``) after
~20 seconds, which on a Render cold start is usually while the first request is
still running. Before this change both copies executed and the buyer's message
was inserted twice. ``kk/idempotency.py::begin_request`` now takes an atomic
in-flight claim, so the overlapping duplicate is refused with a retryable 503
and a later retry replays the stored response of the original.
"""

from __future__ import annotations

import threading
import uuid

import pytest

# Re-use the app/user/listing fixtures and helpers of the BE-18 suite (same app
# factory, isolated sqlite DB, R2 mocked).
from kk.tests.test_be18_chat_send_idempotency import (  # noqa: F401
    _auth,
    _login,
    _make_car,
    _message_count,
    _mock_r2_chat_ops,
    _send_text,
    app_ctx,
    buyer_ctx,
    client,
    seller_ctx,
)


# --------------------------------------------------------------------------
# claim primitives (no Flask needed)
# --------------------------------------------------------------------------
def test_claim_is_exclusive_until_released():
    from kk.idempotency import claim_in_flight, release_in_flight

    k = dict(scope="s", actor_id="a", idem_key=f"k-{uuid.uuid4().hex}")
    assert claim_in_flight(**k) is True
    assert claim_in_flight(**k) is False  # duplicate while in flight
    release_in_flight(**k)
    assert claim_in_flight(**k) is True  # free again after release
    release_in_flight(**k)


def test_claim_is_scoped_by_scope_actor_and_key_and_blank_key_never_blocks():
    from kk.idempotency import claim_in_flight, release_in_flight

    key = f"k-{uuid.uuid4().hex}"
    assert claim_in_flight(scope="s1", actor_id="a", idem_key=key)
    assert claim_in_flight(scope="s2", actor_id="a", idem_key=key)  # other scope
    assert claim_in_flight(scope="s1", actor_id="b", idem_key=key)  # other actor
    assert claim_in_flight(scope="s1", actor_id="a", idem_key=key + "x")  # other key
    for _ in range(3):  # no key -> nothing to claim, never blocks
        assert claim_in_flight(scope="s1", actor_id="a", idem_key="")
        assert claim_in_flight(scope="s1", actor_id="a", idem_key="   ")
    for scope, actor, k in (
        ("s1", "a", key),
        ("s2", "a", key),
        ("s1", "b", key),
        ("s1", "a", key + "x"),
    ):
        release_in_flight(scope=scope, actor_id=actor, idem_key=k)


def test_claim_expires_after_its_ttl(monkeypatch):
    import kk.idempotency as idem

    key = dict(scope="ttl", actor_id="a", idem_key=f"k-{uuid.uuid4().hex}")
    now = [1000.0]
    monkeypatch.setattr(idem.time, "time", lambda: now[0])
    assert idem.claim_in_flight(**key, ttl_s=10) is True
    now[0] += 5
    assert idem.claim_in_flight(**key, ttl_s=10) is False
    now[0] += 6  # past the TTL of a crashed holder
    assert idem.claim_in_flight(**key, ttl_s=10) is True
    idem.release_in_flight(**key)


def test_exactly_one_of_many_racing_claims_wins():
    from kk.idempotency import claim_in_flight, release_in_flight

    k = dict(scope="race", actor_id="a", idem_key=f"k-{uuid.uuid4().hex}")
    n = 32
    barrier = threading.Barrier(n)
    results: list[bool] = []

    def worker():
        barrier.wait()
        results.append(claim_in_flight(**k))

    threads = [threading.Thread(target=worker) for _ in range(n)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert results.count(True) == 1
    release_in_flight(**k)


# --------------------------------------------------------------------------
# chat send: overlapping duplicate
# --------------------------------------------------------------------------
def _setup(app_ctx, client, seller_ctx, buyer_ctx):
    seller_name, seller_pub = seller_ctx
    buyer_name, _buyer_pub = buyer_ctx
    car_id = _make_car(app_ctx, seller_pub)
    return _login(client, buyer_name), car_id, seller_pub


def test_overlapping_duplicate_is_refused_then_replays_the_original(
    app_ctx, client, seller_ctx, buyer_ctx
):
    from kk.routes import chat as chat_routes

    token, car_id, seller_pub = _setup(app_ctx, client, seller_ctx, buyer_ctx)
    key = f"f37-{uuid.uuid4().hex}"
    before = _message_count(app_ctx)

    real_deliver = chat_routes.deliver_message
    entered = threading.Event()
    release = threading.Event()

    def slow_deliver(*args, **kwargs):
        # The Message is already committed at this point; hold the request open
        # exactly like a slow cold-start request would be.
        entered.set()
        assert release.wait(timeout=20)
        return real_deliver(*args, **kwargs)

    first: dict = {}

    def run_first():
        c = app_ctx[0].test_client()
        r = _send_text(c, token, car_id, seller_pub, idem_key=key)
        first["status"] = r.status_code
        first["body"] = r.get_json()

    from unittest.mock import patch

    with patch.object(chat_routes, "deliver_message", side_effect=slow_deliver):
        t = threading.Thread(target=run_first)
        t.start()
        assert entered.wait(timeout=20), "first request never reached delivery"

        # The client timed out and re-sent the same send while #1 is running.
        dup = _send_text(client, token, car_id, seller_pub, idem_key=key)
        assert dup.status_code == 503, dup.data
        assert dup.get_json()["code"] == "request_in_progress"
        assert dup.headers.get("Retry-After")
        assert _message_count(app_ctx) == before + 1  # no second Message

        release.set()
        t.join(timeout=30)
        assert not t.is_alive()

    assert first["status"] == 201, first
    original_id = first["body"]["message"]["id"]

    # After the original finished, the same key replays its stored response.
    again = _send_text(client, token, car_id, seller_pub, idem_key=key)
    assert again.status_code == 201, again.data
    assert again.get_json()["message"]["id"] == original_id
    assert _message_count(app_ctx) == before + 1


def test_failed_request_releases_the_claim_so_the_key_can_be_retried(
    app_ctx, client, seller_ctx, buyer_ctx
):
    token, car_id, seller_pub = _setup(app_ctx, client, seller_ctx, buyer_ctx)
    key = f"f37-{uuid.uuid4().hex}"
    before = _message_count(app_ctx)

    bad = _send_text(client, token, car_id, seller_pub, idem_key=key, content="   ")
    assert bad.status_code == 400, bad.data
    assert _message_count(app_ctx) == before

    # Same key, now valid: must NOT be treated as "still in progress".
    ok = _send_text(client, token, car_id, seller_pub, idem_key=key)
    assert ok.status_code == 201, ok.data
    assert _message_count(app_ctx) == before + 1


def test_different_keys_do_not_block_each_other(app_ctx, client, seller_ctx, buyer_ctx):
    token, car_id, seller_pub = _setup(app_ctx, client, seller_ctx, buyer_ctx)
    before = _message_count(app_ctx)
    a = _send_text(client, token, car_id, seller_pub, idem_key=f"f37-{uuid.uuid4().hex}")
    b = _send_text(client, token, car_id, seller_pub, idem_key=f"f37-{uuid.uuid4().hex}")
    assert a.status_code == 201 and b.status_code == 201
    assert _message_count(app_ctx) == before + 2
