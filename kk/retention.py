"""Opt-in data-retention cleanup (F-16).

EVERYTHING HERE IS A NO-OP UNLESS ITS ENVIRONMENT VARIABLE IS SET. No retention
period is built in: the privacy policy does not state periods for these data
classes, so the periods are an owner decision (see docs/RETENTION_CLEANUP.md).

  RETENTION_TOKEN_BLACKLIST_PURGE=1     delete token_blacklist rows whose JWT has
                                        already expired (functionally dead: the
                                        token is rejected on expiry anyway)
  RETENTION_USER_ACTION_DAYS=<n>        delete analytics rows in user_action
                                        older than n days (admin_* actions are
                                        never touched)
  RETENTION_READ_NOTIFICATION_DAYS=<n>  delete READ notifications older than n
                                        days (unread ones are never touched)

Never touched, regardless of settings: admin_audit_log (append-only), chat
messages and chat media, reports, listings, users.

Deletes are done in bounded batches so a large backlog cannot hold long locks.
"""

from __future__ import annotations

import logging
import os
from datetime import timedelta

from .models import Notification, TokenBlacklist, UserAction, db
from .time_utils import utcnow

logger = logging.getLogger(__name__)

BATCH_SIZE = 1000
MAX_BATCHES = 100  # per table per run -> at most 100k rows/run; the next run continues
# Expired-token rows are kept this long past expiry to absorb clock skew.
TOKEN_EXPIRY_GRACE = timedelta(hours=1)


def _positive_int_env(name: str) -> int | None:
    raw = (os.environ.get(name) or "").strip()
    if not raw:
        return None
    try:
        value = int(raw)
    except ValueError:
        logger.warning("retention: ignoring non-integer %s", name)
        return None
    return value if value > 0 else None


def _flag_env(name: str) -> bool:
    return (os.environ.get(name) or "").strip().lower() in ("1", "true", "yes", "on")


def _delete_in_batches(model, predicate) -> int:
    """Delete rows matching ``predicate`` in id-ordered batches; returns count."""
    total = 0
    for _ in range(MAX_BATCHES):
        ids = [
            r[0]
            for r in db.session.query(model.id)
            .filter(predicate)
            .order_by(model.id)
            .limit(BATCH_SIZE)
            .all()
        ]
        if not ids:
            break
        try:
            deleted = (
                db.session.query(model)
                .filter(model.id.in_(ids))
                .delete(synchronize_session=False)
            )
            db.session.commit()
        except Exception:
            db.session.rollback()
            raise
        total += deleted or 0
        if len(ids) < BATCH_SIZE:
            break
    return total


def purge_expired_token_blacklist(now=None) -> int:
    now = now or utcnow()
    return _delete_in_batches(
        TokenBlacklist, TokenBlacklist.expires_at < (now - TOKEN_EXPIRY_GRACE)
    )


def purge_old_user_actions(days: int, now=None) -> int:
    now = now or utcnow()
    return _delete_in_batches(
        UserAction,
        (UserAction.created_at < now - timedelta(days=days))
        & ~UserAction.action_type.like("admin\\_%", escape="\\"),
    )


def purge_old_read_notifications(days: int, now=None) -> int:
    now = now or utcnow()
    return _delete_in_batches(
        Notification,
        (Notification.is_read.is_(True))
        & (Notification.created_at < now - timedelta(days=days)),
    )


def run_retention(now=None) -> dict:
    """Run every enabled cleanup. Returns per-job deleted counts (absent = disabled)."""
    result: dict = {}
    if _flag_env("RETENTION_TOKEN_BLACKLIST_PURGE"):
        result["token_blacklist"] = purge_expired_token_blacklist(now)
    days = _positive_int_env("RETENTION_USER_ACTION_DAYS")
    if days:
        result["user_action"] = purge_old_user_actions(days, now)
    days = _positive_int_env("RETENTION_READ_NOTIFICATION_DAYS")
    if days:
        result["read_notifications"] = purge_old_read_notifications(days, now)
    logger.info("retention run: %s", result or "all jobs disabled (no-op)")
    return result
