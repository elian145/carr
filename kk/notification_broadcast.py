"""Admin notification broadcast + scheduled delivery."""

from __future__ import annotations

import logging
from datetime import datetime
from typing import Any

from sqlalchemy import or_, update

from .models import Notification, ScheduledNotification, User, db
from .push import fcm_is_configured, send_push
from .time_utils import utcnow

logger = logging.getLogger(__name__)

VALID_AUDIENCES = ("all", "dealers", "users", "user")


def _find_user(public_id: str) -> User | None:
    pid = (public_id or "").strip()
    if not pid:
        return None
    return User.query.filter_by(public_id=pid).first()


def resolve_recipients(
    *,
    audience: str,
    target_user_id: str | None = None,
    limit: int = 5000,
) -> tuple[list[User], str | None]:
    """Return (recipients, error_message)."""
    audience = (audience or "all").strip().lower()
    target_user_id = (target_user_id or "").strip() or None

    if audience not in VALID_AUDIENCES:
        return [], f"Invalid audience. Use: {', '.join(VALID_AUDIENCES)}"

    if audience == "user" or target_user_id:
        if not target_user_id:
            return [], "target_user_id is required for audience=user"
        user = _find_user(target_user_id)
        if not user:
            return [], "Target user not found"
        return [user], None

    if audience == "dealers":
        recipients = (
            User.query.filter(
                User.is_active.is_(True),
                or_(User.account_type == "dealer", User.dealer_status == "approved"),
            )
            .limit(limit)
            .all()
        )
    elif audience == "users":
        recipients = (
            User.query.filter(
                User.is_active.is_(True),
                User.account_type != "dealer",
            )
            .limit(limit)
            .all()
        )
    else:
        recipients = User.query.filter(User.is_active.is_(True)).limit(limit).all()
    return recipients, None


def execute_broadcast(
    *,
    title: str,
    message: str,
    audience: str = "all",
    target_user_id: str | None = None,
    notification_type: str = "admin",
    send_push_flag: bool = True,
    source: str = "admin_broadcast",
) -> dict[str, Any]:
    """
    Create in-app notifications (+ optional FCM) for an audience.
    Raises ValueError for validation errors.
    """
    title = (title or "").strip()
    message = (message or "").strip()
    notification_type = (notification_type or "admin").strip() or "admin"
    audience = (audience or "all").strip().lower()

    if not title or not message:
        raise ValueError("Title and message are required")
    if len(title) > 200:
        raise ValueError("Title must be 200 characters or fewer")

    recipients, err = resolve_recipients(
        audience=audience, target_user_id=target_user_id
    )
    if err:
        raise ValueError(err)

    created = 0
    pushed = 0
    push_ready = fcm_is_configured()
    notif_data = {"source": source, "audience": audience}

    for user in recipients:
        db.session.add(
            Notification(
                user_id=user.id,
                title=title,
                message=message,
                notification_type=notification_type,
                is_read=False,
                data=notif_data,
            )
        )
        created += 1
        if send_push_flag and push_ready:
            token = (getattr(user, "firebase_token", None) or "").strip()
            if token and send_push(
                token,
                title=title,
                body=message,
                data={"type": notification_type, **notif_data},
            ):
                pushed += 1
        if created % 200 == 0:
            db.session.commit()

    db.session.commit()
    return {
        "created": created,
        "pushed": pushed,
        "push_configured": push_ready,
        "audience": audience,
        "message": f"Notification created for {created} user(s)",
    }


def parse_scheduled_at(raw) -> datetime:
    """Parse ISO-8601 datetime into naive UTC for DB storage."""
    if raw is None or raw == "":
        raise ValueError("scheduled_at is required")
    if isinstance(raw, datetime):
        dt = raw
    else:
        s = str(raw).strip()
        if s.endswith("Z"):
            s = s[:-1] + "+00:00"
        try:
            dt = datetime.fromisoformat(s)
        except ValueError as e:
            raise ValueError("scheduled_at must be ISO-8601 datetime") from e
    if dt.tzinfo is not None:
        from datetime import timezone

        dt = dt.astimezone(timezone.utc).replace(tzinfo=None)
    return dt


def _validate_broadcast_request(
    *,
    title: str,
    message: str,
    audience: str,
    target_user_id: str | None,
) -> tuple[str, str, str, str | None]:
    """Shared validation for create_scheduled_notification() and
    create_immediate_broadcast_row() (BE-04): non-empty title/message, a
    200-char title cap, and a resolvable audience/target_user_id. Returns
    the cleaned (title, message, audience, target_user_id). Raises
    ValueError on any validation failure -- identical rules, identical
    error messages, for both scheduled and immediate broadcasts.
    """
    title = (title or "").strip()
    message = (message or "").strip()
    if not title or not message:
        raise ValueError("Title and message are required")
    if len(title) > 200:
        raise ValueError("Title must be 200 characters or fewer")

    audience = (audience or "all").strip().lower()
    target_user_id = (target_user_id or "").strip() or None
    _, err = resolve_recipients(audience=audience, target_user_id=target_user_id)
    if err:
        raise ValueError(err)
    return title, message, audience, target_user_id


def create_scheduled_notification(
    *,
    title: str,
    message: str,
    scheduled_at: datetime,
    audience: str = "all",
    target_user_id: str | None = None,
    notification_type: str = "admin",
    send_push_flag: bool = True,
    created_by_user_id: int | None = None,
) -> ScheduledNotification:
    title, message, audience, target_user_id = _validate_broadcast_request(
        title=title, message=message, audience=audience, target_user_id=target_user_id
    )

    if scheduled_at <= utcnow():
        raise ValueError("scheduled_at must be in the future")

    row = ScheduledNotification(
        title=title,
        message=message,
        audience=audience,
        target_user_public_id=target_user_id,
        notification_type=(notification_type or "admin").strip() or "admin",
        send_push=bool(send_push_flag),
        scheduled_at=scheduled_at,
        status="pending",
        created_by_user_id=created_by_user_id,
        created_at=utcnow(),
        updated_at=utcnow(),
    )
    db.session.add(row)
    db.session.commit()
    return row


def create_immediate_broadcast_row(
    *,
    title: str,
    message: str,
    audience: str = "all",
    target_user_id: str | None = None,
    notification_type: str = "admin",
    send_push_flag: bool = True,
    created_by_user_id: int | None = None,
) -> ScheduledNotification:
    """Durably record a "send now" broadcast as a due ScheduledNotification
    row (BE-04).

    This intentionally does NOT reuse create_scheduled_notification()'s
    future-only ``scheduled_at`` validation (``scheduled_at`` must be
    strictly greater than ``utcnow()``) -- an immediate broadcast is due
    *now*, by definition, so calling that function with ``scheduled_at =
    utcnow()`` would always fail its own check. Rather than loosen that
    existing, already-relied-upon rule, this is a separate, dedicated
    creation path that shares the exact same title/message/audience
    validation via ``_validate_broadcast_request()`` but sets
    ``scheduled_at = utcnow()`` directly.

    The caller (the admin HTTP route) is expected to commit this row --
    which happens here -- *before* attempting to enqueue
    ``send_immediate_broadcast_task``, so the broadcast is never lost even
    if the Celery enqueue itself fails: the row stays ``"pending"`` and is
    still visible/claimable via the existing beat schedule or the
    "process due" admin action.
    """
    title, message, audience, target_user_id = _validate_broadcast_request(
        title=title, message=message, audience=audience, target_user_id=target_user_id
    )

    now = utcnow()
    row = ScheduledNotification(
        title=title,
        message=message,
        audience=audience,
        target_user_public_id=target_user_id,
        notification_type=(notification_type or "admin").strip() or "admin",
        send_push=bool(send_push_flag),
        scheduled_at=now,
        status="pending",
        created_by_user_id=created_by_user_id,
        created_at=now,
        updated_at=now,
    )
    db.session.add(row)
    db.session.commit()
    return row


def _due_pending_query(*, limit: int):
    """Shared due-query used by every BE-03/BE-04 claim entry point:
    pending rows whose scheduled_at is now-or-earlier, oldest first."""
    now = utcnow()
    return (
        ScheduledNotification.query.filter(
            ScheduledNotification.status == "pending",
            ScheduledNotification.scheduled_at <= now,
        )
        .order_by(ScheduledNotification.scheduled_at.asc())
        .limit(limit)
    )


def _try_claim_pending_row(row: ScheduledNotification) -> bool:
    """BE-03 atomic claim primitive: a single conditional SQL
    ``UPDATE scheduled_notification SET status='sending', updated_at=...
    WHERE id = :id AND status = 'pending'``. The plain SELECT that found
    this row can race with any other concurrent caller (another beat tick,
    the manual "process due" endpoint, a concurrent immediate-send task,
    two Gunicorn workers, etc.) -- only the caller whose UPDATE actually
    flips exactly one row from "pending" to "sending" (``rowcount == 1``)
    is allowed to proceed; a ``rowcount == 0`` result means another caller
    already claimed it between the SELECT and this UPDATE.

    On a successful claim, syncs ``row``'s in-memory ``status``/
    ``updated_at`` to match what was just written (the raw Core ``UPDATE``
    does not otherwise update the already-loaded ORM instance).

    Returns True if this call won the claim, False otherwise. Semantics
    are unchanged from the original BE-03 implementation -- this is an
    extraction, not a behavior change.
    """
    claim_ts = utcnow()
    claim = db.session.execute(
        update(ScheduledNotification)
        .where(
            ScheduledNotification.id == row.id,
            ScheduledNotification.status == "pending",
        )
        .values(status="sending", updated_at=claim_ts)
    )
    db.session.commit()
    if claim.rowcount != 1:
        logger.info(
            "scheduled notification %s already claimed by another worker; skipping",
            row.id,
        )
        return False
    row.status = "sending"
    row.updated_at = claim_ts
    return True


def _claim_and_send_scheduled_notification(row: ScheduledNotification) -> dict[str, Any] | None:
    """Atomically claim one due ScheduledNotification row and broadcast it.

    Shared by process_due_scheduled_notifications() (batch sweep, used by
    Celery beat and the "process due" admin action) and
    process_scheduled_notification_by_id() (single-row lookup, used by
    send_immediate_broadcast_task for BE-04 "send now" broadcasts). Both
    entry points share identical BE-03 claim semantics via
    _try_claim_pending_row() -- neither can double-send a row the other
    has already claimed.

    Returns None if the row was already claimed by another caller
    (nothing to report); otherwise a result dict with
    ``{"id", "status": "sent"|"failed", ...}``.
    """
    if not _try_claim_pending_row(row):
        return None

    try:
        out = execute_broadcast(
            title=row.title,
            message=row.message,
            audience=row.audience,
            target_user_id=row.target_user_public_id,
            notification_type=row.notification_type,
            send_push_flag=bool(row.send_push),
            source="admin_scheduled",
        )
        row.status = "sent"
        row.sent_at = utcnow()
        row.result = out
        row.error_message = None
        row.updated_at = utcnow()
        db.session.commit()
        return {"id": row.id, "status": "sent", **out}
    except Exception as e:
        logger.error("scheduled notification %s failed: %s", row.id, e, exc_info=True)
        # BE-04 hardening: an exception here may have left the session's
        # transaction aborted (e.g. a DB error inside execute_broadcast()'s
        # own commit). Roll back first so this failure-state write below
        # cannot itself be rejected by the DB for being issued inside an
        # already-aborted transaction, which would otherwise leave the row
        # stuck in "sending" instead of recording "failed".
        db.session.rollback()
        row.status = "failed"
        row.error_message = str(e)[:500]
        row.updated_at = utcnow()
        db.session.commit()
        return {"id": row.id, "status": "failed", "error": str(e)}


def list_due_pending_ids(*, limit: int = 20) -> list[int]:
    """Read-only lookup of up to ``limit`` due, pending ScheduledNotification
    row ids -- does NOT claim them (BE-04).

    Used by ``POST /api/admin/notifications/scheduled/process``: this is a
    plain ``SELECT`` (no ``UPDATE``, no state change, no commit) so the
    HTTP request thread stays fast and never touches row state itself. It
    then enqueues one ``send_immediate_broadcast_task`` per id returned
    here; each task performs its own authoritative BE-03 atomic
    ``pending -> sending`` claim (via ``process_scheduled_notification_by_id()``
    -> ``_claim_and_send_scheduled_notification()`` -> ``_try_claim_pending_row()``)
    immediately before it calls execute_broadcast() -- exactly like the
    send-now path and beat's own periodic sweep already do.

    IMPORTANT: an earlier version of this function claimed rows here
    (``pending -> sending``) before enqueueing. That was a bug: the task
    it handed off to also tries to claim the same row via the identical
    ``_try_claim_pending_row()`` primitive, and finds it already
    ``"sending"`` -- rowcount 0 -- so it always returns without ever
    calling execute_broadcast(), permanently stranding the row in
    "sending". Only the execution context that is actually about to fan
    out (the Celery task) may perform the ``pending -> sending``
    transition; this function must stay read-only.

    A row returned here can still legitimately be claimed by a race --
    Celery beat's own sweep, or another concurrent enqueue of the same
    task -- before the task enqueued here runs; that is expected and safe:
    BE-03's atomic claim guarantees exactly one of them proceeds.

    Returns the ids of due, pending rows found (a snapshot, not a
    guarantee -- by the time a caller acts on these ids, another caller
    may have already claimed some of them).
    """
    due = _due_pending_query(limit=limit).all()
    return [row.id for row in due]


def process_scheduled_notification_by_id(row_id: int) -> dict[str, Any] | None:
    """Claim-and-send a single ScheduledNotification row by primary key
    (BE-04).

    Used by ``send_immediate_broadcast_task`` so a "send now" broadcast is
    attempted on the very next worker cycle regardless of how many other
    due rows are queued, instead of waiting for
    process_due_scheduled_notifications()'s own batch sweep (which orders
    by ``scheduled_at`` ascending and, under a large backlog, could leave a
    freshly-created row past a bounded ``limit``). Reuses the identical
    BE-03 atomic-claim primitive as the batch sweep.

    Returns None if the row does not exist, or was already claimed by
    another caller (e.g. beat's own periodic sweep won the race) --
    nothing to report in either case. Otherwise returns the same result
    dict shape as _claim_and_send_scheduled_notification().
    """
    row = db.session.get(ScheduledNotification, row_id)
    if row is None:
        logger.warning("scheduled notification %s not found; nothing to send", row_id)
        return None
    return _claim_and_send_scheduled_notification(row)


def process_due_scheduled_notifications(*, limit: int = 20) -> dict[str, Any]:
    """Send pending scheduled notifications that are due. Safe to call often.

    BE-04: the per-row claim + execute_broadcast() + state-update logic
    previously inlined here now lives in _claim_and_send_scheduled_notification()
    (a pure extraction -- same claim SQL, same try/except, same commits,
    same "processed"/"sent"/"failed"/"results" shape). This function's own
    observable behavior is unchanged.
    """
    due = _due_pending_query(limit=limit).all()
    sent = 0
    failed = 0
    results = []
    for row in due:
        outcome = _claim_and_send_scheduled_notification(row)
        if outcome is None:
            continue
        if outcome["status"] == "sent":
            sent += 1
        else:
            failed += 1
        results.append(outcome)
    return {"processed": len(due), "sent": sent, "failed": failed, "results": results}
