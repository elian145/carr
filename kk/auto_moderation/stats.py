"""Approval counts, error rates and the shadow-mode comparison.

Everything is computed from the decision log, never assumed. The "gate" that
guards enabling live mode compares measured shadow results with thresholds an
administrator configured; it makes no claim about accuracy by itself.
"""

from __future__ import annotations

from collections import Counter, defaultdict
from datetime import timedelta
from typing import Any

from ..models import ListingModerationEvent, ListingModerationRun, db
from ..time_utils import utcnow
from .outcomes import NEGATIVE_OUTCOMES

_SERVICE_FAILURE_CODES = ("ai_unavailable", "engine_error")
_ROW_CAP = 20000


def _rate(n: int, d: int) -> float | None:
    return round(n / d, 4) if d else None


def _window(days: int):
    return utcnow() - timedelta(days=max(1, int(days)))


def summary(days: int = 30) -> dict[str, Any]:
    since = _window(days)
    rows = (
        db.session.query(
            ListingModerationRun.created_at,
            ListingModerationRun.mode,
            ListingModerationRun.subject_type,
            ListingModerationRun.status,
            ListingModerationRun.decision,
            ListingModerationRun.outcome,
            ListingModerationRun.reasons,
            ListingModerationRun.ai,
            ListingModerationRun.admin_outcome,
        )
        .filter(ListingModerationRun.created_at >= since)
        .limit(_ROW_CAP)
        .all()
    )
    by_mode_decision: Counter = Counter()
    by_outcome: Counter = Counter()
    by_type: Counter = Counter()
    daily: dict[str, Counter] = defaultdict(Counter)
    failed = 0
    evaluated = 0
    ai_calls = ai_unavailable = 0
    latency_total = latency_n = 0
    published = reversals = 0
    for r in rows:
        if r.status == "stale":
            by_outcome["stale"] += 1
            continue
        evaluated += 1
        by_mode_decision[f"{r.mode}:{r.decision or 'none'}"] += 1
        by_outcome[r.outcome or "none"] += 1
        by_type[r.subject_type] += 1
        day = r.created_at.date().isoformat() if r.created_at else "unknown"
        daily[day][r.decision or "none"] += 1
        codes = {x.get("code") for x in (r.reasons or []) if isinstance(x, dict)}
        if r.status == "error" or codes & set(_SERVICE_FAILURE_CODES):
            failed += 1
        ai = r.ai or {}
        if ai.get("status") in ("ok", "flagged", "uncertain", "unavailable"):
            ai_calls += 1
            if ai["status"] == "unavailable":
                ai_unavailable += 1
            if ai.get("latency_ms") is not None:
                latency_total += ai["latency_ms"]
                latency_n += 1
        if r.outcome == "published":
            published += 1
            if r.admin_outcome in NEGATIVE_OUTCOMES:
                reversals += 1

    def ev(kind: str) -> int:
        return ListingModerationEvent.query.filter(
            ListingModerationEvent.event_type == kind,
            ListingModerationEvent.created_at >= since,
        ).count()

    return {
        "days": days,
        "evaluated": evaluated,
        "by_mode_decision": dict(by_mode_decision),
        "by_outcome": dict(by_outcome),
        "by_subject_type": dict(by_type),
        "auto_approved": published,
        "post_approval_reversals": reversals,
        "post_approval_reversal_rate": _rate(reversals, published),
        "failed_evaluations": failed,
        "error_rate": _rate(failed, evaluated),
        "apply_refusals": ev("apply_refused") + ev("downgraded_at_apply"),
        "stale_discards": ev("stale_result_discarded"),
        "alerts_sent": ev("alert_sent"),
        "ai": {
            "calls": ai_calls,
            "unavailable": ai_unavailable,
            "unavailable_rate": _rate(ai_unavailable, ai_calls),
            "avg_latency_ms": int(latency_total / latency_n) if latency_n else None,
        },
        "daily": [{"day": d, **dict(c)} for d, c in sorted(daily.items())],
        "truncated": len(rows) >= _ROW_CAP,
    }


def shadow_report(settings: dict, days: int | None = None) -> dict[str, Any]:
    """Compare what shadow mode WOULD have done with what a human actually did.

    ``unsafe approval``: shadow said AUTO_APPROVE, a human rejected / hid /
    deleted the subject. ``over-flagged``: shadow asked for a human (or held),
    the human approved as-is -- costs admin time, not safety.
    """
    gate = settings.get("gate") or {}
    days = int(days or gate.get("window_days", 90))
    since = _window(days)
    rows = (
        db.session.query(ListingModerationRun.decision, ListingModerationRun.admin_outcome)
        .filter(
            ListingModerationRun.mode == "shadow",
            ListingModerationRun.status == "completed",
            ListingModerationRun.created_at >= since,
        )
        .limit(_ROW_CAP)
        .all()
    )
    pending = sum(1 for r in rows if r.admin_outcome is None)
    matrix: dict[str, Counter] = {d: Counter() for d in ("AUTO_APPROVE", "NEEDS_REVIEW", "HOLD")}
    for r in rows:
        if r.admin_outcome is None or r.decision not in matrix:
            continue
        key = "approved" if r.admin_outcome == "approved" else "rejected"
        matrix[r.decision][key] += 1
    compared = sum(sum(c.values()) for c in matrix.values())
    would_approve = sum(matrix["AUTO_APPROVE"].values())
    unsafe = matrix["AUTO_APPROVE"]["rejected"]
    flagged_total = sum(matrix["NEEDS_REVIEW"].values()) + sum(matrix["HOLD"].values())
    over_flagged = matrix["NEEDS_REVIEW"]["approved"] + matrix["HOLD"]["approved"]
    agree = matrix["AUTO_APPROVE"]["approved"] + matrix["NEEDS_REVIEW"]["rejected"] + matrix["HOLD"]["rejected"]

    min_samples = int(gate.get("min_samples", 100))
    max_unsafe = float(gate.get("max_unsafe_approve_rate", 0.02))
    unsafe_rate = _rate(unsafe, would_approve)
    problems: list[str] = []
    if would_approve < min_samples:
        problems.append(
            f"only {would_approve} shadow auto-approve decisions have a human outcome "
            f"(configured minimum {min_samples})"
        )
    elif unsafe_rate is not None and unsafe_rate > max_unsafe:
        problems.append(
            f"unsafe-approval rate {unsafe_rate:.2%} exceeds the configured maximum {max_unsafe:.2%}"
        )
    return {
        "window_days": days,
        "compared": compared,
        "awaiting_human_outcome": pending,
        "matrix": {d: dict(c) for d, c in matrix.items()},
        "would_auto_approve": would_approve,
        "unsafe_approvals": unsafe,
        "unsafe_approve_rate": unsafe_rate,
        "over_flagged": over_flagged,
        "over_flag_rate": _rate(over_flagged, flagged_total),
        "agreement_rate": _rate(agree, compared),
        "automation_coverage": _rate(would_approve, compared),
        "gate": {
            "min_samples": min_samples,
            "max_unsafe_approve_rate": max_unsafe,
            "passed": not problems,
            "problems": problems,
        },
    }
