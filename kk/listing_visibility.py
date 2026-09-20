"""Who can see a listing.

Public browse/search/profiles only include ``active`` and ``sold``.
``pending`` / ``hidden`` / ``draft`` (under review) are owner-or-admin only.
"""

from __future__ import annotations

from sqlalchemy import or_

from .models import Car, User

PUBLIC_LISTING_STATUSES = frozenset({"active", "sold"})
MODERATION_LISTING_STATUSES = frozenset({"pending", "hidden", "draft"})


def listing_status_key(car) -> str:
    return (getattr(car, "status", None) or "active").strip().lower()


def listing_is_public(car) -> bool:
    status = listing_status_key(car)
    if status not in PUBLIC_LISTING_STATUSES and status != "":
        return False
    # CarNet V1 fix 5: a deactivated/banned seller's listings must disappear
    # from every public surface, not just get hidden by their own status.
    # `car.seller` is normally already eager-loaded (`joinedload(Car.seller)`)
    # by every caller of this function, so this is not an extra query.
    seller = getattr(car, "seller", None)
    if seller is not None and not getattr(seller, "is_active", True):
        return False
    return True


def listing_visible_to_viewer(car, viewer) -> bool:
    """Public statuses (from an active seller) are visible to everyone;
    pending/hidden/draft -- and anything from a deactivated seller -- are
    owner/admin only. An admin can always inspect/moderate a deactivated
    seller's listings; the owner's own view is unaffected (deactivation
    hides listings from everyone else, it does not delete/alter them)."""
    if listing_is_public(car):
        return True
    if viewer is None:
        return False
    if getattr(viewer, "is_admin", False):
        return True
    return getattr(viewer, "id", None) == getattr(car, "seller_id", None)


def public_listings_filter(query):
    """Browseable listings only (active + sold, from an active seller).
    Pending/hidden/draft -- and anything from a deactivated/banned seller --
    stay private. Joins ``User`` (on the existing ``Car.seller_id`` FK) so
    this is a single query, not N+1."""
    return query.join(User, Car.seller_id == User.id).filter(
        Car.is_active.is_(True),
        or_(Car.status.is_(None), Car.status.in_(tuple(PUBLIC_LISTING_STATUSES))),
        User.is_active.is_(True),
    )


def listings_visible_to_viewer_filter(query, viewer):
    """SQL filter matching ``listing_visible_to_viewer`` for active rows."""
    query = query.join(User, Car.seller_id == User.id).filter(Car.is_active.is_(True))
    public = or_(
        Car.status.is_(None),
        Car.status.in_(tuple(PUBLIC_LISTING_STATUSES)),
    ) & User.is_active.is_(True)
    if viewer is not None and getattr(viewer, "is_admin", False):
        return query
    if viewer is not None and getattr(viewer, "id", None) is not None:
        return query.filter(or_(public, Car.seller_id == viewer.id))
    return query.filter(public)
