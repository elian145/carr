"""Deterministic moderation rules (pure functions, no I/O).

Input is a ``Facts`` snapshot assembled by the engine; output is a list of
``Signal`` objects plus a per-check status map. Nothing here touches the
database, the network or the clock (the current year is passed in), so every
rule is unit-testable in isolation.

Signal levels
-------------
``hold``    the listing cannot be judged yet (media still processing / failed,
            moderation service unavailable). -> decision HOLD
``review``  an administrator must look at it. -> decision NEEDS_REVIEW
``info``    recorded for the admin, never blocks approval.

``suspicious`` separates "something looks wrong" from "routine, just not
provable by rules" (brand-new seller, AI provider not configured). Only
suspicious signals page admins by default.

There is no reject level: automation never rejects.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Any

HOLD = "hold"
REVIEW = "review"
INFO = "info"


@dataclass
class Signal:
    code: str
    level: str  # hold | review | info
    check: str
    suspicious: bool = False
    detail: str | None = None  # short, non-PII (numbers / field names only)

    def to_dict(self) -> dict:
        return {
            "code": self.code,
            "level": self.level,
            "check": self.check,
            "suspicious": self.suspicious,
            "detail": self.detail,
        }


@dataclass
class Facts:
    subject_type: str  # listing | revision
    fields: dict[str, Any]
    media: dict[str, Any]
    seller: dict[str, Any]
    duplicates: dict[str, Any] = field(default_factory=dict)
    revision: dict[str, Any] | None = None


# ---------------------------------------------------------------------------
# Text patterns
# ---------------------------------------------------------------------------

# Obvious scam / prohibited content. Matches only ever route a listing to a
# human; nothing is auto-rejected on a pattern hit.
_SCAM = re.compile(
    r"("
    r"guaranteed\s+profit|double\s+your\s+money|crypto\s+invest|free\s+money|"
    r"click\s+here\s+now|earn\s+\$\d+|western\s*union|money\s*gram|"
    r"advance\s+(fee|payment)|gift\s*cards?|bitcoin|usdt|binance|"
    r"ربح\s*مضمون|ارباح\s*مضمونة|أرباح\s*مضمونة|مضاعفة\s*(اموالك|أموالك)|ويسترن\s*يونيون"
    r")",
    re.IGNORECASE,
)
_PROHIBITED = re.compile(
    r"\b(cocaine|heroin|marijuana|hashish|escort|casino|porn|xxx|viagra|"
    r"firearms?|rifles?|pistols?|ammunition|weapons?)\b",
    re.IGNORECASE,
)
_NON_CAR = re.compile(
    r"\b(iphone|laptop|apartment\s+for\s+(rent|sale)|job\s+vacancy|"
    r"loans?\s+available|visa\s+service)\b",
    re.IGNORECASE,
)
_URL = re.compile(
    r"(https?://|www\.|t\.me/|wa\.me/|bit\.ly/|\b[\w-]+\.(com|net|org|io|me|ly|info|biz)\b)",
    re.IGNORECASE,
)
_EMAIL = re.compile(r"[\w.+-]+@[\w-]+\.[\w.-]+")
_PHONE = re.compile(r"(?:\+?\d[\s().-]?){9,}")
_REPEAT_CHAR = re.compile(r"(.)\1{9,}")
_VIN = re.compile(r"^[A-HJ-NPR-Z0-9]{17}$")
_PLACEHOLDERS = {"", "unknown", "n/a", "na", "none", "null", "-", "--", "test", "asdf", "xxx"}

REQUIRED_TEXT_FIELDS = (
    "brand",
    "model",
    "location",
    "engine_type",
    "transmission",
    "drive_type",
    "condition",
    "body_type",
)


def _clean(v) -> str:
    return str(v if v is not None else "").strip()


def normalize_text(text: str | None) -> str:
    """Lowercased, whitespace/punctuation collapsed -- used for duplicate
    description comparison."""
    return re.sub(r"[\W_]+", " ", (text or "").lower()).strip()


def redact_for_provider(text: str | None) -> str:
    """Remove contact details before text is sent to an external provider."""
    t = text or ""
    t = _EMAIL.sub("[email]", t)
    t = _URL.sub("[link]", t)
    t = _PHONE.sub("[phone]", t)
    return t[:4000]


# ---------------------------------------------------------------------------
# Rule groups
# ---------------------------------------------------------------------------


def check_required_fields(f: Facts, s: dict) -> list[Signal]:
    out: list[Signal] = []
    for name in REQUIRED_TEXT_FIELDS:
        if _clean(f.fields.get(name)).lower() in _PLACEHOLDERS:
            out.append(Signal("missing_field", REVIEW, "required_fields", False, name))
    for name in ("year", "mileage", "price"):
        if f.fields.get(name) in (None, ""):
            out.append(Signal("missing_field", REVIEW, "required_fields", False, name))
    return out


def check_values(f: Facts, s: dict, current_year: int) -> list[Signal]:
    out: list[Signal] = []
    year = f.fields.get("year")
    mileage = f.fields.get("mileage")
    price = f.fields.get("price")
    currency = _clean(f.fields.get("currency")).upper() or "USD"
    condition = _clean(f.fields.get("condition")).lower()

    if isinstance(year, int):
        if year < int(s.get("min_year", 1950)) or year > current_year + 1:
            out.append(Signal("year_out_of_range", REVIEW, "values", True, str(year)))
        if condition == "new" and year < current_year - 1:
            out.append(Signal("new_but_old_year", REVIEW, "values", True, str(year)))
    if isinstance(mileage, int):
        if mileage < 0 or mileage > int(s.get("max_mileage", 1_000_000)):
            out.append(Signal("mileage_out_of_range", REVIEW, "values", True, str(mileage)))
        elif condition == "new" and mileage > 500:
            out.append(Signal("new_with_mileage", REVIEW, "values", True, str(mileage)))
        elif mileage == 0 and condition not in ("new", "") and isinstance(year, int) and year < current_year:
            # The create endpoint defaults a missing mileage to 0.
            out.append(Signal("used_zero_mileage", REVIEW, "values", False, None))
    if price is not None:
        try:
            p = float(price)
        except (TypeError, ValueError):
            p = None
        bounds = (s.get("currency_price_bounds") or {}).get(currency)
        if p is None or p <= 0:
            out.append(Signal("price_invalid", REVIEW, "values", True, None))
        elif not bounds:
            out.append(Signal("unknown_currency", REVIEW, "values", False, currency))
        elif p < float(bounds[0]) or p > float(bounds[1]):
            out.append(Signal("price_out_of_range", REVIEW, "values", True, f"{currency} {p:g}"))
    vin = _clean(f.fields.get("vin")).upper()
    if vin and not _VIN.match(vin):
        out.append(Signal("vin_invalid", REVIEW, "values", True, None))
    return out


def check_text(f: Facts, s: dict) -> list[Signal]:
    out: list[Signal] = []
    text = _clean(f.fields.get("description"))
    if not text:
        return out
    if _SCAM.search(text):
        out.append(Signal("scam_language", REVIEW, "text", True))
    if _PROHIBITED.search(text):
        out.append(Signal("prohibited_content", REVIEW, "text", True))
    if _NON_CAR.search(text):
        out.append(Signal("non_car_content", REVIEW, "text", True))
    if _REPEAT_CHAR.search(text):
        out.append(Signal("repeated_characters", REVIEW, "text", True))
    letters = [c for c in text if c.isalpha()]
    if len(letters) >= 30:
        upper = sum(1 for c in letters if c.isupper() and c.isascii())
        ascii_letters = sum(1 for c in letters if c.isascii())
        if ascii_letters >= 30 and upper / ascii_letters > 0.7:
            out.append(Signal("excessive_caps", REVIEW, "text", False))
    words = normalize_text(text).split()
    if len(words) >= 20:
        top = max((words.count(w) for w in set(words)), default=0)
        if top / len(words) > 0.3:
            out.append(Signal("repetitive_text", REVIEW, "text", True))
    if len(text) > 5000:
        out.append(Signal("description_too_long", REVIEW, "text", False))
    if s.get("flag_contact_in_description", True) and (
        _URL.search(text) or _EMAIL.search(text) or _PHONE.search(text)
    ):
        out.append(Signal("contact_in_description", REVIEW, "text", False))
    return out


def check_media(f: Facts, s: dict) -> list[Signal]:
    m = f.media
    out: list[Signal] = []
    in_flight = int(m.get("in_flight") or 0)
    failed = int(m.get("failed") or 0)
    media_status = m.get("media_status")
    if in_flight > 0 or media_status == "processing":
        out.append(Signal("media_processing", HOLD, "media", False, str(in_flight)))
    if failed > 0 or media_status == "failed":
        out.append(Signal("media_failed", HOLD, "media", False, str(failed)))
    if out:
        return out

    images = [i for i in m.get("images", []) if (i.get("kind") or "listing") != "damage"]
    all_images = m.get("images", [])
    min_photos = int(s.get("min_photos", 1))
    if len(images) < min_photos:
        out.append(Signal("too_few_photos", REVIEW, "media", False, f"{len(images)}<{min_photos}"))
    if any(not i.get("url") for i in all_images):
        out.append(Signal("media_missing", REVIEW, "media", True, "empty url"))
    if images:
        primaries = [i for i in images if i.get("is_primary")]
        if len(primaries) != 1:
            out.append(Signal("cover_invalid", REVIEW, "media", True, f"primaries={len(primaries)}"))
        # Declared cover (server-owned choice) must be the stored cover.
        by_source = {i.get("source_media_id"): i for i in all_images if i.get("source_media_id")}
        for it in m.get("items", []):
            if it.get("kind") != "image" or it.get("status") != "attached":
                continue
            img = by_source.get(it.get("client_media_id"))
            if img is None:
                out.append(Signal("media_missing", REVIEW, "media", True, "attached item without photo"))
                break
            if it.get("is_cover") and not img.get("is_primary"):
                out.append(Signal("cover_mismatch", REVIEW, "media", True, None))
                break
    min_side = int(s.get("min_image_side_px", 0))
    if min_side:
        for i in images:
            w, h = i.get("width"), i.get("height")
            if w and h and min(int(w), int(h)) < min_side:
                out.append(Signal("low_resolution", REVIEW, "media", False, f"{w}x{h}"))
                break
    return out


def check_duplicates(f: Facts, s: dict) -> list[Signal]:
    d = f.duplicates or {}
    out: list[Signal] = []
    if d.get("own_similar"):
        out.append(Signal("duplicate_listing", REVIEW, "duplicates", True, str(d["own_similar"])))
    if d.get("own_same_description"):
        out.append(Signal("repeated_description", REVIEW, "duplicates", True, str(d["own_same_description"])))
    if d.get("vin_own"):
        out.append(Signal("vin_reused_own", REVIEW, "duplicates", True, None))
    if d.get("vin_other_seller"):
        out.append(Signal("vin_other_seller", REVIEW, "duplicates", True, None))
    if int(d.get("recent_24h") or 0) > int(s.get("max_listings_per_24h", 5)):
        out.append(Signal("high_posting_rate", REVIEW, "duplicates", True, str(d.get("recent_24h"))))
    return out


def check_seller(f: Facts, s: dict) -> list[Signal]:
    sl = f.seller
    out: list[Signal] = []
    if not sl.get("exists"):
        return [Signal("seller_missing", REVIEW, "seller", True)]
    if not sl.get("active"):
        out.append(Signal("seller_inactive", REVIEW, "seller", True))
    if not sl.get("phone_verified"):
        out.append(Signal("seller_not_verified", REVIEW, "seller", False))
    if int(sl.get("open_reports") or 0) > 0:
        out.append(Signal("seller_open_reports", REVIEW, "seller", True, str(sl["open_reports"])))
    if int(sl.get("admin_rejections") or 0) > 0 or int(sl.get("hidden_listings") or 0) > 0:
        out.append(
            Signal(
                "seller_abuse_history",
                REVIEW,
                "seller",
                True,
                f"rejected={sl.get('admin_rejections', 0)} hidden={sl.get('hidden_listings', 0)}",
            )
        )
    trusted = (s.get("dealers_count_as_trusted", True) and sl.get("dealer_approved")) or (
        int(sl.get("prior_approved") or 0) >= int(s.get("min_seller_prior_approved", 1))
    )
    if not trusted:
        out.append(Signal("seller_unproven", REVIEW, "seller", False))
    if sl.get("manual_only"):
        out.append(Signal("pinned_manual_review", REVIEW, "seller", False))
    return out


def check_payment(f: Facts, s: dict) -> list[Signal]:
    if f.subject_type != "listing" or not s.get("listing_payment_required"):
        return []
    # There is no payment ledger in this codebase: payment can't be verified,
    # so it can never be assumed (fail safe -> a human decides).
    return [Signal("payment_unverifiable", REVIEW, "payment", False)]


def check_revision(f: Facts, s: dict) -> list[Signal]:
    r = f.revision
    if f.subject_type != "revision" or not r:
        return []
    out: list[Signal] = []
    changed = set(r.get("changed_fields") or [])
    if not changed and not r.get("new_media"):
        out.append(Signal("no_effective_changes", REVIEW, "revision", False))
    identity = changed & {"brand", "model", "year", "vin"}
    if identity:
        out.append(Signal("identity_changed", REVIEW, "revision", True, ",".join(sorted(identity))))
    old, new = r.get("old_price"), r.get("new_price")
    if old and new is not None and old > 0:
        pct = abs(new - old) / old * 100
        if pct > float(s.get("price_change_review_pct", 50)):
            out.append(Signal("large_price_change", REVIEW, "revision", True, f"{pct:.0f}%"))
    return out


def ai_signals(ai: dict | None, s: dict) -> list[Signal]:
    """Translate an advisory AI result into signals. AI is never proof of
    anything: a clean result only *fails to add a reason* to look closer, and
    an unavailable service is HOLD (never an approval)."""
    status = (ai or {}).get("status", "disabled")
    if status == "disabled":
        if s.get("require_ai_for_auto_approve", True):
            return [Signal("ai_not_configured", REVIEW, "ai", False)]
        return []
    if status == "unavailable":
        return [Signal("ai_unavailable", HOLD, "ai", False, (ai or {}).get("error"))]
    if status == "flagged":
        flags = sorted(set((ai or {}).get("text_flags", []) + (ai or {}).get("image_flags", [])))
        return [Signal("ai_flagged", REVIEW, "ai", True, ",".join(flags)[:120] or None)]
    if status == "uncertain":
        return [Signal("ai_uncertain", REVIEW, "ai", False, (ai or {}).get("error"))]
    conf = (ai or {}).get("confidence")
    if conf is not None and conf < float((s.get("ai") or {}).get("min_confidence", 0.7)):
        return [Signal("ai_low_confidence", REVIEW, "ai", False, f"{conf:.2f}")]
    return []


# ---------------------------------------------------------------------------
# Orchestration of the deterministic part
# ---------------------------------------------------------------------------

CHECK_NAMES = (
    "required_fields",
    "values",
    "text",
    "media",
    "duplicates",
    "seller",
    "payment",
    "revision",
    "ai",
)


def run_rules(f: Facts, s: dict, current_year: int) -> list[Signal]:
    signals: list[Signal] = []
    signals += check_required_fields(f, s)
    signals += check_values(f, s, current_year)
    signals += check_text(f, s)
    signals += check_media(f, s)
    signals += check_duplicates(f, s)
    signals += check_seller(f, s)
    signals += check_payment(f, s)
    signals += check_revision(f, s)
    return signals


def checks_map(signals: list[Signal], ran: tuple[str, ...] = CHECK_NAMES) -> dict[str, str]:
    """pass / fail / hold per check (a check that never ran is 'skipped')."""
    out = {name: "skipped" for name in CHECK_NAMES}
    for name in ran:
        out[name] = "pass"
    for sg in signals:
        if sg.level == HOLD:
            out[sg.check] = "hold"
        elif sg.level == REVIEW and out.get(sg.check) != "hold":
            out[sg.check] = "fail"
    return out


def decide(signals: list[Signal]) -> str:
    """HOLD beats NEEDS_REVIEW beats AUTO_APPROVE. AUTO_APPROVE only when no
    hold/review signal remains."""
    if any(sg.level == HOLD for sg in signals):
        return "HOLD"
    if any(sg.level == REVIEW for sg in signals):
        return "NEEDS_REVIEW"
    return "AUTO_APPROVE"
