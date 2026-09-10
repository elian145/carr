"""
Trusted listing engagement metrics (seller analytics).

Client ``/api/analytics/track/*`` endpoints are easy to game. Prefer:
- views: first authenticated view per user (not the seller)
- messages: real chat sends from non-sellers
- favorites: real favorite adds
- calls / shares: at most once per user per listing per day (best-effort dedupe)
"""

from __future__ import annotations

import logging
import time
from typing import Literal

from sqlalchemy import update

from .models import Car, ListingAnalytics, ListingViewClaim, User, db
from .time_utils import utcnow

logger = logging.getLogger(__name__)

MetricField = Literal["views", "messages", "calls", "shares", "favorites"]

_ALLOWED_FIELDS = frozenset({"views", "messages", "calls", "shares", "favorites"})

# Best-effort dedupe for call/share (and similar) when Redis is unavailable.
# key -> expires_at epoch
_memory_claims: dict[str, float] = {}
_MEMORY_CLAIMS_MAX = 20_000

_CALL_SHARE_TTL_S = 60 * 60 * 24  # 24h


def _redis_client():
    try:
        from .security import _redis_client as redis_client

        return redis_client()
    except Exception:
        return None


def _purge_memory_claims() -> None:
    now = time.time()
    expired = [k for k, exp in _memory_claims.items() if exp <= now]
    for k in expired:
        _memory_claims.pop(k, None)
    if len(_memory_claims) > _MEMORY_CLAIMS_MAX:
        # Drop oldest ~10%.
        for k in list(_memory_claims.keys())[: int(_MEMORY_CLAIMS_MAX * 0.1)]:
            _memory_claims.pop(k, None)


def claim_unique_engagement(
    *,
    user_id: int,
    car_id: int,
    action: str,
    ttl_s: int = _CALL_SHARE_TTL_S,
) -> bool:
    """
    Return True once per (user, car, action) within ``ttl_s``.

    Uses Redis SET NX when available; otherwise an in-process map.
    """
    key = f"analytics:claim:{int(user_id)}:{int(car_id)}:{action}"
    ttl = max(60, int(ttl_s))
    r = _redis_client()
    if r is not None:
        try:
            # SET NX EX — first claim wins.
            ok = r.set(key, "1", nx=True, ex=ttl)
            return bool(ok)
        except Exception:
            logger.exception("analytics claim Redis failed for %s", key)

    _purge_memory_claims()
    now = time.time()
    existing = _memory_claims.get(key)
    if existing is not None and existing > now:
        return False
    _memory_claims[key] = now + ttl
    return True


def clear_engagement_claims_for_tests() -> None:
    _memory_claims.clear()


def get_car_for_analytics(listing_id: str) -> Car | None:
    lid = (listing_id or "").strip()
    if not lid:
        return None
    car = Car.query.filter_by(public_id=lid).first()
    if car:
        return car
    if lid.isdigit():
        try:
            return Car.query.filter_by(id=int(lid)).first()
        except Exception:
            return None
    return None


def _conflict_safe_insert(model):
    """
    Return the dialect-appropriate conflict-aware ``insert()`` construct for
    ``model`` (Postgres or SQLite ``INSERT ... ON CONFLICT``).

    D-04: shared by ``get_or_create_analytics()`` and
    ``_bulk_create_missing_analytics()`` so the dialect-detection logic
    exists exactly once. Mirrors the existing
    ``bind.dialect.name == "sqlite"`` idiom already used elsewhere in this
    codebase (e.g. ``kk/app_factory.py``, ``kk/routes/auth.py``). Only
    Postgres (production/CI) and SQLite (local/dev/tests) are ever used by
    this project (see ``kk/config.py``), so any other dialect fails loudly
    instead of silently guessing which conflict syntax to emit.
    """
    bind = db.session.get_bind()
    dialect_name = getattr(getattr(bind, "dialect", None), "name", "") or ""
    if dialect_name == "postgresql":
        from sqlalchemy.dialects.postgresql import insert as _insert
    elif dialect_name == "sqlite":
        from sqlalchemy.dialects.sqlite import insert as _insert
    else:
        raise RuntimeError(
            f"_conflict_safe_insert: unsupported database dialect {dialect_name!r}"
        )
    return _insert(model)


def get_or_create_analytics(car: Car) -> tuple[ListingAnalytics, bool]:
    """
    Return ``(row, created)`` for ``car``'s ListingAnalytics, creating it if
    missing.

    D-04: replaces the previous SELECT-then-INSERT (two requests racing to
    create the same missing row could both pass the SELECT and then hit the
    ``listing_analytics.car_id`` unique index as an uncaught
    ``IntegrityError``, dropping a metric bump and surfacing a 500). Uses a
    single ``INSERT ... ON CONFLICT (car_id) DO NOTHING`` instead: the
    database itself serializes the race, so the losing side's insert is a
    silent no-op rather than an exception, and both sides then reliably
    re-read the one resulting row. Only that exact conflict resolves
    silently here -- any other database error still propagates normally.

    Does not commit; the caller commits (only when ``created`` is True, to
    preserve the previous "only write when something actually changed"
    behavior) together with whatever else it does in the same transaction.
    """
    existing = ListingAnalytics.query.filter_by(car_id=car.id).first()
    if existing is not None:
        return existing, False

    stmt = (
        _conflict_safe_insert(ListingAnalytics)
        .values(car_id=car.id)
        .on_conflict_do_nothing(index_elements=["car_id"])
    )
    db.session.execute(stmt)

    row = ListingAnalytics.query.filter_by(car_id=car.id).first()
    if row is None:
        # Unreachable in practice: the unique index on car_id guarantees
        # either our insert or a concurrent winner's insert has landed.
        raise RuntimeError(
            f"ListingAnalytics row missing for car_id={car.id} after upsert"
        )
    return row, True


def _bulk_create_missing_analytics(missing_car_ids: list[int]) -> None:
    """
    Insert ListingAnalytics rows for every id in ``missing_car_ids`` in a
    single statement.

    D-04: for callers (``get_listings_analytics()``) that already know --
    from a previously-fetched ``existing`` set -- exactly which car_ids are
    missing. Deliberately has no per-id existence check (that would
    reintroduce the N extra SELECT round trips the caller's pre-fetched set
    exists to avoid); one multi-row
    ``INSERT ... ON CONFLICT (car_id) DO NOTHING`` covers the whole batch in
    one round trip, same as a single-row call. Does not commit.
    """
    if not missing_car_ids:
        return
    stmt = (
        _conflict_safe_insert(ListingAnalytics)
        .values([{"car_id": cid} for cid in missing_car_ids])
        .on_conflict_do_nothing(index_elements=["car_id"])
    )
    db.session.execute(stmt)


def bump_listing_metric(car: Car, field: MetricField) -> None:
    """Atomically increment a ListingAnalytics counter (creates row if needed)."""
    if field not in _ALLOWED_FIELDS:
        raise ValueError(f"unsupported metric: {field}")
    if not car or not getattr(car, "id", None):
        return

    get_or_create_analytics(car)

    col = getattr(ListingAnalytics, field)
    db.session.execute(
        update(ListingAnalytics)
        .where(ListingAnalytics.car_id == car.id)
        .values(**{field: col + 1, "updated_at": utcnow()})
    )
    db.session.commit()


def claim_listing_view_once(user_id: int, car_id: int) -> bool:
    """
    BE-11: atomically claim "this user's view of this listing has been
    counted toward ``ListingAnalytics.views``" -- exactly once, forever.

    Returns ``True`` the first time this ``(user_id, car_id)`` pair is
    claimed, ``False`` on every subsequent call (including calls that race
    each other concurrently -- see below).

    Backed entirely by ``ListingViewClaim``'s ``UNIQUE(user_id, car_id)``
    constraint via a single ``INSERT ... ON CONFLICT DO NOTHING ...
    RETURNING`` statement -- there is deliberately no Python-side "does a
    row already exist" check beforehand (a SELECT-then-INSERT would leave a
    window where two concurrent callers for the same pair both observe "no
    row yet" and both attempt the insert; only one can ever land once the
    unique constraint is enforced, but a naive check-then-act could still
    have returned ``True`` to both callers before either insert happened).
    The database's uniqueness constraint -- not this function's control
    flow -- is what makes the claim correct under real concurrency, exactly
    like ``record_user_listing_view()``'s own upsert (``kk/view_history.py``)
    and ``get_or_create_analytics()``'s upsert (this module) already do
    (D-04/D-07). Uses ``.returning(...)`` rather than ``result.rowcount`` to
    detect insert-vs-conflict, for the same reason documented in
    ``record_user_listing_view()``: rowcount is not reliable for this
    purpose under real concurrent PostgreSQL callers.

    Deliberately independent of ``record_user_listing_view()`` /
    ``user_viewed_listings`` (recently-viewed history -- shared, before
    BE-11's fix, with the detail-page GET's best-effort ``Car.views_count``
    bump) and of ``claim_unique_engagement()`` (Redis-preferred /
    in-process-fallback, TTL-based dedupe used only by calls/shares' 24h
    best-effort anti-gaming dedupe -- unsuitable for a permanent claim
    because it cannot survive a Redis restart/eviction/outage and is not
    concurrency-safe across worker processes on its in-memory fallback
    path). See ``ListingViewClaim`` (``kk/models.py``) for the full
    rationale.

    Commits internally (self-contained, like ``record_user_listing_view()``):
    a conflict (``False``) has no pending change to commit either way, and a
    successful claim (``True``) is durably persisted the moment this
    function returns, independent of whatever the caller does next. No
    exception is caught/swallowed here -- a real DB failure propagates to
    the caller unchanged, exactly like every other write path in this
    module.
    """
    stmt = (
        _conflict_safe_insert(ListingViewClaim)
        .values(user_id=int(user_id), car_id=int(car_id), claimed_at=utcnow())
        .on_conflict_do_nothing(index_elements=["user_id", "car_id"])
        .returning(ListingViewClaim.id)
    )
    inserted = db.session.execute(stmt).first()
    db.session.commit()
    return inserted is not None


def record_trusted_view(user: User, listing_id: str) -> dict:
    """
    Record recently-viewed + increment analytics views at most once per user.

    Seller viewing their own listing does not bump the seller-facing view metric.

    BE-11: the recently-viewed side effect (``record_user_listing_view()``,
    which drives the "recently viewed" feature and is also independently
    consumed by the detail-page GET's best-effort ``Car.views_count`` bump)
    and the analytics-count gate (``claim_listing_view_once()``, brand new,
    used for nothing else) are two deliberately separate dedup mechanisms.
    ``record_user_listing_view()`` is still called, unchanged, for its own
    purpose -- its ``is_first_view`` return value is no longer used to
    decide whether to bump ``ListingAnalytics.views``. This is what allows
    ``GET`` detail (which only ever touches ``user_viewed_listings`` /
    ``Car.views_count``) and ``POST /api/analytics/track/view`` (which now
    only ever touches ``listing_view_claim`` / ``ListingAnalytics.views``)
    to no longer steal each other's dedup state, in either call order.
    """
    from .view_history import record_user_listing_view

    car, _is_first_recently_viewed = record_user_listing_view(user, listing_id)
    if not car:
        return {"ok": False, "counted": False, "code": "listing_not_found"}

    if car.seller_id == user.id:
        return {"ok": True, "counted": False, "code": "own_listing"}

    if not claim_listing_view_once(user.id, car.id):
        return {"ok": True, "counted": False, "code": "already_viewed"}

    bump_listing_metric(car, "views")
    return {"ok": True, "counted": True, "code": "counted"}


def record_call_or_share(user: User, listing_id: str, field: MetricField) -> dict:
    if field not in ("calls", "shares"):
        return {"ok": False, "counted": False, "code": "unsupported"}

    car = get_car_for_analytics(listing_id)
    if not car or not car.is_active:
        return {"ok": False, "counted": False, "code": "listing_not_found"}
    from .listing_visibility import listing_visible_to_viewer

    if not listing_visible_to_viewer(car, user):
        return {"ok": False, "counted": False, "code": "listing_not_found"}
    if car.seller_id == user.id:
        return {"ok": True, "counted": False, "code": "own_listing"}

    if not claim_unique_engagement(
        user_id=user.id, car_id=car.id, action=field, ttl_s=_CALL_SHARE_TTL_S
    ):
        return {"ok": True, "counted": False, "code": "deduped"}

    bump_listing_metric(car, field)
    return {"ok": True, "counted": True, "code": "counted"}


def record_buyer_message(car: Car, sender: User) -> None:
    """Count a real chat send from someone who is not the listing seller."""
    if not car or not sender:
        return
    if car.seller_id == sender.id:
        return
    if not car.is_active:
        return
    try:
        bump_listing_metric(car, "messages")
    except Exception:
        logger.exception("Failed to bump messages metric for car_id=%s", getattr(car, "id", None))
        try:
            db.session.rollback()
        except Exception:
            pass


def record_favorite_add(car: Car, user: User) -> None:
    """Count a real favorite add (not remove / not own listing)."""
    if not car or not user:
        return
    if car.seller_id == user.id:
        return
    try:
        bump_listing_metric(car, "favorites")
    except Exception:
        logger.exception("Failed to bump favorites metric for car_id=%s", getattr(car, "id", None))
        try:
            db.session.rollback()
        except Exception:
            pass
