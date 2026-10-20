"""The moderation pipeline: claim -> evaluate -> record -> (live only) apply.

Safety properties, and where they are enforced
----------------------------------------------
Idempotent jobs
    ``(subject_key, content_token, mode)`` is unique. ``_claim`` inserts the
    row (or compare-and-swaps ``attempts`` to take over a failed / expired
    one); a duplicate or re-delivered job finds the row and returns
    ``done`` / ``busy`` instead of deciding again.
No locks across slow work
    Rules read, the AI call runs with NO row locks held. Afterwards the
    subject is locked (``car`` -> ``revision`` -> working copy, the order
    ``listing_revisions`` already uses), the content token is recomputed and
    compared -- if the seller changed anything meanwhile the result is
    discarded as stale and the new content is re-evaluated.
Never approve on failure
    Any exception / AI outage / timeout records HOLD (``engine_error`` /
    ``ai_unavailable``) with a retry schedule. Only an explicit, fully
    successful AUTO_APPROVE decision in ``live`` mode reaches ``_apply``.
Apply is re-validated under locks
    ``_apply`` re-checks mode + kill switch (fresh), decision age, eligibility
    (still pending, not deleted), token, and re-runs every deterministic rule
    (seller, duplicates, media, cover, payment) before publishing. Publication
    itself reuses the manual mechanisms: the same ``Car`` activation + media
    readiness gate + seller notification as ``PATCH /api/admin/cars/<id>/status``,
    and ``listing_revisions.publish_revision`` (with the reviewed content
    token) for edits -- atomic, keeps the previous version until then.
No double approval
    ``applied_at`` / ``outcome == 'pending_apply'`` are checked under the run
    row lock; a second apply is a no-op. A human acting first makes the
    subject non-pending, so automation finds nothing to publish.
There is no reject path.
"""

from __future__ import annotations

import logging
from datetime import timedelta

from sqlalchemy import update
from sqlalchemy.exc import IntegrityError

from .. import listing_revisions as lr
from ..models import ListingModerationEvent, ListingModerationRun, db
from ..time_utils import utcnow
from . import ENGINE_VERSION
from . import ai as ai_mod
from .config import effective_mode, kill_switch_active, load_settings
from .rules import (
    CHECK_NAMES,
    HOLD,
    INFO,
    REVIEW,
    Signal,
    ai_signals,
    checks_map,
    decide,
    run_rules,
)
from .subjects import Ineligible, Subject, build_facts, ai_inputs, resolve_subject

logger = logging.getLogger(__name__)

AUTO_REVIEWER = "auto-moderation"
CLAIM_TTL_SECONDS = 600
#: Recorded outcomes an administrator's "re-run" may re-judge after the rules
#: changed. Published / pending-apply / superseded decisions are never touched.
_REEVALUATE_OUTCOMES = frozenset({"queued_for_review", "shadow_would_approve", "downgraded"})
RETRYABLE_HOLD_CODES = frozenset(
    {"ai_unavailable", "engine_error", "decision_expired", "payment_check_unavailable"}
)


# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------


def log_event(run: ListingModerationRun | None, event_type: str, *, actor: str = "system", data=None, car_id=None, car_public_id=None) -> None:
    db.session.add(
        ListingModerationEvent(
            run_id=run.id if run is not None else None,
            car_id=run.car_id if run is not None else car_id,
            car_public_id=run.car_public_id if run is not None else car_public_id,
            event_type=event_type,
            actor=actor,
            data=data,
        )
    )


def _lock_run(run_id: int) -> ListingModerationRun | None:
    return (
        ListingModerationRun.query.filter_by(id=run_id)
        .with_for_update()
        .populate_existing()
        .one_or_none()
    )


def _lock_subject(subject_type: str, subject_id: int) -> None:
    """Take the same locks, in the same order, as the manual paths."""
    if subject_type == "listing":
        if lr._lock_car_row(subject_id) is None:
            raise Ineligible("not_found")
        return
    try:
        lr._load_locked_for_review(subject_id)
    except lr.RevisionError as e:
        raise Ineligible(e.code)


def _backoff(settings: dict, attempts: int) -> int | None:
    retry = settings.get("retry") or {}
    if attempts >= int(retry.get("max_attempts", 5)):
        return None
    steps = retry.get("backoff_seconds") or [60]
    return int(steps[min(max(attempts - 1, 0), len(steps) - 1)])


def _subject_id(subject: Subject) -> int:
    return subject.revision.id if subject.type == "revision" else subject.car.id


def _finish(
    run_id: int,
    attempts: int,
    *,
    status: str | None = None,
    outcome: str | None = None,
    decision: str | None = None,
    reasons: list | None = None,
    next_retry_in: int | None = None,
    error: str | None = None,
    event: str | None = None,
    event_data: dict | None = None,
) -> bool:
    """Fresh transaction: update a run we still own. False when someone else
    took the run over (our attempt counter no longer matches)."""
    db.session.rollback()
    run = _lock_run(run_id)
    if run is None or run.attempts != attempts:
        db.session.rollback()
        return False
    if status:
        run.status = status
    if outcome:
        run.outcome = outcome
    if decision:
        run.decision = decision
        run.decided_at = utcnow()
    if reasons is not None:
        run.reasons = reasons
    run.next_retry_at = (utcnow() + timedelta(seconds=next_retry_in)) if next_retry_in else None
    if error is not None:
        run.error = error[:500]
    if event:
        log_event(run, event, data=event_data)
    db.session.commit()
    return True


# ---------------------------------------------------------------------------
# Claim (idempotency)
# ---------------------------------------------------------------------------


def _claim(subject: Subject, mode: str, settings: dict, trigger: str):
    """Returns ``(run, state)``; state is one of
    ``new`` | ``retry`` | ``resume_apply`` | ``done`` | ``busy`` | ``backoff``."""
    now = utcnow()
    existing = ListingModerationRun.query.filter_by(
        subject_key=subject.key, content_token=subject.token, mode=mode
    ).first()
    if existing is None:
        run = ListingModerationRun(
            subject_key=subject.key,
            subject_type=subject.type,
            car_id=subject.car.id,
            car_public_id=subject.car.public_id,
            revision_id=subject.revision.id if subject.revision is not None else None,
            revision_public_id=subject.revision.public_id if subject.revision is not None else None,
            seller_id=subject.car.seller_id,
            content_token=subject.token,
            mode=mode,
            status="evaluating",
            attempts=1,
            claimed_at=now,
            engine_version=ENGINE_VERSION,
        )
        db.session.add(run)
        try:
            db.session.flush()
            log_event(run, "claimed", data={"trigger": trigger, "attempt": 1, "mode": mode})
            db.session.commit()
            return run, "new"
        except IntegrityError:
            db.session.rollback()
            existing = ListingModerationRun.query.filter_by(
                subject_key=subject.key, content_token=subject.token, mode=mode
            ).first()
            if existing is None:
                return None, "busy"

    if existing.status == "completed" and existing.decision != "HOLD":
        if (
            existing.outcome == "pending_apply"
            and mode == "live"
            and existing.applied_at is None
        ):
            return existing, "resume_apply"
        if not (
            # An administrator explicitly asked for a fresh look at content whose
            # recorded decision was made by an OLDER rule set (e.g. before the
            # consistency checks existed): judge it again. Never for automatic
            # triggers (events, sweep, retries stay idempotent), never once the
            # decision was applied, and only until it carries the current version.
            trigger == "manual"
            and existing.applied_at is None
            and existing.outcome in _REEVALUATE_OUTCOMES
            and (existing.engine_version or "") != ENGINE_VERSION
        ):
            existing.updated_at = now  # lets the sweep see it is current
            db.session.commit()
            return existing, "done"

    if existing.status == "evaluating" and existing.claimed_at and (
        now - existing.claimed_at
    ) < timedelta(seconds=CLAIM_TTL_SECONDS):
        return existing, "busy"

    if existing.status == "completed" and existing.decision == "HOLD" and trigger != "manual":
        if existing.next_retry_at is None:
            return existing, "done"  # non-retryable HOLD for this exact content
        if existing.next_retry_at > now:
            return existing, "backoff"

    old_attempts = existing.attempts
    res = db.session.execute(
        update(ListingModerationRun)
        .where(
            ListingModerationRun.id == existing.id,
            ListingModerationRun.attempts == old_attempts,
            ListingModerationRun.status == existing.status,
        )
        .values(
            status="evaluating",
            claimed_at=now,
            attempts=old_attempts + 1,
            next_retry_at=None,
            updated_at=now,
            error=None,
            engine_version=ENGINE_VERSION,
        )
    )
    if res.rowcount != 1:
        db.session.rollback()
        return existing, "busy"
    db.session.commit()
    db.session.refresh(existing)
    log_event(existing, "claimed", data={"trigger": trigger, "attempt": existing.attempts, "mode": mode})
    db.session.commit()
    return existing, "retry"


# ---------------------------------------------------------------------------
# Evaluate (no locks held)
# ---------------------------------------------------------------------------


def _reusable_ai(
    subject: Subject, fingerprint: str | None, urls: list[str], cover_needed: bool
) -> dict | None:
    """A definitive (``ok`` / ``flagged``) provider answer already recorded for
    THIS subject about exactly the same question (same text, same ordered photo
    set, same provider / model / prompt / batching: see ``ai.input_fingerprint``).

    Content tokens also change for things the provider never sees (a cover
    crop, a video, a media item changing state),
    and a re-check after a late media change must not pay for the same answer
    twice. ``uncertain`` / ``unavailable`` / ``disabled`` are never reused, so a
    retry still asks the provider. The reused result is judged by the CURRENT
    settings and re-verified against the content at apply time exactly like a
    fresh one."""
    if not fingerprint:
        return None
    prior = (
        ListingModerationRun.query.filter(
            ListingModerationRun.subject_key == subject.key,
            ListingModerationRun.content_token != subject.token,
            ListingModerationRun.status == "completed",
        )
        .order_by(ListingModerationRun.id.desc())
        .limit(10)
        .all()
    )
    expected = len(dict.fromkeys(u for u in urls if isinstance(u, str) and u))
    for r in prior:
        stored = r.ai if isinstance(r.ai, dict) else {}
        if stored.get("input_hash") == fingerprint and stored.get("status") in ("ok", "flagged"):
            # Belt and braces: the fingerprint already pins the photo set, but a
            # stored answer is only ever reused if it covered EVERY photo (and the
            # cover when it was due) -- never a partial inspection.
            if (
                stored.get("images_expected") != expected
                or stored.get("images_checked") != expected
                or (bool(stored.get("cover_expected")) and not stored.get("cover_checked"))
                or bool(stored.get("cover_expected")) != bool(cover_needed and expected)
            ):
                continue
            reused = dict(stored)
            reused["reused_from_run"] = r.public_id
            reused["calls"] = 0
            return reused
    return None


def evaluate(subject: Subject, settings: dict) -> tuple[list[Signal], dict, dict]:
    facts = build_facts(subject, settings)
    signals = run_rules(facts, settings, utcnow().year)
    title, description, urls, needed, cover_needed = ai_inputs(subject, facts)
    candidate = not any(s.level in (HOLD, REVIEW) for s in signals)
    ai_cfg = settings.get("ai") or {}
    if not needed:
        ai = {"status": "not_needed"}
    elif candidate or not ai_cfg.get("only_if_candidate", True):
        fingerprint = ai_mod.input_fingerprint(
            title=title, description=description, image_urls=urls, settings=settings, cover_needed=cover_needed
        )
        ai = _reusable_ai(subject, fingerprint, urls, cover_needed)
        if ai is None:
            ai = ai_mod.moderate(
                title=title, description=description, image_urls=urls, settings=settings, cover_needed=cover_needed
            )
            if fingerprint and ai.get("status") in ("ok", "flagged"):
                ai["input_hash"] = fingerprint
    else:
        # Intentional (``ai.only_if_candidate``): a listing the rules already
        # send to a human costs no AI call. Say so plainly in the record, so
        # nobody reads "no AI flag" as "the photos were looked at and are fine".
        ai = {
            "status": "skipped",
            "reason": "rules_already_flag",
            "images_inspected": False,
            "images_expected": len(urls),
            "images_checked": 0,
            "calls": 0,
        }
    if ai["status"] != "skipped":
        signals += ai_signals(ai, settings)
    else:
        # INFO never blocks and never approves: it is recorded for the reviewer
        # (the decision is already NEEDS_REVIEW/HOLD because of the rule above).
        signals.append(
            Signal(
                "ai_images_not_inspected",
                INFO,
                "ai",
                False,
                f"AI skipped, rules already flag: 0/{len(urls)} photos inspected",
            )
        )
    ran = tuple(
        n
        for n in CHECK_NAMES
        if (n != "ai" or ai["status"] in ("ok", "not_needed"))
        and (n != "revision" or subject.type == "revision")
    )
    return signals, ai, checks_map(signals, ran)


# ---------------------------------------------------------------------------
# Record the decision
# ---------------------------------------------------------------------------


def _record_error(run_id: int, attempts: int, exc: Exception, settings: dict) -> dict:
    logger.warning("auto-moderation evaluation failed (run %s): %s", run_id, type(exc).__name__)
    retry_in = _backoff(settings, attempts)
    ok = _finish(
        run_id,
        attempts,
        status="error",
        outcome="error",
        decision="HOLD",
        reasons=[Signal("engine_error", HOLD, "engine", False, type(exc).__name__).to_dict()],
        next_retry_in=retry_in,
        error=f"{type(exc).__name__}: {exc}",
        event="error",
        event_data={"error": type(exc).__name__, "retry_in": retry_in},
    )
    return {"outcome": "error", "retry_in": retry_in if ok else None}


def _record_decision(run_id, attempts, subject, signals, ai, checks, settings, mode) -> dict:
    sid = _subject_id(subject)
    db.session.rollback()  # drop everything read during evaluation; lock fresh
    try:
        _lock_subject(subject.type, sid)
        fresh = resolve_subject(subject.type, sid)
    except Ineligible as e:
        db.session.rollback()
        _finish(run_id, attempts, status="stale", outcome="superseded",
                event="superseded", event_data={"code": e.code, "stage": "record"})
        return {"outcome": "superseded", "code": e.code}

    run = _lock_run(run_id)
    if run is None or run.attempts != attempts or run.status != "evaluating":
        db.session.rollback()
        return {"outcome": "busy"}

    if fresh.token != run.content_token:
        # The seller changed the listing / pending edit while we were
        # evaluating: this verdict is about content that no longer exists.
        run.status = "stale"
        run.outcome = "stale"
        run.next_retry_at = None
        log_event(run, "stale_result_discarded", data={"stage": "record"})
        db.session.commit()
        return {"outcome": "stale", "reenqueue": True}

    decision = decide(signals)
    reasons = [s.to_dict() for s in signals]
    run.decision = decision
    run.reasons = reasons
    run.checks = checks
    run.ai = ai
    run.decided_at = utcnow()
    run.status = "completed"
    run.error = None
    retry_in = None
    if decision == "AUTO_APPROVE":
        if mode != "live":
            run.outcome = "shadow_would_approve"
        elif (subject.type == "listing" and not settings.get("auto_approve_new_listings", True)) or (
            subject.type == "revision" and not settings.get("auto_approve_revisions", True)
        ):
            run.outcome = "queued_for_review"
            log_event(run, "auto_approve_disabled_for_subject_type", data={"type": subject.type})
        else:
            run.outcome = "pending_apply"
    elif decision == "NEEDS_REVIEW":
        run.outcome = "queued_for_review"
    else:
        run.outcome = "held"
        if any(s.code in RETRYABLE_HOLD_CODES for s in signals if s.level == HOLD):
            retry_in = _backoff(settings, attempts)
            if retry_in is None:
                log_event(run, "retries_exhausted", data={"attempts": attempts})
    run.next_retry_at = utcnow() + timedelta(seconds=retry_in) if retry_in else None
    log_event(
        run,
        "decision",
        data={
            "decision": decision,
            "mode": mode,
            "outcome": run.outcome,
            "reason_codes": [s.code for s in signals if s.level in (HOLD, REVIEW)],
            "ai_status": ai.get("status"),
            "attempt": attempts,
        },
    )
    db.session.commit()
    return {
        "outcome": run.outcome,
        "decision": decision,
        "retry_in": retry_in,
        "run_id": run.id,
        "alert": decision == "NEEDS_REVIEW"
        or (decision == "HOLD" and any(s.code == "media_failed" for s in signals)),
    }


# ---------------------------------------------------------------------------
# Apply (live mode only)
# ---------------------------------------------------------------------------


class PublishResult:
    def __init__(self, car, notification, seller, removed_urls=(), old_price=None, new_price=None, changed_fields=()):
        self.car = car
        self.notification = notification
        self.seller = seller
        self.removed_urls = list(removed_urls)
        self.old_price = old_price
        self.new_price = new_price
        self.changed_fields = list(changed_fields)
        self.car_public_id = car.public_id or str(car.id)


def publish_subject(subject: Subject, *, reviewer: str) -> PublishResult:
    """Publish through the SAME mechanisms as manual approval. Does not commit.
    Caller already holds the subject's locks. Raises ``lr.RevisionError`` (edits)
    or ``Ineligible`` (new listing blocked by the media gate)."""
    from ..routes.admin import (
        _blocked_by_media_readiness,
        _queue_listing_moderation_notification,
        _queue_listing_revision_notification,
    )

    if subject.type == "listing":
        car = subject.car
        if _blocked_by_media_readiness(True, "active", car.media_status):
            raise Ineligible("media_not_ready")
        car.status = "active"
        car.is_active = True
        car.updated_at = utcnow()
        notification = _queue_listing_moderation_notification(car, "active")
        return PublishResult(car, notification, car.seller)
    result = lr.publish_revision(subject.revision.id, expected_token=subject.token, reviewer=reviewer)
    car = result["car"]
    notification = _queue_listing_revision_notification(car, "approved")
    return PublishResult(
        car,
        notification,
        car.seller,
        removed_urls=result["removed_urls"],
        old_price=result["old_price"],
        new_price=result["new_price"],
        changed_fields=result["changed_fields"],
    )


def post_publish(pr: PublishResult) -> None:
    """Side effects after the publishing transaction COMMITTED (same set the
    manual admin routes perform)."""
    from ..response_cache import invalidate_filter_facets_cache
    from ..routes.admin import _deliver_listing_moderation_notification

    try:
        lr.cleanup_unreferenced_media(pr.removed_urls)
    except Exception:
        logger.exception("auto-moderation: media cleanup failed")
    try:
        invalidate_filter_facets_cache()
    except Exception:
        logger.exception("auto-moderation: cache invalidation failed")
    if pr.notification is not None and pr.seller is not None:
        _deliver_listing_moderation_notification(pr.notification, pr.seller)
    if (
        pr.old_price is not None
        and pr.new_price is not None
        and pr.new_price < pr.old_price
        and pr.car.is_active
    ):
        try:
            from ..retention_dispatch import dispatch_price_drop_alerts

            dispatch_price_drop_alerts(pr.car.id, pr.old_price, pr.new_price)
        except Exception:
            logger.exception("auto-moderation: price-drop dispatch failed")


def _ai_gate(stored_ai: dict | None, settings: dict, subject: Subject, facts) -> list[Signal]:
    """Apply-time proof that the advisory check the decision relied on really
    covered what would be published. The stored AI result is re-judged under
    the CURRENT settings (a raised confidence bar, a newly required check) and
    compared with the content as it is NOW: nothing is approved on a missing,
    partial or mismatched inspection, however the run got to pending_apply."""
    out = [s for s in ai_signals(stored_ai, settings) if s.level in (HOLD, REVIEW)]
    if out:
        return out
    _t, _d, urls, needed, cover_needed = ai_inputs(subject, facts)
    status = (stored_ai or {}).get("status")
    if needed and status == "not_needed":
        return [Signal("ai_not_run", REVIEW, "ai", False, "content needs a check")]
    if status == "ok" and (
        int(stored_ai.get("images_expected") or 0) != len(urls)
        or bool(stored_ai.get("cover_expected")) != cover_needed
    ):
        return [Signal("ai_image_coverage_incomplete", REVIEW, "ai", False, "gallery differs from inspected set")]
    if status == "disabled" and settings.get("ai_required_effective", True):
        return [Signal("ai_not_configured", REVIEW, "ai", False)]
    return []


def _downgrade(run: ListingModerationRun, blockers: list[Signal], *, stage: str) -> None:
    hold = any(b.level == HOLD for b in blockers)
    run.decision = "HOLD" if hold else "NEEDS_REVIEW"
    run.outcome = "held" if hold else "downgraded"
    run.reasons = list(run.reasons or []) + [dict(b.to_dict(), stage=stage) for b in blockers]
    run.next_retry_at = None
    log_event(run, "downgraded_at_apply", data={"codes": [b.code for b in blockers], "stage": stage})


def _apply(run_id: int, subject_type: str, subject_id: int) -> dict:
    db.session.rollback()
    try:
        _lock_subject(subject_type, subject_id)
    except Ineligible as e:
        db.session.rollback()
        run = _lock_run(run_id)
        if run is not None and run.outcome == "pending_apply":
            run.outcome = "superseded"
            run.status = "stale"
            log_event(run, "superseded", data={"code": e.code, "stage": "apply"})
            db.session.commit()
        db.session.rollback()
        return {"outcome": "superseded", "code": e.code}

    run = _lock_run(run_id)
    if run is None:
        db.session.rollback()
        return {"outcome": "missing"}
    if run.applied_at is not None or run.outcome != "pending_apply":
        db.session.rollback()
        return {"outcome": run.outcome, "idempotent": True}

    # Share-lock the settings row until this transaction ends: a kill switch
    # (or mode change) committed before this point is seen here, and one
    # being committed now waits for this publication to finish first.
    settings = load_settings(lock_shared=True)
    mode = effective_mode(settings)
    if mode != "live":
        run.outcome = "blocked_killswitch" if kill_switch_active(settings) else "blocked_mode"
        log_event(run, run.outcome, data={"mode": mode})
        db.session.commit()
        return {"outcome": run.outcome}

    max_age = int((settings.get("retry") or {}).get("apply_max_age_seconds", 900))
    if run.decided_at is None or utcnow() - run.decided_at > timedelta(seconds=max_age):
        sig = Signal("decision_expired", HOLD, "engine", False)
        run.decision = "HOLD"
        run.outcome = "held"
        run.reasons = list(run.reasons or []) + [sig.to_dict()]
        run.next_retry_at = utcnow()
        log_event(run, "decision_expired")
        db.session.commit()
        return {"outcome": "held", "retry_in": 1}

    try:
        fresh = resolve_subject(subject_type, subject_id)
    except Ineligible as e:
        run.outcome = "superseded"
        run.status = "stale"
        log_event(run, "superseded", data={"code": e.code, "stage": "apply"})
        db.session.commit()
        return {"outcome": "superseded", "code": e.code}
    if fresh.token != run.content_token:
        run.outcome = "stale"
        run.status = "stale"
        log_event(run, "stale_result_discarded", data={"stage": "apply"})
        db.session.commit()
        return {"outcome": "stale", "reenqueue": True}

    facts = build_facts(fresh, settings)
    blockers = [
        s for s in run_rules(facts, settings, utcnow().year) if s.level in (HOLD, REVIEW)
    ]
    blockers += _ai_gate(run.ai, settings, fresh, facts)
    if blockers:
        _downgrade(run, blockers, stage="apply")
        db.session.commit()
        return {"outcome": run.outcome, "run_id": run.id, "alert": run.decision == "NEEDS_REVIEW"}

    try:
        pr = publish_subject(fresh, reviewer=AUTO_REVIEWER)
    except lr.RevisionError as e:
        db.session.rollback()
        stale = e.code in ("stale_revision",)
        _finish(
            run_id,
            _attempts_of(run_id),
            status="stale" if stale else None,
            outcome="stale" if stale else "downgraded",
            decision=None if stale else ("HOLD" if e.code in ("media_not_ready", "media_failed") else "NEEDS_REVIEW"),
            event="apply_refused",
            event_data={"code": e.code},
        )
        return {"outcome": "stale" if stale else "downgraded", "code": e.code, "reenqueue": stale}
    except Ineligible as e:
        db.session.rollback()
        _finish(run_id, _attempts_of(run_id), outcome="downgraded", decision="HOLD",
                event="apply_refused", event_data={"code": e.code})
        return {"outcome": "downgraded", "code": e.code}

    run = _lock_run(run_id)
    run.applied_at = utcnow()
    run.outcome = "published"
    if run.subject_type == "revision":
        run.revision_id = None  # the revision row is consumed by the publish
    log_event(
        run,
        "published",
        actor=AUTO_REVIEWER,
        data={"subject_type": subject_type, "changed_fields": pr.changed_fields},
    )
    db.session.commit()
    post_publish(pr)
    return {"outcome": "published", "run_id": run.id}


def _attempts_of(run_id: int) -> int:
    row = db.session.query(ListingModerationRun.attempts).filter_by(id=run_id).first()
    return row[0] if row else -1


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def moderate(subject_type: str, subject_id: int, *, trigger: str = "event") -> dict:
    """Run the pipeline for one subject. Safe to call any number of times,
    concurrently, and after any crash: the outcome is determined by the run
    row. Returns a small dict describing what happened (for tasks / tests)."""
    settings = load_settings()
    mode = effective_mode(settings)
    if mode == "off":
        return {"outcome": "skipped_off"}
    try:
        subject = resolve_subject(subject_type, subject_id)
    except Ineligible as e:
        return {"outcome": "ineligible", "code": e.code}

    run, state = _claim(subject, mode, settings, trigger)
    if state in ("done", "busy", "backoff"):
        return {"outcome": state, "run_id": run.id if run is not None else None}
    run_id, attempts = run.id, run.attempts

    if state == "resume_apply":
        return _apply(run_id, subject_type, subject_id)

    try:
        signals, ai, checks = evaluate(subject, settings)
    except Exception as exc:  # incl. SoftTimeLimitExceeded: never approve on failure
        return _record_error(run_id, attempts, exc, settings)

    result = _record_decision(run_id, attempts, subject, signals, ai, checks, settings, mode)
    result.setdefault("run_id", run_id)
    if (
        mode == "live"
        and result.get("decision") == "AUTO_APPROVE"
        and result.get("outcome") == "pending_apply"
    ):
        applied = _apply(run_id, subject_type, subject_id)
        applied.setdefault("run_id", run_id)
        applied["decision"] = result["decision"]
        result = applied
    return result
