"""Platform settings stored in DB with env-var fallbacks."""

from __future__ import annotations

import logging
import os
import re
from typing import Any
from urllib.parse import urlsplit

from .models import AppSetting, db
from .time_utils import iso_utc, utcnow

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
    # MI-03: additive, per-locale overrides for the force-update message.
    # The existing English key/behavior above is unchanged; these are only
    # consulted for ar/ku requests (see get_localized_platform_message()
    # and GET /api/config/app in kk/routes/misc.py). Never renamed/removed.
    "force_update_message_ar",
    "force_update_message_ku",
    "recommended_app_version",
    "recommended_android_build",
    "recommended_ios_build",
    # Force-update hardening: additive "latest published version" marker.
    # Never required; when set it bounds every version floor (a floor above
    # the latest published release can never be satisfied) and lets clients
    # that already run the latest release skip a hard block.
    "latest_app_version",
    "soft_update_message",
    "soft_update_message_ar",
    "soft_update_message_ku",
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
        # No fake fallback mailbox: SUPPORT_EMAIL is required in production
        # (enforced by validate_required_secrets() in kk/config.py). In
        # development/testing where it may be unset, this is simply empty --
        # never a placeholder address that could silently swallow real
        # support/account-deletion emails.
        "support_email": _env("SUPPORT_EMAIL", ""),
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
        # MI-03: optional admin-configured ar/ku overrides. Empty by default
        # -- get_localized_platform_message() falls back to the built-in
        # translated text (kk.localization.translate) when unset.
        "force_update_message_ar": _env("FORCE_UPDATE_MESSAGE_AR", ""),
        "force_update_message_ku": _env("FORCE_UPDATE_MESSAGE_KU", ""),
        "recommended_app_version": _env("RECOMMENDED_APP_VERSION", ""),
        "recommended_android_build": _env("RECOMMENDED_ANDROID_BUILD", ""),
        "recommended_ios_build": _env("RECOMMENDED_IOS_BUILD", ""),
        "latest_app_version": _env("LATEST_APP_VERSION", ""),
        "soft_update_message": _env(
            "SOFT_UPDATE_MESSAGE",
            "A newer version of CarNet is available.",
        ),
        "soft_update_message_ar": _env("SOFT_UPDATE_MESSAGE_AR", ""),
        "soft_update_message_ku": _env("SOFT_UPDATE_MESSAGE_KU", ""),
        "android_store_url": _env(
            "ANDROID_STORE_URL",
            "https://play.google.com/store/apps/details?id=com.carnetiq.app",
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


def get_localized_platform_message(
    base_key: str, locale: str | None, settings: dict[str, Any] | None = None
) -> str:
    """MI-03: locale-aware value for a message-type SETTING_KEY (currently
    ``force_update_message`` / ``soft_update_message``).

    English is completely unchanged: the existing ``base_key`` DB
    override/env default is used exactly as before. For ar/ku, an additive
    ``{base_key}_{locale}`` admin override is preferred; if unset/blank, a
    built-in translated fallback (``kk.localization.translate``) is used --
    this string is never empty.
    """
    from .localization import normalize_locale, translate

    s = settings if settings is not None else get_platform_settings()
    normalized = normalize_locale(locale) or "en"
    if normalized == "en":
        value = s.get(base_key)
        text = str(value).strip() if value is not None else ""
        return text or translate(base_key, "en")

    override = s.get(f"{base_key}_{normalized}")
    if isinstance(override, str) and override.strip():
        return override.strip()
    return translate(base_key, normalized)


def get_admin_settings_payload() -> dict[str, Any]:
    defaults = default_platform_settings()
    overrides = get_platform_overrides()
    effective = get_platform_settings()
    updated_at = None
    try:
        row = AppSetting.query.filter_by(key=PLATFORM_KEY).first()
        if row and row.updated_at:
            updated_at = iso_utc(row.updated_at)
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


# ---------------------------------------------------------------------------
# Force-update hardening: strict parsing / validation of the version-gate
# settings. A malformed value must never reach clients as a hard floor.
# ---------------------------------------------------------------------------

VERSION_SETTING_KEYS = (
    "min_app_version",
    "recommended_app_version",
    "latest_app_version",
)
# Max sane value per build-number field. Android versionCode tops out at
# 2_100_000_000 (Play Store limit). iOS CFBundleVersion is built from the last
# <= 18 digits of the Codemagic build id (codemagic.yaml), so 18 digits is the
# ceiling there.
BUILD_SETTING_LIMITS = {
    "min_android_build": 2_100_000_000,
    "recommended_android_build": 2_100_000_000,
    "min_ios_build": 10**18 - 1,
    "recommended_ios_build": 10**18 - 1,
}
STORE_URL_SETTING_KEYS = ("android_store_url", "ios_store_url")

_VERSION_RE = re.compile(r"[0-9]{1,4}(?:\.[0-9]{1,4}){0,3}")
_BUILD_RE = re.compile(r"[0-9]{1,18}")
# A floor whose major component is above this is a typo (e.g. 999.0.0), not a
# release: the apps are on 1.x.
MAX_VERSION_MAJOR = 99
_STORE_URL_SCHEMES = ("http", "https", "market", "itms-apps", "itms-appss")
_STORE_URL_MAX_LEN = 2048
_DEFAULT_ANDROID_STORE_URL = (
    "https://play.google.com/store/apps/details?id=com.carnetiq.app"
)


class SettingsValidationError(ValueError):
    """Raised by :func:`update_platform_settings` for a rejected value."""

    def __init__(self, field: str, message: str):
        super().__init__(message)
        self.field = field
        self.message = message


def parse_version(value: Any) -> tuple[int, ...] | None:
    """Strict ``N[.N[.N[.N]]]`` parser; ``None`` for anything else.

    Only real strings are accepted (a JSON number/list/bool is a wrong type),
    components are 1-4 ASCII digits, and the major component is capped at
    :data:`MAX_VERSION_MAJOR`. ``"v2"``, ``"1.x"``, ``"-1.0"``, ``""`` and
    ``"1.0.0-beta"`` are all rejected.
    """
    if not isinstance(value, str):
        return None
    text = value.strip()
    if not _VERSION_RE.fullmatch(text):
        return None
    parts = tuple(int(p) for p in text.split("."))
    if parts[0] > MAX_VERSION_MAJOR:
        return None
    return parts


def _version_cmp(a: tuple[int, ...], b: tuple[int, ...]) -> int:
    n = max(len(a), len(b))
    pa = a + (0,) * (n - len(a))
    pb = b + (0,) * (n - len(b))
    return (pa > pb) - (pa < pb)


def canonical_version(parts: tuple[int, ...]) -> str:
    return ".".join(str(p) for p in parts)


def parse_build_number(value: Any, maximum: int) -> int | None:
    """Non-negative integer build number or ``None`` (bool/float/negative/huge)."""
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        number = value
    elif isinstance(value, str):
        text = value.strip()
        if not _BUILD_RE.fullmatch(text):
            return None
        number = int(text)
    else:
        return None
    if number < 0 or number > maximum:
        return None
    return number


def sanitize_store_url(value: Any) -> str:
    """Return a safe store URL (http/https/market/itms-apps) or ``""``."""
    if not isinstance(value, str):
        return ""
    text = value.strip()
    if not text or len(text) > _STORE_URL_MAX_LEN:
        return ""
    if any(ch.isspace() or ord(ch) < 32 for ch in text):
        return ""
    try:
        parts = urlsplit(text)
    except ValueError:
        return ""
    if parts.scheme.lower() not in _STORE_URL_SCHEMES or not parts.netloc:
        return ""
    return text


_warned_bad_values: set[tuple[str, str]] = set()


def _warn_bad_stored_value(key: str, value: Any) -> None:
    marker = (key, repr(value)[:80])
    if marker in _warned_bad_values or len(_warned_bad_values) > 200:
        return
    _warned_bad_values.add(marker)
    logger.warning(
        "app config: ignoring invalid stored %s=%r (served as unset)",
        key,
        str(value)[:80],
    )


def public_version_gate_settings(s: dict[str, Any]) -> dict[str, Any]:
    """Version-gate fields for ``GET /api/config/app`` with garbage removed.

    Read-side safety net: whatever is stored (DB override or env) a malformed
    or unsatisfiable floor is served as *unset* so it can never lock anyone
    out. Same field names / types as always (``str`` versions, ``int|None``
    builds, ``str`` URLs); only ``latest_app_version`` is new (additive).
    """
    out: dict[str, Any] = {}

    def _version(key: str) -> tuple[int, ...] | None:
        raw = s.get(key)
        if raw is None or (isinstance(raw, str) and not raw.strip()):
            return None
        parsed = parse_version(raw)
        if parsed is None:
            _warn_bad_stored_value(key, raw)
        return parsed

    latest = _version("latest_app_version")
    floor = _version("min_app_version")
    recommended = _version("recommended_app_version")
    if floor is not None and latest is not None and _version_cmp(floor, latest) > 0:
        _warn_bad_stored_value("min_app_version(>latest)", s.get("min_app_version"))
        floor = None

    out["min_app_version"] = canonical_version(floor) if floor else ""
    out["recommended_app_version"] = (
        canonical_version(recommended) if recommended else ""
    )
    out["latest_app_version"] = canonical_version(latest) if latest else ""

    for key, maximum in BUILD_SETTING_LIMITS.items():
        raw = s.get(key)
        if raw is None or (isinstance(raw, str) and not raw.strip()):
            out[key] = None
            continue
        parsed = parse_build_number(raw, maximum)
        if parsed is None:
            _warn_bad_stored_value(key, raw)
        out[key] = parsed

    for key in STORE_URL_SETTING_KEYS:
        raw = s.get(key)
        if raw is None or (isinstance(raw, str) and not raw.strip()):
            out[key] = ""
            continue
        url = sanitize_store_url(raw)
        if not url:
            _warn_bad_stored_value(key, raw)
        out[key] = url
    if not out["android_store_url"]:
        out["android_store_url"] = _DEFAULT_ANDROID_STORE_URL
    return out


def _validate_version_gate_patch(
    patch: dict[str, Any], current: dict[str, Any]
) -> dict[str, Any]:
    """Validate + normalise the version-gate keys present in *patch*.

    Returns ``{key: normalised value or None (= clear)}``; raises
    :class:`SettingsValidationError` (-> HTTP 400) on the first bad value.
    """
    normalised: dict[str, Any] = {}

    def _blank(val: Any) -> bool:
        return val is None or (isinstance(val, str) and not val.strip())

    for key in VERSION_SETTING_KEYS:
        if key not in patch:
            continue
        val = patch[key]
        if _blank(val):
            normalised[key] = None
            continue
        if not isinstance(val, str):
            raise SettingsValidationError(key, f"{key} must be a string like 1.2.3")
        parsed = parse_version(val)
        if parsed is None:
            raise SettingsValidationError(
                key,
                f"{key} must look like 1.2.3 (digits and dots only, "
                f"major <= {MAX_VERSION_MAJOR}); got {val.strip()[:40]!r}",
            )
        normalised[key] = canonical_version(parsed)

    for key, maximum in BUILD_SETTING_LIMITS.items():
        if key not in patch:
            continue
        val = patch[key]
        if _blank(val):
            normalised[key] = None
            continue
        parsed_build = parse_build_number(val, maximum)
        if parsed_build is None:
            raise SettingsValidationError(
                key,
                f"{key} must be a whole number between 0 and {maximum}; "
                f"got {str(val).strip()[:40]!r}",
            )
        normalised[key] = str(parsed_build)

    for key in STORE_URL_SETTING_KEYS:
        if key not in patch:
            continue
        val = patch[key]
        if _blank(val):
            normalised[key] = None
            continue
        url = sanitize_store_url(val)
        if not url:
            raise SettingsValidationError(
                key,
                f"{key} must be an absolute http(s)/market/itms-apps URL "
                "without spaces",
            )
        normalised[key] = url

    # Cross-check: a floor above the latest published release can never be
    # satisfied (every user would be blocked with nothing to install).
    if "min_app_version" in normalised or "latest_app_version" in normalised:
        defaults = default_platform_settings()

        def _effective(key: str) -> tuple[int, ...] | None:
            if key in normalised:
                raw = normalised[key]
                if raw is None:
                    raw = defaults.get(key)
            else:
                raw = current.get(key)
                if raw is None or (isinstance(raw, str) and not raw.strip()):
                    raw = defaults.get(key)
            return parse_version(raw)

        floor = _effective("min_app_version")
        latest = _effective("latest_app_version")
        if floor is not None and latest is not None and _version_cmp(floor, latest) > 0:
            field = (
                "min_app_version"
                if "min_app_version" in normalised
                else "latest_app_version"
            )
            raise SettingsValidationError(
                field,
                f"min_app_version ({canonical_version(floor)}) cannot be above "
                f"latest_app_version ({canonical_version(latest)}): users could "
                "never satisfy it",
            )
    return normalised


def update_platform_settings(patch: dict[str, Any]) -> dict[str, Any]:
    """Upsert platform overrides. Empty strings clear an override (fall back to env).

    Raises :class:`SettingsValidationError` (before anything is written) for a
    malformed version / build / store-URL value.
    """
    _ensure_table()
    row = AppSetting.query.filter_by(key=PLATFORM_KEY).first()
    current = dict(row.value) if row and isinstance(row.value, dict) else {}

    normalised = _validate_version_gate_patch(patch, current)
    if normalised:
        patch = {**patch, **normalised}

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
