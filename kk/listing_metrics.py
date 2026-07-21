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

from .models import Car, ListingAnalytics, User, db
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


def bump_listing_metric(car: Car, field: MetricField) -> None:
    """Atomically increment a ListingAnalytics counter (creates row if needed)."""
    if field not in _ALLOWED_FIELDS:
        raise ValueError(f"unsupported metric: {field}")
    if not car or not getattr(car, "id", None):
        return

    a = ListingAnalytics.query.filter_by(car_id=car.id).first()
    if not a:
        a = ListingAnalytics(car_id=car.id)
        db.session.add(a)
        db.session.flush()

    col = getattr(ListingAnalytics, field)
    db.session.execute(
        update(ListingAnalytics)
        .where(ListingAnalytics.car_id == car.id)
        .values(**{field: col + 1, "updated_at": utcnow()})
    )
    db.session.commit()


def record_trusted_view(user: User, listing_id: str) -> dict:
    """
    Record recently-viewed + increment analytics views at most once per user.

    Seller viewing their own listing does not bump the seller-facing view metric.
    """
    from .view_history import record_user_listing_view

    car, is_first = record_user_listing_view(user, listing_id)
    if not car:
        return {"ok": False, "counted": False, "code": "listing_not_found"}

    if car.seller_id == user.id:
        return {"ok": True, "counted": False, "code": "own_listing"}

    if not is_first:
        return {"ok": True, "counted": False, "code": "already_viewed"}

    bump_listing_metric(car, "views")
    return {"ok": True, "counted": True, "code": "counted"}


def record_call_or_share(user: User, listing_id: str, field: MetricField) -> dict:
    if field not in ("calls", "shares"):
        return {"ok": False, "counted": False, "code": "unsupported"}

    car = get_car_for_analytics(listing_id)
    if not car or not car.is_active:
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
