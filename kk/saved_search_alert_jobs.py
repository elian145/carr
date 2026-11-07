"""F-04 durable saved-search alert delivery: the job state machine.

Why this exists
---------------
Saved-search alerts used to be fire-and-forget: ``dispatch_saved_search_alerts``
enqueues a Celery message AFTER the activating commit and swallows any enqueue
error (BE-12, deliberate). A broker outage, a web process dying between the
commit and the enqueue, a worker killed mid-task or a Redis flush therefore lost
the alert forever, with no record that it was owed.

What this adds (all of it behind the ``SAVED_SEARCH_ALERT_DURABILITY`` flag)
---------------------------------------------------------------------------
* ``SavedSearchAlertJob`` (``saved_search_alert_job``): one row per listing,
  ``UNIQUE(car_id)``, inserted in the SAME transaction as the activation
  (:func:`record_alert_job`). Redis/Celery only *transport* the work; the row
  is the durable intent.
* An atomic lease claim (:func:`claim_job`) so the fast-path task, a redriven
  task and any number of concurrent sweeps can never process the same job at
  the same time.
* A bounded sweep (:func:`reconcile`) run by beat: it expires jobs older than
  the recovery window, fails jobs whose attempts are exhausted, and re-enqueues
  due jobs as short per-job tasks (never inline loops).

Feature flag ``SAVED_SEARCH_ALERT_DURABILITY`` (read at call time, default off)
------------------------------------------------------------------------------
``off``     exactly the behaviour before this feature: no job rows, the alert
            task is the unchanged legacy implementation, the sweep returns
            immediately without touching the database.
``record``  job rows are written and the (claim-first) alert task marks them
            ``done``; the sweep only COUNTS/LOGS what it would redrive/expire
            and sends nothing. No sends beyond the existing fast path.
``on``      rows are written and the sweep redrives owed jobs (lease-claimed).
Any other value is treated as ``off`` (and logged once).

Which transitions are a "first publication" (the only ones that get a job)
--------------------------------------------------------------------------
A job is recorded only when ALL hold, evaluated inside the activating
transaction under the car row lock where the path has one:

1. the listing becomes public-active (``is_active`` and status ``active``)
   by ``pending -> active`` (admin single / bulk approve, automated
   moderation publish, admin override-approve, admin-privileged
   ``PUT /api/cars/<id>``) or is CREATED already public-active
   (``create_car`` with approval off); this is exactly
   ``retention_dispatch.is_new_publication_transition`` plus create;
2. no job row exists for the car (``UNIQUE(car_id)`` = the durable
   one-time marker; a job that finished, expired or failed still blocks a
   second one); and
3. no ``SavedSearchAlert`` row exists for the car (it was never alerted).

Never a first publication, so never a job and never an alert from this
feature: un-hide (``hidden -> active``), ``sold -> active`` (admin or seller
``mark-active`` / ``PUT status``), ``draft -> active``, price edits, approved
edits of an already-public listing (revision publish), repeated approvals of
an already-active listing, and ``active -> pending -> active`` for a car that
already has a job. Listings published before the feature have no job row and
there is NO backfill, so historic listings are never alerted retroactively
(that is the cut-over: the table starts empty and only post-flag
publications populate it). Residual (same as today's code, documented in the
notes): an admin who manually sets a PRE-feature published listing back to
``pending`` and approves it again hits the legacy ``pending -> active``
rule; pair de-duplication (``uq_saved_search_alert``) still prevents any
(search, car) pair from being alerted twice.

Delivery semantics (be precise: this is NOT exactly-once)
---------------------------------------------------------
The external push (FCM) is AT-LEAST-ONCE per (saved search, car) while the
pair is uncommitted: the alert task claims the pair FIRST (inserts the
``SavedSearchAlert`` row, flushed), then pushes, then commits the claim
together with the in-app ``Notification``. A crash after the push but before
that commit rolls the claim back, so a redrive pushes that one pair again:
duplicate pushes are BOUNDED (at most one extra per crashed attempt, and at
most ``MAX_ATTEMPTS`` attempts per job), and a push is never silently skipped
by a crash. The unique constraint guarantees at most one *committed* alert
row and at most one in-app ``Notification`` per pair. A push that FCM
rejects (``send_push`` returns ``False``) is not retried, exactly as before
(the in-app notification is still created); that is a best-effort external
channel, not a delivery guarantee.

Failure handling (summary; tests in ``kk/tests/test_f04_durable_*``)
--------------------------------------------------------------------
* broker down at enqueue / web dies after commit: the job row is already
  committed; the sweep redrives it once it is older than the grace period.
* DB rollback of the activating transaction: the job insert is part of it, so
  neither exists afterwards (no job without activation).
* concurrent workers/beats: ``UPDATE ... WHERE <lease free> RETURNING-less
  rowcount == 1`` conditional updates (precedent:
  ``notification_broadcast.py``). It works unchanged on SQLite (tests) and
  PostgreSQL (row-level lock; the second UPDATE re-evaluates the WHERE
  after the first commits and matches nothing). ``SELECT ... FOR UPDATE SKIP
  LOCKED`` was rejected: SQLite ignores it, so it could not be tested there.
* worker killed mid-dispatch: the lease (``LEASE_SECONDS``) expires, the
  sweep redrives; already-committed pairs are skipped.
* poison job: ``attempts`` is capped (``MAX_ATTEMPTS``, default 5); then the
  sweep marks it ``failed`` and logs an ERROR.
* Redis loss: state is in the DB; lost Celery messages are re-enqueued
  after the dispatch lease (``DISPATCH_VISIBILITY_SECONDS``) lapses.
* recovery window (default 72 h, ``SAVED_SEARCH_ALERT_MAX_AGE_HOURS``): jobs
  older than the window become ``expired`` (counted + WARNING), are never
  silently dropped and are never delivered after the window (the claim itself
  refuses jobs older than the window).
"""
from __future__ import annotations

import logging
import os
from datetime import datetime, timedelta
from typing import Callable, NamedTuple

from sqlalchemy import and_, case, func, or_, select, update
from sqlalchemy.exc import IntegrityError, SQLAlchemyError

from .models import SavedSearchAlert, SavedSearchAlertJob, db
from .time_utils import utcnow

logger = logging.getLogger(__name__)

FLAG_ENV = "SAVED_SEARCH_ALERT_DURABILITY"
MODE_OFF = "off"
MODE_RECORD = "record"
MODE_ON = "on"

OUTCOME_DONE = "done"
OUTCOME_EXPIRED = "expired"
OUTCOME_FAILED = "failed"

# claim_job() results
CLAIMED = "claimed"
NO_JOB = "no_job"
NOT_OWNER = "not_owner"  # finished, expired, failed, leased by someone else, or attempts exhausted

#: A message enqueued by the sweep is "in flight" for this long; if the job is
#: still not finished afterwards (message lost with Redis / worker) the sweep
#: enqueues it again. Also used as the message ``expires`` so two messages for
#: one job are never alive at the same time.
DISPATCH_VISIBILITY_SECONDS = 600
#: Re-check delay for a job whose listing is not public right now (hidden
#: again, seller deactivated): stays owed until the recovery window ends.
NOT_PUBLIC_RECHECK_SECONDS = 900
_ERROR_BACKOFF_BASE_SECONDS = 120
_ERROR_BACKOFF_MAX_SECONDS = 900
_HOUSEKEEPING_LIMIT = 200  # max rows expired/failed (and logged) per tick

_warned: set[str] = set()


def _warn_once(key: str, message: str, *args) -> None:
    if key in _warned:
        return
    _warned.add(key)
    logger.warning(message, *args)


# ---------------------------------------------------------------------------
# Configuration (all read at call time; defaults are the documented policy)
# ---------------------------------------------------------------------------


def durability_mode() -> str:
    raw = (os.environ.get(FLAG_ENV) or "").strip().lower()
    if raw in ("", MODE_OFF):
        return MODE_OFF
    if raw in (MODE_RECORD, MODE_ON):
        return raw
    _warn_once(
        "bad_flag",
        "%s=%r is not one of off/record/on; treating as off",
        FLAG_ENV,
        raw,
    )
    return MODE_OFF


def _env_number(name: str, default: float, minimum: float, maximum: float) -> float:
    raw = (os.environ.get(name) or "").strip()
    if not raw:
        return default
    try:
        value = float(raw)
    except ValueError:
        _warn_once("bad_" + name, "%s=%r is not a number; using %s", name, raw, default)
        return default
    return min(max(value, minimum), maximum)


def max_age() -> timedelta:
    """Recovery/expiry window (default 72 h)."""
    return timedelta(hours=_env_number("SAVED_SEARCH_ALERT_MAX_AGE_HOURS", 72.0, 0.01, 24 * 30))


def lease_seconds() -> int:
    return int(_env_number("SAVED_SEARCH_ALERT_LEASE_SECONDS", 900, 30, 6 * 3600))


def max_attempts() -> int:
    return int(_env_number("SAVED_SEARCH_ALERT_MAX_ATTEMPTS", 5, 1, 20))


def sweep_batch() -> int:
    return int(_env_number("SAVED_SEARCH_ALERT_SWEEP_BATCH", 10, 1, 50))


def sweep_grace_seconds() -> int:
    """How old a job must be before the sweep redrives it (the fast path gets
    this long to finish; it is a politeness delay, not a correctness window)."""
    return int(_env_number("SAVED_SEARCH_ALERT_SWEEP_GRACE_SECONDS", 180, 0, 3600))


def job_budget_seconds() -> int:
    """Wall-clock budget of ONE alert-task run over a car's saved searches;
    leftover searches are left to the next (redriven) run."""
    return int(_env_number("SAVED_SEARCH_ALERT_JOB_BUDGET_SECONDS", 120, 5, 600))


# ---------------------------------------------------------------------------
# Recording (inside the activating transaction)
# ---------------------------------------------------------------------------


def record_alert_job(car_id: int) -> bool:
    """Record "alerts owed" for a first publication; call BEFORE the commit
    that activates the listing, from every first-publication path.

    * ``off``: returns ``False`` immediately, touching nothing.
    * Joins the caller's transaction: nothing is committed here, so the row
      exists iff the activation commits (rollback removes both).
    * Idempotent: ``False`` when a job already exists for the car (the
      ``UNIQUE(car_id)`` marker) or the car was already alerted.
    * Runs in a SAVEPOINT so a missing table (code deployed before the
      migration), a race on the unique key or any other database error on the
      job insert degrades to "no job" (logged) instead of failing the
      activation or poisoning the surrounding transaction. In that degraded
      case the existing post-commit fast-path dispatch still happens.

    Returns ``True`` only when a new job row was added.
    """
    if durability_mode() == MODE_OFF:
        return False
    # Real activation errors must surface; only the job insert is guarded.
    db.session.flush()
    try:
        with db.session.begin_nested():
            if db.session.query(SavedSearchAlertJob.id).filter_by(car_id=car_id).first() is not None:
                return False
            if db.session.query(SavedSearchAlert.id).filter_by(car_id=car_id).first() is not None:
                return False
            db.session.add(SavedSearchAlertJob(car_id=car_id))
    except IntegrityError:
        # Concurrent recorder won the unique key; the marker exists either way.
        return False
    except SQLAlchemyError as exc:
        logger.error(
            "saved-search alert job could not be recorded for car %s (%s: %s); "
            "continuing without a durable marker (fast-path dispatch unaffected)",
            car_id,
            type(exc).__name__,
            exc,
        )
        return False
    return True


# ---------------------------------------------------------------------------
# Claim / settle (each is one short, atomic, committed UPDATE)
# ---------------------------------------------------------------------------


class Claim(NamedTuple):
    status: str  # CLAIMED | NO_JOB | NOT_OWNER
    token: datetime | None = None  # the lease start; fences defer_job()
    attempts: int = 0


def _clock(now: datetime | None) -> datetime:
    return now if now is not None else utcnow()


def _free_lease(now: datetime):
    return or_(
        SavedSearchAlertJob.claimed_at.is_(None),
        SavedSearchAlertJob.claimed_at < now - timedelta(seconds=lease_seconds()),
    )


def claim_job(car_id: int, *, now: datetime | None = None) -> Claim:
    """Atomically take the lease on the car's job.

    One conditional ``UPDATE`` (rowcount 1 = we own it). Refuses finished
    jobs, jobs with a live lease, jobs out of attempts and jobs older than the
    recovery window (those are expired by the sweep, never delivered late).
    Commits.
    """
    now = _clock(now)
    J = SavedSearchAlertJob
    res = db.session.execute(
        update(J)
        .where(
            J.car_id == car_id,
            J.finished_at.is_(None),
            J.attempts < max_attempts(),
            J.created_at >= now - max_age(),
            _free_lease(now),
        )
        .values(claimed_at=now, attempts=J.attempts + 1, last_error=None)
        .execution_options(synchronize_session=False)
    )
    db.session.commit()
    if res.rowcount == 1:
        attempts = db.session.execute(select(J.attempts).where(J.car_id == car_id)).scalar() or 0
        db.session.rollback()  # end the read transaction
        return Claim(CLAIMED, now, int(attempts))
    exists = db.session.query(J.id).filter_by(car_id=car_id).first() is not None
    db.session.rollback()
    return Claim(NOT_OWNER if exists else NO_JOB)


def finish_job(
    car_id: int, *, outcome: str = OUTCOME_DONE, now: datetime | None = None
) -> bool:
    """Mark the job terminal. Safe for any runner (a runner whose lease lapsed
    but which completed the work may still mark ``done``: pairs are
    de-duplicated, so finishing is idempotent). Never revives an expired job."""
    now = _clock(now)
    J = SavedSearchAlertJob
    res = db.session.execute(
        update(J)
        .where(J.car_id == car_id, J.finished_at.is_(None))
        .values(finished_at=now, outcome=outcome, claimed_at=None, next_run_at=None)
        .execution_options(synchronize_session=False)
    )
    db.session.commit()
    return res.rowcount == 1


def backoff_seconds(attempts: int) -> int:
    return int(min(_ERROR_BACKOFF_BASE_SECONDS * (2 ** max(attempts - 1, 0)), _ERROR_BACKOFF_MAX_SECONDS))


def defer_job(
    car_id: int,
    token: datetime | None,
    *,
    delay_seconds: float,
    count_attempt: bool,
    error: str | None = None,
    now: datetime | None = None,
) -> bool:
    """Release our lease and schedule the next try ``delay_seconds`` from now.

    Fenced by ``token`` (our lease start): a runner whose lease already lapsed
    and was re-claimed by someone else cannot release the new owner's lease.
    ``count_attempt=False`` hands back the attempt taken by ``claim_job`` (the
    run made no failed attempt: not public yet / time budget used up).
    """
    now = _clock(now)
    J = SavedSearchAlertJob
    values = {
        "claimed_at": None,
        "next_run_at": now + timedelta(seconds=delay_seconds),
        "last_error": error[:255] if error else None,
    }
    if not count_attempt:
        values["attempts"] = case((J.attempts > 0, J.attempts - 1), else_=0)
    res = db.session.execute(
        update(J)
        .where(J.car_id == car_id, J.finished_at.is_(None), J.claimed_at == token)
        .values(**values)
        .execution_options(synchronize_session=False)
    )
    db.session.commit()
    return res.rowcount == 1


# ---------------------------------------------------------------------------
# Sweep
# ---------------------------------------------------------------------------


def _due_filter(now: datetime):
    J = SavedSearchAlertJob
    return and_(
        J.finished_at.is_(None),
        J.attempts < max_attempts(),
        J.created_at <= now - timedelta(seconds=sweep_grace_seconds()),
        J.created_at >= now - max_age(),
        or_(J.next_run_at.is_(None), J.next_run_at <= now),
        _free_lease(now),
    )


def expire_overdue(now: datetime) -> tuple[int, list[int]]:
    """Pending jobs older than the recovery window -> ``expired`` (counted and
    logged by the caller; never delivered, never silently dropped)."""
    J = SavedSearchAlertJob
    cutoff = now - max_age()
    ids = [
        row[0]
        for row in db.session.execute(
            select(J.car_id)
            .where(J.finished_at.is_(None), J.created_at < cutoff)
            .order_by(J.created_at)
            .limit(_HOUSEKEEPING_LIMIT)
        )
    ]
    if not ids:
        db.session.rollback()
        return 0, []
    res = db.session.execute(
        update(J)
        .where(J.car_id.in_(ids), J.finished_at.is_(None), J.created_at < cutoff)
        .values(finished_at=now, outcome=OUTCOME_EXPIRED, claimed_at=None, next_run_at=None)
        .execution_options(synchronize_session=False)
    )
    db.session.commit()
    return int(res.rowcount), ids


def fail_exhausted(now: datetime) -> tuple[int, list[int]]:
    """Jobs out of attempts (and not being worked on) -> ``failed``."""
    J = SavedSearchAlertJob
    cond = and_(J.finished_at.is_(None), J.attempts >= max_attempts(), _free_lease(now))
    ids = [
        row[0]
        for row in db.session.execute(
            select(J.car_id).where(cond).order_by(J.created_at).limit(_HOUSEKEEPING_LIMIT)
        )
    ]
    if not ids:
        db.session.rollback()
        return 0, []
    res = db.session.execute(
        update(J)
        .where(J.car_id.in_(ids), cond)
        .values(finished_at=now, outcome=OUTCOME_FAILED, claimed_at=None, next_run_at=None)
        .execution_options(synchronize_session=False)
    )
    db.session.commit()
    return int(res.rowcount), ids


def select_due(now: datetime, limit: int) -> list[tuple[int, int]]:
    J = SavedSearchAlertJob
    rows = db.session.execute(
        select(J.id, J.car_id)
        .where(_due_filter(now))
        .order_by(J.created_at, J.id)
        .limit(limit)
    ).all()
    db.session.rollback()
    return [(int(r[0]), int(r[1])) for r in rows]


def lease_for_dispatch(job_id: int, now: datetime) -> datetime | None:
    """Atomically become THE sweep that enqueues this job for the next
    ``DISPATCH_VISIBILITY_SECONDS``. Two concurrent sweeps race on this one
    conditional UPDATE; exactly one gets rowcount 1."""
    J = SavedSearchAlertJob
    until = now + timedelta(seconds=DISPATCH_VISIBILITY_SECONDS)
    res = db.session.execute(
        update(J)
        .where(J.id == job_id, _due_filter(now))
        .values(next_run_at=until)
        .execution_options(synchronize_session=False)
    )
    db.session.commit()
    return until if res.rowcount == 1 else None


def _release_dispatch_lease(job_id: int, until: datetime) -> None:
    J = SavedSearchAlertJob
    db.session.execute(
        update(J)
        .where(J.id == job_id, J.finished_at.is_(None), J.next_run_at == until)
        .values(next_run_at=None)
        .execution_options(synchronize_session=False)
    )
    db.session.commit()


def job_stats(now: datetime | None = None) -> dict:
    """Operator view: counts per state and the age of the oldest owed job."""
    now = _clock(now)
    J = SavedSearchAlertJob
    out = {"pending": 0, "done": 0, "expired": 0, "failed": 0, "oldest_pending_age_s": None}
    for outcome, count in db.session.execute(
        select(J.outcome, func.count(J.id)).group_by(J.outcome)
    ):
        out["pending" if outcome is None else outcome] = int(count)
    oldest = db.session.execute(
        select(func.min(J.created_at)).where(J.finished_at.is_(None))
    ).scalar()
    db.session.rollback()
    if oldest is not None:
        out["oldest_pending_age_s"] = max(int((now - oldest).total_seconds()), 0)
    return out


def _count_would_do(now: datetime) -> dict:
    """``record`` mode: the read-only picture of what ``on`` would do."""
    J = SavedSearchAlertJob
    would_redrive = db.session.execute(
        select(func.count(J.id)).where(_due_filter(now))
    ).scalar()
    would_expire = db.session.execute(
        select(func.count(J.id)).where(J.finished_at.is_(None), J.created_at < now - max_age())
    ).scalar()
    db.session.rollback()
    return {"would_redrive": int(would_redrive or 0), "would_expire": int(would_expire or 0)}


def reconcile(
    now: datetime | None = None,
    *,
    enqueue: Callable[..., None],
) -> dict:
    """One bounded sweep tick (beat task ``kk.reconcile_saved_search_alerts``).

    Does only short DB statements plus at most ``sweep_batch()`` enqueues; the
    actual alerting happens in per-job tasks, so this never occupies the
    single-concurrency worker for long. ``enqueue(car_id, expires=<seconds>)``
    must publish the per-job task (injected so tests need no broker).
    """
    mode = durability_mode()
    stats: dict = {"mode": mode}
    if mode == MODE_OFF:
        return stats
    now = _clock(now)
    try:
        if mode == MODE_RECORD:
            stats.update(_count_would_do(now))
            if stats["would_redrive"] or stats["would_expire"]:
                logger.warning(
                    "saved-search alert sweep (record mode, sends nothing): "
                    "would_redrive=%s would_expire=%s",
                    stats["would_redrive"],
                    stats["would_expire"],
                )
            return stats

        expired, expired_ids = expire_overdue(now)
        failed, failed_ids = fail_exhausted(now)
        stats.update({"expired": expired, "failed": failed, "redriven": 0, "enqueue_failed": 0, "lease_lost": 0})
        if expired:
            logger.warning(
                "saved-search alert jobs EXPIRED unsent after %s: count=%s car_ids=%s",
                max_age(),
                expired,
                expired_ids[:50],
            )
        if failed:
            logger.error(
                "saved-search alert jobs FAILED (attempts exhausted): count=%s car_ids=%s",
                failed,
                failed_ids[:50],
            )
        for job_id, car_id in select_due(now, sweep_batch()):
            until = lease_for_dispatch(job_id, now)
            if until is None:
                stats["lease_lost"] += 1  # another sweep took it
                continue
            try:
                enqueue(car_id, expires=DISPATCH_VISIBILITY_SECONDS)
                stats["redriven"] += 1
            except Exception as exc:
                stats["enqueue_failed"] += 1
                logger.warning(
                    "saved-search alert redrive enqueue failed for car %s (%s); retry next tick",
                    car_id,
                    type(exc).__name__,
                )
                try:
                    _release_dispatch_lease(job_id, until)
                except SQLAlchemyError:
                    db.session.rollback()
        stats.update(job_stats(now))
        if stats["redriven"]:
            logger.info("saved-search alert sweep: %s", stats)
    except SQLAlchemyError as exc:
        db.session.rollback()
        stats["error"] = type(exc).__name__
        logger.warning(
            "saved-search alert sweep skipped: %s: %s (missing table before migration?)",
            type(exc).__name__,
            exc,
        )
    return stats
