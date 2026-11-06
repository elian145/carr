"""
Background (or inline) tasks for saved-search and price-drop push notifications.
"""
from __future__ import annotations

import logging
import time
from decimal import Decimal, InvalidOperation

from .. import saved_search_alert_jobs as alert_jobs
from ..listing_filters import car_matches_filters, summarize_filters
from ..localization import get_background_locale, translate
from ..models import Car, Notification, SavedSearch, SavedSearchAlert, User, db, user_favorites
from ..push import send_push
from sqlalchemy import update as sql_update
from sqlalchemy.exc import IntegrityError, SQLAlchemyError

from .celery_app import celery_app

logger = logging.getLogger(__name__)


def _send_retention_push(
    user: User,
    *,
    title: str,
    body: str,
    notification_type: str,
    data: dict | None = None,
    commit: bool = True,
) -> bool | None:
    """Push + in-app ``Notification``.

    Default (``commit=True``) is the historical behaviour used by every
    existing caller: the Notification is committed here and any error is
    swallowed. ``commit=False`` (F-04 claim-first path) only ADDS the
    Notification to the caller's session -- the caller commits it together
    with its claim row and owns rollback. Returns ``send_push``'s result
    (``None`` when the user has no token).
    """
    token = getattr(user, "firebase_token", None)
    sent: bool | None = None
    if token:
        sent = send_push(token, title=title, body=body, data=data or {}, user_id=user.id)

    if not commit:
        db.session.add(
            Notification(
                user_id=user.id,
                title=title,
                message=body,
                notification_type=notification_type,
                is_read=False,
                data=data or {},
            )
        )
        return sent

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
    return sent


@celery_app.task(name="kk.tasks.alert_tasks.notify_saved_searches_for_car")
def notify_saved_searches_for_car(car_id: int) -> dict:
    """Alert matching saved searches about a newly published listing.

    ``SAVED_SEARCH_ALERT_DURABILITY=off`` (the default) runs the unchanged
    legacy implementation below. ``record`` / ``on`` run the job-aware,
    claim-first implementation (``process_saved_search_alert_job``). The same
    task is the fast-path message and the sweep's per-job redrive message.
    """
    mode = alert_jobs.durability_mode()
    if mode == alert_jobs.MODE_OFF:
        return _notify_saved_searches_legacy(car_id)
    return process_saved_search_alert_job(car_id, mode=mode)


@celery_app.task(name="kk.reconcile_saved_search_alerts", soft_time_limit=60, time_limit=90)
def reconcile_saved_search_alerts() -> dict:
    """Beat tick (every 5 min): expire / fail / redrive owed alert jobs.

    Short DB statements plus <= ``SAVED_SEARCH_ALERT_SWEEP_BATCH`` enqueues of
    ``notify_saved_searches_for_car`` per tick; the alert work itself runs in
    those per-job tasks, never inline here. A no-op unless the flag is
    ``record`` (count/log only) or ``on``.
    """
    return alert_jobs.reconcile(enqueue=_enqueue_alert_job)


def _enqueue_alert_job(car_id: int, *, expires: float) -> None:
    # Same publish options as retention_dispatch (no result subscription, no
    # inline publish retry). Exceptions propagate to reconcile(), which
    # releases the dispatch lease so the next tick retries. ``expires`` keeps a
    # queued redrive from outliving its dispatch lease.
    notify_saved_searches_for_car.apply_async(
        args=(car_id,), ignore_result=True, retry=False, expires=expires
    )


def _notify_saved_searches_legacy(car_id: int) -> dict:
    from ..listing_visibility import listing_is_public

    car = db.session.get(Car, car_id)
    if not car or not car.is_active or not listing_is_public(car):
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
        # MI-03: background task -- no request context, use the recipient's
        # stored locale (> English). Only the fallback label is localized;
        # a user-given search name is left exactly as the user typed it.
        title = search.name or translate(
            "saved_search_default_title", get_background_locale(getattr(user, "locale", None))
        )
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


# ---------------------------------------------------------------------------
# F-04 durable path (SAVED_SEARCH_ALERT_DURABILITY = record | on)
# ---------------------------------------------------------------------------
#
# Claim first, then push, then ONE commit. For each matching (saved search,
# car) pair:
#
#   1. insert the ``SavedSearchAlert`` row and FLUSH (the claim). On
#      PostgreSQL a concurrent claimer blocks on the unique index until we
#      commit (then it fails with IntegrityError and does NOT push) or roll
#      back (then it proceeds). IntegrityError -> skip the pair, no push.
#   2. push (``send_push``; never raises ``Exception``, returns a bool).
#   3. add the in-app ``Notification`` to the SAME session and commit it
#      together with the claim.
#
# Crash / retry semantics -- the external push is AT-LEAST-ONCE per pair, not
# exactly-once, and duplicates are bounded:
#
# * process killed (or ``SystemExit``) after the claim flush but before the
#   push: the claim was never committed -> rolled back by the database; the
#   job's lease expires and the redrive pushes the pair (nothing was sent,
#   nothing is lost).
# * killed after the push but before the commit: same rollback, so the redrive
#   pushes the pair AGAIN: one duplicate push, never a missed one. The user's
#   in-app Notification is only ever committed together with the claim, so it
#   is not duplicated. Duplicates are bounded by MAX_ATTEMPTS per job.
# * the commit itself raises: rollback, the pair counts as an ERROR of this
#   run -> the job is deferred with back-off (attempt counted) and redriven;
#   pairs committed earlier in the run are skipped by the redrive; the failed
#   pair is pushed again (at-least-once).
# * ``send_push`` raising a non-``Exception`` BaseException: propagates; the
#   lease handles recovery exactly as for a crash.
# * ``send_push`` returning False (FCM rejected / no Firebase configured): NOT
#   retried -- unchanged from the legacy behaviour; the claim and the in-app
#   Notification are still committed. The push channel is best effort.
# * partial progress: pairs are committed one by one, so a redrive resumes
#   with the remaining pairs only.
# * the car stopped being public: nothing is sent, the job stays owed
#   (re-checked every NOT_PUBLIC_RECHECK_SECONDS) until it is delivered or
#   expires with the recovery window.


def _alert_one_pair(
    car_id: int,
    search_id: int,
    search_user_id: int,
    search_name: str | None,
    search_public_id: str | None,
    raw_filters,
) -> str:
    """Claim, push and record one (saved search, car) pair.

    Returns one of ``no_car | no_match | already | no_user | lost_race | sent``.
    Raises on any failure after the claim (the claim is rolled back first).
    """
    car = db.session.get(Car, car_id)
    if car is None:
        return "no_car"
    filters = raw_filters if isinstance(raw_filters, dict) else {}
    if not car_matches_filters(car, filters):
        return "no_match"
    if (
        db.session.query(SavedSearchAlert.id)
        .filter_by(saved_search_id=search_id, car_id=car_id)
        .first()
        is not None
    ):
        return "already"
    user = db.session.get(User, search_user_id)
    if not user or not user.is_active:
        return "no_user"

    # 1. CLAIM (flushed, not committed).
    db.session.add(SavedSearchAlert(saved_search_id=search_id, car_id=car_id))
    try:
        db.session.flush()
    except IntegrityError:
        db.session.rollback()
        return "lost_race"  # someone else owns this pair; they push, we do not

    summary = summarize_filters(filters)
    title = search_name or translate(
        "saved_search_default_title", get_background_locale(getattr(user, "locale", None))
    )
    body = f"{summary}: {car.brand} {car.model} {car.year}".strip()
    try:
        # 2. PUSH + 3. Notification in the same session, ONE commit.
        _send_retention_push(
            user,
            title=title,
            body=body[:200],
            notification_type="saved_search",
            data={"car_id": car.public_id, "saved_search_id": search_public_id},
            commit=False,
        )
        db.session.commit()
    except Exception:
        db.session.rollback()  # releases the claim: the pair is retried
        raise
    return "sent"


def _alert_pairs_claim_first(car_id: int, *, deadline: float | None, monotonic=time.monotonic) -> dict:
    """Run every matching saved search for the car, claim-first.

    ``status``: ``done`` (nothing left), ``not_public``, ``partial_errors``
    (>= 1 pair failed after its claim was rolled back) or ``partial_budget``
    (stopped at the wall-clock budget; no failure).
    """
    from ..listing_visibility import listing_is_public

    car = db.session.get(Car, car_id)
    if not car or not car.is_active or not listing_is_public(car):
        db.session.rollback()
        return {"matched": 0, "status": "not_public", "errors": 0}

    # Same population as the legacy task (notify=True, not the seller's own;
    # a NULL seller matches nothing, as before). Plain values only: they
    # survive the commits/rollbacks below.
    searches = (
        db.session.query(
            SavedSearch.id,
            SavedSearch.user_id,
            SavedSearch.name,
            SavedSearch.public_id,
            SavedSearch.filters,
        )
        .filter(SavedSearch.notify == True)  # noqa: E712
        .filter(SavedSearch.user_id != car.seller_id)
        .all()
    )
    db.session.rollback()  # end the read transaction before any push
    matched = 0
    errors = 0
    budget_hit = False
    for sid, uid, sname, spub, sfilters in searches:
        if deadline is not None and monotonic() >= deadline:
            budget_hit = True
            break
        try:
            result = _alert_one_pair(car_id, sid, uid, sname, spub, sfilters)
        except Exception:
            errors += 1
            logger.exception(
                "saved-search alert pair failed (search=%s car=%s); will be retried", sid, car_id
            )
            continue
        if result == "no_car":
            return {"matched": matched, "status": "not_public", "errors": errors}
        if result == "sent":
            matched += 1
    status = "partial_errors" if errors else ("partial_budget" if budget_hit else "done")
    return {"matched": matched, "status": status, "errors": errors}


def process_saved_search_alert_job(
    car_id: int,
    *,
    mode: str,
    now=None,
    budget_seconds: float | None = None,
    monotonic=time.monotonic,
) -> dict:
    """Job-aware alert run (flag ``record`` or ``on``).

    ``on``: take the job lease first (one atomic UPDATE) -- a finished /
    leased / expired job is a no-op, so a duplicate or late message cannot
    alert again; no job at all (listing published before the flag, or the
    message was queued before the deploy) falls back to the plain claim-first
    run without job bookkeeping. ``record``: no lease (the sweep sends
    nothing), the run only marks the job ``done`` when it completes.
    """
    claim = alert_jobs.Claim(alert_jobs.NO_JOB)
    if mode == alert_jobs.MODE_ON:
        try:
            claim = alert_jobs.claim_job(car_id, now=now)
        except SQLAlchemyError as exc:
            db.session.rollback()
            logger.warning(
                "alert job table unavailable (%s); running the legacy path for car %s",
                type(exc).__name__,
                car_id,
            )
            return _notify_saved_searches_legacy(car_id)
        if claim.status == alert_jobs.NOT_OWNER:
            return {"matched": 0, "skipped": "job_finished_or_leased"}

    budget = alert_jobs.job_budget_seconds() if budget_seconds is None else budget_seconds
    deadline = monotonic() + budget
    try:
        result = _alert_pairs_claim_first(car_id, deadline=deadline, monotonic=monotonic)
    except Exception as exc:
        db.session.rollback()
        logger.exception("saved-search alert run crashed for car %s", car_id)
        result = {"matched": 0, "status": "partial_errors", "errors": 1, "error": type(exc).__name__}

    status = result["status"]
    try:
        if mode == alert_jobs.MODE_ON and claim.status == alert_jobs.CLAIMED:
            if status == "done":
                alert_jobs.finish_job(car_id, now=now)
            elif status == "not_public":
                alert_jobs.defer_job(
                    car_id, claim.token, delay_seconds=alert_jobs.NOT_PUBLIC_RECHECK_SECONDS,
                    count_attempt=False, now=now,
                )
            elif status == "partial_budget":
                alert_jobs.defer_job(
                    car_id, claim.token, delay_seconds=0, count_attempt=False, now=now
                )
            else:  # partial_errors: counted attempt, exponential back-off
                alert_jobs.defer_job(
                    car_id, claim.token,
                    delay_seconds=alert_jobs.backoff_seconds(claim.attempts),
                    count_attempt=True,
                    error=str(result.get("error") or "pair_error"),
                    now=now,
                )
        elif mode == alert_jobs.MODE_RECORD and status == "done":
            alert_jobs.finish_job(car_id, now=now)
    except SQLAlchemyError as exc:
        db.session.rollback()
        # Not fatal: the lease lapses and the job is redriven; pairs are de-duplicated.
        logger.warning("alert job state update failed for car %s: %s", car_id, type(exc).__name__)

    out = {"matched": result["matched"]}
    if status == "not_public":
        out["skipped"] = "inactive_or_missing"
    elif status != "done":
        out["incomplete"] = status
    return out


@celery_app.task(name="kk.tasks.alert_tasks.notify_price_drop_for_car")
def notify_price_drop_for_car(car_id: int, old_price: float, new_price: float) -> dict:
    if new_price >= old_price:
        return {"notified": 0, "skipped": "not_a_drop"}

    from ..listing_visibility import listing_is_public

    car = db.session.get(Car, car_id)
    if not car or not car.is_active or not listing_is_public(car):
        return {"notified": 0, "skipped": "inactive_or_missing"}

    rows = (
        db.session.query(user_favorites.c.user_id, user_favorites.c.price_at_favorite)
        .filter(user_favorites.c.car_id == car.id)
        .all()
    )
    notified = 0
    currency = (car.currency or "USD").upper()
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

        # MI-03: title is per-recipient (each favoriter may have a different
        # stored locale); the numeric/brand body stays locale-neutral.
        title = translate("price_drop_title", get_background_locale(getattr(user, "locale", None)))
        _send_retention_push(
            user,
            title=title,
            body=body[:200],
            notification_type="price_drop",
            data={"car_id": car.public_id, "old_price": str(old_price), "new_price": str(new_price)},
        )
        notified += 1

        try:
            # C-11: `new_price` is a plain float (Celery task args must stay
            # JSON-simple); convert via str() -> Decimal rather than binding
            # the raw float onto the Numeric(12, 2) column, to avoid a
            # float8->numeric assignment-cast round-trip.
            try:
                new_price_decimal = Decimal(str(new_price)).quantize(Decimal("0.01"))
            except InvalidOperation:
                new_price_decimal = Decimal(str(new_price))
            db.session.execute(
                sql_update(user_favorites)
                .where(
                    user_favorites.c.user_id == user_id,
                    user_favorites.c.car_id == car.id,
                )
                .values(price_at_favorite=new_price_decimal)
            )
            db.session.commit()
        except Exception:
            db.session.rollback()

    return {"notified": notified}
