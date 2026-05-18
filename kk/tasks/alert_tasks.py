"""
Background (or inline) tasks for saved-search and price-drop push notifications.
"""
from __future__ import annotations

import logging

from ..listing_filters import car_matches_filters, summarize_filters
from ..models import Car, Notification, SavedSearch, SavedSearchAlert, User, db, user_favorites
from ..push import send_push
from sqlalchemy import update as sql_update

from .celery_app import celery_app

logger = logging.getLogger(__name__)


def _app_context():
    from ..app_factory import create_app

    app, *_ = create_app()
    return app


def _send_retention_push(
    user: User,
    *,
    title: str,
    body: str,
    notification_type: str,
    data: dict | None = None,
) -> None:
    token = getattr(user, "firebase_token", None)
    if token:
        send_push(token, title=title, body=body, data=data or {})

    try:
        notif = Notification(
            user_id=user.id,
            title=title,
            message=body,
            notification_type=notification_type,
            is_read=False,
            data=data or {},
        )
        db.session.add(notif)
        db.session.commit()
    except Exception:
        db.session.rollback()


@celery_app.task(name="kk.tasks.alert_tasks.notify_saved_searches_for_car")
def notify_saved_searches_for_car(car_id: int) -> dict:
    app = _app_context()
    with app.app_context():
        car = db.session.get(Car, car_id)
        if not car or not car.is_active:
            return {"matched": 0, "skipped": "inactive_or_missing"}

        searches = (
            SavedSearch.query.filter_by(notify=True)
            .filter(SavedSearch.user_id != car.seller_id)
            .all()
        )
        matched = 0
        for search in searches:
            filters = search.filters if isinstance(search.filters, dict) else {}
            if not car_matches_filters(car, filters):
                continue

            existing = SavedSearchAlert.query.filter_by(
                saved_search_id=search.id,
                car_id=car.id,
            ).first()
            if existing:
                continue

            user = db.session.get(User, search.user_id)
            if not user or not user.is_active:
                continue

            summary = summarize_filters(filters)
            title = search.name or "Saved search"
            body = f"{summary}: {car.brand} {car.model} {car.year}".strip()
            _send_retention_push(
                user,
                title=title,
                body=body[:200],
                notification_type="saved_search",
                data={
                    "car_id": car.public_id,
                    "saved_search_id": search.public_id,
                },
            )

            db.session.add(
                SavedSearchAlert(saved_search_id=search.id, car_id=car.id)
            )
            try:
                db.session.commit()
            except Exception:
                db.session.rollback()
                continue
            matched += 1

        return {"matched": matched}


@celery_app.task(name="kk.tasks.alert_tasks.notify_price_drop_for_car")
def notify_price_drop_for_car(car_id: int, old_price: float, new_price: float) -> dict:
    app = _app_context()
    with app.app_context():
        if new_price >= old_price:
            return {"notified": 0, "skipped": "not_a_drop"}

        car = db.session.get(Car, car_id)
        if not car or not car.is_active:
            return {"notified": 0, "skipped": "inactive_or_missing"}

        rows = (
            db.session.query(user_favorites.c.user_id, user_favorites.c.price_at_favorite)
            .filter(user_favorites.c.car_id == car.id)
            .all()
        )
        notified = 0
        currency = (car.currency or "USD").upper()
        title = "Price drop"
        body = (
            f"{car.brand} {car.model} {car.year}: "
            f"{currency} {old_price:,.0f} → {currency} {new_price:,.0f}"
        ).replace(",", " ")

        for user_id, price_at_favorite in rows:
            baseline = price_at_favorite if price_at_favorite is not None else old_price
            if baseline is None or new_price >= float(baseline):
                continue

            user = db.session.get(User, user_id)
            if not user or not user.is_active or user.id == car.seller_id:
                continue

            _send_retention_push(
                user,
                title=title,
                body=body[:200],
                notification_type="price_drop",
                data={"car_id": car.public_id, "old_price": str(old_price), "new_price": str(new_price)},
            )
            notified += 1

            try:
                db.session.execute(
                    sql_update(user_favorites)
                    .where(
                        user_favorites.c.user_id == user_id,
                        user_favorites.c.car_id == car.id,
                    )
                    .values(price_at_favorite=new_price)
                )
                db.session.commit()
            except Exception:
                db.session.rollback()

        return {"notified": notified}
