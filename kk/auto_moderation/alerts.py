"""Admin alerts when a listing needs a human (email and/or Telegram).

Privacy: an alert carries only the kind of subject, a short list of reason
labels, an opaque run id and a deep link into the admin dashboard. No seller
name / phone / e-mail, no listing title or description, no price, no photo.
Secrets (Telegram token, mail credentials) come from the environment, are
never stored in the database, never returned by the API and never logged (HTTP
errors are logged by exception class only -- the Telegram URL contains the
token).

Each run alerts at most once (``alerted_at`` is claimed with a compare-and-set
UPDATE) and a per-hour cap bounds the volume; suppressed alerts are logged as
events. Shadow-mode decisions only alert when ``alerts.include_shadow`` is on.
"""

from __future__ import annotations

import logging
import os
from datetime import timedelta

import requests
from sqlalchemy import update

from ..models import ListingModerationEvent, ListingModerationRun, db
from ..time_utils import utcnow
from .config import load_settings
from .engine import log_event

logger = logging.getLogger(__name__)

REASON_LABELS = {
    "scam_language": "possible scam wording",
    "prohibited_content": "prohibited content wording",
    "non_car_content": "text unrelated to cars",
    "repeated_characters": "spam-like text",
    "repetitive_text": "repetitive text",
    "duplicate_listing": "duplicate of the seller's other listing",
    "repeated_description": "description reused across listings",
    "vin_reused_own": "VIN reused by the same seller",
    "vin_other_seller": "VIN used by another seller",
    "high_posting_rate": "unusually many listings in 24h",
    "seller_open_reports": "seller has open reports",
    "seller_abuse_history": "seller has moderation history",
    "seller_inactive": "seller account restricted",
    "seller_missing": "seller account missing",
    "year_out_of_range": "year out of range",
    "mileage_out_of_range": "mileage out of range",
    "new_but_old_year": "'new' condition with an old year",
    "new_with_mileage": "'new' condition with mileage",
    "price_invalid": "invalid price",
    "price_out_of_range": "price outside expected range",
    "vin_invalid": "invalid VIN format",
    "cover_invalid": "cover photo problem",
    "cover_mismatch": "cover photo mismatch",
    "media_missing": "photo missing",
    "identity_changed": "vehicle identity edited",
    "large_price_change": "large price change",
    "ai_flagged": "flagged by the AI provider",
    "media_failed": "photo upload failed",
}


def _labels(reasons: list[dict], *, routine_too: bool) -> list[str]:
    out = []
    for r in reasons or []:
        if r.get("level") not in ("review", "hold"):
            continue
        if not routine_too and not r.get("suspicious") and r.get("code") != "media_failed":
            continue
        out.append(REASON_LABELS.get(r.get("code"), str(r.get("code")).replace("_", " ")))
    return list(dict.fromkeys(out))


def build_message(run: ListingModerationRun, labels: list[str]) -> tuple[str, str]:
    base = (os.environ.get("ADMIN_WEB_BASE_URL") or "").strip().rstrip("/")
    if run.subject_type == "revision" and run.revision_public_id:
        link = f"{base}/listing-edits/{run.revision_public_id}" if base else ""
        kind = "edit to a published listing"
    else:
        link = f"{base}/listings/{run.car_public_id}" if base and run.car_public_id else ""
        kind = "new listing"
    subject = "CarNet: a listing needs review"
    lines = [
        f"A {kind} needs a human decision.",
        "Reasons: " + ("; ".join(labels) if labels else "see dashboard"),
        f"Reference: {run.public_id[:8]}",
    ]
    if link:
        lines.append(f"Open: {link}")
    return subject, "\n".join(lines)


def _send_telegram(text: str) -> bool:
    token = (os.environ.get("AUTO_MODERATION_TELEGRAM_BOT_TOKEN") or "").strip()
    chat = (os.environ.get("AUTO_MODERATION_TELEGRAM_CHAT_ID") or "").strip()
    if not token or not chat:
        return False
    try:
        r = requests.post(
            f"https://api.telegram.org/bot{token}/sendMessage",
            json={"chat_id": chat, "text": text, "disable_web_page_preview": True},
            timeout=10,
        )
        return r.status_code == 200
    except Exception as exc:  # never log the URL: it contains the bot token
        logger.warning("moderation telegram alert failed: %s", type(exc).__name__)
        return False


def _send_email(recipients: list[str], subject: str, text: str) -> bool:
    from ..email_service import send_email

    ok = False
    for to in recipients:
        try:
            ok = bool(send_email(to, subject=subject, text_body=text)) or ok
        except Exception as exc:
            logger.warning("moderation email alert failed: %s", type(exc).__name__)
    return ok


def _recipients(alerts_cfg: dict) -> list[str]:
    configured = [e for e in (alerts_cfg.get("email_recipients") or []) if e]
    if configured:
        return configured
    env = os.environ.get("AUTO_MODERATION_ALERT_EMAILS") or ""
    return [e.strip().lower() for e in env.split(",") if "@" in e]


def send_alert_for_run(run_id: int) -> dict:
    settings = load_settings()
    cfg = settings.get("alerts") or {}
    if not cfg.get("enabled"):
        return {"sent": False, "reason": "disabled"}
    run = db.session.get(ListingModerationRun, run_id)
    if run is None or run.status != "completed":
        return {"sent": False, "reason": "not_found"}
    if run.mode == "shadow" and not cfg.get("include_shadow"):
        return {"sent": False, "reason": "shadow"}
    has_media_failed = any(r.get("code") == "media_failed" for r in (run.reasons or []))
    if not (
        run.decision == "NEEDS_REVIEW"
        or (run.decision == "HOLD" and cfg.get("notify_on_hold") and has_media_failed)
    ):
        return {"sent": False, "reason": "not_alertable"}
    labels = _labels(run.reasons or [], routine_too=bool(cfg.get("alert_on_routine")))
    if not labels:
        return {"sent": False, "reason": "routine_only"}

    # Claim: exactly one alert per run, even with duplicate jobs.
    res = db.session.execute(
        update(ListingModerationRun)
        .where(ListingModerationRun.id == run.id, ListingModerationRun.alerted_at.is_(None))
        .values(alerted_at=utcnow())
    )
    if res.rowcount != 1:
        db.session.rollback()
        return {"sent": False, "reason": "already_alerted"}

    cap = int(cfg.get("max_per_hour", 30))
    recent = ListingModerationEvent.query.filter(
        ListingModerationEvent.event_type == "alert_sent",
        ListingModerationEvent.created_at >= utcnow() - timedelta(hours=1),
    ).count()
    if recent >= cap:
        log_event(run, "alert_suppressed", data={"cap": cap})
        db.session.commit()
        return {"sent": False, "reason": "rate_capped"}
    db.session.commit()

    subject, text = build_message(run, labels)
    channels = cfg.get("channels") or ["email"]
    results: dict[str, bool] = {}
    if "email" in channels:
        results["email"] = _send_email(_recipients(cfg), subject, text)
    if "telegram" in channels:
        results["telegram"] = _send_telegram(text)
    run = db.session.get(ListingModerationRun, run_id)
    log_event(
        run,
        "alert_sent" if any(results.values()) else "alert_failed",
        data={"channels": results},
    )
    db.session.commit()
    return {"sent": any(results.values()), "channels": results}
