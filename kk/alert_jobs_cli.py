"""Operator tooling for F-04 saved-search alert jobs (observe + recover).

``expired`` and ``failed`` jobs are terminal on purpose: the sweep never
revives them by itself (an alert that is days late is worse than none, and a
job that exhausted its attempts needs a human to look at why). They are never
silent -- the sweep logs every expiry/failure with the car ids and
``job_stats`` counts them -- and they are recoverable here, explicitly and
auditably:

    python -m kk.alert_jobs_cli stats                         # read-only
    python -m kk.alert_jobs_cli requeue                       # dry run (default)
    python -m kk.alert_jobs_cli requeue --apply --reason "FCM outage 2026-11-06"
    python -m kk.alert_jobs_cli requeue --outcome failed --car-id 123 --apply --reason "..."

What ``requeue`` does (and does not do)
---------------------------------------
* Only UPDATEs existing ``failed``/``expired`` rows back to *pending*
  (``attempts`` 0, lease cleared, ``created_at`` = now). It never INSERTs, so
  it can never create a second job for a listing (``UNIQUE(car_id)``), however
  often it is run. ``done`` and already-pending jobs can never match.
* Manual recovery policy (explicit, differs from the automatic one on purpose):
  the automatic sweep never delivers anything older than the recovery window
  (``SAVED_SEARCH_ALERT_MAX_AGE_HOURS``, default 72 h). A manual requeue is a
  deliberate operator decision that restarts a fresh window from *now*, so an
  old listing's owed first-publication alert can still be sent. The dry run
  prints the age of every candidate so the operator sees what they are
  reviving. The automatic 72 h policy itself is unchanged.
* Requeued jobs go through exactly the same processing as automatic ones, so
  nothing is bypassed: the listing must be active and publicly visible
  (otherwise the job is deferred and re-checked, not sent), only saved searches
  with ``notify`` on, not the seller's own, whose filters match and whose
  account is active are alerted, and ``(saved search, car)`` pairs that were
  already alerted are skipped. No job is created for a listing that was never
  a first publication.
* The ``SAVED_SEARCH_ALERT_DURABILITY`` flag is respected: ``--apply`` is
  refused while it is ``off``; in ``record`` the rows are reset but the sweep
  only counts; only ``on`` redrives them.
* Audit: ``--apply`` requires ``--reason``; every requeued job gets one
  WARNING log line (car id, previous outcome and attempts, operator, reason,
  UTC time) plus a marker in the row's ``last_error`` (kept until the next
  claim clears it). The log line is the audit record; there is no dedicated
  audit table (that would need a schema change).
* External push delivery stays at-least-once, NEVER exactly-once: a crash
  between push and commit makes the redrive push that pair again, and repeated
  crashes can repeat it, bounded by the per-job attempt budget (not proven to
  be a single duplicate).

Dry run is the default; ``--apply`` is required to write anything.
"""

from __future__ import annotations

import argparse
import getpass
import json
import logging
import sys
from datetime import datetime

from sqlalchemy import select, update

from . import saved_search_alert_jobs as jobs
from .models import SavedSearchAlertJob, db

logger = logging.getLogger(__name__)

_TERMINAL = (jobs.OUTCOME_FAILED, jobs.OUTCOME_EXPIRED)
MAX_REQUEUE_LIMIT = 1000


class RequeueRefused(RuntimeError):
    """``--apply`` was refused (flag off / missing reason); nothing was written."""


def _operator() -> str:
    try:
        return getpass.getuser()
    except Exception:  # pragma: no cover - no passwd entry in some containers
        return "unknown"


def requeue_terminal_jobs(
    *,
    outcomes: tuple[str, ...] = _TERMINAL,
    car_ids: list[int] | None = None,
    limit: int = 200,
    apply: bool = False,
    reason: str | None = None,
    operator: str | None = None,
    now: datetime | None = None,
) -> dict:
    """Reset ``failed``/``expired`` jobs to pending (see module docstring).

    Dry run unless ``apply``. Each row is updated with a guard on its current
    outcome, so a concurrent requeue or sweep can never be clobbered and two
    simultaneous applies requeue each job exactly once between them; ``done``
    rows can never match.
    """
    bad = [o for o in outcomes if o not in _TERMINAL]
    if bad or not outcomes:
        raise ValueError(f"outcomes must be a non-empty subset of {_TERMINAL}, got {outcomes!r}")
    limit = max(1, min(int(limit), MAX_REQUEUE_LIMIT))
    now = jobs._clock(now)
    mode = jobs.durability_mode()
    reason = (reason or "").strip()
    if apply:
        if mode == jobs.MODE_OFF:
            raise RequeueRefused(
                f"{jobs.FLAG_ENV} is 'off': refusing to requeue (nothing would redrive them). "
                "Set it to 'record' or 'on' first."
            )
        if not reason:
            raise RequeueRefused("--apply requires --reason (it is written to the audit log)")
    operator = (operator or _operator()).strip() or "unknown"
    J = SavedSearchAlertJob

    q = select(J.id, J.car_id, J.outcome, J.attempts, J.created_at).where(J.outcome.in_(list(outcomes)))
    if car_ids:
        q = q.where(J.car_id.in_([int(c) for c in car_ids]))
    rows = db.session.execute(q.order_by(J.created_at, J.id).limit(limit)).all()
    result = {
        "mode": mode,
        "applied": bool(apply),
        "candidates": len(rows),
        "requeued": 0,
        "jobs": [
            {
                "car_id": int(r.car_id),
                "outcome": r.outcome,
                "attempts": int(r.attempts or 0),
                "age_hours": round(max((now - r.created_at).total_seconds(), 0) / 3600, 1),
            }
            for r in rows[:100]
        ],
    }
    if not rows or not apply:
        db.session.rollback()
        return result

    requeued: list[tuple[int, str, int]] = []
    for r in rows:
        marker = (
            f"requeued {now.isoformat(timespec='seconds')}Z by {operator} "
            f"(was {r.outcome}, attempts {int(r.attempts or 0)}): {reason}"
        )[:255]
        res = db.session.execute(
            update(J)
            .where(J.id == r.id, J.outcome == r.outcome)
            .values(
                finished_at=None,
                outcome=None,
                attempts=0,
                claimed_at=None,
                next_run_at=None,
                created_at=now,
                last_error=marker,
            )
            .execution_options(synchronize_session=False)
        )
        if res.rowcount == 1:
            requeued.append((int(r.car_id), r.outcome, int(r.attempts or 0)))
    db.session.commit()
    result["requeued"] = len(requeued)
    for car_id, was, attempts in requeued:
        logger.warning(
            "AUDIT saved-search alert job REQUEUED by operator: car_id=%s was=%s attempts=%s "
            "operator=%s reason=%r at=%sZ",
            car_id,
            was,
            attempts,
            operator,
            reason,
            now.isoformat(timespec="seconds"),
        )
    return result


def main(argv: list[str] | None = None, *, app=None, out=None) -> int:
    parser = argparse.ArgumentParser(prog="python -m kk.alert_jobs_cli", description=__doc__.split("\n")[0])
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("stats", help="read-only: counts per state + age of the oldest owed job")
    rq = sub.add_parser("requeue", help="reset failed/expired jobs to pending (dry run unless --apply)")
    rq.add_argument("--outcome", choices=["failed", "expired", "both"], default="both")
    rq.add_argument("--car-id", type=int, action="append", help="limit to this car id (repeatable)")
    rq.add_argument("--limit", type=int, default=200, help=f"max jobs (<= {MAX_REQUEUE_LIMIT})")
    rq.add_argument("--apply", action="store_true", help="actually write (default: dry run)")
    rq.add_argument("--reason", help="required with --apply; recorded in the audit log")
    args = parser.parse_args(argv)
    out = out or sys.stdout

    if app is None:
        from .app_factory import create_app

        app = create_app()[0]
    with app.app_context():
        if args.cmd == "stats":
            payload = {"mode": jobs.durability_mode(), **jobs.job_stats()}
        else:
            outcomes = _TERMINAL if args.outcome == "both" else (args.outcome,)
            try:
                payload = requeue_terminal_jobs(
                    outcomes=outcomes,
                    car_ids=args.car_id,
                    limit=args.limit,
                    apply=args.apply,
                    reason=args.reason,
                )
            except RequeueRefused as exc:
                out.write(json.dumps({"error": str(exc), "applied": False}, sort_keys=True) + "\n")
                return 2
    out.write(json.dumps(payload, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
