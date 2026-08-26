"""Normalize and validate public dealership social profile links."""

from __future__ import annotations

import json
import re
from urllib.parse import quote_plus, unquote, urlparse, urlunparse

SOCIAL_KEYS = ("facebook", "instagram", "tiktok")
_MAX_URL_LEN = 300

_HOSTS: dict[str, frozenset[str]] = {
    "facebook": frozenset(
        {
            "facebook.com",
            "www.facebook.com",
            "m.facebook.com",
            "web.facebook.com",
            "fb.com",
            "fb.me",
        }
    ),
    "instagram": frozenset({"instagram.com", "www.instagram.com"}),
    "tiktok": frozenset(
        {
            "tiktok.com",
            "www.tiktok.com",
            "m.tiktok.com",
            "vm.tiktok.com",
            "vt.tiktok.com",
        }
    ),
}

_FACEBOOK_VANITY_RE = re.compile(r"^[A-Za-z0-9.]{1,80}$")
_HANDLE_RE: dict[str, re.Pattern[str]] = {
    "facebook": re.compile(r"^[\w._'\-& ]{1,80}$", re.UNICODE),
    "instagram": re.compile(r"^[A-Za-z0-9._]{1,30}$"),
    "tiktok": re.compile(r"^[A-Za-z0-9._]{2,24}$"),
}

_CANONICAL = {
    "facebook": "https://www.facebook.com/{handle}",
    "instagram": "https://www.instagram.com/{handle}",
    "tiktok": "https://www.tiktok.com/@{handle}",
}

_PLATFORM_LABEL = {
    "facebook": "Facebook",
    "instagram": "Instagram",
    "tiktok": "TikTok",
}

_INVALID_SCHEMES = frozenset({"javascript", "data", "file", "vbscript"})


def public_dealership_socials(raw) -> dict[str, str]:
    """Return only known, non-empty social URLs for API payloads."""
    parsed = _coerce_map(raw)
    out: dict[str, str] = {}
    for key in SOCIAL_KEYS:
        val = str(parsed.get(key) or "").strip()
        if val:
            out[key] = val
    return out


def clean_dealership_socials(raw) -> tuple[dict[str, str] | None, str | None]:
    """Validate a dealer socials payload.

    Returns (cleaned_dict, None) on success. An empty dict means "clear all".
    Returns (None, message) when a value is present but invalid.
    """
    parsed = _coerce_map(raw)
    if parsed is None and raw not in (None, "", {}, []):
        return None, "Invalid social media format"

    cleaned: dict[str, str] = {}
    source = parsed or {}
    for key in SOCIAL_KEYS:
        if key not in source and f"dealership_{key}" not in source:
            continue
        value = source.get(key, source.get(f"dealership_{key}"))
        text = "" if value is None else str(value).strip()
        if not text:
            continue
        url = _normalize_one(key, text)
        if not url:
            label = _PLATFORM_LABEL[key]
            return None, f"Enter a valid {label} link"
        cleaned[key] = url
    return cleaned, None


def _coerce_map(raw) -> dict | None:
    if raw is None:
        return {}
    if isinstance(raw, str):
        text = raw.strip()
        if not text:
            return {}
        try:
            decoded = json.loads(text)
        except Exception:
            return None
        raw = decoded
    if isinstance(raw, dict):
        return raw
    return None


def _normalize_one(platform: str, value: str) -> str | None:
    text = (value or "").strip()
    if not text or len(text) > _MAX_URL_LEN:
        return None
    lower = text.lower()
    if any(lower.startswith(f"{scheme}:") for scheme in _INVALID_SCHEMES):
        return None

    if _looks_like_url(text, platform):
        return _normalize_url(platform, re.sub(r"\s", "%20", text))
    return _normalize_handle(platform, text)


def _looks_like_url(text: str, platform: str) -> bool:
    lower = text.lower().strip()
    if "://" in lower or lower.startswith("http:") or lower.startswith("https:"):
        return True
    if "/" in text:
        return True
    host = lower.split("/")[0].split("?")[0]
    if host.startswith("www."):
        host = host[4:]
    return host in _HOSTS.get(platform, frozenset()) or any(
        host.endswith(f".{allowed}") for allowed in _HOSTS.get(platform, frozenset())
    )


def _normalize_handle(platform: str, value: str) -> str | None:
    handle = " ".join(value.strip().lstrip("@").split())
    if not handle:
        return None
    if handle.lower().startswith("www."):
        return None
    pattern = _HANDLE_RE.get(platform)
    if not pattern or not pattern.match(handle):
        return None
    if platform == "facebook":
        if _FACEBOOK_VANITY_RE.match(handle):
            return _CANONICAL[platform].format(handle=handle)
        return _facebook_search_url(handle)
    return _CANONICAL[platform].format(handle=handle)


def _facebook_search_url(name: str) -> str:
    return f"https://www.facebook.com/search/pages/?q={quote_plus(name)}"


def _normalize_url(platform: str, value: str) -> str | None:
    text = value.strip()
    if text.startswith("//"):
        text = f"https:{text}"
    elif "://" not in text:
        text = f"https://{text}"

    try:
        parsed = urlparse(text)
    except Exception:
        return None

    scheme = (parsed.scheme or "").lower()
    if scheme in _INVALID_SCHEMES:
        return None
    if scheme not in {"http", "https"}:
        return None
    if parsed.username or parsed.password:
        return None

    host = (parsed.hostname or "").lower().strip()
    if not host or host not in _HOSTS.get(platform, frozenset()):
        return None
    if parsed.port not in (None, 80, 443):
        return None

    path = parsed.path or "/"
    query = parsed.query or ""
    if path in {"", "/"} and not query:
        return None

    if platform == "facebook":
        decoded = unquote(path)
        segments = [s for s in decoded.split("/") if s]
        if segments and " " in segments[0]:
            return _facebook_search_url(segments[0])

    rebuilt = urlunparse(("https", host, path, "", query, ""))
    if len(rebuilt) > _MAX_URL_LEN:
        return None
    return rebuilt
