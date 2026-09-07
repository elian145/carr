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

    D-07: this used to be a SELECT to check existence, then branch to either
    an UPDATE or an INSERT. Two concurrent requests for the same
    ``(user_id, car_id)`` could both observe "not exists" and both attempt
    the INSERT branch; the composite primary key ``(user_id, car_id)`` then
    made the losing side raise an uncaught ``IntegrityError`` (surfaced as
    an HTTP 500 on ``POST /api/user/recently-viewed`` /
    ``POST /api/analytics/track/view``, or silently swallowed -- and the
    write lost -- on the best-effort view-count bump path).

    Fixed with a single dialect-appropriate
    ``INSERT ... ON CONFLICT (user_id, car_id) DO NOTHING``, reusing
    ``kk.listing_metrics._conflict_safe_insert`` -- the exact same D-04
    dialect-detection helper already shared by
    ``get_or_create_analytics()`` / ``_bulk_create_missing_analytics()``,
    so there is only ever one place that decides Postgres vs SQLite
    ``insert()`` syntax in this codebase. The composite primary key is
    itself the conflict target: the database, not a Python check, resolves
    which side "wins" -- there is no window between a check and a write.

    ``result.rowcount`` on this exact statement shape (a single-row
    ``INSERT ... ON CONFLICT ... DO NOTHING``) is standard, dialect-
    independent DBAPI behavior: 1 if our own row was actually inserted, 0
    if a conflict occurred and nothing was written -- both SQLite and
    PostgreSQL report the number of rows the statement itself affected,
    and ``DO NOTHING`` affects zero rows on conflict. This is deliberately
    *not* ``ON CONFLICT ... DO UPDATE``: that variant's rowcount is 1
    whether it inserted or updated, which would make insert-vs-conflict
    ambiguous again without falling back to a PostgreSQL-only trick (e.g.
    ``RETURNING (xmax = 0)``) that has no SQLite equivalent -- exactly the
    kind of dialect-inconsistent assumption this fix avoids.

    If the row already existed (``rowcount == 0``), a second, plain
    ``UPDATE`` refreshes ``viewed_at`` so it is always current on every
    view, matching the pre-fix behavior exactly. This second statement
    cannot raise -- an ``UPDATE`` violates no uniqueness constraint -- so
    it introduces no new race no matter how many callers reach it at once.
    """
    car = _get_car_by_listing_id(listing_id)
    if not car or not car.is_active:
        return None, False
    from .listing_visibility import listing_visible_to_viewer

    if not listing_visible_to_viewer(car, user):
        return None, False

    from .listing_metrics import _conflict_safe_insert

    now = utcnow()
    insert_stmt = (
        _conflict_safe_insert(user_viewed_listings)
        .values(user_id=user.id, car_id=car.id, viewed_at=now)
        .on_conflict_do_nothing(index_elements=["user_id", "car_id"])
    )
    result = db.session.execute(insert_stmt)
    is_first_view = (result.rowcount or 0) > 0

    if not is_first_view:
        db.session.execute(
            update(user_viewed_listings)
            .where(
                user_viewed_listings.c.user_id == user.id,
                user_viewed_listings.c.car_id == car.id,
            )
            .values(viewed_at=now)
        )

    db.session.commit()
    return car, is_first_view


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


def remove_listing_from_all_view_history(car_id: int) -> int:
    """Remove a listing from every user's recently viewed (e.g. when deleted)."""
    if not car_id:
        return 0
    result = db.session.execute(
        delete(user_viewed_listings).where(user_viewed_listings.c.car_id == car_id)
    )
    return int(result.rowcount or 0)
