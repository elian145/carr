"""Who can see a listing.

Public browse/search/profiles only include ``active`` and ``sold``.
``pending`` / ``hidden`` / ``draft`` (under review) are owner-or-admin only.
"""

from __future__ import annotations

from sqlalchemy import or_

from .models import Car

PUBLIC_LISTING_STATUSES = frozenset({"active", "sold"})
MODERATION_LISTING_STATUSES = frozenset({"pending", "hidden", "draft"})


def listing_status_key(car) -> str:
    return (getattr(car, "status", None) or "active").strip().lower()


def listing_is_public(car) -> bool:
    status = listing_status_key(car)
    return status in PUBLIC_LISTING_STATUSES or status == ""


def listing_visible_to_viewer(car, viewer) -> bool:
    """Public statuses are visible to everyone; pending/hidden/draft only to owner/admin."""
    if listing_is_public(car):
        return True
    if viewer is None:
        return False
    if getattr(viewer, "is_admin", False):
        return True
    return getattr(viewer, "id", None) == getattr(car, "seller_id", None)


def public_listings_filter(query):
    """Browseable listings only (active + sold). Pending/hidden/draft stay private."""
    return query.filter(
        Car.is_active.is_(True),
        or_(Car.status.is_(None), Car.status.in_(tuple(PUBLIC_LISTING_STATUSES))),
    )


def listings_visible_to_viewer_filter(query, viewer):
    """SQL filter matching ``listing_visible_to_viewer`` for active rows."""
    public = or_(
        Car.status.is_(None),
        Car.status.in_(tuple(PUBLIC_LISTING_STATUSES)),
    )
    query = query.filter(Car.is_active.is_(True))
    if viewer is not None and getattr(viewer, "is_admin", False):
        return query
    if viewer is not None and getattr(viewer, "id", None) is not None:
        return query.filter(or_(public, Car.seller_id == viewer.id))
    return query.filter(public)
