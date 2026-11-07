"""Durable web account-deletion requests (the public /delete-account form).

Contract
--------
* :func:`submit_request` commits an ``AccountDeletionRequest`` row BEFORE the
  caller may report success. If the database write fails it raises
  :class:`RequestStorageError` (the route answers 503, never "success").
* The support-mailbox email is only a best-effort NOTIFICATION of that row.
  ``send_email()`` reports delivery failure by returning ``False`` (provider
  helpers swallow their own exceptions), so the result is checked and
  recorded -- an outage leaves ``notified_at`` NULL, ``notify_attempts`` > 0
  and ``last_notify_error`` set, and the request stays visible to operators.
* Retry: a repeated submission for a still-pending, un-notified request
  re-attempts the notification, and operators can trigger
  :func:`retry_unnotified` via the admin API. No scheduler/beat job is needed
  because the row itself is the durable queue.
* No account enumeration: submission never looks up whether an account with
  that phone exists, and new / duplicate submissions look identical to the
  caller (the public route returns the same body for both).
"""

from __future__ import annotations

import hashlib
import hmac
import logging
import unicodedata
from typing import Any

from flask import current_app
from sqlalchemy.exc import IntegrityError

from .models import AccountDeletionRequest, db
from .phone_format import normalize_iraqi_mobile
from .time_utils import utcnow

logger = logging.getLogger(__name__)

STATUS_PENDING = "pending"
STATUS_COMPLETED = "completed"


class RequestStorageError(RuntimeError):
    """The request could not be durably stored (caller must not report success)."""


def phone_digits(value: str) -> str:
    """ASCII digits of ``value`` (Arabic-Indic / Persian digits are mapped)."""
    out = []
    for ch in value or "":
        if ch.isdecimal():
            out.append(str(unicodedata.decimal(ch)))
    return "".join(out)


def phone_key_for(phone: str) -> str:
    """Canonical dedupe key: ``7XXXXXXXXX`` for Iraqi mobiles, else digits."""
    return normalize_iraqi_mobile(phone) or phone_digits(phone)


def _ip_hash(ip: str | None) -> str | None:
    if not ip:
        return None
    key = str(current_app.config.get("SECRET_KEY") or "").encode("utf-8")
    return hmac.new(key, ip.encode("utf-8"), hashlib.sha256).hexdigest()


def _find_pending(phone_key: str) -> AccountDeletionRequest | None:
    return AccountDeletionRequest.query.filter_by(
        phone_key=phone_key, status=STATUS_PENDING
    ).first()


def _notification_body(req: AccountDeletionRequest) -> str:
    return (
        "Web account deletion request\n"
        f"Request ID: {req.public_id}\n"
        f"Phone: {req.phone}\n"
        f"Email: {req.email or '(none)'}\n"
        f"Details: {req.details or '(none)'}\n"
        f"Received: {req.created_at.isoformat() if req.created_at else ''}\n"
        "\nThis request is stored in the admin queue (account deletion requests)."
        " Mark it completed there once processed.\n"
    )


def notify_support(req: AccountDeletionRequest, support_email: str) -> bool:
    """Best-effort notification email. Never raises; records the outcome."""
    ok = False
    error: str | None = None
    if not (support_email or "").strip():
        error = "support_email_not_configured"
    else:
        try:
            from .email_service import send_email

            ok = bool(
                send_email(
                    to_email=support_email,
                    subject="CarNet account deletion request",
                    text_body=_notification_body(req),
                    html_body=None,
                )
            )
            if not ok:
                error = "email_provider_reported_failure"
        except Exception as e:  # provider/network error
            logger.exception("account_deletion_request email failed")
            error = f"{type(e).__name__}"[:255]

    try:
        req.notify_attempts = (req.notify_attempts or 0) + 1
        if ok:
            req.notified_at = utcnow()
            req.last_notify_error = None
        else:
            req.last_notify_error = error
        db.session.commit()
    except Exception:
        db.session.rollback()
        logger.exception("account_deletion_request notify bookkeeping failed")
    if not ok:
        logger.warning(
            "account_deletion_request notification not delivered request=%s reason=%s "
            "(request is stored and visible in the admin queue)",
            req.public_id,
            error,
        )
    return ok


def submit_request(
    *,
    phone: str,
    email: str,
    details: str,
    ip: str | None,
    support_email: str,
) -> tuple[AccountDeletionRequest, bool]:
    """Durably store a request. Returns ``(row, created)``.

    ``created`` is False for a duplicate of a still-pending request. Raises
    :class:`RequestStorageError` if nothing could be stored.
    """
    key = phone_key_for(phone)
    try:
        existing = _find_pending(key)
    except Exception as e:
        db.session.rollback()
        raise RequestStorageError("lookup failed") from e

    if existing is not None:
        if existing.notified_at is None:
            notify_support(existing, support_email)  # retry; never raises
        return existing, False

    row = AccountDeletionRequest(
        phone=phone[:32],
        phone_key=key[:64],
        email=(email or None) and email[:120],
        details=(details or None),
        ip_hash=_ip_hash(ip),
        status=STATUS_PENDING,
    )
    try:
        db.session.add(row)
        db.session.commit()
    except IntegrityError:
        # Concurrent duplicate won the partial unique index.
        db.session.rollback()
        try:
            existing = _find_pending(key)
        except Exception as e:
            db.session.rollback()
            raise RequestStorageError("lookup failed") from e
        if existing is None:
            raise RequestStorageError("insert conflict")
        return existing, False
    except Exception as e:
        db.session.rollback()
        logger.exception("account_deletion_request could not be stored")
        raise RequestStorageError("insert failed") from e

    notify_support(row, support_email)  # best-effort; request is already durable
    return row, True


def retry_unnotified(support_email: str, *, limit: int = 50) -> dict[str, Any]:
    """Re-attempt the support notification for pending, un-notified requests."""
    rows = (
        AccountDeletionRequest.query.filter(
            AccountDeletionRequest.status == STATUS_PENDING,
            AccountDeletionRequest.notified_at.is_(None),
        )
        .order_by(AccountDeletionRequest.created_at.asc())
        .limit(max(1, min(int(limit), 200)))
        .all()
    )
    sent = 0
    for row in rows:
        if notify_support(row, support_email):
            sent += 1
    return {"attempted": len(rows), "sent": sent, "failed": len(rows) - sent}


def list_requests(
    *, status: str | None, limit: int, offset: int
) -> tuple[list[AccountDeletionRequest], int]:
    q = AccountDeletionRequest.query
    if status in (STATUS_PENDING, STATUS_COMPLETED):
        q = q.filter(AccountDeletionRequest.status == status)
    total = q.count()
    rows = (
        q.order_by(AccountDeletionRequest.created_at.asc(), AccountDeletionRequest.id.asc())
        .offset(max(0, offset))
        .limit(max(1, min(limit, 200)))
        .all()
    )
    return rows, total


def mark_completed(
    req: AccountDeletionRequest, *, operator_user_id: int | None, note: str | None
) -> bool:
    """Complete a request and scrub its contact details. Idempotent.

    Returns True if this call changed the row.
    """
    if req.status == STATUS_COMPLETED:
        return False
    digest = hashlib.sha256((req.phone_key or "").encode("utf-8")).hexdigest()
    tail = (req.phone_key or "")[-4:]
    req.status = STATUS_COMPLETED
    req.completed_at = utcnow()
    req.completed_by_user_id = operator_user_id
    req.completion_note = (note or "").strip()[:255] or None
    req.phone = f"***{tail}"
    req.phone_key = digest
    req.email = None
    req.details = None
    req.last_notify_error = None
    db.session.commit()
    return True
