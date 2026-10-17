"""Auto-moderation settings, mode resolution and the global kill switch.

Where things live
-----------------
* Operational settings (mode, kill switch, thresholds, alert routing) are one
  JSON document in the existing ``app_setting`` table under the key
  ``auto_moderation`` -- editable from the admin dashboard, no schema change.
* Secrets and infrastructure switches are environment-only and are NEVER
  stored in the database or returned by the API (only "is it configured"):

  ``AUTO_MODERATION_DISABLED=1``      hard off: nothing is evaluated at all.
  ``AUTO_MODERATION_KILL_SWITCH=1``   forces the kill switch ON (cannot be
                                      cleared from the dashboard).
  ``AUTO_MODERATION_ALLOW_LIVE=1``    required before ``live`` can take
                                      effect. Unset by default, so a fresh
                                      deployment can never publish
                                      automatically, whatever the dashboard
                                      says.
  ``AUTO_MODERATION_AI_PROVIDER``     ``none`` (default) | ``openai`` |
                                      ``anthropic`` | ``stub`` (tests/dev).
  ``AUTO_MODERATION_AI_MODEL``        model name for the provider.
  ``AUTO_MODERATION_OPENAI_API_KEY``  (falls back to ``OPENAI_API_KEY``)
  ``AUTO_MODERATION_ANTHROPIC_API_KEY``
  ``AUTO_MODERATION_TELEGRAM_BOT_TOKEN`` / ``AUTO_MODERATION_TELEGRAM_CHAT_ID``
  ``AUTO_MODERATION_ALERT_EMAILS``    comma separated default recipients.
  ``ADMIN_WEB_BASE_URL``              used to build deep links in alerts.

Modes
-----
``off``     nothing is evaluated.
``shadow``  (default) every eligible listing / pending edit is evaluated and
            the decision is recorded and compared with what a human later
            does. NOTHING is ever published or changed.
``live``    an ``AUTO_APPROVE`` decision is applied through the same code
            that manual approval uses. Only effective when the environment
            allows it AND the kill switch is off.

The thresholds in ``DEFAULTS`` (minimum sample sizes, tolerated unsafe-approval
rate, price bounds ...) are operator policy, not claims about how accurate the
engine or any AI provider is. Accuracy is whatever the shadow report measures.
"""

from __future__ import annotations

import copy
import os
import re
from typing import Any

from ..time_utils import utcnow

SETTINGS_KEY = "auto_moderation"

MODES = ("off", "shadow", "live")

DEFAULTS: dict[str, Any] = {
    "mode": "shadow",
    "kill_switch": False,
    "kill_switch_reason": None,
    "kill_switch_by": None,
    "kill_switch_at": None,
    # Per-subject switches (only relevant in live mode).
    "auto_approve_new_listings": True,
    "auto_approve_revisions": True,
    # Image relevance / text prohibition cannot be verified by rules alone. With
    # this on (default) nothing is auto-approved unless an AI provider actually
    # returned a clean advisory result.
    "require_ai_for_auto_approve": True,
    # Rule thresholds.
    "min_photos": 1,
    "min_image_side_px": 320,
    "min_year": 1950,
    "max_mileage": 1_000_000,
    "currency_price_bounds": {
        "USD": [500, 1_000_000],
        "IQD": [500_000, 1_400_000_000],
    },
    "max_listings_per_24h": 5,
    "price_change_review_pct": 50,
    "flag_contact_in_description": True,
    # Seller requirements: an approved dealer, or a phone-verified seller with
    # at least this many listings already approved by a human.
    "min_seller_prior_approved": 1,
    "dealers_count_as_trusted": True,
    # Payment: this codebase has no listing-payment ledger. When True, nothing
    # is auto-approved because payment cannot be verified (fail safe).
    "listing_payment_required": False,
    "ai": {
        "send_images": True,
        "max_images": 4,
        "timeout_seconds": 20,
        "min_confidence": 0.7,
        # Cost control: only call the provider for subjects that rules alone
        # would still approve. Set false to also collect AI verdicts for
        # flagged listings (useful for measuring the provider in shadow mode).
        "only_if_candidate": True,
    },
    "retry": {
        "max_attempts": 5,
        "backoff_seconds": [60, 300, 900, 1800, 3600],
        # A recorded decision older than this is never applied (re-evaluated).
        "apply_max_age_seconds": 900,
    },
    "alerts": {
        "enabled": False,
        "channels": ["email"],  # email | telegram
        "email_recipients": [],
        "include_shadow": False,
        # Alert for routine reasons (e.g. brand-new seller) too, not only for
        # suspicious signals.
        "alert_on_routine": False,
        "notify_on_hold": False,
        "max_per_hour": 30,
    },
    # Preconditions for enabling live mode (policy knobs, not accuracy claims).
    "gate": {
        "window_days": 90,
        "min_samples": 100,
        "max_unsafe_approve_rate": 0.02,
    },
}

_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def _env_bool(name: str) -> bool:
    return (os.environ.get(name) or "").strip().lower() in ("1", "true", "yes", "on")


def env_disabled() -> bool:
    return _env_bool("AUTO_MODERATION_DISABLED")


def env_kill_switch() -> bool:
    return _env_bool("AUTO_MODERATION_KILL_SWITCH")


def env_allow_live() -> bool:
    return _env_bool("AUTO_MODERATION_ALLOW_LIVE")


def ai_provider_name() -> str:
    return (os.environ.get("AUTO_MODERATION_AI_PROVIDER") or "none").strip().lower()


def ai_model_name() -> str | None:
    return (os.environ.get("AUTO_MODERATION_AI_MODEL") or "").strip() or None


def telegram_configured() -> bool:
    return bool(
        (os.environ.get("AUTO_MODERATION_TELEGRAM_BOT_TOKEN") or "").strip()
        and (os.environ.get("AUTO_MODERATION_TELEGRAM_CHAT_ID") or "").strip()
    )


def _deep_merge(base: dict, patch: dict) -> dict:
    out = copy.deepcopy(base)
    for k, v in (patch or {}).items():
        if isinstance(v, dict) and isinstance(out.get(k), dict) and k != "currency_price_bounds":
            out[k] = _deep_merge(out[k], v)
        else:
            out[k] = copy.deepcopy(v)
    return out


def _stored() -> dict:
    from ..app_settings import _ensure_table
    from ..models import AppSetting

    _ensure_table()
    try:
        row = AppSetting.query.filter_by(key=SETTINGS_KEY).first()
        if row and isinstance(row.value, dict):
            return dict(row.value)
    except Exception:
        pass
    return {}


def load_settings() -> dict[str, Any]:
    """Effective settings: defaults overlaid with the stored document.
    Anything malformed falls back to the safe default for that key."""
    merged = _deep_merge(DEFAULTS, _stored())
    if merged.get("mode") not in MODES:
        merged["mode"] = DEFAULTS["mode"]
    return merged


def effective_mode(settings: dict[str, Any] | None = None) -> str:
    """The mode that is actually in force right now.

    The kill switch (dashboard OR environment) and a missing
    ``AUTO_MODERATION_ALLOW_LIVE`` both cap ``live`` down to ``shadow``;
    ``AUTO_MODERATION_DISABLED`` / mode ``off`` stop evaluation entirely.
    """
    if env_disabled():
        return "off"
    s = settings if settings is not None else load_settings()
    mode = s.get("mode") if s.get("mode") in MODES else "shadow"
    if mode == "live" and (
        s.get("kill_switch") or env_kill_switch() or not env_allow_live()
    ):
        return "shadow"
    return mode


def kill_switch_active(settings: dict[str, Any] | None = None) -> bool:
    s = settings if settings is not None else load_settings()
    return bool(s.get("kill_switch")) or env_kill_switch()


# ---------------------------------------------------------------------------
# Validation of admin-supplied changes
# ---------------------------------------------------------------------------


def _int(v, lo, hi, name):
    try:
        n = int(v)
    except (TypeError, ValueError):
        raise ValueError(f"{name} must be an integer")
    if n < lo or n > hi:
        raise ValueError(f"{name} must be between {lo} and {hi}")
    return n


def _float(v, lo, hi, name):
    try:
        n = float(v)
    except (TypeError, ValueError):
        raise ValueError(f"{name} must be a number")
    if n < lo or n > hi:
        raise ValueError(f"{name} must be between {lo} and {hi}")
    return n


def _bool(v, name):
    if isinstance(v, bool):
        return v
    raise ValueError(f"{name} must be true or false")


def validate_patch(patch: dict) -> dict:
    """Validate + normalise a settings patch from the dashboard. Unknown keys
    are rejected. The kill switch has its own endpoint and ``mode`` is
    validated (and gated) by the caller; both are accepted here only so a
    single PUT can carry them."""
    if not isinstance(patch, dict):
        raise ValueError("JSON object required")
    out: dict[str, Any] = {}
    for key, val in patch.items():
        if key == "mode":
            if val not in MODES:
                raise ValueError("mode must be one of off, shadow, live")
            out[key] = val
        elif key in (
            "auto_approve_new_listings",
            "auto_approve_revisions",
            "require_ai_for_auto_approve",
            "dealers_count_as_trusted",
            "listing_payment_required",
            "flag_contact_in_description",
        ):
            out[key] = _bool(val, key)
        elif key == "min_photos":
            out[key] = _int(val, 0, 30, key)
        elif key == "min_image_side_px":
            out[key] = _int(val, 0, 4000, key)
        elif key == "min_year":
            out[key] = _int(val, 1886, 2100, key)
        elif key == "max_mileage":
            out[key] = _int(val, 1000, 10_000_000, key)
        elif key == "max_listings_per_24h":
            out[key] = _int(val, 1, 500, key)
        elif key == "price_change_review_pct":
            out[key] = _int(val, 1, 10_000, key)
        elif key == "min_seller_prior_approved":
            out[key] = _int(val, 0, 1000, key)
        elif key == "currency_price_bounds":
            if not isinstance(val, dict) or not val:
                raise ValueError("currency_price_bounds must be an object")
            bounds = {}
            for cur, pair in val.items():
                c = str(cur).strip().upper()
                if len(c) != 3 or not c.isalpha():
                    raise ValueError("currency codes must be 3 letters")
                if not isinstance(pair, (list, tuple)) or len(pair) != 2:
                    raise ValueError("each currency bound must be [min, max]")
                lo = _float(pair[0], 0, 1e12, f"{c} min")
                hi = _float(pair[1], 0, 1e13, f"{c} max")
                if lo >= hi:
                    raise ValueError(f"{c}: min must be below max")
                bounds[c] = [lo, hi]
            out[key] = bounds
        elif key == "ai":
            if not isinstance(val, dict):
                raise ValueError("ai must be an object")
            ai: dict[str, Any] = {}
            for k, v in val.items():
                if k in ("send_images", "only_if_candidate"):
                    ai[k] = _bool(v, f"ai.{k}")
                elif k == "max_images":
                    ai[k] = _int(v, 0, 10, "ai.max_images")
                elif k == "timeout_seconds":
                    ai[k] = _int(v, 3, 60, "ai.timeout_seconds")
                elif k == "min_confidence":
                    ai[k] = _float(v, 0, 1, "ai.min_confidence")
                else:
                    raise ValueError(f"unknown ai setting: {k}")
            out[key] = ai
        elif key == "retry":
            if not isinstance(val, dict):
                raise ValueError("retry must be an object")
            r: dict[str, Any] = {}
            for k, v in val.items():
                if k == "max_attempts":
                    r[k] = _int(v, 1, 20, "retry.max_attempts")
                elif k == "apply_max_age_seconds":
                    r[k] = _int(v, 30, 86400, "retry.apply_max_age_seconds")
                elif k == "backoff_seconds":
                    if not isinstance(v, list) or not v or len(v) > 20:
                        raise ValueError("retry.backoff_seconds must be a short list")
                    r[k] = [_int(x, 5, 86400, "retry.backoff_seconds[]") for x in v]
                else:
                    raise ValueError(f"unknown retry setting: {k}")
            out[key] = r
        elif key == "alerts":
            if not isinstance(val, dict):
                raise ValueError("alerts must be an object")
            a: dict[str, Any] = {}
            for k, v in val.items():
                if k in ("enabled", "include_shadow", "alert_on_routine", "notify_on_hold"):
                    a[k] = _bool(v, f"alerts.{k}")
                elif k == "channels":
                    if not isinstance(v, list) or any(c not in ("email", "telegram") for c in v):
                        raise ValueError("alerts.channels must be a list of email / telegram")
                    a[k] = sorted(set(v))
                elif k == "email_recipients":
                    if not isinstance(v, list) or len(v) > 20:
                        raise ValueError("alerts.email_recipients must be a short list")
                    emails = [str(e).strip().lower() for e in v if str(e).strip()]
                    if any(not _EMAIL_RE.match(e) for e in emails):
                        raise ValueError("alerts.email_recipients contains an invalid address")
                    a[k] = emails
                elif k == "max_per_hour":
                    a[k] = _int(v, 1, 1000, "alerts.max_per_hour")
                else:
                    raise ValueError(f"unknown alerts setting: {k}")
            out[key] = a
        elif key == "gate":
            if not isinstance(val, dict):
                raise ValueError("gate must be an object")
            g: dict[str, Any] = {}
            for k, v in val.items():
                if k == "window_days":
                    g[k] = _int(v, 1, 730, "gate.window_days")
                elif k == "min_samples":
                    g[k] = _int(v, 1, 1_000_000, "gate.min_samples")
                elif k == "max_unsafe_approve_rate":
                    g[k] = _float(v, 0, 1, "gate.max_unsafe_approve_rate")
                else:
                    raise ValueError(f"unknown gate setting: {k}")
            out[key] = g
        else:
            raise ValueError(f"unknown setting: {key}")
    return out


def save_settings(patch: dict[str, Any]) -> dict[str, Any]:
    """Persist an already-validated patch (merged onto the stored document)
    and commit. Returns the new effective settings."""
    from ..app_settings import _ensure_table
    from ..models import AppSetting, db

    _ensure_table()
    row = AppSetting.query.filter_by(key=SETTINGS_KEY).with_for_update().first()
    current = dict(row.value) if row and isinstance(row.value, dict) else {}
    current = _deep_merge(current, patch)
    if row is None:
        db.session.add(AppSetting(key=SETTINGS_KEY, value=current, updated_at=utcnow()))
    else:
        row.value = current
        row.updated_at = utcnow()
    db.session.commit()
    return load_settings()


def set_kill_switch(enabled: bool, *, actor: str | None, reason: str | None) -> dict[str, Any]:
    return save_settings(
        {
            "kill_switch": bool(enabled),
            "kill_switch_reason": (reason or "").strip()[:300] or None,
            "kill_switch_by": actor,
            "kill_switch_at": utcnow().isoformat(),
        }
    )


def public_settings(settings: dict[str, Any] | None = None) -> dict[str, Any]:
    """Settings + environment status, safe to return to the dashboard (never
    includes a secret, only whether one is configured)."""
    s = settings if settings is not None else load_settings()
    return {
        "settings": s,
        "effective_mode": effective_mode(s),
        "kill_switch_active": kill_switch_active(s),
        "environment": {
            "disabled": env_disabled(),
            "kill_switch_forced": env_kill_switch(),
            "live_allowed": env_allow_live(),
            "ai_provider": ai_provider_name(),
            "ai_model": ai_model_name(),
            "ai_configured": ai_provider_configured(),
            "telegram_configured": telegram_configured(),
            "admin_web_base_url_configured": bool(
                (os.environ.get("ADMIN_WEB_BASE_URL") or "").strip()
            ),
        },
    }


def ai_provider_configured() -> bool:
    name = ai_provider_name()
    if name == "stub":
        # Test double that reports "everything is fine": it must be impossible
        # to leave it enabled in a real environment.
        return (os.environ.get("APP_ENV") or "").strip().lower() in ("testing", "test")
    if name == "openai":
        return bool(
            (os.environ.get("AUTO_MODERATION_OPENAI_API_KEY") or os.environ.get("OPENAI_API_KEY") or "").strip()
        )
    if name == "anthropic":
        return bool(
            (os.environ.get("AUTO_MODERATION_ANTHROPIC_API_KEY") or "").strip()
            and ai_model_name()
        )
    return False
