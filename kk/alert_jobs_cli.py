"""Operator tooling for F-04 saved-search alert jobs (observe + recover).

``expired`` and ``failed`` jobs are terminal on purpose: the sweep never
revives them by itself (an alert that is days late is worse than none, and a
job that exhausted its attempts needs a human to look at why). They are never
silent -- the sweep logs every expiry/failure with the car ids and
``job_stats`` counts them -- and they are recoverable here, explicitly and
auditably:

    python -m kk.alert_jobs_cli stats
    python -m kk.alert_jobs_cli requeue                      # dry run (default)
    python -m kk.alert_jobs_cli requeue --apply              # failed + expired
    python -m kk.alert_jobs_cli requeue --outcome failed --car-id 123 --apply

``requeue`` resets a ``failed``/``expired`` job to *pending*: ``attempts`` back
to 0, lease cleared, and ``created_at`` restarted so it gets a fresh recovery
window (otherwise an expired job would be re-expired by the very next sweep
tick). It never touches ``done`` jobs and never creates jobs. Re-delivery is
safe: the ``(saved search, car)`` alert rows already committed de-duplicate, so
only pairs that were never claimed are pushed; the external push remains
at-least-once (a crash can still duplicate one push), never exactly-once.

Requeued jobs are only redriven by the sweep when
``SAVED_SEARCH_ALERT_DURABILITY=on``; the result reports the current mode.
Dry run is the default; ``--apply`` is required to write anything.
"""

from __future__ import annotations

import argparse
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


def requeue_terminal_jobs(
    *,
    outcomes: tuple[str, ...] = _TERMINAL,
    car_ids: list[int] | None = None,
    limit: int = 200,
    apply: bool = False,
    now: datetime | None = None,
) -> dict:
    """Reset ``failed``/``expired`` jobs to pending (see module docstring).

    Dry run unless ``apply``. Only rows whose outcome is still one of
    ``outcomes`` when the UPDATE runs are changed, so a concurrent requeue or
    sweep cannot be clobbered; ``done`` rows can never match.
    """
    bad = [o for o in outcomes if o not in _TERMINAL]
    if bad or not outcomes:
        raise ValueError(f"outcomes must be a non-empty subset of {_TERMINAL}, got {outcomes!r}")
    limit = max(1, min(int(limit), MAX_REQUEUE_LIMIT))
    now = jobs._clock(now)
    J = SavedSearchAlertJob

    q = select(J.id, J.car_id, J.outcome).where(J.outcome.in_(list(outcomes)))
    if car_ids:
        q = q.where(J.car_id.in_([int(c) for c in car_ids]))
    rows = db.session.execute(q.order_by(J.created_at, J.id).limit(limit)).all()
    ids = [int(r[0]) for r in rows]
    result = {
        "mode": jobs.durability_mode(),
        "applied": bool(apply),
        "candidates": len(ids),
        "car_ids": [int(r[1]) for r in rows][:100],
        "requeued": 0,
    }
    if not ids or not apply:
        db.session.rollback()
        return result

    res = db.session.execute(
        update(J)
        .where(J.id.in_(ids), J.outcome.in_(list(outcomes)))
        .values(
            finished_at=None,
            outcome=None,
            attempts=0,
            claimed_at=None,
            next_run_at=None,
            created_at=now,
            last_error=None,
        )
        .execution_options(synchronize_session=False)
    )
    db.session.commit()
    result["requeued"] = int(res.rowcount)
    logger.warning(
        "saved-search alert jobs REQUEUED by operator: count=%s outcomes=%s car_ids=%s",
        result["requeued"],
        ",".join(outcomes),
        result["car_ids"][:50],
    )
    return result


def main(argv: list[str] | None = None, *, app=None, out=None) -> int:
    parser = argparse.ArgumentParser(prog="python -m kk.alert_jobs_cli", description=__doc__.split("\n")[0])
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("stats", help="counts per state + age of the oldest owed job")
    rq = sub.add_parser("requeue", help="reset failed/expired jobs to pending (dry run unless --apply)")
    rq.add_argument("--outcome", choices=["failed", "expired", "both"], default="both")
    rq.add_argument("--car-id", type=int, action="append", help="limit to this car id (repeatable)")
    rq.add_argument("--limit", type=int, default=200, help=f"max jobs (<= {MAX_REQUEUE_LIMIT})")
    rq.add_argument("--apply", action="store_true", help="actually write (default: dry run)")
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
            payload = requeue_terminal_jobs(
                outcomes=outcomes, car_ids=args.car_id, limit=args.limit, apply=args.apply
            )
    out.write(json.dumps(payload, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
