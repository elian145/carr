from __future__ import annotations

from sqlalchemy import delete, update

from .models import Car, User, db, user_viewed_listings
from .time_utils import utcnow


def _get_car_by_listing_id(listing_id: str) -> Car | None:
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


def record_user_listing_view(user: User, listing_id: str) -> tuple[Car | None, bool]:
    """
    Upsert user_viewed_listings for recently viewed.

    Returns (car, is_first_view) where is_first_view is True when a new row was inserted.
    """
    car = _get_car_by_listing_id(listing_id)
    if not car or not car.is_active:
        return None, False

    exists = db.session.execute(
        user_viewed_listings.select()
        .with_only_columns(user_viewed_listings.c.user_id)
        .where(
            user_viewed_listings.c.user_id == user.id,
            user_viewed_listings.c.car_id == car.id,
        )
    ).first()

    now = utcnow()
    if exists:
        db.session.execute(
            update(user_viewed_listings)
            .where(
                user_viewed_listings.c.user_id == user.id,
                user_viewed_listings.c.car_id == car.id,
            )
            .values(viewed_at=now)
        )
        db.session.commit()
        return car, False

    db.session.execute(
        user_viewed_listings.insert().values(
            user_id=user.id,
            car_id=car.id,
            viewed_at=now,
        )
    )
    db.session.commit()
    return car, True


def delete_user_listing_view(user: User, listing_id: str) -> bool:
    """Remove one listing from the user's recently viewed history."""
    car = _get_car_by_listing_id(listing_id)
    if not car:
        return False
    db.session.execute(
        delete(user_viewed_listings).where(
            user_viewed_listings.c.user_id == user.id,
            user_viewed_listings.c.car_id == car.id,
        )
    )
    db.session.commit()
    return True


def clear_user_listing_views(user: User) -> None:
    """Remove all recently viewed rows for the user."""
    db.session.execute(
        delete(user_viewed_listings).where(
            user_viewed_listings.c.user_id == user.id,
        )
    )
    db.session.commit()
