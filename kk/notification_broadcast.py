"""Admin notification broadcast + scheduled delivery."""

from __future__ import annotations

import logging
from datetime import datetime
from typing import Any

from sqlalchemy import or_

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


def process_due_scheduled_notifications(*, limit: int = 20) -> dict[str, Any]:
    """Send pending scheduled notifications that are due. Safe to call often."""
    now = utcnow()
    due = (
        ScheduledNotification.query.filter(
            ScheduledNotification.status == "pending",
            ScheduledNotification.scheduled_at <= now,
        )
        .order_by(ScheduledNotification.scheduled_at.asc())
        .limit(limit)
        .all()
    )
    sent = 0
    failed = 0
    results = []
    for row in due:
        row.status = "sending"
        row.updated_at = utcnow()
        db.session.commit()
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
            sent += 1
            results.append({"id": row.id, "status": "sent", **out})
        except Exception as e:
            logger.error("scheduled notification %s failed: %s", row.id, e, exc_info=True)
            row.status = "failed"
            row.error_message = str(e)[:500]
            row.updated_at = utcnow()
            db.session.commit()
            failed += 1
            results.append({"id": row.id, "status": "failed", "error": str(e)})
    return {"processed": len(due), "sent": sent, "failed": failed, "results": results}
