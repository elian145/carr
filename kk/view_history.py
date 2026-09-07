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

    Insert-vs-conflict is detected with ``.returning(...)`` on the INSERT
    itself, NOT ``result.rowcount``. A real PostgreSQL concurrency smoke
    (``scripts/ci_migration_smoke.py::_d07_view_history_upsert_smoke``)
    proved ``rowcount`` unreliable here: under 20 real concurrent
    PostgreSQL callers it reported 0 for every single call, including the
    one call that actually inserted the row (SQLite alone never surfaced
    this -- its ``rowcount`` behaved exactly as expected in isolation,
    which is exactly the "don't assume dialect parity" trap this rewrite
    exists to avoid). ``RETURNING`` combined with ``ON CONFLICT DO
    NOTHING`` is standard, documented behavior on both dialects and does
    not depend on DBAPI/driver rowcount bookkeeping at all: PostgreSQL has
    emitted no row for a DO-NOTHING conflict under RETURNING since 9.5,
    and SQLite (3.35+; this project's SQLite is 3.35+ everywhere it runs)
    behaves identically -- verified directly here by executing both the
    successful-insert and the conflict case against a real SQLite
    connection. If ``.first()`` on the INSERT's result returns a row, our
    own call performed the insert (``is_first_view = True``); if it
    returns ``None``, some other caller's insert already committed (or
    committed as we raced) and we lost nothing but the redundant write
    (``is_first_view = False``).

    If the row already existed (no row returned), a second, plain
    ``UPDATE`` refreshes ``viewed_at`` so it is always current on every
    view, matching the pre-fix behavior exactly. This second statement
    cannot raise -- an ``UPDATE`` violates no uniqueness constraint -- so
    it introduces no new race no matter how many callers reach it at once,
    and it is never itself used to detect the race (only to apply the
    already-safely-determined "not first view" side effect).
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
        .returning(user_viewed_listings.c.user_id)
    )
    inserted_row = db.session.execute(insert_stmt).first()
    is_first_view = inserted_row is not None

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
