"""Platform settings stored in DB with env-var fallbacks."""

from __future__ import annotations

import logging
import os
from typing import Any

from .models import AppSetting, db
from .time_utils import utcnow

logger = logging.getLogger(__name__)

PLATFORM_KEY = "platform"

# Kill-switches exposed on GET /api/config/app as feature_flags (fail-open = true).
KNOWN_FEATURE_FLAGS = (
    "sell",
    "chat",
    "dealers",
    "comparison",
    "saved_searches",
)

SETTING_KEYS = (
    "app_name",
    "support_email",
    "support_phone",
    "support_whatsapp",
    "terms_url",
    "privacy_url",
    "legal_effective_date",
    "featured_listing_price",
    "featured_listing_currency",
    "dealer_subscription_price",
    "dealer_subscription_currency",
    "pricing_notes",
    "min_app_version",
    "min_android_build",
    "min_ios_build",
    "force_update_message",
    "recommended_app_version",
    "recommended_android_build",
    "recommended_ios_build",
    "soft_update_message",
    "android_store_url",
    "ios_store_url",
)


def _env(key: str, default: str = "") -> str:
    return (os.environ.get(key) or default).strip()


def _env_bool(key: str, default: bool = True) -> bool:
    raw = _env(key)
    if not raw:
        return default
    return raw.lower() in ("1", "true", "yes", "on")


def _coerce_bool(value: Any, default: bool = True) -> bool:
    if value is None:
        return default
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return bool(value)
    text = str(value).strip().lower()
    if text in ("1", "true", "yes", "on"):
        return True
    if text in ("0", "false", "no", "off"):
        return False
    return default


def default_feature_flags() -> dict[str, bool]:
    """Env defaults: FEATURE_FLAG_SELL=0 disables sell, etc. Missing → enabled."""
    return {
        name: _env_bool(f"FEATURE_FLAG_{name.upper()}", True)
        for name in KNOWN_FEATURE_FLAGS
    }


def get_feature_flags() -> dict[str, bool]:
    """Effective feature flags (env defaults + DB overrides). Fail-open."""
    merged = default_feature_flags()
    overrides = get_platform_overrides().get("feature_flags")
    if isinstance(overrides, dict):
        for name in KNOWN_FEATURE_FLAGS:
            if name in overrides:
                merged[name] = _coerce_bool(overrides[name], default=merged[name])
    return merged


def default_platform_settings() -> dict[str, Any]:
    """Env-driven defaults used when DB values are empty."""
    from .legal_pages import default_privacy_url, default_terms_url

    return {
        "app_name": _env("APP_DISPLAY_NAME", "CarNet"),
        "support_email": _env("SUPPORT_EMAIL", "support@carzo.app"),
        "support_phone": _env("SUPPORT_PHONE", ""),
        "support_whatsapp": _env("SUPPORT_WHATSAPP", ""),
        "terms_url": _env("TERMS_URL", "") or default_terms_url(),
        "privacy_url": _env("PRIVACY_URL", "") or default_privacy_url(),
        "legal_effective_date": _env("LEGAL_EFFECTIVE_DATE", ""),
        "featured_listing_price": None,
        "featured_listing_currency": _env("FEATURED_LISTING_CURRENCY", "USD"),
        "dealer_subscription_price": None,
        "dealer_subscription_currency": _env("DEALER_SUBSCRIPTION_CURRENCY", "USD"),
        "pricing_notes": "",
        "min_app_version": _env("MIN_APP_VERSION", ""),
        "min_android_build": _env("MIN_ANDROID_BUILD", ""),
        "min_ios_build": _env("MIN_IOS_BUILD", ""),
        "force_update_message": _env(
            "FORCE_UPDATE_MESSAGE",
            "Please update CarNet to continue.",
        ),
        "recommended_app_version": _env("RECOMMENDED_APP_VERSION", ""),
        "recommended_android_build": _env("RECOMMENDED_ANDROID_BUILD", ""),
        "recommended_ios_build": _env("RECOMMENDED_IOS_BUILD", ""),
        "soft_update_message": _env(
            "SOFT_UPDATE_MESSAGE",
            "A newer version of CarNet is available.",
        ),
        "android_store_url": _env(
            "ANDROID_STORE_URL",
            "https://play.google.com/store/apps/details?id=com.carzo.app",
        ),
        "ios_store_url": _env("IOS_STORE_URL", ""),
        "feature_flags": default_feature_flags(),
    }


def _ensure_table() -> None:
    """Create app_setting if migrations have not run yet (best-effort)."""
    try:
        from sqlalchemy import inspect

        insp = inspect(db.engine)
        if not insp.has_table("app_setting"):
            AppSetting.__table__.create(db.engine, checkfirst=True)
    except Exception as exc:
        logger.debug("app_setting ensure_table skipped: %s", exc)


def get_platform_overrides() -> dict[str, Any]:
    _ensure_table()
    try:
        row = AppSetting.query.filter_by(key=PLATFORM_KEY).first()
        if row and isinstance(row.value, dict):
            return dict(row.value)
    except Exception as exc:
        logger.warning("get_platform_overrides failed: %s", exc)
    return {}


def get_platform_settings() -> dict[str, Any]:
    """Merged effective settings: defaults overwritten by non-empty DB values."""
    merged = default_platform_settings()
    overrides = get_platform_overrides()
    for key in SETTING_KEYS:
        if key not in overrides:
            continue
        val = overrides[key]
        if val is None:
            continue
        if isinstance(val, str) and not val.strip():
            continue
        merged[key] = val
    merged["feature_flags"] = get_feature_flags()
    return merged


def get_admin_settings_payload() -> dict[str, Any]:
    defaults = default_platform_settings()
    overrides = get_platform_overrides()
    effective = get_platform_settings()
    updated_at = None
    try:
        row = AppSetting.query.filter_by(key=PLATFORM_KEY).first()
        if row and row.updated_at:
            updated_at = row.updated_at.isoformat()
    except Exception:
        pass
    flag_overrides = overrides.get("feature_flags")
    return {
        "defaults": defaults,
        "overrides": {
            **{k: overrides.get(k) for k in SETTING_KEYS},
            "feature_flags": flag_overrides if isinstance(flag_overrides, dict) else {},
        },
        "effective": effective,
        "feature_flags": effective.get("feature_flags") or default_feature_flags(),
        "known_feature_flags": list(KNOWN_FEATURE_FLAGS),
        "updated_at": updated_at,
    }


def _coerce_price(value: Any) -> float | None:
    if value is None or value == "":
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def update_platform_settings(patch: dict[str, Any]) -> dict[str, Any]:
    """Upsert platform overrides. Empty strings clear an override (fall back to env)."""
    _ensure_table()
    row = AppSetting.query.filter_by(key=PLATFORM_KEY).first()
    current = dict(row.value) if row and isinstance(row.value, dict) else {}

    for key in SETTING_KEYS:
        if key not in patch:
            continue
        val = patch[key]
        if key in ("featured_listing_price", "dealer_subscription_price"):
            coerced = _coerce_price(val)
            if coerced is None:
                current.pop(key, None)
            else:
                current[key] = coerced
            continue
        if val is None:
            current.pop(key, None)
            continue
        text = str(val).strip()
        if not text:
            current.pop(key, None)
        else:
            current[key] = text

    if "feature_flags" in patch:
        val = patch["feature_flags"]
        if val is None or val == "":
            current.pop("feature_flags", None)
        elif isinstance(val, dict):
            if not val:
                current.pop("feature_flags", None)
            else:
                flags = dict(current.get("feature_flags") or {})
                for name in KNOWN_FEATURE_FLAGS:
                    if name not in val:
                        continue
                    flags[name] = _coerce_bool(val[name], default=True)
                current["feature_flags"] = flags

    if row is None:
        row = AppSetting(key=PLATFORM_KEY, value=current, updated_at=utcnow())
        db.session.add(row)
    else:
        row.value = current
        row.updated_at = utcnow()
    db.session.commit()
    return get_admin_settings_payload()
