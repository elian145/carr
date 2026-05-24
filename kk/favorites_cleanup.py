from __future__ import annotations

from sqlalchemy import delete

from .models import db, user_favorites


def remove_listing_from_all_favorites(car_id: int) -> int:
    """Remove a listing from every user's favorites (e.g. when listing is deleted)."""
    if not car_id:
        return 0
    result = db.session.execute(
        delete(user_favorites).where(user_favorites.c.car_id == car_id)
    )
    return int(result.rowcount or 0)
