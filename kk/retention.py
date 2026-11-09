"""Opt-in data-retention cleanup (F-16).

SAFE BY DEFAULT: nothing is deleted unless the owner explicitly turns it on, and
even then the first runs only COUNT. No retention period is built in: the privacy
policy does not state periods for these data classes, so the periods are an owner
decision (see docs/RETENTION_CLEANUP.md).

Three independent gates must ALL be open before a single row is deleted:

  RETENTION_ENABLED=1                   master switch (default OFF -> whole job is a no-op)
  RETENTION_DRY_RUN=0                   default ON: without this the job only COUNTS what it
                                        would delete (anything other than 0/false/no/off,
                                        including unset or garbage, keeps dry-run on)
  <job setting below>                   each job is a no-op until configured; a period that
                                        is unset / not a positive integer is skipped and
                                        reported in the audit record (never defaulted)

  RETENTION_TOKEN_BLACKLIST_PURGE=1     token_blacklist rows whose JWT has already expired
                                        (functionally dead: the token is rejected on expiry
                                        anyway) - fixed 1 h clock-skew grace, not a policy period
  RETENTION_AUTH_TOKEN_PURGE=1          password_reset / email_verification rows that expired
                                        > 1 h ago (unredeemable)
  RETENTION_USER_ACTION_DAYS=<n>        analytics rows in user_action older than n days
                                        (admin_* actions are never touched)
  RETENTION_READ_NOTIFICATION_DAYS=<n>  READ notifications older than n days (unread ones
                                        are never touched)

Never touched, regardless of settings: admin_audit_log (append-only), chat
messages and chat media, reports, listings, users.

Deletes are done in bounded batches (BATCH_SIZE rows, at most MAX_BATCHES batches per
table per run) so a large backlog cannot hold long locks; the next run continues.
Every enabled run (dry or real, including a failed one) writes one ``retention_run``
row to the append-only admin audit log and a log line.
"""

from __future__ import annotations

import logging
import os
from datetime import timedelta

from .models import (
    EmailVerification,
    Notification,
    PasswordReset,
    TokenBlacklist,
    UserAction,
    db,
)
from .time_utils import utcnow

logger = logging.getLogger(__name__)

BATCH_SIZE = 1000
MAX_BATCHES = 100  # per table per run -> at most 100k rows/run; the next run continues
# Expired-token rows are kept this long past expiry to absorb clock skew.
TOKEN_EXPIRY_GRACE = timedelta(hours=1)

AUDIT_ACTION = "retention_run"


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


def retention_enabled() -> bool:
    """Master switch. Default OFF."""
    return _flag_env("RETENTION_ENABLED")


def retention_dry_run() -> bool:
    """Dry-run unless explicitly turned off (fail-safe: unset/garbage => dry-run)."""
    return (os.environ.get("RETENTION_DRY_RUN") or "").strip().lower() not in ("0", "false", "no", "off")


def retention_mode() -> str:
    """'disabled' | 'dry-run' | 'delete' (what the next run would do)."""
    if not retention_enabled():
        return "disabled"
    return "dry-run" if retention_dry_run() else "delete"


def _max_rows_per_run() -> int:
    return BATCH_SIZE * MAX_BATCHES


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


def _count_matching(model, predicate) -> int:
    """Dry-run: how many rows a real run would delete, capped like a real run."""
    return (
        db.session.query(model.id)
        .filter(predicate)
        .limit(_max_rows_per_run())
        .count()
    )


def _token_blacklist_predicate(now):
    return TokenBlacklist.expires_at < (now - TOKEN_EXPIRY_GRACE)


def _auth_token_predicates(now):
    cutoff = now - TOKEN_EXPIRY_GRACE
    return (
        ("password_reset", PasswordReset, PasswordReset.expires_at < cutoff),
        ("email_verification", EmailVerification, EmailVerification.expires_at < cutoff),
    )


def _user_action_predicate(days: int, now):
    return (UserAction.created_at < now - timedelta(days=days)) & ~UserAction.action_type.like(
        "admin\\_%", escape="\\"
    )


def _read_notification_predicate(days: int, now):
    return (Notification.is_read.is_(True)) & (Notification.created_at < now - timedelta(days=days))


def purge_expired_token_blacklist(now=None) -> int:
    now = now or utcnow()
    return _delete_in_batches(TokenBlacklist, _token_blacklist_predicate(now))


def purge_expired_auth_tokens(now=None) -> dict:
    """Delete password-reset / email-verification rows that expired > TOKEN_EXPIRY_GRACE ago.

    Used and unused rows alike: past expiry neither can ever be redeemed (every
    redeem path checks ``expires_at``), so this is behaviour-neutral apart from the
    error text for a long-expired code ("Invalid or expired token" instead of
    "Token has expired"). Also removes any leftover pre-F-29 plaintext reset rows.
    """
    now = now or utcnow()
    return {key: _delete_in_batches(model, pred) for key, model, pred in _auth_token_predicates(now)}


def purge_old_user_actions(days: int, now=None) -> int:
    now = now or utcnow()
    return _delete_in_batches(UserAction, _user_action_predicate(days, now))


def purge_old_read_notifications(days: int, now=None) -> int:
    now = now or utcnow()
    return _delete_in_batches(Notification, _read_notification_predicate(days, now))


def _plan(now) -> tuple[list[tuple[str, object, object]], list[str]]:
    """(configured jobs as (result key, model, predicate), names of jobs skipped for lack of config)."""
    jobs: list[tuple[str, object, object]] = []
    skipped: list[str] = []
    if _flag_env("RETENTION_TOKEN_BLACKLIST_PURGE"):
        jobs.append(("token_blacklist", TokenBlacklist, _token_blacklist_predicate(now)))
    if _flag_env("RETENTION_AUTH_TOKEN_PURGE"):
        jobs.extend(_auth_token_predicates(now))
    days = _positive_int_env("RETENTION_USER_ACTION_DAYS")
    if days:
        jobs.append(("user_action", UserAction, _user_action_predicate(days, now)))
    else:
        skipped.append("user_action (RETENTION_USER_ACTION_DAYS unset or invalid)")
    days = _positive_int_env("RETENTION_READ_NOTIFICATION_DAYS")
    if days:
        jobs.append(("read_notifications", Notification, _read_notification_predicate(days, now)))
    else:
        skipped.append("read_notifications (RETENTION_READ_NOTIFICATION_DAYS unset or invalid)")
    return jobs, skipped


def _audit(mode: str, counts: dict, skipped: list[str], error: str | None) -> None:
    """One append-only audit row per enabled run. Never raises (see log_admin_action)."""
    from .auth import log_admin_action

    # A list of {job, rows} rather than a {job: rows} dict: audit_safe_metadata redacts
    # the VALUE of any key that looks personal-data-ish ("token_blacklist", "password_reset"...).
    metadata = {
        "mode": mode,
        "jobs": [{"job": k, "rows": v} for k, v in counts.items()],
        "skipped_unconfigured": skipped,
        "batch_size": BATCH_SIZE,
        "max_batches": MAX_BATCHES,
    }
    if error:
        metadata["error"] = error
    log_admin_action(None, AUDIT_ACTION, target_type="retention", metadata=metadata)


def run_retention(now=None) -> dict:
    """Run the enabled cleanups. Returns per-job counts (empty dict when disabled).

    In dry-run mode the counts are what WOULD be deleted (nothing is modified). A
    failure stops the run, is recorded in the audit log together with the partial
    counts, and is re-raised so the task is marked failed.
    """
    if not retention_enabled():
        logger.info("retention run: disabled (RETENTION_ENABLED not set) - no-op")
        return {}
    now = now or utcnow()
    dry_run = retention_dry_run()
    mode = "dry-run" if dry_run else "delete"
    jobs, skipped = _plan(now)
    counts: dict = {}
    try:
        for key, model, predicate in jobs:
            counts[key] = _count_matching(model, predicate) if dry_run else _delete_in_batches(model, predicate)
    except Exception as exc:
        db.session.rollback()
        logger.exception("retention run (%s) FAILED after %s", mode, counts)
        _audit(mode, counts, skipped, f"{type(exc).__name__}")
        raise
    if skipped:
        logger.warning("retention run: skipped unconfigured jobs: %s", "; ".join(skipped))
    logger.info(
        "retention run (%s): %s",
        mode,
        counts or "no job configured (enabled but nothing to do)",
    )
    _audit(mode, counts, skipped, None)
    return counts
