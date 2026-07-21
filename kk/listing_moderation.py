"""
Listing publish policy (H-12).

Default: new listings go **active** immediately (marketplace stays populated).
Operators can force a pending queue with LISTING_REQUIRE_APPROVAL=1.
Light heuristics can still hold suspicious posts for admin review.
Post-publish trust uses the existing listing/user report queue.
"""

from __future__ import annotations

import os
import re

# Obvious spam / scam bait in free-text descriptions (EN + common short codes).
_SPAM_HINTS = re.compile(
    r"("
    r"guaranteed\s+profit|double\s+your\s+money|crypto\s+invest|"
    r"whatsapp\s*\+|t\.me/|bit\.ly/|free\s+money|"
    r"click\s+here\s+now|earn\s+\$\d+"
    r")",
    re.IGNORECASE,
)


def listing_require_approval() -> bool:
    """
    When true, every new listing starts as pending until an admin activates it.

    Unset / empty → False (auto-publish). Explicit 1/true/yes/on → True.
    """
    raw = (os.environ.get("LISTING_REQUIRE_APPROVAL") or "").strip().lower()
    if raw in ("1", "true", "yes", "on"):
        return True
    if raw in ("0", "false", "no", "off", ""):
        return False
    # Unknown value: fail closed to auto-publish only when clearly disabled;
    # treat unrecognized tokens as off to avoid accidental empty marketplace.
    return False


def listing_needs_manual_review(
    *,
    description: str | None,
    price: float | None,
    brand: str | None = None,
) -> bool:
    """Heuristic hold for admin queue even when auto-publish is the default."""
    text = (description or "").strip()
    if text and _SPAM_HINTS.search(text):
        return True
    try:
        p = float(price) if price is not None else None
    except (TypeError, ValueError):
        p = None
    # Near-zero prices are often spam or incomplete listings.
    if p is not None and 0 < p < 50:
        return True
    _ = brand  # reserved for future brand/price heuristics
    return False


def initial_listing_status(
    *,
    description: str | None = None,
    price: float | None = None,
    brand: str | None = None,
) -> str:
    """Server-controlled status for a newly created listing."""
    if listing_require_approval():
        return "pending"
    if listing_needs_manual_review(
        description=description, price=price, brand=brand
    ):
        return "pending"
    return "active"
